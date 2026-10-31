import tools.research.PublishedPlanMetadata
import tools.research.FrozenCanonicalBasis
import tools.research.ArtifactHash
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false
  catch _ => return true

def main (args : List String) : IO Unit := do
  let [trialArg,resultArg] := args | throw (IO.userError "trial and result paths required")
  let trial : System.FilePath := .mk trialArg
  let result : System.FilePath := .mk resultArg
  ensure (!(← trial.pathExists) && !(← result.pathExists)) "preserve metadata trial evidence"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let original := study / "r0/stage1/history/source.egg"
  let before ← Eggshell.Research.ArtifactHash.hex (original / "head")
  let (source,rows) ← Eggshell.Research.FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let pagesBefore ← Eggshell.Research.ArtifactHash.hex (DB.PageMap.dataPath source.directory source.head)
  let mut grouped : Std.HashMap String (Array StoredRow) := {}
  for row in rows do
    for owner in hashDistinct (row.origins.toList.map (·.binding.owner)) do
      let ownerRow := {row with origins := row.origins.filter (·.binding.owner == owner)}
      grouped := grouped.insert owner ((grouped[owner]?.getD #[]).push ownerRow)
  let mut originals := #[]
  for (owner,parts) in grouped.toArray.qsort (fun a b => a.1 < b.1) do
    originals := originals.push (owner,← IO.ofExcept (Recipe.compile parts))
  let index ← DB.PageMap.create trial "published original plan metadata audit"
  let old ← DB.PageMap.pin trial
  let publishStarted ← IO.monoMsNow
  let _ ← DB.PageMap.withWriter index fun writer => do
    for (owner,stored) in originals do
      Recipe.write writer owner stored
      PublishedPlanMetadata.publish writer owner stored
    writer.put "manifest" (some "published".toUTF8)
  let publicationMs := (← IO.monoMsNow)-publishStarted
  let pinned ← DB.PageMap.pin trial
  let mut costs : Std.HashMap Key (Nat × Nat) := {}
  let mut restored := #[]
  let mut metadataBytes := 0
  let rehydrateStarted ← IO.monoMsNow
  for (owner,expected) in originals do
    ensure ((← old.get (Recipe.name owner)).isNone && (← old.get (PublishedPlanMetadata.name owner)).isNone)
      "old pin exposed a partial future publication"
    let some stored ← Recipe.read? pinned owner | throw (IO.userError "committed recipe missing")
    ensure (stored == expected) "committed recipe changed"
    let metadata ← PublishedPlanMetadata.read pinned owner
    let layout ← IO.ofExcept (Recipe.check stored.rows stored.records)
    let checked ← IO.ofExcept (PublishedPlanMetadata.check owner stored layout metadata)
    ensure (metadata.owner == owner && metadata.costs.size == stored.rows.size) "published row ordinals changed"
    ensure ((PublishedPlanMetadata.check "foreign-owner" stored layout metadata).toOption.isNone) "metadata accepted a foreign owner"
    if let some cost := metadata.costs[0]? then
      let corrupted := {metadata with costs := metadata.costs.set! 0 (cost.1+1,cost.2+1)}
      ensure ((PublishedPlanMetadata.check owner stored layout corrupted).toOption.isNone) "corrupt published row cost accepted"
    for (row,cost) in stored.rows.zip checked.metadata.costs do
      if let some previous := costs[row.key]? then ensure (previous == cost) "shared row costs disagree"
      costs := costs.insert row.key cost
    metadataBytes := metadataBytes+(toJson metadata).compress.utf8ByteSize
    restored := restored ++ stored.rows
  let rehydrateMs := (← IO.monoMsNow)-rehydrateStarted
  ensure (← rejected (PublishedPlanMetadata.read pinned "absent-owner")) "missing metadata silently rebuilt"
  let merged ← IO.ofExcept (Delivery.merge restored)
  ensure (merged == rows) "metadata publication changed the complete original population"
  let frames : Array (Nat × Nat) := #[(0,0),(47,63),(0,0)]
  let expected := (Eggshell.Research.PreparedSourceCosts.prepare rows frames).data
  let started ← IO.monoMsNow
  let built ← IO.ofExcept (PublishedPlanMetadata.sourceDomain rows costs frames)
  let sourceDomainMs := (← IO.monoMsNow)-started
  ensure (built.rows == expected.rows && built.costs == expected.costs && built.payloads == expected.payloads &&
    rows.all (fun row => built.rowIds[row.key]? == expected.rowIds[row.key]? &&
      built.fileIds[row.key.file]? == expected.fileIds[row.key.file]?)) "published cost domain differs from original rendering"
  if let some first := rows[0]? then
    ensure ((PublishedPlanMetadata.sourceDomain rows (costs.erase first.key) frames).toOption.isNone)
      "query rebuilt an unprepared row cost"
  let some (changedOwner,first) := originals[0]? | throw (IO.userError "empty metadata population")
  let changed ← IO.ofExcept (Recipe.compile (first.rows.extract 0 (first.rows.size-1)))
  let _ ← DB.PageMap.withWriter pinned fun writer => do
    Recipe.write writer changedOwner changed
    PublishedPlanMetadata.publish writer changedOwner changed
    writer.put "manifest" (some "delta".toUTF8)
  let next ← DB.PageMap.pin trial
  ensure ((← Recipe.read? pinned changedOwner) == some first && (← Recipe.read? next changedOwner) == some changed)
    "delta changed an old pinned owner"
  for (owner,_) in originals do
    if owner != changedOwner then
      ensure ((← pinned.readPayload (PublishedPlanMetadata.name owner)) == (← next.readPayload (PublishedPlanMetadata.name owner)))
        "one-owner delta rewrote unrelated metadata"
  ensure ((← Eggshell.Research.ArtifactHash.hex (original / "head")) == before &&
    (← Eggshell.Research.ArtifactHash.hex (DB.PageMap.dataPath source.directory source.head)) == pagesBefore)
    "metadata audit changed the source DB"
  IO.FS.createDirAll result.parent.get!
  IO.FS.writeFile result (Json.mkObj [
    ("sourceUnchanged",toJson true),("originalRows",toJson rows.size),("owners",toJson originals.size),
    ("publishedMetadataBytes",toJson metadataBytes),("publicationMs",toJson publicationMs),
    ("rehydrationAndChecksMs",toJson rehydrateMs),("metadataDomainMs",toJson sourceDomainMs),
    ("completeCostDomainExact",toJson true),("atomicRecipeAndPlan",toJson true),
    ("oldPinAndOneOwnerDelta",toJson true),("missingAndCorruptRejected",toJson true),
    ("actualHooks",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "Published metadata, exact cost domain, old pin, delta and rejection checks passed"
