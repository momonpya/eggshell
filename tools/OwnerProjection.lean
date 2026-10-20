module
public import Eggshell.HashDistinct
import all Init.System.ST
import all Init.System.IO

@[expose] public section
namespace Eggshell.OwnerProjection

variable {α β : Type} [BEq α] [LawfulBEq α] [Hashable α]
  [BEq β] [LawfulBEq β] [Hashable β]

abbrev Choice (α β : Type) := Sum α β × List Nat

structure Result (α β : Type) where
  durable : List α := []
  staged : List β := []
  durableWindows : List (α × List Nat) := []
  stagedWindows : List (β × List Nat) := []
  durableRanking : List α := []
  stagedRanking : List β := []
  presentationOrder : List (Sum α β) := []
  focused : List α := []
  deriving BEq

def hasKey (rows : List (α × List Nat)) (key : α) : Bool :=
  (rows.map Prod.fst).contains key

omit [Hashable α] in theorem hasKey_exact (rows : List (α × List Nat)) (key : α) :
    hasKey rows key = rows.any (·.1 == key) := by
  simp only [hasKey, List.contains_map]
  exact List.any_congr rfl (fun _ => BEq.comm)

def Result.related (state : Result α β) (choice : Choice α β) : Result α β :=
  match choice.1 with
  | .inl key => {state with
      durable := state.durable ++ [key]
      durableWindows := state.durableWindows ++ [(key, choice.2)]}
  | .inr key => {state with
      staged := state.staged ++ [key]
      stagedWindows := state.stagedWindows ++ [(key, choice.2)]}

def rankWindows (rows : List (α × List Nat)) (entry : α × List Nat) : List (α × List Nat) :=
  if hasKey rows entry.1 || entry.2.isEmpty then rows else rows ++ [entry]

def Result.ranked (state : Result α β) (choice : Choice α β) : Result α β :=
  match choice.1 with
  | .inl key => {state with
      durableRanking := state.durableRanking ++ [key]
      durableWindows := rankWindows state.durableWindows (key, choice.2)
      presentationOrder := state.presentationOrder ++ [.inl key]}
  | .inr key => {state with
      stagedRanking := state.stagedRanking ++ [key]
      stagedWindows := rankWindows state.stagedWindows (key, choice.2)
      presentationOrder := state.presentationOrder ++ [.inr key]}

def reference (initial : Result α β) (related ranked : List (Choice α β)) : Result α β :=
  ranked.foldl Result.ranked (related.foldl Result.related initial)

/-- The full key decides identity. Seen keys include empty related windows,
which must block a later ranked window just like the original list test. -/
structure Windows (α : Type) [BEq α] [Hashable α] where
  rows : Array (α × List Nat)
  seen : Std.HashMap α Unit
  exact : ∀ key, seen.contains key = (rows.toList.map Prod.fst).contains key

def Windows.make (rows : List (α × List Nat)) : Windows α := {
  rows := rows.toArray
  seen := (rows.map Prod.fst).foldl (fun known key => known.insert key ()) {}
  exact := by
    intro key
    simpa using HashDistinct.fold_contains (rows.map Prod.fst) ({} : Std.HashMap α Unit) key }

def Windows.related (state : Windows α) (entry : α × List Nat) : Windows α := {
  rows := state.rows.push entry
  seen := state.seen.insert entry.1 ()
  exact := by
    intro key
    simp only [Std.HashMap.contains_insert, Array.toList_push, List.map_append,
      List.map_cons, List.map_nil, List.contains_append, List.contains_cons,
      List.contains_nil, Bool.or_false, state.exact]
    simp only [BEq.comm, Bool.or_comm] }

def Windows.ranked (state : Windows α) (entry : α × List Nat) : Windows α :=
  if state.seen.contains entry.1 || entry.2.isEmpty then state else state.related entry

theorem Windows.related_exact (state : Windows α) (entry : α × List Nat) :
    (state.related entry).rows.toList = state.rows.toList ++ [entry] := by
  simp [Windows.related]

theorem Windows.ranked_exact (state : Windows α) (entry : α × List Nat) :
    (state.ranked entry).rows.toList = rankWindows state.rows.toList entry := by
  have same : state.seen.contains entry.1 = hasKey state.rows.toList entry.1 := state.exact _
  simp only [Windows.ranked, same, rankWindows]
  split <;> simp_all [Windows.related]

structure Builder (α β : Type) [BEq α] [Hashable α] [BEq β] [Hashable β] where
  durable : Array α
  staged : Array β
  durableWindows : Windows α
  stagedWindows : Windows β
  durableRanking : Array α
  stagedRanking : Array β
  presentationOrder : Array (Sum α β)
  focused : List α

