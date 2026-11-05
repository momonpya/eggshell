import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def array (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def measuredRows (report : Json) : Array Json :=
  (#[report.getObjValD "first",report.getObjValD "second"]++array report "remaining").flatMap (array · "rows")
def complete (row : Json) : Bool := row.getObjValD "bothFields" == toJson true &&
  row.getObjValD "complete" == toJson true && row.getObjValD "acknowledged" == toJson true &&
  (row.getObjValAs? Nat "elapsedMs").toOption.any (· < 30000)
def runProfile (tag mode arm : String) : IO Json := do
  IO.println s!"starting {tag}"
  (← IO.getStdout).flush
  let setup ← IO.Process.output {cmd := compiler,args := #["-j1","-M512","--run",
    (workspace/"docs/candidates/focus-locators/setup.lean").toString,tag,mode,arm]}
  unless setup.exitCode == 0 do throw (IO.userError ("profile setup failed: "++setup.stderr))
  let settings ← read (base/(tag++".guard-settings.json"))
  let command ← IO.ofExcept (settings.getObjValAs? (Array String) "command")
  let some executable := command[0]? | throw (IO.userError "empty profile command")
  let result ← IO.Process.output {cmd := executable,args := command.extract 1 command.size,cwd := workspace.toString}
  IO.FS.writeFile (base/(tag++".log")) (result.stdout++result.stderr)
  unless result.exitCode == 0 do throw (IO.userError s!"profile failed: {tag}")
  let report ← read (base/(tag++"-result")/"report.json")
  unless report.getObjValD "originalHeadsUnchanged" == toJson true do throw (IO.userError "profile changed original heads")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot check retired target processes")
  for line in processes.stdout.splitOn "\n" do
    let line := line.trimAscii.toString
    if ["metadata-ingress-candidate-build/StudyMain ","focus-locators-build/StudyMain ","worker-cpu-target/bin/eggshelld "].any
        (fun suffix => line.startsWith (base.toString++"/"++suffix)) then
      throw (IO.userError "profile left a live target process")
  IO.println s!"finished {tag}; originals exact; target processes retired"
  (← IO.getStdout).flush
  return report
def main (args : List String) : IO Unit := do
  let [runName] := args | throw (IO.userError "fresh paired run name required")
  unless runName.startsWith "focus-locators-" do throw (IO.userError "invalid paired run name")
  let order := #[#["parent","candidate"],#["candidate","parent"],#["parent","candidate"]]
  let mut admitted := true
  let mut decisions := #[]
  for index in [:order.size] do
    for arm in order[index]! do
      let report ← runProfile s!"{runName}-pair-{index}-{arm}" "profile" arm
      if arm == "candidate" then
        let rows := measuredRows report
        unless rows.size == 80 do throw (IO.userError "profile lacks eighty frozen questions")
        let passed := rows.all complete
        admitted := admitted && passed
        decisions := decisions.push (Json.mkObj [("pair",toJson index),("count",toJson rows.size),
          ("passed",toJson (rows.filter complete).size),("allFrozenGroupsPass",toJson passed)])
  let gate := Json.mkObj [("profiles",toJson decisions),("burstAdmitted",toJson admitted)]
  IO.FS.writeFile (base/(runName++"-burst-admission.json")) gate.pretty
  if admitted then
    for arm in ["parent","candidate"] do
      discard <| runProfile (runName++"-burst-"++arm) "burst" arm
  else
    IO.println "frozen moderate-load gate fails; no eighty-client burst started"
