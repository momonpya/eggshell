import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy (source target : System.FilePath) : IO Unit := do
  if !(← source.pathExists) then return
  IO.FS.createDirAll target.parent.get!
  let value ← IO.FS.readFile source
  if ← target.pathExists then
    unless (← IO.FS.readFile target) == value do throw (IO.userError "preserve prior evidence")
  else IO.FS.writeFile target value

def main (args : List String) : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "prepared-record-delivery-20261027"
  let parent := base / "bound-span-preparation-20261027"
  let output := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/prepared-record-delivery"
  let output ← match args with
    | [] => pure output
    | ["empty-shell"] => pure (output / "empty-shell-attempt")
    | _ => throw (IO.userError "unknown collection boundary")
  let records := output / "records"
  IO.FS.createDirAll records
  let mut guards := #[]
  for entry in ← root.readDir do
    if entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      unless (value.getObjValAs? String "state").toOption == some "finished" &&
          (value.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
        throw (IO.userError "candidate is still active")
      guards := guards.push (entry.fileName,value)
  IO.FS.writeFile (records / "guards.json") (toJson guards).pretty
  let files := #["Eggshell/ObservedRecordView.lean","Eggshell/SynapseIndex.lean","Eggshell/SynapseBuild.lean",
    "Eggshell/CanonicalSourcePrepared.lean","Eggshell/PublicationWire.lean","Eggshell/PublicationClient.lean",
    "Eggshell/PublicationService.lean","Eggshell/SynapseTransport.lean","Eggshell/Handoff.lean"]
  let response ← IO.FS.readFile (root / "product-build/runtime.rsp")
  let mut patch := ""
  for file in files do
    let path := root / "checkout" / file
    let stem := file.replace "/" "_" |>.replace ".lean" ""
    let object := root / "product-build" / (stem ++ ".o")
    let stamp ← read (object.withExtension "source")
    let fields ← IO.ofExcept stamp.getArr?
    unless (fields[0]!.getStr?).toOption == some (← IO.FS.readFile path) &&
        (response.splitOn ((toJson object.toString).compress)).length == 2 &&
        (← (object.withExtension "dependencies").pathExists) do
      throw (IO.userError s!"candidate source/object mismatch: {file}")
    for included in ← IO.ofExcept fields[1]!.getArr? do
      let (name,bytes) ← IO.ofExcept (fromJson? (α := String × String) included)
      unless bytes == (← IO.FS.readFile (path.parent.get! / name)) do
        throw (IO.userError s!"candidate embedded source mismatch: {file}")
    let old := parent / "checkout" / file
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
      (if ← old.pathExists then old.toString else "/dev/null"),path.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "exact changed candidate expected")
    patch := patch ++ diff.stdout
  IO.FS.writeFile (output / "core.patch") patch
  IO.FS.writeFile (records / "link-boundary.json") (Json.mkObj [("files",toJson files),
    ("sourceAndEmbeddedBytesExact",toJson true),("selectedObjectsExact",toJson true),
    ("dependencyClosuresPresent",toJson true),("adopted",toJson false)]).pretty
  let artifact ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts",(root / "product-build/StudyMain").toString]}
  unless artifact.exitCode == 0 do throw (IO.userError artifact.stderr)
  IO.FS.writeFile (records / "runtime.json") artifact.stdout
  for file in ["result.json"] do copy (root / "raw-record-points" / file) (records / "original-point-audit" / file)
  copy (root / "point-diagnosis/diagnostic.json") (output / "empty-shell-attempt/records/point-diagnosis.json")
  for name in ["variable-frames","ranked-variable-frames"] do
    copy (root / name / "result.json") (records / name / "result.json")
  for name in ["tools_research_DirectBudgetAudit.source","tools_research_DirectBudgetAudit-lean.stdout"] do
    copy (root / "budget-build" / name) (records / "contracts" / name)
  for name in ["result.json","body.txt","audit.json","audit-input.json","handoff-trace.txt","shutdown.json","publisher-shutdown.json"] do
    copy (root / "checked-hook" / name) (records / "checked-hook" / name)
  for name in ["record.json","stdin","stdout","stderr"] do
    copy (root / "checked-hook/hook" / name) (records / "checked-hook/hook" / name)
  for file in ["tools_research_PreparedRecordAudit-lean.stdout","tools_research_PreparedRecordAudit.source"] do
    copy (root / "audit-build" / file) (records / "contracts" / file)
  let trial := root / "fixed-source-hooks"
  for file in ["results.json","frozen-before-delivery.json","warm-complete.json","publisher-shutdown.json"] do
    copy (trial / file) (records / "actual-hook" / file)
  for file in ["body.txt","audit.json","audit-input.json","shutdown.json"] do
    copy (trial / "topic-2" / file) (records / "actual-hook/topic-2" / file)
  for file in ["record.json","stdin","stdout","stderr"] do
    copy (trial / "topic-2/hook" / file) (records / "actual-hook/topic-2/hook" / file)
    copy (trial / "warm" / file) (records / "actual-hook/warm" / file)
  let receipts := trial / "data/receipts"
  if ← receipts.pathExists then
    for entry in ← receipts.readDir do
      if (← entry.path.symlinkMetadata).type != .dir then continue
      for name in ["selection-plan.json","delivery-domain.json","canonical-source-reuse.json",
          "canonical-source-failure.json","canonical-source-input.json"] do
        copy (entry.path / name) (records / "receipt-stages" / entry.fileName / name)
      let synaptic := entry.path / "synaptic-delivery.json"
      if ← synaptic.pathExists then
        let value ← read synaptic
        let data := value.getObjValD "data"
        let offers := (data.getObjValAs? (Array Json) "offers").toOption.getD #[]
        let summary := Json.mkObj [("complete",data.getObjValD "complete"),("offers",toJson offers.size),
          ("deliveredOffers",toJson ((offers.filter fun row =>
            (row.getObjValAs? Bool "bodyDelivered").toOption == some true).size)),
          ("originalReferences",toJson ((data.getObjValAs? (Array Json) "originalReferences").toOption.getD #[]).size),
          ("originalOutputs",toJson ((data.getObjValAs? (Array Json) "originalOutputs").toOption.getD #[]).size)]
        let path := records / "receipt-stages" / entry.fileName / "synaptic-summary.json"
        IO.FS.createDirAll path.parent.get!
        IO.FS.writeFile path summary.pretty
  -- Endpoint files, credentials and reusable service state are not exported.
  IO.FS.writeFile (records / "collection.json") (Json.mkObj [("parent",toJson parent.toString),
    ("candidate",toJson root.toString),("modelCalls",toJson (0 : Nat)),("adopted",toJson false),
    ("sourceHelperBeforeInterfaceFixExecuted",toJson false)]).pretty
