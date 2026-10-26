import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def study := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/study-services-20261026"
private def runner := study / "assessed-controller"

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def call (arguments : Array String) : IO String := do
  let result ← IO.Process.output {cmd := runner.toString,args := arguments}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return result.stdout

private def artifact (path : System.FilePath) : IO Json := do
  let rows ← IO.ofExcept (Json.parse (← call #["artifacts",path.toString]) >>= Json.getArr?)
  let some row := rows[0]? | throw (IO.userError "missing replay artifact")
  return row

/-- Prepare model-free actual hooks for all three questions. Frozen references
are written only to the audit prototype; the product gets the original prompt,
workspace and DB. This command cannot start an App Server or answering turn. -/
def main (args : List String) : IO Unit := do
  let (candidatePath,expectedHash,reuse) ← match args with
    | [candidatePath,expectedHash] => pure (candidatePath,expectedHash,none)
    | [candidatePath,expectedHash,"reuse",previous] => pure (candidatePath,expectedHash,some (System.FilePath.mk previous))
    | _ => throw (IO.userError "PrepareRequiredReplay CANDIDATE EXPECTED-SHA256 [reuse PREVIOUS-REPLAY]")
  let candidate := System.FilePath.mk candidatePath
  unless candidate.isAbsolute && expectedHash.length == 64 && reuse.all (·.isAbsolute) do
    throw (IO.userError "absolute candidate/history and expected product hash required")
  let root := candidate / "required-replay"
  unless !(← root.pathExists) do throw (IO.userError "keep prior required-history replay")
  IO.FS.createDir root
  let installation := root / "prefix"
  let binary := installation / "libexec/eggshell"
  IO.FS.createDirAll binary.parent.get!
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",(candidate / "build/StudyMain").toString,binary.toString]}
  unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
  let runtime ← artifact binary
  unless (runtime.getObjValAs? String "sha256").toOption == some expectedHash do
    throw (IO.userError "candidate product changed before replay")
  let plugin := installation / "share/eggshell/codex-plugin"
  let launcher := plugin / "bin/eggshelld"
  IO.FS.createDirAll launcher.parent.get!
  let originalLauncher := study / "prefix/share/eggshell/codex-plugin/bin/eggshelld"
  IO.FS.writeFile launcher ((← IO.FS.readFile originalLauncher).replace
    (study / "prefix").toString installation.toString)
  IO.setAccessRights launcher {
    user := {read := true,write := true,execution := true}
    group := {read := true,execution := true}
    other := {read := true,execution := true} }
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",
    "/Users/ovm/.codex/experiments/eggshell/numerical-owned-20261024/prefix/share/eggshell/minilm",
    (installation / "share/eggshell/minilm").toString]}
  unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
  let audit ← read (study / "seed-1-complete-audit.json")
  unless (audit.getObjValAs? Bool "seedAccepted").toOption == some true do throw (IO.userError "source audit has not passed")
  let definitions ← IO.ofExcept ((← read (study / "task-definitions.json")).getArr?)
  let availability ← IO.ofExcept (audit.getObjValAs? (Array Json) "availability")
  let history := study / "common-seed-1/history.json"
  let historyArtifact ← artifact history
  let digest ← IO.ofExcept (historyArtifact.getObjValAs? String "sha256")
  let original ← read (study / "pilot-stage-1/draft.json")
  let account ← IO.ofExcept ((original.getObjValD "accountConfiguration").getObjValAs? String "path")
  let privateEnvironment ← IO.ofExcept (fromJson? (α := Array (String × Option String)) (original.getObjValD "environment"))
  IO.FS.writeFile (root / "before-delivery.json") (Json.mkObj [
    ("runtime",runtime),("sourceAudit",← artifact (study / "seed-1-complete-audit.json")),
    ("definitions",← artifact (study / "task-definitions.json")),("history",historyArtifact),
    ("reusedReplay",toJson (reuse.map (·.toString))),
    ("modelFree",toJson true),("newSeedStudy",toJson false),("productionAdoption",toJson false)]).pretty
  for topic in [1,2,3] do
    let stageRoot := root / s!"topic-{topic}"
    let inputRoot ← match reuse with
      | none =>
          let _ ← call #["history","fork",history.toString,digest,stageRoot.toString]
          pure stageRoot
      | some previous =>
          IO.FS.createDir stageRoot
          pure (previous / s!"topic-{topic}")
    let database := inputRoot / "work.egg"
    let data := inputRoot / "data"
    let some definition := definitions.find? (fun value => (value.getObjValAs? Nat "topic").toOption == some topic) |
      throw (IO.userError "missing question definition")
    let some frozen := availability.find? (fun value => (value.getObjValAs? Nat "topic").toOption == some topic) |
      throw (IO.userError "missing frozen source requirements")
    let frozenEvidence := frozen.getObjValD "frozenEvidence"
    let units ← IO.ofExcept (frozenEvidence.getObjValAs? (Array Json) "units")
    unless units.size == (#[4,6,5] : Array Nat)[topic-1]! do throw (IO.userError "frozen denominator changed")
    IO.FS.writeFile (stageRoot / "frozen-evidence.json") frozenEvidence.pretty
    let prototype := stageRoot / "audit-prototype.json"
    IO.FS.writeFile prototype (Json.mkObj [("source",Json.mkObj [("required",definition.getObjValD "referenceRanges")])]).pretty
    let placeholder ← artifact prototype
    let preparation := Json.mkObj ((#["input","stdout","timing","body","state","shutdown","search","auditInput","auditReport"]).toList.map
      (fun key => (key,placeholder)) ++ [("numerical",toJson (#[] : Array Json)),("session",toJson "unprepared")])
    let configuration := stageRoot / "config.toml"
    IO.FS.writeFile configuration ("default = \"work\"\nsemantic_matcher = " ++
      (toJson #[binary.toString,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
      (toJson database.toString).compress ++
      "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
    let updates := #[ ("EGGSHELL_PREFIX",some installation.toString),("EGGSHELL_CONFIG",some configuration.toString),
      ("EGGSHELL_DATA_ROOT",some data.toString),("PLUGIN_ROOT",some plugin.toString),
      ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
    let environment := privateEnvironment.filter (fun value => !updates.any (·.1 == value.1)) ++ updates
    let plan := original.setObjVal! "label" (toJson s!"{candidate.fileName.getD "candidate"}-required-topic-{topic}")
      |>.setObjVal! "topic" (toJson topic)
      |>.setObjVal! "runtime" runtime
      |>.setObjVal! "prompt" (definition.getObjValD "prompt")
      |>.setObjVal! "pluginRoot" (toJson plugin.toString)
      |>.setObjVal! "pluginFiles" (toJson #[← artifact launcher])
      |>.setObjVal! "configuration" (← artifact configuration)
      |>.setObjVal! "accountConfiguration" (← artifact (.mk account))
      |>.setObjVal! "database" (toJson database.toString)
      |>.setObjVal! "dataRoot" (toJson data.toString)
      |>.setObjVal! "environment" (toJson environment)
      |>.setObjVal! "preparation" preparation
      |>.setObjVal! "output" (toJson (stageRoot / "unused-model-trial").toString)
    IO.FS.writeFile (stageRoot / "draft.json") plan.pretty
    IO.FS.writeFile (stageRoot / "prepare.settings.json") (Json.mkObj [
      ("record",toJson (stageRoot / "prepare.guard.json").toString),
      ("cwd",toJson root.toString),("ownedPrefixes",toJson (#[root.toString] ++ reuse.toArray.map (·.toString))),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("command",toJson #[runner.toString,"prepare-live",(stageRoot / "draft.json").toString,
        (stageRoot / "preparation").toString])]).pretty
