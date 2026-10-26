import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

def main (args : List String) : IO Unit := do
  if args.head? == some "hook-profile" then
    let label := (args[1]?).getD "profile"
    unless !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-') do
      throw (IO.userError "simple profile label required")
    let stage := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/owner-unit-postings-20261026/required-replay/topic-1"
    let draft := (← read (stage / "draft.json")).setObjVal! "label" (toJson ("owner-postings-renderer-" ++ label))
    IO.FS.writeFile (stage / (label ++ "-draft.json")) draft.pretty
    let original ← read (stage / "prepare.settings.json")
    let command ← IO.ofExcept (original.getObjValAs? (Array String) "command")
    let command := (command.set! 2 (stage / (label ++ "-draft.json")).toString).set! 3 (stage / (label ++ "-preparation")).toString
    let settings := original.setObjVal! "command" (toJson command)
      |>.setObjVal! "record" (toJson (stage / (label ++ ".guard.json")).toString)
    IO.FS.writeFile (stage / (label ++ "-settings.json")) settings.pretty
    return
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let (label,candidate,parent) ← match args with
    | [label] => pure (label,base / "owner-unit-postings-20261026",base / "routed-transport-20261026")
    | [label,candidate,parent] => pure (label,System.FilePath.mk candidate,System.FilePath.mk parent)
    | _ => throw (IO.userError "PrepareOwnerUnitPostings BUILD-LABEL [CANDIDATE PARENT]")
  unless !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-') do
    throw (IO.userError "simple build label required")
  unless candidate.isAbsolute && parent.isAbsolute do throw (IO.userError "absolute build roots required")
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let mut objects ← IO.ofExcept ((← read (parent / "objects.json")).getObj?)
  let built ← IO.ofExcept (((← read (parent / "product-build/build.json")).getObjValD "modules").getArr?)
  for row in built do
    let path ← IO.ofExcept (row.getObjValAs? String "object")
    objects := objects.insert path (row.getObjValD "module")
  IO.FS.writeFile (candidate / "objects.json") (Json.obj objects).pretty
  let plan := (← read (parent / "product-build/build.json")).getObjValD "settings"
    |>.setObjVal! "core" (toJson (candidate / "checkout").toString)
    |>.setObjVal! "output" (toJson (candidate / "product-build").toString)
    |>.setObjVal! "objectModules" (toJson (candidate / "objects.json").toString)
    |>.setObjVal! "force" (toJson #["Eggshell.Handoff","Main"])
    |>.setObjVal! "baselineResponse" (toJson (parent / "product-build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent / "product-build/Main.o").toString)
    |>.setObjVal! "baselineCore" (toJson (parent / "checkout").toString)
  IO.FS.writeFile (candidate / "build-plan.json") plan.pretty
  let library := candidate / "checkout/.lake/build/lib/lean"
  IO.FS.removeFile library
  let link ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(parent / "product-build/lib").toString,library.toString]}
  unless link.exitCode == 0 do throw (IO.userError link.stderr)
  let settings := Json.mkObj [
    ("command",toJson #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean","LEAN_NUM_THREADS=1",
      toolchain ++ "/bin/lean","-j1","-M1536","--run",project ++ "/tools/research/StudyBuildMain.lean",
      (candidate / "build-plan.json").toString]),
    ("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("ownedPrefixes",toJson #[candidate.toString]),("record",toJson (candidate / (label ++ ".guard.json")).toString)]
  IO.FS.writeFile (candidate / (label ++ "-settings.json")) settings.pretty
