import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def size (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .file then return (1,metadata.byteSize.toNat)
  if metadata.type != .dir then return (0,0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let next ← size entry.path
    total := (total.1+next.1,total.2+next.2)
  return total
private def protect (study : System.FilePath) : IO String := do
  let files := #[study / "r0/stage1/history/source.egg/head",
    study / "r0/stage1/history/source.egg/d6ff6dad444913158edfc86f2a3bd24212835619ec78e5d4da0e3afe1789a812.pages",
    study / "shared-snapshot/query-cache-baseline-build/StudyMain",
    study / "shared-snapshot/prepared-bindings-build/StudyMain",
    study / "shared-snapshot/register-runtime-build/StudyMain"]
  let hashed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"] ++ files.map (·.toString)}
  check (hashed.exitCode == 0) "cannot verify protected originals and runtimes"
  return hashed.stdout
def main : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/joint-relevance"
  check (!(← (records / "retired.json").pathExists)) "already retired"
  let assessment ← read (records / "assessment.json")
  check ((← IO.ofExcept ((assessment.getObjValD "reports").getArr?)).size == 3) "assessment incomplete"
  for kind in ["build","export","score","assess"] do
    let guard ← read (records / (kind ++ ".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "experiment still active"
  check ((← read (records / "native-closure.json")).getObjValD "consistent" == toJson true) "native inputs not sealed"
  let active ← IO.Process.output {cmd := "/usr/bin/pgrep",args := #["-f",
    "^/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot/joint-relevance-build/StudyMain( |$)"]}
  check (active.exitCode == 1) "experiment process may still be live"
  let before ← protect study
  let mut removed := (0,0)
  for name in ["joint-relevance-build","joint-relevance-data"] do
    let owned := root / name
    check ((← IO.FS.realPath owned) == owned) "owned experiment crossed a symlink"
    let counts ← size owned
    removed := (removed.1+counts.1,removed.2+counts.2)
    IO.FS.removeDirAll owned
  let mut settings := 0
  for name in ["joint-relevance-build.settings.json","joint-relevance-build.guard.settings.json",
      "joint-relevance-export.guard.settings.json","joint-relevance-score.guard.settings.json",
      "joint-relevance-assess.guard.settings.json","joint-relevance-setup.guard.settings.json",
      "joint-relevance-retire.guard.settings.json"] do
    let path := root / name
    if ← path.pathExists then
      IO.FS.removeFile path
      settings := settings+1
  let after ← protect study
  check (before == after) "cleanup changed protected originals or runtimes"
  IO.FS.writeFile (records / "protected-before.txt") before
  IO.FS.writeFile (records / "protected-after.txt") after
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("regularFiles",toJson removed.1),
    ("logicalBytes",toJson removed.2),("removedSettings",toJson settings),
    ("protectedHashesEqual",toJson true),("modelAndRawScoresRemoved",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println s!"Retired joint-relevance study: {removed.1} files, {removed.2} logical bytes"
