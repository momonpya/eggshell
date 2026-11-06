import Eggshell.PublicationService
import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.DB Eggshell.Synapses
open Eggshell.Plugin.Publication.Service
#print axioms StatsSnapshot.original_fields
#print axioms StatsSnapshot.exact_counters
#print axioms stats_snapshot_boundary
#print axioms resolveSource_present
#print axioms resolveSource_foreign
#print axioms resolveSource_missing
#print axioms scopedSource_snapshot_boundary

-- Bind the implementation, rather than merely proving a disconnected model.
run_cmd do
  let environment ← getEnv
  let value (name : Name) := do
    let some declaration := environment.find? name | throwError "missing status declaration {name}"
    let some body := declaration.value? | throwError "opaque status declaration {name}"
    pure body
  let actual ← value ``stats
  for name in #[``StatsSnapshot.capture,``collectStats] do
    unless actual.getUsedConstants.contains name do throwError "actual stats lost snapshot boundary {name}"
  let collect ← value ``collectStats
  if collect.getUsedConstants.contains ``Server.state then
    throwError "status collection reentered publication state"
  let authorization ← value ``scopedSource
  unless authorization.getUsedConstants.contains ``resolveSource do
    throwError "read authorization lost pure resolver"
  let mut pending := [``StatsSnapshot.capture,``StatsSnapshot.fields,``resolveSource]
  let mut seen : Std.HashSet Name := {}
  while let some name := pending.head? do
    pending := pending.tail!
    if seen.contains name then continue
    seen := seen.insert name
    let text := name.toString
    if ["Std.Mutex.","IO.Ref.","IO.Promise.","IO.asTask","IO.wait","ST.Ref."].any (fun stem => text.startsWith stem) then
      throwError "pure status snapshot reaches synchronization {name}"
    if let some declaration := environment.find? name then
      if let some body := declaration.value? then pending := body.getUsedConstants.toList++pending
  logInfo m!"Audited actual stats capture/collect boundary and {seen.size} pure snapshot dependencies"

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def makeServer (state : State) : IO Server := do
  let originals ← CanonicalSource.Shared.Pool.new
  return ⟨← Std.Mutex.new state,← Std.Mutex.new 0,← IO.mkRef false,
    ← Std.Mutex.new #[],originals,← CanonicalSource.Leases.Pool.new originals,
    ← ObservedRecordView.Cache.new,← Std.Mutex.new 0,← Std.Mutex.new #[],
    ← SharedReadViews.Pool.new,← Plugin.Publication.Owned.Pool.new,
    ← Plugin.PreparationService.Pool.new,← Plugin.OperationPool.Pool.new⟩
def checks (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh snapshot status check required"
  IO.FS.createDirAll root
  let source ← PageMap.pin "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/frontend-quiescence-fixture-small1/work.project/owners/0/source.egg"
  let project : ProjectState := ⟨source.directory,source.head.identity,"test-only",source.handle,#[],false⟩
  let initial : State := {
    projects := #[project,{project with active := true}]
    admittedBytes := 123
    publishedGroups := 7
    publishedReplies := 9 }
  let server ← makeServer initial
  let snapshot := StatsSnapshot.capture initial
  let entered : IO.Promise Unit ← IO.Promise.new
  let release : IO.Promise Unit ← IO.Promise.new
  let holding ← IO.asTask (server.state.atomically do
    entered.resolve ()
    discard <| IO.wait release.result!
    set {initial with admittedBytes := 456,publishedGroups := 11}) .dedicated
  let running ← IO.mkRef (none : Option (Task (Except IO.Error Json)))
  let captured ← try
    TaskDeadline.wait (Std.Async.AsyncTask.ofPurePromise entered) ((← IO.monoMsNow)+2000)
    let task ← IO.asTask (collectStats server snapshot) .dedicated
    running.set (some task)
    TaskDeadline.wait task ((← IO.monoMsNow)+2000)
  finally
    release.resolve ()
    discard <| IO.wait holding
    if let some task ← running.get then discard <| IO.wait task
  for (key,expected) in snapshot.fields do
    check (captured.getObjValD key == expected) "captured publication fields changed"
  let live ← stats server
  check (live.getObjValD "admittedBytes" == toJson (456 : Nat) &&
    live.getObjValD "publishedGroups" == toJson (11 : Nat) &&
    captured.getObjValD "admittedBytes" == toJson (123 : Nat) &&
    captured.getObjValD "publishedGroups" == toJson (7 : Nat)) "snapshot mixed publication states"
  let fresh ← server.state.atomically do return StatsSnapshot.capture (← get)
  check (live == (← collectStats server fresh)) "actual status disagreed with the captured reference"
  for key in ["preparedSources","retainedSources","paletteQueries","replyBytes","deferredReplies",
      "ownedProjects","preparation","operations","workerPipes","statsOwnerHeap"] do
    check (live.getObjValD key == captured.getObjValD key) "unchanged child schema or values changed"
  let registered : ReadSource := ⟨source.directory,source.head.identity,.database,"scope-a","secret-a"⟩
  server.sources.atomically (set #[registered])
  let directory ← server.sources.atomically get
  let sourceEntered : IO.Promise Unit ← IO.Promise.new
  let sourceRelease : IO.Promise Unit ← IO.Promise.new
  let holder ← IO.asTask (server.sources.atomically do
    sourceEntered.resolve ()
    discard <| IO.wait sourceRelease.result!) .dedicated
  let reads ← IO.mkRef (none : Option (Task (Except IO.Error Unit)))
  try
    TaskDeadline.wait (Std.Async.AsyncTask.ofPurePromise sourceEntered) ((← IO.monoMsNow)+2000)
    let task ← IO.asTask (do
      for _ in [:4096] do
        let allowed ← IO.ofExcept (resolveSource directory "secret-a" source.head.identity "scope-a")
        check (allowed.scope == registered.scope && allowed.directory == registered.directory) "registered source changed"
        check ((resolveSource directory "foreign" source.head.identity "scope-a").toOption.isNone) "foreign capability accepted"
        check ((resolveSource directory "secret-a" "foreign" "scope-a").toOption.isNone) "foreign database accepted"
        check ((resolveSource directory "secret-a" source.head.identity "foreign").toOption.isNone) "foreign scope accepted") .dedicated
    reads.set (some task)
    TaskDeadline.wait task ((← IO.monoMsNow)+2000)
  finally
    sourceRelease.resolve ()
    discard <| IO.wait holder
    if let some task ← reads.get then discard <| IO.wait task
  let payload := Json.mkObj [("database",toJson source.head.identity),("scope",toJson "scope-a")]
  let actual ← scopedSource server "secret-a" payload
  check (actual.scope == registered.scope && actual.capability == registered.capability) "actual source lookup changed"
  server.prepared.close
  server.palettes.close
  server.operations.close
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("publicationMutexHeldThroughoutChildCollection",toJson true),
    ("allChildReportsCompletedWhileHeld",toJson true),("capturedAndLiveStatesSeparated",toJson true),
    ("actualStatsEqualCapturedReference",toJson true),("captured",captured),("live",live),
    ("sourceRegistryMutexHeldThroughout4096PureLookups",toJson true),
    ("foreignCapabilityDatabaseScopeRejected",toJson true),("actualScopedSourceConnected",toJson true),
    ("notWholeRetrievalLockFreedom",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false)]).compress
def main (args : List String) : IO UInt32 := do
  match args with
  | ["snapshot-stats-check",root] => checks (.mk root); return 0
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain"
      args := #["front-traffic-audit",source]}
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | other => sourceRouteEngine other
