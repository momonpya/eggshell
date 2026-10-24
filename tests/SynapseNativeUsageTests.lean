import Eggshell.SynapseLive
import Eggshell.SynapseRecommend

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction
open Eggshell.Synapses.Journal Eggshell.Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def domain : String := String.ofList (List.replicate 64 'a')
private def query : String := String.ofList (List.replicate 64 'b')
private def occurrence (name : String) : Occurrence := ⟨"live","turn",name⟩

private def readTool (name : String) (id := "ID_ALPHA") : ToolEvent := {
  name := "mcp__catalog__invoke",useId := name,input := "{\"key\":\"one\"}"
  response := (Json.mkObj [("id",toJson id),("unused",toJson "UNUSED_VALUE"),
    ("tail",toJson "TAIL_BETA")]).compress}

private def useTool (name value : String) : ToolEvent := {
  name := "mcp__catalog__use",useId := name
  input := (Json.mkObj [("selected",toJson value),("private",toJson "PRIVATE_ARGUMENT_NEVER_SHARED")]).compress
  response := (toJson "CONSUMER_DONE").compress}

private def publish (source : DB.PageMap.Snapshot) (session : String) (tool : ToolEvent) :
    IO (DB.PageMap.Snapshot × OutcomeEdge) := do
  let relation := (compileOperationOutcomes (.text session) (.text "turn") tool).2
  let some edge := OutcomeEdge.fromValue? relation | throw (IO.userError "invalid fixture")
  let _ ← DB.PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let id ← intern.root relation
    writeChange writer ⟨[id],[],false⟩
  return (← DB.PageMap.pin source.directory,edge)

private def events (tool : ToolEvent) (known : Knowledge) (time : Nat)
    (archive : Option String) : Array Entry := #[
  ⟨⟨domain,time⟩,.start (occurrence tool.useId) (canonicalToolWork tool) query known,none⟩,
  ⟨⟨domain,time+1⟩,.finish (occurrence tool.useId) tool.name tool.input tool.response archive,none⟩]

private def usageFacts (source : DB.PageMap.Snapshot) : IO (Array Usage) := do
  let some ready ← Index.open? source .user .usage | return #[]
  return (← Index.allFacts ready.index).filterMap fun fact => match fact with
    | .used usage => some usage
    | _ => none

structure Case where
  label : String
  ack : String := "none"
  privateWork : Bool := false
  uncertain : Bool := false
  missingIndex : Bool := false
  priorData : Bool := true
  consumed : Bool := true
  ambiguous : Bool := false
  appendLater : Bool := false
  lateAck : Bool := false
  archiveRetraction : Bool := false