def Builder.view (state : Builder α β) : Result α β := {
  durable := state.durable.toList, staged := state.staged.toList
  durableWindows := state.durableWindows.rows.toList
  stagedWindows := state.stagedWindows.rows.toList
  durableRanking := state.durableRanking.toList, stagedRanking := state.stagedRanking.toList
  presentationOrder := state.presentationOrder.toList, focused := state.focused }

def Builder.make (initial : Result α β) : Builder α β := {
  durable := initial.durable.toArray, staged := initial.staged.toArray
  durableWindows := Windows.make initial.durableWindows
  stagedWindows := Windows.make initial.stagedWindows
  durableRanking := initial.durableRanking.toArray, stagedRanking := initial.stagedRanking.toArray
  presentationOrder := initial.presentationOrder.toArray, focused := initial.focused }

def Builder.related (state : Builder α β) (choice : Choice α β) : Builder α β :=
  match choice.1 with
  | .inl key => {state with
      durable := state.durable.push key
      durableWindows := state.durableWindows.related (key, choice.2)}
  | .inr key => {state with
      staged := state.staged.push key
      stagedWindows := state.stagedWindows.related (key, choice.2)}

def Builder.ranked (state : Builder α β) (choice : Choice α β) : Builder α β :=
  match choice.1 with
  | .inl key => {state with
      durableRanking := state.durableRanking.push key
      durableWindows := state.durableWindows.ranked (key, choice.2)
      presentationOrder := state.presentationOrder.push (.inl key)}
  | .inr key => {state with
      stagedRanking := state.stagedRanking.push key
      stagedWindows := state.stagedWindows.ranked (key, choice.2)
      presentationOrder := state.presentationOrder.push (.inr key)}

theorem Builder.make_exact (initial : Result α β) : (Builder.make initial).view = initial := by
  cases initial
  simp [Builder.make, Builder.view, Windows.make]

theorem Builder.related_exact (state : Builder α β) (choice : Choice α β) :
    (state.related choice).view = state.view.related choice := by
  rcases choice with ⟨key, indices⟩
  cases key <;> simp [Builder.related, Builder.view, Result.related, Windows.related]

theorem Builder.ranked_exact (state : Builder α β) (choice : Choice α β) :
    (state.ranked choice).view = state.view.ranked choice := by
  rcases choice with ⟨key, indices⟩
  cases key <;> simp [Builder.ranked, Builder.view, Result.ranked, Windows.ranked_exact]

theorem Builder.fold_related_exact (state : Builder α β) (input : List (Choice α β)) :
    (input.foldl Builder.related state).view = input.foldl Result.related state.view := by
  induction input generalizing state with
  | nil => rfl
  | cons head tail ih => simp only [List.foldl_cons, ih, Builder.related_exact]

theorem Builder.fold_ranked_exact (state : Builder α β) (input : List (Choice α β)) :
    (input.foldl Builder.ranked state).view = input.foldl Result.ranked state.view := by
  induction input generalizing state with
  | nil => rfl
  | cons head tail ih => simp only [List.foldl_cons, ih, Builder.ranked_exact]

/-- One array append per row and one full-key lookup per ranked window.
Lists are materialized once, after both folds, with their original order. -/
def project (initial : Result α β) (related ranked : List (Choice α β)) : Result α β :=
  (ranked.foldl Builder.ranked (related.foldl Builder.related (Builder.make initial))).view

theorem project_exact (initial : Result α β) (related ranked : List (Choice α β)) :
    project initial related ranked = reference initial related ranked := by
  simp only [project, reference, Builder.fold_ranked_exact, Builder.fold_related_exact,
    Builder.make_exact]

/-- A resolver may fail or observe arbitrary state. Refinement preserves the
same left-to-right effects, including the first failure; it is not IO caching. -/
theorem foldlM_view {m : Type → Type} [Monad m] [LawfulMonad m]
    {σ τ ρ : Type} (view : σ → τ) (fast : σ → ρ → m σ) (slow : τ → ρ → m τ)
    (same : ∀ state row, view <$> fast state row = slow (view state) row)
    (rows : List ρ) (initial : σ) :
    view <$> rows.foldlM fast initial = rows.foldlM slow (view initial) := by
  induction rows generalizing initial with
  | nil => simp
  | cons head tail ih =>
      simp only [List.foldlM_cons, map_bind, ih]
      rw [← same initial head]
      simp only [bind_map_left]

def referenceM {m : Type → Type} [Monad m] {γ δ : Type}
    (initial : Result α β) (related : List γ) (ranked : List δ)
    (resolveRelated : γ → m (Choice α β)) (resolveRanked : δ → m (Choice α β)) : m (Result α β) := do
  let found ← related.foldlM (fun state row => state.related <$> resolveRelated row) initial
  ranked.foldlM (fun state row => state.ranked <$> resolveRanked row) found

