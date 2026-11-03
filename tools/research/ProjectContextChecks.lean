import Eggshell.PluginHooks
import Eggshell.PublicationService
import Eggshell.ContractAudit
import tools.research.ProjectInputsChecks

open Lean Eggshell Eggshell.Plugin Eggshell.DB Eggshell.ProjectStore
open Eggshell.Synapses

namespace Eggshell.Research.ProjectContextChecks

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def domain := Sha256.hex "native-project-context".toUTF8

private partial def containsText (value : Value) (text : String) : Bool :=
  match value with
  | .atom bytes => (String.fromUTF8? bytes).any (·.contains text)
  | .apply _ refs => refs.toList.any (fun (_,value) => containsText value text)

private def input (root : System.FilePath) (session turn : String) (nanos : Nat) : Json :=
  Json.mkObj [("session_id",toJson session),("turn_id",toJson turn),
    ("cwd",toJson root.toString),("_eggshell_config",toJson (root/"eggshell.toml").toString),
    ("_eggshell_synapse_clock",toJson domain),("_eggshell_synapse_nanos",toJson nanos)]

private def tool (name : String) : ToolEvent := {
  name := "mcp__fixture__inspect",useId := name,
  input := (Json.mkObj [("key",toJson name)]).compress,
  response := (Json.mkObj [("id",toJson name),("tail",toJson (name++"_TAIL")),
    ("body",toJson (String.ofList (List.replicate 5000 'x')))]).compress }

private def nativeInput (base : Json) (tool : ToolEvent) : Json :=
  base.setObjVal! "tool_name" (toJson tool.name)
    |>.setObjVal! "tool_use_id" (toJson tool.useId)
    |>.setObjVal! "tool_input" ((Json.parse tool.input).toOption.getD (.str tool.input))
    |>.setObjVal! "tool_response" ((Json.parse tool.response).toOption.getD (.str tool.response))

private def seed (root project : System.FilePath) (session marker : String) : IO Unit := do
  let pending : PendingTurn := {
    sessionId := session,turnId := "seed",cwd := root.toString,prompt := marker,
    profile := "seed",semanticMatcher := none,read := [project.toString],write := some project.toString,
    handoffChars := 120000,projection := .automatic }
  let pending ← ProjectContext.capture pending ((← IO.monoMsNow)+20000)
  let files ← sessionFiles session
  let state : ThreadState := {profile := "seed"}
  writeJson files.state state
  let recorded := tool marker
  Live.start (input root session "seed" 1) files pending state recorded
  Live.finish (input root session "seed" 2) pending recorded
  let pending := {pending with tools := [recorded],finalMessage := some s!"Recorded `{marker}` and `{marker}_TAIL`."}
  let saved ← Publication.Client.run pending project false
  check (saved.source.accounted && saved.source.awaiting == 0) "native seed publication was not durable"

private def graphs (context : ProjectContext.Context) : IO (List Value) := do
  let mut values := []
  for source in context.reads.sources do
    values := values++(← Persistence.Store.materialize source).values
  return values

private def privateMemo (context : ProjectContext.Context) : IO Unit := do
  let some write := context.selection.write | throw (IO.userError "memo check needs the configured write project")
  let scope := some write.project.manifest.identity
  let source ← context.source
  let sources := context.reads.sources.toList.map fun source => (source.directory.toString,some source.head)
  let request := "PRIVATE_QUERY_MUST_NOT_CHANGE_ORIGINALS"
  let captured := DemandMemo.capture request sources (toJson (none : Option Handoff)).compress none none
  DemandMemo.publishCaptured source captured scope
  let some cache ← QueryMemoStore.open? source scope | throw (IO.userError "private query memo was not stored")
  for other in context.reads.sources do
    check ((← PageMap.pin other.directory).head == other.head) "private memo changed an original source head"
  for other in context.reads.sources do
    if !write.project.manifest.owners.any (·.identity == other.head.identity) then continue
    let some same ← QueryMemoStore.open? other scope | throw (IO.userError "project memo was copied by owner")
    check (same.head == cache.head && same.directory == cache.directory) "project query memo is not shared across owners"
    let some replayed ← DemandMemo.readObserved other request none scope | throw (IO.userError "private memo did not replay")
    check (← DemandMemo.dependenciesAgree replayed.record (context.physicalSelection.read.map (·.path)) context.snapshots)
      "private memo lost its complete original read boundary"
  check (!(← graphs context).any (containsText · request)) "query memo leaked into original work graph"

