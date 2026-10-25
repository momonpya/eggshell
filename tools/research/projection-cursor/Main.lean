
import Eggshell.Install
import Eggshell.SearchProvider
import Eggshell.KeyedSearchProvider
import Eggshell.Numerical
import Eggshell.Setup
import tools.research.NativeHookAudit
import DirectProjectionAudit


def usage : String :=
  "usage: eggshell install codex\n       eggshell install runtime\n       eggshell setup [--project PATH] [--check]\n       eggshell uninstall codex\n       egg init\n       egg [COMMAND]"

def main (arguments : List String) : IO UInt32 := do
  match arguments with
  | ["direct-projection-fixture",path] =>
      Eggshell.DirectProjectionAudit.fixture (.mk path)
      return 0
  | ["direct-projection-scale",database,root,output] =>
      Eggshell.DirectProjectionAudit.scale (.mk database) (.mk root) (.mk output)
      return 0
  | ["stage-native-payload",path] =>
      Eggshell.DirectProjectionAudit.stage (.mk path)
      return 0
  | "native-hook-audit" :: args => do
      HookScaleRun.command args
      return 0
  | ["codex-numerical-daemon",model,models,python] =>
      Eggshell.Numerical.serve ⟨model,.mk models,.mk python⟩
  | ["codex-numerical-client",model,models,python] =>
      Eggshell.Numerical.proxy ⟨model,.mk models,.mk python⟩
  | _ => Eggshell.Numerical.withDefaultKeeper (drainMs := if arguments.head? == some "codex-daemon" ||
      arguments.take 2 == ["egg","warm"] then 1000 else 0) do
      match arguments with
      | ["inspect-equality", receipt] =>
          Eggshell.Install.runCommand do
            pure ((← Eggshell.SelectionAudit.inspectHook receipt).compress)
      | ["import-graph", source, destination] =>
          Eggshell.Install.runCommand do
            Eggshell.Persistence.importGraphFile (.mk source) (.mk destination)
            pure "Imported graph into the page DB."
      | ["inspect-graph", source] =>
          Eggshell.Install.runCommand do
            let graph ← Eggshell.Persistence.load (.mk source)
            IO.ofExcept (Eggshell.Persistence.encode graph)
      | "search-provider" :: options => Eggshell.SearchProvider.run options
      | "keyed-search-provider" :: options => Eggshell.KeyedSearchProvider.run options
      | "setup" :: options => Eggshell.Setup.command options
      | ["codex-hook"] => Eggshell.Plugin.Daemon.hookClient
      | ["codex-hook", "fast"] => Eggshell.Plugin.Daemon.hookClient true
      | ["codex-hook-child", deadline, receipt] => do
          let some deadline := deadline.toNat? | return 1
          Eggshell.Plugin.Daemon.hookProcess deadline receipt
      | ["codex-daemon", "shutdown"] => do
          Eggshell.Plugin.Daemon.shutdown
          pure 0
      | ["codex-daemon", session] => Eggshell.Plugin.Daemon.run session
      | ["codex-worker", role] => Eggshell.Plugin.Worker.run role
      | ["codex-rpc", kind] => Eggshell.Plugin.Daemon.rpcClient kind
      | ["egg", "init"] => Eggshell.Install.initCommand
      | ["egg", "uninstall", "codex"] => Eggshell.Install.command false
      | "egg" :: rest => Eggshell.Plugin.eggControl rest
      | ["init"] => Eggshell.Install.initCommand
      | ["install", "runtime"] => Eggshell.Install.runCommand Eggshell.Install.installRuntime
      | ["install", "codex"] => Eggshell.Install.command true
      | ["uninstall", "codex"] => Eggshell.Install.command false
      | _ =>
          if (← IO.appPath).fileName = some "egg" then
            Eggshell.Plugin.eggControl arguments
          else if arguments.isEmpty || arguments = ["--help"] || arguments = ["-h"] then
            IO.println usage
            pure 0
          else
            IO.eprintln usage
            pure 1
