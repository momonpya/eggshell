module
import all Eggshell.HookCommand
import all Eggshell.Daemon
import all Eggshell.Handoff
import Lean
open Lean Eggshell.Plugin
#print axioms Daemon.valid_hook_reply_is_preserved
#print axioms Daemon.absent_hook_reply_is_incomplete
#print axioms Daemon.invalid_hook_reply_is_incomplete
theorem pending_notice_unchanged : pendingSearch.text = pendingSearchText := rfl
theorem full_entry_uses_same_supervisor (fast : Bool) :
    Daemon.hookClient fast = (do Daemon.Command.hookClient (← IO.appPath) fast) := rfl
theorem full_rpc_uses_same_supervisor (kind : String) (input : Json) (deadline : Nat) :
    Daemon.boundedRpc kind input deadline = (do Daemon.Command.boundedRpc (← IO.appPath) kind input deadline) := rfl
#print axioms pending_notice_unchanged
#print axioms full_entry_uses_same_supervisor
#print axioms full_rpc_uses_same_supervisor
run_meta do
  let env ← getEnv
  let mut pending := [``Daemon.Command.hookClient]
  let mut seen : NameSet := {}
  while let name :: rest := pending do
    pending := rest
    if seen.contains name then continue
    seen := seen.insert name
    let text := name.toString
    if ["Eggshell.Persistence.","Eggshell.DB.","Eggshell.Plugin.Worker.","Eggshell.Plugin.Publication.",
        "Eggshell.SearchProvider.","Eggshell.Numerical."].any (fun part => text.startsWith part) ||
        [``Std.Mutex.atomically,``Eggshell.FileSystem.atomicExistingBytes].contains name then
      throwError "Small hook supervisor reaches backend state: {name}"
    if let some decl := env.find? name then
      if let some body := decl.value? then pending := body.getUsedConstants.toList++pending
  logInfo m!"Small supervisor: {seen.size} declarations; no DB, work graph, model, publication service or shared mutex."
