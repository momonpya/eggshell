import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

/-- A valid incomplete notice is still an observed delivery with zero evidence.
Audit it against the original frozen source instead of omitting its question
from the denominator when the preparation gate rejects it. -/
def main (args : List String) : IO Unit := do
  let [path,chat] := args | throw (IO.userError "SealObservedReplay TOPIC CHAT-INDEX")
  unless ["0","1"].contains chat do throw (IO.userError "known native preflight chat required")
  let root := System.FilePath.mk path
  let plan ← read (root / "draft.json")
  let callRoot := root / "preparation" / ("chat-" ++ chat)
  let hook := callRoot / "UserPromptSubmit"
  let stdout ← read (hook / "stdout")
  let body ← IO.ofExcept (stdout.getObjVal? "hookSpecificOutput" >>= (·.getObjValAs? String "additionalContext"))
  let savedBody := callRoot / "observed-body.txt"
  unless !(← savedBody.pathExists) do throw (IO.userError "keep earlier observed audit")
  IO.FS.writeFile savedBody body
  let preparation := plan.getObjValD "preparation"
  let prototype ← read (.mk (← IO.ofExcept ((preparation.getObjValD "auditInput").getObjValAs? String "path")))
  let prompt ← IO.FS.readFile (.mk (← IO.ofExcept ((plan.getObjValD "prompt").getObjValAs? String "path")))
  let source := Json.mkObj [("source",plan.getObjValD "sourceSnapshot"),("workspace",plan.getObjValD "workspace"),
    ("prompt",toJson prompt),("files",plan.getObjValD "sourceFiles"),
    ("required",(prototype.getObjValD "source").getObjValD "required")]
  let input := callRoot / "observed-audit-input.json"
  let output := callRoot / "observed-audit.json"
  IO.FS.writeFile input (Json.mkObj [("source",source),("database",plan.getObjValD "database"),
    ("request",toJson (hook / "stdin").toString),("stdout",toJson (hook / "stdout").toString),
    ("timing",toJson (hook / "record.json").toString),("body",toJson savedBody.toString)]).pretty
  let result ← IO.Process.output {
    cmd := "/Users/ovm/.codex/experiments/eggshell/study-services-20261026/assessed-controller"
    args := #["audit","emit",input.toString,output.toString] }
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  let report ← read output
  unless report.getObjValD "frozenEvidence" == (← read (root / "frozen-evidence.json")) do
    throw (IO.userError "observed audit changed the frozen source denominator")
  IO.println (report.getObjValD "requiredDelivery").compress
