import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main : IO Unit := do
  let active : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let root := active / "storage-integration"
  unless !(← root.pathExists) do throw (IO.userError "preserve earlier service verification")
  IO.FS.createDirAll (root / "prefix/libexec")
  let runtime := root / "prefix/libexec/eggshell"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",
    (base / "storage-product-build/StudyMain").toString,runtime.toString]}
  unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
  for entry in ← (active / "prefix").readDir do
    if entry.fileName == "libexec" then continue
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",entry.path.toString,(root / "prefix" / entry.fileName).toString]}
    unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
  for entry in ← (active / "prefix/libexec").readDir do
    if entry.fileName == "eggshell" then continue
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",entry.path.toString,(root / "prefix/libexec" / entry.fileName).toString]}
    unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
  let digest ← IO.Process.output {
    cmd := (active / "controller/StudyMain").toString
    args := #["artifacts",runtime.toString]}
  unless digest.exitCode == 0 do throw (IO.userError digest.stderr)
  let artifacts ← IO.ofExcept (Json.parse digest.stdout >>= (·.getArr?))
  let template ← IO.ofExcept (Json.parse (← IO.FS.readFile (active / "native-gate-input.json")))
  let environment ← IO.ofExcept (template.getObjValAs? (Array (String × Option String)) "environment")
  let environment := environment.filter (fun row => !["EGGSHELL_PREFIX","EGGSHELL_DATA_ROOT"].contains row.1) ++
    #[("EGGSHELL_PREFIX",some (root / "prefix").toString),("EGGSHELL_DATA_ROOT",some (root / "generic/data").toString)]
  let input := template.setObjVal! "runtime" artifacts[0]! |>.setObjVal! "environment" (toJson environment)
  IO.FS.writeFile (root / "input.json") input.pretty
  let unset := environment.filterMap fun row => if row.2.isNone then some #["-u",row.1] else none
  let variables := environment.filterMap fun row => row.2.map (fun value => row.1 ++ "=" ++ value)
  let command := #["/usr/bin/env"] ++ unset.flatten ++ variables ++
    #[(base / "storage-controller-build/StudyMain").toString,"seed-checks-generic",
      (root / "input.json").toString,(root / "generic").toString]
  IO.FS.writeFile (root / "generic.settings.json") (Json.mkObj [("command",toJson command),
    ("cwd",toJson "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"),
    ("ownedPrefixes",toJson #[active.toString,base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (root / "generic.guard.json").toString)]).pretty