/-- The original imperative traversal, before compiling the accumulator. -/
def legacyM {m : Type → Type} [Monad m] {γ δ : Type}
    (initial : Result α β) (related : List γ) (ranked : List δ)
    (resolveRelated : γ → m (Choice α β)) (resolveRanked : δ → m (Choice α β)) : m (Result α β) := do
  let mut found := initial
  for row in related do
    found := found.related (← resolveRelated row)
  for row in ranked do
    found := found.ranked (← resolveRanked row)
  pure found

omit [LawfulBEq α] [Hashable α] [LawfulBEq β] [Hashable β] in
theorem legacyM_exact {m : Type → Type} [Monad m] [LawfulMonad m] {γ δ : Type}
    (initial : Result α β) (related : List γ) (ranked : List δ)
    (resolveRelated : γ → m (Choice α β)) (resolveRanked : δ → m (Choice α β)) :
    legacyM initial related ranked resolveRelated resolveRanked =
      referenceM initial related ranked resolveRelated resolveRanked := by
  simp only [legacyM, referenceM, ← map_eq_pure_bind, List.forIn_yield_eq_foldlM, bind_pure]

def projectM {m : Type → Type} [Monad m] {γ δ : Type}
    (initial : Result α β) (related : List γ) (ranked : List δ)
    (resolveRelated : γ → m (Choice α β)) (resolveRanked : δ → m (Choice α β)) : m (Result α β) := do
  let found ← related.foldlM (fun state row => state.related <$> resolveRelated row) (Builder.make initial)
  let found ← ranked.foldlM (fun state row => state.ranked <$> resolveRanked row) found
  pure found.view

theorem projectM_exact {m : Type → Type} [Monad m] [LawfulMonad m] {γ δ : Type}
    (initial : Result α β) (related : List γ) (ranked : List δ)
    (resolveRelated : γ → m (Choice α β)) (resolveRanked : δ → m (Choice α β)) :
    projectM initial related ranked resolveRelated resolveRanked =
      referenceM initial related ranked resolveRelated resolveRanked := by
  have relatedSame := foldlM_view Builder.view
    (fun state row => state.related <$> resolveRelated row)
    (fun state row => state.related <$> resolveRelated row)
    (by intro state row; simp only [Functor.map_map, Builder.related_exact])
    related (Builder.make initial)
  simp only [Builder.make_exact] at relatedSame
  have rankedSame := fun state => foldlM_view Builder.view
    (fun state row => state.ranked <$> resolveRanked row)
    (fun state row => state.ranked <$> resolveRanked row)
    (by intro state row; simp only [Functor.map_map, Builder.ranked_exact])
    ranked state
  unfold projectM referenceM
  simp only [← map_eq_pure_bind]
  simp only [rankedSame]
  have bound := bind_map_left Builder.view
    (related.foldlM (fun (state : Builder α β) row => state.related <$> resolveRelated row)
      (Builder.make initial))
    (fun (state : Result α β) => ranked.foldlM
      (fun state row => state.ranked <$> resolveRanked row) state)
  rw [← bound, relatedSame]

def legacyIO {γ δ : Type} (initial : Result Nat Value) (related : List γ) (ranked : List δ)
    (resolveRelated : γ → IO (Choice Nat Value)) (resolveRanked : δ → IO (Choice Nat Value)) :
    IO (Result Nat Value) :=
  legacyM initial related ranked resolveRelated resolveRanked

def projectIO {γ δ : Type} (initial : Result Nat Value) (related : List γ) (ranked : List δ)
    (resolveRelated : γ → IO (Choice Nat Value)) (resolveRanked : δ → IO (Choice Nat Value)) :
    IO (Result Nat Value) :=
  projectM initial related ranked resolveRelated resolveRanked

/-- Lean exposes IO's exception/state representation but does not install
its lawful-monad instance. These kernel proofs use that representation only. -/
local instance : LawfulMonad IO := .mk'
  (id_map := fun action => by
    funext world
    simp only [Functor.map, instMonadEIO._aux_1, EST.bind]
    cases action world <;> rfl)
  (pure_bind := fun _ _ => rfl)
  (bind_assoc := fun action next last => by
    funext world
    simp only [Bind.bind, instMonadEIO._aux_13, EST.bind]
    cases action world <;> rfl)

@[csimp] theorem legacy_io_compiled : @legacyIO = @projectIO := by
  funext γ δ initial related ranked resolveRelated resolveRanked
  exact (legacyM_exact initial related ranked resolveRelated resolveRanked).trans
    (projectM_exact initial related ranked resolveRelated resolveRanked).symm

end Eggshell.OwnerProjection
