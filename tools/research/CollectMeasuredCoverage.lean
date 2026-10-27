import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source target : System.FilePath) : IO Unit := do
  let bytes ← IO.FS.readBinFile source
  IO.FS.createDirAll target.parent.get!
  if ← target.pathExists then
    unless (← IO.FS.readBinFile target) == bytes do throw (IO.userError "preserve measured-cost evidence")
  else IO.FS.writeBinFile target bytes

def main (args : List String) : IO Unit := do
  let [trial,label] := args | throw (IO.userError "trial and new evidence label required")
  unless [trial,label].all (fun text => !text.isEmpty && text.toList.all (fun c => c.isAlphanum || c == '-')) do
    throw (IO.userError "simple labels required")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "rendered-marginal-cost-20261027"
  let parent := base / "shared-original-structure-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/rendered-marginal-cost" / label
  unless !(← output.pathExists) do throw (IO.userError "preserve prior measured-cost collection")
  let guard ← read (root / (trial ++ ".guard.json"))
  unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "actual hook still owns processes")
  IO.FS.createDirAll output
  let mut inputs := #[(root / "product-build/StudyMain").toString]
  for moduleName in ["Eggshell.Handoff","Eggshell.CanonicalSourceDelivery","tools.research.MeasuredCoverage"] do
    let stem := moduleName.replace "." "_"
    let object := root / "product-build" / (stem ++ ".o")
    let stamp ← IO.ofExcept ((← read (object.withExtension "source")).getArr?)
    let source := (if moduleName.startsWith "tools.research." then project else root / "checkout") /
      System.FilePath.mk (moduleName.replace "." "/" ++ ".lean")
    unless stamp[0]!.getStr?.toOption == some (← IO.FS.readFile source) do throw (IO.userError "source differs from native object")
    for literal in ← IO.ofExcept stamp[1]!.getArr? do
      let (name,text) ← IO.ofExcept (fromJson? (α := String × String) literal)
      unless text == (← IO.FS.readFile (source.parent.get! / name)) do throw (IO.userError "included bytes differ from native object")
    copy (object.withExtension "source") (output / "contracts" / (moduleName ++ ".source"))
    inputs := inputs ++ #[object.toString,(object.withExtension "source").toString,(object.withExtension "dependencies").toString]
  let hashed ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts"] ++ inputs}
  unless hashed.exitCode == 0 do throw (IO.userError hashed.stderr)
  let hashes ← IO.ofExcept (Json.parse hashed.stdout >>= Json.getArr?)
  let actual ← read (root / trial / "result.json")
  let commandName := if actual.getObjValD "actualHook" == toJson true then "hook" else "worker"
  unless hashes[0]!.getObjValD "sha256" == actual.getObjValD "runtimeSha256" do
    throw (IO.userError "collected product differs from executed runtime")
  IO.FS.writeFile (output / "native-input-digests.json") hashed.stdout
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/Eggshell/Handoff.lean",
    "-L","b/Eggshell/Handoff.lean",(parent / "checkout/Eggshell/Handoff.lean").toString,
    (root / "checkout/Eggshell/Handoff.lean").toString]}
  unless diff.exitCode == 1 do throw (IO.userError "isolated cost change expected")
  IO.FS.writeFile (output / "core.patch") diff.stdout
  for file in ["result.json","audit.json","changed-views.json","frozen-before-delivery.json","body.txt","audit-input.json",
      "handoff-trace.txt","shutdown.json","publisher-shutdown.json"] do
    copy (root / trial / file) (output / "hook" / file)
  for file in ["record.json","stdin","stdout","stderr"] do
    copy (root / trial / commandName / file) (output / "hook" / commandName / file)
  if ← (root / trial / "worker.sample.txt").pathExists then
    copy (root / trial / "worker.sample.txt") (output / "worker.sample.txt")
  copy (root / "hook-build/tools_research_OnePreparedHook.source") (output / "contracts/OnePreparedHook.source")
  let mut chosen := Json.null
  let mut domain := Json.null
  for entry in ← (root / trial / "data/receipts").readDir do
    if !(← entry.path.isDir) then continue
    for file in ["search.json","delivery-domain.json","selection-plan.json","synaptic-delivery.json"] do
      if !(← (entry.path / file).pathExists) then continue
      copy (entry.path / file) (output / "receipt-stages" / entry.fileName / file)
      if file == "selection-plan.json" then chosen := (← read (entry.path / file)).getObjValD "data"
      if file == "delivery-domain.json" then domain := (← read (entry.path / file)).getObjValD "data"
  let old := project / "docs/candidates/shared-original-structure/final"
  let parentChosen ← read (old / "receipt-stages/5fb9c697fb0410a7d4e3c92a3ca86c8c5a7737b415acdd8e3a32a394145d3bb1/selection-plan.json")
  let parentDomain ← read (old / "receipt-stages/5fb9c697fb0410a7d4e3c92a3ca86c8c5a7737b415acdd8e3a32a394145d3bb1/delivery-domain.json")
  IO.FS.writeFile (output / "comparison.json") (Json.mkObj [
    ("fields",toJson (["families","candidateUnits","fixedCost","limit","scale"].map fun field =>
      (field,chosen.getObjValD field == (parentChosen.getObjValD "data").getObjValD field))),
    ("sameDomain",toJson (domain == parentDomain.getObjValD "data")),
    ("sameFrozenEvidence",toJson ((← read (root / trial / "audit.json")).getObjValD "frozenEvidence" ==
      (← read (old / "hook/audit.json")).getObjValD "frozenEvidence")),
    ("sameBody",toJson ((← IO.FS.readBinFile (root / trial / "body.txt")) == (← IO.FS.readBinFile (old / "hook/body.txt")))),
    ("tokenImprovementMeasured",toJson false)]).pretty
  let mut guards := #[]
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      unless value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "candidate guard still live")
      guards := guards.push (entry.fileName,value)
  IO.FS.writeFile (output / "guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "collection.json") (Json.mkObj [
    ("trial",toJson trial),("candidate",toJson root.toString),("answeringModelCalls",toJson (0 : Nat)),
    ("newSeedStudy",toJson false),("adopted",toJson false)]).pretty
  IO.println s!"Captured measured-cost evidence: {label}"
