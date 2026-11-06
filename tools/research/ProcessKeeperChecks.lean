import Main
import Eggshell.ContractAudit
open Lean Eggshell
#print axioms frontend_has_no_process_keeper
#print axioms publication_has_process_keeper
#print axioms warm_has_process_keeper
#print axioms run_frontend_without_process_keeper
#print axioms Numerical.foreign_owner_not_polled
#print axioms Numerical.same_owner_polled
#print axioms DB.PageMap.PagePool.reader_find_is_local
#print axioms DB.PageMap.PagePool.reader_insert_is_local
#print axioms DB.PageMap.PagePool.reader_has_no_owner
run_cmd do
  let environment ← getEnv
  for (caller,required) in [(``sourceRouteEngine,``runProcess),(``runProcess,``processKeepsModel),
      (``runProcess,``dispatchEngine),(``SearchProvider.encoder,``Numerical.openClient),
      (``Numerical.openClient,``Numerical.keep),(``Numerical.proxy,``Numerical.openClient),
      (``Numerical.alive,``Numerical.ownedExit)] do
    let some declaration := environment.find? caller | throwError "missing lifecycle caller {caller}"
    let some value := declaration.value? | throwError "opaque lifecycle caller {caller}"
    unless value.getUsedConstants.contains required do throwError "disconnected lifecycle {caller} -> {required}"
  logInfo "Process role lifetime connected;actual numerical clients keep their own live claims"
  -- Check the actual captured path, not a separate lock-free model. The
  -- PagePool reader laws separately specialize the mixed owner/reader API.
  for (caller,required) in [(``Plugin.Publication.Service.sourcePlan,``Synapses.SharedReadViews.Source.readMetadata),
      (``Plugin.Publication.Service.readSourceViews,``Synapses.SharedReadViews.Source.focusWindows)] do
    let some declaration := environment.find? caller | throwError "missing captured caller {caller}"
    let some value := declaration.value? | throwError "opaque captured caller {caller}"
    unless value.getUsedConstants.contains required do throwError "disconnected captured read {caller} -> {required}"
  let forbidden := fun (name : Name) => ["Std.Mutex.","IO.Ref.","IO.Promise.",
    "IO.asTask","IO.wait","IO.sleep","Eggshell.FileSystem.tryReadLock",
    "Eggshell.Persistence.withLock"].any (fun stem => name.toString.startsWith stem)
  unless forbidden ``Std.Mutex.atomically && forbidden ``IO.wait &&
      forbidden ``FileSystem.tryReadLock do throwError "read synchronization detector lost its negative controls"
  let mut pending := [``Synapses.SharedReadViews.Source.readRecords,
    ``Synapses.SharedReadViews.Source.readMetadata,``Synapses.SharedReadViews.Source.focusWindows,
    ``Synapses.PreparedSourceView.fileReady,``Synapses.PreparedSourceView.FileReady.addExtents,
    ``DB.PageMap.LocalPages.readView]
  let mut seen : Std.HashSet Name := {}
  while let some name := pending.head? do
    pending := pending.tail!
    if seen.contains name then continue
    seen := seen.insert name
    if forbidden name then throwError "captured immutable read reaches synchronization {name}"
    if let some declaration := environment.find? name then
      if let some value := declaration.value? then pending := value.getUsedConstants.toList++pending
  logInfo m!"Captured immutable read closure: {seen.size} declarations;no shared lock,ref,promise,task or wait"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def foreignChildCheck (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh foreign child control required"
  IO.FS.createDirAll root
  let called ← IO.mkRef (0 : Nat)
  check (!(← Numerical.ownedExit 1 2 (do called.modify (·+1); pure true)) && (← called.get) == 0)
    "foreign ownership executed a poll"
  let child : Numerical.Service ← IO.Process.spawn {
    cmd := (← IO.appPath).toString,args := #["keeper-noop"],stdin := .null,stdout := .null,stderr := .inherit}
  Numerical.ownedServices.atomically (modify (·.push child))
  try
    let deadline := (← IO.monoMsNow)+3000
    repeat
      let state ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString child.pid,"-o","stat="]}
      if state.exitCode != 0 || !(Numerical.processStateLive state.stdout.trimAscii.copy) then break
      check ((← IO.monoMsNow) < deadline) "owned noop child did not exit"
      IO.sleep 5
    check (← Numerical.alive (← IO.Process.getPID).toNat) "own process was not live"
    check ((← child.tryWait).isSome) "foreign liveness probe stole another child's result"
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("foreignPollCalls",toJson (← called.get)),
      ("unrelatedExitedChildRemainsWaitable",toJson true),("searchOrModelRequests",toJson (0 : Nat)),("adopted",toJson false)]).compress
  finally
    Numerical.ownedServices.atomically (modify (·.filter (fun entry => entry.pid != child.pid)))

