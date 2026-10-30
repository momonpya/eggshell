import Eggshell.PublicationClient
import Eggshell.PublicationService
import Eggshell.SynapseBuild
import Eggshell.UsageCache
import tools.research.RoutingScopeReference
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Routing

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def rejected (action : IO α) : IO Bool := try let _ ← action; pure false catch _ => pure true
private def same (a b : Store.Walk) : Bool := toJson a == toJson b

private def start (binary : String) : IO (IO.Process.Child {stdin := .null,stdout := .null,stderr := .piped} × Daemon.Endpoint) := do
  let child ← IO.Process.spawn {
    cmd := binary
    args := #["codex-publication-daemon"]
    stdin := .null
    stdout := .null
    stderr := .piped
    setsid := true}
  let deadline := (← IO.monoMsNow)+10000
  repeat
    check (← child.tryWait).isNone "routing service stopped on startup"
    if let some endpoint ← Publication.Client.endpoint? then
      check (endpoint.pid == child.pid.toNat) "another service owns routing audit endpoint"
      let _ ← Daemon.exchange endpoint "ping" (budget := 1000)
      return (child,endpoint)
    check ((← IO.monoMsNow) < deadline) "routing service startup expired"
    IO.sleep 5
  throw (IO.userError "unreachable routing service startup")

private def fact (query : String) (source : Range) (session : String) : Fact := .used {
  event := {occurrence := ⟨session,"turn","read"⟩,ordinal := 0},query,source,kind := .omittedThenRead}

