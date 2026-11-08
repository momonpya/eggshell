module
public import tools.ByteBudgetCache
@[expose] public section

namespace Eggshell.Research.WeighedCache
open ByteBudgetCache
variable {κ α : Type} [BEq κ] [Hashable κ] [LawfulBEq κ]

def charges (weight : κ → α → Nat) (slots : Array (Slot κ α)) : Prop :=
  ∀ slot ∈ slots,slot.charge = weight slot.key slot.value

theorem inserted_charges (weight : κ → α → Nat) (generation : Generation κ α limit)
    (prior : charges weight generation.slots) (slot : Slot κ α)
    (correct : slot.charge = weight slot.key slot.value)
    (next : Generation κ α limit) (inserted : generation.insert? slot = some next) :
    charges weight next.slots := by
  unfold Generation.insert? at inserted
  split at inserted
  · cases inserted
    intro item member
    obtain old | rfl := Array.mem_push.mp member
    · exact prior item old
    · exact correct
  · contradiction

/-- A byte budget is tied to the retained values themselves. A caller cannot
put a large value in a zero-charge slot and still construct this cache. -/
structure Cache (κ α : Type) [BEq κ] [Hashable κ] (limit : Nat) (weight : κ → α → Nat) where
  state : ByteBudgetCache.Cache κ α limit := {}
  recent : charges weight state.recent.slots := by simp [Eggshell.Research.WeighedCache.charges]
  previous : charges weight state.previous.slots := by simp [Eggshell.Research.WeighedCache.charges]

def Cache.find? (cache : Cache κ α limit weight) (key : κ) : Option α :=
  cache.state.find? key

def Cache.insert (cache : Cache κ α limit weight) (key : κ) (value : α) : Cache κ α limit weight :=
  let slot : Slot κ α := ⟨key,value,weight key value⟩
  match recent : cache.state.recent.insert? slot with
  | some next => ⟨{cache.state with recent := next},inserted_charges weight _ cache.recent slot rfl _ recent,cache.previous⟩
  | none => match fresh : ({} : Generation κ α limit).insert? slot with
    | some next => ⟨⟨next,cache.state.recent⟩,
        inserted_charges weight _ (by simp [charges]) slot rfl _ fresh,cache.recent⟩
    | none => cache

theorem Cache.insert_raw (cache : Cache κ α limit weight) (key : κ) (value : α) :
    (cache.insert key value).state = cache.state.touch ⟨key,value,weight key value⟩ := by
  unfold insert ByteBudgetCache.Cache.touch
  dsimp only
  split <;> simp_all
  split <;> simp_all

theorem Cache.insert_find (cache : Cache κ α limit weight) (key : κ) (value : α)
    (fits : weight key value ≤ limit) : (cache.insert key value).find? key = some value := by
  rw [find?,insert_raw]
  unfold ByteBudgetCache.Cache.find?
  rw [ByteBudgetCache.Cache.touch_recent _ _ fits]
  rfl

def weightOf (weight : κ → α → Nat) (slots : Array (Slot κ α)) : Nat :=
  slots.foldl (fun sum slot => sum+weight slot.key slot.value) 0

omit [BEq κ] [Hashable κ] [LawfulBEq κ] in
theorem exact_weight (weight : κ → α → Nat) (slots : Array (Slot κ α))
    (correct : charges weight slots) : weightOf weight slots = allocated slots := by
  have equal : slots.map (fun slot => weight slot.key slot.value) = slots.map (·.charge) := by
    apply Array.map_congr_left
    intro slot member
    exact (correct slot member).symm
  unfold weightOf allocated
  have first := Array.foldl_map (xs := slots) (f := fun slot => weight slot.key slot.value)
    (g := Nat.add) (init := 0)
  have second := Array.foldl_map (xs := slots) (f := fun slot => slot.charge)
    (g := Nat.add) (init := 0)
  exact first.symm.trans ((congrArg (fun values : Array Nat => values.foldl Nat.add 0) equal).trans second)

omit [LawfulBEq κ] in
theorem Cache.retained_bounded (cache : Cache κ α limit weight) :
    weightOf weight cache.state.recent.slots+weightOf weight cache.state.previous.slots ≤ 2*limit := by
  rw [exact_weight weight _ cache.recent,exact_weight weight _ cache.previous]
  exact cache.state.allocated_bounded

end Eggshell.Research.WeighedCache
