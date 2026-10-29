import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def size (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut total := 0
    for entry in ← path.readDir do total := total+(← size entry.path)
    return total
  return metadata.byteSize.toNat
private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path
private partial def protect (path : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then protect entry.path targets
    else if metadata.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      unless targets.all (fun target => actual != target &&
          !actual.toString.startsWith (target.toString ++ "/")) do
        throw (IO.userError s!"retained interface still depends on {actual}")

def main (args : List String) : IO Unit := do
  let prior := args == ["prior-builds"]
  unless prior || args.isEmpty do throw (IO.userError "expected no arguments or prior-builds")
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/anchored-capture"
  let retirement := records / (if prior then "retired-builds.json" else "retired-data.json")
  unless !(← retirement.pathExists) do throw (IO.userError "keep prior retirement")
  let comparison ← read (records / "comparison.json")
  let audited ← read (records / "body-row-audit.json")
  unless comparison.getObjValD "sameFrozenEvidenceAndAlternatives" == toJson true &&
      audited.getObjValD "independentFileFingerprintsChecked" == toJson true do
    throw (IO.userError "seal actual delivery first")
  if !prior then
    unless (← IO.FS.readBinFile (records / "hook/body.txt")) ==
        (← IO.FS.readBinFile (root / "anchored-prepared-hook/body.txt")) do
      throw (IO.userError "delivery body changed before retirement")
  let guards := if prior then ["capture-native.guard.json","capture-saved.guard.json","correspondence-run.guard.json"]
    else ["capture-prepared-native.guard.json","anchored-hook.guard.json",
      "anchored-selection.guard.json","anchored-body-rows-2.guard.json"]
  for name in guards do
    let guard ← read (root / name)
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "wait for successful terminal guards")
  let targets := if prior then #[root / "capture-build",root / "correspondence-build"] else
    #[root / "anchored-prepared-hook",root / "prefix",root / "capture-prepared-build",
    root / "anchored-contracts-build",root / "anchored-hook-build",root / "anchored-selection-build",
    root / "anchored-capture/fixtures",root / "anchored-capture/saved-fixtures",
    root / "anchored-capture/prepared-fixtures",root / "anchored-capture/parent-runtime",
    root / "anchored-capture/patch-parent",root / "anchored-capture/current-originals.json"]
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 && targets.all (fun target =>
      (processes.stdout.splitOn target.toString).length == 1) do
    throw (IO.userError "ended target still owns a process")
  for name in (if prior then ["product-build","hook-build"] else
      ["product-build","hook-build","capture-build","correspondence-build"]) do
    protect (root / name / "lib") targets
    let response ← IO.FS.readFile (root / name / "runtime.rsp")
    unless targets.all (fun target => (response.splitOn target.toString).length == 1) do
      throw (IO.userError "retained native build depends on ended target")
  let mut retired := #[]
  let mut bytes := 0
  for path in targets do
    let count ← size path
    bytes := bytes+count
    retired := retired.push (path.toString,count)
  IO.FS.writeFile retirement (Json.mkObj [("targets",toJson retired),
    ("logicalBytes",toJson bytes),("archiveCreated",toJson false),
    ("seedAndCurrentRuntimeRetained",toJson true),("nativeDependenciesChecked",toJson true)]).pretty
  for path in targets do remove path
  IO.println s!"Deleted {targets.size} ended targets, {bytes} logical bytes; no archive"
