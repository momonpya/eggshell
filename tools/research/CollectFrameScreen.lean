import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
private def docs : System.FilePath :=
  "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/compact-native-context"
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  let data ← IO.FS.readBinFile source
  IO.FS.writeBinFile target data
  unless (← IO.FS.readBinFile target) == data do throw (IO.userError "record copy differs")
private partial def copyTree (source target : System.FilePath) : IO Unit := do
  match (← source.symlinkMetadata).type with
  | .dir =>
      IO.FS.createDirAll target
      for entry in ← source.readDir do copyTree entry.path (target / entry.fileName)
  | .file => copy source target
  | _ => throw (IO.userError "only plain receipt files may be captured")
private partial def erase (path : System.FilePath) : IO (Nat × Nat) := do
  let state ← path.symlinkMetadata
  if state.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let next ← erase entry.path
      total := (total.1+next.1,total.2+next.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if state.type == .file then state.byteSize.toNat else 0)

def main (args : List String) : IO Unit := do
  let [arm] := args | throw (IO.userError "baseline | compact")
  unless ["baseline","compact"].contains arm do throw (IO.userError "unknown fixed arm")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 do throw (IO.userError processes.stderr)
  let mut deleted := #[]
  let mut results := #[]
  for topic in [1,2,3] do
    let label := s!"frame-{arm}-{topic}"
    let trial := root / label
    let target := docs / arm / s!"topic-{topic}"
    unless !(← target.pathExists) do throw (IO.userError "preserve captured study records")
    unless (processes.stdout.splitOn trial.toString).length == 1 do
      throw (IO.userError "trial process still uses its runtime")
    let guard ← read (root / (label ++ ".guard.json"))
    unless guard.getObjValD "state" == toJson "finished" &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "trial guard is not terminal")
    let result ← read (trial / "result.json")
    unless result.getObjValD "topic" == toJson topic &&
        result.getObjValD "modelCalls" == toJson (0 : Nat) do
      throw (IO.userError "incorrect trial result")
    for file in ["result.json","audit.json","body.txt","changed-views.json","frozen-before-delivery.json",
        "audit-input.json","handoff-trace.txt","shutdown.json","publisher-shutdown.json"] do
      copy (trial / file) (target / file)
    copyTree (trial / "hook") (target / "hook")
    copyTree (trial / "data/receipts") (target / "receipts")
    IO.FS.writeFile (target / "guard.json") guard.pretty
    results := results.push result
    deleted := deleted.push (trial.toString,← erase trial)
  IO.FS.writeFile (docs / arm / "summary.json") (Json.mkObj [
    ("results",toJson results),("deletedTrialFiles",toJson deleted),
    ("archiveCreated",toJson false),("newSeedStudy",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
