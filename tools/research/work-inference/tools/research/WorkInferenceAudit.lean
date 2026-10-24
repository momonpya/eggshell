import Eggshell.WorkInference
import Eggshell.CandidateDomain
import tests.FullSearchOracle

open Lean Eggshell Eggshell.Persistence.Store Eggshell.Matcher

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def coverage (value : Coverage) : String := reprStr value

private def alignment (work : WorkAlignment) : Json := Json.mkObj [
  ("prior",toJson (coverage work.priorInDemand)),("demand",toJson (coverage work.demandInPrior)),
  ("subwork",toJson work.subwork),("wholePast",toJson work.pastWholeWork),
  ("wholeIdentity",toJson work.wholeWorkIdentity),("fragmentIdentity",toJson work.fragmentIdentity),
  ("current",Persistence.valueToJson work.currentFragment),("past",Persistence.valueToJson work.pastFragment),
  ("currentSpan",toJson (work.currentSpan.start,work.currentSpan.stop)),
  ("pastSpan",toJson (work.pastSpan.start,work.pastSpan.stop))]

private def sameProposal (left right : Option UnionEdge) : Bool :=
  decide (left = right)

@[noinline] private def workPass (inputs : List (WorkInference.Input Nat)) (view : RunView)
    (corpus : Corpus) (current : Value) (query : CompiledDemand LogicalText.logicalNormalizer text native) :
    IO (List (WorkInference.Prepared Nat)) :=
  pure (WorkInference.pass inputs pairedCoverages view.quotient {corpus with candidates := []}
    current query.pattern query.workPatterns native)

@[noinline] private def oraclePass (view : RunView) (corpus : Corpus) (current : Value)
    (query : CompiledDemand LogicalText.logicalNormalizer text native)
    (evidence : Option String) (semantic : SemanticNominations) : IO (List Match) :=
  pure (TestOracle.findInUsingBeforeWorkGate LogicalText.logicalNormalizer
    (demandProvider LogicalText.logicalNormalizer text native query) pairedCoverages
    view.quotient corpus current text evidence semantic native)

private def runCase (inputs : List (WorkInference.Input Nat)) (owners : List OutcomeEdge)
    (text : String) (native : Bool) (nominated : List Nat) (evidence : Option String := none)
    (frequency : String → Nat := fun _ => 1) (children : Bool := false) : IO Json := do
  check (inputs.length == owners.length) "source domain differs"
  let current := Value.text text
  let graph : WorkGraph := {outcomes := owners}
  let some view := RunView.make? graph (current :: inputs.map (·.view.value)) [] [] |
    throw (IO.userError "cannot construct fixed Work quotient")
  let candidates := owners.filterMap (Corpus.compileCandidate LogicalText.logicalNormalizer)
  let corpus : Corpus := {
    candidates, population := owners.length, frequency
    subworks := if children then inputs.map (·.view.value) else [] }
  let semantic : SemanticNominations := {
    related := nominated.filterMap fun i => (owners[i]?).map (·.relation) }
  let inputs := inputs.zipIdx |>.map fun (input,index) => {input with retrieved := nominated.contains index}
  let query := CompiledDemand.make LogicalText.logicalNormalizer text native
  let started ← IO.monoMsNow
  let actual ← workPass inputs view corpus current query
  let count := actual.length
  let workPassMs := (← IO.monoMsNow)-started
  let started ← IO.monoMsNow
  let expected ← oraclePass view corpus current query evidence semantic
  check (count == expected.length) "Work-only comparison domain differs from the frozen complete oracle"
  let mut proposals := 0
  let mut retrieved := 0
  let mut pairs : Std.HashSet (Value × Value) := {}
  let mut inert := 0
  let mut comparedOwners : Std.HashSet Nat := {}
  let mut activeOwners : Std.HashSet Nat := {}
  for (row,matched) in actual.zip expected do
    check (alignment row.work == alignment matched.work && row.retrieved == matched.retrieved)
      "ordered Work alignment differs from the frozen oracle"
    let actualProposal := row.propose view.quotient current
    let expectedProposal := Matcher.localUnion? view.quotient current matched
    check (sameProposal actualProposal expectedProposal) "a complete Work-only Union proposal differs"
    comparedOwners := comparedOwners.insert row.source
    if row.inert view.quotient current then
      inert := inert+1
      check (!matched.automatic && actualProposal.isNone) "inert Work had a matcher effect"
    else activeOwners := activeOwners.insert row.source
    if let some edge := actualProposal then
      proposals := proposals+1
      pairs := pairs.insert (edge.left,edge.right)
    if row.retrieved then
      retrieved := retrieved+1
      check actualProposal.isNone "retrieval granted Union authority"
  return Json.mkObj [
    ("query",toJson text),("native",toJson native),("evidence",toJson evidence.isSome),
    ("children",toJson children),("inertAlignments",toJson inert),
    ("inertOwners",toJson (comparedOwners.size-activeOwners.size)),
    ("owners",toJson owners.length),("alignments",toJson count),("proposals",toJson proposals),
    ("directedProposalPairs",toJson pairs.size),
    ("retrievedAlignments",toJson retrieved),("workPassMs",toJson workPassMs),
    ("oracleAndComparisonMs",toJson ((← IO.monoMsNow)-started)),
    ("allOrderedAlignmentsEqual",toJson true),("allOrderedProposalsEqual",toJson true)]

