import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def installed : System.FilePath := "/Users/ovm/.local/share/eggshell/minilm"
private def numerical : System.FilePath :=
  "/Users/ovm/.codex/experiments/eggshell/numerical-owned-20261024/prefix/share/eggshell/minilm"
private def current : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"

private def run (command : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd := command,args}
  unless result.exitCode == 0 do throw (IO.userError s!"{command}: {result.stderr}")
  pure result.stdout

private partial def candidates (relative : System.FilePath) : IO (Array (System.FilePath × Nat)) := do
  let mut result := #[]
  for entry in ← (numerical / relative).readDir do
    let state ← entry.path.symlinkMetadata
    let name := relative / entry.fileName
    if state.type == .dir then result := result ++ (← candidates name)
    -- Small mutable readiness/config/cache files and symlinks stay separate.
    else if state.type == .file && state.byteSize.toNat ≥ 1024*1024 then
      let counterpart := installed / name
      unless (← counterpart.symlinkMetadata).type == .file do
        throw (IO.userError s!"installed counterpart is not a regular file: {name}")
      unless (← run "/usr/bin/stat" #["-f","%d:%p:%u:%g",entry.path.toString]) ==
          (← run "/usr/bin/stat" #["-f","%d:%p:%u:%g",counterpart.toString]) do
        throw (IO.userError s!"file ownership, mode or device differs: {name}")
      let same ← IO.Process.output {cmd := "/usr/bin/cmp",args := #["-s",entry.path.toString,counterpart.toString]}
      unless same.exitCode == 0 do throw (IO.userError s!"numerical file bytes differ: {name}")
      if (← run "/usr/bin/stat" #["-f","%d:%i",entry.path.toString]) !=
          (← run "/usr/bin/stat" #["-f","%d:%i",counterpart.toString]) then
        result := result.push (name,state.byteSize.toNat)
  pure result

def main : IO Unit := do
  let record := project / "docs/candidates/numerical-file-consolidation.json"
  unless !(← record.pathExists) do throw (IO.userError "consolidation already recorded")
  let selected ← candidates "."
  unless !selected.isEmpty do throw (IO.userError "no independently stored matching files")
  let binaryPaths := #[current / "product-build/StudyMain",current / "controller-build/StudyMain"]
  let files := binaryPaths ++ selected.flatMap (fun row => #[installed / row.1,numerical / row.1])
  let controller := "/Users/ovm/.codex/experiments/eggshell/study-services-20261026/assessed-controller"
  let digest : IO String := run controller (#["artifacts"] ++ files.map (·.toString))
  let before ← digest
  let spaceBefore ← run "/bin/df" #["-k",current.toString]
  for (relative,_) in selected do
    let target := numerical / relative
    let temporary := target.withExtension "eggshell-link-pending"
    unless !(← temporary.pathExists) do throw (IO.userError "unexpected pending link")
    IO.FS.hardLink (installed / relative) temporary
    IO.FS.rename temporary target
    unless (← run "/usr/bin/stat" #["-f","%d:%i",target.toString]) ==
        (← run "/usr/bin/stat" #["-f","%d:%i",(installed / relative).toString]) do
      throw (IO.userError "hard link was not installed")
  unless (← digest) == before do throw (IO.userError "file content or current runtime changed")
  IO.FS.writeFile record (Json.mkObj [
    ("consolidatedFiles",toJson (selected.map (fun row => (row.1.toString,row.2)))),
    ("duplicateLogicalBytes",toJson (selected.foldl (fun total row => total+row.2) 0)),
    ("spaceBefore",toJson spaceBefore),("spaceAfter",toJson (← run "/bin/df" #["-k",current.toString])),
    ("allDigestsBeforeAndAfter",← IO.ofExcept (Json.parse before)),
    ("contentsPathsOwnershipAndModesPreserved",toJson true),
    ("sourceDbOrDerivedIndexModified",toJson false),("numericalFileBytesChanged",toJson false),
    ("newModelCalls",toJson (0 : Nat)),
    ("archiveCreated",toJson false),("adoptedProductChange",toJson false)]).pretty
