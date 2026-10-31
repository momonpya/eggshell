import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("profile anchor changed: " ++ toString (before.take 100))
  return source.replace before after

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "project-metadata-core"
  let runtime := root / "project-metadata-runtime-build"
  let records := project / "docs/candidates/metadata-profile"
  IO.FS.createDirAll records
  let target := core / "tools/research/MetadataProfileHook.lean"
  check (!(← target.pathExists) && !(← (records / "plan.json").pathExists)) "preserve the one current-runtime profile"
  let mut source := (← IO.FS.readFile (project / "tools/research/SourceViewHook.lean")).replace "prepared-view" "metadata-profile"
  source ← once source "import tools.research.StudyCommand\n"
    "import tools.research.StudyCommand\nimport tools.research.MetadataNativeProfile\n"
  source ← once source "else \"metadata-profile-runtime-build\"" "else \"project-metadata-runtime-build\""
  source ← once source "def main (args : List String) : IO Unit := do\n"
    "def main (args : List String) : IO Unit := do\n  MetadataNativeProfile.parserChecks\n"
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
  let profileTarget := core / "tools/research/MetadataNativeProfile.lean"
  check (!(← profileTarget.pathExists)) "preserve native sampling module"
  IO.FS.writeFile profileTarget (← IO.FS.readFile (project / "tools/research/MetadataNativeProfile.lean"))
  let settingsPath := root / "metadata-profile-hook.settings.json"
  IO.FS.writeFile settingsPath (Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "metadata-profile-hook-candidate-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (runtime / "object-mapping.json").toString),
    ("baselineResponse",toJson (runtime / "runtime.rsp").toString),
    ("baselineMain",toJson (runtime / "Main.o").toString),
    ("parents",toJson #[runtime.toString]),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.MetadataProfileHook")]).compress
  let helper := root / "metadata-profile-hook-candidate-build/StudyMain"
  for (name,command) in [
    ("build",#["/usr/bin/env","LEAN_NUM_THREADS=1",
      "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      (project / "tools/research/StudyBuildMain.lean").toString,settingsPath.toString]),
    ("describe",#["/usr/bin/env","LEAN_NUM_THREADS=1",helper.toString,"describe","candidate"]),
    ("prepare",#["/usr/bin/env","LEAN_NUM_THREADS=1",helper.toString,"prepare","candidate"]),
    ("run",#["/usr/bin/env","LEAN_NUM_THREADS=1",helper.toString,"run","candidate","0","1"])] do
    IO.FS.writeFile (root / ("metadata-profile-" ++ name ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / (name ++ ".guard.json")).toString),("command",toJson command)]).compress
  IO.FS.writeFile (records / "plan.json") (Json.mkObj [
    ("runtimeSha256",toJson "ae06a4a112a4aa7e2d8b7e0f925a1d652368081891936cac33ae575306c1eabf"),
    ("runtimeChanged",toJson false),("source",toJson "frozen R40 plus sealed supplement"),
    ("topic",toJson (1 : Nat)),("actualHookCount",toJson (1 : Nat)),
    ("purpose",toJson "Locate current CPU work before repeating an abandoned publication-index optimization"),
    ("rejectedPriorRetry",toJson "RecordIncidence: prior full ordered comparison was about 7.32 times slower; do not tune or reconnect it"),
    ("observation",toJson "One 18-second 2-ms OS stack sample each of the owned publisher and owned search worker. Unchanged runtime; not direct function wall times, p99 or a latency comparison."),
    ("scope",toJson "diagnostic source fork; no new seed or answering-model call"),
    ("adopted",toJson false)]).pretty
  IO.println "Prepared one unchanged-runtime native CPU profile; no record-incidence retry"
