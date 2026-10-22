import Eggshell.SynapseLive

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Journal
open Eggshell.Synapses.Extraction Eggshell.Persistence.Store

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def domain : String := String.ofList (List.replicate 64 'a')
private def query : String := String.ofList (List.replicate 64 'b')
private def occurrence (name : String) : Occurrence := ⟨"live", "turn", name⟩
private def body : String := "  10\talpha\n  11\tNEEDED_SYMBOL\n  12\tomega\n"
private def command : String := "nl -ba src/source.cpp | sed -n '10,12p'"
private def tool (name : String) (cmd := command) (output := body) : Plugin.ToolEvent := {
  name := "shell", useId := name
  input := (Json.mkObj [("command", toJson cmd)]).compress
  response := (Json.mkObj [("metadata", Json.mkObj [("status", toJson (0 : Nat))]), ("output", toJson output)]).compress }

private def publish (snapshot : DB.PageMap.Snapshot) (session turn : String) (tool : Plugin.ToolEvent) :
    IO (DB.PageMap.Snapshot × OutcomeEdge) := do
  let relation := (Plugin.compileOperationOutcomes (.text session) (.text turn) tool).2
  let some owner := OutcomeEdge.fromValue? relation | throw (IO.userError "invalid fixture owner")
  let certificate := SourceEvidence.receipt (.text session) (.text turn) (.text tool.useId) relation {
    workspace := "/fixture", complete := true
    files := [⟨"src/source.cpp", some ⟨1000, String.ofList (List.replicate 64 'c')⟩⟩] }
  let _ ← DB.PageMap.withWriter snapshot fun writer => do
    let intern : Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← [relation, certificate].mapM intern.root
    writeChange writer ⟨ids, [], false⟩
  return (← DB.PageMap.pin snapshot.directory, owner)

private def startEvent (source : DB.PageMap.Snapshot) (name : String) (nanos : Nat)
    (keys : List String := []) (uncertain := false) (cmd := command) (archive : Option String := none) : IO Entry := do
  let tool := tool name cmd
  return ⟨⟨domain, nanos⟩, .start (occurrence name) (Plugin.canonicalToolWork tool) query
    (← knowledge source keys uncertain archive)⟩

private def finishEvent (name : String) (nanos : Nat) (cmd := command) (output := body)
    (archive : Option String := none) : Entry :=
  let tool := tool name cmd output
  ⟨⟨domain, nanos⟩, .finish (occurrence name) tool.name tool.input tool.response archive⟩

private def facts (source : DB.PageMap.Snapshot) : IO (Array Fact) := do
  let some usage ← Index.open? source .user .usage | return #[]
  Index.allFacts usage.index

private def usages (source : DB.PageMap.Snapshot) (name : String) : IO (Array Usage) := do
  return (← facts source).filterMap fun fact => match fact with
    | .used usage => if usage.event.occurrence.useId == name then some usage else none
    | _ => none

