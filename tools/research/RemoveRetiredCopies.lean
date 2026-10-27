import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell"
private def active : System.FilePath := base / "verified-winner-20261027"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"

private def readJson (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def within (root path : System.FilePath) : Bool :=
  path == root || path.toString.startsWith (root.toString ++ "/")

/-- Materialize a current dependency, checking its bytes before retiring its old
location. This is the live workspace, not a backup or archive. -/
private def copyExact (source target : System.FilePath) : IO Unit := do
  let bytes ← IO.FS.readBinFile source
  IO.FS.createDirAll target.parent.get!
  let temporary := target.withExtension "cleanup-pending"
  unless !(← temporary.pathExists) do throw (IO.userError "unexpected pending copy")
  IO.FS.writeBinFile temporary bytes
  unless (← IO.FS.readBinFile temporary) == bytes do
    throw (IO.userError s!"copy differs: {target}")
  IO.FS.rename temporary target

private partial def ownDependencies (path : System.FilePath) : IO Nat := do
  let kind := (← path.symlinkMetadata).type
  if kind == .symlink then
    if !(← path.pathExists) then
      if path.toString.endsWith "/Eggshell/Storage/sync.c" then
        copyExact (project / "Eggshell/Storage/sync.c") path
        return 0
      if path.toString.endsWith ".lean" then
        throw (IO.userError s!"missing Lean dependency: {path}")
      IO.FS.removeFile path
      return 1
    let actual ← IO.FS.realPath path
    if within active actual then return 0
    unless (← actual.metadata).type == .file do
      throw (IO.userError s!"unexpected external directory dependency: {path}")
    copyExact actual path
    return 0
  else if kind == .dir then
    let mut count := 0
    for entry in ← path.readDir do count := count + (← ownDependencies entry.path)
    return count
  else return 0

private partial def retain (path : System.FilePath) (kept : IO.Ref (Std.HashSet String)) : IO Unit := do
  if (← kept.get).contains path.toString then return
  let kind := (← path.symlinkMetadata).type
  kept.modify (·.insert path.toString)
  if kind == .symlink then retain (← IO.FS.realPath path) kept
  else if kind == .dir then
    for entry in ← path.readDir do retain entry.path kept

private partial def obsolete (path : System.FilePath) (kept : Std.HashSet String)
    (out : IO.Ref (Array (System.FilePath × Nat))) : IO Unit := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    for entry in ← path.readDir do obsolete entry.path kept out
  else if !kept.contains path.toString then
    out.modify (·.push (path,if metadata.type == .file then metadata.byteSize.toNat else 0))

private partial def removeEmpty (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type != .dir then return
  for entry in ← path.readDir do removeEmpty entry.path
  if (← path.readDir).isEmpty then IO.FS.removeDir path

private def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  pure result.stdout

def main (args : List String) : IO Unit := do
  let report := project / "docs/candidates/cleanup-current.json"
  if args == ["verify"] then
    let mut count := 0
    for line in (← IO.FS.readFile (active / "product-build/runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let value ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      if value.endsWith ".o" || value.endsWith ".a" then
        unless within active (.mk value) && (← (System.FilePath.mk value).pathExists) do
          throw (IO.userError s!"unresolved native dependency: {value}")
        count := count + 1
    let smoke := active / "product-build/RelocatedSmoke"
    unless ← smoke.pathExists do throw (IO.userError "successful relink required")
    IO.FS.removeFile smoke
    let result := (← readJson report)
      |>.setObjVal! "nativeDependenciesChecked" (toJson count)
      |>.setObjVal! "consolidatedRelinkSucceeded" (toJson true)
      |>.setObjVal! "relinkSmokeExecutableRemoved" (toJson true)
      |>.setObjVal! "nativeArchive" (toJson (active / "product-build/inherited_libstorage_sync.a").toString)
    IO.FS.writeFile report result.pretty
    IO.println s!"Verified all {count} current native dependencies; removed the temporary relink executable."
    return
  unless args.isEmpty do throw (IO.userError "no arguments | verify")
  unless !(← report.pathExists) do throw (IO.userError "cleanup already recorded")
  let ps ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless ps.exitCode == 0 && (ps.stdout.splitOn base.toString).length == 1 do
    throw (IO.userError "an experiment process is still running")
  unless (← readJson (active / "verified-native-comparison/result.json")).getObjValD "allPassed" == toJson true do
    throw (IO.userError "current native comparison is not complete")
  let binary := active / "product-build/StudyMain"
  let before ← digest binary
  let dangling := (← ownDependencies (active / "checkout")) +
    (← ownDependencies (active / "product-build/lib"))
  let objects ← IO.ofExcept ((← readJson (active / "objects.json")).getObj?)
  let mut relocated := #[]
  let mut arguments : Array String := #[]
  let mut mapping : Array (String × Json) := #[]
  for line in (← IO.FS.readFile (active / "product-build/runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let original ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    if !original.endsWith ".o" && !original.endsWith ".a" then
      arguments := arguments.push original
      continue
    let path := System.FilePath.mk original
    let moduleJson := objects[original]?.getD (toJson ("__native__." ++ path.fileStem.get!))
    let moduleName ← IO.ofExcept moduleJson.getStr?
    let target := if within active path then path else
      active / "product-build" / ("inherited_" ++ moduleName.replace "." "_" ++
        (if original.endsWith ".a" then ".a" else ".o"))
    if target != path then
      if ← target.pathExists then
        unless (← IO.FS.readBinFile target) == (← IO.FS.readBinFile path) do
          throw (IO.userError s!"object destination differs: {target}")
      copyExact path target
      for suffix in ["source","dependencies"] do
        let provenance := path.withExtension suffix
        if ← provenance.pathExists then copyExact provenance (target.withExtension suffix)
      relocated := relocated.push (original,target.toString)
    arguments := arguments.push target.toString
    mapping := mapping.push (target.toString,moduleJson)
  IO.FS.writeFile (active / "product-build/runtime.rsp")
    ("\n".intercalate (arguments.toList.map (fun s => (toJson s).compress)) ++ "\n")
  IO.FS.writeFile (active / "objects.json") (Json.mkObj mapping.toList).pretty
  let mut build ← readJson (active / "product-build/build.json")
  let settings := (build.getObjValD "settings")
    |>.setObjVal! "baselineResponse" (toJson (active / "product-build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (active / "product-build/Main.o").toString)
    |>.setObjVal! "baselineCore" (toJson (active / "checkout").toString)
    |>.setObjVal! "parents" (toJson (#[] : Array String))
  build := build.setObjVal! "settings" settings
  IO.FS.writeFile (active / "product-build/build.json") build.pretty
  IO.FS.rename (base / "selector-input-20261027/selector-input.json") (active / "selector-input.json")
  let prepared := base / "packet-delivery-ledger-20261027/one-prepared-hook"
  IO.FS.rename (base / "literal-support-20261026/required-replay/topic-1/data/read-cache") (prepared / "read-cache")
  let kept ← IO.mkRef ({} : Std.HashSet String)
  for entry in ← active.readDir do
    if !["audit-build","interfaces"].contains entry.fileName then retain entry.path kept
  let study := base / "study-services-20261026"
  for path in #[prepared,study,base / "numerical-owned-20261024"] do retain path kept
  let retained ← kept.get
  let sizes ← retained.toArray.filterMapM fun name => do
    let metadata ← (System.FilePath.mk name).symlinkMetadata
    pure (if metadata.type == .file then some (name,metadata.byteSize.toNat) else none)
  let selected ← IO.mkRef #[]
  obsolete base retained selected
  -- Old demo output and interpreter caches are generated data, not source or
  -- actual user memories. Do not follow their links into other projects.
  let extra : Array System.FilePath := #[
    "/Users/ovm/Code/eggshell/.private/product-hunt-demo",
    "/Users/ovm/Code/eggshell/tests/__pycache__",
    "/Users/ovm/Code/eggshell/adapters/__pycache__",
    "/Users/ovm/Code/eggshell/scripts/__pycache__",
    "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/preparation/__pycache__",
    project / ".lake/build"]
  for path in extra do
    if ← path.pathExists then obsolete path retained selected
  let targets ← selected.get
  let bytes := targets.foldl (fun total row => total+row.2) 0
  IO.println s!"Deleting {targets.size} unused files ({bytes} logical bytes)."
  for (path,_) in targets do IO.FS.removeFile path
  for entry in ← base.readDir do removeEmpty entry.path
  for path in extra do if ← path.pathExists then removeEmpty path
  for (name,size) in sizes do
    unless (← (System.FilePath.mk name).metadata).byteSize.toNat == size do
      throw (IO.userError s!"retained file changed: {name}")
  unless (← digest binary) == before do throw (IO.userError "current executable changed")
  let help ← IO.Process.output {cmd := binary.toString,args := #["--help"]}
  unless help.exitCode == 0 && help.stdout.startsWith "usage:" do throw (IO.userError "current executable no longer starts")
  IO.FS.writeFile report (Json.mkObj [
    ("deletedFileCount",toJson targets.size),("deletedLogicalBytes",toJson bytes),
    ("removedDanglingLinks",toJson dangling),
    ("currentDependencyRelocations",toJson relocated),
    ("retainedFileChecks",toJson sizes.size),("currentExecutableSHA256",toJson before),
    ("currentExecutableStarts",toJson true),("retainedDatabases",toJson #[
      (study / "common-seed-1/source.egg").toString,(prepared / "work.egg").toString]),
    ("archiveCreated",toJson false)]).pretty
  IO.println "Cleanup complete. Only current dependencies and the two active DBs remain."
