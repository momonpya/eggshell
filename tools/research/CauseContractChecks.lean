import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter
open Eggshell.Synapses

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

#print axioms Cause.credited_requires_all
#print axioms Cause.credited_binding_invariant
#print axioms Cause.admitted_requires_same_reason
#print axioms Cause.admitted_requires_completion
#print axioms Cause.projection_preserves_cause
#print axioms Cause.association_is_independent
#print axioms Cause.omissions_do_not_imply_joint_dependencies
#print axioms Plan.keeps_control
#print axioms Plan.within_budget
#print axioms bundle_recipe_indexed_exact
#print axioms cached_cue_coefficients_compiled

private def digestText := String.ofList (List.replicate 64 'a')
private def original : Original := ⟨"read",digestText,200⟩
private def firstRange : Synapses.Range := .original original 0 20
private def secondRange : Synapses.Range := .original original 80 100
private def claim : Group := .claim ⟨"db","answer",10,30⟩
private def hint (kind : Nat) (target : Synapses.Range) (group : Option Group) : Routing.Store.Hint :=
  ⟨.range target,3,digestText,kind,group⟩

private def family (source : String) : Family := Id.run do
  let work := Value.text "mcp__records__read\n{}"
  let output := Value.text source
  let occurrence := Value.applyList .occurrence [Ref.semantic output,Ref.semantic work,
    Ref.exact (.text "test"),Ref.exact (.text "turn"),Ref.exact (.text "call")]
  let owner := OutcomeEdge.make work output [occurrence] (by simp) (by simp [maxOutcomeObservations])
  return {
    owner,template := {owner := some owner.relation,keys := [],text := "",members := [],visibleKeys := []}
    windows := [],original := some (OriginalStructure.prepare source)}

private def wire (slices : List TransportSlice) : Nat × Nat :=
  slices.foldl (fun sum slice =>
    (sum.1+slice.text.length+1,sum.2+slice.text.utf8ByteSize+1)) (0,0)

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "new result directory required")
  let root := System.FilePath.mk output
  check (!(← root.pathExists)) "preserve previous cause checks"
  IO.FS.createDir root
  let support := hint 0 firstRange (some claim)
  let requested := Cause.demands #[⟨"db",support⟩,⟨"db",{support with target := .range secondRange}⟩,
    ⟨"db",support⟩]
  let some demand := requested[0]? | throw (IO.userError "missing support demand")
  check (requested.size == 1 && demand.sources.size == 2 && demand.reason.joint)
    "a support reason lost a requirement or gained a duplicate"
  check (!demand.credited (· == firstRange) && demand.credited (fun _ => true))
    "partial support earned complete-reason credit"
  check (Cause.key? "other-db" support |>.isNone) "support crossed its recorded scope"
  let association := hint 2 firstRange (some claim)
  let independent := Cause.demands #[⟨"db",support⟩,⟨"db",association⟩,
    ⟨"db",{association with target := .range secondRange}⟩]
  check (independent.size == 3 && (independent.filter (·.reason.joint)).size == 1)
    "coquotation became a joint prerequisite or merged with support"
  let omitted := hint 3 firstRange none
  let uses := Cause.demands #[⟨"db",omitted⟩,⟨"db",{omitted with target := .range secondRange}⟩,
    ⟨"db",{omitted with kind := 4}⟩,⟨"db",{omitted with kind := 5}⟩]
  check (uses.size == 4 && uses.all (!·.reason.joint))
    "usage source or omitted/cited role was erased"
  let consumed := hint 1 firstRange none
  let consumption := Cause.demands #[⟨"db",consumed⟩,⟨"db",{consumed with target := .range secondRange}⟩]
  check (consumption.size == 1 && consumption[0]?.any (·.sources.size == 2))
    "consumption requirements were split before binding"
  let reason := demand.reason
  let projection : Cause.Projection := ⟨reason,0,20⟩
  check ((projection.rebind 100 120).cause == reason) "display binding changed a cause"
  let otherReason := Cause.outputKey "db" digestText
  check (Cause.admits [reason] reason true && !Cause.admits [reason] reason false &&
    !Cause.admits [reason] otherReason true) "credit crossed a reason or ignored completeness"

  let source := (Json.mkObj [("uri",toJson "mcp://server/resource"),
    ("content",toJson "opaque 日本語\nlast row")]).compress
  let outputCause := Cause.outputKey "db" digestText
  let outputRange : Transport.OutputRange := {
    priority := 0,first := 0,limit := source.length,path := none,cause := outputCause
    target := .output ⟨"test","turn","call"⟩}
  let outputCue : Transport.CausalRange := ⟨0,0,source.length,outputCause⟩
  let outputFamily := {family source with outputRanges := [outputRange],causalRanges := [outputCue]}
  let contextual := outputFamily.contextualOutputs
  let outputs := prepareOutputs 0 contextual
  let some whole := outputs.1.head? | throw (IO.userError "native opaque output disappeared")
  check (whole.localCauses.length == 1 && whole.coversPrepared 0 source.length &&
    whole.slice.members.isEmpty) "output requirements or control separation failed"
  let piece : CuePiece := {
    family := 0,first := 0,last := source.length,weight := 100,baseWeight := 0,causes := [outputCause]}
  let some p := problem [contextual] [whole] [piece] (0,0) (10000,10000) |
    throw (IO.userError "opaque source problem could not be constructed")
  let recipes := localOutputRecipes #[whole] [piece] (cueDirectory [piece]) p
  check (recipes.size == 1) "complete opaque output lost its independent data-flow recipe"
  let prefixUnit : UnitPlan := {
    family := whole.family,slice := whole.slice,ranges := [(0,source.length-1)],localCauses := whole.localCauses}
  check ((localOutputRecipes #[prefixUnit] [piece] (cueDirectory [piece]) p).isEmpty)
    "an incomplete output earned its complete native-fragment credit"
  let weaker := {piece with weight := 50}
  check ((strongestPieces (#[0,0],#[(0,100)]) [(weaker,0),(piece,1)]).map (·.2) == [1])
    "a weaker producer earned another producer's maximum shared-row value"
  let some associationCause := Cause.key? "db" association |
    throw (IO.userError "association has no scoped cause")
  let associated := {contextual with causalRanges := [⟨0,0,source.length,associationCause⟩]}
  check (!(baseRankedCues associated).isEmpty) "coquotation association stopped recommending its source"
  let some selected := plan (10000,10000) wire [outputFamily] |
    throw (IO.userError "opaque output failed the actual selection and final-budget path")
  check (selected.result.val.any fun slice => slice.context.any fun context =>
    context.fragments.any (fun fragment => fragment.first == 0 && fragment.original == source))
    "complete opaque payload was not materialized by the selector"
  IO.FS.writeFile (root / "result.json") (Json.mkObj [
    ("allPassed",toJson true),("completeRequirements",toJson true),("causeAndRolePreserved",toJson true),
    ("coquotationIndependentSignal",toJson true),("usageRolesDistinct",toJson true),
    ("opaqueNativeOutputCredit",toJson true),("partialAndWrongReasonRejected",toJson true),
    ("strongestSharedProducerChecked",toJson true),("selectorMaterializesOriginal",toJson true),
    ("modelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
