import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.StudyHistory
import tools.research.NativeTrialAudit
import Eggshell.Install
import Eggshell.SynapseJournal
open Lean Eggshell Eggshell.Research Eggshell.Synapses

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def install (runtime target models : System.FilePath) : IO (System.FilePath × System.FilePath) := do
  let binary := target / "libexec/eggshell"
  IO.FS.createDirAll binary.parent.get!
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",runtime.toString,binary.toString]}
  check (copied.exitCode == 0) "cannot install selected measured runtime"
  let plugin := target / "share/eggshell/codex-plugin"
  IO.FS.createDirAll (plugin / "bin")
  for name in ["egg","eggshelld"] do
    let path := plugin / "bin" / name
    IO.FS.writeFile path (Install.pluginLauncher target)
    IO.setAccessRights path {
      user := {read := true,write := true,execution := true}
      group := {read := true,execution := true}
      other := {read := true,execution := true}}
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",models.toString,(target / "share/eggshell/minilm").toString]}
  check (linked.exitCode == 0) "cannot share the existing numerical boundary"
  return (binary,plugin)

private def configuration (binary database : System.FilePath) (writable : Bool) : String :=
  "default = \"work\"\nsemantic_matcher = " ++ (toJson #[binary.toString,"search-provider"]).compress ++
  "\n[eggs]\nwork = " ++ (toJson database.toString).compress ++
  "\n[profiles.work]\nread = [\"work\"]\n" ++ (if writable then "write = \"work\"\n" else "") ++
  "handoff_chars = 120000\n"

def main : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot/prepared-original-keys-trial"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/prepared-original-keys/trial"
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh paired key-reuse trial required"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  let manifest := study / "r0/stage1/history/history.json"
  let manifestHash ← ArtifactHash.hex manifest
  let common := study / "r0/stage1/history/source.egg"
  let original ← StudyRuntime.files common
  let pinned ← DB.PageMap.pin common
  let workspace : System.FilePath := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let definitions ← IO.ofExcept ((← read (study / "task-definitions.json")).getArr?)
  let previous : Array Json ← IO.ofExcept ((← read (records.parent.get!.parent.get! / "query-cache-llvm/records/frozen-before-delivery.json")).getArr?)
  let mut questions : Array (Nat × String × Json × AvailableDelivery.Frozen) := #[]
  for topic in [1,2,3] do
    let some definition := definitions.find? (fun row => (row.getObjValAs? Nat "topic").toOption == some topic) |
      throw (IO.userError "fixed topic definition missing")
    let prompt ← IO.FS.readFile (study / "prompts" / s!"topic-{topic}.txt")
    check ((definition.getObjValD "prompt").getObjValD "sha256" == toJson (Sha256.hex prompt.toUTF8)) "fixed prompt changed"
    let spec := Json.mkObj [("source",toJson common.toString),("workspace",toJson workspace.toString),
      ("prompt",toJson prompt),("files",toJson original),("required",definition.getObjValD "referenceRanges")]
    let frozen ← NativeTrialAudit.freezeAvailable spec
    let some old := previous.find? (fun row => row.getObjValD "topic" == toJson topic) |
      throw (IO.userError "prior frozen obligation missing")
    check (old.getObjValD "available" == toJson frozen) "frozen DB-present obligations drifted"
    questions := questions.push (topic,prompt,spec,frozen)
  IO.FS.writeFile (records / "frozen-before-delivery.json") (toJson (questions.map fun (topic,_,spec,available) =>
    Json.mkObj [("topic",toJson topic),("specification",spec),("available",toJson available)])).pretty
  IO.FS.writeFile (records / "protocol.json") (Json.mkObj [
    ("repetitions",toJson (2 : Nat)),("topics",toJson #[1,2,3]),("allFreshSessions",toJson true),
    ("armOrder",toJson #[#["baseline","candidate"],#["candidate","baseline"]]),
    ("sameHistoryManifestSha256",toJson manifestHash),("source",toJson pinned.head),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenComparison",toJson false),("adopted",toJson false)]).pretty
  let derivation ← read (study / "shared-snapshot/anchored-capture/seed-refinement.json")
  check (derivation.getObjValD "source" == toJson pinned.head) "coordinate supplement changed source"
  let additions : Array (Nat × String × ContentCapture.Supplement) ← IO.ofExcept (derivation.getObjValAs? _ "supplements")
  let environment := fun (arm installation plugin config : System.FilePath) => #[
    ("CODEX_HOME",some (study / "account").toString),("TMPDIR",some (study / "tmp").toString),
    ("EGGSHELL_PREFIX",some installation.toString),("EGGSHELL_DATA_ROOT",some (arm / "data").toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some plugin.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),("LEAN_NUM_THREADS",some "1"),
    ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
    ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
  let mut arms := #[]
  for (name,runtime) in [("baseline","query-cache-baseline-build"),("candidate","prepared-original-keys-build")] do
    let arm := root / name
    let _ ← StudyHistory.fork ⟨manifest.toString,manifestHash⟩ arm
    let database := arm / "work.egg"
    check ((← StudyRuntime.files database) == original) "arm fork changed source bytes"
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(study / "study/seed-2/work.egg/derived").toString,
      (database / "derived").toString]}
    check (copied.exitCode == 0) "cannot retain existing immutable vector preparation"
    let source ← DB.PageMap.pin database
    let reader ← Persistence.Store.NodeReader.new source
    let mut supplements := #[]
    for (id,owner,supplement) in additions do
      check ((← Build.document reader id).owner == owner) "supplement crossed source owners"
      if supplement.sealed then supplements := supplements.push (id,supplement)
    let prepared ← Build.refresh source .database supplements
    let destination := records / name
    IO.FS.createDirAll destination
    IO.FS.writeFile (destination / "prepared-source.json") (toJson prepared).pretty
    let installation := arm / "prefix"
    let (binary,plugin) ← install (study / "shared-snapshot" / runtime / "StudyMain") installation (study / "prefix/share/eggshell/minilm")
    let writeConfig := arm / "prepare.toml"
    let config := arm / "readonly.toml"
    IO.FS.writeFile writeConfig (configuration binary database true)
    IO.FS.writeFile config (configuration binary database false)
    let env := environment arm installation plugin writeConfig
    let publisher ← StudyRuntime.startPublisher binary (arm / "data") env
    try
      let warmed ← StudyCommand.run binary.toString #["egg","warm","work"] env workspace.toString "" (destination / "warm") 240000
      check (warmed.exitCode == 0) "paired arm preparation failed"
    finally StudyRuntime.stopManaged publisher (destination / "prepare-shutdown.json")
    arms := arms.push (name,arm,binary,plugin,installation,config)
  let mut results := #[]
  let mut bodies : Std.HashMap Nat String := {}
  for repetition in [0:2] do
    let order := if repetition == 0 then arms else arms.reverse
    for (name,arm,binary,plugin,installation,config) in order do
      let env := environment arm installation plugin config
      let publisher ← StudyRuntime.startPublisher binary (arm / "data") env
      let destination := records / name / s!"rep-{repetition}"
      IO.FS.createDirAll destination
      try
        for (topic,prompt,spec,frozen) in questions do
          let out := destination / s!"topic-{topic}"
          IO.FS.createDir out
          let session := s!"keys-{name}-{repetition}-{topic}"
          let managed ← StudyRuntime.startManaged binary plugin session (arm / "data/sessions" / session / "daemon.json") env
          try
            for event in ["SessionStart","UserPromptSubmit"] do
              let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
                ("turn_id",toJson "paired-turn"),("cwd",toJson workspace.toString),("_eggshell_config",toJson config.toString)] ++
                if event == "UserPromptSubmit" then [("prompt",toJson prompt)] else [])
              let response ← StudyCommand.run binary.toString #["codex-hook"] env workspace.toString (request.compress ++ "\n") (out / event) 35000
              check (response.exitCode == 0) "paired actual hook failed"
              if event == "UserPromptSubmit" then
                let reply ← IO.ofExcept (Json.parse response.stdout)
                let body := ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
                IO.FS.writeFile (out / "body.txt") body
                let same := (bodies[topic]?).all (· == body)
                if !bodies.contains topic then bodies := bodies.insert topic body
                let input := Json.mkObj [("source",spec),("database",toJson (arm / "work.egg").toString),
                  ("request",toJson (out / event / "stdin").toString),("stdout",toJson (out / event / "stdout").toString),
                  ("timing",toJson (out / event / "record.json").toString),("body",toJson (out / "body.txt").toString)]
                IO.FS.writeFile (out / "audit-input.json") input.pretty
                let audit ← NativeTrialAudit.inspect (out / "audit-input.json").toString
                check (audit.getObjValD "availableEvidence" == toJson frozen) "paired delivery changed frozen denominator"
                IO.FS.writeFile (out / "audit.json") audit.pretty
                results := results.push (Json.mkObj [("arm",toJson name),("repetition",toJson repetition),
                  ("topic",toJson topic),("runtimeSha256",toJson (← ArtifactHash.hex binary)),
                  ("elapsedMs",toJson response.elapsedMs),("bodyUnchanged",toJson same),
                  ("bodySha256",toJson (Sha256.hex body.toUTF8)),("availableDelivery",audit.getObjValD "availableDelivery")])
                IO.FS.writeFile (records / "progress.json") (Json.arr results).pretty
          finally StudyRuntime.stopManaged managed (out / "shutdown.json")
      finally StudyRuntime.stopManaged publisher (destination / "publisher-shutdown.json")
  for (_,arm,_,_,_,_) in arms do
    check ((← StudyRuntime.files (arm / "work.egg")) == original) "paired source changed during actual hooks"
    let saved := records / arm.fileName.get! / "receipts"
    IO.FS.createDir saved
    for receipt in ← (arm / "data/receipts").readDir do
      IO.FS.createDir (saved / receipt.fileName)
      for entry in ← receipt.path.readDir do
        if entry.fileName.endsWith ".json" then IO.FS.writeFile (saved / receipt.fileName / entry.fileName) (← IO.FS.readFile entry.path)
  check ((← StudyRuntime.files common) == original) "common immutable source changed"
  IO.FS.writeFile (records / "result.json") (Json.mkObj [("results",Json.arr results),
    ("originalSourcesUnchanged",toJson true),("allBodiesUnchanged",toJson (results.all fun row => row.getObjValD "bodyUnchanged" == toJson true)),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