private def fixtures : IO (List Json) := do
  let works := ["inspect alpha clock kernel", "alpha clock source", "unrelated banana",
    "exec_command\n{\"cmd\":\"sed -n '1,5p' driver.c; rg clock driver.c\"}",
    "mcp__issues__get\n{\"issue\":42}","alpha-clock"]
  let bodies := ["alpha clock original", "clock source observation", "banana output",
    "driver.c:1 clock branch", "{\"id\":42,\"title\":\"alpha clock\"}","alpha clock original"]
  let owners := works.zip bodies |>.zipIdx |>.map fun ((work,body),index) =>
    let work := Value.text work
    let body := Value.text body
    if index == 3 || index == 4 then OutcomeEdge.make work body
      [.applyList .occurrence [.semantic body,.semantic work]] (by simp) (by simp [maxOutcomeObservations])
    else OutcomeEdge.make work body [] (by simp) (by simp)
  let inputs ← owners.zipIdx.mapM fun (owner,index) => do
    let some view := WorkView.compile LogicalText.logicalNormalizer owner.work (nativeOutcome owner) |
      throw (IO.userError "nontextual fixture")
    pure ({source := index,view,retrieved := false} : WorkInference.Input Nat)
  let mut rows := []
  for question in ["alpha clock", "inspect alpha clock kernel", "no matching quantum", works[3]!, works[4]!] do
    for native in [false,true] do
      for children in [false,true] do
        rows := (← runCase inputs owners question native [2]
          (if native then some "driver.c:1 clock" else none) (fun _ => 1) children) :: rows
  return rows.reverse

def main (args : List String) : IO Unit := do
  let [database,output] := args | throw (IO.userError "WorkInferenceAudit DB NEW-OUTPUT")
  let output := System.FilePath.mk output
  check (!(← output.pathExists)) "keep earlier Work-inference evidence"
  FileSystem.privateDirectory output
  let source ← DB.PageMap.pin (.mk database)
  let some domain ← CandidateDomain.openShared? source | throw (IO.userError "prepared source domain required")
  let reader ← NodeReader.new source
  source.cache.set {}
  source.reads.set 0
  source.readBytes.set 0
  let started ← IO.monoMsNow
  let mut loaded : Array (WorkInference.Input WorkInference.Address) := #[]
  let mut observedBodies : Std.HashSet String := {}
  for row in domain.data.rows do
    source.trace.set (some {})
    let input ← WorkInference.load reader row.owner
    let some trace ← source.trace.get | throw (IO.userError "missing original Work trace")
    check trace.complete "incomplete original Work trace"
    for operation in trace.operations do
      match operation with
      | .payload name .. => observedBodies := observedBodies.insert name
      | _ => pure ()
    loaded := loaded.push input
  source.trace.set none
  let loadWorkMs := (← IO.monoMsNow)-started
  let workPageReads ← source.reads.get
  let workReadBytes ← source.readBytes.get
  let workBodies : Std.HashSet Nat := Std.HashSet.ofList (loaded.toList.map (·.source.work))
  let resultReads := loaded.toList.filter fun input =>
    !workBodies.contains input.source.outcome && observedBodies.contains (key "body" input.source.outcome)
  check resultReads.isEmpty "this source's Work pass eagerly read result bodies"
  let started ← IO.monoMsNow
  let owners ← domain.data.rows.mapM fun row => do reader.outcome (← reader.locateOutcome row.owner)
  let loadOutcomeMs := (← IO.monoMsNow)-started
  let inputs := loaded.toList.map fun input => ({
    source := input.source.owner,view := input.view,retrieved := false } : WorkInference.Input Nat)
  let mut cases := []
  for text in ["kernel realtime clock monotonic scheduling elapsed timers", "no matching quantum"] do
    let query := CompiledDemand.make LogicalText.logicalNormalizer text false
    let wanted := hashDistinct (inputs.flatMap fun input => Corpus.workScoringTerms input.view query)
    let weights ← frequencies source wanted
    cases := (← runCase inputs owners text false [0] none (weights.getD · 0)) :: cases
  let fixtures ← fixtures
  check ((← DB.PageMap.pin source.directory).head == source.head) "source facts changed"
  let result := Json.mkObj [
    ("source",toJson source.head),("owners",toJson inputs.length),
    ("loadWorkMs",toJson loadWorkMs),("workPhysicalPageReads",toJson workPageReads),
    ("workPhysicalReadBytes",toJson workReadBytes),("resultBodyPayloadReads",toJson resultReads.length),
    ("laterOutcomeHydrationMs",toJson loadOutcomeMs),("cases",toJson cases.reverse),
    ("fixtures",toJson fixtures),("sourceUnchanged",toJson true),
    ("fullHookMeasured",toJson false),("completeDiscoveryFixpointProved",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output / "result.json") result.pretty
  IO.println result.compress
