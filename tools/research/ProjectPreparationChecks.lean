import Eggshell.PreparationService
import Eggshell.PluginCli
import Eggshell.Daemon
import tools.research.ProjectCacheChecks
import tools.research.ProjectPreparationNumerical

open Lean Eggshell Eggshell.Plugin

namespace Eggshell.Research.ProjectPreparationChecks

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def job (name source : String) (semantic : Option String := none) (bytes : Nat := 1) : PreparationPlan.Job :=
  ⟨name,source,semantic,Json.null,bytes,0,0⟩

private def model : IO Unit := do
  let lane0 : PreparationPlan.Lane := ⟨0,by decide⟩
  let lane1 : PreparationPlan.Lane := ⟨1,by decide⟩
  let initial := PreparationPlan.initial
  let (queued,_) := PreparationPlan.notify initial (job "a" "source-a")
  let (queued,_) := PreparationPlan.notify queued (job "a" "source-a")
  check (queued.contents.pending.size == 1 && queued.contents.coalesced == 1) "pending requests were not coalesced"
  let (running,active) := PreparationPlan.take queued lane0 0
  let some active := active | throw (IO.userError "first owner did not start")
  let (running,_) := PreparationPlan.notify running (job "a" "source-a")
  let done := PreparationPlan.finish running lane0 active.token 0 true
  check (done.contents.pending.size == 1) "active completion erased a newer notification"
  let (next,again) := PreparationPlan.take done lane0 0
  let some again := again | throw (IO.userError "new notification disappeared")
  let stale := PreparationPlan.finish next lane0 active.token 0 true
  check (stale.contents.running[lane0].any (·.token == again.token)) "stale completion consumed another lease"
  let retry := PreparationPlan.finish next lane0 again.token 0 false
  check ((PreparationPlan.take retry lane0 49).2.isNone && (PreparationPlan.take retry lane0 50).2.isSome)
    "retry backoff lost or immediately restarted work"
  let closed := PreparationPlan.close running
  check (!(PreparationPlan.notify closed (job "b" "source-b")).2 &&
    (PreparationPlan.take closed lane1 0).2.isNone &&
    (PreparationPlan.finish closed lane0 active.token 0 false).contents.pending.isEmpty)
    "closed preparation restarted or requeued work"
  let (same,_) := PreparationPlan.notify initial (job "a" "source-a" (some "project"))
  let (same,_) := PreparationPlan.notify same (job "b" "source-b" (some "project"))
  let (same,_) := PreparationPlan.take same lane0 0
  check ((PreparationPlan.take same lane1 0).2.isNone) "two jobs acquired the project's numerical writer"
  let (other,_) := PreparationPlan.notify same (job "c" "source-c" (some "another-project"))
  check ((PreparationPlan.take other lane1 0).2.isSome) "independent projects were serialized"
  let mut full := initial
  for i in [:PreparationPlan.maxRequests] do
    let (next,admitted) := PreparationPlan.notify full (job (toString i) (toString i))
    check admitted "queue rejected work below its request bound"
    full := next
  check (!(PreparationPlan.notify full (job "overflow" "overflow")).2) "queue exceeded its request bound"
  let (bytes,_) := PreparationPlan.notify initial (job "large" "large" none PreparationPlan.maxBytes)
  check (!(PreparationPlan.notify bytes (job "byte-overflow" "another")).2) "queue exceeded its byte bound"
  IO.println (Json.mkObj [("pureStateChecks",toJson true),("requestBound",toJson PreparationPlan.maxRequests),
    ("workers",toJson PreparationPlan.workers),("answeringModelCalls",toJson (0 : Nat))]).compress

private def preparationStats : IO Json := do
  let all ← IO.ofExcept (Json.parse (← Publication.Client.control "stats"))
  IO.ofExcept (all.getObjVal? "preparation")

private def idle (deadline : Nat) : IO Json := do
  repeat
    let value ← preparationStats
    if (value.getObjValAs? Nat "pending").toOption == some 0 &&
        (value.getObjValAs? Nat "active").toOption == some 0 then return value
    check ((← IO.monoMsNow) < deadline) s!"shared preparation did not drain: {value.compress}"
    IO.sleep 5
  throw (IO.userError "unreachable preparation wait")

