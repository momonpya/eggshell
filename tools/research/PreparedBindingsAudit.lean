import tools.PreparedBindingCache
import tools.research.PreparedBindingsContract
open Lean Eggshell Eggshell.Synapses
open IndexedBindings

#print axioms Prepared.ready_complete
#print axioms Prepared.namespace_isolated
#print axioms Prepared.retained_budget
#print axioms Origin.only_admitted_owner
#print axioms Origin.same_source
#print axioms Origin.same_database

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def same (a b : Resolved) : Bool :=
  a.complete == b.complete && a.requests == b.requests && a.bytes == b.bytes && a.inspected == b.inspected &&
    a.unresolved == b.unresolved && a.unusable == b.unusable && a.rows.size == b.rows.size &&
    a.rows.toArray.all (fun (range,rows) => b.rows[range]? == some rows)

private def start (pool : Prepared.Pool) (key : Prepared.Key) : IO Prepared.Flight := do
  let .start flight ← pool.admit key | throw (IO.userError "expected one new shared load")
  return flight

private def rejected (action : IO α) : IO Bool :=
  try let _ ← action; pure false catch _ => pure true

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "fresh audit directory required")
  let root := System.FilePath.mk output
  check (root.isAbsolute && !(← root.pathExists)) "preserve previous prepared binding audit"
  IO.FS.createDir root
  let source ← DB.PageMap.create (root / "source.egg") "typed-original-bindings"
  let file : Synapses.File := ⟨"source/file.cc",String.ofList (List.replicate 64 'a'),200⟩
  let range : Range := ⟨.file file,4,5⟩
  let absent : Range := ⟨.file file,19,20⟩
  let a : Read := ⟨⟨"session-a","turn","call-a"⟩,range,
    ⟨source.head.identity,"owner-a","work",30,45⟩,#[]⟩
  let b := {a with
    occurrence := ⟨"session-b","turn","call-b"⟩
    binding := {a.binding with owner := "owner-b"}}
  let facts := #[Fact.read a,.read b]
  let _ ← Index.replace source .database .shared facts
  let some reader ← Index.open? source .database .shared | throw (IO.userError "fixture index missing")
  let namespaceKey := "scope-a"
  let pool ← Prepared.Pool.new
  let deadline ← pure ((← IO.monoMsNow)+15000)
  for owners in [#["owner-a","owner-b"],#[],#["owner-a"],#["owner-b"],#["not-an-owner"]] do
    let allowed := Std.HashSet.ofArray owners
    let wanted := #[range,absent,range]
    let expected ← resolve reader wanted allowed deadline
    let actual ← pool.resolve namespaceKey reader wanted allowed deadline
    check (same expected actual) "decoded retention changed exact bindings, order, empties or logical counters"
  let first ← pool.stats
  check (first.getObjValD "loads" == toJson (2 : Nat) && first.getObjValD "active" == toJson (0 : Nat))
    "allowed-owner changes recompiled immutable bindings"
  let narrow ← pool.raw namespaceKey reader range deadline 0
  let original ← rawLookup reader range deadline 0
  check (narrow.complete == original.complete && narrow.bytes == original.bytes && narrow.rows.size == original.rows.size)
    "a smaller byte budget changed partial-prefix semantics"
  let cold ← pool.resolve "other-scope" reader #[range] (Std.HashSet.ofArray #["owner-a"]) deadline
  check (cold.complete && (← pool.stats).getObjValD "loads" == toJson (3 : Nat))
    "a different read scope reused the compiled entry"
  let next := {a with source := absent}
  let _ ← Index.replace source .database .shared (facts.push (.read next))
  let some changed ← Index.open? source .database .shared | throw (IO.userError "updated fixture index missing")
  let beforeUnrelated ← pool.stats
  let sameRange ← pool.resolve namespaceKey changed #[range] (Std.HashSet.ofArray #["owner-a"]) deadline
  let unchanged ← resolve changed #[range] (Std.HashSet.ofArray #["owner-a"]) deadline
  check (same sameRange unchanged && (← pool.stats).getObjValD "loads" == beforeUnrelated.getObjValD "loads")
    "an unrelated publication recompiled unchanged bindings"
  let now ← pool.resolve namespaceKey changed #[absent] (Std.HashSet.ofArray #["owner-a"]) deadline
  let old ← pool.resolve namespaceKey reader #[absent] (Std.HashSet.ofArray #["owner-a"]) deadline
  check (now.complete && (now.rows[absent]?.getD #[]).size == 1 && old.complete &&
    (old.rows[absent]?.getD #[]).isEmpty) "negative retention hid a new publication or changed an old pin"
  let _ ← Index.replace source .database .shared #[.read b,.read next]
  let some removed ← Index.open? source .database .shared | throw (IO.userError "removed fixture index missing")
  let surviving := Std.HashSet.ofArray #["owner-a","owner-b"]
  let afterRemoval ← pool.resolve namespaceKey removed #[range] surviving deadline
  check (same afterRemoval (← resolve removed #[range] surviving deadline) &&
    (afterRemoval.rows[range]?.getD #[]).map (·.binding.owner) == #["owner-b"])
    "a deletion retained an obsolete original binding"
  let beforeUnchanged ← pool.stats
  let stable ← pool.resolve namespaceKey removed #[absent] surviving deadline
  check (stable.complete && (← pool.stats).getObjValD "loads" == beforeUnchanged.getObjValD "loads")
    "deletion recompiled a different range"
  let stillOld ← pool.resolve namespaceKey reader #[range] surviving deadline
  check ((stillOld.rows[range]?.getD #[]).size == 2) "deletion changed a previously pinned reader"
  let shared ← Prepared.Pool.new
  let key ← Prepared.keyFor "single-flight" reader range
  let flight ← start shared key
  let arrived ← Std.Mutex.new (0 : Nat)
  let jobs ← (Array.range 80).mapM fun _ => IO.asTask (do
    arrived.atomically (modify (·+1))
    shared.raw "single-flight" reader range deadline Prepared.readLimit) .dedicated
  let arrivedBy := (← IO.monoMsNow)+3000
  while (← arrived.atomically get) < 80 do
    check ((← IO.monoMsNow) < arrivedBy) "concurrent readers did not reach their shared preparation"
    IO.sleep 1
  let joinedBy ← pure ((← IO.monoMsNow)+3000)
  while ((← shared.stats).getObjValAs? Nat "joins").toOption.getD 0 < 80 do
    check ((← IO.monoMsNow) < joinedBy) "concurrent readers did not join their common preparation"
    IO.sleep 1
  shared.launch key flight (rawLookup reader range deadline Prepared.readLimit)
  let expected ← rawLookup reader range deadline Prepared.readLimit
  for job in jobs do
    let actual ← IO.ofExcept (job.get.mapError IO.Error.toString)
    check (actual.complete && actual.rows.map (·.read) == expected.rows.map (·.read))
      "a concurrent reader lost or changed original bindings"
  let sharedStats ← shared.stats
  check (sharedStats.getObjValD "loads" == toJson (1 : Nat) &&
    sharedStats.getObjValD "active" == toJson (0 : Nat)) "concurrent readers duplicated preparation"
  let partialKey := ("incomplete",range)
  let previous ← start shared partialKey
  shared.finish partialKey previous (.ok {complete := false})
  let retry ← start shared partialKey
  shared.finish partialKey previous (.error "late old failure")
  check (((← shared.state.atomically get).flights[partialKey]?).any (·.serial == retry.serial))
    "a prior load completed over its replacement"
  shared.finish partialKey retry (.error "expected retryable failure")
  let afterFailure ← start shared partialKey
  shared.finish partialKey afterFailure (.ok expected)
  let timed ← Prepared.keyFor "caller-deadline" reader range
  let flight ← start shared timed
  let expired ← shared.raw "caller-deadline" reader range ((← IO.monoMsNow)+10) Prepared.readLimit
  check (!expired.complete && !(← flight.promise.isResolved)) "one caller cancelled another reader's shared load"
  shared.launch timed flight (pure expected)
  let late ← shared.raw "caller-deadline" reader range deadline Prepared.readLimit
  check late.complete "a later reader lost the same immutable preparation"
  let beforeClose ← shared.stats
  shared.close
  check (← rejected (shared.admit ("closed",range))) "closed preparation admitted another reader"
  let ran ← IO.mkRef false
  shared.launch ("closed",range) flight do ran.set true; return expected
  check (!(← ran.get)) "shutdown restarted a preparation"
  pool.close
  IO.FS.writeFile (root / "result.json") (Json.mkObj [
    ("exactOrderedBindingsAndCounters",toJson true),("allowedOwnersCheckedPerRequest",toJson true),
    ("emptyAndDuplicateRangesExact",toJson true),("smallerByteBudgetExact",toJson true),
    ("scopeIsolated",toJson true),("oldNegativeAndNewPublicationExact",toJson true),
    ("unrelatedPublicationKeepsDecodedBindings",toJson true),
    ("removalInvalidatesAffectedBindingsOnly",toJson true),
    ("clients",toJson (80 : Nat)),("singleFlight",sharedStats),
    ("incompleteAndFailureNotRetained",toJson true),("lateFinishCannotEraseReplacement",toJson true),
    ("callerDeadlineKeepsSharedLoad",toJson true),("closeCannotSpawn",toJson true),
    ("finalStats",beforeClose),("answeringModelCalls",toJson (0 : Nat)),
    ("actualHook",toJson false),("adopted",toJson false)]).pretty
