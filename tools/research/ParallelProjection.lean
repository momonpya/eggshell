module
public import Eggshell.TaskDeadline
@[expose] public section
namespace Eggshell.Research.ParallelProjection

/-- The projection is pure and owns references to immutable inputs. The caller
continues IO on its existing actor; the ordinary CPU pool only evaluates this
projection. The callback never runs on the CPU pool. -/
def withJob (project : Unit → α) (deadline : Nat)
    (action : Task (Except IO.Error α) → IO β) : IO (β × α) := do
  TaskDeadline.ensureLive deadline
  let task ← IO.asTask (do
    TaskDeadline.ensureLive deadline
    let value ← IO.mkRef (project ())
    value.get) .default
  try
    let result ← action task
    let projected ← TaskDeadline.wait task deadline
    return (result,projected)
  finally
    unless ← IO.hasFinished task do IO.cancel task
    discard <| IO.wait task

def alongside (project : Unit → α) (deadline : Nat) (action : IO β) : IO (β × α) :=
  withJob project deadline (fun _ => action)

/-- Pure projection is unchanged. This is not a theorem about OS scheduling
or cancellation latency; the native lifecycle controls check those boundaries. -/
def paired (left : Unit → α) (right : Unit → β) (_ : Unit) : α × β := (left (),right ())

theorem paired_exact (left : Unit → α) (right : Unit → β) :
    paired left right () = (left (),right ()) := rfl

#print axioms paired_exact
end Eggshell.Research.ParallelProjection
