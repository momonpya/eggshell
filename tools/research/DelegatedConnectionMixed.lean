import tools.research.MixedChatChecks
import tools.research.StudyLaunchers
open Lean Eggshell
def main : List String → IO UInt32
  | ["bind",directory,inherited,report] => do
    let root : System.FilePath := .mk directory
    let parent : System.FilePath := .mk inherited
    unless root.isAbsolute && parent.isAbsolute && root != parent &&
        !(← (System.FilePath.mk report).pathExists) && (← (root/"libexec/eggshell-hook").pathExists) do
      throw (IO.userError "fresh isolated delegated binding required")
    for name in ["egg","eggshelld"] do
      let path := "plugins/eggshell/bin/"++name
      unless (← IO.FS.readFile (root/path)) == (← IO.FS.readFile (parent/path)) do
        throw (IO.userError "unrelated copied launcher changed")
      Install.writeExecutable (root/path) (Install.pluginLauncher root)
    Research.StudyLaunchers.verify root
    IO.FS.writeFile (.mk report) (Json.mkObj [("actualProductGeneratorUsed",toJson true),
      ("smallHookRequired",toJson true),("scope",toJson "isolated candidate prefix only")]).compress
    return 0
  | ["growth",input,directory] => do MixedChatChecks.run input directory true true true; return 0
  | ["inspect",directory,report] => do MixedChatChecks.inspect directory report; return 0
  | arguments => sourceRouteEngine arguments
