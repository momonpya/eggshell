module
public import Main
import all Eggshell.PreparedReaders
import all Eggshell.DB.PageMap
@[expose] public section
namespace Eggshell.Research.ActorReadsChecks
open Lean DB PreparedReaders

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

#print axioms CheckedFrame.original_boundary
#print axioms CheckedFrame.original_key
#print axioms CheckedFrame.public_image
#print axioms CheckedFrame.local_fork

private def occurrences (target : Name) : Expr → Nat
  | .const name _ => if name == target then 1 else 0
  | .app f x => occurrences target f+occurrences target x
  | .lam _ ty body _ | .forallE _ ty body _ => occurrences target ty+occurrences target body
  | .letE _ ty value body _ => occurrences target ty+occurrences target value+occurrences target body
  | .mdata _ value | .proj _ _ value => occurrences target value
  | _ => 0

run_cmd do
  let env ← getEnv
  let body (name : Name) : Elab.Command.CommandElabM Expr := do
    let some value := (env.find? name).bind (·.value?) | throwError "missing independent read implementation {name}"
    pure value
  -- Fail closed if the imported module hides the implementation of the root
  -- being audited. An opaque wrapper alone is not evidence about its body.
  discard <| body ``localSession
  discard <| body ``SnapshotImage.borrow
  discard <| body ``PageMap.LocalPages.Front.new
  discard <| body ``Pool.stats
  discard <| body ``Pool.find
  let mut pending := [``CheckedFrame.fork,``localSession,``Pool.stats,``Pool.find]
  let mut seen : Std.HashSet Name := {}
  while let some name := pending.head? do
    pending := pending.tail!
    if seen.contains name then continue
    seen := seen.insert name
    if ["Std.Mutex.","IO.Promise.","IO.asTask","IO.wait","IO.sleep","Std.CloseableChannel.",
        "IO.Ref.modifyGet","IO.Ref.compareAndSwap"].any (fun stem => name.toString.startsWith stem) then
      throwError "request-local reader assembly reaches shared synchronization {name}"
    if let some value := (env.find? name).bind (·.value?) then pending := value.getUsedConstants.toList++pending
  -- Audit the capability's field types as well as the executable call graph.
  let mut fields := [``CheckedFrame,``Frozen,``Image,``SnapshotImage,``PageMap.LocalPages.State,``Shared,``Owners,``OwnerInput,``BitmapImage]
  let mut types : Std.HashSet Name := {}
  while let some name := fields.head? do
    fields := fields.tail!
    if types.contains name then continue
    types := types.insert name
    if ["Std.Mutex","IO.Ref","IO.Promise","Eggshell.PreparedReaders.Pool","Eggshell.SearchReaders.Coordinator"].contains name.toString then
      throwError "checked public image retains mutable/shared ownership {name}"
    if let some info := getStructureInfo? env name then
      for field in info.fieldNames do
        let projection := name ++ field
        let some decl := env.find? projection | throwError "missing checked image field {projection}"
        fields := decl.type.getUsedConstants.toList++fields
  unless occurrences ``CheckedFrame.fork (← body ``SearchReaders.Coordinator.borrow) == 1 do
    throwError "ordinary search actor does not instantiate its own readers"
  unless occurrences ``Pool.prepareFrame (← body ``SearchReaders.serve) == 1 &&
      occurrences ``localSession (← body ``SearchReaders.serve) == 0 &&
      occurrences ``CheckedFrame.fork (← body ``SearchReaders.serve) == 0 do
    throwError "reader assembly still runs in the shared catalogue loop"
  logInfo m!"{seen.size} reader-assembly dependencies without shared synchronization; {types.size} checked capability field types audited"

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh independent reader controls required"
  IO.FS.createDirAll root
  let sources ← (Array.range 3).mapM fun i => do
    let source ← PageMap.create (root/s!"source-{i}.egg") s!"actor-read-{i}"
    discard <| PageMap.withWriter source fun writer => writer.put "original-value" (some s!"original-{i}".toUTF8)
    PageMap.pin source.directory
  let inputs := sources.map fun source => PreparedInputs.empty source "unchanged-model" "unchanged-encoder"
  let frame ← Frame.capture sources inputs none
  let pool ← Pool.new
  let checked ← pool.prepareFrame frame
  check (checked.image.key == frame.key) "checked image changed its complete read cut"
  let reversed ← Frame.capture sources.reverse inputs.reverse none
  check (!(CheckedFrame.bind checked.image reversed).isOk) "reordered original inventory accepted"
  let changed ← Frame.capture sources (inputs.modify 0 fun input => {input with encoder := "changed"}) none
  check (!(CheckedFrame.bind checked.image changed).isOk) "different prepared producer accepted"
  let some original := sources[0]? | throw (IO.userError "original fixture missing")
  let usage ← Frame.capture sources (inputs.map fun input => {input with usage := some original.head}) none
  check ((CheckedFrame.bind checked.image usage).isOk) "private usage root leaked into shared image identity"
  let before ← pool.pages.stats
  let began ← IO.monoMsNow
  let deadline := began+28000
  let .owner owner := pool.pages | throw (IO.userError "control needs the catalogue page owner")
  -- The owner is deliberately unavailable for the whole 80-reader test.
  -- A hidden lock in session assembly or page reads cannot finish this test.
  owner.atomically do
    -- The warm catalogue hit and its diagnostic snapshot must also avoid
    -- the page owner: these run on every ordinary coordinator admission.
    let some found ← pool.find frame.key | throw (IO.userError "prepared catalogue hit disappeared")
    check (found.key == checked.image.key) "catalogue hit changed the checked image"
    let stats ← pool.stats
    check (stats.getObjValD "images" == toJson (1 : Nat)) "catalogue statistics changed its image inventory"
    let actors ← (Array.range 80).mapM fun _ => IO.asTask (do
      let session ← checked.fork
      check session.pool.pages.readOnly "actor received the page-cache owner"
      for i in [:session.sources.size] do
        let some source := session.sources[i]? | throw (IO.userError "actor omitted an original source")
        check ((← source.get "original-value") == some s!"original-{i}".toUTF8)
          "independent source read changed original bytes"
        check ((← source.reads.get) > 0) "actor did not record its own reads") .dedicated
    try
      for actor in actors do TaskDeadline.wait actor deadline
    finally
      for actor in actors do IO.cancel actor
      for actor in actors do discard <| IO.wait actor
  let elapsed := (← IO.monoMsNow)-began
  check ((← pool.pages.stats) == before) "independent readers mutated shared cache bookkeeping"
  -- A finished request cannot leak its local trace into a later reader.
  let left ← checked.fork
  let right ← checked.fork
  let some l := left.sources[0]? | throw (IO.userError "left reader missing")
  let some r := right.sources[0]? | throw (IO.userError "right reader missing")
  discard <| l.get "original-value"
  check ((← l.reads.get) > 0 && (← r.reads.get) == 0) "actors shared mutable read counters"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [
    ("parallelReaders",toJson (80 : Nat)),("originalSources",toJson sources.size),
    ("cataloguePageMutexHeldThroughout",toJson true),("componentElapsedMs",toJson elapsed),
    ("warmCatalogueHitAndStatsAvoidPageOwner",toJson true),
    ("originalBytesExact",toJson true),("foreignPreparedInputAndReorderingRejected",toJson true),
    ("privateUsageExcluded",toJson true),("sharedCacheUnchanged",toJson true),("localCountersIndependent",toJson true),
    ("wholeSearchLockFree",toJson false),("fullHooksOrGrowingProjectLoad",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress

end Eggshell.Research.ActorReadsChecks