private def trial (root : System.FilePath) (spec : Case) : IO Json := do
  let base ← DB.PageMap.create (root / "memory.egg") "native-usage-memory"
  let (source,seed) ← publish base "seed" (readTool "seed" (if spec.priorData then "ID_ALPHA" else "OTHER_ID"))
  let _ ← Build.refresh source .database
  let reader ← NodeReader.new source
  let some id ← findNode? source seed.relation | throw (IO.userError "missing seed")
  let doc ← Build.document reader id
  let some catalog := ObservationContext.recorded source.head.identity doc | throw (IO.userError "missing native catalog")
  let some needed := (catalog.located.map (·.read)).find? (·.quotations.contains (Quotes.digest (if spec.priorData then "ID_ALPHA" else "OTHER_ID"))) |
    throw (IO.userError "missing native id")
  let key := fun a b => s!"e:{doc.owner}:{Persistence.selectionKey (.text (doc.source.getD ""))}:{a}:{b}"
  let split := (needed.binding.first+needed.binding.limit)/2
  let keys := match spec.ack with
    | "whole" => ["h:" ++ doc.owner]
    | "split" => [key needed.binding.first split,key split needed.binding.limit]
    | "hole" => [key needed.binding.first split,key (split+1) needed.binding.limit]
    | _ => []
  let archive ← if spec.privateWork then pure (some (← DB.PageMap.create (root / "private.egg") "native-private-work")) else pure none
  let archive ← if spec.archiveRetraction then do
      let some saved := archive | throw (IO.userError "archive fixture required")
      let (saved,_) ← publish saved "earlier-private" (readTool "old-private")
      pure (some saved)
    else pure archive
  let archivePath := archive.map (·.directory.toString)
  let keys ← if spec.archiveRetraction then do
      unless archive.isSome do throw (IO.userError "missing archive")
      let edge := (compileOperationOutcomes (.text "earlier-private") (.text "turn") (readTool "old-private")).2
      pure ["h:" ++ Persistence.selectionKey edge]
    else pure keys
  let known ← knowledge source keys spec.uncertain archivePath
  let known := if spec.missingIndex then {known with indexed := none} else known
  let archive ← if spec.archiveRetraction then do
      let some saved := archive | throw (IO.userError "missing archive")
      let edge := (compileOperationOutcomes (.text "earlier-private") (.text "turn") (readTool "old-private")).2
      let some id ← findNode? saved edge | throw (IO.userError "missing old private owner")
      let _ ← DB.PageMap.withWriter saved fun writer => do
        removeRoot writer id
        writeChange writer ⟨[],[id],false⟩
      pure (some (← DB.PageMap.pin saved.directory))
    else pure archive
  if spec.archiveRetraction then
    check (covered needed.source (← presentation source known).ranges)
      "a later archive retraction rewrote acknowledged pre-read knowledge"
  let producer := readTool "read"
  let consumer := useTool "use-A" "ID_ALPHA"
  let tools := #[producer] ++ (if spec.ambiguous then #[readTool "another-read"] else #[]) ++
    (if spec.consumed then #[consumer] else #[])
  let mut source := source
  let mut archive := archive
  for tool in tools do
    if let some saved := archive then
      let (updated,_) ← publish saved "live" tool
      archive := some updated
    else
      let (updated,_) ← publish source "live" tool
      source := updated
  let sourceBefore := source.head
  let mut ordinal := 10
  for tool in tools do
    for event in events tool known ordinal archivePath do
      let _ ← Journal.append source event
      if spec.lateAck && event.payload.kind == "start" && tool.useId == producer.useId then
        let lateKnown := {known with acknowledged := ["h:" ++ doc.owner]}
        let late := {event with payload := .start (occurrence producer.useId) (canonicalToolWork producer) query lateKnown}
        check (!(← Journal.append source late)) "retry replaced pre-read ACK knowledge"
    ordinal := ordinal+10
  let storage := if spec.privateWork then DB.Sidecar.Storage.user else .database
  let replayed ← Journal.refresh source storage ((← IO.monoMsNow)+10000)
  source ← DB.PageMap.pin source.directory
  let beforeLater ← usageFacts source
  let positive := beforeLater.filter (·.kind == .omittedThenConsumed)
  let expected := spec.consumed && spec.priorData && !spec.uncertain && !spec.missingIndex &&
    !spec.ambiguous && spec.ack != "whole" && spec.ack != "split" && !spec.archiveRetraction
  check (positive.size == if expected then 1 else 0) s!"{spec.label}: wrong missing-use count"
  check (beforeLater.all (fun usage => usage.event.occurrence == occurrence "read" &&
      usage.event.consumption.any (fun cause => cause.consumer == occurrence "use-A" && cause.source == usage.source) &&
      usage.source == needed.source)) s!"{spec.label}: unused sibling or fabricated event was labelled"
  if spec.ambiguous then check (replayed.ambiguousNativeUses > 0) "ambiguous output matches were not recorded"
  if spec.uncertain || spec.missingIndex then check (replayed.unknown > 0) "unconfirmed pre-read knowledge became complete"
  if spec.privateWork then
    check (source.head == sourceBefore && replayed.consumed == 0)
      "private usage changed the shared source or published private consumption"
  let some shared ← Index.open? source storage .shared | throw (IO.userError "missing shared index")
  let sharedFacts ← Index.allFacts shared.index
  check (sharedFacts.all (fun fact => match fact with | .used _ => false | _ => true) &&
      ((toJson sharedFacts).compress.splitOn "PRIVATE_ARGUMENT_NEVER_SHARED").length == 1)
    "private feedback or private arguments leaked to the shared index"
  if expected then
    let some usage ← Index.open? source .user .usage | throw (IO.userError "missing private usage index")
    let recommendation ← Recommend.collect shared (some usage) #[] #[] query ((← IO.monoMsNow)+10000)
    check (recommendation.complete && recommendation.admitted.any (·.target.source? == some needed.source))
      "native missing-use feedback did not reach recommendation"
  if spec.appendLater then
    let later := useTool "use-B" "TAIL_BETA"
    let (updated,_) ← publish source "live" later
    source := updated
    for event in events later known 50 none do let _ ← Journal.append source event; pure ()
    let _ ← Journal.refresh source storage ((← IO.monoMsNow)+10000)
    source ← DB.PageMap.pin source.directory
    let after ← usageFacts source
    check (after.size == 2 && beforeLater.all after.contains && after.all (·.kind == .omittedThenConsumed))
      "later consumption reassigned an earlier usage event or lost a distinct used range"
  let beforeRepeat ← usageFacts source
  let again ← Journal.refresh source storage ((← IO.monoMsNow)+10000)
  check (again.turns == 0 && (← usageFacts (← DB.PageMap.pin source.directory)) == beforeRepeat)
    "unchanged native replay inflated use evidence"
  return Json.mkObj [("case",toJson spec.label),("replay",toJson replayed),
    ("usage",toJson beforeRepeat),("sourceUnchanged",toJson (sourceBefore == source.head))]

def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "SynapseNativeUsageTests NEW-DIRECTORY")
  let root := System.FilePath.mk path
  check (root.isAbsolute && !(← root.pathExists)) "new absolute fixture required"
  IO.FS.createDirAll root
  let cases : Array Case := #[
    {label := "missing-local"},{label := "missing-private",privateWork := true},
    {label := "whole-ack",ack := "whole"},{label := "split-ack",ack := "split"},
    {label := "hole-ack",ack := "hole"},{label := "uncertain",uncertain := true},
    {label := "missing-index",missingIndex := true},{label := "absent-prior",priorData := false},
    {label := "not-consumed",consumed := false},{label := "ambiguous",ambiguous := true},
    {label := "append-later",appendLater := true},{label := "late-ack",lateAck := true},
    {label := "archive-retraction",privateWork := true,archiveRetraction := true}]
  let mut results := #[]
  for spec in cases do
    let directory := root / spec.label
    IO.FS.createDirAll directory
    results := results.push (← trial directory spec)
  IO.FS.writeFile (root / "usage.json") (toJson results).pretty
  IO.println s!"native usage passed: {cases.size} cases; consumed ranges only, pinned pre-read DB/ACKs, private feedback, ambiguity, stable later events and idempotent replay"
