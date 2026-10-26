import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def parent := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/study-services-20261026"
private def runner := parent / "assessed-controller"
private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))
private def call (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd := runner.toString,args}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return result.stdout
private def artifact (path : System.FilePath) : IO Json := do
  let rows ← IO.ofExcept (Json.parse (← call #["artifacts",path.toString]) >>= Json.getArr?)
  let some row := rows[0]? | throw (IO.userError "missing comparison artifact")
  return row
private def save (path : System.FilePath) (value : Json) : IO Unit := do
  unless !(← path.pathExists) do throw (IO.userError "keep existing comparison evidence")
  IO.FS.writeFile path (value.pretty ++ "\n")

/-- A model-free comparison on the already frozen source. This does not
admit a changed product into the fixed-runtime seed/topic study. -/
private def prepare (root : System.FilePath) (number : String) : IO Unit := do
  let some topic := number.toNat? | throw (IO.userError "numeric topic required")
  unless 1 ≤ topic && topic ≤ 3 do throw (IO.userError "topic outside frozen development set")
  let stage := root / s!"topic-{topic}"
  unless !(← stage.pathExists) do throw (IO.userError "keep previous topic comparison")
  let manifest := parent / "common-seed-1/history.json"
  let historyArtifact ← artifact manifest
  let digest ← IO.ofExcept (historyArtifact.getObjValAs? String "sha256")
  let _ ← call #["history","fork",manifest.toString,digest,stage.toString]
  let definitions ← IO.ofExcept ((← read (parent / "task-definitions.json")).getArr?)
  let some definition := definitions.find? (fun row => (row.getObjValAs? Nat "topic").toOption == some topic) |
    throw (IO.userError "missing frozen topic")
  let availability ← IO.ofExcept ((← read (parent / "seed-1-complete-audit.json")).getObjValAs? (Array Json) "availability")
  let some available := availability.find? (fun row => (row.getObjValAs? Nat "topic").toOption == some topic) |
    throw (IO.userError "missing pre-delivery denominator")
  save (stage / "frozen-evidence.json") (available.getObjValD "frozenEvidence")
  let prototype := stage / "audit-prototype.json"
  save prototype (Json.mkObj [("source",Json.mkObj [("required",definition.getObjValD "referenceRanges")])])
  let runtime := root / "prefix/libexec/eggshell"
  let config := stage / "config.toml"
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = " ++
    (toJson #[runtime.toString,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
    (toJson (stage / "work.egg").toString).compress ++
    "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let template ← read (parent / "pilot-stage-1/draft.json")
  let env ← IO.ofExcept (template.getObjValAs? (Array (String × Option String)) "environment")
  let updates := #[("EGGSHELL_PREFIX",some (root / "prefix").toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_DATA_ROOT",some (stage / "data").toString)]
  let env := env.filter (fun entry => !updates.any (·.1 == entry.1)) ++ updates
  let preparation := (template.getObjValD "preparation").setObjVal! "auditInput" (← artifact prototype)
  let plan := template.setObjVal! "label" (toJson s!"delivery-comparison-topic-{topic}")
    |>.setObjVal! "topic" (toJson topic) |>.setObjVal! "stage" (toJson topic)
    |>.setObjVal! "prompt" (definition.getObjValD "prompt")
    |>.setObjVal! "runtime" (← artifact runtime)
    |>.setObjVal! "configuration" (← artifact config)
    |>.setObjVal! "database" (toJson (stage / "work.egg").toString)
    |>.setObjVal! "dataRoot" (toJson (stage / "data").toString)
    |>.setObjVal! "environment" (toJson env)
    |>.setObjVal! "preparation" preparation
    |>.setObjVal! "output" (toJson (stage / "not-admitted").toString)
    |>.setObjVal! "guardRecord" (toJson (stage / "not-admitted.guard.json").toString)
  save (stage / "draft.json") plan
  save (stage / "prepare.settings.json") (Json.mkObj [
    ("record",toJson (stage / "prepare.guard.json").toString),
    ("cwd",toJson root.toString),("ownedPrefixes",toJson #[root.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("command",toJson #[runner.toString,"prepare-live",(stage / "draft.json").toString,
      (stage / "preparation").toString])])

private def assess (root : System.FilePath) (number : String) : IO Unit := do
  let some topic := number.toNat? | throw (IO.userError "numeric topic required")
  let stage := root / s!"topic-{topic}"
  let frozen ← read (stage / "frozen-evidence.json")
  let prototype ← read (parent / "pilot-stage-1/preparation/audit-input.json")
  let definition ← read (stage / "audit-prototype.json")
  let source := (prototype.getObjValD "source").setObjVal! "required"
    ((definition.getObjValD "source").getObjValD "required")
  let promptArtifact := (← read (stage / "draft.json")).getObjValD "prompt"
  let source := source.setObjVal! "prompt" (toJson (← IO.FS.readFile (.mk
    (← IO.ofExcept (promptArtifact.getObjValAs? String "path")))) )
  let destination := stage / "diagnosis"
  unless !(← destination.pathExists) do throw (IO.userError "keep prior independent diagnosis")
  IO.FS.createDir destination
  for index in [:2] do
    let chat := stage / "preparation" / s!"chat-{index}"
    let hook := chat / "UserPromptSubmit"
    let stdout ← read (hook / "stdout")
    let body ← IO.ofExcept ((stdout.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
    let bodyPath := destination / s!"chat-{index}-body.txt"
    IO.FS.writeFile bodyPath body
    let specification := prototype.setObjVal! "source" source
      |>.setObjVal! "database" (toJson (stage / "work.egg").toString)
      |>.setObjVal! "request" (toJson (hook / "stdin").toString)
      |>.setObjVal! "stdout" (toJson (hook / "stdout").toString)
      |>.setObjVal! "timing" (toJson (hook / "record.json").toString)
      |>.setObjVal! "body" (toJson bodyPath.toString)
    let input := destination / s!"chat-{index}-input.json"
    let output := destination / s!"chat-{index}-audit.json"
    save input specification
    let _ ← call #["audit","emit",input.toString,output.toString]
    let result ← read output
    unless result.getObjValD "frozenEvidence" == frozen do
      throw (IO.userError "independent diagnosis changed the frozen denominator")
    IO.println (Json.mkObj [("topic",toJson topic),("chat",toJson index),
      ("bodySha256",result.getObjValD "bodySha256"),
      ("requiredDelivery",result.getObjValD "requiredDelivery"),
      ("qualifiesStudy",toJson false),("answeringModelCalls",toJson (0 : Nat))]).compress

def main (args : List String) : IO Unit := do
  match args with
  | [rootPath,number] =>
      let root := System.FilePath.mk rootPath
      unless root.isAbsolute && (← root.isDir) do throw (IO.userError "existing absolute candidate root required")
      prepare root number
  | ["assess",rootPath,number] =>
      let root := System.FilePath.mk rootPath
      unless root.isAbsolute && (← root.isDir) do throw (IO.userError "existing absolute candidate root required")
      assess root number
  | _ => throw (IO.userError "PrepareDeliveryComparison [assess] CANDIDATE-ROOT TOPIC")