private def targetsReady (targets : Array IndexTarget) : IO Unit := do
  for target in targets do
    let source ← target.owner.pin
    check (!(← Warm.required target source)) "shared worker left a required source cold"
    let work ← PreparationRegistry.request "index" target.key
    check (← PreparationRegistry.drained work) "shared worker lost durable preparation debt"

private def diagnose (root : System.FilePath) : IO Unit := do
  let original ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))
  try
    let _ ← flushIndexesResult original.sessionId ((← IO.monoMsNow)+10000)
    for _ in [:5] do
      IO.println (← preparationStats).compress
      IO.sleep 200
    let sources ← maintenanceSources original.sessionId ((← IO.monoMsNow)+10000)
    for (_,target) in ← registeredIndexTargets sources do
      let work ← PreparationRegistry.request "index" target.key
      IO.println (Json.mkObj [("index",toJson work.key),("debt",← PreparationRegistry.explain work)]).compress
    for (_,target) in ← Synapses.Journal.targets sources do
      let work ← PreparationRegistry.request "synapses" (Synapses.Index.contentKey target)
      IO.println (Json.mkObj [("synapses",toJson work.key),("debt",← PreparationRegistry.explain work)]).compress
  finally
    Worker.shutdown
    try let _ ← Publication.Client.control "shutdown" catch _ => pure ()

private def idleManager (root : System.FilePath) : IO Unit := do
  let original ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))
  let pending ← ProjectContext.capture {original with
    sessionId := "idle-preparation-manager",turnId := "idle",projectInputs := none,
    tools := [],finalMessage := none,closed := false} ((← IO.monoMsNow)+20000)
  let files ← sessionFiles pending.sessionId
  writeJson files.state ({profile := pending.profile} : ThreadState)
  writeJson files.pending pending
  markPreparationWake pending.sessionId
  let _ ← Publication.Client.resolve
  let baseline ← preparationStats
  let admitted := fun (value : Json) => (value.getObjValAs? Nat "accepted").toOption.getD 0+
    (value.getObjValAs? Nat "coalesced").toOption.getD 0
  let manager ← IO.Process.spawn {
    cmd := (← IO.appPath).toString,args := #["codex-daemon",pending.sessionId]
    stdin := .null,stdout := .null,stderr := .null,setsid := true}
  let endpoint ← Daemon.awaitEndpoint pending.sessionId 500
  try
    let deadline := (← IO.monoMsNow)+20000
    repeat
      if admitted (← preparationStats) > admitted baseline then break
      check ((← IO.monoMsNow) < deadline) "daemon did not process its first preparation wake"
      IO.sleep 5
    let first ← idle deadline
    IO.sleep 2200
    let quiet ← preparationStats
    check (admitted first == admitted quiet) "idle daemon resubmitted unchanged preparation targets"
    markPreparationWake pending.sessionId
    repeat
      if admitted (← preparationStats) > admitted quiet then break
      check ((← IO.monoMsNow) < deadline) "daemon lost a newer preparation wake"
      IO.sleep 5
    let newer ← idle deadline
    let report := Json.mkObj [("allPassed",toJson true),("idleMs",toJson (2200 : Nat)),
      ("before",first),("afterIdle",quiet),("afterWake",newer),
      ("unchangedTargetsNotResubmitted",toJson true),("newWakeProcessed",toJson true)]
    IO.FS.writeFile (root/"idle-manager-report.json") (report.pretty++"\n")
    IO.println report.compress
  finally
    try let _ ← Daemon.exchange endpoint "shutdown" (budget := 1000) catch _ => pure ()
    let _ ← manager.wait
    try let _ ← Publication.Client.control "shutdown" catch _ => pure ()

