import tests.SourceEvidenceTests
import tests.SourceObservationTests
import Eggshell.Daemon

/-- Existing source tests exercise native workers. Child modes must dispatch
to the product worker rather than recursively running the test harness. -/
def main (args : List String) : IO UInt32 := do
  match args with
  | ["codex-worker",role] => Eggshell.Plugin.Worker.run role
  | ["codex-daemon","shutdown"] => Eggshell.Plugin.Daemon.shutdown; return 0
  | ["codex-daemon",session] => Eggshell.Plugin.Daemon.run session
  | ["sources"] | ["observations"] =>
    try
      if args == ["sources"] then Eggshell.SourceEvidenceTests.run
      else Eggshell.SourceObservationTests.run
      return 0
    finally
      Eggshell.Plugin.Worker.shutdown
      Eggshell.Plugin.Daemon.shutdown
  | _ => throw (IO.userError "FreshnessSourceAudit sources|observations")
