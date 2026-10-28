import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

/-- Build new entry points from the verified storage candidate without
overwriting the frozen product or reusing its stale interfaces. -/
def main (args : List String) : IO Unit := do
  let (mode,attempt) ← match args with
    | [mode] => pure (mode,"")
    | [mode,attempt] => pure (mode,"-" ++ attempt)
    | _ => throw (IO.userError "product | controller | preparation | service | journal [ATTEMPT]")
  unless attempt.toList.all (fun c => c.isAlphanum || c == '-') do throw (IO.userError "simple attempt label required")
  let entry ← match mode with
    | "product" => pure "Main"
    | "controller" => pure "tools.research.StudyMain"
    | "preparation" => pure "tools.research.SourcePreparationAudit"
    | "service" => pure "tools.research.StorageReplay"
    | "journal" => pure "tools.research.JournalReadDiagnosis"
    | "fixture" => pure "tools.research.StudyTransportFixture"
    | "events" => pure "tools.research.SeedJournalAudit"
    | "delivery" => pure "tools.research.SeedDeliveryReplay"
    | _ => throw (IO.userError "known storage integration mode required")
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let baseline := base / "storage-build"
  let built ← IO.ofExcept (Json.parse (← IO.FS.readFile (baseline / "build.json")))
  let settings := built.getObjValD "settings"
  let library := base / "checkout/.lake/build/lib/lean"
  unless (← library.symlinkMetadata).type == .symlink do throw (IO.userError "expected candidate library link")
  IO.FS.removeFile library
  let link ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(baseline / "lib").toString,library.toString]}
  unless link.exitCode == 0 do throw (IO.userError link.stderr)
  let mut objects ← IO.ofExcept (Json.parse (← IO.FS.readFile (base / "objects.json")))
  for row in ← IO.ofExcept ((built.getObjValD "modules").getArr?) do
    objects := objects.setObjVal! (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
  let label := "storage-" ++ mode
  let objectPath := base / (label ++ "-objects.json")
  IO.FS.writeFile objectPath objects.pretty
  let plan := settings.setObjVal! "output" (toJson (base / (label ++ "-build")).toString)
    |>.setObjVal! "mainModule" (toJson entry)
    |>.setObjVal! "objectModules" (toJson objectPath.toString)
    |>.setObjVal! "baselineResponse" (toJson (baseline / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (baseline / "tools_research_StorageReplay.o").toString)
    |>.setObjVal! "force" (toJson #[entry])
  let planPath := base / (label ++ "-plan.json")
  IO.FS.writeFile planPath plan.pretty
  let command := #["/usr/bin/env","LEAN_NUM_THREADS=1",
    "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-j1","-M1536","--run",
    project ++ "/tools/research/StudyBuildMain.lean",planPath.toString]
  IO.FS.writeFile (base / (label ++ attempt ++ "-build.settings.json")) (Json.mkObj [
    ("command",toJson command),("cwd",toJson project),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (base / (label ++ attempt ++ "-build.guard.json")).toString)]).pretty
