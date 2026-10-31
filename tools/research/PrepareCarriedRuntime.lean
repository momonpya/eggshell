import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  ensure ((source.splitOn before).length == 2) ("carried runtime anchor changed: " ++ toString (before.take 100))
  return source.replace before after
private def save (path : System.FilePath) (source : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path source

def main (args : List String) : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/carried-value"
  let core := root / "carried-value-core"
  let parent := root / "project-metadata-runtime-build"
  let runtime := root / "carried-value-runtime-build"
  let mode := args.headD ""
  if mode == "runtime" then
    ensure (!(← core.pathExists) && !(← (records / "integration-plan.json").pathExists)) "preserve carried runtime"
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "project-metadata-core").toString,core.toString]}
    ensure (copied.exitCode == 0) "cannot isolate carried runtime"
    save (core / "tools/research/CarriedSelectionValue.lean") (← IO.FS.readFile (project / "tools/research/CarriedSelectionValue.lean"))
    let winner := core / "tools/VerifiedWinnerCoverage.lean"
    save winner (← once (← IO.FS.readFile winner) "public import tools.WinnerUpdates\n"
      "public import tools.WinnerUpdates\npublic import tools.research.CarriedSelectionValue\n")
    let wire := core / "Eggshell/PublicationWire.lean"
    save wire (← once (← IO.FS.readFile wire) "  (include_str \"Handoff.lean\").toUTF8,"
      ("  (include_str \"Handoff.lean\").toUTF8,\n" ++
       "  (include_str \"../tools/VerifiedWinnerCoverage.lean\").toUTF8,\n" ++
       "  (include_str \"../tools/research/CarriedSelectionValue.lean\").toUTF8,"))
    IO.FS.writeFile (records / "integration-plan.json") (Json.mkObj [
      ("parentRuntimeSha256",toJson "ae06a4a112a4aa7e2d8b7e0f925a1d652368081891936cac33ae575306c1eabf"),
      ("change",toJson "Recompile VerifiedWinnerCoverage with the proved bestSingleton substitution. Bind both new source dependencies to the service generation. Published source/index metadata is unchanged."),
      ("preparation",toJson "Clone the already prepared diagnostic R40 DB. Verify original files and source-metadata readiness, then run warm; do not regenerate a seed or alter source/index producer stamps."),
      ("connection",toJson "One new candidate topic-1 fresh-session hook, with current worker-role parsing. Audit byte equality and frozen 3-item denominator before any model. Do not rerun the completed parent hook."),
      ("sampling",toJson "One 18-second 2-ms sample each of the owned publisher and search worker; diagnostic failure must be marked without discarding the completed hook."),
      ("latencyComparisonMeasured",toJson false),("answeringModelCalls",toJson (0 : Nat)),
      ("newSeeds",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  else ensure (mode == "hooks") "runtime/hooks required"
  let output := if mode == "runtime" then runtime else root / "carried-value-hook-candidate-build"
  let mainModule := if mode == "runtime" then "Main" else "tools.research.CarriedValueHook"
  let baseline := if mode == "runtime" then parent else runtime
  if mode == "hooks" then
    let target := core / "tools/research/CarriedValueHook.lean"
    ensure (!(← target.pathExists)) "preserve carried connection helper"
    let mut source := (← IO.FS.readFile (project / "tools/research/SourceViewHook.lean")).replace "prepared-view" "carried-value"
    source ← once source "import tools.research.StudyCommand\n"
      "import tools.research.StudyCommand\nimport tools.research.MetadataNativeProfile\n"
    source ← once source "def main (args : List String) : IO Unit := do\n"
      "def main (args : List String) : IO Unit := do\n  MetadataNativeProfile.parserChecks\n"
    let first := "    let manifest := study / \"r0/stage1/history/history.json\"\n"
    let last := "    install arm\n"
    let [_,rest] := source.splitOn first | throw (IO.userError "missing prepared DB copy anchor")
    let [old,_] := rest.splitOn last | throw (IO.userError "missing prepared DB copy end")
    source ← once source (first ++ old)
      ("    IO.FS.createDirAll root\n" ++
       "    let preparedDatabase := study / \"shared-snapshot/metadata-profile-trial/candidate/work.egg\"\n" ++
       "    let copied ← IO.Process.output {cmd := \"/bin/cp\",args := #[\"-cR\",preparedDatabase.toString,database.toString]}\n" ++
       "    check (copied.exitCode == 0 && (← StudyRuntime.files database) == originalFiles) \"prepared clone changed raw source\"\n" ++
       "    let source ← DB.PageMap.pin database\n" ++
       "    check ((← CanonicalSource.Cache.openShared? source).isSome) \"unchanged original metadata was not ready\"\n" ++
       "    IO.FS.writeFile (saved / \"preparation-reuse.json\") (Json.mkObj [(\"sourceFiles\",toJson originalFiles),\n" ++
       "      (\"preparedDatabase\",toJson preparedDatabase.toString),(\"metadataReady\",toJson true),\n" ++
       "      (\"newSeed\",toJson false)]).pretty\n")
    source ← once source "        let response ← StudyCommand.run binary.toString #[\"codex-hook\"] env workspace\n"
      ("        let profiling ← if event == \"UserPromptSubmit\" then\n" ++
       "          MetadataNativeProfile.start (StudyRuntime.pid publisher) (StudyRuntime.pid daemon) binary.toString (destination / \"native-profile\")\n" ++
       "          else pure #[]\n" ++
       "        let response ← StudyCommand.run binary.toString #[\"codex-hook\"] env workspace\n")
    source ← once source "        check (response.exitCode == 0) \"actual matched hook failed\"\n"
      "        let profilingComplete ← MetadataNativeProfile.finish profiling\n        check (response.exitCode == 0) \"actual matched hook failed\"\n"
    source ← once source "            (\"availableDelivery\",audit.getObjValD \"availableDelivery\"),(\"answeringModelCalls\",toJson (0 : Nat)),"
      "            (\"profilingComplete\",toJson profilingComplete),(\"availableDelivery\",audit.getObjValD \"availableDelivery\"),(\"answeringModelCalls\",toJson (0 : Nat)),"
    IO.FS.writeFile target source
    save (core / "tools/research/MetadataNativeProfile.lean") (← IO.FS.readFile (project / "tools/research/MetadataNativeProfile.lean"))
  let settingsPath := root / ("carried-value-" ++ mode ++ ".settings.json")
  IO.FS.writeFile settingsPath (Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson output.toString),("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (baseline / "object-mapping.json").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
    ("baselineMain",toJson (baseline / "Main.o").toString),
    ("parents",toJson #[baseline.toString]),("force",toJson (#[] : Array String)),("mainModule",toJson mainModule)]).compress
  let buildLabel := if mode == "runtime" then "runtime-build" else "hook-build"
  let mut jobs := [(buildLabel,#["/usr/bin/env","LEAN_NUM_THREADS=1",
    "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
    (project / "tools/research/StudyBuildMain.lean").toString,settingsPath.toString])]
  if mode == "hooks" then
    for action in ["describe","prepare","run"] do
      let command := #["/usr/bin/env","LEAN_NUM_THREADS=1",(output / "StudyMain").toString,action,"candidate"] ++
        (if action == "run" then #["0","1"] else #[])
      jobs := jobs ++ [(if action == "run" then "hook-run" else action,command)]
  for (label,command) in jobs do
    IO.FS.writeFile (root / ("carried-value-" ++ label ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / (label ++ ".guard.json")).toString),("command",toJson command)]).compress
