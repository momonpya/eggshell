import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let build ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "controller-build/build.json")))
  let modules ← IO.ofExcept (build.getObjValAs? (Array Json) "modules")
  let objects ← modules.toList.mapM fun row => do
    return (← IO.ofExcept (row.getObjValAs? String "object"),toJson (← IO.ofExcept (row.getObjValAs? String "module")))
  IO.FS.writeFile (root / "drain-objects.json") (Json.mkObj objects).pretty
  let core := "/Users/ovm/.codex/experiments/eggshell/bounded-source-replies-20261028/scope-hook-checkout"
  let library := System.FilePath.mk core / ".lake/build/lib/lean"
  IO.FS.removeDir library
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(root / "controller-build/lib").toString,library.toString]}
  unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
  let settings ← IO.ofExcept (build.getObjVal? "settings")
  let mut settings := settings.setObjVal! "output" (toJson (root / "drain-controller-build").toString)
  settings := settings.setObjVal! "baselineResponse" (toJson (root / "controller-build/runtime.rsp").toString)
  settings := settings.setObjVal! "baselineMain" (toJson (root / "controller-build/tools_research_StudyMain.o").toString)
  settings := settings.setObjVal! "baselineCore" (toJson core)
  settings := settings.setObjVal! "objectModules" (toJson (root / "drain-objects.json").toString)
  settings := settings.setObjVal! "mainModule" (toJson "tools.research.DrainStudyHistory")
  IO.FS.writeFile (root / "drain-build.settings.json") settings.pretty
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  IO.FS.writeFile (root / "drain-build.guard-settings.json") (Json.mkObj [
    ("record",toJson (root / "drain-build.guard.json").toString),("cwd",toJson project),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("command",toJson #["/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","--run",
      project ++ "/tools/research/StudyBuildMain.lean",(root / "drain-build.settings.json").toString])]).pretty
