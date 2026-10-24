module

public import Lean

@[expose] public section

namespace Eggshell.Deadline

def minimumDeliveryMs : Nat := 250

/-- Verification shares the existing absolute deadline. Reserve at least half
of the remaining interval and, when available, a small publication floor.
When only that floor remains, do not start another verification probe. -/
def verification (now deadline : Nat) : Nat :=
  min deadline (now + min ((deadline-now)/2) (deadline-now-minimumDeliveryMs))

theorem never_extends (now deadline : Nat) : verification now deadline ≤ deadline :=
  Nat.min_le_left _ _

theorem reserves_delivery (now deadline : Nat) (live : now ≤ deadline) :
    (deadline-now)/2 ≤ deadline-verification now deadline := by
  simp only [verification]
  omega

theorem reserves_minimum (now deadline : Nat) (live : now ≤ deadline) :
    min minimumDeliveryMs (deadline-now) ≤ deadline-verification now deadline := by
  simp only [verification,minimumDeliveryMs]
  omega

theorem expired_stays_expired (now deadline : Nat) (expired : deadline ≤ now) :
    verification now deadline = deadline := by
  simp only [verification]
  omega

end Eggshell.Deadline
