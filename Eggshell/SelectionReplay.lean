module

public import Eggshell.RankMemo

@[expose] public section
namespace Eggshell.Matcher.SelectionReplay

/-- Runtime membership contains only unit ordinals. The refinement below
keeps the old selected history entirely in erased propositions. -/
structure Index where
  query : Std.HashMap Nat Unit
  target : Std.HashMap Nat Unit

structure Index.Represents (index : Index) (selected : List Evidence) : Prop where
  queryExact : ∀ unit, index.query.contains unit = (selected.flatMap (·.query.units)).contains unit
  targetExact : ∀ unit, index.target.contains unit = (selected.flatMap (·.target.units)).contains unit

def Index.empty : Index := ⟨{}, {}⟩

theorem Index.empty_exact : Index.empty.Represents [] :=
  ⟨by intro unit; simp [empty], by intro unit; simp [empty]⟩

def Index.conflicts (index : Index) (candidate : Evidence) : Bool :=
  candidate.query.units.any index.query.contains || candidate.target.units.any index.target.contains

theorem Index.conflicts_exact (index : Index) (known : index.Represents selected) (candidate : Evidence) :
    index.conflicts candidate =
      (candidate.query.units.any (selected.flatMap (·.query.units)).contains ||
       candidate.target.units.any (selected.flatMap (·.target.units)).contains) := by
  have query : index.query.contains = (selected.flatMap (·.query.units)).contains :=
    funext known.queryExact
  have target : index.target.contains = (selected.flatMap (·.target.units)).contains :=
    funext known.targetExact
  rw [conflicts, query, target]

def Index.extend (index : Index) (candidate : Evidence) : Index :=
  ⟨candidate.query.units.foldl (fun known unit => known.insert unit ()) index.query,
   candidate.target.units.foldl (fun known unit => known.insert unit ()) index.target⟩

theorem Index.extend_exact (index : Index) (known : index.Represents selected) (candidate : Evidence) :
    (index.extend candidate).Represents (selected ++ [candidate]) :=
  ⟨by intro unit; simp [extend, HashDistinct.fold_contains, known.queryExact],
   by intro unit; simp [extend, HashDistinct.fold_contains, known.targetExact]⟩

/-- Witness positions refer to the current complete ordered evidence, not to
old positive hits. Every skipped candidate must currently overlap an earlier
selection; every selected candidate must currently be disjoint. -/
def check (index : Index) (ordinal : Nat) (positions : List Nat) : List Evidence → Bool
  | [] => positions.isEmpty
  | candidate :: rest =>
      if index.conflicts candidate then
        if positions.head? == some ordinal then false
        else check index (ordinal + 1) positions rest
      else if positions.head? == some ordinal then
        check (index.extend candidate) (ordinal + 1) positions.tail rest
      else false

def pick (ordinal : Nat) (positions : List Nat) : List Evidence → List Evidence
  | [] => []
  | candidate :: rest =>
      if positions.head? == some ordinal then
        candidate :: pick (ordinal + 1) positions.tail rest
      else pick (ordinal + 1) positions rest

theorem check_exact (ranked : List Evidence) (index : Index) (known : index.Represents selected)
    (ordinal : Nat) (positions : List Nat)
    (accepted : check index ordinal positions ranked = true) :
    selected ++ pick ordinal positions ranked = ranked.foldl workSelectionStep selected := by
  induction ranked generalizing selected index ordinal positions with
  | nil => simp [pick]
  | cons candidate rest ih =>
      have overlap := index.conflicts_exact known candidate
      cases conflict : index.conflicts candidate <;>
        cases take : positions.head? == some ordinal <;>
        simp only [check, conflict, take, Bool.false_eq_true, ↓reduceIte] at accepted
      · have tail := ih (index.extend candidate) (index.extend_exact known candidate) (ordinal + 1) positions.tail accepted
        simpa only [pick, take, ↓reduceIte, List.foldl_cons, workSelectionStep,
          ← overlap, conflict, Bool.false_eq_true, ↓reduceIte, List.append_assoc,
          List.singleton_append] using tail
      · have tail := ih index known (ordinal + 1) positions accepted
        simpa only [pick, take, Bool.false_eq_true, ↓reduceIte, List.foldl_cons,
          workSelectionStep, ← overlap, conflict, ↓reduceIte] using tail

