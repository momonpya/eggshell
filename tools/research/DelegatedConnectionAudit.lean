module
import all Eggshell.ProjectGateway
import all Eggshell.ProjectGatewayPeer
meta import Lean
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.Publication Gateway

def originalPin (endpoint : Daemon.Endpoint) (scope : Scope) (deadline : Nat) : IO Boundary := do
  let projects ← scope.readers.mapM fun (name,grant) => do
    let (cut,prepared) ← Client.pinPreparedProject endpoint grant deadline
    return (⟨name,cut,prepared⟩ : NamedCut)
  let boundary : Boundary := ⟨scope.key,projects⟩
  unless boundary.inScope scope do throw (IO.userError "project pin changed its complete scope")
  return boundary

/-- The preceding product's checked operation body, before executor injection. -/
def originalExecute (endpoint : Daemon.Endpoint) (scope : Scope) (operation : Operation) (deadline : Nat) : IO Json := do
  match operation with
  | .open _ => throw (IO.userError "project scope is immutable for this connection")
  | .pin => return toJson (← originalPin endpoint scope deadline)
  | .query boundary question =>
    unless boundary.inScope scope && question.policy == scope.descriptor.policy do
      throw (IO.userError "project query changed its selected scope or host policy")
    let requests := (boundary.projects.zip scope.readers).map fun (cut,(_,grant)) => (grant,cut.cut)
    return toJson (← Client.readProjectAdvice requests question (boundary.projects.map (·.prepared)) deadline)
  | .publish target boundary capsule =>
    let writer ← IO.ofExcept (writeFor scope target)
    unless boundary.inScope scope do throw (IO.userError "publication changed its complete read boundary")
    let some original := boundary.projects.find? (·.name == writer.name) |
      throw (IO.userError "publication omitted its write project cut")
    let mut inputs := #[]
    for (saved,(name,grant)) in boundary.projects.zip scope.readers do
      if name != writer.name then inputs := inputs.push (grant,saved.cut)
    return toJson (← Client.submitProject endpoint writer.grant original.cut capsule inputs deadline)

theorem executor_preserves_original_operations (endpoint : Daemon.Endpoint) (scope : Scope)
    (operation : Operation) (deadline : Nat) :
    execute endpoint scope operation deadline = originalExecute endpoint scope operation deadline := by
  cases operation <;> rfl

#print axioms executor_preserves_original_operations
#print axioms delegated_keeps_writer
#print axioms captured_keeps_writer
#print axioms boundary_keeps_all_projects
#print axioms readonly_rejects_publication
#print axioms publication_keeps_target

private partial def actionType (type : Expr) : Bool :=
  match type with
  | .forallE _ _ body _ => actionType body
  | .mdata _ body => actionType body
  | _ => [``IO,``BaseIO,``EIO].contains (type.getAppFn.constName?.getD .anonymous)

run_meta do
  let env ← getEnv
  let mut pending := [``directExchange]
  let mut seen : NameSet := {}
  while let name :: rest := pending do
    pending := rest
    if seen.contains name then continue
    seen := seen.insert name
    let label := name.toString
    if ["IO.Process.spawn","Std.Mutex.","Std.SharedMutex.","Eggshell.ProcessGroup.",
        "Eggshell.Plugin.Publication.Owned."].any (fun key => label.startsWith key) then
      throwError "direct client reaches a forbidden effect: {name}"
    if let some declaration := env.find? name then
      if label.startsWith "Eggshell.DB." && actionType declaration.type then
        throwError "direct client reaches source DB IO: {name}"
      if let some value := declaration.value? then pending := value.getUsedConstants.toList++pending
  Lean.logInfo m!"Direct client: {seen.size} declarations; no process spawn, application mutex, project ownership or source DB."
