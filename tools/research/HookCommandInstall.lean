import Eggshell.Install
import tools.research.StudyLaunchers
open Lean Eggshell

/-- Only binds an isolated prefix copied from a declared, fixed parent. All
script bytes come from the candidate's ordinary product generator. -/
def main : List String → IO Unit
  | [directory,inherited,report] => do
      let root : System.FilePath := .mk directory
      let parent : System.FilePath := .mk inherited
      unless root.isAbsolute && parent.isAbsolute && root != parent &&
          !(← (System.FilePath.mk report).pathExists) && (← (root/"libexec/eggshell-hook").pathExists) do
        throw (IO.userError "fresh isolated hook-command binding required")
      for name in ["egg","eggshelld"] do
        let path := "plugins/eggshell/bin/"++name
        unless (← IO.FS.readFile (root/path)) == (← IO.FS.readFile (parent/path)) do
          throw (IO.userError "copied launcher differs from its declared parent")
        Install.writeExecutable (root/path) (Install.pluginLauncher root)
      Research.StudyLaunchers.verify root
      IO.FS.writeFile (.mk report) (Json.mkObj [("inheritedScriptMatched",toJson true),
        ("actualProductGeneratorUsed",toJson true),("smallHookRequired",toJson true),
        ("scope",toJson "isolated prefix only")]).compress
  | _ => throw (IO.userError "HookCommandInstall PREFIX PARENT REPORT")