def certify (ranked : List Evidence) (positions : List Nat) :
    Option { chosen : List Evidence // chosen = workSelection ranked } :=
  if accepted : check Index.empty 0 positions ranked = true then
    some ⟨pick 0 positions ranked, by
      simpa only [List.nil_append, workSelection] using check_exact ranked Index.empty Index.empty_exact 0 positions accepted⟩
  else none

/-- On a miss, produce only a compact position trace. The original ranked
objects are selected afterward; previous unit lists are never rebuilt. -/
def positions (index : Index) (ordinal : Nat) : List Evidence → List Nat
  | [] => []
  | candidate :: rest =>
      if index.conflicts candidate then positions index (ordinal + 1) rest
      else ordinal :: positions (index.extend candidate) (ordinal + 1) rest

theorem positions_lower (ranked : List Evidence) (index : Index) (ordinal : Nat)
    (position : Nat) (member : position ∈ positions index ordinal ranked) : ordinal ≤ position := by
  induction ranked generalizing index ordinal with
  | nil => simp [positions] at member
  | cons candidate rest ih =>
      simp only [positions] at member
      split at member
      · have later := ih index (ordinal + 1) member; omega
      · rcases List.mem_cons.mp member with same | later
        · omega
        · have later := ih (index.extend candidate) (ordinal + 1) later; omega

theorem positions_check (ranked : List Evidence) (index : Index) (ordinal : Nat) :
    check index ordinal (positions index ordinal ranked) ranked = true := by
  induction ranked generalizing index ordinal with
  | nil => rfl
  | cons candidate rest ih =>
      cases conflict : index.conflicts candidate
      · simpa only [positions, check, conflict, Bool.false_eq_true, ↓reduceIte,
          List.head?_cons, beq_self_eq_true, List.tail_cons] using
          ih (index.extend candidate) (ordinal + 1)
      · have next := ih index (ordinal + 1)
        have notCurrent : (positions index (ordinal + 1) rest).head? ≠ some ordinal := by
          cases found : positions index (ordinal + 1) rest with
          | nil => simp
          | cons head tail =>
              have later := positions_lower rest index (ordinal + 1) head (by rw [found]; simp)
              have different : head ≠ ordinal := by omega
              simp [different]
        simpa [positions, check, conflict, notCurrent] using next

def generate (ranked : List Evidence) :
    { chosen : List Evidence // chosen = workSelection ranked } × List Nat :=
  let saved := positions Index.empty 0 ranked
  (⟨pick 0 saved ranked, by
    simpa only [List.nil_append, workSelection] using
      check_exact ranked Index.empty Index.empty_exact 0 saved (positions_check ranked Index.empty 0)⟩, saved)

/-- Arbitrary old/corrupt positions cannot produce a non-reference selection.
Scores and source spans are reconstructed from the current chosen objects. -/
def obtain (ranked : List Evidence) (saved : Option (List Nat)) :
    { chosen : List Evidence // chosen = workSelection ranked } × List Nat × Bool :=
  match saved with
  | some positions =>
      match certify ranked positions with
      | some chosen => (chosen, positions, true)
      | none => let found := generate ranked; (found.1, found.2, false)
  | none => let found := generate ranked; (found.1, found.2, false)

theorem obtain_exact (ranked : List Evidence) (saved : Option (List Nat)) :
    (obtain ranked saved).1.val = workSelection ranked := (obtain ranked saved).1.property

end Eggshell.Matcher.SelectionReplay
