import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

/-- Build read-only diagnostics against the frozen runtime's existing objects. -/
def main (args : List String) : IO Unit := do
  let [moduleName,label] := args | throw (IO.userError "MODULE LABEL")
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let source ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "drain-build.settings.json")))
  let target := root / (label ++ "-build")
  let settings := source.setObjVal! "output" (toJson target.toString)
    |>.setObjVal! "mainModule" (toJson moduleName)
  IO.FS.writeFile (root / (label ++ "-build.settings.json")) settings.pretty
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  IO.FS.writeFile (root / (label ++ "-build.guard-settings.json")) (Json.mkObj [
    ("record",toJson (root / (label ++ "-build.guard.json")).toString),("cwd",toJson project),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),
    ("command",toJson #["/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","--run",
      project ++ "/tools/research/StudyBuildMain.lean",(root / (label ++ "-build.settings.json")).toString])]).pretty
