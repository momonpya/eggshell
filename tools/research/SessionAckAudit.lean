import Eggshell.ContractAudit
import tools.research.SessionStateProbe
import tools.research.SessionAcknowledgmentChecks
import tools.research.StudySeedChecks

#print axioms Eggshell.Plugin.acknowledgment_rejects_new_context
#print axioms Eggshell.Plugin.acknowledgment_rejects_expired

def main (args : List String) : IO Unit := do
  match args with
  | ["probe",output] => Eggshell.Research.SessionStateProbe.run output
  | ["checks",output] => Eggshell.Research.SessionAcknowledgmentChecks.run output
  | ["native",input,root] =>
    Eggshell.Research.StudySeedChecks.run input root (remote := true) (literal := true) (generic := true)
  | _ => throw (IO.userError "SessionAckAudit {probe OUTPUT | checks OUTPUT | native INPUT NEW-ROOT}")