private def inspect (root : System.FilePath) : IO Json := do
  let pending ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))
  let some context ← ProjectContext.open? pending ((← IO.monoMsNow)+20000) |
    throw (IO.userError "serialized native turn lost its captured project context")
  let values ← graphs context
  check (values.any (containsText · "OLD_ID_ALPHA") && !values.any (containsText · "NEW_ID_BETA"))
    "historical native context substituted a later foreign publication"
  check (some context.reads.images == pending.projectInputs) "native context reopen changed its complete source heads"
  return Json.mkObj [("sameCapturedImages",toJson true),("oldOriginalPresent",toJson true),
    ("newOriginalAbsent",toJson true),("sources",toJson context.reads.sources.size),
    ("inputs",toJson (ProjectInputs.digest context.reads.images))]

private def checkJournal (pending : PendingTurn) : IO Json := do
  let some context ← ProjectContext.open? pending ((← IO.monoMsNow)+20000) | throw (IO.userError "no context")
  let primary ← context.source
  let some journal ← Journal.open? primary | throw (IO.userError "ordinary hooks did not capture native ingress")
  let entries ← Journal.turnEntries journal ⟨pending.sessionId,pending.turnId⟩
  check (entries.size == 3) "ordinary Pre/Post/Stop did not capture exactly three native events"
  let targets := (← Journal.targets).filter fun (_,target) =>
    (target.owner.database == primary.head.identity && target.ingress.isNone) ||
      target.ingress == some (Sidecar.Owner.ofSnapshot primary)
  check (targets.size == context.reads.sources.size) "ordinary capture omitted a source feed or copied whole bodies"
  let mut imported := 0
  for (_,target) in targets do
    if target.owner.database == primary.head.identity then continue
    check (target.ingress == some (Sidecar.Owner.ofSnapshot primary)) "native source target lost its original ingress owner"
    let other ← target.owner.pin
    check (← Journal.feedRequired other (Sidecar.Owner.ofSnapshot primary)) "new project feed was falsely ready"
    let result ← Worker.exchange pending.sessionId "index"
      (Json.mkObj [("kind",toJson "synapses"),("target",toJson target)]) ((← IO.monoMsNow)+20000)
    let some result := result | throw (IO.userError "background source import did not reply")
    let result ← IO.ofExcept (fromJson? (α := Journal.Result) result)
    check (result.complete) "background source import did not finish"
    check (!(← Journal.feedRequired other (Sidecar.Owner.ofSnapshot primary))) "import cursor retained completed feed debt"
    let some secondary ← Journal.open? other | throw (IO.userError "native source projection did not commit")
    let projected ← Journal.turnEntries secondary ⟨pending.sessionId,pending.turnId⟩
    check (projected.size == 3) "background projection dropped native events"
    for entry in projected do
      let some ordinalBytes ← secondary.get ("event:"++entry.name) | throw (IO.userError "missing source event posting")
      let ordinal ← IO.ofExcept (Persistence.Store.payloadSize (some ordinalBytes))
      check ((← secondary.get (Journal.referenceKey ordinal)).isSome &&
        (← secondary.get (PageMap.payloadChunkKey (Persistence.Store.key "entry" ordinal) 0)).isNone)
        "source projection duplicated an original native body"
    imported := imported+1
  return Json.mkObj [("originalEvents",toJson entries.size),("referenceSources",toJson imported),
    ("oneOriginalBody",toJson true),("backgroundWorkerImports",toJson true)]

