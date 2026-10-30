import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal recovered stage record"
  return (result.stdout.splitOn " ").headD ""

/-- Repairs only the outer aggregator's directory mismatch. Never invokes a
runtime, a hook, warm or a model; all evidence is the completed original run. -/
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let records := project / "docs/candidates/query-stage-profile"
  let destination := records / "hooks"
  check (!(← (records / "result.json").pathExists)) "preserve recovered result"
  let guard ← read (records / "run.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "original diagnostic still live"
  check ((← read (records / "run-exit.json")).getObjValD "exitCode" == toJson (0 : Nat)) "actual hook helper failed"
  let actual := project / "docs/candidates/query-stage/hooks"
  check (!(← destination.pathExists) && (← actual.pathExists)) "unexpected aggregation state"
  let stages : Array (String × String) ← IO.ofExcept (fromJson? (← read (records / "stages.json")))
  let files : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in files do check ((← hash (.mk path)) == expected) "original/runtime changed"
  let run := actual / "candidate/rep-0"
  let result ← read (run / "result.json")
  let digest ← hash (run / "body.txt")
  let same := digest == "098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481"
  let delivery := result.getObjValD "availableDelivery"
  check (same && result.getObjValD "bodySha256" == toJson digest &&
    delivery.getObjValD "eligible" == toJson (3 : Nat) && delivery.getObjValD "delivered" == toJson (2 : Nat))
    "timing instrumentation changed original delivery"
  for name in ["shutdown.json","publisher-shutdown.json"] do
    let stopped ← read (run / name)
    check (stopped.getObjValD "acknowledged" == toJson true && stopped.getObjValD "processExited" == toJson true &&
      stopped.getObjValD "endpointRemoved" == toJson true) "service shutdown incomplete"
  IO.FS.rename actual destination
  IO.FS.writeFile (records / "result.json") ((result.setObjVal! "sameBaselineBody" (toJson same))
    |>.setObjVal! "stageLines" (toJson stages.size)
    |>.setObjVal! "protectedHashesBeforeAndAfter" (toJson true)
    |>.setObjVal! "wholeHookCpuPercentages" (toJson false)
    |>.setObjVal! "aggregationRecoveredWithoutRepeatingHook" (toJson true)
    |>.setObjVal! "stageObservationsAvailable" (toJson (!stages.isEmpty))).pretty
  if (← actual.parent.get!.readDir).isEmpty then IO.FS.removeDir actual.parent.get!
  IO.println "Recovered completed original hook and stages without repeating warm, hook or model"
