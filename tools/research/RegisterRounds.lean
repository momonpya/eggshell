module
public import tools.research.RegisterMix
@[expose] public section

namespace Eggshell.Research.RegisterRounds

structure Words where
  v0 : UInt32
  v1 : UInt32
  v2 : UInt32
  v3 : UInt32
  v4 : UInt32
  v5 : UInt32
  v6 : UInt32
  v7 : UInt32
  v8 : UInt32
  v9 : UInt32
  v10 : UInt32
  v11 : UInt32
  v12 : UInt32
  v13 : UInt32
  v14 : UInt32
  v15 : UInt32

@[inline] def Words.array (s : Words) : Array UInt32 :=
  #[s.v0,s.v1,s.v2,s.v3,s.v4,s.v5,s.v6,s.v7,s.v8,s.v9,s.v10,s.v11,s.v12,s.v13,s.v14,s.v15]

@[inline] def Words.read (s : Array UInt32) : Words :=
  ⟨s[0]!,s[1]!,s[2]!,s[3]!,s[4]!,s[5]!,s[6]!,s[7]!,s[8]!,s[9]!,s[10]!,s[11]!,s[12]!,s[13]!,s[14]!,s[15]!⟩

theorem Words.read_array (s : Array UInt32) (size : s.size = 16) : (Words.read s).array = s := by
  apply Array.ext
  · simp [Words.array,size]
  · intro i hi _
    have bound : i < 16 := by simpa [Words.array] using hi
    have cases : i=0 ∨ i=1 ∨ i=2 ∨ i=3 ∨ i=4 ∨ i=5 ∨ i=6 ∨ i=7 ∨
      i=8 ∨ i=9 ∨ i=10 ∨ i=11 ∨ i=12 ∨ i=13 ∨ i=14 ∨ i=15 := by omega
    rcases cases with h|h|h|h|h|h|h|h|h|h|h|h|h|h|h|h <;> subst i <;>
      simp_all [Words.array,Words.read]

noncomputable def Words.get (s : Words) (i : Fin 16) : UInt32 := match i.val with
  | 0 => s.v0 | 1 => s.v1 | 2 => s.v2 | 3 => s.v3
  | 4 => s.v4 | 5 => s.v5 | 6 => s.v6 | 7 => s.v7
  | 8 => s.v8 | 9 => s.v9 | 10 => s.v10 | 11 => s.v11
  | 12 => s.v12 | 13 => s.v13 | 14 => s.v14 | _ => s.v15

noncomputable def Words.set (s : Words) (i : Fin 16) (v : UInt32) : Words := match i.val with
  | 0 => {s with v0 := v} | 1 => {s with v1 := v}
  | 2 => {s with v2 := v} | 3 => {s with v3 := v}
  | 4 => {s with v4 := v} | 5 => {s with v5 := v}
  | 6 => {s with v6 := v} | 7 => {s with v7 := v}
  | 8 => {s with v8 := v} | 9 => {s with v9 := v}
  | 10 => {s with v10 := v} | 11 => {s with v11 := v}
  | 12 => {s with v12 := v} | 13 => {s with v13 := v}
  | 14 => {s with v14 := v} | _ => {s with v15 := v}

theorem lane_cases (i : Nat) (bound : i < 16) :
    i=0 ∨ i=1 ∨ i=2 ∨ i=3 ∨ i=4 ∨ i=5 ∨ i=6 ∨ i=7 ∨
    i=8 ∨ i=9 ∨ i=10 ∨ i=11 ∨ i=12 ∨ i=13 ∨ i=14 ∨ i=15 := by omega

theorem Words.get_array (s : Words) (i : Fin 16) : s.get i = s.array[i.val]! := by
  rcases i with ⟨i,bound⟩
  rcases lane_cases i bound with h|h|h|h|h|h|h|h|h|h|h|h|h|h|h|h <;> subst i <;>
    simp [Words.get,Words.array]

theorem Words.set_array (s : Words) (i : Fin 16) (v : UInt32) :
    (s.set i v).array = s.array.set! i.val v := by
  rcases i with ⟨i,bound⟩
  rcases lane_cases i bound with h|h|h|h|h|h|h|h|h|h|h|h|h|h|h|h <;> subst i <;>
    simp [Words.set,Words.array]

theorem array_left (xs ys : Array UInt32) (i : Nat) (inside : i < xs.size) :
    (xs++ys)[i]! = xs[i]! := by
  have joined : i < (xs++ys).size := by rw [Array.size_append]; omega
  rw [getElem!_pos (xs++ys) i joined,Array.getElem_append_left inside,getElem!_pos xs i inside]

