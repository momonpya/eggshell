import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  ensure ((source.splitOn before).length == 2) ("source-view harness anchor changed: " ++ toString (before.take 90))
  return source.replace before after

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "prepared-view-core"
  let runtime := root / "prepared-view-runtime-build"
  let destination := project / "tools/research/SourceViewHook.lean"
  ensure (!(← destination.pathExists)) "preserve generated source-view hook controller"
  let mut source ← IO.FS.readFile (project / "tools/research/PublishedPlanHook.lean")
  let [leading,tail] := source.splitOn "private def servicePlanSuite" | throw (IO.userError "missing old suite")
  let [_,main] := tail.splitOn "  let mode :: arm :: rest := args" | throw (IO.userError "missing hook entry")
  source := leading ++ "def main (args : List String) : IO Unit := do\n  let mode :: arm :: rest := args" ++ main
  source := source.replace "published-plan" "prepared-view"
    |>.replace "service-plan-runtime-build" "published-plan-runtime-build"
  source ← once source "check ([\"baseline\",\"candidate\"].contains arm)" "check (arm == \"candidate\")"
  source ← once source
    "  let frozenEntries ← IO.ofExcept ((← read (project / \"docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json\")).getArr?)\n" ""
  let before := "  let some frozen := frozenEntries[topic-1]? | throw (IO.userError \"missing frozen first question\")\n" ++
    "  check (frozen.getObjValD \"topic\" == toJson topic &&\n" ++
    "    (frozen.getObjValD \"specification\").getObjValD \"files\" == toJson originalFiles) \"original source changed\"\n"
  source ← once source before ""
  source ← once source ",(\"frozen\",frozen)" ""
  source ← once source "  check ((frozen.getObjValD \"specification\").getObjValD \"prompt\" == toJson prompt) \"fixed question changed\"\n" ""
  source ← once source "          let sha := Sha256.hex body.toUTF8\n"
    ("          let sha := Sha256.hex body.toUTF8\n" ++
     "          IO.FS.writeFile (destination / \"before-gold.json\") (Json.mkObj [\n" ++
     "            (\"bodySha256\",toJson sha),(\"sourceFiles\",toJson originalFiles),\n" ++
     "            (\"runtime\",toJson expected),(\"questionSha256\",toJson (Sha256.hex prompt.toUTF8)),\n" ++
     "            (\"elapsedMs\",toJson response.elapsedMs),(\"goldRead\",toJson false)]).pretty\n" ++
     "          let frozenEntries ← IO.ofExcept ((← read (project / \"docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json\")).getArr?)\n" ++
     "          let some frozen := frozenEntries[topic-1]? | throw (IO.userError \"missing frozen topic\")\n" ++
     "          check (frozen.getObjValD \"topic\" == toJson topic &&\n" ++
     "            (frozen.getObjValD \"specification\").getObjValD \"files\" == toJson originalFiles &&\n" ++
     "            (frozen.getObjValD \"specification\").getObjValD \"prompt\" == toJson prompt) \"frozen question or source changed\"\n")
  IO.FS.writeFile destination source
  let target := core / "tools/research/SourceViewHook.lean"
  ensure (!(← target.pathExists)) "preserve isolated source-view hook producer"
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",destination.toString,target.toString]}
  ensure (linked.exitCode == 0) "cannot bind source-view hook controller"
  let settings := Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),
    ("output",toJson (root / "prepared-view-hook-candidate-build").toString),
    ("toolchain",toJson "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"),
    ("objectModules",toJson (runtime / "object-mapping.json").toString),
    ("baselineResponse",toJson (runtime / "runtime.rsp").toString),
    ("baselineMain",toJson (runtime / "Main.o").toString),
    ("parents",toJson #[runtime.toString]),("force",toJson (#[] : Array String)),
    ("mainModule",toJson "tools.research.SourceViewHook")]
  let settingsPath := root / "prepared-view-hook.settings.json"
  IO.FS.writeFile settingsPath settings.compress
  let records := project / "docs/candidates/prepared-view"
  let guard (name : String) (command : Array String) : IO Unit :=
    IO.FS.writeFile (root / ("prepared-view-" ++ name ++ ".guard.settings.json")) (Json.mkObj [
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("record",toJson (records / (name ++ ".guard.json")).toString),("command",toJson command)]).compress
  guard "hook-build" #["/usr/bin/env","LEAN_NUM_THREADS=1",
    "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
    (project / "tools/research/StudyBuildMain.lean").toString,settingsPath.toString]
  let helper := root / "prepared-view-hook-candidate-build/StudyMain"
  guard "hook-describe" #["/usr/bin/env","LEAN_NUM_THREADS=1",helper.toString,"describe","candidate"]
  guard "hook-prepare" #["/usr/bin/env","LEAN_NUM_THREADS=1",helper.toString,"prepare","candidate"]
  for topic in [1,2,3] do
    guard s!"hook-topic-{topic}" #["/usr/bin/env","LEAN_NUM_THREADS=1",helper.toString,"run","candidate","0",toString topic]
  IO.println "Prepared one diagnostic per topic with body frozen before reading labels; no model or adoption claim"
