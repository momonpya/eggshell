import Eggshell.PublicationService
import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.DB Eggshell.Synapses
open Eggshell.Synapses.ObservedRecordView
open Eggshell.Synapses.Extraction
#print axioms Image.foreign_source
#print axioms Image.foreign_database
#print axioms Image.lookup_is_immutable
#print axioms CachedGeometry.encoded_size_exact
#print axioms Cache.project_snapshot_boundary
#print axioms Cache.publish_empty

run_cmd do
  let environment ← getEnv
  let value (name : Name) := do
    let some declaration := environment.find? name | throwError "missing record read declaration {name}"
    let some body := declaration.value? | throwError "opaque record read declaration {name}"
    pure body
  let service ← value ``Plugin.Publication.Service.sourceRecords
  unless service.getUsedConstants.contains ``Cache.project do throwError "service bypasses immutable record batch"
  if service.getUsedConstants.contains ``geometry? then throwError "service independently reloads original geometry"
  if service.getUsedConstants.contains ``Cache.stats then throwError "record service reenters cache for hit statistics"
  let project ← value ``Cache.project
  for required in #[``Cache.capture,``Image.collect,``Cache.publish] do
    unless project.getUsedConstants.contains required do throwError "record projection lost its ownership boundary {required}"
  for root in #[``Cache.capture,``Cache.publish] do
    let body ← value root
    if body.getUsedConstants.contains ``geometry? then throwError "cache owner performs DB IO"
  let mut pending := [``Image.lookup?,``geometryIdentity,``CachedGeometry.charge,``Image.collect]
  let mut seen : Std.HashSet Name := {}
  while let some name := pending.head? do
    pending := pending.tail!
    if seen.contains name then continue
    seen := seen.insert name
    let text := name.toString
    if ["Std.Mutex.","IO.Ref.","IO.Promise.","IO.asTask","IO.wait","ST.Ref.","Atomic","CompareAndSwap"].any
        (fun stem => text.startsWith stem) then
      throwError "immutable record read reaches synchronization {name}"
    if let some declaration := environment.find? name then
      if let some body := declaration.value? then pending := body.getUsedConstants.toList++pending
  logInfo m!"Actual record service/batch connected; {seen.size} lookup and collection dependencies contain no shared synchronization"

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def rejects (work : IO α) : IO Bool := try discard work; pure false catch _ => pure true
def checks (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh record image checks required"
  IO.FS.createDirAll root
  let first ← PageMap.create (root/"original.egg") "immutable-record-read"
  let database := first.head.identity
  let makeDocument (owner raw : String) : Document := ⟨owner,"work-"++owner,none,some raw,false,#[],#[]⟩
  let json := (Json.mkObj [("uri",toJson "mcp://tickets/42"),
    ("body",toJson (String.ofList (List.replicate 6000 '語'))),("tail",toJson "retained-tail")]).compress
  let (_,_,_) ← PageMap.withWriter first fun writer => do
    stage writer database (makeDocument "file-output" "plain source\n  no required command syntax\n")
    stage writer database (makeDocument "mcp-json" json)
  let index ← PageMap.pin first.directory
  let owners := #["file-output","mcp-json","missing","mcp-json"]
  let cache ← Cache.new
  let budget := Plugin.Publication.Stream.maxBytes-4096
  let initial ← cache.project index database owners ((← IO.monoMsNow)+2000) budget
  let reference ← owners.mapM fun owner => do return (owner,← geometry? index database owner ((← IO.monoMsNow)+2000))
  check (toJson initial.rows == toJson reference && initial.rows.map Prod.fst == owners) "original batch differs from DB or owner order"
  let image ← cache.capture index.head database owners
  check ((image.lookup? {index.head with revision := index.head.revision+1} database "file-output").isNone) "foreign head accepted"
  check ((image.lookup? index.head "foreign" "file-output").isNone) "foreign database accepted"
  let before ← cache.stats
  let entered : IO.Promise Unit ← IO.Promise.new
  let release : IO.Promise Unit ← IO.Promise.new
  let holder ← IO.asTask (cache.atomically do
    entered.resolve ()
    discard <| IO.wait release.result!
    set ({} : CacheState)) .dedicated
  let tasks ← IO.mkRef (#[] : Array (Task (Except IO.Error Unit)))
  try
    TaskDeadline.wait (Std.Async.AsyncTask.ofPurePromise entered) ((← IO.monoMsNow)+2000)
    for _ in [:80] do
      let task ← IO.asTask (do
        for _ in [:16] do
          let result ← image.collect owners ((← IO.monoMsNow)+2000) budget
            (fun _ => throw (IO.userError "warm immutable hit invoked a loader"))
          check (toJson result.rows == toJson reference && result.additions.isEmpty) "immutable parallel read changed data"
          check (result.bytes == initial.bytes) "cached encoded size changed") .dedicated
      tasks.modify (·.push task)
    for task in ← tasks.get do TaskDeadline.wait task ((← IO.monoMsNow)+3000)
    let emptyImage : Image := ⟨index.head,database,{}⟩
    let miss ← emptyImage.collect owners ((← IO.monoMsNow)+2000) budget
      (fun owner => do geometry? index database owner ((← IO.monoMsNow)+2000))
    check (toJson miss.rows == toJson reference) "miss DB IO waited on cache owner"
  finally
    release.resolve ()
    discard <| IO.wait holder
    for task in ← tasks.get do discard <| IO.wait task
  check ((← cache.stats).getObjValD "entries" == toJson (0 : Nat)) "test eviction not committed"
  let old ← image.collect owners ((← IO.monoMsNow)+2000) budget (fun _ => throw (IO.userError "old snapshot lost value"))
  check (toJson old.rows == toJson reference) "old snapshot did not survive cache eviction"
  let empty ← cache.capture index.head database owners
  let cold ← empty.collect owners ((← IO.monoMsNow)+2000) budget
    (fun owner => do geometry? index database owner ((← IO.monoMsNow)+2000))
  cache.publish empty cold.additions
  let published ← cache.stats
  cache.publish empty cold.additions
  check ((← cache.stats) == published) "concurrent duplicate fills changed cache accounting"
  check (← rejects (image.collect owners (← IO.monoMsNow) budget (fun _ => pure none))) "expired image read accepted"
  check (← rejects (image.collect owners ((← IO.monoMsNow)+2000) 0 (fun _ => pure none))) "reply budget bypassed"
  let finalImage ← cache.capture index.head database owners
  for _ in [:128] do
    discard <| finalImage.collect owners ((← IO.monoMsNow)+2000) budget (fun _ => throw (IO.userError "cache miss"))
  check ((← cache.stats) == published) "read hit mutated cache LRU or counters"
  cache.atomically do
    modify fun state => (Array.range 1024).foldl (fun state n =>
      state.publish index.head database (CachedGeometry.make ("eviction-"++toString n) none)) state
  let bounded ← cache.stats
  check ((bounded.getObjValAs? Nat "entries").toOption.getD 1000 ≤ 512 &&
    (bounded.getObjValAs? Nat "chargedBytes").toOption.getD (geometryCapacity+1) ≤ geometryCapacity) "cache exceeded existing limits"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("actualProjectionEqualsIndependentDbRead",toJson true),
    ("ownerOrderAndDuplicatesPreserved",toJson true),("sourceAndDatabaseRejected",toJson true),
    ("originalCacheMutexHeldDuring80ParallelReaders",toJson true),("readsPerActor",toJson (16 : Nat)),
    ("hitInvokedNoLoaderAndNoSharedUpdate",toJson true),("oldSnapshotSurvivedEviction",toJson true),
    ("missDatabaseReadsCompletedWithCacheMutexHeld",toJson true),
    ("duplicateFillIdempotent",toJson true),("expiredAndOversizedReplyRejected",toJson true),
    ("fileAndNonFileJsonGeometryEqual",toJson true),("before",before),("published",published),("bounded",bounded),
    ("notWholeRetrievalLockFreedom",toJson true),("adopted",toJson false)]).compress
def main (args : List String) : IO UInt32 := do
  match args with
  | ["record-image-check",root] => checks (.mk root); return 0
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain",
      args := #["front-traffic-audit",source]}
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | other => sourceRouteEngine other
