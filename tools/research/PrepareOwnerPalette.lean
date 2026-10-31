import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  ensure ((source.splitOn before).length == 2) ("owner palette anchor changed: " ++ toString (before.take 80))
  return source.replace before after

private def alignSources (project core : System.FilePath) : IO Unit := do
  for entry in ← (project / "tools/research").readDir do
    if !entry.fileName.endsWith ".lean" || entry.fileName == "PreparedOwnerArena.lean" then continue
    let target := core / "tools/research" / entry.fileName
    if ← target.pathExists then IO.FS.removeFile target
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",entry.path.toString,target.toString]}
    ensure (linked.exitCode == 0) "cannot bind isolated research source"

def main (args : List String) : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let parent := root / "receipt-reconciliation-core"
  let core := root / "owner-palette-core"
  if args == ["sources"] then
    ensure (← core.pathExists) "isolated palette package is absent"
    alignSources project core
    let settingsFile := root / "owner-palette.settings.json"
    let settings ← IO.FS.readFile settingsFile >>= fun text => IO.ofExcept (Json.parse text)
    IO.FS.writeFile settingsFile (settings.setObjVal! "project" (toJson core.toString)).compress
    IO.println "Bound candidate research modules to the isolated package root"
    return
  let refresh := args == ["refresh"]
  ensure (refresh || !(← core.pathExists)) "preserve previous owner palette candidate"
  let records := project / "docs/candidates/owner-palette"
  IO.FS.createDirAll records
  let mut arena ← IO.FS.readFile (parent / "tools/research/PreparedOwnerArena.lean")
  arena ← once arena "public import Eggshell.CanonicalSourceRecipe\n"
    "public import Eggshell.CanonicalSourceRecipe\npublic import tools.research.OwnerPalette\n"
  arena ← once arena "    origin.binding.database == database && origin.binding.owner == owner)) = true\n"
    "    origin.binding.database == database && origin.binding.owner == owner)) = true\n  palette : OwnerPalette.Ready stored layout\n"
  arena ← once arena "⟨database,owner,stored,layout,checked,⟨registry,loaded⟩,inScope⟩"
    "⟨database,owner,stored,layout,checked,⟨registry,loaded⟩,inScope,OwnerPalette.prepare stored layout⟩"
  let mut service ← IO.FS.readFile (parent / "Eggshell/PublicationService.lean")
  service ← once service "public import Eggshell.PublicationWire\n"
    "public import Eggshell.PublicationWire\npublic import tools.research.OwnerPaletteLease\n"
  service ← once service "  deferredReplies : Std.Mutex (Array DeferredReply)\n"
    "  deferredReplies : Std.Mutex (Array DeferredReply)\n  palettes : OwnerPaletteLease.Pool\n"
  service ← once service "/-- The identical authenticated read scope serves generic original output."
    ((← IO.FS.readFile (project / "tools/research/OwnerPaletteService.lean.inc")) ++ "\n" ++
      "/-- The identical authenticated read scope serves generic original output.")
  service ← once service "[\"source-rows\",\"source-records\",\"source-bindings\"].contains kind"
    "[\"source-rows\",\"source-records\",\"source-bindings\",\"source-palette\",\"source-fetch\"].contains kind"
  service ← once service "[\"prepare-source\",\"refresh-source\",\"source-rows\",\"source-records\",\"source-bindings\"].contains kind"
    "[\"prepare-source\",\"refresh-source\",\"source-rows\",\"source-records\",\"source-bindings\",\"source-palette\",\"source-fetch\",\"source-release\"].contains kind"
  service ← once service "      else if kind == \"source-rows\" then sourceRows server secret payload deadline\n"
    ("      else if kind == \"source-rows\" then sourceRows server secret payload deadline\n" ++
     "      else if kind == \"source-palette\" then sourcePalette server secret payload deadline\n" ++
     "      else if kind == \"source-fetch\" then sourceFetch server secret payload deadline\n" ++
     "      else if kind == \"source-release\" then releasePalette server secret payload\n")
  service ← once service "    reserveReply server replyCharge deadline\n    reservedReply.set replyCharge\n"
    ("    if kind != \"source-palette\" then\n" ++
     "      reserveReply server replyCharge deadline\n      reservedReply.set replyCharge\n")
  service ← once service "    pure (.ok value.compress : Except String String)\n"
    ("    if kind == \"source-palette\" then\n" ++
     "      reserveReply server replyCharge deadline\n      reservedReply.set replyCharge\n" ++
     "    pure (.ok value.compress : Except String String)\n")
  service ← once service "    (\"preparedSources\",← server.prepared.stats),\n"
    "    (\"preparedSources\",← server.prepared.stats),(\"paletteQueries\",← server.palettes.stats),\n"
  service ← once service "    ← Std.Mutex.new 0,← Std.Mutex.new #[]⟩\n"
    "    ← Std.Mutex.new 0,← Std.Mutex.new #[],← OwnerPaletteLease.Pool.new⟩\n"
  service ← once service "    server.prepared.close\n" "    server.palettes.close\n    server.prepared.close\n"
  let client ← once (← IO.FS.readFile (parent / "Eggshell/PublicationClient.lean"))
    "def endpoint? : IO (Option Daemon.Endpoint) := do"
    ((← IO.FS.readFile (project / "tools/research/OwnerPaletteClient.lean.inc")) ++ "\n" ++
      "def endpoint? : IO (Option Daemon.Endpoint) := do")
  let wire ← once (← IO.FS.readFile (parent / "Eggshell/PublicationWire.lean"))
    "  (include_str \"PublicationWire.lean\").toUTF8,"
    ("  (include_str \"../tools/research/OwnerPalette.lean\").toUTF8,\n" ++
     "  (include_str \"../tools/research/SourceProjectionDictionary.lean\").toUTF8,\n" ++
     "  (include_str \"../tools/research/OwnerPaletteLease.lean\").toUTF8,\n  (include_str \"PublicationWire.lean\").toUTF8,")
  if !refresh then
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",parent.toString,core.toString]}
    ensure (copied.exitCode == 0) "cannot isolate original palette source"
  alignSources project core
  IO.FS.writeFile (core / "tools/research/OwnerPalette.lean") (← IO.FS.readFile (project / "tools/research/OwnerPalette.lean"))
  IO.FS.writeFile (core / "tools/research/PreparedOwnerArena.lean") arena
  for (name,source) in [("PublicationService",service),("PublicationClient",client),("PublicationWire",wire)] do
    IO.FS.writeFile (core / "Eggshell" / (name ++ ".lean")) source
  let baseline := root / "receipt-reconciliation-runtime-build"
  let settings := Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "owner-palette-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (baseline / "object-mapping.json").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
    ("baselineMain",toJson (baseline / "Main.o").toString),
    ("parents",toJson #[baseline.toString]),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.OwnerPaletteAudit")]
  let settingsFile := root / "owner-palette.settings.json"
  IO.FS.writeFile settingsFile settings.compress
  IO.FS.writeFile (root / "owner-palette-build.guard.settings.json") (Json.mkObj [
    ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (records / "build.guard.json").toString),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,settingsFile.toString])]).compress
  IO.println "Prepared original metadata/fetch split in the existing bounded owner arena"
