import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot verify retained artifact"
  return (result.stdout.splitOn " ").headD ""
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let counts ← remove entry.path
    total := (total.1+counts.1,total.2+counts.2)
  IO.FS.removeDir path
  return total

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/work-requirements"
  check (!(← (records / "retired.json").pathExists)) "preserve previous cleanup"
  let result ← read (records / "audit-erased/result.json")
  check (result.getObjValD "sourceUnchanged" == toJson true && result.getObjValD "adopted" == toJson false &&
    result.getObjValD "answeringModelCalls" == toJson (0 : Nat)) "readonly experiment did not finish"
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".guard.json" && !entry.fileName.startsWith "retire" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "related process still active"
  check ((← read (records / "native-closure-erased.json")).getObjValD "consistent" == toJson true)
    "native inputs were not validated"
  let mut originals : Array (String × String) ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  originals := originals.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected source/runtime changed"
  let build := root / "work-requirements-build"
  let running ← IO.Process.output {cmd := "/usr/bin/pgrep",args := #["-f","^" ++ build.toString ++ "/StudyMain( |$)"]}
  check (running.exitCode == 1) "audit executable remains active"
  let builds := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build"]
  for retained in builds do
    check (((← IO.FS.readFile (retained / "runtime.rsp")).splitOn build.toString).length == 1)
      "retained runtime uses experiment inputs"
  let artifactSeals := Json.mkObj [("auditExecutableSha256",toJson (← hash (build / "StudyMain"))),
    ("componentSha256",toJson (← hash (project / "tools/research/WorkEvidenceRequirements.lean"))),
    ("auditSourceSha256",toJson (← hash (project / "tools/research/WorkEvidenceRequirementsAudit.lean")))]
  let counts ← remove build
  let mut settings := 0
  for entry in ← root.readDir do
    if entry.fileName.startsWith "work-requirements-" && entry.fileName.endsWith ".json" then
      IO.FS.removeFile entry.path
      settings := settings+1
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "cleanup changed protected source/runtime"
  let mut links := 0
  for retained in builds do
    for line in (← IO.FS.readFile (retained / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      check (← path.pathExists) "cleanup lost a retained native input"
      links := links+1
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("files",toJson counts.1),("logicalBytes",toJson counts.2),
    ("removedSettings",toJson settings),("seals",artifactSeals),("protectedHashesBeforeAndAfter",toJson true),
    ("retainedNativeLinkInputs",toJson links),("archiveCreated",toJson false)]).pretty
  IO.println s!"Removed completed dependency audit: {counts.1} files, {counts.2} logical bytes"
