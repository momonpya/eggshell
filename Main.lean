module

public import Eggshell.Install
public import Eggshell.SearchProvider
public import Eggshell.Setup

@[expose] public section

def usage : String :=
  "usage: eggshell install codex\n       eggshell install runtime\n       eggshell setup [--project PATH] [--check]\n       eggshell uninstall codex\n       egg init\n       egg [COMMAND]"

def main (arguments : List String) : IO UInt32 := do
  match arguments with
  | ["import-graph", source, destination] =>
      Eggshell.Install.runCommand do
        Eggshell.Persistence.importGraphFile (.mk source) (.mk destination)
        pure "Imported graph into the page DB."
  | ["inspect-graph", source] =>
      Eggshell.Install.runCommand do
        let graph ← Eggshell.Persistence.load (.mk source)
        IO.ofExcept (Eggshell.Persistence.encode graph)
  | "search-provider" :: options => Eggshell.SearchProvider.run options
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
