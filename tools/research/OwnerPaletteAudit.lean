import Eggshell.PublicationService
import tools.research.FrozenCanonicalBasis
import tools.research.StudyRuntime
import tools.research.SourceProjectionWire
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses
open Eggshell.Synapses.CanonicalSource
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false
  catch _ => return true
private def percentile (values : Array Nat) (percent : Nat) : Nat :=
  let sorted := values.qsort (· < ·)
  sorted[min (sorted.size-1) ((sorted.size*percent+99)/100-1)]?.getD 0

private def leaseLifecycle (source : DB.PageMap.Snapshot) (path : System.FilePath) : IO Json := do
  let some metadata ← Cache.manifestAt? source path | throw (IO.userError "missing lease fixture manifest")
  let recipes ← DB.PageMap.pin (path / "recipes")
  let owners ← PreparedOwnerArena.Cache.new
  let loaded : Shared.Loaded := ⟨metadata,recipes,none,owners,"palette-lease-fixture"⟩
  let pool ← OwnerPaletteLease.Pool.new
  let finish := (← IO.monoMsNow)+5000
  try
    let tokens ← (Array.range OwnerPaletteLease.maxActive).mapM fun _ =>
      pool.acquire "scope" source.head loaded #["owner"] 0 finish
    ensure (← rejected (pool.acquire "scope" source.head loaded #["owner"] 0 ((← IO.monoMsNow)+15)))
      "full query metadata budget admitted another large view"
    ensure (← rejected (pool.validate tokens[0]! "foreign" source.head #["owner"])) "lease crossed read scope"
    ensure (← rejected (pool.validate tokens[0]! "scope" {source.head with revision := source.head.revision+1} #["owner"]))
      "lease crossed publication"
    ensure (← rejected (pool.validate tokens[0]! "scope" source.head #["foreign-owner"])) "lease expanded its owner domain"
    for token in tokens do pool.release token "scope"
    ensure (← rejected (pool.validate tokens[0]! "scope" source.head #["owner"])) "released lease remained usable"
    ensure (← rejected (pool.acquire "scope" source.head loaded #["owner"] OwnerPaletteLease.capacity finish))
      "oversized metadata reservation entered the queue"
    let expired ← pool.acquire "scope" source.head loaded #["owner"] 0 ((← IO.monoMsNow)+100)
    IO.sleep 120
    ensure (← rejected (pool.validate expired "scope" source.head #["owner"])) "expired lease remained usable"
    let before ← pool.stats
    ensure (before.getObjValD "active" == toJson (0 : Nat) && before.getObjValD "queued" == toJson (0 : Nat))
      "query lease cancellation retained its reservation"
    pool.close
    ensure (← rejected (pool.acquire "scope" source.head loaded #[] 0 finish)) "stopped lease pool accepted work"
    return Json.mkObj [("scopeHeadOwnerAndExpiry",toJson true),("boundedAdmission",toJson true),
      ("releasedAndStopped",toJson true),("beforeStop",before),("afterStop",← pool.stats)]
  finally
    pool.close
    owners.close

private def writePrepared (source : DB.PageMap.Snapshot) (directory : System.FilePath)
    (rows : Array StoredRow) (owners : Array (String × Recipe.Stored)) : IO Unit := do
  IO.FS.createDirAll directory
  let recipes ← DB.PageMap.create (directory / "recipes") "owner palette original recipes"
  let payloadBytes := (toJson rows).compress.toUTF8
  let payload := Sha256.hex payloadBytes
  IO.FS.writeBinFile (directory / (payload ++ ".json")) payloadBytes
  let initial : Cache.Manifest := {
    source := source.head,implementation := Cache.implementation,payload,rows := rows.size,
    statistics := {nativeOwners := owners.size,originalRows := rows.size}}
  let _ ← DB.PageMap.withWriter recipes fun writer => do
    for (owner,stored) in owners do Recipe.write writer owner stored
    writer.put "manifest" (some
      (toJson (initial.source,initial.implementation,initial.payload,initial.bindings,initial.supplements)).compress.toUTF8)
  let recipes ← DB.PageMap.pin recipes.directory
  let metadata := {initial with recipes := some recipes.head}
  IO.FS.writeFile (directory / "manifest.json") (toJson metadata).compress
  ensure ((← Cache.atSource? source directory metadata).isSome) "palette fixture has an invalid publication manifest"

private def fetches (palette : OwnerPalette.Projection) : Array OwnerPalette.Fetch :=
  palette.owners.map fun (owner,descriptor) =>
    let size := descriptor.rows.size
    let indices := if size == 0 then #[] else
      (hashDistinct [0,size/2,size-1]).toArray
    {owner,indices}

private def verify (expected : Std.HashMap String Recipe.Stored)
    (metadata : Std.HashMap String OwnerPalette.Descriptor)
    (palette : OwnerPalette.Projection) (response : OwnerPalette.Reply) : IO Unit := do
  for part in response.parts do
    let stored := expected[part.owner]?.getD ⟨#[],[]⟩
    let selected ← IO.ofExcept (OwnerPalette.select stored part.indices)
    ensure (part.rows == selected.rows) "selected fetch differs from its exact saved original rows"
  for (owner,descriptor) in palette.owners do
    ensure (metadata[owner]? == some descriptor) "palette differs from exact original costs or catalogue"

private def phase (reference : Publication.Client.SourceReference) (ids : Array String)
    (expected : Std.HashMap String Recipe.Stored) (metadata : Std.HashMap String OwnerPalette.Descriptor) : IO Json := do
  let tasks ← (List.range 80).mapM fun index => IO.asTask (do
    let started ← IO.monoMsNow
    let ids := if index%2 == 0 then ids else ids.reverse
    let count ← Publication.Client.withSourcePalette reference ids (started+28000) fun palette => do
      let requests := fetches palette
      let response ← Publication.Client.sourceFetch reference palette requests (started+28000)
      verify expected metadata palette response
      return response.parts.foldl (fun n part => n+part.rows.size) 0
    return ((← IO.monoMsNow)-started,count)) .dedicated
  let mut results := #[]
  let mut errors := #[]
  for task in tasks do
    match ← IO.wait task with
    | .ok result => results := results.push result
    | .error error => errors := errors.push error.toString
  let times := results.map Prod.fst
  return Json.mkObj [("clients",toJson (80 : Nat)),("successes",toJson results.size),("errors",toJson errors),
    ("p50Ms",toJson (percentile times 50)),("p95Ms",toJson (percentile times 95)),
    ("p99Ms",toJson (percentile times 99)),("maxMs",toJson (times.foldl max 0)),
    ("selectedRowsPerSuccessfulClient",toJson (results.map Prod.snd)),
    ("transport",toJson "loopback TCP"),("actualHook",toJson false)]

private def audit (mode : String) : IO UInt32 := do
  let resume := !mode.isEmpty
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let shared := study / "shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let records := project / "docs/candidates/owner-palette" / mode
  let trial := shared / "owner-palette-trial"
  ensure ((resume || !(← trial.pathExists)) && !(← (records / "result.json").pathExists)) "preserve previous palette trial"
  IO.FS.createDirAll trial
  IO.FS.createDirAll records
  let (original,rows) ← Eggshell.Research.FrozenCanonicalBasis.load study shared
  let originalFiles ← if resume then Eggshell.Research.StudyRuntime.files original.directory
    else Eggshell.Research.StudyRuntime.checkpoint original.directory (trial / "work.egg")
  let source ← DB.PageMap.pin (trial / "work.egg")
  ensure ((← Eggshell.Research.StudyRuntime.files source.directory) == originalFiles) "existing palette source changed"
  let inventory ← read (study / "seed-originals.json")
  let documents : Array Json ← IO.ofExcept (inventory.getObjValAs? _ "documents")
  let ids ← documents.mapM fun doc => IO.ofExcept (doc.getObjValAs? String "owner")
  let ids := ids.push "absent-owner"
  let owners ← ids.mapM fun owner => do
    let selected := rows.filterMap fun row =>
      let origins := row.origins.filter (·.binding.owner == owner)
      if origins.isEmpty then none else some {row with origins}
    return (owner,← IO.ofExcept (Recipe.compile selected))
  let path ← Cache.directory source .database
  let reference : Shared.Projection := ⟨Json.null,owners.map (fun (owner,stored) => (owner,stored.rows)),.hit,
    owners.map (fun (owner,stored) => (owner,stored.records))⟩
  let some restored := Eggshell.Research.SourceProjectionWire.unpack (Eggshell.Research.SourceProjectionWire.pack reference) |
    throw (IO.userError "shared dictionary failed to restore original source data")
  ensure (toJson restored == toJson reference) "shared dictionary changed code, layout, scope or origin order"
  if resume then
    let some metadata ← Cache.manifestAt? source path | throw (IO.userError "prepared original manifest is missing")
    ensure ((← Cache.atSource? source path metadata).isSome) "existing original preparation is invalid"
  else writePrepared source path rows owners
  let lifecycle ← leaseLifecycle source path
  let binary ← IO.appPath
  let dataRoot := trial / (if resume then "data-" ++ mode else "data")
  let expected : Eggshell.Research.StudyRuntime.PublisherRuntime := {
    binary := binary.toString,sha256 := ← Eggshell.Research.ArtifactHash.hex binary,
    generation := ← Publication.generation}
  IO.FS.writeFile (records / "sealed.json") (Json.mkObj [
    ("runtime",toJson expected),("source",toJson source.head),("sourceFiles",toJson originalFiles),
    ("existingSourcePreparationReused",toJson resume),("newSeed",toJson false),
    ("answeringModelCalls",toJson (0 : Nat))]).pretty
  let environment := #[("EGGSHELL_DATA_ROOT",some dataRoot.toString),("LEAN_NUM_THREADS",some "1")]
  let service ← Eggshell.Research.StudyRuntime.startPublisher binary dataRoot environment (expectedRuntime := some expected)
  try
    let endpoint ← IO.ofExcept (fromJson? (α := Daemon.Endpoint) (← read (dataRoot / "publisher/endpoint.json")))
    ensure (endpoint.pid == Eggshell.Research.StudyRuntime.pid service && endpoint.compatible expected.generation)
      "owned palette service endpoint changed"
    let some reference ← Publication.Client.prepareSourceUsing endpoint source .database ((← IO.monoMsNow)+28000) |
      throw (IO.userError "palette source could not be opened read-only")
    let before ← Daemon.exchange endpoint "stats" >>= fun text => IO.ofExcept (Json.parse text)
    let expectedRows := Std.HashMap.ofArray owners
    let expectedPalettes ← owners.mapM fun (owner,stored) => do
      let layout ← IO.ofExcept (Recipe.check stored.rows stored.records)
      return (owner,OwnerPalette.describe stored layout)
    let expectedPalettes := Std.HashMap.ofArray expectedPalettes
    let cold ← phase reference ids expectedRows expectedPalettes
    let afterCold ← Daemon.exchange endpoint "stats" >>= fun text => IO.ofExcept (Json.parse text)
    IO.FS.writeFile (records / "cold.json") cold.pretty
    ensure (cold.getObjValD "successes" == toJson (80 : Nat)) "cold palette/fetch requests did not all complete"
    let warm ← phase reference ids expectedRows expectedPalettes
    IO.FS.writeFile (records / "warm.json") warm.pretty
    ensure (warm.getObjValD "successes" == toJson (80 : Nat)) "warm palette/fetch requests did not all complete"
    let deadline := (← IO.monoMsNow)+28000
    let palette ← Publication.Client.sourcePalette reference ids deadline
    let legacy ← Publication.Client.sourceRows reference ids deadline
    ensure (legacy.values.all fun ready =>
      (expectedRows[ready.owner]?).any (· == ready.stored)) "full original reference changed"
    let bytes := (toJson palette).compress.utf8ByteSize
    let legacyBytes := (toJson legacy.raw).compress.utf8ByteSize
    let requests := fetches palette
    let response ← Publication.Client.sourceFetch reference palette requests deadline
    let fetchBytes := (toJson response).compress.utf8ByteSize
    ensure (← rejected (Publication.Client.sourcePalette {reference with endpoint := {reference.endpoint with secret := "wrong"}} ids deadline))
      "palette accepted a foreign capability"
    let some (owner,descriptor) := palette.owners.find? (fun (_,descriptor) => !descriptor.rows.isEmpty) |
      throw (IO.userError "empty original palette audit")
    ensure (← rejected (Publication.Client.sourceFetch reference palette #[{owner,indices := #[descriptor.rows.size]}] deadline))
      "fetch accepted an out-of-range original"
    let changed := {palette with identity := Json.null}
    ensure (← rejected (Publication.Client.sourceFetch reference changed requests deadline)) "fetch accepted another source view"
    ensure (← rejected (Publication.Client.sourcePalette reference ids 0)) "palette ignored expiry"
    Publication.Client.releaseSourcePalette reference palette.lease deadline
    let after ← Daemon.exchange endpoint "stats" >>= fun text => IO.ofExcept (Json.parse text)
    let arena := (after.getObjValD "preparedSources").getObjValD "owners"
    ensure (arena.getObjValD "loads" == toJson ids.size && arena.getObjValD "borrowers" == toJson (0 : Nat))
      "metadata preparation was repeated or a source loan leaked"
    let queries := after.getObjValD "paletteQueries"
    ensure (queries.getObjValD "active" == toJson (0 : Nat) && queries.getObjValD "queued" == toJson (0 : Nat))
      "original query metadata loan was not released"
    ensure ((← Eggshell.Research.StudyRuntime.files original.directory) == originalFiles &&
      (← Eggshell.Research.StudyRuntime.files source.directory) == originalFiles) "palette audit changed the original snapshot"
    IO.FS.writeFile (records / "result.json") (Json.mkObj [
      ("source",toJson source.head),("runtime",toJson expected),("sourceUnchanged",toJson true),
      ("owners",toJson ids.size),("rows",toJson rows.size),("cold",cold),("warm",warm),
      ("paletteJsonBytes",toJson bytes),("legacyJsonBytes",toJson legacyBytes),("selectedFetchJsonBytes",toJson fetchBytes),
      ("before",before),("afterCold",afterCold),("after",after),("leaseLifecycle",lifecycle),
      ("sharedDictionaryRoundtrip",toJson true),
      ("scopeBoundsExpiryAndExactRows",toJson true),("fullQueryPlannerConnected",toJson false),
      ("actualHooks",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
    IO.println s!"Original palette: {bytes} bytes; full source projection: {legacyBytes}; selected fetch: {fetchBytes}"
    return 0
  finally Eggshell.Research.StudyRuntime.stopManaged service (records / "shutdown.json")

def main (args : List String) : IO UInt32 := do
  if args == ["codex-publication-daemon"] then Publication.Service.run
  else audit (if args == ["resume"] then "resumed" else if args == ["leased"] then "leased"
    else if args == ["compact"] then "compact" else "")
