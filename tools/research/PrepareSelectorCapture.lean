import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main (args : List String) : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "selector-input-20261027"
  let parent := base / "range-postings-20261027"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  if args == ["fork"] then
    unless !(← root.pathExists) do throw (IO.userError "preserve current selector capture")
    IO.FS.createDir root
    let result ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(parent / "checkout").toString,(root / "checkout").toString]}
    unless result.exitCode == 0 do throw (IO.userError result.stderr)
    let library := root / "checkout/.lake/build/lib/lean"
    IO.FS.removeFile library
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(parent / "product-build/lib").toString,library.toString]}
    unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
    return
  let [mode,label] := args | throw (IO.userError "fork | MODE LABEL")
  unless ["product","controller","replay","changed","capture","analyze","compare","budget"].contains mode && !label.isEmpty &&
      label.toList.all (fun c => c.isAlphanum || c == '-') do throw (IO.userError "known mode/simple label required")
  let command ← if mode == "capture" then
    pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ (root / label / "data").toString,
      (root / "controller-build/StudyMain").toString,root.toString,(root / label).toString,
      (base / "packet-delivery-ledger-20261027/one-prepared-hook").toString,"selector-input"]
  else if mode == "analyze" then
    pure #[(root / "replay-build/StudyMain").toString,(root / "selector-input.json").toString,(root / label).toString]
  else if mode == "compare" then
    pure #[(root / "changed-build/StudyMain").toString,(root / "selector-input.json").toString,(root / label).toString]
  else if mode == "budget" then
    pure #["/usr/bin/env","LEAN_PATH=" ++ (root / "product-build/lib").toString,"LEAN_NUM_THREADS=1",
      toolchain ++ "/bin/lean","--root=" ++ (root / "checkout").toString,"-j1","-M1024",
      (root / "checkout/tools/SelectionBudget.lean").toString]
  else do
    let origin := if mode == "product" then parent else root
    let baseline := origin / "product-build"
    let library := root / "checkout/.lake/build/lib/lean"
    unless (← library.symlinkMetadata).type == .symlink do throw (IO.userError "expected candidate library link")
    IO.FS.removeFile library
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(baseline / "lib").toString,library.toString]}
    unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
    let build ← IO.ofExcept (Json.parse (← IO.FS.readFile (baseline / "build.json")))
    let mut objects ← IO.ofExcept (Json.parse (← IO.FS.readFile (origin / "objects.json")) >>= Json.getObj?)
    for row in ← IO.ofExcept ((build.getObjValD "modules").getArr?) do
      objects := objects.insert (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
    IO.FS.writeFile (root / "objects.json") (Json.obj objects).pretty
    let plan := (build.getObjValD "settings")
      |>.setObjVal! "core" (toJson (root / "checkout").toString)
      |>.setObjVal! "output" (toJson (root / (mode ++ "-build")).toString)
      |>.setObjVal! "mainModule" (toJson (if mode == "product" then "Main" else
        if mode == "controller" then "tools.research.OnePreparedHook" else
          if mode == "changed" then "tools.research.ChangedWinnerAudit" else "tools.research.SelectorChangeReplay"))
      |>.setObjVal! "baselineCore" (toJson (origin / "checkout").toString)
      |>.setObjVal! "baselineResponse" (toJson (baseline / "runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (baseline / "Main.o").toString)
      |>.setObjVal! "objectModules" (toJson (root / "objects.json").toString)
      |>.setObjVal! "force" (toJson (#[] : Array String))
    IO.FS.writeFile (root / (mode ++ "-plan.json")) plan.pretty
    pure #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-j1","-M1536","--run",
      project ++ "/tools/research/StudyBuildMain.lean",(root / (mode ++ "-plan.json")).toString]
  IO.FS.writeFile (root / (label ++ "-settings.json")) (Json.mkObj [
    ("command",toJson command),("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("ownedPrefixes",toJson #[root.toString]),
    ("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
