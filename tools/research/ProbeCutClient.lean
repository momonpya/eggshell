module
public import tools.research.ProbeCut
public import Lean.Data.Json.Parser
@[expose] public section
namespace Eggshell.Research.ProbeCutClient
open Lean
def run (root engine : System.FilePath) (mode : String) : IO Unit := do
  unless mode == "sham" || mode == "collect" do throw (IO.userError "unknown diagnostic mode")
  let began ← IO.monoMsNow
  let deadline := began+10000
  let mut attempts := #[]
  repeat
    let result ← IO.Process.output {cmd := engine.toString,args := #["retention-probe",mode]}
    let parsed := Json.parse result.stdout
    let value := parsed.toOption.getD Json.null
    attempts := attempts.push (Json.mkObj [("elapsedMs",toJson ((← IO.monoMsNow)-began)),
      ("exitCode",toJson result.exitCode.toNat),("reply",value),("stderr",toJson result.stderr),
      ("invalidStdout",if parsed.isOk then Json.null else toJson result.stdout)])
    IO.FS.writeFile (root/("retention-attempts-"++mode++".json")) (toJson attempts).compress
    unless result.exitCode == 0 do throw (IO.userError ("diagnostic RPC failed: "++result.stderr))
    let status ← IO.ofExcept (value.getObjValAs? String "status")
    if status == "busy" then
      unless value.getObjValD "executed" == toJson false && value.getObjValD "observation" == Json.null do
        throw (IO.userError "busy response is not a certified non-execution")
      unless (← IO.monoMsNow) < deadline do throw (IO.userError "diagnostic readiness budget exhausted without an intervention")
      IO.sleep 5
    else
      -- Preserve every executed outcome before evaluating it. An overlap is
      -- a terminal diagnostic failure, never a reason to execute collection again.
      IO.FS.writeFile (root/("retention-"++mode++".json")) value.compress
      unless value.getObjValD "executed" == toJson true && status == "observed" &&
          ProbeCut.acceptable (value.getObjValD "beforeStats") (value.getObjValD "afterStats") do
        throw (IO.userError "executed intervention overlapped work; not retried")
      return
end Eggshell.Research.ProbeCutClient
