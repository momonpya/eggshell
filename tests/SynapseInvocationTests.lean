import Eggshell.SynapseJournal

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction
open Eggshell.Synapses.Journal Eggshell.Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def call (name id : String) (input output : Json) : Plugin.ToolEvent :=
  ⟨name,id,input.compress,output.compress,none⟩

private def store (source : DB.PageMap.Snapshot) (tool : Plugin.ToolEvent) : IO DB.PageMap.Snapshot := do
  let outcome := (Plugin.compileOperationOutcomes (.text "mcp-session") (.text "turn") tool).2
  let _ ← DB.PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let id ← intern.root outcome
    writeChange writer ⟨[id],[],false⟩
  DB.PageMap.pin source.directory

def main (args : List String) : IO Unit := do
  let [rootPath] := args | throw (IO.userError "SynapseInvocationTests NEW-DIRECTORY")
  check (!(← (System.FilePath.mk rootPath).pathExists)) "new fixture directory required"
  let query := String.ofList (List.replicate 64 'b')
  let domain := String.ofList (List.replicate 64 'a')
  let producer := call "mcp__catalog__lookup" "lookup"
    (Json.mkObj [("filters",Json.mkObj [("city",toJson "東京")])])
    (toJson #[Json.mkObj [("id",toJson "RECORD_42"),("status",toJson "available")]])
  let consumer := call "mcp__catalog__inspect" "inspect"
    (Json.mkObj [("request",Json.mkObj [("record",toJson "RECORD_42")])])
    (Json.mkObj [("record",toJson "RECORD_42"),("size",toJson (17 : Nat))])
  let work := Plugin.canonicalToolWork consumer
  check ((← IO.ofExcept (invocationInput work)) == consumer.input)
    "MCP invocation lost its complete structured arguments"
  let values ← IO.ofExcept (payloadOccurrences .json consumer.input)
  check (values.all (fun term => term.text != "record" && term.text != "request"))
    "object keys became argument witnesses"
  check ((workCommand work).toOption.isNone) "non-shell fixture unexpectedly became a source-reader command"
  let withCommand := {consumer with input := (Json.mkObj [
    ("command",toJson "server-side operation"),("cursor",toJson (73 : Nat))]).compress}
  check ((← IO.ofExcept (invocationInput (Plugin.canonicalToolWork withCommand))) == withCommand.input)
    "a command field discarded the other MCP arguments"
  for response in [producer.response,consumer.response,"null","42","true"] do
    let view ← IO.ofExcept (layout response)
    check (view.text == response && view.original == response &&
      view.offsets == Array.range (response.length+1)) "structured result was dropped or rewritten"
  let base ← DB.PageMap.create (.mk rootPath) "mcp-invocation-fixture"
  let source ← store (← store base producer) consumer
  let occurrence := fun (tool : Plugin.ToolEvent) => Occurrence.mk "mcp-session" "turn" tool.useId
  let _ ← Build.refresh source .database
  let known ← knowledge source [] false
  let events := #[
    Entry.mk ⟨domain,10⟩ (.start (occurrence producer) (Plugin.canonicalToolWork producer) query known),
    Entry.mk ⟨domain,20⟩ (.finish (occurrence producer) producer.name producer.input producer.response none),
    Entry.mk ⟨domain,30⟩ (.start (occurrence consumer) work query known),
    Entry.mk ⟨domain,40⟩ (.finish (occurrence consumer) consumer.name consumer.input consumer.response none)]
  let result ← replay source events ((← IO.monoMsNow)+5000)
  check (result.unknown == 0 && result.pending == 0 && result.origins.size == 2 && result.consumers.size == 2)
    "MCP calls did not retain their complete native provenance"
  let edges := result.consumed.filterMap fun fact => match fact with
    | .consumed edge => some edge | _ => none
  check (edges.size == 1 && edges.all (fun edge => edge.kind == .value &&
    edge.term == (toJson "RECORD_42").compress && !edge.rows.isEmpty && edge.rows.all (·.file?.isNone) &&
    edge.producer == occurrence producer && edge.consumer == occurrence consumer))
    "structured MCP output did not produce its exact argument-consumption witness"
  let altered := {consumer with name := "mcp__different_server__inspect"}
  let invalid := events.extract 0 3 |>.push
    ⟨⟨domain,40⟩,.finish (occurrence consumer) altered.name altered.input altered.response none⟩
  let rejected ← try
    let _ ← replay source invalid ((← IO.monoMsNow)+5000)
    pure false
    catch _ => pure true
  check rejected "different tool with identical arguments replaced the original invocation"
  IO.println "MCP invocation checks passed: nested arguments, structured results, exact producer/consumer and tool identity"
