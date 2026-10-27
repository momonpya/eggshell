import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "selector-input-20261027"
  let trial := root / "capture-actual-selector-input"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let reference := project / "docs/candidates/range-postings/final/hook"
  let output := project / "docs/candidates/selector-input/capture"
  unless !(← output.pathExists) && !(← (root / "selector-input.json").pathExists) do
    throw (IO.userError "preserve earlier selector input")
  let guard ← read (root / "capture-actual-selector-input.guard.json")
  unless guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      guard.getObjValD "exitCode" == toJson (0 : Nat) do
    throw (IO.userError "selector capture did not terminate successfully")
  let actual ← read (trial / "result.json")
  unless actual.getObjValD "actualHook" == toJson false && actual.getObjValD "diagnosticOnly" == toJson true do
    throw (IO.userError "selector capture must remain a worker diagnostic")
  unless (← IO.FS.readBinFile (trial / "body.txt")) == (← IO.FS.readBinFile (reference / "body.txt")) do
    throw (IO.userError "diagnostic capture changed actual rendered bytes")
  unless (← read (trial / "audit.json")).getObjValD "frozenEvidence" ==
      (← read (reference / "audit.json")).getObjValD "frozenEvidence" do
    throw (IO.userError "capture changed the frozen evidence")
  let mut captured : Array (String × Json) := #[]
  for entry in ← (trial / "data/receipts").readDir do
    let path := entry.path / "selection-plan.json"
    if !(← path.pathExists) then continue
    let plan := (← read path).getObjValD "data"
    let input := plan.getObjValD "selectorInput"
    unless input == Json.null do captured := captured.push (path.toString,input)
  let [(receipt,input)] := captured.toList | throw (IO.userError "exactly one native selector input required")
  IO.FS.writeFile (root / "selector-input.json") input.compress
  IO.FS.createDirAll output
  IO.FS.writeFile (output / "input.json") input.compress
  for file in ["result.json","changed-views.json","audit.json","handoff-trace.txt","shutdown.json","publisher-shutdown.json"] do
    IO.FS.writeBinFile (output / file) (← IO.FS.readBinFile (trial / file))
  IO.FS.writeFile (output / "guard.json") guard.pretty
  let hashes ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts",(root / "selector-input.json").toString,(root / "product-build/StudyMain").toString,
      (root / "controller-build/StudyMain").toString,(root / "replay-build/StudyMain").toString]}
  unless hashes.exitCode == 0 do throw (IO.userError hashes.stderr)
  let digests ← IO.ofExcept (Json.parse hashes.stdout >>= Json.getArr?)
  unless digests[1]!.getObjValD "sha256" == actual.getObjValD "runtimeSha256" do
    throw (IO.userError "captured runtime differs from executed product")
  IO.FS.writeFile (output / "digests.json") hashes.stdout
  IO.FS.writeFile (output / "origin.json") (Json.mkObj [
    ("nativeReceipt",toJson receipt),("sameBodyAsParent",toJson true),("sameFrozenEvidence",toJson true),
    ("actualHookLatencyAcceptance",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("newSeedStudy",toJson false),("adopted",toJson false)]).pretty
