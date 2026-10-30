import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def report := project / "docs/candidates/prepared-bindings/retired-historical-duplicates.json"
private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def same (left right : System.FilePath) : IO Bool := do
  if !(← left.pathExists) || !(← right.pathExists) then return false
  let a ← read (left / "head")
  let b ← read (right / "head")
  if a != b then return false
  let identity ← IO.ofExcept (a.getObjValAs? String "identity")
  check (identity.length == 64 && identity.toList.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')))
    "invalid copied DB incarnation"
  let size ← IO.ofExcept (a.getObjValAs? Nat "bytes")
  check (size ≤ 128*1024*1024) "inspect a larger DB with a streaming verifier"
  let first ← IO.FS.readBinFile (left / (identity ++ ".pages"))
  let second ← IO.FS.readBinFile (right / (identity ++ ".pages"))
  check (size ≤ first.size && size ≤ second.size) "truncated historical DB copy"
  return first.extract 0 size == second.extract 0 size

def main (args : List String) : IO Unit := do
  check (args.isEmpty && !(← report.pathExists)) "fresh explicit duplicate retirement only"
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0 && (processes.stdout.splitOn "StudyBuildMain.lean").length == 1)
    "finish native builds before removing their temporary output"
  let current := study / "r0/stage1/history/source.egg"
  let completed := study / "r0/stage2/history/source.egg"
  let mut candidates := #[(study / "study/seed-2/output.egg",current),
    (study / "r0/stage1/trial/output.egg",completed),(study / "r0/stage1/trial/input.egg",current)]
  for label in ["trial-prethread-remote-failure","trial-prethread-remote-state-failure","trial-preturn-publisher-failure"] do
    for name in ["input.egg","output.egg"] do
      candidates := candidates.push (study / "r0/stage1" / label / name,current)
  let mut approved := #[]
  let mut skipped := #[]
  for (path,retained) in candidates do
    if !(← same path retained) then skipped := skipped.push path; continue
    let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t","+D",path.toString]}
    check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty &&
      (processes.stdout.splitOn path.toString).length == 1) "a historical copy is still active"
    approved := approved.push (path,retained)
  let temporary := study / "shared-snapshot/source-lexical-query-hook-build/StudyMain.tmpc156860"
  let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t",temporary.toString]}
  check ((← temporary.symlinkMetadata).type == .file && opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty &&
    (processes.stdout.splitOn temporary.toString).length == 1) "an orphan linker output is still in use"
  let result := Json.mkObj [("exactCommittedHeadAndPrefixDuplicates",toJson approved),
    ("nonidenticalOrMissingCopiesRetained",toJson skipped),("orphanLinkerOutput",toJson temporary),
    ("currentSourceAndPostModelSourceRetained",toJson #[current,completed]),
    ("rawRpcUsageAnswersJournalsAndModelsRetained",toJson true),("archiveCreated",toJson false)]
  IO.FS.writeFile report (result.setObjVal! "completed" (toJson false)).pretty
  for (path,_) in approved do IO.FS.removeDirAll path
  IO.FS.removeFile temporary
  IO.FS.writeFile report (result.setObjVal! "completed" (toJson true)).pretty
  IO.println s!"Deleted {approved.size} byte-identical committed DB copies and one orphan linker output"
