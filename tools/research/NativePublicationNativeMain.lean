import tools.research.StudySeedChecks
import Eggshell.Install

open Lean Eggshell Eggshell.Research

/-- Exercise the actual product hooks, shell, save worker, index worker and
source-only recovery. This fixture has no answering-model credentials. -/
def main : IO UInt32 := do
  try
    let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/native-publication-20261025"
    let installRoot := root / "prefix"
    unless !(← installRoot.pathExists) do throw (IO.userError "keep the existing native fixture prefix")
    let binary := installRoot / "libexec/eggshell"
    IO.FS.createDirAll binary.parent.get!
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",(root / "product").toString,binary.toString]}
    unless copied.exitCode == 0 do throw (IO.userError "could not install reviewed candidate")
    let plugin := installRoot / "share/eggshell/codex-plugin"
    let launcher := plugin / "bin/eggshelld"
    IO.FS.createDirAll launcher.parent.get!
    IO.FS.writeFile launcher (Install.pluginLauncher installRoot)
    IO.setAccessRights launcher {
      user := {read := true,write := true,execution := true}
      group := {read := true,execution := true}
      other := {read := true,execution := true} }
    let model := "/Users/ovm/.codex/experiments/eggshell/numerical-owned-20261024/prefix/share/eggshell/minilm"
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",model,(installRoot / "share/eggshell/minilm").toString]}
    unless linked.exitCode == 0 do throw (IO.userError "could not select existing MiniLM boundary")
    let fixture := root / "native"
    let environment := #[
      ("EGGSHELL_PREFIX",some installRoot.toString),("EGGSHELL_DATA_ROOT",some (fixture / "data").toString),
      ("PLUGIN_ROOT",some plugin.toString),("LEAN_NUM_THREADS",some "1"),
      ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
      ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
    let input : StudySeedChecks.Input := {
      runtime := ⟨binary.toString,Sha256.hex (← IO.FS.readBinFile binary)⟩
      pluginRoot := plugin.toString
      pluginFiles := #[⟨launcher.toString,Sha256.hex (← IO.FS.readBinFile launcher)⟩]
      environment }
    let template := root / "native-input.json"
    IO.FS.writeFile template (toJson input).pretty
    StudySeedChecks.run template.toString fixture.toString true
    IO.println (← IO.FS.readFile (fixture / "result.json"))
    IO.println (← IO.FS.readFile (fixture / "recovery.json"))
    return 0
  catch error => IO.eprintln error.toString; return 1
