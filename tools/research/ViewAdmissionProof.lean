module
public import tools.research.SharedReadViews
@[expose] public section
namespace Eggshell.Research.ViewAdmissionProof
open Eggshell.Synapses.SharedReadViews

theorem reap_keeps_borrower (state : State) (token : String) (view : View) (now : Nat)
    (found : state.active[token]? = some view) (borrowed : 0 < view.borrowers) :
    (state.reap now).active[token]? = some view := by
  simp [State.reap,found,borrowed]

theorem reap_released_idle (state : State) (token : String) (view : View) (now : Nat)
    (found : state.active[token]? = some view) (idle : view.borrowers = 0)
    (released : view.released = true) : (state.reap now).active[token]? = none := by
  simp [State.reap,found,idle,released]

#print axioms reap_keeps_borrower
#print axioms reap_released_idle
#print axioms Checked.byte_bound
#print axioms Checked.lease_bound
#print axioms View.project_private_lifetime
#print axioms View.project_shared_image
end Eggshell.Research.ViewAdmissionProof
