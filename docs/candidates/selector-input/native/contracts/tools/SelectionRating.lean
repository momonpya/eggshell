module
public import tools.StableWinnerIndex
@[expose] public section
namespace SharedCoverage.Rating

structure Key (n : Nat) where
  index : Fin n
  gain : Nat
  charge : Nat
  deriving DecidableEq, BEq

def better (a b : Key n) : Bool :=
  if a.charge == 0 then b.charge != 0 || b.gain < a.gain
  else if b.charge == 0 then false
  else b.gain*a.charge < a.gain*b.charge

theorem fraction_trans {a b c x y z : Nat} (hx : 0 < x) (hy : 0 < y) (hz : 0 < z)
    (ab : b*x < a*y) (bc : c*y < b*z) : c*x < a*z := by
  have first : (c*x)*y < (b*x)*z := by
    simpa only [Nat.mul_assoc,Nat.mul_comm,Nat.mul_left_comm] using Nat.mul_lt_mul_of_pos_right bc hx
  have second := Nat.mul_lt_mul_of_pos_right ab hz
  have combined : (c*x)*y < (a*z)*y := by
    simpa only [Nat.mul_assoc,Nat.mul_comm,Nat.mul_left_comm] using Nat.lt_trans first second
  exact (Nat.mul_lt_mul_right hy).mp combined

theorem fraction_neg_trans {a b c x y z : Nat} (_hx : 0 < x) (hy : 0 < y) (_hz : 0 < z)
    (ab : ¬b*x < a*y) (bc : ¬c*y < b*z) : ¬c*x < a*z := by
  have first : (a*z)*y ≤ (b*z)*x := by
    simpa only [Nat.mul_assoc,Nat.mul_comm,Nat.mul_left_comm] using Nat.mul_le_mul_right z (Nat.le_of_not_gt ab)
  have second := Nat.mul_le_mul_right x (Nat.le_of_not_gt bc)
  have combined : (a*z)*y ≤ (c*x)*y := by
    simpa only [Nat.mul_assoc,Nat.mul_comm,Nat.mul_left_comm] using Nat.le_trans first second
  exact Nat.not_lt_of_ge (Nat.le_of_mul_le_mul_right combined hy)

theorem better_trans (a b c : Key n) (ab : better a b = true) (bc : better b c = true) :
    better a c = true := by
  by_cases az : a.charge = 0 <;> by_cases bz : b.charge = 0 <;> by_cases cz : c.charge = 0
  all_goals simp [better,az,bz,cz] at ab bc ⊢
  all_goals try omega
  exact fraction_trans (by omega) (by omega) (by omega) ab bc

theorem better_neg_trans (a b c : Key n) (ab : better a b ≠ true) (bc : better b c ≠ true) :
    better a c ≠ true := by
  by_cases az : a.charge = 0 <;> by_cases bz : b.charge = 0 <;> by_cases cz : c.charge = 0
  all_goals simp [better,az,bz,cz] at ab bc ⊢
  all_goals try omega
  exact Nat.le_of_not_gt (fraction_neg_trans (by omega) (by omega) (by omega)
    (Nat.not_lt_of_ge ab) (Nat.not_lt_of_ge bc))

def preference (n : Nat) : StableWinnerIndex.Preference (Key n) :=
  ⟨better,better_trans,better_neg_trans⟩

end SharedCoverage.Rating
