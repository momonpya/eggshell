import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashSet

open Lean

private partial def targets (path : System.FilePath) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  if !(← path.pathExists) then return
  let actual ← IO.FS.realPath path
  if (← seen.get).contains actual.toString then return
  seen.modify (·.insert actual.toString)
  if ← actual.isDir then
    for entry in ← actual.readDir do targets entry.path seen

private partial def leaves (path : System.FilePath) : IO (Array System.FilePath) := do
  let mut result := #[]
  if !(← path.pathExists) then return result
  for entry in ← path.readDir do
    let kind := (← entry.path.symlinkMetadata).type
    if kind == .dir then result := result ++ (← leaves entry.path)
    else if kind == .file then result := result.push entry.path
  return result

private def free (root : System.FilePath) : IO String := do
  let output ← IO.Process.output {cmd := "/bin/df",args := #["-Pk",root.toString]}
  unless output.exitCode == 0 do throw (IO.userError "cannot inspect research free space")
  return output.stdout

/-- Trace real interface targets and actual link inputs before removing only
unreferenced, regular interface files of superseded research objects. No
symlink, object, source stamp, database or active library target is removed. -/
def main (args : List String) : IO Unit := do
  let objects := args == ["objects"]
  unless args.isEmpty || objects do throw (IO.userError "[objects]")
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "fixed-frame-study"
  let builds := study / "shared-snapshot"
  let report := root / (if objects then "replay-cursor-object-cleanup.json" else "replay-cursor-interface-cleanup.json")
  unless !(← report.pathExists) do throw (IO.userError "interface cleanup already recorded")
  let live ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless live.exitCode == 0 && (live.stdout.splitOn "StudyBuildMain.lean").length == 1 do
    throw (IO.userError "a native builder is active")
  let protectedTargets ← IO.mkRef ({} : Std.HashSet String)
  let own := ["core/.lake/build/lib/lean","read-catalog-core/.lake/build/lib/lean",
    "read-preparation-core/.lake/build/lib/lean","controller/lib","read-catalog-build/lib",
    "replay-cursor-build/lib","replay-preparation-checks-build/lib"]
  for path in own do targets (root / path) protectedTargets
  targets (study / "controller-build/lib") protectedTargets
  let kept := ["fixed-frame-price-runtime-build","transport-profile-runtime-build",
    "query-cache-baseline-build","prepared-bindings-build"]
  for directory in kept do targets (builds / directory / "lib") protectedTargets
  targets (builds / "query-cache-baseline-core/.lake/build/lib/lean") protectedTargets
  let mut linked : Std.HashSet String := {}
  for directory in [root / "controller",root / "read-catalog-build",root / "replay-cursor-build",root / "replay-preparation-checks-build",
      study / "controller-build"] ++ kept.map (fun name => builds / System.FilePath.mk name) do
    let path := directory / "runtime.rsp"
    if !(← path.pathExists) then continue
    for line in (← IO.FS.readFile path).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      linked := linked.insert (← IO.ofExcept (Json.parse line >>= Json.getStr?))
  let protectedFiles ← protectedTargets.get
  let mut plan : Array (System.FilePath × UInt64) := #[]
  for directory in ← builds.readDir do
    if kept.contains directory.fileName || !directory.fileName.endsWith "-build" then continue
    if (← directory.path.symlinkMetadata).type != .dir then continue
    let library := directory.path / "lib"
    if objects then
      let mut interfaces : Std.HashSet String := {}
      for path in ← leaves library do
        if !path.toString.endsWith ".olean" then continue
        let relative := ((path.toString.drop (library.toString.length+1)).copy.dropEnd 6).copy
        interfaces := interfaces.insert (relative.replace "/" "_")
      for entry in ← directory.path.readDir do
        if !entry.fileName.endsWith ".o" || (← entry.path.symlinkMetadata).type != .file ||
            linked.contains entry.path.toString || interfaces.contains (entry.fileName.dropEnd 2).copy then continue
        let source := entry.path.withExtension "source"
        let dependencies := entry.path.withExtension "dependencies"
        if !(← source.pathExists) || !(← dependencies.pathExists) then continue
        for path in [entry.path,source,dependencies] do
          if protectedFiles.contains (← IO.FS.realPath path).toString then
            throw (IO.userError "an unlinked object is still an active interface target")
          plan := plan.push (path,(← path.metadata).byteSize)
      continue
    for path in ← leaves library do
      if protectedFiles.contains (← IO.FS.realPath path).toString then continue
      let relative := ((path.toString.drop (library.toString.length+1)).copy)
      let parts := relative.splitOn ".olean"
      let name := if parts.length == 2 then parts.head! else
        if relative.endsWith ".ilean" then (relative.dropEnd 6).copy else
        if relative.endsWith ".ir" then (relative.dropEnd 3).copy else ""
      if name.isEmpty then continue
      let object := directory.path / (name.replace "/" "_" ++ ".o")
      if !(← object.pathExists) || linked.contains object.toString then continue
      plan := plan.push (path,(← path.metadata).byteSize)
  let before ← free root
  let bytes := plan.foldl (fun total row => total+row.2) (0 : UInt64)
  let receipt := Json.mkObj [("count",toJson plan.size),("logicalBytes",toJson bytes),
    ("protectedRealTargets",toJson protectedFiles.size),("activeObjectInputs",toJson linked.size),
    ("files",toJson (plan.map fun (path,size) => (path.toString,size))),
    ("beforeFreeSpace",toJson before),("objectsSourcesDatabasesAndSymlinksUnchanged",toJson (!objects)),
    ("onlyUnlinkedObjectsWithoutLiveInterfaces",toJson objects),
    ("archiveCreated",toJson false)]
  IO.FS.writeFile report (receipt.setObjVal! "completed" (toJson false)).pretty
  for (path,_) in plan do IO.FS.removeFile path
  for path in protectedFiles do
    unless ← System.FilePath.pathExists path do throw (IO.userError "a required interface disappeared")
  IO.FS.writeFile report (receipt.setObjVal! "completed" (toJson true) |>.setObjVal! "afterFreeSpace" (toJson (← free root))).pretty
  IO.println s!"Deleted {plan.size} unreferenced old interface files ({bytes} logical bytes)."
