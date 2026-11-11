import Main
import Eggshell.ContractAudit
import tools.research.SharedTrafficChecks
def main : List String → IO Unit
  | [directory,report] => Eggshell.Research.SharedTrafficChecks.inspect directory report
  | _ => throw (IO.userError "MixedSaveAudit DIRECTORY REPORT")
