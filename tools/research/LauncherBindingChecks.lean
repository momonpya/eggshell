import tools.research.StudyAdmission

open Lean Eggshell Eggshell.Research

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "LauncherBindingChecks NEW-DIRECTORY")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "new absolute fixture directory required"
  let plugin := root / "plugin"
  IO.FS.createDirAll (plugin / "bin")
  let installRoot := root / "space and 'quote"
  let runtime : StudyAdmission.Artifact := ⟨(installRoot / "libexec/eggshell").toString,"not-executed"⟩
  let valid := Install.pluginLauncher installRoot
  for name in #["egg","eggshelld"] do IO.FS.writeFile (plugin / "bin" / name) valid
  StudyAdmission.verifyPluginRuntime runtime plugin.toString
  let mut rejected := #[]
  for name in #["egg","eggshelld"] do
    IO.FS.writeFile (plugin / "bin" / name) (Install.pluginLauncher (root / "old-prefix"))
    let failure ← try
      StudyAdmission.verifyPluginRuntime runtime plugin.toString
      pure false
    catch _ => pure true
    check failure s!"old {name} launcher passed with a different runtime prefix"
    rejected := rejected.push name
    IO.FS.writeFile (plugin / "bin" / name) valid
  let failure ← try
    StudyAdmission.verifyPluginRuntime {runtime with path := (root / "eggshell").toString} plugin.toString
    pure false
  catch _ => pure true
  check failure "non-installed runtime path passed launcher binding"
  IO.FS.writeFile (root / "result.json") ((Json.mkObj [
    ("quotedPrefixAccepted",toJson true),("oldPrefixLaunchersRejected",toJson rejected),
    ("nonInstalledRuntimeRejected",toJson true),("answeringModelCalls",toJson (0 : Nat))]).compress ++ "\n")
