import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Plugin Eggshell.DB
namespace Eggshell.Research.SessionReaderChecks
#print axioms PreparedReaders.Frozen.matches_exact
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def check (accepted : Bool) (message : String) : IO Unit := unless accepted do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def refused (action : IO α) : IO Bool := do try let _ ← action; return false catch _ => return true
def observe (session : PreparedReaders.Session) (inputs : Array PreparedInputs.Reference)
    (reference : OwnerViews.Reference) : IO Json := do
  for source in session.sources do source.trace.set (some {})
  let borrow ← session.pool.acquire session.sources inputs (some reference)
  let shared ← (session.sources.zip inputs).mapM fun (source,input) =>
    Synapses.Recommend.capturedLocal source input (some (borrow.shared source input))
  let owners ← borrow.owners session.sources reference
  let ids ← match owners.base.allOwners with
    | none => pure []
    | some root => owners.base.bitmap.members root.height root
  let positions ← ids.mapM fun id => do
    let binding ← Plugin.preparedOwnerBinding owners id
    return (id,binding.originals)
  let traces ← session.sources.mapM fun source => do
    let some trace ← source.trace.get | throw (IO.userError "borrower trace missing")
    check trace.complete "borrower trace overflow"
    return (trace.operations.map (fun item => (PageMap.readObservationCodec.encode item).map UInt8.toNat),trace.encodedBytes)
  let next ← owners.base.bitmap.next.get
  let _ ← owners.base.bitmap.put 0 {bits := 1}
  let second ← borrow.owners session.sources reference
  check ((← second.base.bitmap.next.get) == next && (← second.base.bitmap.reads.get) == 0)
    "query mutation reached the immutable owner image"
  return Json.mkObj [("positions",toJson positions),("counts",toJson (← second.counts)),
    ("shared",toJson (shared.map fun item => item.shared.map fun reader => (reader.index.head,reader.manifest))),
    ("traceSha256",toJson (Sha256.hex (toJson traces).compress.toUTF8))]
def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve previous session-reader check"
  IO.FS.createDirAll root
  let source := base/"frontend-quiescence-fixture-small1/work.project"
  IO.FS.writeFile (root/"eggshell.toml") ("default = \"work\"\n[eggs]\nwork = \""++source.toString++
    "\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\n")
  let warm ← IO.Process.output {
    cmd := (← IO.appPath).toString
    args := #["egg","warm",source.toString]
    env := #[("EGGSHELL_CONFIG",some (root/"eggshell.toml").toString)]}
  IO.FS.writeFile (root/"warm.json") (Json.mkObj [("exitCode",toJson warm.exitCode.toNat),
    ("stdout",toJson warm.stdout),("stderr",toJson warm.stderr)]).pretty
  check (warm.exitCode == 0) "selected target did not prepare the source"
  let project ← ProjectStore.openProject source
  let view ← ProjectStore.pin project ((← IO.monoMsNow)+30000)
  let heads := view.sources.map (·.head)
  let inputs ← view.sources.mapM fun original => do
    let some input ← PreparedInputs.load? original MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "prepared source missing")
    return input
  let some reference ← OwnerViews.load? view.sources | throw (IO.userError "prepared owner root missing")
  let coordinator ← PreparedReaders.Pool.new
  let began ← IO.monoMsNow
  let frozen ← coordinator.freeze view.sources inputs (some reference)
  let freezeMs := (← IO.monoMsNow)-began
  let baseline ← frozen.fork view.sources inputs (some reference)
  let expected ← observe baseline inputs reference
  let forkStarted ← IO.monoMsNow
  let sessions ← (List.range 80).toArray.mapM fun _ => frozen.fork view.sources inputs (some reference)
  let forkMs := (← IO.monoMsNow)-forkStarted
  -- Distinct source counters demonstrate that the original reader state is
  -- request-owned before any simultaneous operations begin.
  for index in [:sessions.size] do
    let some session := sessions[index]? | throw (IO.userError "session missing")
    let some original := session.sources[0]? | throw (IO.userError "session source missing")
    original.reads.set (index+1)
  for index in [:sessions.size] do
    let some session := sessions[index]? | throw (IO.userError "session missing")
    let some original := session.sources[0]? | throw (IO.userError "session source missing")
    check ((← original.reads.get) == index+1) "different workers alias an original read counter"
    original.reads.set 0
  let start ← IO.Promise.new
  let tasks ← sessions.mapM fun session => IO.asTask (do
    discard <| IO.wait start.result!
    let observed ← observe session inputs reference
    check (observed == expected) "parallel worker changed owners, source references or dependency observations"
    let stats ← session.pool.stats
    check (stats.getObjValD "builds" == toJson (0 : Nat) && stats.getObjValD "hits" == toJson (1 : Nat))
      "worker rebuilt the public image or shared mutable catalogue state"
    return stats) .dedicated
  let parallelStarted ← IO.monoMsNow
  start.resolve ()
  let observations ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
  let parallelMs := (← IO.monoMsNow)-parallelStarted
  let coordinatorStats ← coordinator.stats
  check (coordinatorStats.getObjValD "builds" == toJson (1 : Nat) &&
    coordinatorStats.getObjValD "hits" == toJson (0 : Nat)) "workers mutated the coordinator cache"
  check (← refused (frozen.fork view.sources.reverse inputs.reverse (some reference))) "reordered source scope accepted"
  check (← refused (frozen.fork (view.sources.extract 0 15) (inputs.extract 0 15) (some reference))) "partial source scope accepted"
  check (← refused (frozen.fork view.sources inputs none)) "changed owner namespace accepted"
  let some first := inputs[0]? | throw (IO.userError "source input missing")
  check (← refused (frozen.fork view.sources (inputs.set! 0 {first with producer := first.producer++"!"}) (some reference)))
    "changed prepared producer accepted"
  for (original,head) in view.sources.zip heads do
    check ((← PageMap.pin original.directory).head == head) "reader component changed original publication"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("borrowers",toJson observations.size),
    ("originalSources",toJson view.sources.size),("freezeMs",toJson freezeMs),("fork80Ms",toJson forkMs),
    ("parallelObservationMs",toJson parallelMs),("coordinator",coordinatorStats),
    ("allOriginalBindingsAndTracesExact",toJson true),("mutableCountersAndBitmapsIsolated",toJson true),
    ("newPublicBuildsPerWorker",toJson (0 : Nat)),("rejectedBoundaries",toJson (4 : Nat)),
    ("originalHeadsUnchanged",toJson true),("actualHookDispatchTested",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
end Eggshell.Research.SessionReaderChecks
def main (args : List String) : IO UInt32 := do
  match args with
  | ["session-reader-checks",root] =>
    try Eggshell.Research.SessionReaderChecks.run (.mk root); return 0
    finally
      discard <| IO.Process.output {cmd := (← IO.appPath).toString,args := #["publication-control","shutdown"]}
  | other => sourceRouteEngine other
