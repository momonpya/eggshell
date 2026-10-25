import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

/-- Plain reviewed modules form the candidate. No chain of source replacements
is executed, and the parent checkout is never edited through inherited links. -/
def main : IO Unit := do
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/native-publication-20261025"
  let parent := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/worker-lifecycle-20261025"
  unless !(← root.pathExists) do throw (IO.userError "keep existing native publication candidate")
  IO.FS.createDir root
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(parent / "checkout").toString,(root / "checkout").toString]}
  unless copied.exitCode == 0 do throw (IO.userError "native publication clone failed")
  let modules := #["Eggshell.Persistence","Eggshell.PluginModel","Eggshell.SynapseProvenance",
    "Eggshell.SynapseJournal","Eggshell.SynapseLive","Eggshell.PluginHooks","Eggshell.NativePublication",
    "Eggshell.PluginCli","Eggshell.Worker"]
  for name in modules do
    let relative := name.replace "." "/" ++ ".lean"
    let source ← IO.FS.readFile (project / "tools/research/native-publication" / relative)
    let destination := root / "checkout" / relative
    if ← destination.pathExists then
      if (← destination.symlinkMetadata).type == .symlink then IO.FS.removeFile destination
    IO.FS.writeFile destination source
  let settings ← IO.ofExcept (Json.parse (← IO.FS.readFile (parent / "build-plan.json")))
  let inherited ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  let settings := settings.setObjVal! "core" (toJson (root / "checkout").toString)
    |>.setObjVal! "output" (toJson (root / "build").toString)
    |>.setObjVal! "parents" (toJson (inherited.push parent.toString))
    |>.setObjVal! "force" (toJson (modules ++ #["Eggshell.Warm","Eggshell.Daemon","Main"]))
  IO.FS.writeFile (root / "build-plan.json") (settings.pretty ++ "\n")
  IO.println "prepared source and native origin in one publication"
