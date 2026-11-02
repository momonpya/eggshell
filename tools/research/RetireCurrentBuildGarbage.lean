import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashSet

open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)
private def sha (path : String) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path]}
  check (result.exitCode == 0) "cannot inspect protected input"
  return (result.stdout.splitOn " ").headD ""

private partial def mark (path : System.FilePath) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  if !(← path.pathExists) then return
  let actual ← IO.FS.realPath path
  if (← seen.get).contains actual.toString then return
  seen.modify (·.insert actual.toString)
  if (← actual.metadata).type == .dir then
    for entry in ← actual.readDir do mark entry.path seen

private partial def generated (directory : System.FilePath) : IO (Array System.FilePath) := do
  let mut found := #[]
  for entry in ← directory.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then found := found ++ (← generated entry.path)
    else if metadata.type == .file && [".o",".source",".dependencies",".olean",".olean.private",
        ".olean.server",".ir",".ilean",".c",".stdout",".stderr"].any (fun suffix => entry.fileName.endsWith suffix) then
      found := found.push entry.path
  return found

private partial def retireCopy (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes + (← retireCopy entry.path)
    IO.FS.removeDir path
    return bytes
  check (metadata.type == .file) "ended snapshot contains a non-regular file"
  IO.FS.removeFile path
  return metadata.byteSize.toNat

def main (args : List String) : IO Unit := do
  check (args.isEmpty || args == ["duplicate-snapshots"] || args == ["ended-cache"] ||
    args == ["ended-source"] || args == ["ended-recommendations"]) "unexpected retirement mode"
  let duplicates := args == ["duplicate-snapshots"]
  let endedCache := args == ["ended-cache"]
  let endedSource := args == ["ended-source"]
  let endedRecommendations := args == ["ended-recommendations"]
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := base / "fixed-frame-study"
  let output := project / "docs/candidates/delivery-ack" /
    (if duplicates then "duplicate-snapshot-retirement.json" else if endedCache then
      "ended-cache-retirement.json" else if endedSource then "ended-source-retirement.json" else
      if endedRecommendations then "ended-recommendations-retirement.json" else "unreachable-build-retirement.json")
  check (!(← output.pathExists)) "preserve the retirement record"
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0 && (processes.stdout.splitOn "StudyBuildMain.lean").length == 1)
    "wait for the active native build"
  let protection ← read (project / "docs/candidates/delivery-ack/obsolete-runtime-retirement.json")
  let protectedInputs : Array (String × String) ← IO.ofExcept (protection.getObjValAs? _ "currentProtectedInputs")
  let sealedInputs : Array Json ← IO.ofExcept ((← read (project / "docs/candidates/frozen-post/manifest.json")).getObjValAs? _ "sealedInputs")
  let verify := do
    for (path,digest) in protectedInputs do check ((← sha path) == digest) "protected input changed"
    for artifact in sealedInputs do
      let path ← IO.ofExcept (artifact.getObjValAs? String "path")
      check (toJson (← sha path) == artifact.getObjValD "sha256") "sealed input changed"
  verify
  if endedRecommendations then
    let original := root / "study/seed-1/work.egg"
    let identity ← IO.ofExcept ((← read (original / "head")).getObjValAs? String "identity")
    let page := original / (identity ++ ".pages")
    let digest ← sha page.toString
    let target := original / "derived" / identity / "synapses/recommendations"
    let headDigest ← sha (target / "head").toString
    let bytes ← retireCopy target
    check ((← sha page.toString) == digest) "seed1 source changed during ended-cache retirement"
    verify
    IO.FS.writeFile output (Json.mkObj [("retired",toJson (target.toString,bytes,headDigest)),
      ("seed1HistoricalIndexNoLongerAvailable",toJson true),
      ("retainedOriginal",toJson (page.toString,digest)),("seed2ReplayInputsExcluded",toJson true),
      ("protectedInputsUnchanged",toJson true),("archiveCreated",toJson false)]).pretty
    IO.println "Retired ended seed1 recommendation cache; original, private journal and seed2 replay inputs retained."
    return
  if endedSource then
    let target := base / "study/seed-2/work.egg"
    let identity ← IO.ofExcept ((← read (target / "head")).getObjValAs? String "identity")
    let digest ← sha (target / (identity ++ ".pages")).toString
    let headDigest ← sha (target / "head").toString
    for entry in ← root.readDir do
      if entry.fileName.endsWith ".plan.json" || entry.fileName.endsWith ".settings.json" then
        check (((← IO.FS.readFile entry.path).splitOn (toJson target.toString).compress).length == 1)
          "current experiment still selects the ended source"
    let bytes ← retireCopy target
    verify
    IO.FS.writeFile output (Json.mkObj [("retired",toJson (target.toString,bytes,headDigest,digest)),
      ("protectedInputsUnchanged",toJson true),("currentFixedFrameSeedsExcluded",toJson true),
      ("archiveCreated",toJson false)]).pretty
    IO.println "Retired the ended pre-fixed-frame seed DB; current protected snapshots retained."
    return
  if endedCache then
    let original := base / "study/seed-2/work.egg"
    let identity ← IO.ofExcept ((← read (original / "head")).getObjValAs? String "identity")
    let page := original / (identity ++ ".pages")
    let digest ← sha page.toString
    let target := original / "derived"
    let bytes ← retireCopy target
    check ((← sha page.toString) == digest) "ended source changed during cache retirement"
    verify
    IO.FS.writeFile output (Json.mkObj [("retired",toJson (target.toString,bytes)),
      ("retainedOriginal",toJson (page.toString,digest)),("protectedInputsUnchanged",toJson true),
      ("archiveCreated",toJson false)]).pretty
    IO.println "Retired the ended pre-fixed-frame seed's derived cache; source bytes retained."
    return
  if duplicates then
    let original := root / "study/seed-1/work.egg"
    let identity ← IO.ofExcept ((← read (original / "head")).getObjValAs? String "identity")
    let filename := identity ++ ".pages"
    let digest ← sha (original / filename).toString
    let mut retired := #[]
    for relative in ["seed-1-ready-continued/ready.egg","seed-1-initial-history/source.egg"] do
      let target := root / relative
      check ((← sha (target / filename).toString) == digest) "ended snapshot differs from retained original"
      let headDigest ← sha (target / "head").toString
      let bytes ← retireCopy target
      retired := retired.push (target.toString,bytes,headDigest,digest)
    check ((← sha (original / filename).toString) == digest) "retained original changed"
    verify
    IO.FS.writeFile output (Json.mkObj [("retired",toJson retired),
      ("retainedOriginal",toJson (original.toString,digest)),("protectedInputsUnchanged",toJson true),
      ("archiveCreated",toJson false)]).pretty
    IO.println "Retired two ended snapshot copies; the byte-identical original remains."
    return
  let settings ← read (root / "delivery-ack-shared-build.settings.json")
  let parents : Array String ← IO.ofExcept (settings.getObjValAs? _ "parents")
  let active := parents.push (root / "delivery-ack-build").toString
  let seen ← IO.mkRef ({} : Std.HashSet String)
  for directory in active do
    mark (.mk directory) seen
    let response := System.FilePath.mk directory / "runtime.rsp"
    if ← response.pathExists then
      for row in (← IO.FS.readFile response).splitOn "\n" do
        if row.trimAscii.isEmpty then continue
        let path ← IO.ofExcept (Json.parse row >>= Json.getStr?)
        if !(path.endsWith ".o") then continue
        let path := System.FilePath.mk path
        mark path seen
        mark (path.withExtension "source") seen
        mark (path.withExtension "dependencies") seen
  for entry in ← root.readDir do
    if (← entry.path.symlinkMetadata).type == .dir && (entry.fileName == "core" || entry.fileName.endsWith "-core") then
      mark (entry.path / ".lake/build/lib") seen
  mark (project / ".lake/build/lib") seen
  mark (.mk "/Users/ovm/Code/eggshell/.lake/build/lib") seen
  let kept := ← seen.get
  let mut candidates := #[]
  for parent in [base,base / "shared-snapshot",root] do
    for entry in ← parent.readDir do
      if (← entry.path.symlinkMetadata).type == .dir && (← (entry.path / "build.json").pathExists) then
        candidates := candidates ++ (← generated entry.path)
  let mut removed := #[]
  let mut bytes := 0
  for path in candidates do
    if kept.contains (← IO.FS.realPath path).toString then continue
    let size := (← path.metadata).byteSize
    removed := removed.push (path.toString,size,← sha path.toString)
    bytes := bytes+size.toNat
    IO.FS.removeFile path
  verify
  IO.FS.writeFile output (Json.mkObj [("removed",toJson removed),("logicalBytesRemoved",toJson bytes),
    ("currentLinkObjectsInterfacesAndStampsRetained",toJson true),
    ("protectedInputsUnchanged",toJson true),("sourceAndDbFilesExcluded",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println s!"Retired {removed.size} unreachable generated files ({bytes} logical bytes); active build inputs retained."
