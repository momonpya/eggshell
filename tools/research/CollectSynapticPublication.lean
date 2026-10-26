import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))
private def write (path : System.FilePath) (value : String) : IO Unit := do
  IO.FS.createDirAll path.parent.get!
  if ← path.pathExists then
    unless (← IO.FS.readFile path) == value do throw (IO.userError s!"keep prior evidence: {path}")
  else IO.FS.writeFile path value
private def copyIf (source target : System.FilePath) : IO Unit := do
  if ← source.pathExists then write target (← IO.FS.readFile source)

private def commands (root : System.FilePath) : IO Json := do
  let mut result := #[]
  if !(← root.pathExists) then return toJson result
  for entry in ← root.readDir do
    if !(← entry.path.isDir) then continue
    if !(← (entry.path / "record.json").pathExists) then continue
    let mut fields := [("timing",← read (entry.path / "record.json"))]
    for name in ["stdin","stdout","stderr"] do
      if ← (entry.path / name).pathExists then fields := fields ++ [(name,toJson (← IO.FS.readFile (entry.path / name)))]
    result := result.push (entry.fileName,Json.mkObj fields)
  return toJson (result.qsort fun a b => a.1 < b.1)

def main (args : List String) : IO Unit := do
  let [mode] := args | throw (IO.userError "CollectSynapticPublication routing|receipt|prepared|payload")
  unless ["routing","receipt","prepared","payload","fold","leaf","sparse","dispatch"].contains mode do throw (IO.userError "known candidate required")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let name := if mode == "routing" then "synaptic-publication-delta" else if mode == "dispatch" then "incremental-dispatch" else if mode == "sparse" then "incremental-selection" else if mode == "leaf" then "bounded-leaf-encoding" else if mode == "fold" then "selector-weight-fold" else if mode == "payload" then "nonempty-source-payload" else if mode == "prepared" then "receipt-preparation" else "receipt-row-postings"
  let root := base / (name ++ "-20261027")
  let parent := base / (if mode == "routing" then "captured-correspondence-20261026" else if mode == "dispatch" then "incremental-selection-20261027" else if mode == "sparse" then "bounded-leaf-encoding-20261027" else if mode == "leaf" then "selector-weight-fold-20261027" else if mode == "fold" then "nonempty-source-payload-20261027" else if mode == "payload" then "receipt-preparation-20261027" else if mode == "prepared" then "receipt-row-postings-20261027" else "synaptic-publication-delta-20261027")
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates" / name
  let records := output / "records"
  let files := if mode == "routing" then #["Eggshell/SynapseIndex.lean","Eggshell/SynapseRecommend.lean",
    "Eggshell/SynapticRouting.lean","Eggshell/SynapticRoutingStore.lean","Eggshell/SynapticTransport.lean",
    "Eggshell/SynapticTopology.lean","Eggshell/SynapticTopologyStore.lean"]
    else if mode == "leaf" then #["Eggshell/DB/PageMap.lean"]
    else if mode == "fold" || mode == "sparse" || mode == "dispatch" then #["tools/DeferredCoverage.lean"]
    else if mode == "payload" then #["Eggshell/CanonicalSourceDelivery.lean","Eggshell/Handoff.lean","Eggshell/SynapseTransport.lean"]
    else if mode == "prepared" then #["Eggshell/SynapseTransport.lean","Eggshell/SynapseBundles.lean","tools/KeyPostings.lean"]
    else #["Eggshell/SynapseIndex.lean","Eggshell/SynapseUsage.lean","tools/SpanPostings.lean"]
  let response ← IO.FS.readFile (root / "product-build/runtime.rsp")
  let mut patch := ""
  for file in files do
    let stem := (file.dropEnd 5).toString.replace "/" "_"
    let source := root / "checkout" / file
    let object := root / "product-build" / (stem ++ ".o")
    let stamp ← read (root / "product-build" / (stem ++ ".source"))
    let fields ← IO.ofExcept stamp.getArr?
    unless (fields[0]?.bind (fun value => value.getStr?.toOption)) == some (← IO.FS.readFile source) &&
      (response.splitOn ((toJson object.toString).compress)).length == 2 &&
      (← (root / "product-build" / (stem ++ ".dependencies")).pathExists) do
      throw (IO.userError s!"source/object dependency boundary differs: {file}")
    for item in ← IO.ofExcept (fields[1]!.getArr?) do
      let (name,bytes) ← IO.ofExcept (fromJson? (α := String × String) item)
      unless bytes == (← IO.FS.readFile (source.parent.get! / name)) do throw (IO.userError "compiled include differs")
    let previous := parent / "checkout" / file
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
      (if ← previous.pathExists then previous.toString else "/dev/null"),source.toString]}
    unless diff.exitCode == 1 do throw (IO.userError s!"expected exact candidate change: {file}")
    patch := patch ++ diff.stdout
  write (output / "core.patch") patch
  if mode == "payload" then
    let file := "tests/CanonicalHookTests.lean"
    let stamp ← read (root / "canonical-build/tests_CanonicalHookTests.source")
    unless ((← IO.ofExcept stamp.getArr?)[0]!.getStr?).toOption == some (← IO.FS.readFile (root / "checkout" / file)) do
      throw (IO.userError "ported canonical fixture source differs from tested object")
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
      (parent / "checkout" / file).toString,(root / "checkout" / file).toString]}
    unless diff.exitCode == 1 do throw (IO.userError "expected exact ported canonical fixture")
    write (output / "test.patch") diff.stdout
  write (records / "link-boundary.json") (Json.mkObj [("files",toJson files),("sourceBytesExact",toJson true),
    ("includeBytesExact",toJson true),("selectedObjectsExact",toJson true),("dependencyClosuresPresent",toJson true)]).pretty
  let mut guards := #[]
  for entry in ← root.readDir do
    if !entry.fileName.endsWith ".guard.json" then continue
    let guard ← read entry.path
    unless (guard.getObjValAs? String "state").toOption == some "finished" &&
      (guard.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do throw (IO.userError "candidate still active")
    guards := guards.push (entry.fileName,guard)
  write (records / "guards.json") (toJson (guards.qsort fun a b => a.1 < b.1)).pretty
  for run in ["atomic-projection","actual-checkpoint","span-receipt","keyed-receipt","forced-receipt","original-domain-regression","exact-marginals","atomic-page-encoding","incremental-marginals","checked-incremental-marginals","shared-evaluation-marginals","public-entry-marginals"] do
    copyIf (root / run / "results.json") (records / run / "results.json")
  let native := root / "native-atomic-routing"
  copyIf (native / "routing-hook.json") (records / "native/routing-hook.json")
  for name in ["result.json","recovery.json","recall-audit.json","recall-body.txt","shutdown.json",
      "publisher-shutdown.json","recall-shutdown.json","recall-publisher-shutdown.json"] do
    copyIf (native / "native" / name) (records / "native" / name)
  if ← native.pathExists then write (records / "native/commands.json") (← commands (native / "native")).pretty
  let study := root / "fixed-source-hooks"
  for name in ["results.json","frozen-before-delivery.json","warm-complete.json","publisher-shutdown.json"] do
    copyIf (study / name) (records / "fixed-source" / name)
  if ← study.pathExists then
    write (records / "fixed-source/warm.json") (← commands study).pretty
    for topic in [1,2,3] do
      let path := study / s!"topic-{topic}"
      for name in ["audit.json","body.txt","shutdown.json"] do copyIf (path / name) (records / "fixed-source" / s!"topic-{topic}" / name)
      write (records / "fixed-source" / s!"topic-{topic}/hook.json") (← commands path).pretty
    write (records / "profile/hook.json") (← commands (study / "profile-topic-2")).pretty
    for label in ["selection","render","warm"] do
      copyIf (study / (label ++ "-sample-process.json")) (records / "profile" / (label ++ "-sample-process.json"))
      let sample := study / (label ++ ".sample")
      if ← sample.pathExists then
        let frames := ((← IO.FS.readFile sample).splitOn "\n").filter (fun line =>
          ["l_Eggshell_","l_SharedCoverage_","l_List_fold"].any (fun text => line.contains text))
        write (records / "profile" / (label ++ ".frames.txt")) ("\n".intercalate (frames.take 140) ++ "\n")
  for name in ["isolated-warm-profile.stdout","isolated-warm-profile.stderr"] do
    copyIf (root / name) (records / "profile" / name)
  copyIf (root / "source-trace.json") (records / "source-trace.json")
  copyIf (root / "native-selector-dispatch.json") (records / "native-selector-dispatch.json")
  for name in ["repeated-evaluation-attempt.patch","repeated-evaluation-runtime.json","repeated-evaluation.frames.txt"] do
    copyIf (root / name) (records / "failed-attempt" / name)
  let explained := root / "missing-unit-explanation"
  if ← explained.pathExists then
    for entry in ← explained.readDir do
      if entry.fileName.endsWith ".json" then copyIf entry.path (records / "explanation" / entry.fileName)
  for name in ["Eggshell_ContractAudit-lean.stdout","tests_FullSearchOracle-lean.stdout",
      "tools_research_SynapticPublicationContract-lean.stdout","tools_research_ReceiptPreparationContract-lean.stdout"] do
    copyIf (root / "contract-build" / name) (records / "contracts" / name)
  copyIf (root / "receipt-audit-build/tools_research_ReceiptPostingsAudit-lean.stdout") (records / "contracts/span-postings.stdout")
  copyIf (root / "receipt-audit-build/tools_research_ReceiptPreparationAudit-lean.stdout") (records / "contracts/key-postings.stdout")
  copyIf (root / "audit-build/tools_research_NonemptySourcePayloadAudit-lean.stdout") (records / "contracts/nonempty-payload.stdout")
  copyIf (root / "canonical-native.stdout") (records / "contracts/canonical-native.stdout")
  copyIf (root / "canonical-independent-row-native.stdout") (records / "contracts/canonical-independent-row-native.stdout")
  copyIf (root / "canonical-checked-payload-native.stdout") (records / "contracts/canonical-checked-payload-native.stdout")
  copyIf (root / "audit-build/tools_research_SelectorFoldAudit-lean.stdout") (records / "contracts/weight-fold.stdout")
  copyIf (root / "audit-build/tools_research_PageEncodingAudit-lean.stdout") (records / "contracts/bounded-page-encoding.stdout")
  copyIf (root / "audit-build/tools_research_IncrementalSelectionAudit-lean.stdout") (records / "contracts/incremental-selection.stdout")
  copyIf (root / "audit-build/tools_research_IncrementalSelectionAudit.source") (records / "contracts/audit-source.json")
  let artifact ← IO.Process.output {
    cmd := (base / "study-services-20261026/assessed-controller").toString
    args := #["artifacts",(root / "product-build/StudyMain").toString]}
  unless artifact.exitCode == 0 do throw (IO.userError artifact.stderr)
  write (records / "runtime.json") artifact.stdout
  write (records / "collection.json") (Json.mkObj [("parent",toJson parent.toString),
    ("answeringModelCalls",toJson (0 : Nat)),("answeringStages",toJson (0 : Nat)),
    ("newSeedStudy",toJson false),("productionAdoption",toJson false),("archivesCreated",toJson false)]).pretty
