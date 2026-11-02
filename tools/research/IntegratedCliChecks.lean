import tools.research.StudySeedChecks

open Lean Eggshell Eggshell.Research

private def resumeRecall (root fixture : System.FilePath) : IO Unit := do
  let input := root / (fixture.fileName.get! ++ ".input.json")
  let plan ← IO.ofExcept (fromJson? (α := StudySeedChecks.Input) (← StudyAdmission.readJson input.toString))
  StudyAdmission.verifyArtifact plan.runtime
  let source ← DB.PageMap.pin (fixture / "work.egg")
  let records ← Synapses.Provenance.records source
  unless records.size == 92 do throw (IO.userError "retained source lacks the 92 accepted native observations")
  let reader ← Persistence.Store.NodeReader.new source
  for record in records do
    let occurrence := record.origin.occurrence
    unless occurrence.session == "native-empty-seed" && occurrence.turn == "seed-turn" do
      throw (IO.userError "retained fixture has another native occurrence")
    let path := fixture / (occurrence.useId ++ "-Post") / "stdin"
    let request ← StudyAdmission.readJson path.toString
    let tool : Plugin.ToolEvent := {
      name := ← IO.ofExcept (request.getObjValAs? String "tool_name"),useId := occurrence.useId
      input := (request.getObjValD "tool_input").compress,response := (request.getObjValD "tool_response").compress}
    let document ← Synapses.Provenance.checkedDocument reader record.origin
    unless document.workText == some (Plugin.canonicalToolWork tool) &&
        document.source == some (Plugin.canonicalJson tool.response) do
      throw (IO.userError "accepted native input/output differs from its literal Post")
  let some journal ← Synapses.Journal.open? source | throw (IO.userError "retained native journal is missing")
  let events ← Synapses.Journal.turnEntries journal ⟨"native-empty-seed","seed-turn"⟩
  unless events.size == 185 do throw (IO.userError "retained journal lacks a Pre, Post or final answer")
  let copied := fixture / "recovered-source.egg"
  let files ← StudyRuntime.checkpoint source.directory copied
  let report := Json.mkObj [("nativeObservations",toJson records.size),("exactPostInputOutputPairs",toJson records.size),
    ("journalEvents",toJson events.size),("sourceOnlyCopy",toJson true),("copiedFiles",toJson files),
    ("runtime",toJson plan.runtime),("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (fixture / "retained-source-audit.json") report.pretty
  StudySeedChecks.recall plan fixture copied plan.environment
  unless (← StudyRuntime.files copied) == files do throw (IO.userError "readonly recovery changed copied original bytes")
  IO.FS.writeFile (fixture / "resume-complete.json")
    (report.setObjVal! "readonlyRecallCompleted" (toJson true)).pretty

def main (args : List String) : IO Unit := do
  if let [base,directory,"resume-recall"] := args then
    resumeRecall (.mk base) (.mk directory)
    return
  let [base,directory] := args | throw (IO.userError "STUDY-ROOT NEW-FIXTURE")
  let root := System.FilePath.mk base
  let installRoot := root / "integrated-cli-prefix"
  let binary := installRoot / "libexec/eggshell"
  let actual := root / "integrated-cli-runtime-build/StudyMain"
  IO.FS.createDirAll binary.parent.get!
  if !(← binary.pathExists) then
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",actual.toString,binary.toString]}
    unless linked.exitCode == 0 do throw (IO.userError "cannot select integrated runtime")
  unless (← IO.FS.realPath binary) == (← IO.FS.realPath actual) do
    throw (IO.userError "integrated runtime path changed")
  let plugin := installRoot / "share/eggshell/codex-plugin"
  let launcher := plugin / "bin/eggshelld"
  IO.FS.createDirAll launcher.parent.get!
  let script := Install.pluginLauncher installRoot
  if ← launcher.pathExists then
    unless (← IO.FS.readFile launcher) == script do throw (IO.userError "integrated launcher changed")
  else
    IO.FS.writeFile launcher script
    IO.setAccessRights launcher {
      user := {read := true,write := true,execution := true}
      group := {read := true,execution := true}
      other := {read := true,execution := true}}
  let models := installRoot / "share/eggshell/minilm"
  if !(← models.pathExists) then
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",
      "/Users/ovm/.codex/experiments/eggshell/numerical-owned-20261024/prefix/share/eggshell/minilm",models.toString]}
    unless linked.exitCode == 0 do throw (IO.userError "cannot select installed numerical boundary")
  let environment := #[
    ("EGGSHELL_PREFIX",some installRoot.toString),("PLUGIN_ROOT",some plugin.toString),
    ("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),
    ("MKL_NUM_THREADS",some "1"),("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let plan : StudySeedChecks.Input := {
    runtime := ← StudyPrepare.artifact binary,handoffChars := 500000,
    pluginRoot := plugin.toString,pluginFiles := #[← StudyPrepare.artifact launcher],environment}
  let input := root / ((System.FilePath.mk directory).fileName.get! ++ ".input.json")
  unless !(← input.pathExists) do throw (IO.userError "preserve the integrated input descriptor")
  IO.FS.writeFile input (toJson plan).pretty
  StudySeedChecks.run input.toString directory
    (remote := true) (literal := true) (generic := true) (additionalCalls := 84)