private def runHooks (root : System.FilePath) : IO Json := do
  let base := input root "context-client" "turn" 10
  let promptStarted ← IO.monoMsNow
  let output ← userPromptSubmit (base.setObjVal! "prompt" (toJson "Find OLD_ID_ALPHA and OLD_ID_ALPHA_TAIL original evidence"))
  let promptMs := (← IO.monoMsNow)-promptStarted
  let files ← sessionFiles "context-client"
  let some pending ← readPendingBase? files | throw (IO.userError "ordinary prompt did not create PendingTurn")
  check (pending.projectInputs.isSome) "ordinary prompt did not capture project inputs"
  IO.FS.writeFile (root/"captured-turn.json") ((toJson pending).pretty++"\n")
  let some captured ← ProjectContext.open? pending ((← IO.monoMsNow)+20000) |
    throw (IO.userError "first query invalidated its own captured project boundary")
  for source in captured.reads.sources do
    check ((← PageMap.pin source.directory).head == source.head)
      "query metadata changed an authoritative project source head"
  privateMemo captured
  IO.FS.writeFile (root/"prompt-output.json") (output++"\n")
  let outputJson ← IO.ofExcept (Json.parse output)
  let hookSpecific ← IO.ofExcept (outputJson.getObjVal? "hookSpecificOutput")
  let body ← IO.ofExcept (hookSpecific.getObjValAs? String "additionalContext")
  check (body.contains "\"OLD_ID_ALPHA\"" && body.contains "\"OLD_ID_ALPHA_TAIL\"" &&
      !body.contains "search-incomplete")
    "ordinary prompt did not deliver the old original evidence"
  seed root (root/"reference.project") "foreign-later" "NEW_ID_BETA"
  let beforeProbes ← captured.reads.sources.mapM fun source => PageMap.pin source.directory
  let old ← inspect root
  let reopened ← IO.Process.output {cmd := (← IO.appPath).toString,args := #["inspect-context",root.toString]}
  check (reopened.exitCode == 0 && reopened.stderr.isEmpty &&
    (← IO.ofExcept (Json.parse reopened.stdout)) == old) "fresh-process retained context differs"
  let recorded := tool "CURRENT_ID_GAMMA"
  let preStarted ← IO.monoMsNow
  let pre ← preToolUse (nativeInput base recorded)
  let preMs := (← IO.monoMsNow)-preStarted
  let postStarted ← IO.monoMsNow
  let post ← postToolUse (nativeInput (input root "context-client" "turn" 20) recorded)
  let postMs := (← IO.monoMsNow)-postStarted
  let stopStarted ← IO.monoMsNow
  let _ ← stop ((input root "context-client" "turn" 30).setObjVal! "last_assistant_message"
    (toJson "Recorded `CURRENT_ID_GAMMA` and `CURRENT_ID_GAMMA_TAIL`."))
  let stopMs := (← IO.monoMsNow)-stopStarted
  check (!pre.contains "NEW_ID_BETA" && !post.contains "NEW_ID_BETA") "later probe read a newer foreign original"
  let some closed ← readPending? files | throw (IO.userError "native turn disappeared before publication")
  check (closed.projectInputs == pending.projectInputs && closed.tools.length == 1)
    "ordinary native lifecycle changed the captured boundary or lost a Post"
  let some context ← ProjectContext.open? closed ((← IO.monoMsNow)+20000) | throw (IO.userError "no closed context")
  for original in beforeProbes do
    check ((← PageMap.pin original.directory).head == original.head) "Pre/Post/Stop changed original source heads"
  let some write := context.selection.write | throw (IO.userError "native write route disappeared")
  let some view := context.reads.views.find? (·.project.directory == write.directory) | throw (IO.userError "no write view")
  let request ← Publication.Client.prepareProject write view closed false
  let savePath := root/"save-context.json"
  writeJson savePath closed
  let some reply ← Worker.exchange closed.sessionId "save"
      (Json.mkObj [("session",toJson closed.sessionId),("path",toJson savePath.toString)]) ((← IO.monoMsNow)+28000) |
    throw (IO.userError "ordinary project save worker did not reply")
  let .published saved ← IO.ofExcept (NativePublication.SaveReply.check? reply) |
    throw (IO.userError "ordinary project save worker did not publish")
  check (saved.publication.awaiting == 0 && saved.publication.accounted) "ordinary project save lost native receipts"
  let source ← PageMap.pin write.sourceDirectory
  let inputs ← ProjectInputs.recorded source (Publication.projectRequestKey (Publication.Capsule.ofPrepared request))
  check (inputs == #[ProjectInputs.ofView view]++context.reads.images)
    "ordinary project save replaced the actual captured query boundary"
  let journal ← checkJournal closed
  let before := source.head
  let _ ← Publication.Client.run closed write.directory false
  check ((← PageMap.pin write.sourceDirectory).head == before) "ordinary project retry republished source"
  check (← rejected (ProjectContext.open? {closed with projectInputs := none} ((← IO.monoMsNow)+20000)))
    "project operation accepted missing capture"
  check (← rejected (ProjectContext.open? {closed with read := closed.read.reverse} ((← IO.monoMsNow)+20000)))
    "project operation reordered its captured read scope"
  check (!(← (write.directory/"head").pathExists)) "ordinary project save created a shadow DB"
  return Json.mkObj [("nativeTurnBoundary",old),("privateIngress",journal),
    ("ordinaryPromptDeliveredOriginal",toJson true),("nativeToolPrePostStop",toJson true),
    ("privateMemoAcrossOwners",toJson true),("queriesNeverAdvanceOriginalHeads",toJson true),
    ("sourceAckBindsCapturedQuery",toJson true),("retryHeadUnchanged",toJson true),
    ("saveWorker",toJson true),("derivedPreparationQueued",toJson saved.preparationQueued),
    ("missingAndReorderedCaptureRejected",toJson true),("noShadowDb",toJson true),
    ("stdoutSha256",toJson (Sha256.hex output.toUTF8)),
    ("preBytes",toJson pre.utf8ByteSize),("postBytes",toJson post.utf8ByteSize),
    ("hookMs",Json.mkObj [("prompt",toJson promptMs),("pre",toJson preMs),
      ("post",toJson postMs),("stop",toJson stopMs)])]

private def run (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute context root required"
  FileSystem.privateDirectory root
  let _ ← ProjectStore.create (root/"work.project") 4
  let _ ← ProjectStore.create (root/"reference.project") 2
  IO.FS.writeFile (root/"eggshell.toml")
    "default = \"work\"\nsemantic_matcher = false\n[eggs]\nwork = \"work.project\"\nreference = \"reference.project\"\n[profiles.work]\nread = [\"reference\"]\nwrite = \"work\"\nhandoff_chars = 120000\n"
  try
    seed root (root/"reference.project") "foreign-first" "OLD_ID_ALPHA"
    -- The turn starts from prepared source indexes. Later foreign publication
    -- stays pending; concurrent replacement of prepared roots is a separate gate.
    let source ← openProject (root/"reference.project")
    let prepared ← pin source ((← IO.monoMsNow)+20000)
    for source in prepared.sources do
      let _ ← Warm.prepareSourceIndexes source .user
      let _ ← Build.refresh source .user
      let _ ← CanonicalSource.Cache.refresh source .user
    -- Seed ingress has separate native identities and is not this turn's feed.
    let registry ← Journal.registry
    if ← registry.pathExists then IO.FS.removeDirAll registry
    let result ← runHooks root
    let report := Json.mkObj [("allPassed",toJson true),("checks",result),
      ("answeringModelCalls",toJson (0 : Nat)),("notCapacityOrTokenEvidence",toJson true)]
    IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
    IO.println report.compress
  finally
    Worker.shutdown
    try let _ ← Publication.Client.control "shutdown" catch _ => pure ()

private def diagnose (root : System.FilePath) : IO Unit := do
  let pending ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))
  let files ← sessionFiles pending.sessionId
  let some state ← (readJson? files.state stateJsonDefaults : IO (Option ThreadState)) |
    throw (IO.userError "diagnostic native state missing")
  try
    let request : Worker.Search := {pending,state,work := pending.prompt,enforce := false,deadline := (← IO.monoMsNow)+28000}
    IO.println (toJson (← Worker.search request)).compress
  finally
    Worker.shutdown
    try let _ ← Publication.Client.control "shutdown" catch _ => pure ()

end Eggshell.Research.ProjectContextChecks

def main (args : List String) : IO UInt32 := do
  match args with
  | ["codex-publication-daemon"] => Eggshell.Plugin.Publication.Service.run
  | ["serve"] => Eggshell.Plugin.Publication.Service.run
  | ["owners80",root] => projectInputsCommand [root]
  | ["inspect",root] => projectInputsCommand ["inspect",root]
  | ["codex-worker",role] => Eggshell.Plugin.Worker.run role
  | ["inspect-context",root] =>
    IO.println (← Eggshell.Research.ProjectContextChecks.inspect (.mk root)).compress
    return 0
  | ["diagnose-context",root] => Eggshell.Research.ProjectContextChecks.diagnose (.mk root); return 0
  | [root] => Eggshell.Research.ProjectContextChecks.run (.mk root); return 0
  | _ => throw (IO.userError "ProjectContextChecks ROOT | inspect-context ROOT")
