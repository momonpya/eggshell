import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def main (args : List String) : IO Unit := do
  let [trial,label] := args | throw (IO.userError "ended trial and collected evidence label required")
  unless [trial,label].all (fun text => !text.isEmpty && text.toList.all (fun c => c.isAlphanum || c == '-')) do
    throw (IO.userError "simple labels required")
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/rendered-marginal-cost-20261027"
  let output := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/rendered-marginal-cost" / label
  let target := root / trial
  unless !(← (output / "retirement.json").pathExists) do throw (IO.userError "preserve retirement record")
  let guard ← read (root / (trial ++ ".guard.json"))
  unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "trial still owns a process")
  unless (← read (target / "result.json")) == (← read (output / "hook/result.json")) &&
      (← IO.FS.readBinFile (target / "body.txt")) == (← IO.FS.readBinFile (output / "hook/body.txt")) do
    throw (IO.userError "capture the ended trial before deletion")
  unless !(← (target / "work.egg").pathExists) do throw (IO.userError "the retained prepared checkpoint must not be here")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  let response ← IO.FS.readFile (root / "product-build/runtime.rsp")
  unless processes.exitCode == 0 && (processes.stdout.splitOn target.toString).length == 1 &&
      (response.splitOn target.toString).length == 1 do throw (IO.userError "trial is still referenced")
  IO.FS.writeFile (output / "retirement.json") (Json.mkObj [
    ("target",toJson target.toString),("terminalGuard",guard),("capturedBeforeDeletion",toJson true),
    ("retainedPreparedCheckpointUnchanged",toJson true),("archiveCreated",toJson false)]).pretty
  remove target
  IO.println "Deleted ended run/cache/runtime copy without an archive"
