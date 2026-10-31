import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "prepared owner source anchor changed"
  return source.replace before after
private def region (source first last replacement : String) : IO String := do
  let parts := source.splitOn first
  check (parts.length == 2) "prepared owner region start changed"
  let rest := parts[1]!.splitOn last
  check (rest.length == 2) "prepared owner region end changed"
  return parts[0]! ++ replacement ++ last ++ rest[1]!

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let base := root / "query-cache-baseline-core"
  let core := root / "prepared-owner-core"
  check (!(← core.pathExists)) "preserve previous prepared owner fork"
  let mut source ← IO.FS.readFile (base / "Eggshell/CanonicalSourcePrepared.lean")
  source ← once source "public import Eggshell.CanonicalSourceDelivery\n"
    "public import Eggshell.CanonicalSourceDelivery\npublic import tools.research.PreparedOwnerArena\n"
  source ← once source "  originals : Option Index.Reader := none\n"
    "  originals : Option Index.Reader := none\n  owners : PreparedOwnerArena.Cache\n  identity : String\n"
  source ← region source "/-- Publication compiled each owner." "structure Budget (capacity : Nat) where"
    ("/-- The service owns one checked resident value for each immutable original. -/\n" ++
     "def Loaded.withOwner (loaded : Loaded) (owner : String) (deadline : Nat)\n" ++
     "    (use : PreparedOwnerArena.Ready → IO α) : IO α := do\n" ++
     "  unless (← IO.monoMsNow) < deadline do throw (IO.userError \"prepared owner request expired\")\n" ++
     "  let descriptor ← loaded.recipes.get (Recipe.name owner)\n" ++
     "  let bytes ← IO.ofExcept (PreparedOwnerArena.payloadBytes descriptor)\n" ++
     "  loaded.owners.withReady loaded.identity loaded.metadata.source.identity owner bytes deadline (do\n" ++
     "    let stored := (← Recipe.read? loaded.recipes owner).getD ⟨#[],[]⟩\n" ++
     "    IO.ofExcept (PreparedOwnerArena.prepare loaded.metadata.source.identity owner stored)) use\n\n" ++
     "def Loaded.rows (loaded : Loaded) (owners : Array String) (deadline : Nat) : IO (Array (String × Recipe.Stored)) := do\n" ++
     "  let mut result := #[]\n  let mut total := 0\n" ++
     "  for owner in owners do\n" ++
     "    let descriptor ← loaded.recipes.get (Recipe.name owner)\n" ++
     "    total := total+(← IO.ofExcept (PreparedOwnerArena.payloadBytes descriptor))\n" ++
     "    unless total ≤ 16*1024*1024 do throw (IO.userError \"prepared original projection exceeds reply budget\")\n" ++
     "    let stored ← loaded.withOwner owner deadline (fun ready => pure ready.stored)\n" ++
     "    result := result.push (owner,stored)\n  return result\n\n")
  source ← once source
    "def capacity : Nat := 512*1024*1024-ObservedRecordView.geometryCapacity-PageMap.SharedPageCache.capacity"
    ("def capacity : Nat := 64*1024*1024\n\n" ++
     "theorem shared_resident_capacity : capacity+PreparedOwnerArena.capacity+\n" ++
     "    ObservedRecordView.geometryCapacity+PageMap.SharedPageCache.capacity = 512*1024*1024 := by decide")
  source ← once source "  pages : PageMap.PagePool\n" "  pages : PageMap.PagePool\n  owners : PreparedOwnerArena.Cache\n"
  source ← once source
    "def Pool.new : IO Pool := return ⟨← Std.Mutex.new {},← Std.Mutex.new #[],← PageMap.PagePool.new⟩"
    "def Pool.new : IO Pool := return ⟨← Std.Mutex.new {},← Std.Mutex.new #[],← PageMap.PagePool.new,← PreparedOwnerArena.Cache.new⟩"
  source ← once source "            return ⟨metadata,recipes,original⟩"
    "            return ⟨metadata,recipes,original,pool.owners,identity⟩"
  source ← once source "def Pool.close (pool : Pool) : IO Unit := do\n"
    "def Pool.close (pool : Pool) : IO Unit := do\n  pool.owners.close\n"
  source ← once source "  let pages ← pool.pages.stats\n"
    "  let pages ← pool.pages.stats\n  let owners ← pool.owners.stats\n"
  source ← once source "(\"capacity\",toJson capacity),(\"pages\",pages)"
    "(\"capacity\",toJson capacity),(\"pages\",pages),(\"owners\",owners)"
  let wire ← once (← IO.FS.readFile (base / "Eggshell/PublicationWire.lean"))
    "  (include_str \"CanonicalSourcePrepared.lean\").toUTF8,"
    "  (include_str \"../tools/research/PreparedOwnerArena.lean\").toUTF8,\n  (include_str \"CanonicalSourcePrepared.lean\").toUTF8,"
  let copy ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",base.toString,core.toString]}
  check (copy.exitCode == 0) "cannot isolate prepared owner fork"
  IO.FS.writeFile (core / "Eggshell/CanonicalSourcePrepared.lean") source
  IO.FS.writeFile (core / "Eggshell/PublicationWire.lean") wire
  let moduleFile := "tools/research/PreparedOwnerArena.lean"
  IO.FS.createDirAll (core / moduleFile).parent.get!
  IO.FS.writeFile (core / moduleFile) (← IO.FS.readFile (project / moduleFile))
  let settings := Json.mkObj [
    ("project",toJson project.toString),("core",toJson core.toString),("baselineCore",toJson base.toString),
    ("output",toJson (root / "prepared-owner-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (root / "query-cache-baseline-objects.json").toString),
    ("baselineResponse",toJson (root / "query-cache-baseline-build/runtime.rsp").toString),
    ("baselineMain",toJson (root / "query-cache-baseline-build/Main.o").toString),
    ("parents",toJson (#[(root / "query-cache-baseline-build").toString] : Array String)),
    ("force",toJson (#[] : Array String)),("mainModule",toJson "tools.research.PreparedOwnerArenaAudit")]
  IO.FS.writeFile (root / "prepared-owner-build.settings.json") settings.pretty
  IO.println "Prepared isolated shared resident-owner path; stored layout and selector unchanged"
