module

public import Lean
public import Std.Time.DateTime.Timestamp

@[expose] public section

namespace Eggshell.ObservationAge
open Lean

/-- An advisory interval after receipt, not a proof that external data is unchanged. -/
def monthMs : Nat := 30 * 24 * 60 * 60 * 1000

inductive Status where
  | recent | expired | unknown | clockSkew
  deriving BEq, ToJson, FromJson

structure Assessment where
  receivedUnixMs : Option Nat
  assessedUnixMs : Option Nat
  updateAfterMs : Nat
  status : Status
  deriving BEq, ToJson, FromJson

/-- Missing, invalid, or future receipt times cannot become recent. Zero TTL
expires immediately. Callers may supply an applicable provider interval. -/
def assess (now received : Option Nat) (interval : Nat := monthMs) : Assessment :=
  let status := match now, received with
    | some now, some received =>
      if now = 0 ∨ received = 0 then .unknown
      else if now < received then .clockSkew
      else if now - received < interval then .recent else .expired
    | _, _ => .unknown
  ⟨received, now, interval, status⟩

theorem recent_is_within_interval (now received interval : Nat)
    (recent : (assess (some now) (some received) interval).status = .recent) :
    received ≤ now ∧ now - received < interval := by
  simp only [assess] at recent
  split at recent <;> try contradiction
  split at recent <;> try contradiction
  split at recent <;> simp_all <;> omega

theorem expired_is_at_least_interval (now received interval : Nat)
    (expired : (assess (some now) (some received) interval).status = .expired) :
    received ≤ now ∧ interval ≤ now - received := by
  simp only [assess] at expired
  split at expired <;> try contradiction
  split at expired <;> try contradiction
  split at expired <;> simp_all <;> omega

theorem missing_receipt_is_unknown (now : Option Nat) (interval : Nat) :
    (assess now none interval).status = .unknown := by cases now <;> rfl

theorem assessment_preserves_receipt (now received : Option Nat) (interval : Nat) :
    (assess now received interval).receivedUnixMs = received := rfl

/-- Read the wall clock at ingress. Warm/replay must never call this to fill
an absent receipt time on an old observation. -/
def now : IO (Option Nat) := do
  try
    let millis := (← Std.Time.Timestamp.now).toMillisecondsSinceUnixEpoch.val
    return if millis > 0 then some millis.toNat else none
  catch _ => return none

end Eggshell.ObservationAge
