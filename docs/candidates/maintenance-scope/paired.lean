import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def compiler := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def main : IO Unit := do
  let order := #[#["parent","candidate"],#["candidate","parent"],#["parent","candidate"]]
  for index in [:order.size] do
    for arm in order[index]! do
      let tag := s!"worker-cpu-pair-{index}-{arm}"
      IO.println s!"starting {tag}"
      (← IO.getStdout).flush
      let setup ← IO.Process.output {cmd := compiler,args := #["-j1","-M512","--run",
        (workspace/"docs/candidates/worker-cpu/setup.lean").toString,tag,
        if arm == "parent" then "profile" else "profile-candidate"]}
      unless setup.exitCode == 0 do throw (IO.userError ("profile setup failed: "++setup.stderr))
      let settings ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/(tag++".guard-settings.json"))))
      let command ← IO.ofExcept (settings.getObjValAs? (Array String) "command")
      let some executable := command[0]? | throw (IO.userError "empty profile command")
      let result ← IO.Process.output {cmd := executable,args := command.extract 1 command.size,cwd := workspace.toString}
      IO.FS.writeFile (base/(tag++".log")) (result.stdout++result.stderr)
      unless result.exitCode == 0 do throw (IO.userError s!"profile failed: {tag}")
      let report ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/(tag++"-result")/"report.json")))
      unless report.getObjValD "originalHeadsUnchanged" == toJson true do
        throw (IO.userError "profile changed an original head")
      let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
      unless processes.exitCode == 0 do throw (IO.userError "cannot check retired processes")
      for line in processes.stdout.splitOn "\n" do
        let line := line.trimAscii.toString
        if ["metadata-ingress-candidate-build/StudyMain ","maintenance-scope-build/StudyMain ","worker-cpu-target/bin/eggshelld "].any
            (fun suffix => line.startsWith (base.toString++"/"++suffix)) then
          throw (IO.userError "profile left a live target process")
      IO.println s!"finished {tag}; original heads exact; target processes retired"
      (← IO.getStdout).flush
