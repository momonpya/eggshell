import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

def main (args : List String) : IO Unit := do
  if args == ["hook-profile"] then
    let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/routed-transport-20261026/runtime-candidate/required-replay/topic-1"
    let draft := (← read (root / "draft.json")).setObjVal! "label" (toJson "routed-renderer-profile")
    IO.FS.writeFile (root / "profile-draft.json") draft.pretty
    let original ← read (root / "prepare.settings.json")
    let command ← IO.ofExcept (original.getObjValAs? (Array String) "command")
    let command := (command.set! 2 (root / "profile-draft.json").toString).set! 3 (root / "profile-preparation").toString
    let settings := original.setObjVal! "command" (toJson command)
      |>.setObjVal! "record" (toJson (root / "profile.guard.json").toString)
    IO.FS.writeFile (root / "profile-settings.json") settings.pretty
    return
  if let ["run",label] := args then
    unless !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-') do
      throw (IO.userError "simple run label required")
    let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/routed-transport-20261026"
    let original ← read (root / "run-settings.json")
    let command ← IO.ofExcept (original.getObjValAs? (Array String) "command")
    let command := command.set! (command.size-1) (root / (label ++ "-report.json")).toString
    let settings := original.setObjVal! "command" (toJson command)
      |>.setObjVal! "record" (toJson (root / (label ++ ".guard.json")).toString)
    IO.FS.writeFile (root / (label ++ "-settings.json")) settings.pretty
    return
  let label ← match args with
    | [] => pure "build"
    | [label] => pure label
    | _ => throw (IO.userError "PrepareRoutedTransport [BUILD-LABEL]")
  unless !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-') do
    throw (IO.userError "simple build label required")
  let product := label.startsWith "product"
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let parent := base / "synaptic-routing-store-20261026"
  let candidate := base / "routed-transport-20261026"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let mut objects ← IO.ofExcept ((← read (parent / "objects.json")).getObj?)
  let built ← IO.ofExcept (((← read (parent / "build/build.json")).getObjValD "modules").getArr?)
  for row in built do
    let path ← IO.ofExcept (row.getObjValAs? String "object")
    objects := objects.insert path (row.getObjValD "module")
  IO.FS.writeFile (candidate / "objects.json") (Json.obj objects).pretty
  let plan := (← read (parent / "build-plan.json"))
    |>.setObjVal! "core" (toJson (candidate / "checkout").toString)
    |>.setObjVal! "output" (toJson (candidate / (if product then "product-build" else "build")).toString)
    |>.setObjVal! "objectModules" (toJson (candidate / "objects.json").toString)
    |>.setObjVal! "mainModule" (toJson (if product then "Main" else "tools.research.RoutedTransportAudit"))
    |>.setObjVal! "force" (toJson (#["Eggshell.SynapseRecommend","Eggshell.SynapseTransport","Eggshell.SynapseBundles"] ++
      if product then #["Eggshell.Handoff","Main"] else #[]))
    |>.setObjVal! "baselineResponse" (toJson (parent / "build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent / "build/tools_research_SynapticRoutingStoreAudit.o").toString)
  IO.FS.writeFile (candidate / "build-plan.json") plan.pretty
  let library := candidate / "checkout/.lake/build/lib/lean"
  IO.FS.removeFile library
  let link ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(parent / "build/lib").toString,library.toString]}
  unless link.exitCode == 0 do throw (IO.userError link.stderr)
  let guardSettings := Json.mkObj [
    ("command",toJson #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean","LEAN_NUM_THREADS=1",
      toolchain ++ "/bin/lean","-j1","-M1536","--run",project ++ "/tools/research/StudyBuildMain.lean",
      (candidate / "build-plan.json").toString]),
    ("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("ownedPrefixes",toJson #[candidate.toString]),("record",toJson (candidate / (label ++ ".guard.json")).toString)]
  IO.FS.writeFile (candidate / (label ++ "-settings.json")) guardSettings.pretty