theorem array_right (xs ys : Array UInt32) (i : Nat) (inside : i < ys.size) :
    (xs++ys)[xs.size+i]! = ys[i]! := by
  have joined : xs.size+i < (xs++ys).size := by rw [Array.size_append]; omega
  rw [getElem!_pos (xs++ys) (xs.size+i) joined,getElem!_pos ys i inside]
  simpa only [Nat.add_comm] using (Array.getElem_append_right' xs inside).symm

theorem joined_left (s m : Words) (i : Fin 16) :
    (s.array++m.array)[i.val]! = s.get i :=
  (array_left s.array m.array i.val i.isLt).trans (Words.get_array s i).symm

theorem joined_right (s m : Words) (i : Fin 16) :
    (s.array++m.array)[16+i.val]! = m.get i :=
  (array_right s.array m.array i.val i.isLt).trans (Words.get_array m i).symm

theorem joined_set (s m : Words) (i : Fin 16) (v : UInt32) :
    (s.set i v).array++m.array = (s.array++m.array).set! i.val v := by
  rw [Words.set_array]
  have inside : i.val < s.array.size := i.isLt
  simp only [Array.set!_eq_setIfInBounds,
    Array.setIfInBounds_append_left (xs := s.array) (ys := m.array) (i := i.val) (x := v) inside]

structure Quad where
  a : UInt32
  b : UInt32
  c : UInt32
  d : UInt32

@[irreducible,inline] def mix (a b c d mx my : UInt32) : Quad :=
  let a := a+b+mx
  let d := RegisterMix.rotate (d ^^^ a) 16
  let c := c+d
  let b := RegisterMix.rotate (b ^^^ c) 12
  let a := a+b+my
  let d := RegisterMix.rotate (d ^^^ a) 8
  let c := c+d
  let b := RegisterMix.rotate (b ^^^ c) 7
  ⟨a,b,c,d⟩

noncomputable def step (s m : Words) (a b c d mx my : Fin 16) : Words :=
  let q := mix (s.get a) (s.get b) (s.get c) (s.get d) (m.get mx) (m.get my)
  (((s.set a q.a).set b q.b).set c q.c).set d q.d

theorem step_join (s m : Words) (a b c d mx my : Fin 16)
    (different : a.val ≠ b.val ∧ a.val ≠ c.val ∧ a.val ≠ d.val ∧
      b.val ≠ c.val ∧ b.val ≠ d.val ∧ c.val ≠ d.val) :
    (step s m a b c d mx my).array++m.array =
      RegisterMix.reference (s.array++m.array) a.val b.val c.val d.val (16+mx.val) (16+my.val) := by
  have safe : RegisterMix.valid (s.array++m.array).size a.val b.val c.val d.val (16+mx.val) (16+my.val) := by
    simp only [RegisterMix.valid,Array.size_append,show s.array.size=16 from rfl,show m.array.size=16 from rfl]
    have ha := a.isLt
    have hb := b.isLt
    have hc := c.isLt
    have hd := d.isLt
    have hx := mx.isLt
    have hy := my.isLt
    omega
  rw [← RegisterMix.registers_exact _ _ _ _ _ _ _ safe]
  simp only [step,RegisterMix.registers,joined_left,joined_right,← joined_set]
  unfold mix
  rfl

noncomputable def round (s m : Words) : Words :=
  let s := step s m 0 4 8 12 0 1
  let s := step s m 1 5 9 13 2 3
  let s := step s m 2 6 10 14 4 5
  let s := step s m 3 7 11 15 6 7
  let s := step s m 0 5 10 15 8 9
  let s := step s m 1 6 11 12 10 11
  let s := step s m 2 7 8 13 12 13
  step s m 3 4 9 14 14 15

@[inline] def permute (m : Words) : Words :=
  ⟨m.v2,m.v6,m.v3,m.v10,m.v7,m.v0,m.v4,m.v13,m.v1,m.v11,m.v12,m.v5,m.v9,m.v14,m.v15,m.v8⟩

/-- The existing total array computation, retained as the specification.
The fields here are exactly the calls made by the linked Blake3 source. -/
def referenceRoundState (state message : Array UInt32) : Array UInt32 :=
  let words := state++message
  let words := RegisterMix.reference words 0 4 8 12 16 17
  let words := RegisterMix.reference words 1 5 9 13 18 19
  let words := RegisterMix.reference words 2 6 10 14 20 21
  let words := RegisterMix.reference words 3 7 11 15 22 23
  let words := RegisterMix.reference words 0 5 10 15 24 25
  let words := RegisterMix.reference words 1 6 11 12 26 27
  let words := RegisterMix.reference words 2 7 8 13 28 29
  RegisterMix.reference words 3 4 9 14 30 31

def referenceRound (state message : Array UInt32) : Array UInt32 :=
  (referenceRoundState state message).extract 0 16

def referencePermute (message : Array UInt32) : Array UInt32 :=
  (#[2,6,3,10,7,0,4,13,1,11,12,5,9,14,15,8] : Array Nat).map fun i => message[i]!

theorem round_join_exact (s m : Words) :
    (round s m).array++m.array = referenceRoundState s.array m.array := by
  unfold round
  rw [step_join _ _ 3 4 9 14 14 15 (by decide)]
  rw [step_join _ _ 2 7 8 13 12 13 (by decide)]
  rw [step_join _ _ 1 6 11 12 10 11 (by decide)]
  rw [step_join _ _ 0 5 10 15 8 9 (by decide)]
  rw [step_join _ _ 3 7 11 15 6 7 (by decide)]
  rw [step_join _ _ 2 6 10 14 4 5 (by decide)]
  rw [step_join _ _ 1 5 9 13 2 3 (by decide)]
  rw [step_join _ _ 0 4 8 12 0 1 (by decide)]
  rfl

theorem joined_extract (s m : Words) : (s.array++m.array).extract 0 16 = s.array := by
  apply Array.toList_inj.mp
  simp [Words.array]

theorem round_exact (s m : Words) : (round s m).array = referenceRound s.array m.array := by
  have result := congrArg (fun array : Array UInt32 => array.extract 0 16) (round_join_exact s m)
  simpa only [joined_extract,referenceRound] using result

theorem permute_exact (m : Words) : (permute m).array = referencePermute m.array := by
  simp [permute,Words.array,referencePermute]

/-- Concrete lanes avoid the generic record setters in the executable.
The step-by-step round above is used only as a proof specification. -/
@[noinline] def packedRound (s m : Words) : Words :=
  let c0 := mix s.v0 s.v4 s.v8 s.v12 m.v0 m.v1
  let c1 := mix s.v1 s.v5 s.v9 s.v13 m.v2 m.v3
  let c2 := mix s.v2 s.v6 s.v10 s.v14 m.v4 m.v5
  let c3 := mix s.v3 s.v7 s.v11 s.v15 m.v6 m.v7
  let d0 := mix c0.a c1.b c2.c c3.d m.v8 m.v9
  let d1 := mix c1.a c2.b c3.c c0.d m.v10 m.v11
  let d2 := mix c2.a c3.b c0.c c1.d m.v12 m.v13
  let d3 := mix c3.a c0.b c1.c c2.d m.v14 m.v15
  ⟨d0.a,d1.a,d2.a,d3.a,d3.b,d0.b,d1.b,d2.b,d2.c,d3.c,d0.c,d1.c,d1.d,d2.d,d3.d,d0.d⟩

theorem packedRound_exact (s m : Words) : packedRound s m = round s m := by
  simp only [packedRound,round,step,Words.get,Words.set]
  rfl

@[csimp] theorem round_packed_compiled : @round = @packedRound := by
  funext s m
  exact (packedRound_exact s m).symm

@[inline] def seven (s m : Words) : Words :=
  let s := round s m
  let m := permute m
  let s := round s m
  let m := permute m
  let s := round s m
  let m := permute m
  let s := round s m
  let m := permute m
  let s := round s m
  let m := permute m
  let s := round s m
  round s (permute m)

def referenceSeven (state message : Array UInt32) : Array UInt32 :=
  let first := referenceRound state message
  let secondMessage := referencePermute message
  let second := referenceRound first secondMessage
  let thirdMessage := referencePermute secondMessage
  let third := referenceRound second thirdMessage
  let fourthMessage := referencePermute thirdMessage
  let fourth := referenceRound third fourthMessage
  let fifthMessage := referencePermute fourthMessage
  let fifth := referenceRound fourth fifthMessage
  let sixthMessage := referencePermute fifthMessage
  let sixth := referenceRound fifth sixthMessage
  referenceRound sixth (referencePermute sixthMessage)

theorem seven_exact (s m : Words) : (seven s m).array = referenceSeven s.array m.array := by
  simp only [seven,round_exact,permute_exact,referenceSeven]

/-- One size check per compression pipeline; fixed lanes remain registers
through all rounds. Arbitrary array inputs retain their original behavior. -/
def optimized (state message : Array UInt32) : Array UInt32 :=
  if state.size == 16 && message.size == 16 then
    (seven (Words.read state) (Words.read message)).array
  else referenceSeven state message

theorem optimized_exact (state message : Array UInt32) :
    optimized state message = referenceSeven state message := by
  unfold optimized
  split
  · rename_i sized
    have sizes : state.size=16 ∧ message.size=16 := by simpa only [Bool.and_eq_true,beq_iff_eq] using sized
    rw [seven_exact,Words.read_array state sizes.1,Words.read_array message sizes.2]
  · rfl

#print axioms round_exact
#print axioms packedRound_exact
#print axioms round_packed_compiled
#print axioms seven_exact
#print axioms optimized_exact
end Eggshell.Research.RegisterRounds