def main (args : List String) : IO Unit := do
  let [binary,destination] := args | throw (IO.userError "routing runtime and fresh audit directory required")
  let root : System.FilePath := .mk destination
  check (!(← root.pathExists)) "preserve earlier routing service audit"
  IO.FS.createDir root
  let source ← DB.PageMap.pin (.mk "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/r0/stage1/history/source.egg")
  let _ ← Build.refresh source .user
  let _ ← CanonicalSource.Cache.refresh source .user
  let some index ← Index.open? source .user .shared | throw (IO.userError "real shared source is cold")
  let some routing ← Store.open? index | throw (IO.userError "real routing source is cold")
  let facts ← Index.allFacts index.index
  let ranges := (hashDistinct (facts.toList.filterMap fun fact =>
    (Index.bindingCandidate? fact).map (·.source))).toArray.qsort fun a b =>
      (toJson a).compress < (toJson b).compress
  check (ranges.size ≥ 3) "real source has too few original ranges"
  let query := Sha256.hex "routing service caller separation".toUTF8
  let _ ← Index.replace source .user .usage #[fact query ranges[0]! "caller-a"]
  let some a ← Index.open? source .user .usage | throw (IO.userError "caller A usage is missing")
  let some a ← Store.open? a | throw (IO.userError "caller A routing is cold")
  let _ ← Index.replace source .user .usage #[fact query ranges[1]! "caller-b"]
  let some b ← Index.open? source .user .usage | throw (IO.userError "caller B usage is missing")
  let some b ← Store.open? b | throw (IO.userError "caller B routing is cold")
  let deadline := (← IO.monoMsNow)+28000
  let ca ← PrivateView.capture a #[query] deadline
  let cb ← PrivateView.capture b #[query] deadline
  -- Poison the service account's conventional private classifier. The API
  -- must use caller capsules even when this other private history exists.
  let _ ← UsageCache.publish source {
    session := "service-account"
    turn := "turn"
    source := source.head
    view := Sha256.hex "isolated service classifier".toUTF8
    count := 1} #[fact query ranges[2]! "service-account"]
  check (← UsageCache.open? source).isSome "service-account usage poison was not installed"
  let roots := #[(Index.Key.query query,0)]
  let oa ← Store.referenceWalk routing (some a) roots ((← IO.monoMsNow)+28000)
  let ob ← Store.referenceWalk routing (some b) roots ((← IO.monoMsNow)+28000)
  let empty ← Store.referenceWalk routing none roots ((← IO.monoMsNow)+28000)
  check (oa.complete && ob.complete && empty.complete && !oa.hints.isEmpty && !ob.hints.isEmpty &&
    toJson oa != toJson ob) "real private routing oracles are empty, equal or incomplete"
  let (child,endpoint) ← start binary
  let reaped ← IO.mkRef false
  try
    let some reference ← Publication.Client.prepareSourceUsing endpoint source .user ((← IO.monoMsNow)+28000)
      | throw (IO.userError "service could not prepare the real source")
    let arrived ← Std.Mutex.new (0 : Nat)
    let released ← IO.mkRef false
    let tasks ← (Array.range 80).mapM fun client => IO.asTask (do
      arrived.atomically (modify (·+1))
      while !(← released.get) do IO.sleep 1
      let capsule := if client%2 == 0 then ca else cb
      let expected := if client%2 == 0 then oa else ob
      let begin ← IO.monoMsNow
      let reply ← Publication.Client.sourceRouting reference {basis := index.index.head,roots,usage := some capsule} (begin+28000)
      check (same reply.walk expected) "physical routing changed or leaked caller-private hints"
      return (← IO.monoMsNow)-begin) .dedicated
    let barrier := (← IO.monoMsNow)+10000
    repeat
      if (← arrived.atomically get) == 80 then break
      check ((← IO.monoMsNow) < barrier) "routing clients failed to reach the barrier"
      IO.sleep 1
    released.set true
    let times ← tasks.mapM fun task => IO.ofExcept (task.get.mapError IO.Error.toString)
    let none ← Publication.Client.sourceRouting reference {basis := index.index.head,roots,usage := none} ((← IO.monoMsNow)+28000)
    check (same none.walk empty) "service account's private history leaked into a caller without an overlay"
    let group := Group.answer source.head.identity (Persistence.selectionKey (.text "new shared routing group"))
    let _ ← Index.publishDelta source .user .shared (some index.manifest.source)
      {added := #[.coquoted group ranges[0]!,.coquoted group ranges[2]!]}
    let some changed ← Index.open? source .user .shared | throw (IO.userError "routing delta disappeared")
    let some newRouting ← Store.open? changed | throw (IO.userError "routing delta is cold")
    let expectedNew ← Store.referenceWalk newRouting (some a) roots ((← IO.monoMsNow)+28000)
    let next ← Publication.Client.sourceRouting reference {basis := changed.index.head,roots,usage := some ca}
      ((← IO.monoMsNow)+28000)
    check (same next.walk expectedNew && !same next.walk oa) "new routing view was hidden behind an older canonical preparation"
    let old ← Publication.Client.sourceRouting reference {basis := index.index.head,roots,usage := some ca}
      ((← IO.monoMsNow)+28000)
    check (same old.walk oa) "new routing publication changed an old pinned request"
    let wrong := {reference with endpoint := {reference.endpoint with secret := "wrong-secret"}}
    check (← rejected (Publication.Client.sourceRouting wrong {basis := index.index.head,roots,usage := some ca}
      ((← IO.monoMsNow)+5000))) "routing accepted a wrong capability"
    check (← rejected (Publication.Client.sourceRouting reference {basis := source.head,roots,usage := some ca}
      ((← IO.monoMsNow)+5000))) "routing accepted a different basis"
    let state ← IO.ofExcept (Json.parse (← Daemon.exchange endpoint "stats" (budget := 1000)))
    let acknowledged ← Daemon.exchange endpoint "shutdown" (budget := 1000)
    let stop := (← IO.monoMsNow)+5000
    repeat
      if let some code ← child.tryWait then
        reaped.set true
        check (code == 0) "routing service failed on shutdown"
        break
      check ((← IO.monoMsNow) < stop) "routing service did not stop"
      IO.sleep 5
    check (← Publication.Client.endpoint?).isNone "routing endpoint survived shutdown"
    check ((← DB.PageMap.pin source.directory).head == source.head) "routing service changed the original DB"
    let sorted := times.qsort (· < ·)
    let result := Json.mkObj [("clients",toJson times.size),("source",toJson source.head),
      ("p50Ms",toJson sorted[39]!),("p95Ms",toJson sorted[75]!),("maxMs",toJson sorted[79]!),
      ("callerAHints",toJson oa.hints.size),("callerBHints",toJson ob.hints.size),
      ("allOriginalOrdersCountersAndGroupsEqual",toJson true),("serviceAccountUsageIgnored",toJson true),
      ("capabilityAndBasisRejected",toJson true),("sourceUnchanged",toJson true),("service",state),
      ("routingDeltaWithoutCanonicalRebuild",toJson true),("oldRoutingPinPreserved",toJson true),
      ("shutdownAcknowledged",toJson (acknowledged == "true")),("endpointRemoved",toJson true),
      ("answeringModels",toJson (0 : Nat)),("actualHookMeasured",toJson false),("adopted",toJson false)]
    IO.FS.writeFile (root / "results.json") result.pretty
    IO.println result.compress
  finally
    unless ← reaped.get do
      if (← child.tryWait).isNone then
        child.kill
        let _ ← child.wait
        pure ()
      reaped.set true
