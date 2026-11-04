module

import all Eggshell.HookFrontend
import all Eggshell.Daemon
import all Eggshell.Persistence
import Lean

open Lean
run_meta do
  for (name,required) in [
      (``Eggshell.Plugin.HookFrontend.run,
        #[``Eggshell.HookBudget.admit,``Eggshell.HookBudget.canStart,``IO.wait]),
      (``Eggshell.Plugin.HookFrontend.Session.refresh,
        #[``Eggshell.Plugin.flushDeferred,``Eggshell.Plugin.flushIndexesResult]),
      (``Eggshell.Plugin.Daemon.hookRequest,#[``Eggshell.Plugin.Daemon.chatClock]),
      (``Eggshell.Plugin.Daemon.run.runOwned,#[``Eggshell.Plugin.HookFrontend.run]),
      (``Eggshell.Plugin.Daemon.exchangeBefore,#[``Eggshell.Plugin.Daemon.connectBefore,
        ``Eggshell.Plugin.Daemon.sendFrameBefore,``Eggshell.Plugin.Daemon.receiveFrameBefore]),
      (``Eggshell.Plugin.Publication.Client.resolve,#[``IO.checkCanceled]),
      (``Eggshell.Persistence.acquireLock,#[``Eggshell.Persistence.acquireLock._f]),
      (``Eggshell.Persistence.acquireLock._f,#[``IO.checkCanceled]),
      (``Eggshell.Plugin.Daemon.shutdown,#[``Eggshell.Persistence.withLockWithin,
        ``Eggshell.Plugin.Daemon.awaitStopped]),
      (``Eggshell.Plugin.Daemon.awaitStopped,#[``IO.Process.Child.tryWait])] do
    let info ← getConstInfo name
    let some body := info.value? | throwError "missing actual frontend implementation: {name}"
    let used := body.getUsedConstants
    for dependency in required do
      unless used.contains dependency do
        throwError "frontend path missing {dependency}: {name}; actual callees: {used.toList}"

#print axioms Eggshell.HookBudget.admitted_bounds
#print axioms Eggshell.HookBudget.full_refused
#print axioms Eggshell.HookBudget.overflow_refused
#print axioms Eggshell.HookBudget.active_session_refused
