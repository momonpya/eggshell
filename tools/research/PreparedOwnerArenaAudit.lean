import Eggshell.PublicationService
import tools.research.PreparedOwnerArena
import tools.research.FrozenCanonicalBasis
open Lean Eggshell Eggshell.Synapses
open Eggshell.Synapses.CanonicalSource
open Eggshell.Synapses.PreparedOwnerArena

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def fails (action : IO Unit) : IO Bool := do
  try action; return false
  catch _ => return true
private def number (value : Json) (name : String) : IO Nat := IO.ofExcept (value.getObjValAs? Nat name)
private def empty (database owner : String) : IO Ready := IO.ofExcept (PreparedOwnerArena.prepare database owner ⟨#[],[]⟩)
private def deadline : IO Nat := return (← IO.monoMsNow)+60000

private def lifecycle : IO Json := do
  let cache ← PreparedOwnerArena.Cache.new
  let loads ← IO.mkRef 0
  let load := do loads.modify (·+1); empty "project" "owner"
  let use := fun (_ : Ready) => pure ()
  let finish ← deadline
  cache.withReady "root" "project" "owner" 1 finish load use
  cache.withReady "root" "project" "owner" 1 finish load use
  check ((← loads.get) == 1) "repeat request decoded its owner again"
  check (← fails (cache.withReady "root" "project" "owner" 2 finish load use)) "changed descriptor was reused"
  check (← fails (cache.withReady "root" "other" "owner" 1 finish load use)) "foreign database entered cache"
  cache.withReady "root" "other" "owner" 1 finish (empty "other" "owner") use
  cache.withReady "new-root" "project" "owner" 1 finish load use
  check ((← loads.get) == 3) "publication or database isolation failed"
  check (← fails (cache.withReady "root" "project" "owner" 1 finish load (fun _ => throw (IO.userError "callback"))))
    "callback failure disappeared"
  check ((← number (← cache.stats) "borrowers") == 0) "callback leaked a loan"
  let before ← cache.stats
  cache.close
  check (← fails (cache.withReady "root" "project" "owner" 1 finish load use)) "closed cache accepted request"
  let closed ← cache.stats
  check ((← number closed "chargedBytes") == 0 && closed.getObjValD "closed" == toJson true) "close retained reservations"
  let failed ← PreparedOwnerArena.Cache.new
  let tryLoad : IO Ready := throw (IO.userError "injected failure")
  check (← fails (failed.withReady "root" "project" "owner" 1 finish tryLoad use)) "load error disappeared"
  check ((← number (← failed.stats) "chargedBytes") == 0) "failed load retained charge"
  failed.withReady "root" "project" "owner" 1 finish load use
  check ((← number (← failed.stats) "borrowers") == 0) "retry retained loan"
  failed.close
  let delayed ← PreparedOwnerArena.Cache.new
  let attempts ← IO.mkRef 0
  let slow := do attempts.modify (·+1); IO.sleep 80; empty "project" "owner"
  check (← fails (delayed.withReady "root" "project" "owner" 1 ((← IO.monoMsNow)+20) slow use))
    "wait expiry did not fire"
  delayed.withReady "root" "project" "owner" 1 finish slow use
  check ((← attempts.get) == 1) "expired observer restarted live preparation"
  check ((← number (← delayed.stats) "borrowers") == 0) "expired observer retained a loan"
  delayed.close
  let closing ← PreparedOwnerArena.Cache.new
  let started ← IO.mkRef false
  let waiting := do
    started.set true
    repeat
      IO.sleep 5
      if ← IO.checkCanceled then throw (IO.userError "fixture load cancelled")
    empty "project" "owner"
  let pending ← IO.asTask (closing.withReady "root" "project" "owner" 1 finish waiting use) .dedicated
  repeat
    if ← started.get then break
    check ((← IO.monoMsNow) < finish) "closing fixture did not start"
    IO.sleep 1
  closing.close
  check pending.get.toOption.isNone "closing service did not fail its waiting borrower"
  check ((← number (← closing.stats) "chargedBytes") == 0) "in-flight close retained reservation"
  let evicting ← PreparedOwnerArena.Cache.new
  for key in ["a","b","c"] do
    evicting.withReady key "project" "owner" (8*1024*1024) finish load use
  let eviction ← evicting.stats
  check ((← number eviction "evictions") == 1 && (← number eviction "entries") == 2 &&
    eviction.getObjValD "accountedExact" == toJson true) "shared-budget eviction failed"
  evicting.close
  let held ← PreparedOwnerArena.Cache.new
  held.withReady "a" "project" "owner" (8*1024*1024) finish load fun _ =>
    held.withReady "b" "project" "owner" (8*1024*1024) finish load fun _ => do
      check (← fails (held.withReady "c" "project" "owner" (8*1024*1024)
        ((← IO.monoMsNow)+20) load use)) "borrowed values were evicted"
  check ((← number (← held.stats) "borrowers") == 0) "budget timeout retained loan"
  held.close
  return Json.mkObj [("shared",before),("closed",closed),("eviction",eviction),
    ("failureExpiryRetryScopeAndPinnedLoans",toJson true)]

private def percentile (values : Array Nat) (percent : Nat) : Nat :=
  let ordered := values.qsort (· < ·)
  ordered[min (ordered.size-1) ((ordered.size*percent+99)/100-1)]?.getD 0

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "fresh arena output directory required")
  let output : System.FilePath := .mk output
  check (!(← output.pathExists)) "preserve prior arena audit"
  IO.FS.createDirAll output
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let (source,rows) ← Eggshell.Research.FrozenCanonicalBasis.load study root
  let initialHead := source.head
  let lifecycleResult ← lifecycle
  let ids := hashDistinct (rows.toList.flatMap fun row => row.origins.toList.map (·.binding.owner)) |>.toArray
  let owners ← ids.mapM fun owner => do
    let selected := rows.filterMap fun row =>
      let origins := row.origins.filter (·.binding.owner == owner)
      if origins.isEmpty then none else some {row with origins}
    let stored ← IO.ofExcept (Recipe.compile selected)
    let _ ← IO.ofExcept (PreparedOwnerArena.prepare source.head.identity owner stored)
    return (owner,stored)
  let some (firstOwner,firstStored) := owners[0]? | throw (IO.userError "empty original owner domain")
  let some firstRow := firstStored.rows[0]? | throw (IO.userError "empty original owner")
  let badOrigins := firstRow.origins.map fun origin => {origin with binding := {origin.binding with database := "foreign"}}
  check ((PreparedOwnerArena.prepare source.head.identity firstOwner ⟨#[{firstRow with origins := badOrigins}],[]⟩).toOption.isNone)
    "foreign original entered checked owner"
  check ((PreparedOwnerArena.prepare source.head.identity firstOwner
    ⟨#[firstRow,{firstRow with code := firstRow.code ++ "different"}],[]⟩).toOption.isNone)
    "conflicting original bytes entered checked owner"
  let directory := output / "canonical"
  IO.FS.createDirAll directory
  let recipes ← DB.PageMap.create (directory / "recipes") "prepared owner arena audit"
  let payloadBytes := (toJson rows).compress.toUTF8
  let payload := Sha256.hex payloadBytes
  IO.FS.writeBinFile (directory / (payload ++ ".json")) payloadBytes
  let initial : CanonicalSource.Cache.Manifest := {
    source := source.head,implementation := CanonicalSource.Cache.implementation,payload,rows := rows.size,
    statistics := {nativeOwners := owners.size,originalRows := rows.size},
    recipes := none,bindings := none,supplements := none}
  let _ ← DB.PageMap.withWriter recipes fun writer => do
    for (owner,stored) in owners do Recipe.write writer owner stored
    writer.put "manifest" (some
      (toJson (initial.source,initial.implementation,initial.payload,initial.bindings,initial.supplements)).compress.toUTF8)
  let recipes ← DB.PageMap.pin recipes.directory
  let metadata := {initial with recipes := some recipes.head}
  IO.FS.writeFile (directory / "manifest.json") (toJson metadata).compress
  check (← (CanonicalSource.Cache.atSource? source directory metadata).map Option.isSome)
    "fixture is not an authentic prepared source sidecar"
  let referenceLayouts ← owners.mapM fun (owner,stored) => do
    let checked ← IO.ofExcept (Recipe.check stored.rows stored.records)
    return (owner,checked.catalogue.map (List.map Fin.val))
  let pool ← CanonicalSource.Shared.Pool.new
  let request := fun order => do
    let started ← IO.monoMsNow
    pool.withReady source directory metadata (started+60000) fun loaded _ => do
      let found ← loaded.rows order (started+60000)
      check (found.map Prod.fst == order) "projection changed requested owner order"
      for (owner,stored) in found do
        let expected := owners.find? (·.1 == owner) |>.map Prod.snd
        check (some stored == expected) "resident projection differs from complete original recipe"
      for owner in order do
        loaded.withOwner owner (started+60000) fun ready => do
          check (some (ready.layout.catalogue.map (List.map Fin.val)) ==
            (referenceLayouts.find? (·.1 == owner) |>.map Prod.snd))
            "resident checked catalogue differs from reference"
    return (← IO.monoMsNow)-started
  try
    let before ← pool.stats
    let coldJobs ← (List.range 80).mapM fun _ => IO.asTask (request ids) .dedicated
    let coldTimes ← coldJobs.mapM fun job => IO.ofExcept job.get
    let afterCold ← pool.stats
    let jobs ← (List.range 80).mapM fun index => IO.asTask (request (if index%2 == 0 then ids else ids.reverse)) .dedicated
    let times ← jobs.mapM fun job => IO.ofExcept job.get
    let after ← pool.stats
    let arena := after.getObjValD "owners"
    check ((← number arena "loads") == ids.size && (← number arena "borrowers") == 0 &&
      arena.getObjValD "accountedExact" == toJson true) "clients repeated preparation or retained loans"
    check ((← DB.PageMap.pin source.directory).head == initialHead) "audit changed original snapshot"
    pool.close
    let stopped ← pool.stats
    check ((← number (stopped.getObjValD "owners") "chargedBytes") == 0) "service close retained arena"
    IO.FS.writeFile (output / "result.json") (Json.mkObj [
      ("source",toJson initialHead),("rows",toJson rows.size),("owners",toJson ids.size),
      ("coldP95Ms",toJson (percentile coldTimes.toArray 95)),
      ("coldMaxMs",toJson (coldTimes.foldl max 0)),("afterCold",afterCold),
      ("concurrentNativeClientsPerPhase",toJson (80 : Nat)),
      ("p50Ms",toJson (percentile times.toArray 50)),("p95Ms",toJson (percentile times.toArray 95)),
      ("maxMs",toJson (times.foldl max 0)),("before",before),("after",after),("stopped",stopped),
      ("lifecycle",lifecycleResult),("sourceUnchanged",toJson true),("fullRecipeAndCatalogueEquality",toJson true),
      ("actualHooks",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
      ("adopted",toJson false),("wholeQueryPlannerMoved",toJson false)]).pretty
    IO.println s!"Shared {ids.size} checked owners across 80 native clients; p95 {percentile times.toArray 95} ms"
  finally pool.close
