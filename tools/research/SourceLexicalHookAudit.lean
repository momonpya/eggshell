import tools.research.StudySeedChecks
import Eggshell.SourceLexical
import Eggshell.Install
open Lean Eggshell Eggshell.Research

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

public def main (args : List String) : IO Unit := do
  let (runtime,destination,previous) ← match args with
    | [runtime,destination] => pure (runtime,destination,none)
    | [runtime,destination,source,workspace] => pure (runtime,destination,some (source,workspace))
    | _ => throw (IO.userError "checked runtime, fresh output root and optional unchanged source/workspace required")
  let root := System.FilePath.mk destination
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  check (!(← root.pathExists) && (← Paths.dataRoot) == root / "trial/data") "fresh fixture and explicit private root required"
  IO.FS.createDir root
  let installRoot := root / "prefix"
  let binary := installRoot / "libexec/eggshell"
  IO.FS.createDirAll binary.parent.get!
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",runtime,binary.toString]}
  check (copied.exitCode == 0) "could not install the audited runtime privately"
  let plugin := installRoot / "share/eggshell/codex-plugin"
  IO.FS.createDirAll (plugin / "bin")
  let mut pluginFiles := #[]
  for name in ["egg","eggshelld"] do
    let path := plugin / "bin" / name
    IO.FS.writeFile path (Install.pluginLauncher installRoot)
    IO.setAccessRights path {
      user := {read := true,write := true,execution := true}
      group := {read := true,execution := true}
      other := {read := true,execution := true}}
    pluginFiles := pluginFiles.push (← StudyPrepare.artifact path)
  let model := study / "prefix/share/eggshell/minilm"
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",model.toString,(installRoot / "share/eggshell/minilm").toString]}
  check (linked.exitCode == 0) "could not reuse the existing numerical boundary"
  let environment : Array (String × Option String) := #[
    ("CODEX_HOME",some (study / "account").toString),("TMPDIR",some (study / "tmp").toString),
    ("EGGSHELL_PREFIX",some installRoot.toString),("PLUGIN_ROOT",some plugin.toString),
    ("EGGSHELL_DATA_ROOT",some (root / "trial/data").toString),
    ("HF_HUB_OFFLINE",some "1"),("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),
    ("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let plan : StudySeedChecks.Input := {
    runtime := ← StudyPrepare.artifact binary
    pluginRoot := plugin.toString
    pluginFiles
    environment}
  let template := root / "input.json"
  IO.FS.writeFile template (toJson plan).pretty
  let sourcePath ← match previous with
    | none => do
      StudySeedChecks.run template.toString (root / "trial").toString
        (remote := true) (literal := true) (generic := true)
      pure (root / "trial/work.egg")
    | some (source,workspace) => do
      IO.FS.createDir (root / "trial")
      StudySeedChecks.recall plan (.mk workspace) (.mk source) environment (some (root / "trial"))
      pure (.mk source)
  let source ← DB.PageMap.pin sourcePath
  let primary ← SourceLexical.status source
  let mut legacyDirectories := #[]
  for storage in [DB.Sidecar.Storage.database,.user] do
    let path ← RetrievalResearch.Index.path source storage
    check (!(← path.pathExists)) "ordinary native lifecycle constructed a duplicate lexical index"
    legacyDirectories := legacyDirectories.push path.toString
  IO.FS.writeFile (root / "source-lexical.json") (Json.mkObj [
    ("source",toJson source.head),("primary",toJson primary),
    ("duplicateLexicalDirectoriesAbsent",toJson legacyDirectories),
    ("actualNativeHookLifecycle",toJson previous.isNone),
    ("unchangedSourceRecall",toJson previous.isSome),("realMcpServerUsed",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("eightyUserLoadMeasured",toJson false),
    ("adopted",toJson false)]).pretty
  IO.println "Actual hook lifecycle, source-only recovery and readonly recall passed without a duplicate lexical index"
