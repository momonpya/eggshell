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
    unless (← IO.FS.readBinFile target) == bytes do throw (IO.userError "preserve collected incidence evidence")
  else IO.FS.writeBinFile target bytes

private def stages (trial target : System.FilePath) : IO Unit := do
  let mut rows := #[]
  for entry in ← (trial / "data/receipts").readDir do
    if !(← entry.path.isDir) then continue
    for file in ["search.json","delivery-domain.json","selection-plan.json","synaptic-delivery.json"] do
      if !(← (entry.path / file).pathExists) then continue
      copy? (entry.path / file) (target / "receipt-stages" / entry.fileName / file)
      let value ← read (entry.path / file)
      let data := value.getObjValD "data"
      let count := fun field => (data.getObjValAs? (Array Json) field).toOption.getD #[] |>.size
      rows := rows.push (Json.mkObj [
        ("stage",toJson file),("observedMs",value.getObjValD "observedMs"),
        ("trace",data.getObjValD "trace"),("candidateUnits",data.getObjValD "candidateUnits"),
        ("selected",toJson (count "selected")),("complete",data.getObjValD "complete"),
        ("originalPieces",toJson (count "originalPieces")),("sharedRows",toJson (count "sharedRows")),
        ("unverifiedParts",data.getObjValD "unverifiedParts"),("packetVerified",data.getObjValD "packetVerified")])
  IO.FS.writeFile (target / "stage-summary.json") (toJson rows).pretty

