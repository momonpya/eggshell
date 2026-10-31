import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("publication metadata anchor changed: " ++ toString (before.take 90))
  return source.replace before after
private def save (path : System.FilePath) (source : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path source

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let parent := root / "service-plan-core"
  let core := root / "published-plan-core"
  check (!(← core.pathExists)) "preserve publication metadata candidate"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",parent.toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate publication metadata candidate"
  let target := core / "tools/research/PublishedPlanMetadata.lean"
  if ← target.pathExists then IO.FS.removeFile target
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(project / "tools/research/PublishedPlanMetadata.lean").toString,target.toString]}
  check (linked.exitCode == 0) "cannot bind publication metadata source"
  let mut cache ← IO.FS.readFile (parent / "Eggshell/CanonicalSourceCache.lean")
  cache ← once cache "public import Eggshell.CanonicalSourceRecipe\n"
    "public import Eggshell.CanonicalSourceRecipe\npublic import tools.research.PublishedPlanMetadata\n"
  cache ← once cache "  (include_str \"CanonicalSourceDelivery.lean\").toUTF8,"
    "  (include_str \"CanonicalSourceDelivery.lean\").toUTF8,\n  PublishedPlanMetadata.implementation.toUTF8,"
  cache ← once cache "        Recipe.write writer owner stored\n"
    "        Recipe.write writer owner stored\n        PublishedPlanMetadata.publish writer owner stored\n"
  save (core / "Eggshell/CanonicalSourceCache.lean") cache
  let mut arena ← IO.FS.readFile (parent / "tools/research/PreparedOwnerArena.lean")
  arena ← once arena "public import tools.research.PreparedFileUnits\n"
    "public import tools.research.PreparedFileUnits\npublic import tools.research.PublishedPlanMetadata\n"
  arena ← once arena "  units : PreparedFileUnits.Ready owner stored.rows layout\n"
    "  units : PreparedFileUnits.Ready owner stored.rows layout\n  published : PublishedPlanMetadata.Ready owner stored layout\n"
  arena ← once arena "PreparedFileUnits.prepare owner stored.rows layout⟩"
    "PreparedFileUnits.prepare owner stored.rows layout,PublishedPlanMetadata.prepare owner stored layout⟩"
  arena ← once arena "theorem Ready.no_foreign_origin"
    ("/-- Persisted metadata is required on the service path, never repaired by a query. -/\n" ++
     "def preparePublished (database owner : String) (stored : CanonicalSource.Recipe.Stored)\n" ++
     "    (metadata : PublishedPlanMetadata.Stored) : Except String Ready := do\n" ++
     "  let ready ← prepare database owner stored\n" ++
     "  let published ← PublishedPlanMetadata.check ready.owner ready.stored ready.layout metadata\n" ++
     "  return {ready with published}\n\ntheorem Ready.no_foreign_origin")
  save (core / "tools/research/PreparedOwnerArena.lean") arena
  let mut prepared ← IO.FS.readFile (parent / "Eggshell/CanonicalSourcePrepared.lean")
  prepared ← once prepared "    let stored := (← Recipe.read? loaded.recipes owner).getD ⟨#[],[]⟩\n    IO.ofExcept (PreparedOwnerArena.prepare loaded.metadata.source.identity owner stored)) use"
    ("    let found ← Recipe.read? loaded.recipes owner\n" ++
     "    match found with\n" ++
     "    | none => IO.ofExcept (PreparedOwnerArena.prepare loaded.metadata.source.identity owner ⟨#[],[]⟩)\n" ++
     "    | some stored =>\n" ++
     "      let metadata ← PublishedPlanMetadata.read loaded.recipes owner\n" ++
     "      IO.ofExcept (PreparedOwnerArena.preparePublished loaded.metadata.source.identity owner stored metadata)) use")
  save (core / "Eggshell/CanonicalSourcePrepared.lean") prepared
  let mut handoff ← IO.FS.readFile (parent / "Eggshell/Handoff.lean")
  handoff ← once handoff "public import tools.research.PreparedFileUnits\n"
    "public import tools.research.PreparedFileUnits\npublic import tools.research.PublishedPlanMetadata\n"
  handoff ← once handoff
    ("def selectPrepared (query : ServiceQuery) (units : Array ServiceUnit)\n" ++
     "    (pieces : List CuePiece) (originalRows : Array Synapses.CanonicalSource.StoredRow) : Option ServiceChoice := do\n" ++
     "  let source := (Eggshell.Research.PreparedSourceCosts.prepare originalRows query.frameCosts).data")
    ("def selectPrepared (query : ServiceQuery) (units : Array ServiceUnit)\n" ++
     "    (pieces : List CuePiece) (source : Eggshell.Research.PreparedSourceCosts.Data) : Option ServiceChoice := do")
  save (core / "Eggshell/Handoff.lean") handoff
  let mut service ← IO.FS.readFile (parent / "Eggshell/PublicationService.lean")
  service ← once service "    let mut originalRows := #[]\n"
    "    let mut originalRows := #[]\n    let mut publishedCosts : Std.HashMap CanonicalSource.Key (Nat × Nat) := {}\n"
  service ← once service "          let (incoming,prepared) ← entry.loaded.withOwner file.owner deadline fun ready => do"
    "          let (incoming,prepared,metadata) ← entry.loaded.withOwner file.owner deadline fun ready => do"
  service ← once service "SharedRangeAdapter.fileUnits file ready.stored ready.layout (same ▸ ready.units))"
    "SharedRangeAdapter.fileUnits file ready.stored ready.layout (same ▸ ready.units),ready.published.metadata.costs)"
  service ← once service "          if incoming.rows.isEmpty then continue\n"
    ("          unless metadata.size == incoming.rows.size do throw (IO.userError \"published cost ordinals changed\")\n" ++
     "          for (row,cost) in incoming.rows.zip metadata do\n" ++
     "            if let some previous := publishedCosts[row.key]? then\n" ++
     "              unless previous == cost do throw (IO.userError \"published row cost conflicts across read views\")\n" ++
     "            publishedCosts := publishedCosts.insert row.key cost\n" ++
     "          if incoming.rows.isEmpty then continue\n")
  service ← once service "    let some choice := SharedRangeAdapter.selectPrepared query units pieces originals |"
    ("    let source ← IO.ofExcept (PublishedPlanMetadata.sourceDomain originals publishedCosts query.frameCosts)\n" ++
     "    let some choice := SharedRangeAdapter.selectPrepared query units pieces source |")
  save (core / "Eggshell/PublicationService.lean") service
  let baseline := root / "service-plan-runtime-build"
  let records := project / "docs/candidates/published-plan"
  IO.FS.createDirAll records
  let settings := Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "published-plan-runtime-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (baseline / "object-mapping.json").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
    ("baselineMain",toJson (baseline / "Main.o").toString),
    ("parents",toJson #[baseline.toString]),("force",toJson (#[] : Array String)),("mainModule",toJson "Main")]
  let path := root / "published-plan-runtime.settings.json"
  IO.FS.writeFile path settings.compress
  IO.FS.writeFile (root / "published-plan-build.guard.settings.json") (Json.mkObj [
    ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (records / "build.guard.json").toString),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,path.toString])]).compress
  IO.println "Isolated publication metadata and its actual service consumer; original implementation unchanged"
