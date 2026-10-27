import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def copy (source target : System.FilePath) : IO Unit := do
  let bytes ← IO.FS.readBinFile source
  IO.FS.createDirAll target.parent.get!
  if ← target.pathExists then
    unless (← IO.FS.readBinFile target) == bytes do throw (IO.userError "preserve original structure evidence")
  else IO.FS.writeBinFile target bytes

def main (args : List String) : IO Unit := do
  let rejected := args == ["native-only"]
  unless args.isEmpty || rejected do throw (IO.userError "native-only | no arguments")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "shared-original-structure-20261027"
  let parent := base / "prepared-original-service-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / (if rejected then "docs/candidates/shared-original-structure/native-only"
    else "docs/candidates/shared-original-structure/final")
  let trialName := if rejected then "prepared-structure-hook" else "complete-structure-hook"
  IO.FS.createDirAll output
  let mut guards := #[]
  for entry in ← root.readDir do
    if !entry.fileName.endsWith ".guard.json" then continue
    let value ← read entry.path
    unless value.getObjValD "state" == toJson "finished" &&
        value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "original structure experiment still live")
    guards := guards.push (entry.fileName,value)
  for label in [if rejected then "checked-structure" else "checked-all-structure",trialName] do
    let value ← read (root / (label ++ ".guard.json"))
    unless value.getObjValD "exitCode" == toJson (0 : Nat) && value.getObjValD "guardTriggered" == toJson false do
      throw (IO.userError "native structure audit or actual hook failed")
  let mut patch := ""
  let mut objects := #[]
  for file in ["Eggshell/OriginalStructure.lean","Eggshell/Handoff.lean","Eggshell/ObservedRecordView.lean",
      "Eggshell/SynapseIndex.lean","Eggshell/SynapseTransport.lean","Eggshell/CanonicalSourcePrepared.lean",
      "Eggshell/PublicationClient.lean","Eggshell/PublicationService.lean"] ++
      (if rejected then [] else ["Eggshell/SynapseBuild.lean"]) do
    let moduleName := file.replace "/" "." |>.replace ".lean" ""
    let stem := moduleName.replace "." "_"
    let object := root / "product-build" / (stem ++ ".o")
    let stamp ← IO.ofExcept ((← read (object.withExtension "source")).getArr?)
    let source := root / "checkout" / file
    unless stamp[0]!.getStr?.toOption == some (← IO.FS.readFile source) do
      throw (IO.userError s!"native source mismatch: {moduleName}")
    for included in ← IO.ofExcept stamp[1]!.getArr? do
      let (path,text) ← IO.ofExcept (fromJson? (α := String × String) included)
      unless text == (← IO.FS.readFile (source.parent.get! / path)) do
        throw (IO.userError "native included source mismatch")
    copy (object.withExtension "source") (output / "contracts" / (moduleName ++ ".source"))
    objects := objects ++ #[object.toString,(object.withExtension "source").toString,
      (object.withExtension "dependencies").toString]
    let old := parent / "checkout" / file
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
      (if ← old.pathExists then old.toString else "/dev/null"),source.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "missing isolated structure change")
    patch := patch ++ diff.stdout
  IO.FS.writeFile (output / "core.patch") patch
  let hash ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts",(root / "product-build/StudyMain").toString] ++ objects}
  unless hash.exitCode == 0 do throw (IO.userError hash.stderr)
  IO.FS.writeFile (output / "native-input-digests.json") hash.stdout
  let hashes ← IO.ofExcept (Json.parse hash.stdout >>= Json.getArr?)
  let actual ← read (root / trialName / "result.json")
  unless hashes[0]!.getObjValD "sha256" == actual.getObjValD "runtimeSha256" do
    throw (IO.userError "actual hook did not execute the measured structure runtime")
  let checked := if rejected then "checked-structure" else "checked-all-structure"
  for file in ["result.json","changed-view.json"] do
    copy (root / checked / file) (output / "checks" / file)
  if rejected then copy (root / checked / "audit.sample.txt") (output / "checks/audit.sample.txt")
  copy (root / "audit-build/tools_research_OriginalStructureAudit.source") (output / "contracts/audit.source")
  copy (root / "audit-build/tools_research_OriginalStructureAudit-lean.stdout") (output / "checks/axioms.txt")
  let trial := root / trialName
  for file in ["result.json","audit.json","changed-views.json","frozen-before-delivery.json","body.txt","audit-input.json",
      "handoff-trace.txt","shutdown.json","publisher-shutdown.json","hook/record.json","hook/stdin","hook/stdout","hook/stderr"] do
    copy (trial / file) (output / "hook" / file)
  let mut selection := none
  for entry in ← (trial / "data/receipts").readDir do
    if !(← entry.path.isDir) then continue
    for file in ["search.json","delivery-domain.json","selection-plan.json","synaptic-delivery.json"] do
      if !(← (entry.path / file).pathExists) then continue
      copy (entry.path / file) (output / "receipt-stages" / entry.fileName / file)
      if file == "selection-plan.json" then
        unless selection.isNone do throw (IO.userError "ambiguous structure selection receipt")
        selection := some ((← read (entry.path / file)).getObjValD "data")
  let some chosen := selection | throw (IO.userError "missing actual selection receipt")
  let old := project / "docs/candidates/prepared-original-service"
  let oldSelection ← read (old / "receipt-stages/4b58ed3cb00c88a81d419a341b7fadebf2e5f7fa062431f1a07ebe9f46fc901c/selection-plan.json")
  let mut fields := #[]
  for field in ["families","candidateUnits","selected","fixedCost","limit","scale","jointBindings"] do
    fields := fields.push (field,chosen.getObjValD field == (oldSelection.getObjValD "data").getObjValD field)
  IO.FS.writeFile (output / "comparison.json") (Json.mkObj [
    ("sameActualBodyBytes",toJson ((← IO.FS.readBinFile (trial / "body.txt")) == (← IO.FS.readBinFile (old / "hook/body.txt")))),
    ("selectionFields",toJson fields),("sameFrozenEvidence",toJson ((← read (trial / "audit.json")).getObjValD "frozenEvidence" ==
      (← read (old / "hook/audit.json")).getObjValD "frozenEvidence")),("tokenImprovementMeasured",toJson false)]).pretty
  IO.FS.writeFile (output / "guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "collection.json") (Json.mkObj [("candidate",toJson root.toString),
    ("modelCalls",toJson (0 : Nat)),("actualHookRuns",toJson (1 : Nat)),("newSeedStudy",toJson false),
    ("adopted",toJson false),("rejected",toJson rejected),("dependencyStampsStoredAsDigests",toJson true)]).pretty
