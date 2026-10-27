import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private partial def erase (path : System.FilePath) : IO Unit := do
  let info ← path.symlinkMetadata
  if info.type == .dir then
    for entry in ← path.readDir do erase entry.path
    IO.FS.removeDir path
  else if info.type == .file then IO.FS.removeFile path
  else throw (IO.userError "owned checkpoint contains an unexpected link")
private def artifact (binary : System.FilePath) (path : System.FilePath) : IO Json := do
  let result ← IO.Process.output {cmd := binary.toString,args := #["artifacts",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  let values ← IO.ofExcept (Json.parse result.stdout >>= Json.getArr?)
  let some found := values[0]? | throw (IO.userError "no artifact digest")
  return found
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
  let run := root / "usage-run"
  let guard ← read (root / "usage-run.guard.json")
  unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (1 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "preserve any live answering attempt")
  let lines := (← IO.FS.readFile (run / "rpc/exchange.jsonl")).splitOn "\n" |>.filter (!·.isEmpty)
  let mut turnStarts := 0
  let mut modelUsage := 0
  let mut expectedError := false
  for line in lines do
    let row ← IO.ofExcept (Json.parse line)
    let message := row.getObjValD "message"
    if row.getObjValD "direction" == toJson "client" && message.getObjValD "method" == toJson "turn/start" then
      turnStarts := turnStarts+1
    if row.getObjValD "direction" == toJson "server" &&
        message.getObjValD "method" == toJson "thread/tokenUsage/updated" then modelUsage := modelUsage+1
    if (message.getObjValD "error").getObjValD "message" ==
        toJson "failed to load configuration: default_permissions requires a `[permissions]` table" then
      expectedError := true
  unless turnStarts == 0 && modelUsage == 0 && expectedError do
    throw (IO.userError "an answering call or another failure cannot be reset here")
  unless (← read (run / "input-files.json")) == (← read (run / "output-files.json")) do
    throw (IO.userError "source publication changed")
  let evidence : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/usage-feedback/pre-generation-permission"
  unless !(← evidence.pathExists) && !(← (root / "usage-authorized-plan.json").pathExists) do
    throw (IO.userError "preserve this exact pre-generation correction")
  IO.FS.createDirAll evidence
  for name in ["failure.json","input-files.json","output-files.json","limits.json"] do
    IO.FS.writeBinFile (evidence / name) (← IO.FS.readBinFile (run / name))
  IO.FS.writeBinFile (evidence / "exchange.jsonl") (← IO.FS.readBinFile (run / "rpc/exchange.jsonl"))
  IO.FS.writeBinFile (evidence / "guard.json") (← IO.FS.readBinFile (root / "usage-run.guard.json"))
  let plan ← read (root / "usage-sealed-plan.json")
  let account := root / "account/config.toml"
  let old ← IO.FS.readFile account
  unless (old.splitOn "sandbox_mode = \"read-only\"\n").length == 2 && !old.contains "[permissions.pilot]" do
    throw (IO.userError "unexpected account policy")
  let configured := old.replace "sandbox_mode = \"read-only\"\n" "default_permissions = \"pilot\"\n" ++
    "\n[permissions.pilot]\nextends = \":read-only\"\n[permissions.pilot.network]\nenabled = false\n"
  IO.FS.writeFile account configured
  let binary := root / "controller/StudyMain"
  let newPlan := plan.setObjVal! "accountConfiguration" (← artifact binary account)
  IO.FS.writeFile (root / "usage-authorized-plan.json") (newPlan.compress ++ "\n")
  let revised ← artifact binary (root / "usage-authorized-plan.json")
  let settings ← read (root / "usage-run.settings.json")
  let original ← IO.ofExcept (settings.getObjValAs? (Array String) "command")
  let some position := original.findIdx? (· == "trial-bounded") | throw (IO.userError "wrong bounded command")
  let command := original.set! (position+1) (root / "usage-authorized-plan.json").toString
    |>.set! (position+2) (← IO.ofExcept (revised.getObjValAs? String "sha256"))
  erase (run / "input.egg")
  erase (run / "output.egg")
  IO.FS.rename run (root / "usage-pre-generation-failure")
  IO.FS.rename (root / "usage-run.guard.json") (root / "usage-pre-generation.guard.json")
  IO.FS.rename (root / "usage-run.settings.json") (root / "usage-pre-generation.settings.json")
  IO.FS.writeFile (root / "usage-run.settings.json") ((settings.setObjVal! "command" (toJson command)).pretty)
  IO.FS.writeFile (evidence / "correction.json") (Json.mkObj [
    ("turnStartRequests",toJson turnStarts),("usageNotifications",toJson modelUsage),
    ("sourceUnchanged",toJson true),("readOnlyProfileDefined",toJson true),
    ("networkEnabled",toJson false),("originalAccount",plan.getObjValD "accountConfiguration"),
    ("correctedAccount",newPlan.getObjValD "accountConfiguration"),
    ("officialReference",toJson "https://developers.openai.com/codex/config-reference/"),
    ("answeringCallLimitUnchanged",toJson (1 : Nat)),("productRuntimeChanged",toJson false)]).pretty
