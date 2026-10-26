import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

def main (args : List String) : IO Unit := do
  if args.head? == some "hook-profile" then
    let (label,candidate) ← match args with
      | [_,label] => pure (label,"shared-prepared-service-20261026")
      | [_,label,candidate] => pure (label,candidate)
      | _ => throw (IO.userError "hook-profile LABEL [CANDIDATE]")
    unless !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-') do
      throw (IO.userError "simple hook diagnostic label required")
    unless ["shared-prepared-service-20261026","shared-bundle-projection-20261026"].contains candidate do
      throw (IO.userError "known isolated runtime required")
    let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell" / candidate / "required-replay"
    let stage := root / "topic-1"
    let draft := (← read (stage / "draft.json")).setObjVal! "label" (toJson ("shared-source-" ++ label))
    let input := stage / (label ++ "-draft.json")
    unless !(← input.pathExists) do throw (IO.userError "keep earlier hook diagnostic")
    IO.FS.writeFile input draft.pretty
    let settings ← read (stage / "prepare.settings.json")
    let command ← IO.ofExcept (settings.getObjValAs? (Array String) "command")
    let command := (command.set! 2 input.toString).set! 3 (stage / (label ++ "-preparation")).toString
    let settings := settings.setObjVal! "command" (toJson command)
      |>.setObjVal! "record" (toJson (stage / (label ++ ".guard.json")).toString)
    IO.FS.writeFile (stage / (label ++ "-settings.json")) settings.pretty
    return
  if let ["run",label] := args then
    unless !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-') do
      throw (IO.userError "simple run label required")
    let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/shared-prepared-service-20261026"
    let output := root / label
    let settings := Json.mkObj [
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT=" ++ (output / "data").toString,
        (root / "audit-build/StudyMain").toString,(root / "product-build/StudyMain").toString,output.toString]),
      ("cwd",toJson "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("ownedPrefixes",toJson #[root.toString]),("record",toJson (root / (label ++ ".guard.json")).toString)]
    IO.FS.writeFile (root / (label ++ "-settings.json")) settings.pretty
    return
  let [label] := args | throw (IO.userError "PrepareSharedPreparedAudit BUILD-LABEL")
  unless !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-') do
    throw (IO.userError "simple build label required")
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/shared-prepared-service-20261026"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let baseline ← read (root / "product-build/build.json")
  let mut objects ← IO.ofExcept ((← read (root / "objects.json")).getObj?)
  for row in ← IO.ofExcept ((baseline.getObjValD "modules").getArr?) do
    objects := objects.insert (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
  IO.FS.writeFile (root / "audit-objects.json") (Json.obj objects).pretty
  let plan := baseline.getObjValD "settings"
    |>.setObjVal! "output" (toJson (root / "audit-build").toString)
    |>.setObjVal! "objectModules" (toJson (root / "audit-objects.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.SharedPreparedServiceAudit")
    |>.setObjVal! "force" (toJson (#[] : Array String))
    |>.setObjVal! "baselineResponse" (toJson (root / "product-build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root / "product-build/Main.o").toString)
    |>.setObjVal! "baselineCore" (toJson (root / "checkout").toString)
  IO.FS.writeFile (root / "audit-build-plan.json") plan.pretty
  let library := root / "checkout/.lake/build/lib/lean"
  IO.FS.removeFile library
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(root / "product-build/lib").toString,library.toString]}
  unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
  let settings := Json.mkObj [
    ("command",toJson #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean","LEAN_NUM_THREADS=1",
      toolchain ++ "/bin/lean","-j1","-M1536","--run",project ++ "/tools/research/StudyBuildMain.lean",
      (root / "audit-build-plan.json").toString]),
    ("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("ownedPrefixes",toJson #[root.toString]),("record",toJson (root / (label ++ ".guard.json")).toString)]
  IO.FS.writeFile (root / (label ++ "-settings.json")) settings.pretty
