import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source target : System.FilePath) : IO Unit := do
  let bytes ← IO.FS.readBinFile source
  IO.FS.createDirAll target.parent.get!
  if ← target.pathExists then
    unless (← IO.FS.readBinFile target) == bytes do throw (IO.userError "preserve captured evidence")
  else IO.FS.writeBinFile target bytes

def main (args : List String) : IO Unit := do
  let [trial,label] := args | throw (IO.userError "terminal trial and new collection label required")
  unless [trial,label].all (fun text => !text.isEmpty && text.toList.all (fun c => c.isAlphanum || c == '-')) do
    throw (IO.userError "simple labels required")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "evidence-cause-contract-20261027"
  let parent := base / "shared-original-structure-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/evidence-cause-contract" / label
  unless !(← output.pathExists) do throw (IO.userError "preserve prior cause collection")
  let guard ← read (root / (trial ++ ".guard.json"))
  unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "trial is not terminal")
  IO.FS.createDirAll output
  let nativeChecks ← read (root / "native-causes/result.json")
  unless nativeChecks.getObjValD "allPassed" == toJson true do throw (IO.userError "native cause checks failed")
  let dependencies ← IO.ofExcept (fromJson? (α := Array (String × String))
    (← read (root / "audit-build/tools_research_CauseContractChecks.dependencies")))
  let mut artifacts := #[(root / "product-build/StudyMain").toString]
  let mut patch := ""
  for moduleName in ["SynapticCause","SynapseTransport","SynapseBundles","SynapseRecommend","Handoff"] do
    let source := root / "checkout/Eggshell" / (moduleName ++ ".lean")
    let object := root / "product-build" / ("Eggshell_" ++ moduleName ++ ".o")
    let stamp ← IO.ofExcept ((← read (object.withExtension "source")).getArr?)
    unless stamp[0]!.getStr?.toOption == some (← IO.FS.readFile source) do
      throw (IO.userError "source differs from native object")
    let some (_,nativeStamp) := dependencies.find? (·.1 == "Eggshell." ++ moduleName) |
      throw (IO.userError "native checks did not import the changed module")
    unless nativeStamp == (← IO.FS.readFile (object.withExtension "source")) do
      throw (IO.userError "native checks used a different product source")
    for literal in ← IO.ofExcept stamp[1]!.getArr? do
      let (name,text) ← IO.ofExcept (fromJson? (α := String × String) literal)
      unless text == (← IO.FS.readFile (source.parent.get! / name)) do
        throw (IO.userError "included bytes differ from native object")
    copy (object.withExtension "source") (output / "contracts" / (moduleName ++ ".source"))
    artifacts := artifacts ++ #[object.toString,(object.withExtension "source").toString,
      (object.withExtension "dependencies").toString]
    let previous := parent / "checkout/Eggshell" / (moduleName ++ ".lean")
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0",
      "-L","a/Eggshell/" ++ moduleName ++ ".lean","-L","b/Eggshell/" ++ moduleName ++ ".lean",
      if ← previous.pathExists then previous.toString else "/dev/null",source.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "expected isolated cause source change")
    patch := patch ++ diff.stdout
  IO.FS.writeFile (output / "core.patch") patch
  copy (root / "native-causes/result.json") (output / "checks/result.json")
  copy (root / "native-causes.guard.json") (output / "checks/guard.json")
  copy (root / "audit-build/tools_research_CauseContractChecks-lean.stdout") (output / "checks/axioms.txt")
  copy (root / "audit-build/tools_research_CauseContractChecks.source") (output / "checks/source.stamp")
  copy (root / "checkout/Eggshell/SynapticCause.lean") (output / "contracts/SynapticCause.lean")
  let hashed ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts"] ++ artifacts}
  unless hashed.exitCode == 0 do throw (IO.userError hashed.stderr)
  let hashes ← IO.ofExcept (Json.parse hashed.stdout >>= Json.getArr?)
  let actual ← read (root / trial / "result.json")
  unless hashes[0]!.getObjValD "sha256" == actual.getObjValD "runtimeSha256" do
    throw (IO.userError "captured runtime differs from executed product")
  IO.FS.writeFile (output / "native-input-digests.json") hashed.stdout
  for file in ["result.json","audit.json","changed-views.json","frozen-before-delivery.json","body.txt",
      "audit-input.json","handoff-trace.txt","shutdown.json","publisher-shutdown.json"] do
    copy (root / trial / file) (output / "hook" / file)
  for file in ["record.json","stdin","stdout","stderr"] do
    copy (root / trial / "hook" / file) (output / "hook/hook" / file)
  copy (root / "hook-build/tools_research_OnePreparedHook.source") (output / "contracts/OnePreparedHook.source")
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
  let previousSelected := (← read (oldStages / "selection-plan.json")).getObjValD "data"
  IO.FS.writeFile (output / "comparison.json") (Json.mkObj [
    ("sameDomain",toJson (domain == (← read (oldStages / "delivery-domain.json")).getObjValD "data")),
    ("sameFrozenEvidence",toJson ((← read (root / trial / "audit.json")).getObjValD "frozenEvidence" ==
      (← read (old / "hook/audit.json")).getObjValD "frozenEvidence")),
    ("fields",toJson (["families","candidateUnits","fixedCost","limit","scale"].map fun field =>
      (field,selected.getObjValD field == previousSelected.getObjValD field))),
    ("jointBindings",selected.getObjValD "jointBindings"),("modelCalls",toJson (0 : Nat)),
    ("tokenImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
  IO.FS.writeFile (output / "terminal-guard.json") guard.pretty
  IO.FS.writeFile (output / "collection.json") (Json.mkObj [
    ("trial",toJson trial),("newSeedStudy",toJson false),("actualHook",actual.getObjValD "actualHook"),
    ("runtimeSourcesAndIncludesChecked",toJson true),("modelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println s!"Captured native cause contract and actual hook: {label}"