def main (_args : List String) : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "prepared-cue-incidence-20261027"
  let parent := base / "packet-delivery-ledger-20261027"
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/prepared-cue-incidence"
  let records := output / "records"
  IO.FS.createDirAll records
  let mut guards := #[]
  for entry in ← root.readDir do
    if !entry.fileName.endsWith ".guard.json" then continue
    let value ← read entry.path
    unless (value.getObjValAs? String "state").toOption == some "finished" &&
        (value.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
      throw (IO.userError "incidence candidate still has an active process")
    guards := guards.push (entry.fileName,value)
  IO.FS.writeFile (records / "guards.json") (toJson guards).pretty
  let response ← IO.FS.readFile (root / "product-build/runtime.rsp")
  let objectMap ← IO.ofExcept ((← read (root / "objects.json")).getObj?)
  let mut selected := #[]
  let mut patch := ""
  for file in #["tools/PreparedCueIndex.lean","Eggshell/Handoff.lean"] do
    let moduleName := file.replace "/" "." |>.replace ".lean" ""
    let mut object := none
    for row in response.splitOn "\n" do
      if row.isEmpty then continue
      let path ← IO.ofExcept (Json.parse row >>= Json.getStr?)
      if ((objectMap[path]?).bind (fun value => value.getStr?.toOption)) == some moduleName then
        if object.isSome then throw (IO.userError "duplicate selected incidence module")
        object := some (System.FilePath.mk path)
    let some current := object | throw (IO.userError s!"missing selected module: {moduleName}")
    let source := root / "checkout" / file
    let fields ← IO.ofExcept ((← read (current.withExtension "source")).getArr?)
    unless fields[0]!.getStr?.toOption == some (← IO.FS.readFile source) &&
        (← (current.withExtension "dependencies").pathExists) do throw (IO.userError "incidence source/object mismatch")
    for included in ← IO.ofExcept fields[1]!.getArr? do
      let (name,text) ← IO.ofExcept (fromJson? (α := String × String) included)
      unless text == (← IO.FS.readFile (source.parent.get! / name)) do throw (IO.userError "embedded source changed")
    selected := selected.push (moduleName,current.toString)
    copy? (current.withExtension "source") (records / "final-contracts" / (moduleName ++ ".source"))
    if moduleName == "Eggshell.Handoff" then
      let symbols ← IO.Process.output {cmd := "/usr/bin/nm",args := #["-u",current.toString]}
      unless symbols.exitCode == 0 && ["_l_Eggshell_PreparedCueIndex_Prepared_one___redArg",
          "_l_Eggshell_PreparedCueIndex_Prepared_many___redArg","_l_SharedCoverage_Deferred_Sparse_choose_x3f"].all
          (fun name => (symbols.stdout.splitOn name).length > 1) do
        throw (IO.userError "ordered cue postings or incremental selector disconnected")
      IO.FS.writeFile (records / "native-callees.txt") symbols.stdout
    let old := parent / "checkout" / file
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
      (if ← old.pathExists then old.toString else "/dev/null"),source.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "changed isolated source required")
    patch := patch ++ diff.stdout
  IO.FS.writeFile (output / "core.patch") patch
  IO.FS.writeFile (records / "link-boundary.json") (Json.mkObj [("selectedObjects",toJson selected),
    ("sourcesAndEmbeddedBytesExact",toJson true),("orderedPostingsAndIncrementalSelectorConnected",toJson true),
    ("parent",toJson parent.toString),("adopted",toJson false)]).pretty
  copy? (root / "checked-cue-order/result.json") (records / "checked-cue-order.json")
  copy? (root / "unique-cue-order/result.json") (records / "unique-cue-order.json")
  for file in ["tools_research_CueIncidenceAudit-lean.stdout","tools_research_CueIncidenceAudit.source"] do
    copy? (root / "audit-build" / file) (records / "final-contracts" / file)
  for file in ["tools_research_OnePreparedHook-lean.stdout","tools_research_OnePreparedHook.source"] do
    copy? (root / "hook-build" / file) (records / "final-contracts" / file)
  let trial := root / "indexed-prepared-hook"
  for file in ["result.json","changed-views.json","frozen-before-delivery.json","body.txt","audit.json","audit-input.json",
      "handoff-trace.txt","shutdown.json","publisher-shutdown.json","hook/record.json","hook/stdin","hook/stdout","hook/stderr"] do
    copy? (trial / file) (records / "hook" / file)
  stages trial records
  let previous := project / "docs/candidates/packet-delivery-ledger/records/canonical-reader-hook/body.txt"
  let same := (← IO.FS.readBinFile previous) == (← IO.FS.readBinFile (trial / "body.txt"))
  IO.FS.writeFile (records / "comparison.json") (Json.mkObj [
    ("baseline",toJson previous.toString),("sameActualBodyBytes",toJson same),
    ("baselineTrial",← read (project / "docs/candidates/packet-delivery-ledger/records/canonical-reader-hook/result.json")),
    ("candidateTrial",← read (trial / "result.json")),("tokenImprovementMeasured",toJson false)]).pretty
  let profile := root / "indexed-cpu-profile-checked"
  for file in ["result.json","audit.json","changed-views.json","profile.json","search.sample.txt",
      "sample.stdout","sample.stderr","handoff-trace.txt","shutdown.json","publisher-shutdown.json",
      "hook/record.json","hook/stdout","hook/stderr"] do
    copy? (profile / file) (records / "profile" / file)
  let profileSame := (← IO.FS.readBinFile (profile / "body.txt")) == (← IO.FS.readBinFile (trial / "body.txt"))
  IO.FS.writeFile (records / "profile-comparison.json") (Json.mkObj [
    ("sameActualBodyBytes",toJson profileSame),("profiledTiming",toJson true),
    ("unprofiled",← read (trial / "result.json")),("profiled",← read (profile / "result.json")),
    ("notAnAnsweringModelReplication",toJson true)]).pretty
  let unique := root / "unique-key-hook"
  for file in ["result.json","audit.json","changed-views.json","frozen-before-delivery.json","body.txt",
      "handoff-trace.txt","shutdown.json","publisher-shutdown.json","hook/record.json","hook/stdout","hook/stderr"] do
    copy? (unique / file) (records / "unique" / file)
  stages unique (records / "unique")
  let uniqueSame := (← IO.FS.readBinFile (unique / "body.txt")) == (← IO.FS.readBinFile (trial / "body.txt"))
  IO.FS.writeFile (records / "unique-comparison.json") (Json.mkObj [
    ("sameActualBodyBytes",toJson uniqueSame),("beforeKeyDedup",← read (trial / "result.json")),
    ("afterKeyDedup",← read (unique / "result.json")),("tokenImprovementMeasured",toJson false)]).pretty
  let artifacts ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts",(root / "product-build/StudyMain").toString]}
  unless artifacts.exitCode == 0 do throw (IO.userError artifacts.stderr)
  IO.FS.writeFile (records / "runtime.json") artifacts.stdout
  IO.FS.writeFile (records / "collection.json") (Json.mkObj [("modelCalls",toJson (0 : Nat)),
    ("newSeedStudy",toJson false),("candidate",toJson root.toString),("adopted",toJson false)]).pretty
