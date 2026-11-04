import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/literal-boundaries"
partial def erase (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← erase entry.path)
    IO.FS.removeDir path
    return bytes
  IO.FS.removeFile path
  return metadata.byteSize.toNat
def main : IO Unit := do
  unless !(← (output/"cleanup.json").pathExists) do throw (IO.userError "preserve cleanup receipt")
  let mut recording := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "literal-boundaries-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "literal-boundaries-cleanup" then
      let guard ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      if entry.fileName.startsWith "literal-boundaries-records" then
        let log := base/(entry.fileName.replace ".guard.json" ".log")
        recording := recording.push (entry.fileName,guard,← IO.FS.readFile log)
  for name in ["word-only.json","word-only.patch","identity.json","candidate.patch","grammar-tests.patch",
      "probe.json","guards.json","failed-attempts.json","logs.json","laws.txt","contract-audit.txt","grammar.txt",
      "summary.json","native-reports.json","native-trials.json","native-stages.json","original-heads.json"] do
    unless ← (output/name).pathExists do throw (IO.userError "compact evidence is incomplete")
  IO.FS.writeFile (output/"recording-guards.json") ((toJson recording).compress++"\n")
  let mut removed := #[]
  for name in ["literal-boundaries-fixture-baseline1","literal-boundaries-fixture-candidate1",
      "literal-boundaries-fixture-audit1","literal-boundaries-fixture-literal-boundaries-probe2",
      "literal-boundaries-fixture-literal-boundaries-readback1","literal-boundaries-fixture-literal-boundaries-readback2",
      "literal-boundaries-grammar-build"] do
    let path := base/name
    if ← path.pathExists then removed := removed.push (path.toString,← erase path)
  for entry in ← base.readDir do
    if entry.fileName.startsWith "literal-boundaries-" && !entry.fileName.startsWith "literal-boundaries-cleanup" &&
        (entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard-settings.json") then
      removed := removed.push (entry.path.toString,← erase entry.path)
  let receipt := Json.mkObj [("removed",toJson removed),
    ("apparentBytes",toJson (removed.foldl (fun n item => n+item.2) 0)),("archivesCreated",toJson false),
    ("activeDiagnostic",toJson "frontend-quiescence-fixture-small1"),("activeRuntime",toJson "literal-boundaries-build/StudyMain"),
    ("neededComparisonAndBuildInputsRetained",toJson true)]
  IO.FS.writeFile (output/"cleanup.json") (receipt.pretty++"\n")
  IO.println (receipt.getObjValD "apparentBytes").compress
