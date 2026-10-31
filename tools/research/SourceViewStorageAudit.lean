import Eggshell.CanonicalSourcePrepared
import Eggshell.NativePublication
import tools.research.ArtifactHash
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.CanonicalSource
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false
  catch _ => return true

private def publish (root database : System.FilePath) (round : Nat) : IO DB.PageMap.Snapshot := do
  let command := if round == 1 then "nl -ba source.txt | sed -n '1,4p'"
    else "nl -ba source.txt | sed -n '2,3p'"
  let input := Json.mkObj [("path",toJson "source.txt"),("cmd",toJson command)]
  let capture ← SourceEvidence.capture root input ((← IO.monoMsNow)+5000)
  ensure capture.record.complete "fixture input was not observed"
  let output := if round == 1 then "1\tif (ready) {\n2\t  execute();\n3\t}\n4\tfinish();\n"
    else "2\t  execute();\n3\t}\n"
  let pending : PendingTurn := {
    sessionId := s!"storage-{round}",turnId := "turn",cwd := root.toString,
    prompt := "inspect original source",profile := "work",semanticMatcher := none,
    read := [database.toString],write := some database.toString,handoffChars := 120000,projection := .none,
    tools := [{
      name := "read",useId := s!"read-{round}",input := input.compress,
      response := (toJson output).compress,source := some capture}]}
  let saved ← NativePublication.run pending database true
  ensure saved.source.accounted "fixture publication was not accounted"
  DB.PageMap.pin database

