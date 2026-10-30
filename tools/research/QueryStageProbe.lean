module
public import Lean.Data.Json.FromToJson

@[expose] public section
namespace Eggshell.Research.QueryStageProbe

/-- Diagnostic-only native wall-clock observation. Its logical value is the
unchanged thunk. It does not manufacture data, alter a budget or cache a plan. -/
def record (name : String) (started stopped : Nat) : IO Unit := do
  try
    if let some path ← IO.getEnv "EGGSHELL_QUERY_STAGE_LOG" then
      let output ← IO.FS.Handle.mk (.mk path) .append
      output.putStr ((Lean.Json.mkObj [("stage",Lean.toJson name),("startedNs",Lean.toJson started),
        ("stoppedNs",Lean.toJson stopped),("elapsedNs",Lean.toJson (stopped-started))]).compress ++ "\n")
      output.flush
  catch _ => pure ()

unsafe def measureNative {α : Type} (name : String) (action : Unit → α) : α :=
  unsafeBaseIO do
    let started ← IO.monoNanosNow
    -- Force evaluation through an IO effect before the second clock sample.
    -- A pure let may be floated after both clock reads by the compiler.
    let result ← IO.mkRef (action ())
    let stopped ← IO.monoNanosNow
    let _ ← (record name started stopped).toBaseIO
    result.get

@[noinline, implemented_by measureNative]
def measure {α : Type} (_name : String) (action : Unit → α) : α := action ()

theorem measure_exact {α : Type} (name : String) (action : Unit → α) :
    measure name action = action () := rfl

def observe (name : String) (action : IO α) : IO α := do
  let started ← IO.monoNanosNow
  let result ← action
  let stopped ← IO.monoNanosNow
  record name started stopped
  return result

end Eggshell.Research.QueryStageProbe
