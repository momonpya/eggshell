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

private def install (runtime root : System.FilePath) : IO (System.FilePath × System.FilePath) := do
  let binary := root / "libexec/eggshell"
  IO.FS.createDirAll binary.parent.get!
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",runtime.toString,binary.toString]}
  check (copied.exitCode == 0) "cannot select readonly trial runtime"
  let plugin := root / "share/eggshell/codex-plugin"
  IO.FS.createDirAll (plugin / "bin")
  for name in ["egg","eggshelld"] do
    let path := plugin / "bin" / name
    IO.FS.writeFile path (Install.pluginLauncher root)
    IO.setAccessRights path {
      user := {read := true,write := true,execution := true}
      group := {read := true,execution := true}
      other := {read := true,execution := true}}
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",
    "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/prefix/share/eggshell/minilm",
    (root / "share/eggshell/minilm").toString]}
  check (linked.exitCode == 0) "cannot select existing numerical boundary"
  return (binary,plugin)

private def configuration (runtime database : System.FilePath) (writable : Bool) : String :=
  "default = \"work\"\nsemantic_matcher = " ++ (toJson #[runtime.toString,"search-provider"]).compress ++
  "\n[eggs]\nwork = " ++ (toJson database.toString).compress ++
  "\n[profiles.work]\nread = [\"work\"]\n" ++
  (if writable then "write = \"work\"\n" else "") ++ "handoff_chars = 120000\n"

def main (args : List String) : IO Unit := do
  let [candidate,destination] := args | throw (IO.userError "query-only runtime and fresh output root required")
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := System.FilePath.mk destination
  check (!(← root.pathExists) && (← Paths.dataRoot) == root / "data") "fresh explicit readonly trial required"
  let manifest := study / "r0/stage1/history/history.json"
  let _ ← StudyHistory.fork ⟨manifest.toString,← ArtifactHash.hex manifest⟩ root
  let database := root / "work.egg"
  let source ← DB.PageMap.pin database
  check (source.head == (← DB.PageMap.pin (study / "r0/stage1/history/source.egg")).head)
    "readonly trial differs from the fixed source"
  let original ← StudyRuntime.files database
  let inherited := study / "study/seed-2/work.egg/derived"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",inherited.toString,(database / "derived").toString]}
  check (copied.exitCode == 0) "cannot retain existing source vector preparation"
  let workspace : System.FilePath := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let definitions ← IO.ofExcept ((← read (study / "task-definitions.json")).getArr?)
  let mut questions : Array (Nat × String × Json × AvailableDelivery.Frozen) := #[]
  for topic in [1,2,3] do
    let some definition := definitions.find? (fun row => (row.getObjValAs? Nat "topic").toOption == some topic) |
      throw (IO.userError "fixed topic missing")
    let prompt ← IO.FS.readFile (study / "prompts" / s!"topic-{topic}.txt")
    check ((definition.getObjValD "prompt").getObjValD "sha256" == toJson (Sha256.hex prompt.toUTF8)) "topic prompt changed"
    let specification := Json.mkObj [("source",toJson database.toString),("workspace",toJson workspace.toString),
      ("prompt",toJson prompt),("files",toJson original),("required",definition.getObjValD "referenceRanges")]
    let frozen ← NativeTrialAudit.freezeAvailable specification
    questions := questions.push (topic,prompt,specification,frozen)
  IO.FS.writeFile (root / "frozen-before-delivery.json") (toJson (questions.map fun (topic,_,specification,frozen) =>
    Json.mkObj [("topic",toJson topic),("specification",specification),("available",toJson frozen)])).pretty
  let derivation ← read (study / "shared-snapshot/anchored-capture/seed-refinement.json")
  check (derivation.getObjValD "source" == toJson source.head) "coordinate refinement changed source"
  let supplements : Array (Nat × String × ContentCapture.Supplement) ← IO.ofExcept (derivation.getObjValAs? _ "supplements")
  let reader ← Persistence.Store.NodeReader.new source
  let mut additions := #[]
  for (id,owner,value) in supplements do
    check ((← Build.document reader id).owner == owner) "coordinate refinement crossed owners"
    if value.sealed then additions := additions.push (id,value)
  let prepared ← Build.refresh source .database additions
  let canonical ← CanonicalSource.Cache.refresh source .database
  IO.FS.writeFile (root / "prepared-source.json") (Json.mkObj [
    ("synapses",toJson prepared),("canonical",toJson canonical),("sourceUnchanged",toJson (source.head == (← DB.PageMap.pin database).head))]).pretty
  let baseline := study / "shared-snapshot/fact-deferred-runtime-build/StudyMain"
  let mut selected := #[]
  for (name,path) in [("baseline",baseline),("candidate",System.FilePath.mk candidate)] do
    let installation := root / name / "prefix"
    let (binary,plugin) ← install path installation
    selected := selected.push (name,binary,plugin,installation)
  let data := root / "data"
  let environment := fun (installation plugin config : System.FilePath) => #[
    ("CODEX_HOME",some (study / "account").toString),("TMPDIR",some (study / "tmp").toString),
    ("EGGSHELL_PREFIX",some installation.toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some plugin.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),
    ("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),("HF_HUB_OFFLINE",some "1"),
    ("TOKENIZERS_PARALLELISM",some "false")]
  let some (_,prepareBinary,preparePlugin,prepareInstallation) := selected[1]? | throw (IO.userError "candidate not selected")
  let prepareConfig := root / "prepare-config.toml"
  IO.FS.writeFile prepareConfig (configuration prepareBinary database true)
  let prepareEnv := environment prepareInstallation preparePlugin prepareConfig
  let publisher ← StudyRuntime.startPublisher prepareBinary data prepareEnv
  let mut results := #[]
  try
    let warmed ← StudyCommand.run prepareBinary.toString #["egg","warm","work"] prepareEnv workspace.toString "" (root / "warm") 240000
    check (warmed.exitCode == 0) "readonly trial preparation failed"
    for (name,binary,plugin,installation) in selected do
      let config := root / name / "readonly.toml"
      IO.FS.writeFile config (configuration binary database false)
      let env := environment installation plugin config
      for (topic,prompt,specification,frozen) in questions do
        let output := root / name / s!"topic-{topic}"
        IO.FS.createDir output
        let session := s!"readonly-{name}-{topic}"
        let managed ← StudyRuntime.startManaged binary plugin session (data / "sessions" / session / "daemon.json") env
        try
          for event in ["SessionStart","UserPromptSubmit"] do
            let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
              ("turn_id",toJson "readonly-turn"),("cwd",toJson workspace.toString),("_eggshell_config",toJson config.toString)] ++
              if event == "UserPromptSubmit" then [("prompt",toJson prompt)] else [])
            let command := output / event
            let response ← StudyCommand.run binary.toString #["codex-hook"] env workspace.toString (request.compress ++ "\n") command 35000
            check (response.exitCode == 0) "readonly native hook failed"
            if event == "UserPromptSubmit" then
              let reply ← IO.ofExcept (Json.parse response.stdout)
              let body := ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
              IO.FS.writeFile (output / "body.txt") body
              let input := Json.mkObj [("source",specification),("database",toJson database.toString),
                ("request",toJson (command / "stdin").toString),("stdout",toJson (command / "stdout").toString),
                ("timing",toJson (command / "record.json").toString),("body",toJson (output / "body.txt").toString)]
              IO.FS.writeFile (output / "audit-input.json") input.pretty
              let audit ← NativeTrialAudit.inspect (output / "audit-input.json").toString
              check (audit.getObjValD "availableEvidence" == toJson frozen) "readonly obligation changed after delivery"
              IO.FS.writeFile (output / "audit.json") audit.pretty
              results := results.push (Json.mkObj [("arm",toJson name),("topic",toJson topic),
                ("runtimeSha256",toJson (← ArtifactHash.hex binary)),("elapsedMs",toJson response.elapsedMs),
                ("bodySha256",toJson (Sha256.hex body.toUTF8)),("availableDelivery",audit.getObjValD "availableDelivery")])
        finally StudyRuntime.stopManaged managed (output / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (root / "publisher-shutdown.json")
  check ((← StudyRuntime.files database) == original) "readonly comparison changed original bytes"
  IO.FS.writeFile (root / "result.json") (Json.mkObj [("source",toJson source.head),("results",Json.arr results),
    ("originalSourceUnchanged",toJson true),("readOnlyProfiles",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("allFreshSessions",toJson true),("tokenImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
  IO.println "Readonly fixed-source topic hooks finished; see per-topic actual delivery and limits"
