import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
private def evidence := project / "docs/candidates/group-cue-coverage"
private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def replace (text old next : String) : IO String := do
  check ((text.splitOn old).length == 2) "expected one unchanged group-coverage boundary"
  return text.replace old next

private def prepare (core parent : System.FilePath) (label entry : String) : IO Unit := do
  let out := root / (label ++ "-build")
  check (!(← out.pathExists)) "keep existing native candidate build"
  let prior ← read (parent / "build.json")
  let settings := prior.getObjValD "settings"
  let mut objects ← IO.ofExcept ((← read (.mk (← IO.ofExcept (settings.getObjValAs? String "objectModules")))).getObj?)
  for info in ← IO.ofExcept (prior.getObjValAs? (Array Json) "modules") do
    objects := objects.insert (← IO.ofExcept (info.getObjValAs? String "object")) (info.getObjValD "module")
  let mapping := root / (label ++ "-objects.json")
  IO.FS.writeFile mapping (Json.obj objects).pretty
  let plan := settings.setObjVal! "core" (toJson core.toString)
    |>.setObjVal! "project" (toJson project.toString)
    |>.setObjVal! "baselineCore" (toJson (root / "query-cache-baseline-core").toString)
    |>.setObjVal! "baselineResponse" (toJson (parent / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent / "Main.o").toString)
    |>.setObjVal! "objectModules" (toJson mapping.toString)
    |>.setObjVal! "mainModule" (toJson entry)
    |>.setObjVal! "output" (toJson out.toString)
  let config := root / (label ++ "-build.settings.json")
  IO.FS.writeFile config plan.pretty
  IO.FS.writeFile (root / (label ++ "-build.guard-settings.json")) (Json.mkObj [
    ("record",toJson (evidence / (label ++ "-build.guard.json")).toString),("cwd",toJson project.toString),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
      "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,config.toString])]).pretty

def main (args : List String) : IO Unit := do
  let core := root / "group-cue-core"
  if args == ["runtime"] then
    check (!(← core.pathExists)) "preserve previous isolated source"
    let replay ← read (root / "group-cue-replay-out/result.json")
    check (replay.getObjValD "plannedOriginalNodesOnly" == toJson true &&
      (replay.getObjValD "candidate").getObjValD "targetMet" == toJson true)
      "do not build a runtime after failed source-node preview"
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "query-cache-baseline-core").toString,core.toString]}
    check (copied.exitCode == 0) "cannot isolate source candidate"
    let path := core / "Eggshell/Handoff.lean"
    let text ← IO.FS.readFile path
    let text ← replace text "public import tools.ClosedCoverage\n"
      "public import tools.ClosedCoverage\npublic import tools.research.GroupCueCoverage\n"
    let old := "    let conditioned := scopes.problem\n    let chosen ← SharedCoverage.choose? conditioned\n"
    let next := "    let mut groupFrames := Std.HashSet.ofList (List.range families.length)\n" ++
      "    let mut groupFiles : Std.HashSet Synapses.File := {}\n" ++
      "    for (row,atom) in requirements.sourceRows do\n" ++
      "      unless groupFiles.contains row.key.file do\n" ++
      "        groupFrames := groupFrames.insert (atom.val-1)\n" ++
      "        groupFiles := groupFiles.insert row.key.file\n" ++
      "    let groupValues ← (Eggshell.Research.GroupCueCoverage.prepare\n" ++
      "      (SharedCoverage.Input.ofProblem scopes.problem) p.offers.size compiled.offers.size 512 groupFrames).toOption\n" ++
      "    let conditioned ← groupValues.problem.decode.toOption\n" ++
      "    let chosen ← SharedCoverage.choose? conditioned\n"
    let text ← replace text old next
    let text ← replace text
      "          (\"selectedBundles\",toJson (chosen.selected.countP (fun index => p.offers.size ≤ index.val)))]\n"
      ("          (\"selectedBundles\",toJson (chosen.selected.countP (fun index => p.offers.size ≤ index.val))),\n" ++
       "          (\"physicalGroupCells\",toJson groupValues.groups.size),\n" ++
       "          (\"groupContainmentChecks\",toJson groupValues.candidateChecks)]\n")
    IO.FS.writeFile path text
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",(root / "query-cache-baseline-core/Eggshell/Handoff.lean").toString,path.toString]}
    check (patch.exitCode == 1) "candidate patch is missing"
    IO.FS.writeFile (evidence / "runtime.patch") patch.stdout
    prepare core (root / "query-cache-baseline-build") "group-cue-runtime" "Main"
    return
  if args == ["trial"] then
    prepare core (root / "group-cue-runtime-build") "group-cue-trial" "tools.research.GroupCueTrial"
    return
  throw (IO.userError "prepare isolated runtime or trial build")
