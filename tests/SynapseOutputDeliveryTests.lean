import Eggshell.Handoff
import Eggshell.SynapseJournal

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction
open Eggshell.Synapses.Journal Eggshell.Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def publish (source : DB.PageMap.Snapshot) (tool : ToolEvent) :
    IO (DB.PageMap.Snapshot × Synapses.Transport.Owner) := do
  let relation := (compileOperationOutcomes (.text "mcp-session") (.text "turn") tool).2
  let some owner := OutcomeEdge.fromValue? relation | throw (IO.userError "invalid native outcome")
  let _ ← DB.PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let id ← intern.root relation
    writeChange writer ⟨[id],[],false⟩
  return (← DB.PageMap.pin source.directory,⟨source.head.identity,owner,[]⟩)

private def packet (slices : List TransportSlice) : String :=
  "EGGSHELL\n" ++ "\n".intercalate (slices.map (·.text)) ++ "\nEND EGGSHELL"

private def cost (slices : List TransportSlice) : Nat × Nat :=
  (packet slices |>.length,packet slices |>.utf8ByteSize)

private def trial (rootPath : System.FilePath) (description : String) : IO Unit := do
  let base ← DB.PageMap.create rootPath "native-output-delivery"
  let record := Json.mkObj [("id",toJson "RECORD_42"),("description",toJson description)]
  let producer : ToolEvent := {
    name := "mcp__catalog__lookup",useId := "producer",input := "{}"
    response := (toJson #[record,Json.mkObj [("unrelated",toJson "UNSELECTED_SIBLING")]]).compress}
  let consumer : ToolEvent := {
    name := "mcp__catalog__inspect",useId := "consumer"
    input := (Json.mkObj [("record",toJson "RECORD_42")]).compress,response := "null"}
  let (source,original) ← publish base producer
  let (source,used) ← publish source consumer
  let occurrence := fun (tool : ToolEvent) => Occurrence.mk "mcp-session" "turn" tool.useId
  let known ← knowledge source [] false
  let domain := String.ofList (List.replicate 64 'a')
  let query := String.ofList (List.replicate 64 'b')
  let events := #[
    Entry.mk ⟨domain,10⟩ (.start (occurrence producer) (canonicalToolWork producer) query known),
    Entry.mk ⟨domain,20⟩ (.finish (occurrence producer) producer.name producer.input producer.response none),
    Entry.mk ⟨domain,30⟩ (.start (occurrence consumer) (canonicalToolWork consumer) query known),
    Entry.mk ⟨domain,40⟩ (.finish (occurrence consumer) consumer.name consumer.input consumer.response none)]
  let replayed ← replay source events ((← IO.monoMsNow)+5000)
  check (replayed.consumed.size == 1 && replayed.pending == 0 && replayed.unknown == 0)
    "native pre/post events did not form their exact consumption edge"
  let _ ← Index.replace source .database .shared replayed.consumed
  let prepared ← Recommend.prepare source true
  let before := source.head
  let plan ← Synapses.Transport.build #[prepared] #[(Persistence.selectionKey used.original.relation,0)]
    #[original,used] "" ((← IO.monoMsNow)+5000)
  check (plan.complete && plan.rows.isEmpty && plan.unsupported == 0)
    "non-source MCP output required file metadata"
  let mut families := []
  for owner in plan.owners do
    let ranges := (plan.outputRanges.find? (·.1 == owner.owner.relation)).map Prod.snd |>.getD []
    if ranges.isEmpty then continue
    let some raw := Matcher.atomText? owner.owner.outcome | throw (IO.userError "lost original output")
    let context : ContextDelivery := {
      owner := relationKey owner.owner.relation,outcome := relationKey owner.owner.outcome
      sourceChars := raw.length,cues := [],fragments := []
      leading := "WORK GRAPH " ++ relationKey owner.owner.relation ++ "\n  GROUNDED OUTCOME\n"
      trailing := "\n  TRACE\nEND WORK GRAPH"}
    let template : TransportSlice := {
      owner := some owner.owner.relation,keys := context.keys,text := context.render
      context := some context,members := [],visibleKeys := []}
    families := families ++ [{owner := owner.owner,template,windows := [],outputRanges := ranges}]
  check (families.length == 1) "the producer did not reach the actual selector"
  let some selected := SharedRangeAdapter.fit (120000,480000) cost families |
    throw (IO.userError "native original output failed the real packet cost")
  let body := packet selected.val
  let shown := presented body plan.documents plan.rows
  check (plan.owners.all fun owner => owner.outputs.all fun output => shown.coversBinding output.fragment.binding)
    "the selected MCP object was not acknowledged as its original bytes"
  check ((body.splitOn "UNSELECTED_SIBLING").length == 1 &&
      selected.val.all (fun slice => slice.members.isEmpty))
    "unrelated sibling data or new completion authority was introduced"
  let fragments := selected.val.flatMap fun slice => (slice.context.map (·.fragments)).getD []
  check (("".intercalate (fragments.map (·.original))) == record.compress &&
      fragments.all (fun fragment => fragment.original.length ≤ 2048))
    "large original objects were truncated or exceeded the receipt segment bound"
  check (selected.val.all fun slice =>
      (({keys := slice.keys,text := slice.text,context := slice.context} : DeliveryPart).remaining []).isSome)
    "the actual receipt reconciliation rejected an unacknowledged native fragment"
  check (selected.val.all fun slice =>
      (({keys := slice.keys,text := slice.text,context := slice.context} : DeliveryPart).remaining slice.keys).isNone)
    "acknowledged native output was offered again"
  check ((SharedRangeAdapter.fit (100,400) cost families).all (fun chosen => chosen.val.isEmpty))
    "insufficient budget split a complete native JSON object"
  check ((← DB.PageMap.pin source.directory).head == before) "selection changed the semantic graph"
  IO.FS.writeFile (rootPath.addExtension "delivery.txt") body
  IO.FS.writeFile (rootPath.addExtension "receipt.json") (plan.receipt body).pretty

def main (args : List String) : IO Unit := do
  let [rootPath] := args | throw (IO.userError "SynapseOutputDeliveryTests NEW-DIRECTORY")
  let root := System.FilePath.mk rootPath
  check (!(← root.pathExists)) "new fixture directory required"
  IO.FS.createDirAll root
  trial (root / "small.egg") "東京 } [ \" quoted"
  trial (root / "large.egg") (String.ofList (List.replicate 5000 'x'))
  IO.println "native MCP delivery passed: pre/post events, original JSON selection, exact receipts, long-output reconciliation, atomic budget admission and unchanged authority"
