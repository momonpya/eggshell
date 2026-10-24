import Eggshell.Handoff
import Eggshell.SynapseJournal

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction
open Eggshell.Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def publish (source : DB.PageMap.Snapshot) (session : String) (tool : ToolEvent) :
    IO (DB.PageMap.Snapshot × Synapses.Transport.Owner) := do
  let relation := (compileOperationOutcomes (.text session) (.text "turn") tool).2
  let some owner := OutcomeEdge.fromValue? relation | throw (IO.userError "invalid original")
  let _ ← DB.PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let id ← intern.root relation
    writeChange writer ⟨[id],[],false⟩
  return (← DB.PageMap.pin source.directory,⟨source.head.identity,owner,[]⟩)

private def row (owner : Synapses.Transport.Owner) (term : String) : IO Read := do
  let doc ← IO.ofExcept owner.document
  let raw := doc.source.getD ""
  let [leading,_] := raw.splitOn term | throw (IO.userError "unique fixture literal required")
  let producer := doc.occurrences[0]!
  let edge : Consumption := {
    producer,consumer := ⟨"next","turn","consumer"⟩,producerFinish := 1,consumerStart := 2
    kind := .identifier,term,inputFirst := 0,inputLimit := term.length
    outputFirst := leading.length,outputLimit := leading.length+term.length,outputFormat := .json}
  let some fragment := ObservationContext.locate? owner.database doc edge |
    throw (IO.userError "unlocated original field")
  let some read := fragment.read? | throw (IO.userError "invalid canonical data interval")
  return read.val

private def packet (slices : List TransportSlice) : String :=
  "EGGSHELL\n" ++ "\n".intercalate (slices.map (·.text)) ++ "\nEND EGGSHELL"