def contentionCheck (root : System.FilePath) (parent : String) : IO Unit := do
  check (!(← root.pathExists)) "fresh ownership contention control required"
  IO.FS.createDirAll root
  let some config ← Numerical.defaultConfig? | throw (IO.userError "installed numerical runtime required")
  let handle ← Numerical.lockFile ((← Numerical.directory config)/"owners.guard")
  check (← FileSystem.tryReadLock handle true) "empty numerical owner guard already held"
  try
    let started ← IO.monoMsNow
    let old ← IO.Process.output {cmd := parent,args := #["codex-daemon","shutdown"]}
    let oldMs := (← IO.monoMsNow)-started
    let started ← IO.monoMsNow
    let fixed ← IO.Process.output {cmd := (← IO.appPath).toString,args := #["codex-daemon","shutdown"]}
    let fixedMs := (← IO.monoMsNow)-started
    check (old.exitCode != 0 && old.stderr.contains "deadline expired" && oldMs ≥ 9000)
      "parent did not reproduce the unnecessary model-ownership dependency"
    check (fixed.exitCode == 0 && fixedMs < 3000) "administrative command still waits for unrelated model ownership"
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("exclusiveModelGuardHeld",toJson true),
      ("parentExit",toJson old.exitCode.toNat),("parentStderr",toJson old.stderr),("parentMs",toJson oldMs),
      ("candidateExit",toJson fixed.exitCode.toNat),("candidateStderr",toJson fixed.stderr),("candidateMs",toJson fixedMs),
      ("searchOrModelRequests",toJson (0 : Nat)),("adopted",toJson false)]).compress
  finally FileSystem.unlockRead handle

def lifetimeCheck (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh process lifetime control required"
  IO.FS.createDirAll root
  let some config ← Numerical.defaultConfig? | throw (IO.userError "installed numerical runtime required")
  let client ← Numerical.openClient config
  try
    let numerical ← Numerical.resolve config
    let publisher ← Plugin.Publication.Client.resolve
    let frontend ← Plugin.Daemon.ensure "lifetime-owner-control"
    let started ← IO.monoMsNow
    Plugin.Daemon.shutdown
    let stoppedMs := (← IO.monoMsNow)-started
    check (!(← Plugin.Daemon.running frontend)) "frontend stayed live after shutdown"
    discard <| Plugin.Daemon.exchange numerical "ping" (budget := 1000)
    client.close
    discard <| Plugin.Daemon.exchange numerical "ping" (budget := 1000)
    let stats ← IO.ofExcept (Json.parse (← Plugin.Daemon.exchange numerical "stats"))
    check (stats.getObjValD "modelStarts" == toJson (0 : Nat) &&
      stats.getObjValD "rawStarts" == toJson (0 : Nat)) "lifecycle control unexpectedly started numerical computation"
    discard <| Plugin.Publication.Client.control "shutdown"
    check (!(← Numerical.alive publisher.pid) && !(← Numerical.alive numerical.pid)) "last owner failed to retire its service"
    for child in ← Numerical.ownedServices.atomically get do
      check ((← child.tryWait).isSome) "owned numerical child was not reaped"
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("frontendStopMs",toJson stoppedMs),
      ("numericalSurvivesFrontendStop",toJson true),("publicationOwnerRetainsServiceAfterClientClose",toJson true),
      ("lastOwnerRetiresService",toJson true),("ownedChildrenReaped",toJson true),
      ("numericalStats",stats),("searchOrModelRequests",toJson (0 : Nat)),("adopted",toJson false)]).compress
  finally
    client.close
    try Plugin.Daemon.shutdown catch _ => pure ()
    try discard <| Plugin.Publication.Client.control "shutdown" catch _ => pure ()
def main (args : List String) : IO UInt32 := do
  match args with
  | ["keeper-noop"] => return 0
  | ["keeper-foreign-child-check",root] => foreignChildCheck (.mk root); return 0
  | ["keeper-contention-check",root,parent] => contentionCheck (.mk root) parent; return 0
  | ["keeper-lifetime-check",root] => lifetimeCheck (.mk root); return 0
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain",
      args := #["front-traffic-audit",source]}
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | other => sourceRouteEngine other
