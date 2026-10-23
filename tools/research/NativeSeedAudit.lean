import tools.research.StudyAcquire
import Eggshell.SynapseLive

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction
open Eggshell.Research

namespace Eggshell.Research.NativeSeedAudit

private structure Requirement where
  name : String
  path : String
  first : Nat
  last : Nat
  deriving FromJson, ToJson

private structure Topic where
  topic : Nat
  referenceRanges : Array Requirement
  deriving FromJson

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def originalRows (snapshot : DB.PageMap.Snapshot) : IO (Array Document × Array Read) := do
  let reader ← Persistence.Store.NodeReader.new snapshot
  let mut documents := #[]
  let mut rows := #[]
  for entry in ← Build.entries snapshot do
    let doc ← Build.document reader entry.id
    documents := documents.push doc
    if let .ok found := recordedRows snapshot.head.identity doc then rows := rows ++ found
  return (documents,rows)

private def rpcCommands (path : System.FilePath) (session turn : String) : IO (Array Json) := do
  let input ← IO.FS.Handle.mk path .read
  let mut result := #[]
  let mut seen : Std.HashSet String := {}
  let mut terminals : Std.HashMap String Json := {}
  let mut hooks : Array Json := #[]
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let row ← IO.ofExcept (Json.parse line)
    if (row.getObjValAs? String "direction").toOption != some "server" then continue
    let .ok message := row.getObjVal? "message" | continue
    let method := (message.getObjValAs? String "method").toOption
    if method != some "item/started" && method != some "item/completed" && method != some "hook/completed" then continue
    let params ← IO.ofExcept (message.getObjVal? "params")
    if (params.getObjValAs? String "threadId").toOption != some session ||
        (params.getObjValAs? String "turnId").toOption != some turn then continue
    if method == some "hook/completed" then
      let run ← IO.ofExcept (params.getObjVal? "run")
      hooks := hooks.push (Json.mkObj [
        ("id",← IO.ofExcept (run.getObjVal? "id")),("eventName",← IO.ofExcept (run.getObjVal? "eventName")),
        ("status",← IO.ofExcept (run.getObjVal? "status")),("durationMs",← IO.ofExcept (run.getObjVal? "durationMs"))])
      continue
    let item ← IO.ofExcept (params.getObjVal? "item")
    if (item.getObjValAs? String "type").toOption != some "commandExecution" then continue
    let id ← IO.ofExcept (item.getObjValAs? String "id")
    if method == some "item/completed" then
      terminals := terminals.insert id (Json.mkObj [
        ("status",← IO.ofExcept (item.getObjVal? "status")),("exitCode",← IO.ofExcept (item.getObjVal? "exitCode")),
        ("outputCharacters",toJson ((item.getObjValAs? String "aggregatedOutput").toOption.getD "").length)])
      continue
    if seen.contains id then continue
    seen := seen.insert id
    result := result.push (Json.mkObj [("id",toJson id),("command",← IO.ofExcept (item.getObjVal? "command"))])
  return result.map fun row =>
    let id := (row.getObjValAs? String "id").toOption.getD ""
    (row.setObjVal! "terminal" (terminals[id]?.getD .null)).setObjVal! "hooks"
      (toJson (hooks.filter fun hook => (hook.getObjValAs? String "id").toOption.any (·.endsWith (":" ++ id))))

