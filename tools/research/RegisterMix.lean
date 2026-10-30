module
public import Std
@[expose] public section

namespace Eggshell.Research.RegisterMix

@[inline] def rotate (word : UInt32) (count : Nat) : UInt32 :=
  (word >>> count.toUInt32) ||| (word <<< (32-count).toUInt32)

def update (words : Array UInt32) (index : Nat) (change : UInt32 → UInt32) : Array UInt32 :=
  words.set! index (change words[index]!)

/-- The existing mix, including its behavior on malformed lane indices. -/
def reference (state : Array UInt32) (a b c d mx my : Nat) : Array UInt32 :=
  let state := update state a fun value => value+state[b]!+state[mx]!
  let state := state.set! d (rotate (state[d]! ^^^ state[a]!) 16)
  let state := update state c fun value => value+state[d]!
  let state := state.set! b (rotate (state[b]! ^^^ state[c]!) 12)
  let state := update state a fun value => value+state[b]!+state[my]!
  let state := state.set! d (rotate (state[d]! ^^^ state[a]!) 8)
  let state := update state c fun value => value+state[d]!
  state.set! b (rotate (state[b]! ^^^ state[c]!) 7)

def valid (size a b c d mx my : Nat) : Prop :=
  a < size ∧ b < size ∧ c < size ∧ d < size ∧ mx < size ∧ my < size ∧
  a ≠ b ∧ a ≠ c ∧ a ≠ d ∧ b ≠ c ∧ b ≠ d ∧ c ≠ d ∧
  a ≠ mx ∧ b ≠ mx ∧ c ≠ mx ∧ d ≠ mx ∧
  a ≠ my ∧ b ≠ my ∧ c ≠ my ∧ d ≠ my

instance (size a b c d mx my : Nat) : Decidable (valid size a b c d mx my) :=
  by unfold valid; infer_instance

/-- Read immutable lanes once, compute in registers, then write each lane once. -/
@[inline] def registers (state : Array UInt32) (a b c d mx my : Nat) : Array UInt32 :=
  let av := state[a]!+state[b]!+state[mx]!
  let dv := rotate (state[d]! ^^^ av) 16
  let cv := state[c]!+dv
  let bv := rotate (state[b]! ^^^ cv) 12
  let av := av+bv+state[my]!
  let dv := rotate (dv ^^^ av) 8
  let cv := cv+dv
  let bv := rotate (bv ^^^ cv) 7
  ((state.set! a av).set! b bv).set! c cv |>.set! d dv

theorem registers_exact (state : Array UInt32) (a b c d mx my : Nat)
    (safe : valid state.size a b c d mx my) :
    registers state a b c d mx my = reference state a b c d mx my := by
  rcases safe with ⟨ha,hb,hc,hd,hmx,hmy,hab,hac,had,hbc,hbd,hcd,
    hamx,hbmx,hcmx,hdmx,hamy,hbmy,hcmy,hdmy⟩
  have hba : b ≠ a := Ne.symm hab
  have hca : c ≠ a := Ne.symm hac
  have hda : d ≠ a := Ne.symm had
  have hcb : c ≠ b := Ne.symm hbc
  have hdb : d ≠ b := Ne.symm hbd
  have hdc : d ≠ c := Ne.symm hcd
  generalize hleft : registers state a b c d mx my = left
  generalize hright : reference state a b c d mx my = right
  apply Array.ext
  · rw [← hleft,← hright]
    simp [registers,reference,update]
  · intro i hi hj
    rw [← getElem!_pos left i hi,← getElem!_pos right i hj]
    rw [← hleft,← hright]
    clear hi hj hleft hright left right
    by_cases ia : i = a
    · subst i
      simp_all [registers,reference,update]
    · have ai : a ≠ i := Ne.symm ia
      by_cases ib : i = b
      · subst i
        simp_all [registers,reference,update]
      · have bi : b ≠ i := Ne.symm ib
        by_cases ic : i = c
        · subst i
          simp_all [registers,reference,update]
        · have ci : c ≠ i := Ne.symm ic
          by_cases id : i = d
          · subst i
            simp_all [registers,reference,update]
          · have di : d ≠ i := Ne.symm id
            simp_all [registers,reference,update,Array.getElem!_eq_getD]

@[inline] def optimized (state : Array UInt32) (a b c d mx my : Nat) : Array UInt32 :=
  if valid state.size a b c d mx my then registers state a b c d mx my
  else reference state a b c d mx my

/-- A total refinement: no assumption is imposed on existing callers. -/
theorem optimized_exact (state : Array UInt32) (a b c d mx my : Nat) :
    optimized state a b c d mx my = reference state a b c d mx my := by
  unfold optimized
  split
  · exact registers_exact state a b c d mx my ‹_›
  · rfl

end Eggshell.Research.RegisterMix