def main (args : List String) : IO Unit := do
  let [rootArg,resultArg] := args | throw (IO.userError "storage trial and result required")
  let root : System.FilePath := .mk rootArg
  let result : System.FilePath := .mk resultArg
  ensure (!(← root.pathExists) && !(← result.pathExists)) "preserve storage audit"
  IO.FS.createDirAll root
  IO.FS.writeFile (root / "source.txt") "if (ready) {\n  execute();\n}\nfinish();\n"
  let database := root / "source.egg"
  let source ← publish root database 1
  let _ ← Build.refresh source .database
  let first ← Cache.refresh source .database
  ensure (first.mode == "owner-stream" && first.metadata.rows > 0) "bootstrap did not prepare real original rows"
  let path ← Cache.directory source .database
  let some old ← Cache.preparedAt? source path first.metadata | throw (IO.userError "bootstrap root not ready")
  let oldEntries ← Build.entries source
  let oldReader ← Persistence.Store.NodeReader.new source
  let documents ← oldEntries.mapM fun entry => Build.document oldReader entry.id
  let owners := documents.filterMap fun doc => if doc.native then some doc.owner else none
  let headBefore ← Eggshell.Research.ArtifactHash.hex (database / "head")
  let pool ← Shared.Pool.new
  let loaded ← pool.withReady source path first.metadata ((← IO.monoMsNow)+5000) fun loaded _ => pure loaded
  let deadline := (← IO.monoMsNow)+10000
  let tasks ← (Array.range 80).mapM fun _ => IO.asTask (do
    for owner in owners do
      loaded.withMetadata owner deadline fun ready => do
        ensure (!ready.rows.isEmpty) "published view lost its original rows"
        for file in ready.stored.descriptor.files do
          loaded.withFile file deadline fun header => ensure (header.stored.file == file) "file header crossed scope") .dedicated
  for task in tasks do let _ ← IO.ofExcept (← IO.wait task)
  let rawStats ← pool.owners.stats
  let metadataState ← pool.views.state.atomically get
  ensure (rawStats.getObjValD "loads" == toJson (0 : Nat) && metadataState.loads == owners.size &&
    metadataState.entries.fold (fun total _ entry => total+entry.borrowers) 0 == 0)
    "metadata consumers fetched bodies or repeated immutable loads"
  pool.close
  ensure ((← Eggshell.Research.ArtifactHash.hex (database / "head")) == headBefore) "metadata read changed source"
  let next ← publish root database 2
  let _ ← Build.refresh next .database
  let second ← Cache.refresh next .database
  ensure (second.mode == "owner-delta" && second.hydrated == 1 && second.metadata.rows > first.metadata.rows)
    "one-owner change rebuilt the whole view or lost old rows"
  let some current ← Cache.preparedAt? next path second.metadata | throw (IO.userError "delta root not ready")
  for owner in owners do
    let before ← PreparedSourceView.readOwner old source.head.identity owner
    let after ← PreparedSourceView.readOwner current next.head.identity owner
    ensure ((toJson before.stored).compress == (toJson after.stored).compress) "unaffected owner changed during delta"
  ensure ((← Cache.preparedAt? source path first.metadata).isSome) "delta retired a live old pin"
  let retained ← Cache.manifestAt? source path
  ensure (retained == some first.metadata) "retained original root was not addressable"
  ensure (← rejected (PreparedSourceView.readOwner current source.head.identity "missing-owner"))
    "missing metadata rebuilt itself"
  let wrong := {second.metadata with payload := String.ofList (List.replicate 64 'f')}
  ensure (← rejected (Cache.preparedAt? next path wrong)) "a changed header was accepted"
  let warm ← Cache.refresh next .database
  ensure (warm.mode == "warm" && warm.hydrated == 0) "unchanged warm rehydrated originals"
  let some header ← Cache.header? current | throw (IO.userError "committed header missing")
  let some owner := owners[0]? | throw (IO.userError "fixture owner missing")
  let some stored ← CanonicalSource.Recipe.read? current owner | throw (IO.userError "fixture recipe missing")
  let stale := "retired-owner"
  let staleStored := {stored with rows := stored.rows.map fun row =>
    {row with origins := row.origins.map fun origin => {origin with binding := {origin.binding with owner := stale}}}}
  let _ ← DB.PageMap.withWriter current fun writer => do
    CanonicalSource.Recipe.write writer stale staleStored
    PreparedSourceView.publishOwner writer stale staleStored
    Persistence.Store.putPayload writer (Cache.stateName 999999) (toJson (⟨stale,0,{}⟩ : Cache.OwnerState)).compress.toUTF8
    Persistence.Store.putPayload writer "view-header" (toJson {header with implementation := "changed-producer"}).compress.toUTF8
  let rebuilt ← Cache.refresh next .database
  ensure (rebuilt.mode == "owner-stream" && rebuilt.metadata.rows == second.metadata.rows)
    "producer rebuild changed original row population"
  let some rebuiltView ← Cache.preparedAt? next path rebuilt.metadata | throw (IO.userError "rebuilt view not ready")
  ensure ((← rebuiltView.get (CanonicalSource.Recipe.name stale)).isNone &&
    (← rebuiltView.get (PreparedSourceView.ownerName stale)).isNone) "producer rebuild retained a deleted owner"
  ensure ((← PreparedSourceView.readOwner old source.head.identity owner).rows.size > 0)
    "bootstrap lost an old reader"
  IO.FS.createDirAll result.parent.get!
  IO.FS.writeFile result (Json.mkObj [
    ("bootstrapMode",toJson first.mode),("bootstrapOwnerRows",toJson first.metadata.rows),
    ("deltaMode",toJson second.mode),("deltaHydrated",toJson second.hydrated),
    ("unchangedWarmHydrated",toJson warm.hydrated),("metadataConsumers",toJson (80 : Nat)),
    ("metadataLoads",toJson metadataState.loads),("bodyLoadsBeforeFetch",rawStats.getObjValD "loads"),
    ("oldPinsAndRetainedRoots",toJson true),("missingAndChangedHeaderRejected",toJson true),
    ("staleOwnerRemovedDuringRebuild",toJson true),("ordinaryHooks",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "Real publication bootstrap/delta, metadata-only shared reads, readiness, retained roots and rebuild passed"
