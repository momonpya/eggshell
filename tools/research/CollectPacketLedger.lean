import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def copy? (source target : System.FilePath) : IO Unit := do
  if !(← source.pathExists) then return
  let bytes ← IO.FS.readBinFile source
  IO.FS.createDirAll target.parent.get!
  if ← target.pathExists then
    unless (← IO.FS.readBinFile target) == bytes do throw (IO.userError "preserve collected evidence")
  else IO.FS.writeBinFile target bytes

def main (_args : List String) : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "packet-delivery-ledger-20261027"
  let parent := base / "quotation-context-20261027"
  let output := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/packet-delivery-ledger"
  let records := output / "records"
  IO.FS.createDirAll records
  -- The measured shared-reader binary precedes the canonical ledger witness.
  -- Keep its source patch and runtime identity as small evidence, not a DB archive.
  if !(← (output / "shared-reader-core.patch").pathExists) then
    copy? (output / "core.patch") (output / "shared-reader-core.patch")
  if !(← (records / "shared-reader-runtime.json").pathExists) then
    copy? (records / "runtime.json") (records / "shared-reader-runtime.json")
  let mut guards := #[]
  for entry in ← root.readDir do
    if !entry.fileName.endsWith ".guard.json" then continue
    let value ← read entry.path
    unless (value.getObjValAs? String "state").toOption == some "finished" &&
        (value.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
      throw (IO.userError "candidate still has an active process")
    guards := guards.push (entry.fileName,value)
  IO.FS.writeFile (records / "guards.json") (toJson guards).pretty
  let response ← IO.FS.readFile (root / "product-build/runtime.rsp")
  let objectMap ← IO.ofExcept ((← read (root / "objects.json")).getObj?)
  let files := #["Eggshell/PacketReceipt.lean","Eggshell/SynapseRecommend.lean","Eggshell/Handoff.lean"]
  let mut patch := ""
  let mut selected := #[]
  for file in files do
    let moduleName := file.replace "/" "." |>.replace ".lean" ""
    let mut object := none
    for row in response.splitOn "\n" do
      if row.isEmpty then continue
      let path ← IO.ofExcept (Json.parse row >>= Json.getStr?)
      if ((objectMap[path]?).bind (fun value => value.getStr?.toOption)) == some moduleName then
        if object.isSome then throw (IO.userError "duplicate selected module")
        object := some (System.FilePath.mk path)
    let some selectedObject := object | throw (IO.userError s!"missing selected module: {moduleName}")
    let source := root / "checkout" / file
    let stamp ← read (selectedObject.withExtension "source")
    let fields ← IO.ofExcept stamp.getArr?
    unless (fields[0]!.getStr?).toOption == some (← IO.FS.readFile source) &&
        (← (selectedObject.withExtension "dependencies").pathExists) do throw (IO.userError "source/object mismatch")
    for included in ← IO.ofExcept fields[1]!.getArr? do
      let (name,text) ← IO.ofExcept (fromJson? (α := String × String) included)
      unless text == (← IO.FS.readFile (source.parent.get! / name)) do throw (IO.userError "embedded source changed")
    selected := selected.push (moduleName,selectedObject.toString)
    if moduleName == "Eggshell.Handoff" then
      let symbols ← IO.Process.output {cmd := "/usr/bin/nm",args := #["-u",selectedObject.toString]}
      unless symbols.exitCode == 0 && (symbols.stdout.splitOn "_l_SharedCoverage_Deferred_Sparse_choose_x3f").length > 1 &&
          (symbols.stdout.splitOn "_l_SharedCoverage_Deferred_chooseDeferred_x3f").length == 1 do
        throw (IO.userError "incremental selector is not the actual native callee")
      IO.FS.writeFile (records / "handoff-undefined-symbols.txt") symbols.stdout
    let old := parent / "checkout" / file
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
      (if ← old.pathExists then old.toString else "/dev/null"),source.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "changed isolated source required")
    patch := patch ++ diff.stdout
  IO.FS.writeFile (output / "core.patch") patch
  IO.FS.writeFile (records / "link-boundary.json") (Json.mkObj [("selectedObjects",toJson selected),
    ("sourcesAndEmbeddedBytesExact",toJson true),("incrementalSelectorConnected",toJson true),
    ("parent",toJson parent.toString),("adopted",toJson false)]).pretty
  for name in ["saved-origin-packet","canonical-origin-packet","actual-body-witness"] do
    copy? (root / name / "result.json") (records / name / "result.json")
  for file in ["independent-original-bindings.json","selected-packet-receipt.json"] do
    copy? (root / "actual-body-witness" / file) (records / "actual-body-witness" / file)
  for file in ["contract.stdout","contract.stderr"] do copy? (root / file) (records / "final-contracts" / file)
  for (build,stem) in #[("audit-build","tools_research_PacketLedgerAudit"),
      ("payload-build","tools_research_NativePacketPayloadAudit"),("hook-build","tools_research_OnePreparedHook")] do
    for suffix in [".source","-lean.stdout"] do
      copy? (root / build / (stem ++ suffix)) (records / "final-contracts" / (stem ++ suffix))
  for name in ["one-prepared-hook","shared-reader-hook","canonical-reader-hook"] do
    for file in ["result.json","changed-views.json","frozen-before-delivery.json","body.txt","audit.json","audit-input.json",
        "handoff-trace.txt","shutdown.json","publisher-shutdown.json","hook/record.json","hook/stdin","hook/stdout","hook/stderr"] do
      copy? (root / name / file) (records / name / file)
    let receipts := root / name / "data/receipts"
    if ← receipts.pathExists then
      for entry in ← receipts.readDir do
        if !(← entry.path.isDir) then continue
        for file in ["search.json","delivery-domain.json","selection-plan.json","synaptic-delivery.json",
            "canonical-source-input.json","canonical-source-reuse.json","canonical-source-failure.json","keyed-nominations.json"] do
          copy? (entry.path / file) (records / name / "receipt-stages" / entry.fileName / file)
        let mut stages := #[]
        for file in ["search.json","delivery-domain.json","selection-plan.json","synaptic-delivery.json"] do
          if !(← (entry.path / file).pathExists) then continue
          let value ← read (entry.path / file)
          let data := value.getObjValD "data"
          let count := fun field => (data.getObjValAs? (Array Json) field).toOption.getD #[] |>.size
          stages := stages.push (Json.mkObj [
            ("stage",toJson file),("observedMs",value.getObjValD "observedMs"),
            ("complete",data.getObjValD "complete"),("inputs",data.getObjValD "inputs"),
            ("candidateUnits",data.getObjValD "candidateUnits"),("selected",toJson (count "selected")),
            ("bindingRequests",data.getObjValD "bindingRequests"),("bindingBytes",data.getObjValD "bindingBytes"),
            ("originalPieces",toJson (count "originalPieces")),("sharedRows",toJson (count "sharedRows")),
            ("unverifiedParts",data.getObjValD "unverifiedParts"),
            ("trace",data.getObjValD "trace"),("packetVerified",data.getObjValD "packetVerified")])
        IO.FS.writeFile (records / name / "stage-summary.json") (toJson stages).pretty
  copy? (root / "canonical-reader-hook/search.sample.txt") (records / "canonical-reader-hook/search.sample.txt")
  let firstBody ← IO.FS.readBinFile (root / "shared-reader-hook/body.txt")
  let finalBody ← IO.FS.readBinFile (root / "canonical-reader-hook/body.txt")
  unless firstBody == finalBody do throw (IO.userError "ledger-only change altered the delivered body")
  IO.FS.writeFile (records / "body-equality.json") (Json.mkObj [
    ("trials",toJson #["shared-reader-hook","canonical-reader-hook"]),
    ("sameActualBodyBytes",toJson true),("bodyBytes",toJson finalBody.size),
    ("requiredDelivered",toJson (4 : Nat)),("requiredEligible",toJson (6 : Nat)),
    ("tokenImprovementMeasured",toJson false)]).pretty
  let artifacts ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts",(root / "product-build/StudyMain").toString]}
  unless artifacts.exitCode == 0 do throw (IO.userError artifacts.stderr)
  IO.FS.writeFile (records / "runtime.json") artifacts.stdout
  IO.FS.writeFile (records / "collection.json") (Json.mkObj [("modelCalls",toJson (0 : Nat)),
    ("fullWarmCalls",toJson (0 : Nat)),("candidate",toJson root.toString),("adopted",toJson false)]).pretty