private def publishDuring (root : System.FilePath) (pending : PendingTurn) : IO (DB.PageMap.Head × Bool) := do
  let files ← sessionFiles pending.sessionId
  let state : ThreadState := {profile := pending.profile}
  writeJson files.state state
  let domain := Sha256.hex "project-preparation-native".toUTF8
  let input := fun nanos => Json.mkObj [("_eggshell_synapse_clock",toJson domain),("_eggshell_synapse_nanos",toJson nanos)]
  let tools : List ToolEvent := (List.range 4).map fun index => {
    name := "mcp__fixture__inspect",useId := s!"late-{index}",
    input := (Json.mkObj [("key",toJson s!"late-{index}")]).compress,
    response := (Json.mkObj [("evidence",toJson s!"LATE_ORIGINAL_{index}"),
      ("body",toJson (String.ofList (List.replicate 8000 'x')))]).compress }
  for (tool,index) in tools.zipIdx do
    Synapses.Live.start (input (index*2+1)) files pending state tool
    Synapses.Live.finish (input (index*2+2)) pending tool
  let active ← preparationStats
  let overlap := (active.getObjValAs? Nat "active").toOption.any (· > 0)
  let pending := {pending with tools,finalMessage := some "Recorded `LATE_ORIGINAL_0` through `LATE_ORIGINAL_3`."}
  let some path := pending.write | throw (IO.userError "native preparation test needs a write project")
  let saved ← Publication.Client.run pending (.mk path) false
  check (saved.source.accounted && saved.source.awaiting == 0) "concurrent original publication lost its durable ACK"
  let selection ← ProjectAccess.resolve pending.sessionId (pendingSelection pending)
  let some write := selection.write | throw (IO.userError "concurrent source owner disappeared")
  let source ← write.project.current write.slot.val
  let target ← queueIndexAt source [(← IO.appPath).toString,"search-provider","--mode","lexical"] saved.promotion
  check (← Publication.Client.enqueuePreparation "index" target.key ((← IO.monoMsNow)+10000)) "late original could not wake preparation"
  let _ ← flushIndexesResult pending.sessionId ((← IO.monoMsNow)+10000)
  IO.FS.writeFile (root/"late-turn.json") ((toJson pending).pretty++"\n")
  return (source.head,overlap)