def main (args : List String) : IO Unit := do
  let [rootPath] := args | throw (IO.userError "SynapseSubjectTests NEW-DB")
  let root := System.FilePath.mk rootPath
  check (!(← root.pathExists)) "new fixture required"
  let source ← DB.PageMap.create root "canonical-native-data"
  let producer : ToolEvent := {
    name := "mcp__records__lookup",useId := "lookup",input := "{}"
    response := (Json.mkObj [("id",toJson "RECORD_42"),("status",toJson "READY_17")]).compress}
  let consumer : ToolEvent := {
    name := "mcp__records__inspect",useId := "inspect"
    input := (Json.mkObj [("id",toJson "RECORD_42")]).compress
    response := (Json.mkObj [("result",toJson "SUCCESS_23")]).compress}
  let (source,a) ← publish source "first" producer
  let (source,again) ← publish source "second" producer
  let (source,c) ← publish source "first" consumer
  let id ← row a "RECORD_42"
  let same ← row again "RECORD_42"
  let status ← row a "READY_17"
  let result ← row c "SUCCESS_23"
  check (id.source == same.source && id.binding.owner != same.binding.owner && id.source.file?.isNone)
    "separate sessions did not share one data identity with distinct real origins"
  check (!({id with binding := {id.binding with work := "wrong-work"}} : Read).valid)
    "a canonical data interval accepted a different Work"
  check (!({id.source with last := id.source.last+1000} : Range).valid)
    "an original interval escaped its immutable output extent"
  let originalDoc ← IO.ofExcept a.document
  check ((ObservationContext.bindSource? a.database
      {originalDoc with source := some (producer.response.replace "RECORD_42" "RECORD_43")} id.source).isNone &&
    (ObservationContext.bindSource? a.database {originalDoc with work := "different-work"} id.source).isNone)
    "a changed payload or Work acquired an old canonical binding"
  let trace : Trace := {}
  let trace ← IO.ofExcept (trace.start id.occurrence 1 producer.input .json)
  let trace ← IO.ofExcept (trace.finish id.occurrence 2 producer.response .json)
  let trace ← IO.ofExcept (trace.start result.occurrence 3 consumer.input .json)
  let trace ← IO.ofExcept (trace.finish result.occurrence 4 consumer.response .json)
  let trace ← IO.ofExcept (trace.locate (({} : Std.HashMap Occurrence (Array OutputRow)).insert id.occurrence
    #[⟨id.source,id.binding.first,id.binding.limit⟩]))
  let claim : Claim := ⟨source.head.identity,"answer",0,32⟩
  let support ← IO.ofExcept (Support.checked result result.source claim)
  let mut graph ← IO.ofExcept (Graph.ofFacts #[.read id,.read same,.read status,.read result,.supports support])
  graph ← IO.ofExcept (graph.merge trace.graph)
  for source in #[id.source,status.source,result.source] do
    graph ← IO.ofExcept (graph.insert (.coquoted (.claim claim) source))
    graph ← IO.ofExcept (graph.insert (.coquoted (.answer claim.database claim.answer) source))
  check (graph.rangeCount == 3 && (graph.sourceBindings id.source).size == 2)
    "data classes multiplied by session instead of accumulating origin witnesses"
  let relevant := graph.relevant #[claim]
  check (relevant.ranges.contains id.source && relevant.occurrences.contains id.occurrence)
    "native support did not seed reverse consumption"
  let query := String.ofList (List.replicate 64 'b')
  let usage ← IO.ofExcept ((Graph.empty.recordRead ⟨same.occurrence,0⟩ query id.source #[id.source] #[] true) >>= fun graph =>
    graph.recordCitation ⟨same.occurrence,1⟩ query id.source #[id.source])
  let counts := usage.usageCounts id.source
  check (counts.omittedThenRead == 1 && counts.deliveredThenCited == 1)
    "native usage was not accumulated at the canonical data interval"
  let _ ← Index.replace source .database .shared graph.snapshot
  let _ ← Index.replace source .user .usage usage.snapshot
  let prepared ← Recommend.prepare source true
  let before := source.head
  let plan ← Synapses.Transport.build #[prepared] #[("answer",0)] #[a,again,c] query ((← IO.monoMsNow)+5000)
  let offers := plan.results.flatMap (·.admitted)
  check (plan.complete && offers.any (fun offer => offer.target == .range id.source && offer.kind == "consumption") &&
      offers.any (fun offer => offer.target == .range status.source && offer.kind == "coquotation") &&
      offers.any (fun offer => offer.target == .range id.source && offer.kind == "omitted_then_read"))
    "persistent native derivation, coquotation or private usage failed to reach recommendation"
  check ((plan.outputRanges.flatMap (·.2)).length == 3 && (plan.ranges.flatMap (·.2)).isEmpty)
    "one canonical data interval was delivered twice or projected into a fake file"
  let families := plan.outputRanges.filterMap fun (owner,ranges) => do
    if ranges.isEmpty then none else do
      let original ← (#[a,again,c]).find? (·.original.relation == owner)
      some ({
        owner := original.original
        template := {owner := some owner,keys := [],text := "",members := [],visibleKeys := []}
        windows := []
        outputRanges := ranges} : SharedRangeAdapter.Family)
  let cost := fun slices => ((packet slices).length,(packet slices).utf8ByteSize)
  let some selected := SharedRangeAdapter.fit (120000,480000) cost families [] (Synapses.Bundles.project plan) |
    throw (IO.userError "canonical native relations failed the production selector")
  let body := packet selected.val
  let shown := presented body plan.documents plan.rows
  check ((#[id.source,status.source,result.source]).all (fun source => covered source shown.ranges))
    "recommended native intervals did not arrive as their original bytes"
  check (selected.val.all (·.members.isEmpty) && (← DB.PageMap.pin source.directory).head == before)
    "recommendation created authority or changed the original DB"
  IO.FS.writeFile (root.addExtension "delivery.txt") body
  IO.FS.writeFile (root.addExtension "receipt.json") (plan.receipt body).pretty
  IO.println "native subject checks passed: one data class across sessions, real origins, three persistent relations, private feedback, canonical delivery and no authority mutation"
