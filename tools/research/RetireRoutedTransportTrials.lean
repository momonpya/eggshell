import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private partial def size (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    return if metadata.type == .file then metadata.byteSize.toNat else 0
  let mut total := 0
  for entry in ← path.readDir do total := total + (← size entry.path)
  return total

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

/-- Completed diagnostic executables and their retired provider target are
not experiment evidence. Preserve the original DBs and active link inputs. -/
def main (args : List String) : IO Unit := do
  let (selectors,destination) ← match args with
    | [destination] => pure (false,destination)
    | ["selectors",destination] => pure (true,destination)
    | _ => throw (IO.userError "RetireRoutedTransportTrials [selectors] NEW-REPORT")
  let output := System.FilePath.mk destination
  unless output.isAbsolute && !(← output.pathExists) do throw (IO.userError "unused report required")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "routed-transport-20261026"
  let data := base / "literal-support-20261026/required-replay/topic-1/data"
  let records := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/routed-transport/records"
  let guards := if selectors then #[
      root / "coverage-candidate/required-replay/topic-1/prepare.guard.json",
      base / "owner-unit-postings-20261026/collect.guard.json",
      base / "owner-unit-postings-20261026/required-replay/topic-1/prepare.guard.json",
      base / "owner-unit-postings-20261026/required-replay/topic-1/profile.guard.json",
      base / "owner-unit-postings-20261026/required-replay/topic-1/late.guard.json",
      base / "selector-preparation-20261026/collect.guard.json",
      base / "selector-preparation-20261026/required-replay/topic-1/prepare.guard.json"]
    else #[root / "directory.guard.json",root / "collect-fixed.guard.json",
      root / "runtime-candidate/required-replay/topic-1/prepare.guard.json",
      root / "runtime-candidate/required-replay/topic-1/profile.guard.json"]
  for path in guards do
    let record ← read path
    unless (record.getObjValAs? String "state").toOption == some "finished" &&
        (record.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
      throw (IO.userError "trial still owns processes")
  for relative in ["required-report.json","actual-trials.json","directory-report.json"] do
    unless ← (records / relative).pathExists do throw (IO.userError "evidence collection missing")
  if selectors then
    for label in ["owner-unit-postings","selector-preparation"] do
      let report := records.parent.get!.parent.get! / label / "records/required-report.json"
      unless ← report.pathExists do throw (IO.userError "selector evidence collection missing")
  let oldPrefix := root / "runtime-candidate/required-replay/prefix"
  let target := data / "index-targets/37777a7fdd6637f225d450e487985b027ae9b2783c26bedb87c3707e95436a95.json"
  let prefixes := #[root / "coverage-candidate/required-replay/prefix",
    base / "owner-unit-postings-20261026/required-replay/prefix",
    base / "selector-preparation-20261026/required-replay/prefix"]
  let mut targets := if selectors then prefixes ++ #[root / "coverage-candidate/build",
      base / "owner-unit-postings-20261026/build",base / "selector-preparation-20261026/build"]
    else #[root / "build",oldPrefix,root / "runtime-candidate/build",target]
  if selectors then
    for entry in ← (data / "index-targets").readDir do
      if !entry.fileName.endsWith ".json" then continue
      let command ← IO.ofExcept ((← read entry.path).getObjValAs? (Array String) "command")
      if prefixes.any (fun installation => command[0]? == some (installation / "libexec/eggshell").toString) then
        targets := targets.push entry.path
  else
    let command ← IO.ofExcept ((← read target).getObjValAs? (Array String) "command")
    unless command[0]? == some (oldPrefix / "libexec/eggshell").toString do
      throw (IO.userError "unexpected maintenance target")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect processes")
  let mut response ← IO.FS.readFile (root / "product-build/runtime.rsp")
  if selectors then
    for name in ["owner-unit-postings-20261026","selector-preparation-20261026"] do
      response := response ++ (← IO.FS.readFile (base / name / "product-build/runtime.rsp"))
  let mut rows := #[]
  let mut total := 0
  for path in targets do
    unless (processes.stdout.splitOn path.toString).length == 1 &&
        (response.splitOn path.toString).length == 1 do
      throw (IO.userError "target still has a process or link dependency")
    let bytes ← size path
    total := total + bytes
    rows := rows.push (Json.mkObj [("path",toJson path.toString),("logicalBytes",toJson bytes)])
  let result := Json.mkObj [("targets",toJson rows),("logicalBytes",toJson total),
    ("archiveCreated",toJson false),("followsSymlinks",toJson false),
    ("activeSourceAndRoutingDatabasesRetained",toJson true),("activeProductLinkInputsRetained",toJson true)]
  IO.FS.writeFile output result.pretty
  for path in targets do remove path
  for path in targets do
    if ← path.pathExists then throw (IO.userError "retired target survived")
  IO.FS.writeFile (.mk (destination ++ ".result.json"))
    (Json.mkObj [("removed",toJson targets.size),("logicalBytes",toJson total),("archiveCreated",toJson false)]).pretty
  IO.println result.compress
