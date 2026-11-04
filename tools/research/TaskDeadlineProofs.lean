module
import all Eggshell.TaskDeadline
import all Eggshell.DaemonWire
import all Eggshell.Daemon
import all Eggshell.SemanticMatcher
import all Eggshell.Numerical
import Lean

open Lean
run_meta do
  for (name,required,forbidden) in [
      (``Eggshell.TaskDeadline.wait,#[``Std.Async.Selectable.one,``Eggshell.TaskDeadline.ensureLive],#[``IO.sleep,``IO.waitAny]),
      (``Eggshell.TaskDeadline.event,#[``IO.mapTask],#[``IO.asTask]),
      (``Eggshell.Plugin.Daemon.receiveExactly,#[``Eggshell.TaskDeadline.wait],#[]),
      (``Eggshell.Plugin.Daemon.sendFrameBefore,#[``Eggshell.TaskDeadline.run],#[]),
      (``Eggshell.Plugin.Daemon.connectBefore,#[``Eggshell.TaskDeadline.run],#[]),
      (``Eggshell.Plugin.Daemon.readyEndpoint,#[``Eggshell.Plugin.Daemon.running],#[``Eggshell.Plugin.Daemon.exchange]),
      (``Eggshell.SemanticMatcher.withResponseDeadline,#[``Eggshell.TaskDeadline.wait,``Eggshell.SemanticMatcher.stop,``IO.wait],#[``IO.sleep,``IO.waitAny]),
      (``Eggshell.Numerical.Backend.encode,#[``Eggshell.Numerical.Backend.modelGate],#[``Eggshell.Numerical.Backend.scoreGate]),
      (``Eggshell.Numerical.Backend.scoreBlocks,#[``Eggshell.Numerical.Backend.scoreGate],#[``Eggshell.Numerical.Backend.modelGate])] do
    let env ← getEnv
    let executable := (Compiler.getImplementedBy? env name).getD name
    let some info := env.find? (Compiler.mkUnsafeRecName executable) <|> env.find? executable
      | throwError "missing executable owner: {name}"
    let some body := info.value? | throwError "missing actual task/pipe owner: {name}"
    let used := body.getUsedConstants
    for dependency in required do
      unless used.contains dependency do throwError "missing {dependency}: {name}; actual callees {used.toList}"
    for dependency in forbidden do
      if used.contains dependency then throwError "unexpected dependency {dependency}: {name}"

#print axioms Eggshell.TaskDeadline.expired_refused
#print axioms Eggshell.TaskDeadline.cancelled_refused
#print axioms Eggshell.SemanticMatcher.process_handle_has_no_stdin
