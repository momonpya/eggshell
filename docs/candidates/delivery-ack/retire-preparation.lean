import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap

open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)
private def sha (path : String) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path]}
  check (result.exitCode == 0) "cannot check protected input"
  return (result.stdout.splitOn " ").headD ""

private partial def retire (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← retire entry.path)
    IO.FS.removeDir path
    return bytes
  check (metadata.type == .file) "cache contains a symlink or special file; stop"
  IO.FS.removeFile path
  return metadata.byteSize.toNat

/-- Preserve both captured paths and every byte while sharing identical
APFS extents. This is a Mac experiment cleanup, not a DB storage premise. -/
private def cloneTwin (original duplicate : System.FilePath) : IO (Option (String × String)) := do
  if !(← duplicate.pathExists) then return none
  check ((← original.symlinkMetadata).type == .file && (← duplicate.symlinkMetadata).type == .file)
    "snapshot copy is not a regular file"
  let digest ← sha original.toString
  if (← sha duplicate.toString) != digest then return none
  let temporary := System.FilePath.mk (duplicate.toString ++ ".pending")
  check (!(← temporary.pathExists)) "snapshot clone temporary already exists"
  let result ← IO.Process.output {cmd := "/bin/cp",args := #["-cp",original.toString,temporary.toString]}
  check (result.exitCode == 0) "cannot clone identical APFS snapshot"
  let copied := temporary
  check ((← sha copied.toString) == digest && (← sha original.toString) == digest)
    "captured source changed during independent cloning"
  IO.FS.rename copied duplicate
  return some (duplicate.toString,digest)

private partial def compiledFiles (directory : System.FilePath) : IO (Array System.FilePath) := do
  let mut found := #[]
  for entry in ← directory.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then found := found ++ (← compiledFiles entry.path)
    else if metadata.type == .file && [".o",".olean",".olean.private",".olean.server",".ir",".ilean"].any
        (fun suffix => entry.fileName.endsWith suffix) then found := found.push entry.path
  return found

private def shareBuildPages (currentOnly : Bool := false) : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let output := project / "docs/candidates/delivery-ack" /
    (if currentOnly then "current-build-page-sharing.json" else "build-page-sharing.json")
  check (!(← output.pathExists)) "preserve build sharing evidence"
  let live ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (live.exitCode == 0 && (live.stdout.splitOn "StudyBuildMain.lean").length == 1)
    "wait for the native build"
  let mut files := #[]
  if currentOnly then files := ← compiledFiles (base / "fixed-frame-study/delivery-ack-build")
  else
    for parent in [base,base / "shared-snapshot",base / "fixed-frame-study"] do
      for entry in ← parent.readDir do
        if (← entry.path.symlinkMetadata).type != .dir || !(← (entry.path / "build.json").pathExists) then continue
        files := files ++ (← compiledFiles entry.path)
  let mut groups : Std.HashMap (String × Nat) (Std.HashMap String System.FilePath) := {}
  if currentOnly then
    let reference ← read (project / "docs/candidates/delivery-ack/build-page-sharing.json")
    let recorded : Array (String × Nat × String) ← IO.ofExcept (reference.getObjValAs? _ "files")
    for (path,bytes,digest) in recorded do
      let group := ((System.FilePath.mk path).fileName.get!,bytes)
      groups := groups.insert group (groups[group]?.getD {} |>.insert digest (.mk path))
  let mut changed := #[]
  let mut logicalBytes := 0
  for path in files.qsort (fun a b => a.toString < b.toString) do
    let bytes := (← path.metadata).byteSize.toNat
    let group := (path.fileName.get!,bytes)
    let digest ← sha path.toString
    let previous := groups[group]?.getD {}
    if let some representative := previous[digest]? then
      let some copied ← cloneTwin representative path | throw (IO.userError "identical build changed during sharing")
      changed := changed.push (copied.1,bytes,copied.2)
      logicalBytes := logicalBytes+bytes
      if changed.size % 64 == 0 then IO.println s!"Shared {changed.size} byte-identical build files."
    else groups := groups.insert group (previous.insert digest path)
  IO.FS.writeFile output (Json.mkObj [("files",toJson changed),("count",toJson changed.size),
    ("logicalBytesShared",toJson logicalBytes),("allFileBytesUnchanged",toJson true),
    ("runtimesSourcesAndDbFilesExcluded",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println s!"Independently cloned {changed.size} identical compiled files; no byte or pathname changed."

private def retirePluginCheckout : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let path := root / "account/.tmp/plugins"
  let output := project / "docs/candidates/delivery-ack/plugin-checkout-cleanup.json"
  check (!(← output.pathExists)) "preserve plugin checkout cleanup evidence"
  let manifest ← read (project / "docs/candidates/frozen-post/manifest.json")
  let inputs : Array Json ← IO.ofExcept (manifest.getObjValAs? _ "sealedInputs")
  for input in inputs do
    let file ← IO.ofExcept (input.getObjValAs? String "path")
    check (!(file.startsWith (path.toString ++ "/"))) "temporary checkout is a sealed dependency"
    check (toJson (← sha file) == input.getObjValD "sha256") "sealed input changed"
  let bytes ← if ← path.pathExists then retire path else pure 0
  for input in inputs do
    let file ← IO.ofExcept (input.getObjValAs? String "path")
    check (toJson (← sha file) == input.getObjValD "sha256") "sealed input changed after retirement"
  IO.FS.writeFile output (Json.mkObj [("path",toJson path.toString),("logicalBytesRemoved",toJson bytes),
    ("installedPluginsRuntimeConfigurationAndSealedInputsUnchanged",toJson true),
    ("newHarnessMustBeSealedBeforeModelCalls",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println s!"Retired {bytes} bytes of temporary plugin checkout; installed plugins and sealed inputs unchanged."

private def shareRuntimeCopies : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let output := project / "docs/candidates/delivery-ack/runtime-page-sharing.json"
  check (!(← output.pathExists)) "preserve runtime sharing evidence"
  let live ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (live.exitCode == 0 && !(live.stdout.splitOn "\n").any (fun line =>
    line.startsWith (root / "prefix/libexec/eggshell").toString ||
    line.startsWith (root / "control-prefix/libexec/eggshell").toString)) "runtime is live"
  let inputs : Array Json ← IO.ofExcept ((← read (project / "docs/candidates/frozen-post/manifest.json")).getObjValAs? _ "sealedInputs")
  let verify := do
    for input in inputs do
      let path ← IO.ofExcept (input.getObjValAs? String "path")
      check (toJson (← sha path) == input.getObjValD "sha256") "sealed runtime bytes changed"
  verify
  let mut copied := #[]
  for (build,installed) in [("fixed-frame-price-runtime-build","prefix"),("transport-profile-runtime-build","control-prefix")] do
    let original := root.parent.get! / "shared-snapshot" / build / "StudyMain"
    let target := root / installed / "libexec/eggshell"
    let some record ← cloneTwin original target | throw (IO.userError "runtime copy differs from its sealed binary")
    copied := copied.push record
  verify
  IO.FS.writeFile output (Json.mkObj [("independentApfsClones",toJson copied),
    ("allSealedInputBytesAndRuntimePathsUnchanged",toJson true),("controllerExcluded",toJson true),
    ("archiveCreated",toJson false)]).pretty
  IO.println "Shared byte-identical installed runtime copies; all sealed hashes and paths unchanged."

private def retireObsoleteRuntimes : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let output := project / "docs/candidates/delivery-ack/obsolete-runtime-retirement.json"
  check (!(← output.pathExists)) "preserve obsolete-runtime retirement evidence"
  let old ← read (project / "docs/candidates/frozen-post/manifest.json")
  let protectedInputs : Array (String × String) ← IO.ofExcept (old.getObjValAs? _ "protectedOriginals")
  let sealedInputs : Array Json ← IO.ofExcept (old.getObjValAs? _ "sealedInputs")
  let targets := ["query-cache-baseline-build","prepared-bindings-build"].map fun (name : String) =>
    root.parent.get! / "shared-snapshot" / name / "StudyMain"
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".plan.json" || entry.fileName.endsWith ".settings.json" then
      let raw ← IO.FS.readFile entry.path
      for path in targets do
        check ((raw.splitOn (toJson path.toString).compress).length == 1)
          "an experiment plan still selects an obsolete runtime"
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0) "cannot inspect runtime liveness"
  for path in targets do
    check (!(processes.stdout.splitOn "\n").any (·.startsWith path.toString)) "old runtime is still live"
  let verifySealed := do
    for artifact in sealedInputs do
      let path ← IO.ofExcept (artifact.getObjValAs? String "path")
      check (toJson (← sha path) == artifact.getObjValD "sha256") "current sealed input changed"
  verifySealed
  for (path,digest) in protectedInputs do check ((← sha path) == digest) "old protection record differs"
  let mut current := protectedInputs.filter fun (path,_) => !(targets.any (·.toString == path))
  for (build,installed) in [("fixed-frame-price-runtime-build","prefix"),("transport-profile-runtime-build","control-prefix")] do
    let path := root.parent.get! / "shared-snapshot" / build / "StudyMain"
    let digest ← sha path.toString
    check ((← sha (root / installed / "libexec/eggshell").toString) == digest) "matched runtime differs"
    current := current.push (path.toString,digest)
  let mut removed := #[]
  for path in targets do
    check ((← path.symlinkMetadata).type == .file) "obsolete runtime is not a regular file"
    removed := removed.push (path.toString,← sha path.toString,(← path.metadata).byteSize)
    IO.FS.removeFile path
  for (path,digest) in current do check ((← sha path) == digest) "current protected input changed"
  verifySealed
  IO.FS.writeFile output (Json.mkObj [("retired",toJson removed),("currentProtectedInputs",toJson current),
    ("originalSnapshotsAndCurrentMatchedRuntimeHashesUnchanged",toJson true),
    ("oldObjectsInterfacesAndInputStampsRetained",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println "Retired two obsolete diagnostic runtimes; current matched runtimes and original snapshots unchanged."

def main (args : List String) : IO Unit := do
  if args == ["share-build-pages"] then return ← shareBuildPages
  if args == ["share-current-build"] then return ← shareBuildPages true
  if args == ["retire-plugin-checkout"] then return ← retirePluginCheckout
  if args == ["share-runtime-copies"] then return ← shareRuntimeCopies
  if args == ["retire-obsolete-runtimes"] then return ← retireObsoleteRuntimes
  check args.isEmpty "expected no arguments, share-build-pages or share-current-build"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let output := project / "docs/candidates/delivery-ack/capacity-cleanup.json"
  check (!(← output.pathExists)) "preserve the existing cleanup record"
  let manifest ← read (project / "docs/candidates/frozen-post/manifest.json")
  let originals : Array (String × String) ← IO.ofExcept (manifest.getObjValAs? _ "protectedOriginals")
  let sealedInputs : Array Json ← IO.ofExcept (manifest.getObjValAs? _ "sealedInputs")
  let verify := do
    for (path,digest) in originals do check ((← sha path) == digest) "protected original changed"
    for artifact in sealedInputs do
      let path ← IO.ofExcept (artifact.getObjValAs? String "path")
      check (toJson (← sha path) == artifact.getObjValD "sha256") "sealed input changed"
  verify
  let live ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (live.exitCode == 0 && !(live.stdout.splitOn "\n").any (fun line =>
    line.startsWith (root / "prefix/libexec/eggshell").toString ||
    line.startsWith "./controller/StudyMain guard delivery-ack")) "wait for the active experiment"
  let mut targets := #[]
  let mut total := 0
  let mut cloned := #[]
  for acquisition in ["seed-1","seed-2-isolated"] do
    let source := root / "study" / acquisition / "work.egg"
    let identity ← IO.ofExcept ((← read (source / "head")).getObjValAs? String "identity")
    check (identity.length == 64 && identity.toList.all (fun c =>
      ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))) "invalid source identity"
    if let some copied ← cloneTwin (source / (identity ++ ".pages"))
        (root / "study" / acquisition / "output.egg" / (identity ++ ".pages")) then
      cloned := cloned.push copied
    -- Invalidate readiness first; incomplete retirement cannot look warm.
    for family in ["indexes","lexical","semantic"] do
      let path := source / "derived" / identity / family
      if !(← path.pathExists) then continue
      let bytes ← retire path
      total := total+bytes
      targets := targets.push (path.toString,bytes)
  verify
  IO.FS.writeFile output (Json.mkObj [("targets",toJson targets),("logicalBytesRemoved",toJson total),
    ("identicalOutputSnapshotsReplacedByIndependentApfsClones",toJson cloned),
    ("protectedOriginalsAndSealedInputsUnchanged",toJson true),("capturedSynapticHistoryPreserved",toJson true),
    ("reWarmRequiredBeforeAnyModelComparison",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println s!"Retired {total} bytes of rebuildable preparation; original snapshots and captured synaptic history unchanged."