/-- Read only the saved seed, native event journal and source code. This
auditor neither opens a handoff body nor calls Handoff, warm or a model. -/
def cliMain (args : List String) : IO Unit := do
  let [acquisition,definitions,publication,output] := args |
    throw (IO.userError "NativeSeedAudit ACQUISITION TASK-DEFINITIONS PUBLICATION NEW-REPORT")
  let root := System.FilePath.mk acquisition
  check (root.isAbsolute && !(← (System.FilePath.mk output).pathExists)) "absolute acquisition and new output required"
  check ((← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString) "native seed private root required"
  let plan ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan) (← StudyAdmission.readJson (root / "plan.json").toString))
  let result ← StudyAdmission.readJson (root / "result.json").toString
  check (plan.kind == "seed" && (result.getObjValAs? Bool "completed").toOption == some true)
    "completed seed acquisition required"
  StudyAdmission.verifyArtifact plan.runtime
  let thread ← StudyAdmission.readJson (root / "thread.json").toString
  let session ← IO.ofExcept ((← IO.ofExcept (thread.getObjVal? "thread")).getObjValAs? String "id")
  let started ← StudyAdmission.readJson (root / "turn-start.json").toString
  let turn ← IO.ofExcept ((← IO.ofExcept (started.getObjVal? "turn")).getObjValAs? String "id")
  let original ← DB.PageMap.pin (.mk publication)
  let current ← DB.PageMap.pin (root / "work.egg")
  check (← Index.sameSources current original.head) "seed source facts changed after acquisition"
  let files ← StudyRuntime.files original.directory
  let (documents,rows) ← originalRows original
  let origins ← Provenance.records current
  let derived ← Provenance.derive current
  let reconstructed := derived.graph.snapshot
  let journal ← Journal.open? current
  let entries ← journal.mapM (Journal.turnEntries · ⟨session,turn⟩)
  let entries := entries.getD #[]
  let shared ← Index.open? current .database .shared
  let indexed ← shared.mapM (fun reader => Index.allFacts reader.index)
  let indexed := indexed.getD #[]
  let commands ← rpcCommands (root / "rpc/exchange.jsonl") session turn
  let starts := entries.filter fun entry => match entry.payload with | .start .. => true | _ => false
  let finishes := entries.filter fun entry => match entry.payload with | .finish .. => true | _ => false
  let consumed := reconstructed.filterMap fun fact => match fact with | .consumed edge => some edge | _ => none
  let sourceReader ← Persistence.Store.NodeReader.new current
  let mut commandAudit := #[]
  let mut missingNativeStarts := 0
  let mut missingNativeFinishes := 0
  let mut missingPortableOrigins := 0
  for command in commands do
    let id ← IO.ofExcept (command.getObjValAs? String "id")
    let occurrence : Occurrence := ⟨session,turn,id⟩
    let pres := starts.filter (·.payload.occurrence == occurrence)
    let posts := finishes.filter (·.payload.occurrence == occurrence)
    let original := origins.filter (·.origin.occurrence == occurrence)
    let incoming := consumed.filter (·.consumer == occurrence)
    let persisted := indexed.filter fun fact => match fact with | .consumed edge => edge.consumer == occurrence | _ => false
    let mut supportedCommand := false
    for stored in original do
      let doc ← Provenance.checkedDocument sourceReader stored.origin
      supportedCommand := supportedCommand || (doc.workText.any (fun text => (workCommand text).isOk) &&
        doc.source.any (fun text => (layout text).isOk))
    let earlier := original.any fun stored => origins.any fun previous =>
      previous.origin.domain == stored.origin.domain &&
      previous.origin.occurrence.session == occurrence.session && previous.origin.occurrence.turn == occurrence.turn &&
      previous.origin.finished < stored.origin.started
    let hooks := (command.getObjValAs? (Array Json) "hooks").toOption.getD #[]
    let postCompleted := hooks.any fun hook =>
      (hook.getObjValAs? String "eventName").toOption == some "postToolUse" &&
      (hook.getObjValAs? String "status").toOption == some "completed"
    let preCompleted := hooks.any fun hook =>
      (hook.getObjValAs? String "eventName").toOption == some "preToolUse" &&
      (hook.getObjValAs? String "status").toOption == some "completed"
    if preCompleted && pres.isEmpty then missingNativeStarts := missingNativeStarts+1
    if postCompleted && posts.isEmpty then missingNativeFinishes := missingNativeFinishes+1
    if postCompleted && original.isEmpty then missingPortableOrigins := missingPortableOrigins+1
    let reason := if pres.isEmpty then "missing-native-pre-or-unmatched-rpc-id"
      else if posts.isEmpty && postCompleted then "completed-post-hook-without-native-journal-finish"
      else if posts.isEmpty then "missing-native-post"
      else if original.isEmpty then "missing-published-portable-origin"
      else if !supportedCommand then "unsupported-original-command-or-output"
      else if !incoming.isEmpty then "consumption-witness-present"
      else if !earlier then "no-earlier-published-tool-output"
      else "no-eligible-earlier-output-witness"
    commandAudit := commandAudit.push (command.setObjVal! "audit" (Json.mkObj [
      ("reason",toJson reason),("nativePre",toJson pres.size),("nativePost",toJson posts.size),
      ("portableOrigins",toJson original.size),("derivedIncoming",toJson incoming.size),
      ("indexedIncoming",toJson persisted.size),("locatedWitnesses",toJson (incoming.filter (!·.rows.isEmpty)).size)]))
  let definitionsBytes ← IO.FS.readBinFile (.mk definitions)
  let topics ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk definitions)) >>= fromJson? (α := Array Topic))
  let mut availability := #[]
  for topic in topics do
    let mut required := #[]
    for requirement in topic.referenceRanges do
      check (safeRelative requirement.path && 0 < requirement.first && requirement.first ≤ requirement.last)
        "invalid frozen source requirement"
      let candidates := rows.filter fun row => row.source.file.relative == requirement.path &&
        row.source.first ≤ requirement.last && requirement.first ≤ row.source.last
      let files := candidates.foldl (fun found row => found.insert row.source.file) ({} : Std.HashSet File)
      let stored := files.toArray.any fun file => covered ⟨file,requirement.first,requirement.last⟩ (candidates.map (·.source))
      required := required.push (Json.mkObj [
        ("reference",toJson requirement),("storedOriginal",toJson stored),
        ("sourceFiles",toJson files.toArray),("originalRows",toJson candidates),
        ("owners",toJson (candidates.map (·.binding.owner)).toList.eraseDups.toArray)])
    availability := availability.push (Json.mkObj [("topic",toJson topic.topic),("requirements",toJson required)])
  check ((← StudyRuntime.files original.directory) == files) "audit changed the frozen seed publication"
  let unaccounted := commandAudit.filter fun row =>
    ((row.getObjVal? "audit").bind (·.getObjValAs? Nat "portableOrigins")).toOption == some 0
  let report := Json.mkObj [
    ("runtime",toJson plan.runtime),("provider",toJson plan.provider),("model",toJson plan.model),("effort",toJson plan.effort),
    ("publication",toJson publication),
    ("taskDefinitionsSha256",toJson (Sha256.hex definitionsBytes)),("sourceFiles",toJson files),
    ("sourceFactsUnchanged",toJson true),("handoffBodiesRead",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("originalDocuments",toJson documents.size),("originalRows",toJson rows.size),
    ("rpcCommands",toJson commands.size),("nativeStarts",toJson starts.size),("nativeFinishes",toJson finishes.size),
    ("portableOrigins",toJson origins.size),("unaccountedCommands",toJson unaccounted.size),
    ("missingNativeStarts",toJson missingNativeStarts),("missingNativeFinishes",toJson missingNativeFinishes),
    ("missingPortableOrigins",toJson missingPortableOrigins),
    ("nativeJournalComplete",toJson (missingNativeStarts == 0 && missingNativeFinishes == 0)),
    ("portableOriginsComplete",toJson (missingPortableOrigins == 0)),
    ("seedAccepted",toJson (missingNativeStarts == 0 && missingNativeFinishes == 0 && missingPortableOrigins == 0)),
    ("ignoredOrigins",toJson derived.ignored),("reconstructedConsumption",toJson consumed.size),
    ("indexAvailable",toJson shared.isSome),("commandAudit",toJson commandAudit),("availability",toJson availability)]
  IO.FS.writeFile (.mk output) (report.compress ++ "\n")
  check (missingNativeStarts == 0 && missingNativeFinishes == 0)
    "completed native hooks lost journal events; do not freeze an accepted seed or start topic delivery"
  check (missingPortableOrigins == 0)
    "completed native tools lack portable original observations; drain durable saves before accepting the seed"

end Eggshell.Research.NativeSeedAudit
