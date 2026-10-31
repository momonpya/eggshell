import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  ensure ((source.splitOn before).length == 2) ("source-view anchor changed: " ++ toString (before.take 100))
  return source.replace before after
private def between (source first last : String) : IO String := do
  let [_,rest] := source.splitOn first | throw (IO.userError ("missing source-view start: " ++ first))
  let [body,_] := rest.splitOn last | throw (IO.userError ("missing source-view end: " ++ last))
  return first ++ body
private def save (path : System.FilePath) (source : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path source

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let parent := root / "published-plan-core"
  let core := root / "prepared-view-core"
  let records := project / "docs/candidates/prepared-view"
  ensure (← core.pathExists) "isolated source-view package is missing"
  for name in ["PreparedRangeCoverage","SharedMetadataCache","PreparedSourceView","PreparedSourceViewAudit","PreparedFileIdentities"] do
    save (core / "tools/research" / (name ++ ".lean")) (← IO.FS.readFile (project / "tools/research" / (name ++ ".lean")))
  let mut cache ← IO.FS.readFile (project / "tools/research/SourceViewPublication.lean")
  for (before,after) in [
    ("include_str \"SourceViewPublication.lean\"","include_str \"CanonicalSourceCache.lean\""),
    ("include_str \"PreparedSourceView.lean\"","include_str \"../tools/research/PreparedSourceView.lean\""),
    ("include_str \"OwnerPalette.lean\"","include_str \"../tools/research/OwnerPalette.lean\""),
    ("include_str \"PreparedFileUnits.lean\"","include_str \"../tools/research/PreparedFileUnits.lean\""),
    ("include_str \"PublishedPlanMetadata.lean\"","include_str \"../tools/research/PublishedPlanMetadata.lean\""),
    ("include_str \"../../Eggshell/CanonicalSource.lean\"","include_str \"CanonicalSource.lean\""),
    ("include_str \"../../Eggshell/CanonicalSourceRecipe.lean\"","include_str \"CanonicalSourceRecipe.lean\""),
    ("include_str \"../../Eggshell/CanonicalSourceRecords.lean\"","include_str \"CanonicalSourceRecords.lean\""),
    ("include_str \"ScopeAlternatives.lean\"","include_str \"../tools/research/ScopeAlternatives.lean\""),
    ("include_str \"ReferenceRequirements.lean\"","include_str \"../tools/research/ReferenceRequirements.lean\"")]
    do cache ← once cache before after
  cache ← once cache "  (include_str \"CanonicalSourceRecords.lean\").toUTF8,"
    ("  (include_str \"CanonicalSourceRecords.lean\").toUTF8,\n" ++
     "  (include_str \"SynapseBuild.lean\").toUTF8,(include_str \"SynapseProvenance.lean\").toUTF8,\n" ++
     "  ContentCapture.implementation.toUTF8,")
  save (core / "Eggshell/CanonicalSourceCache.lean") cache
  let mut arena ← IO.FS.readFile (parent / "tools/research/PreparedOwnerArena.lean")
  arena ← once arena "def capacity : Nat := 304*1024*1024" "def capacity : Nat := 240*1024*1024"
  arena := arena.replace "Snapshot headers keep 64 MiB, geometry 16 MiB,\nand PageMap pages 128 MiB; these resident owners use the remaining 304 MiB."
    "Snapshot headers keep 48 MiB, owner metadata 64 MiB, file headers 16 MiB,\ngeometry 16 MiB and pages 128 MiB; raw selected owners use 240 MiB."
  save (core / "tools/research/PreparedOwnerArena.lean") arena
  let reader ← IO.FS.readFile (project / "tools/research/SourceViewReader.lean.inc")
  let [aliases,methods] := reader.splitOn "def Loaded.withMetadata" | throw (IO.userError "invalid source-view reader template")
  let mut shared ← IO.FS.readFile (parent / "Eggshell/CanonicalSourcePrepared.lean")
  shared ← once shared "public import tools.research.PreparedOwnerArena\n"
    "public import tools.research.PreparedOwnerArena\npublic import tools.research.PreparedSourceView\npublic import tools.research.SharedMetadataCache\n"
  shared ← once shared "structure Loaded where" (aliases ++ "\nstructure Loaded where")
  shared ← once shared "  owners : PreparedOwnerArena.Cache\n  identity : String"
    "  owners : PreparedOwnerArena.Cache\n  views : MetadataCache\n  files : FileCache\n  identity : String"
  shared ← once shared "/-- The service owns one checked resident value"
    ("def Loaded.withMetadata" ++ methods ++ "\n/-- The service owns one checked resident value")
  shared ← once shared "      let metadata ← PublishedPlanMetadata.read loaded.recipes owner\n"
    "      let metadata ← loaded.withMetadata owner deadline (fun ready => pure ready.stored.plan)\n"
  shared ← once shared "def capacity : Nat := 64*1024*1024" "def capacity : Nat := 48*1024*1024"
  shared ← once shared "theorem shared_resident_capacity : capacity+PreparedOwnerArena.capacity+"
    "theorem shared_resident_capacity : capacity+metadataCapacity+fileCapacity+PreparedOwnerArena.capacity+"
  shared ← once shared "  owners : PreparedOwnerArena.Cache\n\ndef Pool.new"
    "  owners : PreparedOwnerArena.Cache\n  views : MetadataCache\n  files : FileCache\n\ndef Pool.new"
  shared ← once shared "← PreparedOwnerArena.Cache.new⟩"
    "← PreparedOwnerArena.Cache.new,← SharedMetadataCache.Cache.new _ metadataCapacity 4096 2,← SharedMetadataCache.Cache.new _ fileCapacity 4096 2⟩"
  shared ← once shared "return ⟨metadata,recipes,original,pool.owners,identity⟩"
    "return ⟨metadata,recipes,original,pool.owners,pool.views,pool.files,identity⟩"
  shared ← once shared "  pool.owners.close\n" "  pool.owners.close\n  pool.views.close\n  pool.files.close\n"
  save (core / "Eggshell/CanonicalSourcePrepared.lean") shared
  let mut delivery ← IO.FS.readFile (parent / "Eggshell/CanonicalSourceDelivery.lean")
  delivery ← once delivery "public import Eggshell.CanonicalSourcePacket\n"
    "public import Eggshell.CanonicalSourcePacket\npublic import tools.research.PreparedFileIdentities\n"
  delivery ← once delivery
    ("def Part.keys (part : Part) : List String :=\n" ++
     "  (if part.plan.isEmpty then [] else [part.plan]) ++ part.rows.toList.map (fun row => rowKey row.key)")
    ("def Part.keys (part : Part) : List String :=\n" ++
     "  let files := PreparedFileIdentities.prepare (part.rows.toList.map (·.key.file))\n" ++
     "  (if part.plan.isEmpty then [] else [part.plan]) ++ part.rows.toList.map (fun row => PreparedFileIdentities.rowKey files row.key)\n\n" ++
     "theorem Part.keys_exact (part : Part) : part.keys =\n" ++
     "    (if part.plan.isEmpty then [] else [part.plan]) ++ part.rows.toList.map (fun row => rowKey row.key) := by\n" ++
     "  simp only [Part.keys,PreparedFileIdentities.rowKey_exact,rowKey]\n")
  save (core / "Eggshell/CanonicalSourceDelivery.lean") delivery
  let mut handoff ← IO.FS.readFile (parent / "Eggshell/Handoff.lean")
  handoff ← once handoff "public import tools.research.PreparedFileUnits\n"
    "public import tools.research.PreparedFileUnits\npublic import tools.research.PreparedSourceView\npublic import tools.research.PreparedRangeCoverage\n"
  let ranges ← between handoff "def validCoverage (ranges" "structure UnitShape where"
  handoff ← once handoff ranges ("abbrev validCoverage := Eggshell.Research.PreparedRangeCoverage.validCoverage\n" ++
    "abbrev CoverageIndex := Eggshell.Research.PreparedRangeCoverage.CoverageIndex\n" ++
    "abbrev CoverageIndex.prepare := Eggshell.Research.PreparedRangeCoverage.CoverageIndex.prepare\n\n")
  let pieces ← between handoff "def filePieces (scale" "def problemFromPrepared"
  let pieces := pieces.replace "def filePieces" "def viewPieces"
    |>.replace "Array Synapses.CanonicalSource.StoredRow" "Array Synapses.PreparedSourceView.RowRef"
    |>.replace "cachedBindings query.owner" "Synapses.PreparedSourceView.bindings query.owner"
  let problem ← between handoff "def problemFromPrepared" "/-- The original selector consumes coordinate/cost stencils."
  let problem := problem.replace "problemFromPrepared" "problemFromView"
    |>.replace "Eggshell.Research.PreparedSourceCosts.Data" "Synapses.PreparedSourceView.Domain"
  let selection ← between handoff "def selectPrepared (query" "namespace RangeLocators"
  let mut selection := selection.replace "selectPrepared" "selectView"
    |>.replace "problemFromPrepared" "problemFromView"
    |>.replace "Eggshell.Research.PreparedSourceCosts.Data" "Synapses.PreparedSourceView.Domain"
    |>.replace "Eggshell.Research.PreparedSourceCosts.bind" "Synapses.PreparedSourceView.bind"
    |>.replace "let requirements := bound.requirements" "let requirements := bound"
  selection ← once selection
    ("  let scopes ← Eggshell.Research.ScopeAlternatives.prepareUsingFrames compiled query.owners.size\n" ++
     "    requirements.sourceRows requirements.dependencies bound.frames")
    "  let scopes ← Synapses.PreparedSourceView.prepareScopes source compiled query.owners.size ⟨bound.sourceRows,bound.frames⟩"
  handoff ← once handoff "namespace RangeLocators" (pieces ++ problem ++ selection ++ "\nnamespace RangeLocators")
  save (core / "Eggshell/Handoff.lean") handoff
  let mut service ← IO.FS.readFile (parent / "Eggshell/PublicationService.lean")
  service := service.replace "loaded.withOwner owner deadline (fun ready => pure ready.palette.bytes)"
    "loaded.withMetadata owner deadline (fun ready => pure ready.bytes)"
    |>.replace "loaded.withOwner owner deadline (fun ready => pure ready.palette.json)"
    "loaded.withMetadata owner deadline (fun ready => pure ready.json)"
  let old ← between service "def sourcePlan (server" "def sourceRecords"
  let replacement ← IO.FS.readFile (project / "tools/research/SourceViewService.lean.inc")
  service ← once service old (replacement ++ "\n")
  save (core / "Eggshell/PublicationService.lean") service
  let baseline := root / "published-plan-runtime-build"
  let settings := Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "prepared-view-runtime-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (baseline / "object-mapping.json").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
    ("baselineMain",toJson (baseline / "Main.o").toString),
    ("parents",toJson #[baseline.toString]),("force",toJson (#[] : Array String)),("mainModule",toJson "Main")]
  let settingsPath := root / "prepared-view-runtime.settings.json"
  IO.FS.writeFile settingsPath settings.compress
  let mut attempt := 1
  while ← (records / s!"runtime-build-{attempt}.guard.json").pathExists do attempt := attempt+1
  IO.FS.writeFile (root / "prepared-view-runtime-build.guard.settings.json") (Json.mkObj [
    ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (records / s!"runtime-build-{attempt}.guard.json").toString),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,settingsPath.toString])]).compress
  IO.println "Connected publication-owned metadata, body-free selection and shared readers in the isolated runtime"
