import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
private def evidence := project / "docs/candidates/prepared-bindings/resumed"
private def leanBinary := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def fresh (path : System.FilePath) (value : Json) : IO Unit := do
  check (!(← path.pathExists)) "preserve prior resumed comparison record"
  IO.FS.writeFile path value.pretty
private def hash (p : String) : IO String := do
  let found ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",p]}
  check (found.exitCode == 0) "cannot hash prepared comparison runtime"
  pure ((found.stdout.splitOn " ").headD "")
private def capacity : IO Json := do
  let found ← IO.Process.output {cmd := "/bin/df",args := #["-Pk",root.toString]}
  check (found.exitCode == 0) "cannot check restarted preparation capacity"
  let some row := ((found.stdout.splitOn "\n").filter (! ·.isEmpty)).getLast? |
    throw (IO.userError "missing capacity row")
  let some available := ((row.splitOn " ").filter (! ·.isEmpty))[3]?.bind String.toNat? |
    throw (IO.userError "invalid capacity row")
  check (available ≥ 3145728) "paired setup still needs 3 GiB startup reserve"
  pure (Json.mkObj [("availableKiB",toJson available),("startupMinimumKiB",toJson (3145728 : Nat)),
    ("continuousMinFreeKiB",toJson (2097152 : Nat)),("limitsLowered",toJson false)])
private def completed (label : String) : IO Unit := do
  let guard ← read (evidence / (label ++ "-build.guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) && guard.getObjValD "guardTriggered" == toJson false)
    "native build is not successfully terminal"
private def audit (label : String) (output : System.FilePath) : IO Unit := do
  let result ← IO.Process.output {cmd := leanBinary,args := #["-M1024","--run",
    (project / "tools/research/StudyBuildClosureAudit.lean").toString,
    (root / "cached-usage-runtime-build").toString,output.toString,
    (evidence / (label ++ "-native-closure.json")).toString]}
  check (result.exitCode == 0) "resumed native dependency audit failed"
private def guardSettings (record : System.FilePath) (command : Array String) : Json :=
  Json.mkObj [("record",toJson record),("cwd",toJson project),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("command",toJson command)]

def main (args : List String) : IO Unit := do
  if args == ["init"] then
    let space ← capacity
    check (!(← evidence.pathExists) && !(← (root / "prepared-bindings-trial").pathExists)) "fresh resumed comparison required"
    IO.FS.createDirAll evidence
    let descriptors ← read (project / "docs/candidates/prepared-bindings/runtime-descriptors.json")
    for entry in ← IO.ofExcept descriptors.getArr? do
      let runtime := entry.getObjValD "runtime"
      let binary ← IO.ofExcept (runtime.getObjValAs? String "binary")
      check (runtime.getObjValD "sha256" == toJson (← hash binary)) "runtime changed before resumed setup"
    fresh (evidence / "capacity.json") space
    fresh (evidence / "runtime-descriptors.json") descriptors
    return
  let [mode,label] := args | throw (IO.userError "init or build/seal baseline/candidate/trial")
  check (["baseline","candidate","trial","cue"].contains label) "known isolated comparison role required"
  let name := if label == "trial" || label == "cue" then "prepared-bindings-resumed-" ++ label else "source-prepare-" ++ label
  let output := root / (name ++ "-build")
  if mode == "build" then
    let _ ← capacity
    let control := label == "baseline" || label == "cue"
    let parent := root / (if control then "query-cache-baseline-build" else "prepared-bindings-build")
    let built ← read (parent / "build.json")
    let settings := built.getObjValD "settings"
    let mut objects ← IO.ofExcept ((← read (.mk (← IO.ofExcept (settings.getObjValAs? String "objectModules")))).getObj?)
    for moduleInfo in ← IO.ofExcept (built.getObjValAs? (Array Json) "modules") do
      objects := objects.insert (← IO.ofExcept (moduleInfo.getObjValAs? String "object")) (moduleInfo.getObjValD "module")
    let map := root / (name ++ "-resumed-objects.json")
    IO.FS.writeFile map (Json.obj objects).pretty
    let plan := settings.setObjVal! "project" (toJson project)
      |>.setObjVal! "core" (toJson (root / (if control then "query-cache-baseline-core" else "prepared-bindings-core")))
      |>.setObjVal! "baselineCore" (toJson (root / "query-cache-baseline-core"))
      |>.setObjVal! "baselineResponse" (toJson (parent / "runtime.rsp"))
      |>.setObjVal! "baselineMain" (toJson (parent / "Main.o"))
      |>.setObjVal! "objectModules" (toJson map)
      |>.setObjVal! "mainModule" (toJson (if label == "cue" then "tools.research.PreparedCueCapture" else
        if label == "trial" then "tools.research.PreparedOriginalKeysTrial" else "tools.research.SourcePrepare"))
      |>.setObjVal! "output" (toJson output)
    let config := root / (name ++ "-resumed-build.settings.json")
    fresh config plan
    fresh (root / (name ++ "-resumed-build.guard-settings.json"))
      (guardSettings (evidence / (label ++ "-build.guard.json")) #["/usr/bin/env","LEAN_NUM_THREADS=1",leanBinary,
        "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,config.toString])
    return
  check (mode == "seal") "known build/seal mode required"
  completed label
  audit label output
  let binary := output / "StudyMain"
  if label == "baseline" || label == "candidate" then
    fresh (evidence / (label ++ "-preparer.json")) (Json.mkObj [("binary",toJson binary),("sha256",toJson (← hash binary.toString))])
    if (← (evidence / "baseline-preparer.json").pathExists) && (← (evidence / "candidate-preparer.json").pathExists) then
      fresh (evidence / "source-preparers.json") (toJson (← #["baseline","candidate"].mapM fun arm =>
        return Json.mkObj [("arm",toJson arm),("preparer",← read (evidence / (arm ++ "-preparer.json")))]))
    return
  let _ ← capacity
  let command := #["/usr/bin/env","LEAN_NUM_THREADS=1",
    "EGGSHELL_DATA_ROOT=" ++ (root / "prepared-bindings-trial/data").toString,binary.toString] ++
    (if label == "trial" then #["bindings-cache-resumed"] else #[])
  fresh (root / (name ++ ".guard-settings.json"))
    (guardSettings (evidence / (label ++ ".guard.json")) command)
