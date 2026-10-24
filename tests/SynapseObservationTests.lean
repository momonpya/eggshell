import Eggshell.SynapseJournal
import Eggshell.SynapseTransport

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction
open Eggshell.Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def occurrence (name : String) : Occurrence := ⟨"observations","turn",name⟩

private def edge (text : String) (structured : Bool := false) : Consumption := Id.run do
  let [leading,_] := text.splitOn "RECORD_42" | panic! "unique fixture value required"
  return {
    producer := occurrence "producer",consumer := occurrence "consumer"
    producerFinish := 10,consumerStart := 20,kind := .identifier,term := "RECORD_42"
    inputFirst := 0,inputLimit := 9,outputFirst := leading.length,outputLimit := leading.length+9
    outputFormat := if structured then .json else .text}

private def nativeDocument (raw : String) : Document := {
  owner := "original-owner",work := "original-work",workText := some "mcp__catalog\n{}"
  source := some raw,native := true,occurrences := #[occurrence "producer"],files := #[]}

private def checkContexts : IO Unit := do
  let record := Json.mkObj [("id",toJson "RECORD_42"),("status",toJson "ready"),
    ("description",toJson "東京 } [ \" quoted")]
  let serialized := (toJson #[record,Json.mkObj [("unrelated",toJson "do not deliver")]]).compress
  let doc := nativeDocument serialized
  let some found := ObservationContext.locate? "database" doc (edge serialized true) |
    throw (IO.userError "MCP object with no file metadata was rejected")
  check (found.payload == "\"id\":\"RECORD_42\"" &&
      found.address.any (·.label == "[0,\"id\"]"))
    "a field lost its ancestor path or copied unrelated fields"
  check (found.binding.owner == doc.owner && found.binding.work == doc.work)
    "context escaped its original native owner"
  for text in ["prefix\nRECORD_42 active\nsuffix\n","🙂 prefix\nRECORD_42 active\n終わり\n"] do
    for raw in [text,(toJson text).compress,(Json.mkObj [("stdout",toJson text)]).compress] do
      let some found := ObservationContext.locate? "database" (nativeDocument raw) (edge text) |
        throw (IO.userError "Unicode text context disappeared")
      let payload := if raw == text then some found.payload else
        (Json.parse ("\"" ++ found.payload ++ "\"") >>= Json.getStr?).toOption
      check (payload == some "RECORD_42 active\n") "encoded offsets changed the original text row"
  check ((ObservationContext.locate? "database" {doc with occurrences := #[]} (edge serialized true)).isNone)
    "an unrelated invocation acquired an output fragment"
  check ((ObservationContext.locate? "database" {doc with native := false} (edge serialized true)).isNone)
    "a non-native answer became a native tool result"
  check ((ObservationContext.locate? "database" doc {edge serialized true with term := "RECORD_43"}).isNone)
    "different saved output passed its literal witness"
  let binding := found.binding
  let packet := "\nWORK GRAPH " ++ doc.owner ++ "\n  GROUNDED OUTCOME\n  JSON PATH [0,\"id\"]\n  ORIGINAL CHARS [" ++
    toString binding.first ++ "," ++ toString binding.limit ++ ")\n" ++ found.payload ++ "\n  TRACE\n"
  let shown := presented packet #[doc] #[]
  check (shown.coversBinding binding && shown.ranges.isEmpty && shown.uncertain.isEmpty)
    "non-file data was not counted independently of source lines"
  check (shown.coversAddress binding [.index 0,.key "id"])
    "the original JSON address was not acknowledged"
  check (!(presented (packet.replace "RECORD_42" "RECORD_43") #[doc] #[]).coversBinding binding)
    "tampered output was counted as delivered"
  check (!(presented (packet.replace "[0,\"id\"]" "[1,\"id\"]") #[doc] #[]).coversBinding binding)
    "unchanged bytes with a fabricated ancestor path were counted as delivered"
  let split := binding.first+(binding.limit-binding.first)/2
  let joined : Presentation := {bindings := #[(doc.owner,binding.first,split),(doc.owner,split,binding.limit)]}
  check (joined.coversBinding binding) "two exact adjacent packet fragments did not cover their original"
  let gap := {joined with bindings := #[(doc.owner,binding.first,split),(doc.owner,split+1,binding.limit)]}
  check (!gap.coversBinding binding) "a hole in delivered bytes was hidden"

private def publish (source : DB.PageMap.Snapshot) (tool : Plugin.ToolEvent) : IO (DB.PageMap.Snapshot × Transport.Owner) := do
  let relation := (Plugin.compileOperationOutcomes (.text "observations") (.text "turn") tool).2
  let some original := OutcomeEdge.fromValue? relation | throw (IO.userError "invalid native fixture")
  let _ ← DB.PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let id ← intern.root relation
    writeChange writer ⟨[id],[],false⟩
  return (← DB.PageMap.pin source.directory,⟨source.head.identity,original,[]⟩)

def main (args : List String) : IO Unit := do
  checkContexts
  let [rootPath] := args | throw (IO.userError "SynapseObservationTests NEW-DB")
  check (!(← (System.FilePath.mk rootPath).pathExists)) "new fixture required"
  let source ← DB.PageMap.create (.mk rootPath) "generic-observation-fixture"
  let producer : Plugin.ToolEvent := {
    name := "mcp__catalog__lookup",useId := "producer",input := "{}"
    response := (toJson #[Json.mkObj [("id",toJson "RECORD_42"),("status",toJson "ready")],
      Json.mkObj [("unrelated",toJson "do not deliver")]]).compress}
  let consumer : Plugin.ToolEvent := {
    name := "mcp__catalog__inspect",useId := "consumer"
    input := (Json.mkObj [("id",toJson "RECORD_42")]).compress,response := "null"}
  let (source,original) ← publish source producer
  let (source,used) ← publish source consumer
  let fact := Fact.consumed (edge producer.response true)
  let _ ← Index.replace source .database .shared #[fact]
  let prepared ← Recommend.prepare source true
  let before := source.head
  let plan ← Transport.build #[prepared] #[(Persistence.selectionKey used.original.relation,0)]
    #[original,used] "" ((← IO.monoMsNow)+5000)
  check (plan.complete && plan.rows.isEmpty && plan.unsupported == 0 && plan.unlocatedFileOwners == 0)
    "valid MCP data still required a source file"
  let parts := plan.owners.flatMap fun owner => owner.outputs.map (fun output => output.fragment.payload)
  check (parts == #["\"id\":\"RECORD_42\""])
    "native data-flow context did not reach the transport plan independently of sibling fields"
  check ((plan.outputRanges.flatMap (·.2)).length == 1 &&
    (← DB.PageMap.pin source.directory).head == before) "planning invented authority or lost native coordinates"
  IO.println "generic observation checks passed: JSON context, Unicode offsets, literal/origin validation, byte receipts and MCP transport"
