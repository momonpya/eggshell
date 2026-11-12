import tools.research.LLVMProjectActions
import tools.research.StudyCommand
open Lean Eggshell.Research
namespace MatchedDeliveryChecks
structure Case where
  plan : String
  environment : Array (String × Option String)
  workspace : String
  commands : String
  deriving FromJson
structure Input where
  observer : String
  cases : Array Case
  deriving FromJson
def run (action input : String) : IO Unit := do
  let input ← IO.ofExcept (fromJson? (α := Input) (← LLVMProjectChecks.read (.mk input)))
  for item in input.cases do
    let result ← StudyCommand.run input.observer #["single-"++action,item.plan] item.environment item.workspace ""
      (.mk item.commands/action) (if action == "prepare" then 180000 else 240000)
    LLVMProjectChecks.check (result.exitCode == 0) (result.stdout++result.stderr)
end MatchedDeliveryChecks
def main : List String → IO UInt32
  | ["prepare",input] => do MatchedDeliveryChecks.run "prepare" input; return 0
  | ["run",input] => do MatchedDeliveryChecks.run "run" input; return 0
  | ["single-prepare",input] => do LLVMProjectChecks.prepare input; return 0
  | ["single-run",input] => do LLVMProjectChecks.run input; return 0
  | _ => throw (IO.userError "MatchedDeliveryChecks prepare|run INPUT")
