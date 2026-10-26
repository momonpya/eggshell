import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main (args : List String) : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let parent := base / "bound-span-preparation-20261027"
  let root := base / "prepared-record-delivery-20261027"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  if args == ["fork"] then
    unless !(← root.pathExists) do throw (IO.userError "preserve previous candidate")
    IO.FS.createDir root
    let result ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(parent / "checkout").toString,(root / "checkout").toString]}
    unless result.exitCode == 0 do throw (IO.userError result.stderr)
    IO.FS.removeFile (root / "checkout/.lake/build/lib/lean")
    let result ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(parent / "product-build/lib").toString,(root / "checkout/.lake/build/lib/lean").toString]}
    unless result.exitCode == 0 do throw (IO.userError result.stderr)
    return
  let [mode,label] := args | throw (IO.userError "fork | MODE LABEL")
  unless ["product","audit","budget","source","inspect","replay","run-audit","run-budget","run-source","run-inspect","run-replay"].contains mode &&
      !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-') do
    throw (IO.userError "unknown mode/label")
  let command ← if mode.startsWith "run-" then
    pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++
      (if mode == "run-inspect" || mode == "run-replay" then root / "fixed-source-hooks/data" else root / label / "data").toString,
      (root / (if mode == "run-source" then "source-build/StudyMain"
        else if mode == "run-inspect" then "inspect-build/StudyMain"
        else if mode == "run-replay" then "replay-build/StudyMain"
        else if mode == "run-budget" then "budget-build/StudyMain" else "audit-build/StudyMain")).toString] ++
      (if mode == "run-source" then #[root.toString,(root / label).toString,"topic","2"]
      else #[(root / label).toString]))
  else do
    let origin := if mode != "product" && (← (root / "product-build/build.json").pathExists) then root else parent
    let library := root / "checkout/.lake/build/lib/lean"
    IO.FS.removeFile library
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(origin / "product-build/lib").toString,library.toString]}
    unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
    let built ← IO.ofExcept (Json.parse (← IO.FS.readFile (origin / "product-build/build.json")))
    let mut objects ← IO.ofExcept (Json.parse (← IO.FS.readFile (origin / "objects.json")) >>= Json.getObj?)
    for entry in ← IO.ofExcept ((built.getObjValD "modules").getArr?) do
      objects := objects.insert (← IO.ofExcept (entry.getObjValAs? String "object")) (entry.getObjValD "module")
    IO.FS.writeFile (root / "objects.json") (Json.obj objects).pretty
    let mut force : Array String := #[]
    let previousBuild := root / (mode ++ "-build/build.json")
    if mode != "product" && (← previousBuild.pathExists) then
      let previous ← IO.ofExcept (Json.parse (← IO.FS.readFile previousBuild))
      for entry in ← IO.ofExcept ((previous.getObjValD "modules").getArr?) do
        let name ← IO.ofExcept (entry.getObjValAs? String "module")
        if name.startsWith "tools.research." then force := force.push name
    let plan := built.getObjValD "settings"
    let plan := plan.setObjVal! "core" (toJson (root / "checkout").toString)
      |>.setObjVal! "output" (toJson (root / (mode ++ "-build")).toString)
      |>.setObjVal! "mainModule" (toJson (if mode == "product" then "Main"
        else if mode == "source" then "tools.research.SynapticSourceHookAudit"
        else if mode == "inspect" then "tools.research.InspectPreparedDelivery"
        else if mode == "budget" then "tools.research.DirectBudgetAudit"
        else if mode == "replay" then "tools.research.ReplayPreparedRecord"
        else "tools.research.PreparedRecordAudit"))
      |>.setObjVal! "baselineCore" (toJson (origin / "checkout").toString)
      |>.setObjVal! "baselineResponse" (toJson (origin / "product-build/runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (origin / "product-build/Main.o").toString)
      |>.setObjVal! "objectModules" (toJson (root / "objects.json").toString)
      |>.setObjVal! "force" (toJson force)
    IO.FS.writeFile (root / (mode ++ "-plan.json")) plan.pretty
    pure #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean",
      "-j1","-M1536","--run",project ++ "/tools/research/StudyBuildMain.lean",(root / (mode ++ "-plan.json")).toString]
  IO.FS.writeFile (root / (label ++ "-settings.json")) (Json.mkObj [
    ("command",toJson command),("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("ownedPrefixes",toJson #[root.toString]),
    ("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
