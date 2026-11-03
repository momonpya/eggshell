import tools.research.PreparedOwnerChecks
import Eggshell.PluginCli
import Eggshell.FederatedDemand

open Lean Eggshell Eggshell.DB Eggshell.Plugin Eggshell.Persistence.Store
namespace Eggshell.Research.OwnerRouteChecks

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def all (parent child : Value) : IO AllEdge := do
  if valid : [child] ≠ [] ∧ parent ∉ [child] then return AllEdge.make parent [child] valid.1 valid.2
  else throw (IO.userError "invalid synthetic All edge")

private def source (path : System.FilePath) (values : List Value) : IO PageMap.Snapshot := do
  let snapshot ← PageMap.create path (Persistence.valueToJson (.text path.toString)).compress
  let _ ← PageMap.withWriter snapshot fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let added ← values.mapM intern.root
    writeChange writer {added,removed := [],unionsChanged := false}
  PageMap.pin path

def topology (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh topology fixture required"
  FileSystem.privateDirectory root
  let a := Value.text "A"
  let b := Value.text "B"
  let c := Value.text "C"
  let d := Value.text "D"
  let first ← all a b
  let second ← all b c
  let third ← all c d
  let unrelated ← all (.text "unrelated") (.text "unrelated child")
  let structured := Value.applyList .inquiry [(.exact,.text "structure")]
  let structural ← all structured (.text "structured child")
  let source0 ← source (root/"a.egg") [first.relation]
  let source1 ← source (root/"b.egg") [second.relation,structural.relation]
  let source2 ← source (root/"c.egg") [third.relation,first.relation,unrelated.relation]
  let sources := #[source0,source1,source2]
  let readers ← NodeReaders.new sources
  let joint ← FederatedDemand.new readers
  let reference ← Federated.prepare sources
  let unionSource ← source (root/"reference.egg") (reference.all.map (·.relation))
  let single ← DemandTopology.new (← NodeReader.new unionSource)
  let mut independent := []
  for snapshot in sources do
    let demand ← DemandTopology.new (← NodeReader.new snapshot)
    independent := independent++(← demand.read [] [a])
  check (!independent.contains second && !independent.contains third) "fixture does not distinguish local from joint closure"
  let expected ← single.read [] [a]
  check ((← joint.read [] [a]) == expected && expected == [first,second,third])
    "joint forward closure differs from the complete reference graph"
  for origin in [a,b,c,d,.text "absent"] do
    check ((← joint.neighborhood [] [origin]) == (← single.neighborhood [] [origin]))
      "joint bidirectional closure differs from complete reference"
  check ((← joint.read [] [structured]) == reference.all) "structured fallback omitted original topology"
  let alias := Value.text "alias A"
  let bridge := Value.text "bridge A"
  let authority0 ← authority source0
  let authority1 ← authority source1
  let edge0 : UnionEdge := ⟨alias,bridge,.workspace authority0,by intro _; rfl⟩
  let edge1 : UnionEdge := ⟨bridge,a,.workspace authority1,by intro _; rfl⟩
  let edges := [edge0,edge1]
  check ((← joint.read edges [alias]) == (← single.read edges [alias])) "cross-source Union aliases lost demand parents"
  let graph : WorkGraph := {all := reference.all,outcomes := []}
  let some view := RunView.make? graph (alias::bridge::a::b::c::d::reference.all.map (·.relation)) edges [] |
    throw (IO.userError "reference child quotient invalid")
  let actual ← joint.childLookup view
  let expectedChild ← single.childLookup view
  for work in [a,b,c,d,alias,bridge,structured,.text "structured child",.text "absent"] do
    check ((← actual work) == (← expectedChild work)) "global child membership differs from complete reference"
  let allocated ← sources.foldlM (init := 0) fun total snapshot => do return total+(← getNat snapshot.get "nodes")
  check (reference.semanticPopulation ≤ allocated) "allocated-domain fuel does not bound complete semantic population"
  let report := Json.mkObj [("allPassed",toJson true),("independentClosuresMissDownstream",toJson true),
    ("jointForwardBidirectionalAndChildEqual",toJson true),("duplicateAllAndStructuredFallback",toJson true),
    ("globalUnionAliasesEqual",toJson true),("completeSemanticPopulation",toJson reference.semanticPopulation),
    ("allocationFuelBound",toJson allocated),("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
  IO.println report.compress

private def evidence (marker : String) : Value :=
  (OutcomeEdge.make (.text ("inspect "++marker)) (.text ("original "++marker)) [.text ("dependency "++marker)]
    (by simp) (by simp [maxOutcomeObservations])).relation

private def append (snapshot : PageMap.Snapshot) (marker : String) : IO PageMap.Snapshot := do
  let _ ← PageMap.withWriter snapshot fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let id ← intern.root (evidence marker)
    writeChange writer {added := [id],removed := [],unionsChanged := false}
  PageMap.pin snapshot.directory

/-- A valid old/new combination is not necessarily a formerly completed
whole tuple. Every individual source remains warm and its originals intact. -/
def independentCuts (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh independent-cut fixture required"
  FileSystem.privateDirectory root
  let a0 ← source (root/"a.egg") [evidence "A0_MARKER"]
  let b0 ← source (root/"b.egg") [evidence "B0_MARKER"]
  let command := [(← IO.appPath).toString,"search-provider","--mode","lexical"]
  let _ ← Warm.run a0 command
  let _ ← Warm.run b0 command
  let a0 ← PageMap.pin a0.directory
  let b0 ← PageMap.pin b0.directory
  let _ ← OwnerViews.prepare #[a0,b0]
  let a1 ← append (← PageMap.pin a0.directory) "A1_MARKER"
  let _ ← Warm.run a1 command
  let a1 ← PageMap.pin a1.directory
  check ((← OwnerViews.load? #[a1,b0]).isSome) "normal A preparation did not publish its completed group"
  let b1 ← append (← PageMap.pin b0.directory) "B1_MARKER"
  let _ ← Warm.run b1 command
  let b1 ← PageMap.pin b1.directory
  check ((← OwnerViews.load? #[a1,b1]).isSome) "normal B preparation did not publish its completed group"
  let mixed := #[a0,b1]
  let inputs ← mixed.mapM fun snapshot => do
    let some input ← PreparedInputs.load? snapshot MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "an independently captured source is not actually warm")
    let _ ← PreparedInputs.lexical input snapshot
    return input
  let full ← Federated.prepare mixed
  check (full.owners.size == 3 && full.documents.length == 3) "complete original engine lost a valid mixed-cut owner"
  let missing ← OwnerViews.load? mixed
  check missing.isNone "fixture unexpectedly prepared the mixed whole tuple"
  let pending : PendingTurn := {
    sessionId := "mixed-cut",turnId := "turn",cwd := root.toString,
    prompt := "A0_MARKER B1_MARKER",profile := "work",read := [a0.directory.toString,b1.directory.toString],
    write := none,semanticMatcher := none,handoffChars := 120000,projection := .automatic}
  let request : Worker.Search := {
    pending,state := {profile := "work"},work := pending.prompt,enforce := false,
    deadline := (← IO.monoMsNow)+20000,prepared := some inputs,originals := some [some a0.head,some b1.head]}
  let some restored ← Worker.originalSnapshots request (pendingSelection pending) none |
    throw (IO.userError "valid mixed original boundary could not be restored")
  check (restored.map (·.map (·.head)) == [some a0.head,some b1.head]) "original restoration substituted latest"
  let mut refused := false
  try let _ ← Worker.capturePrepared request
  catch _ => refused := true
  check refused "candidate did not reproduce the whole-tuple admission defect"
  let old ← federatedDiscoveryReference (pendingSelection pending) (mixed.toList.map some) pending.prompt [] false none true
    (queryInputs := some inputs)
  let candidate ← computeAutomaticHandoff (pendingSelection pending) (mixed.toList.map some) pending.prompt [] false
    (queryInputs := some inputs)
  check (old.any (fun result => result.reason != "search-incomplete")) "complete reference cannot answer the diagnostic mixed cut"
  check (candidate.any (·.reason == "search-incomplete")) "candidate did not reject the missing completed tuple"
  let some referenceReply := old | throw (IO.userError "reference reply absent")
  check (referenceReply.text.contains "original A0_MARKER" && referenceReply.text.contains "original B1_MARKER")
    "reference reply did not contain both original evidence bodies"
  IO.FS.writeFile (root/"reference-output.json") ((toJson referenceReply).pretty++"\n")
  IO.FS.writeFile (root/"candidate-output.json") ((toJson candidate).pretty++"\n")
  let report := Json.mkObj [("diagnosticPassed",toJson true),("candidateRejected",toJson true),
    ("allIndividualSourcesPrepared",toJson true),("originalBoundaryRestoredExactly",toJson true),
    ("fullEngineOwnerCount",toJson full.owners.size),("fullEngineCandidateCount",toJson full.documents.length),
    ("referenceReason",toJson (old.map (·.reason))),("candidateReason",toJson (candidate.map (·.reason))),
    ("referenceOriginalBodiesDelivered",toJson true),("referenceBodySha256",toJson (Sha256.hex referenceReply.text.toUTF8)),
    ("wholeTupleMissing",toJson missing.isNone),("captureRejected",toJson refused),
    ("sourceCuts",toJson (mixed.map (·.head))),("individualInputs",toJson inputs),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]
  IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
  IO.println report.compress

end Eggshell.Research.OwnerRouteChecks

#print axioms Eggshell.Persistence.Store.FederatedDemand.distinct_original_bound

def main (args : List String) : IO UInt32 := do
  match args with
  | ["owner-topology",root] => Eggshell.Research.OwnerRouteChecks.topology (.mk root); return 0
  | ["owner-independent-cuts",root] => Eggshell.Research.OwnerRouteChecks.independentCuts (.mk root); return 0
  | ["egg","warm"] => IO.println (← Eggshell.Plugin.warm none); return 0
  | _ => preparedOwnerMain args
