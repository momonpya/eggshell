import Main
import Eggshell.CanonicalSourceLease
open Lean Eggshell Eggshell.DB Eggshell.Synapses.CanonicalSource
namespace Eggshell.Research.SharedLeaseChecks
#print axioms Leases.Descriptor.same_source
#print axioms Leases.State.within_capacity
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def refused (action : IO α) : IO Bool := do try let _ ← action; return false catch _ => return true
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def waitFlag (flag : IO.Promise Bool) (deadline : Nat) : IO Unit := do
  while !(← flag.isResolved) do
    TaskDeadline.ensureLive deadline
    IO.sleep 1
def checkedAccounting (pool : Leases.Pool) : IO Json := do
  let stats ← pool.stats
  check (stats.getObjValD "accountedExact" == toJson true &&
    stats.getObjValD "borrowersExact" == toJson true) "descriptor/token accounting is not exact"
  return stats
def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve preceding source-lease test"
  IO.FS.createDirAll root
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let captured ← read (base/"private-pages-smoke1-result/private/sessions/cpu-wave-a-0/pending.json")
  let inputs ← IO.ofExcept (fromJson? (((captured.getObjValD "preparedInputs").getObjValD "payload").getObjValD "inputs") :
    Except String (Array PreparedInputs.Reference))
  let heads ← IO.ofExcept (fromJson? (← read
    "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/worker-cpu/heads.json") :
    Except String (Array (String × String × String)))
  check (inputs.size == 16 && heads.size == 16) "complete fixture read cut changed"
  let sources ← inputs.mapM fun input => do
    let some (storage,metadata) := input.canonical | throw (IO.userError "captured canonical source missing")
    let some row := heads.find? (fun (_,bytes,_) =>
        (Json.parse bytes >>= fromJson? (α := PageMap.Head)).toOption == some input.source) |
      throw (IO.userError "captured source is not in the frozen original heads")
    let source ← PageMap.pin ((System.FilePath.mk row.1).parent.get!)
    check (source.head == input.source) "current original head differs from frozen cut"
    let path ← Cache.directory source storage
    return (source,metadata,path)
  let originals ← Shared.Pool.new
  let pool ← Leases.Pool.new originals
  try
    let start ← IO.monoMsNow
    let tasks ← (List.range 80).toArray.mapM fun _ => IO.asTask (do
      sources.mapM fun (source,metadata,path) => do
        let (token,_,_) ← pool.retain "authorized-project" source path metadata (start+24000) (start+28000)
        return token) .dedicated
    let mut cuts := #[]
    for task in tasks do cuts := cuts.push (← IO.ofExcept (← IO.wait task))
    let elapsed := (← IO.monoMsNow)-start
    let full ← checkedAccounting pool
    check (full.getObjValD "active" == toJson (1280 : Nat) &&
      full.getObjValD "sharedDescriptors" == toJson (16 : Nat)) "eighty full cuts did not share sixteen descriptors"
    let cache ← originals.state.atomically do
      let state ← get
      return (state.entries.size,state.entries.fold (fun total _ entry => total+entry.borrowers) 0)
    check (cache == (16,16)) "original cache has a per-chat descriptor pin"
    let some (source,metadata,_) := sources[0]? | throw (IO.userError "first source missing")
    let token := cuts[0]![0]!
    for (scope,head,manifest) in #[
      ("foreign-project",source.head,metadata),
      ("authorized-project",{source.head with revision := source.head.revision+1},metadata),
      ("authorized-project",source.head,{metadata with payload := "changed"})] do
      check (← refused (pool.withHeld token scope head manifest (start+28000) (fun _ _ => pure ())))
        "shared descriptor weakened exact scope/root/manifest checks"
    check (← refused (pool.release token "foreign-project")) "foreign scope released another request"
    let entered ← IO.Promise.new
    let finish ← IO.Promise.new
    let reader ← IO.asTask (pool.withHeld token "authorized-project" source.head metadata (start+28000) fun _ _ => do
      entered.resolve true
      waitFlag finish (start+28000)) .dedicated
    try
      waitFlag entered (start+28000)
      for cut in cuts do
        for held in cut do pool.release held "authorized-project"
      pool.release token "authorized-project"
      let during ← checkedAccounting pool
      check (during.getObjValD "active" == toJson (1 : Nat) &&
        during.getObjValD "sharedDescriptors" == toJson (1 : Nat) &&
        during.getObjValD "readers" == toJson (1 : Nat)) "active released reader lost its single descriptor charge"
      check (← refused (pool.withHeld token "authorized-project" source.head metadata (start+28000) (fun _ _ => pure ())))
        "released token admitted a new read"
    finally finish.resolve true
    IO.ofExcept (← IO.wait reader)
    let drained ← checkedAccounting pool
    check (drained.getObjValD "active" == toJson (0 : Nat) &&
      drained.getObjValD "chargedBytes" == toJson (0 : Nat)) "last reader retained descriptor or token charges"
    let some (source,metadata,path) := sources[0]? | throw (IO.userError "first source missing")
    let now ← IO.monoMsNow
    let (expiring,_,_) ← pool.retain "authorized-project" source path metadata (now+1000) (now+1100)
    let entered ← IO.Promise.new
    let finish ← IO.Promise.new
    let reading ← IO.asTask (pool.withHeld expiring "authorized-project" source.head metadata (now+4000) fun _ _ => do
      entered.resolve true
      waitFlag finish (now+4000)) .dedicated
    try
      waitFlag entered (now+1000)
      IO.sleep 1150
      pool.reap
      let active ← checkedAccounting pool
      check (active.getObjValD "active" == toJson (1 : Nat)) "expiry retired a still-running reader"
      check (← refused (pool.withHeld expiring "authorized-project" source.head metadata (now+4000) (fun _ _ => pure ())))
        "expired token admitted a new read"
      pool.close
      check (← refused (pool.retain "authorized-project" source path metadata (now+3000) (now+3500)))
        "closed shared source service admitted a new descriptor"
      let active ← checkedAccounting pool
      check (active.getObjValD "active" == toJson (1 : Nat)) "close retired an active reader before its finalizer"
    finally finish.resolve true
    IO.ofExcept (← IO.wait reading)
    let final ← checkedAccounting pool
    check (final.getObjValD "chargedBytes" == toJson (0 : Nat) &&
      final.getObjValD "sharedDescriptors" == toJson (0 : Nat)) "last expired reader leaked shared descriptors"
    let borrowers ← originals.state.atomically do
      return (← get).entries.fold (fun total _ entry => total+entry.borrowers) 0
    check (borrowers == 0) "retired shared descriptors leaked original cache pins"
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("concurrentCuts",toJson (80 : Nat)),
      ("sourcesPerCut",toJson sources.size),("retainedTokens",toJson (1280 : Nat)),
      ("acquisitionElapsedMs",toJson elapsed),("full",full),("drained",drained),("final",final),
      ("oneCachePinPerDescriptor",toJson true),("foreignScopeRootManifestRejected",toJson true),
      ("activeReleaseExpiryCloseAccounted",toJson true),("actualHookCapacityTested",toJson false),
      ("adopted",toJson false)]).pretty
  finally
    pool.close
    originals.close
end Eggshell.Research.SharedLeaseChecks
