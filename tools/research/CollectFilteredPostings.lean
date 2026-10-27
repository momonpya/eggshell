import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  IO.FS.writeBinFile target (← IO.FS.readBinFile source)

def main (args : List String) : IO Unit := do
  let [trial] := args | throw (IO.userError "terminal trial label required")
  unless !trial.isEmpty && trial.toList.all (fun c => c.isAlphanum || c == '-') do
    throw (IO.userError "simple trial label required")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "filtered-postings-20261027"
  let parent := base / "shared-original-structure-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/filtered-postings"
  unless !(← output.pathExists) do throw (IO.userError "preserve prior filtered posting evidence")
  let guard ← read (root / (trial ++ ".guard.json"))
  unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "hook still owns a process")
  let source := root / "checkout/tools/OwnerUnitPostings.lean"
  let stem := root / "product-build/tools_OwnerUnitPostings"
  let stamp := System.FilePath.mk (stem.toString ++ ".source")
  let native ← read stamp
  let stampFields ← IO.ofExcept native.getArr?
  unless stampFields[0]!.getStr?.toOption == some (← IO.FS.readFile source) do
    throw (IO.userError "runtime source stamp changed")
  let checks ← read (root / "checked-postings/result.json")
  unless checks.getObjValD "allPassed" == toJson true do throw (IO.userError "native posting checks failed")
  let dependencies ← IO.ofExcept (fromJson? (α := Array (String × String))
    (← read (root / "audit-build/tools_research_FilteredPostingsChecks.dependencies")))
  let some (_,checkedStamp) := dependencies.find? (·.1 == "tools.OwnerUnitPostings") |
    throw (IO.userError "native checks did not import the changed postings")
  unless checkedStamp == (← IO.FS.readFile stamp) do throw (IO.userError "native checks used another source")
  unless (← IO.FS.readFile (root / "checkout/Eggshell/Handoff.lean")) ==
      (← IO.FS.readFile (parent / "checkout/Eggshell/Handoff.lean")) do
    throw (IO.userError "the isolated posting optimization changed Handoff source")
  IO.FS.createDirAll output
  copy source (output / "contracts/OwnerUnitPostings.lean")
  copy stamp (output / "contracts/OwnerUnitPostings.source")
  copy (root / "audit-build/tools_research_FilteredPostingsChecks.source") (output / "checks/source.stamp")
  copy (root / "audit-build/tools_research_FilteredPostingsChecks-lean.stdout") (output / "checks/axioms.txt")
  copy (root / "checked-postings/result.json") (output / "checks/result.json")
  copy (root / "checked-postings.guard.json") (output / "checks/guard.json")
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/tools/OwnerUnitPostings.lean",
    "-L","b/tools/OwnerUnitPostings.lean",(parent / "checkout/tools/OwnerUnitPostings.lean").toString,source.toString]}
  unless diff.exitCode == 1 do throw (IO.userError "expected the isolated posting change")
  IO.FS.writeFile (output / "core.patch") diff.stdout
  let hashed ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts",(root / "product-build/StudyMain").toString,stamp.toString,
      (System.FilePath.mk (stem.toString ++ ".o")).toString,(root / "audit-build/StudyMain").toString]}
  unless hashed.exitCode == 0 do throw (IO.userError hashed.stderr)
  let hashes ← IO.ofExcept (Json.parse hashed.stdout >>= Json.getArr?)
  let actual ← read (root / trial / "result.json")
  unless hashes[0]!.getObjValD "sha256" == actual.getObjValD "runtimeSha256" do
    throw (IO.userError "executed runtime differs from collected runtime")
  IO.FS.writeFile (output / "native-input-digests.json") hashed.stdout
  for file in ["result.json","audit.json","body.txt","changed-views.json","frozen-before-delivery.json",
      "audit-input.json","handoff-trace.txt","shutdown.json","publisher-shutdown.json"] do
    copy (root / trial / file) (output / "hook" / file)
  for file in ["record.json","stdin","stdout","stderr"] do
    copy (root / trial / "hook" / file) (output / "hook/hook" / file)
  let mut selected := Json.null
  let mut domain := Json.null
  for entry in ← (root / trial / "data/receipts").readDir do
    if !(← entry.path.isDir) then continue
    for file in ["search.json","delivery-domain.json","selection-plan.json","synaptic-delivery.json"] do
      if !(← (entry.path / file).pathExists) then continue
      copy (entry.path / file) (output / "receipt-stages" / entry.fileName / file)
      if file == "selection-plan.json" then selected := (← read (entry.path / file)).getObjValD "data"
      if file == "delivery-domain.json" then domain := (← read (entry.path / file)).getObjValD "data"
  let old := project / "docs/candidates/shared-original-structure/final"
  let oldStages := old / "receipt-stages/5fb9c697fb0410a7d4e3c92a3ca86c8c5a7737b415acdd8e3a32a394145d3bb1"
  IO.FS.writeFile (output / "comparison.json") (Json.mkObj [
    ("sameBodyBytes",toJson ((← IO.FS.readBinFile (root / trial / "body.txt")) == (← IO.FS.readBinFile (old / "hook/body.txt")))),
    ("sameSelectedUnitIds",toJson (selected.getObjValD "selected" ==
      ((← read (oldStages / "selection-plan.json")).getObjValD "data").getObjValD "selected")),
    ("sameDomain",toJson (domain == (← read (oldStages / "delivery-domain.json")).getObjValD "data")),
    ("sameFrozenEvidence",toJson ((← read (root / trial / "audit.json")).getObjValD "frozenEvidence" ==
      (← read (old / "hook/audit.json")).getObjValD "frozenEvidence")),
    ("parent",← read (old / "hook/result.json")),("candidate",actual),
    ("tokenImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
  IO.FS.writeFile (output / "terminal-hook-guard.json") guard.pretty
  IO.FS.writeFile (output / "collection.json") (Json.mkObj [("trial",toJson trial),
    ("nativeCheckAndRuntimeSourceMatch",toJson true),("newSeedStudy",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
