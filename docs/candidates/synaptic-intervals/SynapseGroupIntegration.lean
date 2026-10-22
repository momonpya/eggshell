import Eggshell.Handoff
import Eggshell.SynapseTransport

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

def main : IO Unit := do
  let file : File := ⟨"src/source.cpp", String.ofList (List.replicate 64 'c'), 1000⟩
  let work := Value.text ("shell\n" ++ (Json.mkObj [
    ("command", toJson "nl -ba src/source.cpp | sed -n '11,12p'")]).compress)
  let text := "    11\tif (condition)\n    12\t  dependent();\n"
  let output := Value.text text
  let event := Value.applyList .occurrence [Ref.semantic output, Ref.semantic work,
    Ref.exact (.text "session"), Ref.exact (.text "turn"), Ref.exact (.text "read")]
  let owner := OutcomeEdge.make work output [event] (by simp) (by simp [maxOutcomeObservations])
  let provenance : List SourceEvidence.Record := [{
    workspace := "/fixture", complete := true
    files := [⟨file.relative, some ⟨file.bytes, file.fingerprint⟩⟩]}]
  let original : Transport.Owner := ⟨"database", owner, provenance⟩
  let document ← IO.ofExcept original.document
  let rows ← IO.ofExcept (recordedRows "database" document)
  let read := {rows[0]! with
    source := ⟨file,11,12⟩
    binding := {rows[0]!.binding with limit := rows[1]!.binding.limit}}
  let support ← IO.ofExcept (Support.checked read read.source ⟨"database","answer",0,10⟩)
  let fact := Fact.supports support
  let some offer := Recommend.Offer.check? read.source 0 fact ⟨Index.contentKey fact,rfl⟩ |
    throw (IO.userError "missing checked original interval")
  let plan : Transport.Plan := {owners := #[⟨owner,Recommend.locate #[offer] rows⟩]}
  let some (_,ranges) := plan.ranges.head? | throw (IO.userError "no original row positions")
  let some (_,groups) := plan.groups.head? | throw (IO.userError "no original interval group")
  check (ranges.length == 2 && groups.length == 1 && groups[0]!.2.length == 2)
    "a two-row recommendation lost its shared evidence identity"
  let context : ContextDelivery := {
    owner := "owner", outcome := "outcome", sourceChars := text.length
    cues := [], leading := "begin\n", trailing := "end\n", fragments := []}
  let template : TransportSlice := {
    owner := some owner.relation,keys := [],text := "",members := []
    visibleKeys := [],context := some context}
  let family : SharedRangeAdapter.Family := {
    owner,template,windows := []
    synapticRanges := ranges,synapticGroups := groups,provenance}
  let (units,_) := SharedRangeAdapter.prepare 0 family
  check (!units.isEmpty && units.any (fun unit => groups[0]!.2.all fun (first,last) =>
      SharedRangeAdapter.covers unit.ranges first last))
    "synaptic-only evidence vanished or no candidate retained its complete interval"
  check (units.all (·.slice.members.isEmpty)) "advisory evidence manufactured native control"
  IO.println "Lean synaptic group integration passed: no numerical window required; complete two-row interval and original coordinates retained"
