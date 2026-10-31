import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  ensure (result.exitCode == 0) "cannot verify protected source/runtime"
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
  let records := project / "docs/candidates/checked-original"
  ensure (!(← (records / "retired-staging.json").pathExists)) "preserve previous staging cleanup"
  let result ← read (records / "negative-result.json")
  ensure (result.getObjValD "sourceUnchanged" == toJson true &&
    (result.getObjValD "mixed").getObjValD "sameCompleteProjection" == toJson true) "mixed regression did not finish"
  for name in ["run.guard.json","negative-realpath.guard.json","negative-coherent.guard.json"] do
    let record ← read (records / name)
    ensure (record.getObjValD "state" == toJson "finished" &&
      record.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "related job still active"
  let targets := #[root / "prepared-owner-core",root / "prepared-owner-build",
    root / "checked-original-hook-baseline-build",root / "checked-original-hook-candidate-build",
    root / "checked-original-hook-trial/baseline",
    root / "checked-original-builder-interface-fixture",root / "checked-original-builder-interface-sequenced-fixture",
    root / "checked-original-builder-interface-scoped-fixture",root / "checked-original-builder-interface-identity-fixture"]
  let retained := #[root / "query-cache-baseline-build",root / "prepared-bindings-build",root / "register-runtime-build",
    root / "checked-original-runtime-build",root / "checked-original-negative-audit-build"]
  for directory in retained do
    let response ← IO.FS.readFile (directory / "runtime.rsp")
    for target in targets do ensure ((response.splitOn target.toString).length == 1) "retained build uses staging input"
  let originals : Array (String × String) ← IO.ofExcept
    ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in originals do ensure ((← hash (.mk path)) == expected) "protected original/runtime changed"
  let sourceId ← IO.ofExcept ((result.getObjValD "source").getObjValAs? String "identity")
  IO.FS.writeFile (records / "mixed-source-manifest.json")
    (← IO.FS.readFile (root / "checked-original-hook-trial/candidate/work.egg/derived" /
      sourceId / "canonical-source/manifest.json"))
  let mut total := (0,0)
  for target in targets do
    let counts ← remove target
    total := (total.1+counts.1,total.2+counts.2)
  let mut removedSettings := 0
  for entry in ← root.readDir do
    if (entry.fileName.startsWith "checked-original-" && entry.fileName.endsWith ".guard.settings.json") ||
        entry.fileName == "prepared-owner-build.settings.json" then
      IO.FS.removeFile entry.path
      removedSettings := removedSettings+1
  for (path,expected) in originals do ensure ((← hash (.mk path)) == expected) "cleanup changed protected original/runtime"
  let mut inputs := 0
  for directory in retained do
    for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      ensure (← path.pathExists) "cleanup lost retained native input"
      inputs := inputs+1
  IO.FS.writeFile (records / "retired-staging.json") (Json.mkObj [
    ("files",toJson total.1),("logicalBytes",toJson total.2),("removedSettings",toJson removedSettings),
    ("retainedNativeLinkInputs",toJson inputs),("protectedHashesBeforeAndAfter",toJson true),
    ("activeCandidateDatabaseKeptForFixedHookVerification",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println s!"Removed ended staging: {total.1} files, {total.2} logical bytes"