private def integration (root : System.FilePath) : IO Unit := do
  model
  let original ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))
  let pending ← ProjectContext.capture {original with
    sessionId := "preparation-native",turnId := "new-source",projectInputs := none,
    tools := [],finalMessage := none,closed := false} ((← IO.monoMsNow)+20000)
  let some context ← ProjectContext.open? pending ((← IO.monoMsNow)+20000) |
    throw (IO.userError "complete preparation test scope did not capture")
  let before := context.reads.sources.map (·.head)
  let files ← sessionFiles pending.sessionId
  writeJson files.pending pending
  let command := [(← IO.appPath).toString,"search-provider","--mode","lexical"]
  let targets ← context.reads.sources.mapM fun source => do
    let writable := context.canPrepare (DB.Sidecar.Owner.ofSnapshot source)
    let target ← registerIndexTarget source command writable
    let sidecar ← DB.Sidecar.locate source target.storage
    let lexical := sidecar.directory/"lexical"
    if ← lexical.pathExists then IO.FS.removeDirAll lexical
    return target
  let _ ← Publication.Client.resolve
  let started ← IO.monoMsNow
  try
    let notifications ← (List.range 80).mapM fun index =>
      IO.asTask (do
        let some target := targets[index % targets.size]? | throw (IO.userError "no checked target")
        Publication.Client.enqueuePreparation "index" target.key ((← IO.monoMsNow)+20000)) .dedicated
    let publication ← IO.asTask (publishDuring root pending) .dedicated
    for notification in notifications do
      check (← IO.ofExcept (← IO.wait notification)) "bounded target wake was not admitted"
    let (published,overlap) ← IO.ofExcept (← IO.wait publication)
    let complete ← idle ((← IO.monoMsNow)+60000)
    targetsReady targets
    check ((complete.getObjValAs? Nat "peakActive").toOption.any (· ≥ 2)) "independent source preparation never overlapped"
    check ((complete.getObjValAs? Nat "workers").toOption == some 3) "preparation worker bound changed"
    for source in context.reads.sources do
      let current ← DB.PageMap.pin source.directory
      if source.head.identity == published.identity then
        check (current.head == published) "preparation changed its concurrently published original"
      else
        check (current.head == source.head) "preparation wrote into another original source"
    let firstMs := (← IO.monoMsNow)-started
    -- Force real cold lexical work, then stop a service with admitted active work.
    for target in targets do
      let source ← target.owner.pin
      let lexical := (← DB.Sidecar.locate source target.storage).directory/"lexical"
      if ← lexical.pathExists then IO.FS.removeDirAll lexical
      let _ ← Publication.Client.enqueuePreparation "index" target.key ((← IO.monoMsNow)+10000)
      pure ()
    let activeDeadline := (← IO.monoMsNow)+10000
    let mut activeAtStop := Json.null
    repeat
      let current ← preparationStats
      if (current.getObjValAs? Nat "active").toOption.any (· > 0) then
        activeAtStop := current
        break
      check ((← IO.monoMsNow) < activeDeadline) "no active preparation was available for shutdown test"
      IO.sleep 1
    let stopped ← IO.monoMsNow
    let _ ← Publication.Client.control "shutdown"
    repeat
      if (← Publication.Client.endpoint?).isNone then break
      check ((← IO.monoMsNow)-stopped < 5000) "shutdown waited for derived preparation"
      IO.sleep 5
    let shutdownMs := (← IO.monoMsNow)-stopped
    let _ ← Publication.Client.resolve
    for target in targets do
      check (← Publication.Client.enqueuePreparation "index" target.key ((← IO.monoMsNow)+10000))
        "restart did not recover preparation intent"
    let recovered ← idle ((← IO.monoMsNow)+60000)
    targetsReady targets
    for source in context.reads.sources do
      let current ← DB.PageMap.pin source.directory
      check (current.head == (if source.head.identity == published.identity then published else source.head))
        "preparation recovery changed an acknowledged original"
    let report := Json.mkObj [("allPassed",toJson true),("notifications",toJson (80 : Nat)),
      ("completeSourceInventory",toJson targets.size),("initialSourceHeads",toJson before),
      ("initialPreparation",complete),("sourcePublicationObservedActivePreparation",toJson overlap),
      ("sourceAckAndOriginalsPreserved",toJson true),("firstPhaseMs",toJson firstMs),
      ("activeAtShutdown",activeAtStop),("shutdownMs",toJson shutdownMs),("recoveredPreparation",recovered),
      ("answeringModelCalls",toJson (0 : Nat)),("eightyPersonEightHourCapacity",toJson false),
      ("requiredEvidenceRecallProven",toJson false),("productionAdoption",toJson false)]
    IO.FS.writeFile (root/"preparation-service-report.json") (report.pretty++"\n")
    IO.println report.compress
  finally
    Worker.shutdown
    try let _ ← Publication.Client.control "shutdown" catch _ => pure ()

end Eggshell.Research.ProjectPreparationChecks

def command (args : List String) : IO UInt32 := do
  match args with
  | ["model"] => Eggshell.Research.ProjectPreparationChecks.model; return 0
  | ["integration",root] => Eggshell.Research.ProjectPreparationChecks.integration (.mk root); return 0
  | ["diagnose",root] => Eggshell.Research.ProjectPreparationChecks.diagnose (.mk root); return 0
  | ["idle",root] => Eggshell.Research.ProjectPreparationChecks.idleManager (.mk root); return 0
  | ["numerical",root] => numericalPreparationCommand [(← IO.appPath).toString,root]; return 0
  | ["codex-daemon",session] => Eggshell.Plugin.Daemon.run session
  | other => projectCacheCommand other

def main (args : List String) : IO UInt32 := do
  if ["codex-worker","codex-daemon","search-provider","keyed-search-provider"].contains (args.headD "") ||
      args.take 2 == ["egg","warm"] then
    Numerical.withDefaultKeeper (command args)
      (drainMs := if args.head? == some "codex-daemon" || args.take 2 == ["egg","warm"] then 1000 else 0)
  else command args
