import Eggshell.Install
import Lean.Data.Json.Parser

open Lean
namespace Eggshell.Research.StudyLaunchers

/-- A launcher digest alone does not bind its executable: copied scripts may
still contain a different installation's absolute path. Check the exact product
generator at the admitted prefix before starting any DB or hook process. -/
def verify (installation : System.FilePath) : IO Unit := do
  unless installation.isAbsolute do throw (IO.userError "absolute study installation required")
  let expected := Eggshell.Install.pluginLauncher installation
  for name in ["egg","eggshelld"] do
    let path := installation/"plugins/eggshell/bin"/name
    unless (← IO.FS.readFile path) == expected do
      throw (IO.userError s!"{path}: launcher does not select its admitted runtime")
  unless (← IO.FS.readFile (installation/"bin/egg")) == Eggshell.Install.commandLauncher do
    throw (IO.userError "command launcher differs from its product generator")
  unless ← (installation/"libexec/eggshell").pathExists do
    throw (IO.userError "admitted launcher has no native executable")

def bind (installation inherited : System.FilePath) (report : System.FilePath) : IO Unit := do
  unless installation.isAbsolute && inherited.isAbsolute && installation != inherited && !(← report.pathExists) do
    throw (IO.userError "fresh isolated launcher binding required")
  let expected := Eggshell.Install.pluginLauncher inherited
  for name in ["egg","eggshelld"] do
    unless (← IO.FS.readFile (installation/"plugins/eggshell/bin"/name)) == expected do
      throw (IO.userError "inherited launcher differs from its declared product generator")
  let rejected ← try verify installation; pure false catch _ => pure true
  unless rejected do throw (IO.userError "misbound launcher negative control did not fail")
  for name in ["egg","eggshelld"] do
    Eggshell.Install.writeExecutable (installation/"plugins/eggshell/bin"/name)
      (Eggshell.Install.pluginLauncher installation)
  verify installation
  IO.FS.writeFile report (Json.mkObj [("installation",toJson installation.toString),
    ("inheritedInstallation",toJson inherited.toString),("oldBindingRejected",toJson rejected),
    ("actualProductGeneratorUsed",toJson true),("newBindingVerified",toJson true),
    ("productionCoreChanged",toJson false)]).compress

def cliMain : List String → IO Unit
  | ["bind",installation,inherited,report] =>
      Eggshell.Research.StudyLaunchers.bind (.mk installation) (.mk inherited) (.mk report)
  | ["verify",installation] => Eggshell.Research.StudyLaunchers.verify (.mk installation)
  | _ => throw (IO.userError "StudyLaunchers bind INSTALLATION INHERITED REPORT | verify INSTALLATION")

end Eggshell.Research.StudyLaunchers
