import tools.research.PreparedSourceView
import tools.research.SharedMetadataCache
import tools.research.PreparedFileIdentities
import tools.research.FrozenCanonicalBasis
import tools.research.ArtifactHash
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false
  catch _ => return true

private def federationFixture : IO Json := do
  let file : File := ⟨"resource",String.ofList (List.replicate 64 'a'),4096⟩
  let row := fun database line code => ({
    key := ⟨file,line⟩,code,
    origins := #[⟨⟨"session","turn","read"⟩,⟨database,"owner","work",line*10,line*10+8⟩⟩]} : StoredRow)
  let first ← IO.ofExcept (Recipe.compile #[row "project-a" 1 "alpha();",row "project-a" 3 "gamma();"])
  let second ← IO.ofExcept (Recipe.compile #[row "project-b" 1 "alpha();",row "project-b" 2 "beta();"])
  let decode := fun (database : String) (stored : Recipe.Stored) => do
    let layout ← IO.ofExcept (Recipe.check stored.rows stored.records)
    IO.ofExcept (PreparedSourceView.decodeOwner database "owner" (PreparedSourceView.ownerStored "owner" stored layout))
  let a ← decode "project-a" first
  let b ← decode "project-b" second
  let header : PreparedSourceView.FileReady := ⟨PreparedSourceView.fileStored file,rfl,rfl⟩
  let headers := Std.HashMap.ofArray #[(file,header)]
  let rows ← IO.ofExcept (PreparedSourceView.join (a.rows ++ b.rows) headers)
  let merged ← IO.ofExcept (Delivery.merge (first.rows ++ second.rows))
  let records ← IO.ofExcept (Recipe.combine first.rows second.rows merged first.records second.records)
  let layout ← IO.ofExcept (Recipe.check merged records)
  for groups in [[],[[(5,50)]],[[(10,18)],[(30,38)]]] do
    let actual ← IO.ofExcept (PreparedSourceView.federatedUnits "owner" #[a,b] rows groups)
    let expected := PreparedFileUnits.combine "owner" merged layout (PreparedFileUnits.prepare "owner" merged layout) groups
    ensure (actual.map (·.keys) == expected.map (fun unit => unit.rows.map (·.key)) &&
      actual.map (·.ranges) == expected.map (·.ranges)) "metadata federation differs from original record federation"
  let bad := {a.stored with plan := {a.stored.plan with costs := a.stored.plan.costs.set! 0 (99,99)}}
  ensure ((PreparedSourceView.decodeOwner "project-a" "owner" bad).toOption.isNone) "mismatched stored costs accepted"
  ensure ((PreparedSourceView.decodeOwner "project-b" "owner" a.stored).toOption.isNone)
    "metadata federation bypassed original project validation"
  ensure ((PreparedSourceView.decodeOwner "project-a" "foreign-owner" a.stored).toOption.isNone)
    "metadata accepted a foreign owner"
  let missing := {a.stored with plan := {a.stored.plan with units := #[⟨[999999],[]⟩]}}
  ensure ((PreparedSourceView.decodeOwner "project-a" "owner" missing).toOption.isNone)
    "metadata accepted a missing row ordinal"
  return Json.mkObj [("projects",toJson (2 : Nat)),("groupCases",toJson (3 : Nat)),
    ("originalRecordFederationExact",toJson true),("foreignAndCorruptMetadataRejected",toJson true)]

private def cacheFixture : IO Json := do
  let cache ← SharedMetadataCache.Cache.new Nat (128*1024) 2 2
  let started ← IO.monoMsNow
  let counter ← IO.mkRef (0 : Nat)
  let tasks ← (Array.range 80).mapM fun _ => IO.asTask (cache.withReady "snapshot/project/owner" 65536 (started+5000)
    (do counter.modify (·+1); IO.sleep 30; pure 41)
    (fun value => do ensure (value == 41) "joined metadata changed its value"; IO.sleep 1)) .dedicated
  for task in tasks do let _ ← IO.ofExcept (← IO.wait task)
  let state ← cache.state.atomically get
  ensure (state.loads == 1 && (← counter.get) == 1 && state.entries.size == 1 &&
    state.entries.fold (fun total _ entry => total+entry.borrowers) 0 == 0 && state.budget.used == 65536)
    "80 metadata borrowers did not share one charged load"
  ensure (← rejected (cache.withReady "expired" 65536 started (pure 0) (fun _ => pure ())))
    "expired metadata request was admitted"
  cache.close
  ensure (← rejected (cache.withReady "late" 65536 (started+5000) (pure 0) (fun _ => pure ())))
    "closed metadata cache restarted a loader"
  return Json.mkObj [("borrowers",toJson (80 : Nat)),("loads",toJson state.loads),
    ("borrowersAfter",toJson (0 : Nat)),("closedAndExpiredRejected",toJson true)]

def main (args : List String) : IO Unit := do
  let [trialArg,resultArg] := args | throw (IO.userError "trial and result required")
  let trial : System.FilePath := .mk trialArg
  let result : System.FilePath := .mk resultArg
  ensure (!(← trial.pathExists) && !(← result.pathExists)) "preserve source-view audit"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let original := study / "r0/stage1/history/source.egg"
  let before ← Eggshell.Research.ArtifactHash.hex (original / "head")
  let (source,rows) ← Eggshell.Research.FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let pagesBefore ← Eggshell.Research.ArtifactHash.hex (DB.PageMap.dataPath source.directory source.head)
  let mut grouped : Std.HashMap String (Array StoredRow) := {}
  let mut byFile : Std.HashMap File (Array StoredRow) := {}
  for row in rows do
    byFile := byFile.insert row.key.file ((byFile[row.key.file]?.getD #[]).push row)
    for owner in hashDistinct (row.origins.toList.map (·.binding.owner)) do
      let value := {row with origins := row.origins.filter (·.binding.owner == owner)}
      grouped := grouped.insert owner ((grouped[owner]?.getD #[]).push value)
  let mut owners := #[]
  for (owner,parts) in grouped.toArray.qsort (fun a b => a.1 < b.1) do
    owners := owners.push (owner,← IO.ofExcept (Recipe.compile parts))
  let index ← DB.PageMap.create trial "source-view metadata audit"
  let old ← DB.PageMap.pin trial
  let publishStarted ← IO.monoMsNow
  let _ ← DB.PageMap.withWriter index fun writer => do
    for (owner,stored) in owners do
      Recipe.write writer owner stored
      PreparedSourceView.publishOwner writer owner stored
    for (file,_) in byFile do PreparedSourceView.publishFile writer file
    writer.put "manifest" (some "source-view".toUTF8)
  let publicationMs := (← IO.monoMsNow)-publishStarted
  let pinned ← DB.PageMap.pin trial
  let mut files := {}
  for (file,_) in byFile do
    let ready ← PreparedSourceView.readFile pinned file
    ensure ready.stored.extents.isEmpty "file header unexpectedly contains a DB-wide parse"
    files := files.insert file ready
  let mut refs := #[]
  let mut groupsChecked := 0
  let mut metadataBytes := 0
  for (owner,stored) in owners do
    ensure ((← old.get (PreparedSourceView.ownerName owner)).isNone) "old pin saw a future owner view"
    let ready ← PreparedSourceView.readOwner pinned source.head.identity owner
    for (file,extents) in ready.stored.scopes do
      let parts := stored.rows.filter (·.key.file == file)
      ensure (extents == PreparedSourceView.compileExtents parts) "published observation scopes changed"
      if let some previous := files[file]? then files := files.insert file (previous.addExtents extents)
    ensure (ready.rows.map (·.key) == stored.rows.map (·.key)) "metadata changed original row identities"
    ensure (ready.rows.map (·.cost) == stored.rows.map PublishedPlanMetadata.rowCost)
      "metadata changed original row costs"
    ensure (← rejected (PreparedSourceView.readOwner pinned "foreign-project" owner)) "metadata crossed a project"
    let layout ← IO.ofExcept (Recipe.check stored.rows stored.records)
    let base := PreparedFileUnits.prepare owner stored.rows layout
    let samples := (hashDistinct [0,stored.rows.size/2,stored.rows.size-1]).filterMap fun index =>
      (stored.rows[index]?).bind fun row => row.origins[0]? |>.map fun origin => [(origin.binding.first,origin.binding.limit)]
    for spans in samples do
      let expected := PreparedFileUnits.combine owner stored.rows layout base [spans]
      let actual ← IO.ofExcept (PreparedSourceView.groupedUnits owner ready [spans])
      ensure (actual.map (·.keys) == expected.map (fun unit => unit.rows.map (·.key)) &&
        actual.map (·.ranges) == expected.map (·.ranges)) "metadata original groups differ from raw-record closure"
      groupsChecked := groupsChecked+1
    metadataBytes := metadataBytes+(toJson ready.stored).compress.utf8ByteSize
    refs := refs ++ ready.rows
  let started ← IO.monoMsNow
  let joined ← IO.ofExcept (PreparedSourceView.join refs files)
  let view ← IO.ofExcept (PreparedSourceView.domain joined files #[(0,0),(43,61),(0,0)])
  let queryMs := (← IO.monoMsNow)-started
  let expected := (Eggshell.Research.PreparedSourceCosts.prepare rows #[(0,0),(43,61),(0,0)]).data
  ensure (view.rows.map (·.key) == rows.map (·.key) && view.costs == expected.costs && view.payloads == expected.payloads &&
    rows.all (fun row => view.rowIds[row.key]? == expected.rowIds[row.key]? &&
      view.fileIds[row.key.file]? == expected.fileIds[row.key.file]?)) "metadata cost/identity view differs from raw preparation"
  let identities := PreparedFileIdentities.prepare (rows.toList.map (·.key.file))
  ensure (rows.all (fun row => PreparedFileIdentities.rowKey identities row.key == Delivery.rowKey row.key))
    "memoized file identities changed source delivery keys"
  let sharing ← cacheFixture
  let federation ← federationFixture
  ensure ((← Eggshell.Research.ArtifactHash.hex (original / "head")) == before &&
    (← Eggshell.Research.ArtifactHash.hex (DB.PageMap.dataPath source.directory source.head)) == pagesBefore)
    "source-view audit changed original storage"
  IO.FS.createDirAll result.parent.get!
  IO.FS.writeFile result (Json.mkObj [("rows",toJson rows.size),("owners",toJson owners.size),
    ("files",toJson byFile.size),("metadataBytes",toJson metadataBytes),("publicationMs",toJson publicationMs),
    ("metadataJoinAndDomainMs",toJson queryMs),("recordGroupsChecked",toJson groupsChecked),
    ("originalIdentitiesAndCostsExact",toJson true),("scopesPublished",toJson true),("sharingFixture",sharing),
    ("federationFixture",federation),
    ("sourceUnchanged",toJson true),("actualHooks",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false)]).pretty
  IO.println "Body-free metadata, published scopes, original group closure, scope and shared-load checks passed"
