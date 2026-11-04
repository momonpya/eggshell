module
import all Eggshell.Daemon
import Lean
open Lean
run_meta do
  for (caller,required) in [
      (``Eggshell.Plugin.Daemon.hookRequest,#[``Eggshell.Plugin.Daemon.ensureBefore]),
      (``Eggshell.Plugin.Daemon.rpcClient,#[``Eggshell.Plugin.Daemon.ensureBefore]),
      (``Eggshell.Plugin.Daemon.ensureBefore,#[``Eggshell.Plugin.Daemon.Startup.check,``Eggshell.Plugin.Daemon.Startup.observeOrStart]),
      (``Eggshell.Plugin.Daemon.Startup.observeOrStart,#[``Eggshell.Plugin.Daemon.Startup.check,``Eggshell.Plugin.Daemon.Startup.ready?,``Eggshell.Plugin.Daemon.Startup.startOwned]),
      (``Eggshell.Plugin.Daemon.Startup.startOwned,#[``Eggshell.Plugin.Daemon.Startup.check,``Eggshell.Plugin.Daemon.spawn,``Eggshell.Plugin.Daemon.Startup.awaitReady]),
      (``Eggshell.Plugin.Daemon.Startup.awaitReady,#[``Eggshell.Plugin.Daemon.Startup.check]),
      (``Eggshell.Plugin.Daemon.Startup.check,#[``Eggshell.Plugin.Daemon.Startup.allowed])] do
    let env ← getEnv
    let actual := (Compiler.getImplementedBy? env caller).getD caller
    let some declaration := env.find? (Compiler.mkUnsafeRecName actual) <|> env.find? actual
      | throwError "missing startup implementation: {caller}"
    let some body := declaration.value? | throwError "missing startup body: {caller}"
    for dependency in required do
      unless body.getUsedConstants.contains dependency do throwError "{caller} lost {dependency}"
#print axioms Eggshell.Plugin.Daemon.Startup.expired
#print axioms Eggshell.Plugin.Daemon.Startup.cancelled