private def scenario (root : System.FilePath) : IO Unit := do
  let source ← DB.PageMap.create (root / "source.egg") (Persistence.valueToJson (.text "authority")).compress
  let (source, seed) ← publish source "seed" "seed-turn" (tool "seed")
  let _ ← Build.refresh source .database
  let originalHead := source.head
  let start ← startEvent source "missing" 100
  let late ← startEvent source "missing" 999 ["h:" ++ Persistence.selectionKey seed.relation]
  check (← append source start) "first Pre event was not recorded"
  check (!(← append source late)) "retry rewrote first knowledge or clock"
  check (← append source (finishEvent "missing" 200 command body (some source.directory.toString))) "Post event was not recorded"
  let before ← refresh source .database ((← IO.monoMsNow)+3000)
  check (before.pending == 1 && before.usage == 0) "unpublished Post invented a saved observation"
  let (source, _) ← publish source "live" "turn" (tool "missing")
  let first ← refresh source .database ((← IO.monoMsNow)+3000)
  let missing ← usages source "missing"
  check (first.usage == 1 && missing.size == 1 && missing.all (·.kind == .omittedThenRead))
    "saved pre-read evidence or first observed knowledge was lost"
  let some journal ← Journal.open? source | throw (IO.userError "missing private journal")
  let saved ← turnEntries journal ⟨"live", "turn"⟩
  check (saved[0]?.any (· == start)) "first event changed after identical retry"
  let repeated ← refresh source .database ((← IO.monoMsNow)+3000)
  check (repeated.turns == 0 && (← usages source "missing").size == 1) "replay inflated feedback"
  let shown := ["h:" ++ Persistence.selectionKey seed.relation]
  let answer : Entry := ⟨⟨domain, 300⟩, .answer (occurrence "answer") query
    "[source.cpp:11](src/source.cpp:11)" (← knowledge source shown false)⟩
  let _ ← append source answer
  let _ ← refresh source .database ((← IO.monoMsNow)+3000)
  check ((← usages source "answer").any (·.kind == .deliveredThenCited)) "acknowledged source citation was not recorded"
  let _ ← append source (← startEvent source "known" 400 shown)
  let _ ← append source (finishEvent "known" 500)
  let (source, _) ← publish source "live" "turn" (tool "known")
  let _ ← refresh source .database ((← IO.monoMsNow)+3000)
  check ((← usages source "known").all (·.kind == .reread)) "known native source was rewarded as missing"
  let _ ← append source (← startEvent source "uncertain" 600 [] true)
  let _ ← append source (finishEvent "uncertain" 700)
  let (source, _) ← publish source "live" "turn" (tool "uncertain")
  let unknown ← refresh source .database ((← IO.monoMsNow)+3000)
  check (unknown.unknown > 0 && (← usages source "uncertain").isEmpty)
    "unconfirmed stdout was called absent"
  let reader ← NodeReader.new source
  let some seedId ← findNode? source seed.relation | throw (IO.userError "missing seed")
  let doc ← Build.document reader seedId
  let rows ← IO.ofExcept (recordedRows source.head.identity doc)
  let some middle := rows.find? (·.source.first == 11) | throw (IO.userError "missing projected JSON output row")
  check (middle.binding.first > 0 && middle.binding.limit < (doc.source.getD "").length)
    "native response wrapper lost original coordinates"
  let excerpt := s!"e:{doc.owner}:{Persistence.selectionKey (.text (doc.source.getD ""))}:{middle.binding.first}:{middle.binding.limit}"
  let _ ← append source (← startEvent source "partial" 800 [excerpt])
  let _ ← append source (finishEvent "partial" 900)
  let (source, _) ← publish source "live" "turn" (tool "partial")
  let _ ← refresh source .database ((← IO.monoMsNow)+3000)
  let gaps ← usages source "partial"
  check (gaps.size == 2 && gaps.all (·.kind == .omittedThenRead) &&
    gaps.any (·.source.first == 10) && gaps.any (·.source.first == 12))
    "partial delivery did not produce the exact omitted line intervals"
  -- A later literal argument consumes the actual earlier numbered output.
  let consume := "printf NEEDED_SYMBOL"
  let _ ← append source (← startEvent source "consume" 1000 [] false consume)
  let _ ← append source (finishEvent "consume" 1100 consume "done")
  let (source, _) ← publish source "live" "turn" (tool "consume" consume "done")
  let consumed ← refresh source .database ((← IO.monoMsNow)+3000)
  check (consumed.consumed > 0) "observed output consumption was not indexed"
  let some shared ← Index.open? source .database .shared | throw (IO.userError "missing shared index")
  let found ← shared.lookup (.consumer (occurrence "consume")) 1000 ((← IO.monoMsNow)+3000)
  check (found.complete && found.facts.any (fun fact => match fact with
    | .consumed edge => edge.rows.any (·.first == 11)
    | _ => false)) "consumption witness was not projected onto its original line"
  check ((← DB.PageMap.pin source.directory).head == source.head && source.head != originalHead)
    "background journal processing changed the source graph"
  let beforeHead := shared.index.head
  let again ← refresh source .database ((← IO.monoMsNow)+3000)
  let some shared ← Index.open? source .database .shared | throw (IO.userError "missing repeat index")
  check (again.turns == 0 && shared.index.head == beforeHead) "replay rewrote identical synaptic facts"
  -- Arrival order is not chronology; different manager-clock domains never mix.
  let a ← startEvent source "parallel-A" 1200 [] false "search"
  let b ← startEvent source "parallel-B" 1201 [] false "printf NEEDED_SYMBOL"
  let outA := finishEvent "parallel-A" 1202 "search" "NEEDED_SYMBOL"
  let outB := finishEvent "parallel-B" 1203 "printf NEEDED_SYMBOL" "done"
  let (source, _) ← publish source "live" "turn" (tool "parallel-A" "search" "NEEDED_SYMBOL")
  let (source, _) ← publish source "live" "turn" (tool "parallel-B" "printf NEEDED_SYMBOL" "done")
  let future ← replay source #[a, b, outA, outB] ((← IO.monoMsNow)+3000)
  check (future.consumed.isEmpty) "parallel invocation consumed a future output"
  let isolated := {b with clock := ⟨String.ofList (List.replicate 64 'd'), 1300⟩}
  let isolatedEnd := {outB with clock := ⟨String.ofList (List.replicate 64 'd'), 1301⟩}
  let separated ← replay source #[a, outA, isolated, isolatedEnd] ((← IO.monoMsNow)+3000)
  check (separated.consumed.isEmpty) "different manager clocks were joined"
  let _ ← refresh source .database ((← IO.monoMsNow)+3000)
  check (!(← Journal.required source)) "journal was not ready before the cache-only replacement"
  let priorUsage ← facts source
  let cache ← Index.directory source .database .shared
  IO.FS.rename cache (root / "retired-index")
  let _ ← Build.refresh source .database
  check (← Journal.required source) "new cache incarnation forgot its journal replay debt"
  let recovered ← refresh source .database ((← IO.monoMsNow)+3000)
  check (recovered.unknown > 0 && (← facts source) == priorUsage)
    "lost captured cache relabelled earlier immutable usage events"
  let some restored ← Index.open? source .database .shared | throw (IO.userError "missing restored cache")
  let restoredEdges ← restored.lookup (.consumer (occurrence "consume")) 1000 ((← IO.monoMsNow)+3000)
  check (!restoredEdges.facts.isEmpty && !(← Journal.required source)) "cold rebuild did not replay consumption from the private journal"
  let _ ← DB.PageMap.withWriter source fun writer => do
    writer.put "memo:journal-fixture" (some "derived-only".toUTF8)
    writeChange writer ⟨[], [], false⟩
  let derived ← DB.PageMap.pin source.directory
  check (!(← Journal.required derived)) "derived query memo scheduled original-body replay"
  let noReplay ← refresh derived .database ((← IO.monoMsNow)+3000)
  check (noReplay.turns == 0) "derived-only update rehydrated old observations"
  let archive ← DB.PageMap.create (root / "private-work.egg") (Persistence.valueToJson (.text "private-authority")).compress
  let _ ← append derived (← startEvent derived "cross-db" 1400)
  let _ ← append derived (finishEvent "cross-db" 1401 command body (some archive.directory.toString))
  let deferred ← refresh derived .database ((← IO.monoMsNow)+3000)
  check (deferred.pending == 1 && !deferred.complete && (← Journal.required derived))
    "foreign publication wait lost its replay debt"
  let (archive, privateRead) ← publish archive "live" "turn" (tool "cross-db")
  let _ ← refresh derived .database ((← IO.monoMsNow)+3000)
  check ((← usages derived "cross-db").any (·.kind == .omittedThenRead))
    "private work could not label omitted memory in a read-only source DB"
  let _ ← append derived (← startEvent derived "cross-known" 1450
    ["h:" ++ Persistence.selectionKey privateRead.relation] false command (some archive.directory.toString))
  let _ ← append derived (finishEvent "cross-known" 1451 command body (some archive.directory.toString))
  let (archive, _) ← publish archive "live" "turn" (tool "cross-known")
  let _ ← refresh derived .database ((← IO.monoMsNow)+3000)
  check ((← usages derived "cross-known").any (·.kind == .reread))
    "already observed private read was rewarded again as a shared-source omission"
  let _ ← append derived (← startEvent derived "private-consumer" 1500 [] false "printf NEEDED_SYMBOL")
  let _ ← append derived (finishEvent "private-consumer" 1501 "printf NEEDED_SYMBOL" "done" (some archive.directory.toString))
  let _ ← publish archive "live" "turn" (tool "private-consumer" "printf NEEDED_SYMBOL" "done")
  let _ ← refresh derived .database ((← IO.monoMsNow)+3000)
  let some shared ← Index.open? derived .database .shared | throw (IO.userError "missing shared cache")
  let privateTerms ← shared.lookup (.consumer (occurrence "private-consumer")) 1000 ((← IO.monoMsNow)+3000)
  check (privateTerms.facts.isEmpty) "foreign private tool terms leaked into the shared source index"
  let futureStart ← startEvent derived "future-publication" 1600 [] false "printf NEEDED_SYMBOL"
  let futureFinish := finishEvent "future-publication" 1601 "printf NEEDED_SYMBOL" "done" (some derived.directory.toString)
  let _ ← publish derived "live" "turn" (tool "future-publication" "printf NEEDED_SYMBOL" "done")
  let pinned ← replay derived #[a, outA, futureStart, futureFinish] ((← IO.monoMsNow)+3000)
  check (pinned.consumed.isEmpty) "later head with the same DB identity bypassed pinned owner membership"
  IO.println s!"native journal checks passed: missing={missing.size} partial={gaps.size} consumption={consumed.consumed}; immutable retries, deferred publication, exact JSON coordinates, ACK knowledge, uncertainty, repeat and temporal isolation"

def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "SynapseJournalTests NEW-DIRECTORY")
  let root := System.FilePath.mk path
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new absolute fixture directory required")
  IO.FS.createDirAll root
  scenario root
