module

public import Eggshell.Matcher
public import Eggshell.HashDistinct
public import Init.Data.Array.Sort.Lemmas
public import Init.Data.List.Sort.Lemmas
import all Init.Data.List.Sort.Basic

@[expose] public section
namespace Eggshell.Matcher.EvidenceReplay

local instance : BEq Evidence := ⟨fun a b => decide (a = b)⟩
local instance : LawfulBEq Evidence where
  rfl := by intro a; simp [BEq.beq]
  eq_of_beq := by intro a b h; exact of_decide_eq_true h

def lex (a b : Nat) (rest : Bool) : Bool :=
  if a == b then rest else a ≤ b

theorem lex_trans (a b c : Nat) (ab bc ac : Bool)
    (tail : ab → bc → ac) : lex a b ab → lex b c bc → lex a c ac := by
  intro first second
  by_cases h : a = b <;> by_cases k : b = c <;> by_cases j : a = c <;>
    simp_all [lex] <;> omega

theorem lex_reverse_trans (a b c : Nat) (ab bc ac : Bool)
    (tail : ab → bc → ac) : lex b a ab → lex c b bc → lex c a ac := by
  intro first second
  exact lex_trans c b a bc ab ac (fun x y => tail y x) second first

theorem lex_total (a b : Nat) (ab ba : Bool) (tail : ab || ba) :
    lex a b ab || lex b a ba := by
  by_cases h : a = b
  · subst b; simpa [lex] using tail
  · simp [lex, h, Ne.symm h]; omega

def order (weights : Array Nat) (a b : Evidence) : Bool :=
  lex (evidenceWeight weights b) (evidenceWeight weights a)
    (lex b.query.units.length a.query.units.length
      (lex a.target.units.length b.target.units.length
        (lex a.target.span.start b.target.span.start (a.query.span.start ≤ b.query.span.start))))

theorem order_reference (weights : Array Nat) (a b : Evidence) :
    order weights a b = !preferredEvidence weights b a := by
  by_cases w : evidenceWeight weights b = evidenceWeight weights a <;>
  by_cases q : b.query.units.length = a.query.units.length <;>
  by_cases t : b.target.units.length = a.target.units.length <;>
  by_cases s : b.target.span.start = a.target.span.start <;>
    simp [order, lex, preferredEvidence, w, q, t, s, Ne.symm, ← decide_not, Nat.not_lt]

theorem order_trans (weights : Array Nat) (a b c : Evidence) :
    order weights a b → order weights b c → order weights a c := by
  unfold order
  apply lex_reverse_trans
  · apply lex_reverse_trans
    · apply lex_trans
      · apply lex_trans
        · simpa only [decide_eq_true_eq] using
            (@Nat.le_trans a.query.span.start b.query.span.start c.query.span.start)

theorem order_total (weights : Array Nat) (a b : Evidence) :
    order weights a b || order weights b a := by
  apply lex_total
  apply lex_total
  apply lex_total
  apply lex_total
  simpa using Nat.le_total a.query.span.start b.query.span.start

/-- Linear adjacent-order verification. Transitivity closes the all-pairs
contract in Lean; the executable does not compare every pair. -/
def chain (le : α → α → Bool) : List α → Bool
  | [] | [_] => true
  | a :: b :: rest => le a b && chain le (b :: rest)

theorem chain_pairwise (le : α → α → Bool)
    (trans : ∀ a b c, le a b → le b c → le a c) (items : List α)
    (accepted : chain le items) : items.Pairwise (fun a b => le a b = true) := by
  induction items with
  | nil => simp
  | cons a rest ih =>
    cases rest with
    | nil => simp
    | cons b rest =>
      have h : le a b = true ∧ chain le (b :: rest) = true := by
        simpa [chain] using accepted
      have tail := ih h.2
      apply List.pairwise_cons.mpr
      refine ⟨?_, tail⟩
      intro c member
      rcases List.mem_cons.mp member with equal | member
      · subst c; exact h.1
      · exact trans a b c h.1 ((List.pairwise_cons.mp tail).1 c member)

/-- Hash deduplication and indexed array access bound verification to a
linear frontier. No serialized body, result or erased proof is trusted. -/
def replay (items : List α) [BEq α] [Hashable α] (positions : List Nat) : List (α × Nat) :=
  let source := items.toArray
  (hashDistinct positions).filterMap (fun i => source[i]?.map (fun item => (item, i)))

/-- A current, complete evidence domain. Its list parameter and correctness
proofs erase; lookup may address a virtual product without allocating it. -/
structure Indexed (items : List Evidence) where
  count : Nat
  lookup : Nat → Option Evidence
  countExact : count = items.length
  lookupExact : ∀ position, lookup position = items[position]?

def replayIndexed (source : Indexed items) (positions : List Nat) : List (Evidence × Nat) :=
  (hashDistinct positions).filterMap fun i => (source.lookup i).map (fun item => (item, i))

theorem replayIndexed_reference (source : Indexed items) (positions : List Nat) :
    replayIndexed source positions = replay items positions := by
  simp only [replayIndexed, replay, source.lookupExact, List.getElem?_toArray,
    ]

theorem replay_subset [BEq α] [LawfulBEq α] [Hashable α]
    (items : List α) (positions : List Nat) : replay items positions ⊆ items.zipIdx := by
  intro item member
  obtain ⟨i, _, found⟩ := List.mem_filterMap.mp member
  have found : items.zipIdx[i]? = some item := by
    simpa only [List.getElem?_toArray, List.getElem?_zipIdx, Nat.zero_add] using found
  exact List.mem_of_getElem? found

theorem replay_nodup [BEq α] [Hashable α] (items : List α) (positions : List Nat) :
    (replay items positions).Nodup := by
  dsimp only [replay]
  refine List.Pairwise.filterMap _ ?_ (HashDistinct.nodup positions)
  intro i j different a first b second same
  have ordinal (i : Nat) (item : α × Nat)
      (found : (items.toArray[i]?).map (fun value => (value, i)) = some item) : item.2 = i := by
    cases value : items.toArray[i]? <;> simp_all
    exact (congrArg Prod.snd found).symm
  exact different ((ordinal i a first).symm.trans (congrArg Prod.snd same) |>.trans
    (ordinal j b second))

theorem full_subset_perm [BEq α] [LawfulBEq α] {a b : List α}
    (unique : a.Nodup) (sourceUnique : b.Nodup) (subset : a ⊆ b)
    (size : a.length = b.length) : a.Perm b := by
  apply (List.perm_ext_iff_of_nodup unique sourceUnique).mpr
  intro x
  refine ⟨fun member => subset member, ?_⟩
  intro member
  apply Decidable.byContradiction
  intro absent
  have smaller : a ⊆ b.erase x := by
    intro y hy
    exact (List.mem_erase_of_ne (by intro equal; subst y; exact absent hy)).mpr (subset hy)
  have length := unique.length_le_of_subset smaller
  have positive := List.length_pos_of_mem member
  rw [List.length_erase_of_mem member] at length
  omega

theorem replay_perm (items : List Evidence) (positions : List Nat)
    (size : (replay items positions).length = items.length) :
    (replay items positions).Perm items.zipIdx := by
  have unique : (items.zipIdx.map Prod.snd).Nodup := by
    rw [List.zipIdx_map_snd]; exact List.nodup_range' _
  have sourceUnique : items.zipIdx.Nodup :=
    List.Pairwise.of_map Prod.snd (fun _ _ different equal => different (congrArg Prod.snd equal)) unique
  exact full_subset_perm (replay_nodup items positions) sourceUnique
    (replay_subset items positions) (by simpa using size)

def stableOrder (weights : List Nat) := List.zipIdxLE (order weights.toArray)

structure RankKey where
  weight : Nat
  queryWidth : Nat
  targetWidth : Nat
  targetStart : Nat
  queryStart : Nat

def RankKey.of (weights : Array Nat) (item : Evidence) : RankKey :=
  ⟨evidenceWeight weights item, item.query.units.length, item.target.units.length,
    item.target.span.start, item.query.span.start⟩

def RankKey.order (a b : RankKey) : Bool :=
  lex b.weight a.weight (lex b.queryWidth a.queryWidth
    (lex a.targetWidth b.targetWidth (lex a.targetStart b.targetStart (a.queryStart ≤ b.queryStart))))

/-- Compute the dependency-sensitive weight once per source ordinal, rather
than once per comparison. The equality field ties that key to this request. -/
structure Keyed (weights : List Nat) where
  original : Evidence × Nat
  key : RankKey
  exact : key = RankKey.of weights.toArray original.1

def Keyed.make (weights : List Nat) (array : Array Nat) (exact : array = weights.toArray)
    (item : Evidence × Nat) : Keyed weights :=
  ⟨item, RankKey.of array item.1, by rw [exact]⟩

def Keyed.order (a b : Keyed weights) : Bool :=
  List.zipIdxLE RankKey.order (a.key, a.original.2) (b.key, b.original.2)

theorem Keyed.order_exact (a b : Keyed weights) :
    Keyed.order a b = stableOrder weights a.original b.original := by
  simp only [Keyed.order, a.exact, b.exact, stableOrder, List.zipIdxLE, RankKey.of,
    RankKey.order, EvidenceReplay.order]
  rfl

theorem Keyed.order_trans (a b c : Keyed weights) :
    Keyed.order a b → Keyed.order b c → Keyed.order a c := by
  simp only [Keyed.order_exact]
  exact List.zipIdxLE_trans (EvidenceReplay.order_trans weights.toArray) a.original b.original c.original

theorem Keyed.chain_sorted (parts : List (Keyed weights)) (accepted : chain Keyed.order parts = true) :
    (parts.map (·.original)).Pairwise (fun a b => stableOrder weights a b = true) := by
  rw [List.pairwise_map]
  exact (chain_pairwise _ Keyed.order_trans parts accepted).imp (fun {_ _} good =>
    by simpa only [Keyed.order_exact] using good)

theorem sorted_exact (weights : List Nat) (items : List Evidence)
    (ranked : List (Evidence × Nat)) (perm : ranked.Perm items.zipIdx)
    (sorted : ranked.Pairwise (fun a b => stableOrder weights a b = true)) :
    ranked.map Prod.fst = rankedEvidence weights items := by
  have equal : ranked = items.zipIdx.mergeSort (stableOrder weights) := by
    apply List.Perm.eq_of_pairwise (le := fun a b => stableOrder weights a b = true)
    · rintro ⟨a, i⟩ ⟨b, j⟩ ha hb ab ba
      have ma := perm.subset ha
      have mb := List.mem_mergeSort.mp hb
      simp only [stableOrder, List.zipIdxLE] at ab ba
      have ai : i ≤ j := by
        split at ab <;> split at ba <;> simp_all
      have bj : j ≤ i := by
        split at ab <;> split at ba <;> simp_all
      have same := Nat.le_antisymm ai bj
      subst j
      have := List.mem_zipIdx ma
      have := List.mem_zipIdx mb
      simp_all
    · exact sorted
    · exact List.pairwise_mergeSort (List.zipIdxLE_trans (order_trans _))
        (List.zipIdxLE_total (order_total _)) _
    · exact perm.trans (List.mergeSort_perm _ _).symm
  rw [equal]
  change (items.zipIdx.mergeSort (List.zipIdxLE (order weights.toArray))).map (·.1) = _
  rw [List.mergeSort_zipIdx]
  simp only [rankedEvidence, Array.toList_mergeSort]
  congr 1
  funext a b
  exact order_reference _ a b

/-- Arbitrary persisted positions can only produce an exact current result.
A stale/corrupt certificate is a miss, never approximate evidence. -/
def certify (weights : List Nat) (items : List Evidence) (positions : List Nat) :
    Option {ranked : List Evidence // ranked = rankedEvidence weights items} :=
  let ranked := replay items positions
  if size : ranked.length = items.length then
    if sorted : chain (stableOrder weights) ranked = true then
      some ⟨ranked.map Prod.fst,
        sorted_exact weights items ranked (replay_perm items positions size)
          (chain_pairwise _ (List.zipIdxLE_trans (order_trans _)) _ sorted)⟩
    else none
  else none

/-- Certify an existing order directly against the current source index.
No full join list is evaluated on this path. Complete count, permutation and
stable ordering remain mandatory, including every newly matching anchor. -/
@[inline] def certifyIndexed (weights : List Nat) (source : Indexed items) (positions : List Nat) :
    Option {ranked : List Evidence // ranked = rankedEvidence weights items} :=
  let ranked := replayIndexed source positions
  if size : ranked.length = source.count then
    if sorted : chain (stableOrder weights) ranked = true then
      some ⟨ranked.map Prod.fst,
        sorted_exact weights items ranked
          (by
            have complete : (replay items positions).length = items.length := by
              simpa only [ranked, replayIndexed_reference, source.countExact] using size
            simpa only [ranked, replayIndexed_reference] using replay_perm items positions complete)
          (chain_pairwise _ (List.zipIdxLE_trans (order_trans _)) _ sorted)⟩
    else none
  else none

theorem certify_exact (weights : List Nat) (source : Indexed items) (positions : List Nat)
    (ranked : {ranked : List Evidence // ranked = rankedEvidence weights items})
    (_accepted : certifyIndexed weights source positions = some ranked) :
    ranked.val = rankedEvidence weights items := ranked.property

/-- Reuse ascending runs after a dependency changes. Only the boundaries
that changed order cause merges; an unchanged order needs no sort. -/
def runs (le : α → α → Bool) : List α → List (List α)
  | [] => []
  | head :: tail =>
      match runs le tail with
      | [] => [[head]]
      | [] :: rest => [head] :: [] :: rest
      | (next :: following) :: rest =>
          if le head next then (head :: next :: following) :: rest
          else [head] :: (next :: following) :: rest

theorem runs_flatten (le : α → α → Bool) (items : List α) :
    (runs le items).flatten = items := by
  induction items with
  | nil => rfl
  | cons head tail ih =>
      simp only [runs]
      split <;> simp_all
      split <;> simp_all

def mergePairs (le : α → α → Bool) : List (List α) → List (List α)
  | first :: second :: rest => List.merge first second le :: mergePairs le rest
  | rest => rest

theorem mergePairs_perm (le : α → α → Bool) (parts : List (List α)) :
    (mergePairs le parts).flatten.Perm parts.flatten := by
  match parts with
  | [] => rfl
  | [part] => rfl
  | first :: second :: rest =>
      simpa only [mergePairs, List.flatten_cons, List.append_assoc] using
        (List.merge_perm_append (le := le) (xs := first) (ys := second)).append
          (mergePairs_perm le rest)
termination_by parts.length

def mergeRuns (le : α → α → Bool) : Nat → List (List α) → List α
  | 0, parts => parts.flatten
  | _ + 1, [] => []
  | _ + 1, [part] => part
  | fuel + 1, parts => mergeRuns le fuel (mergePairs le parts)

theorem mergeRuns_perm (le : α → α → Bool) (fuel : Nat) (parts : List (List α)) :
    (mergeRuns le fuel parts).Perm parts.flatten := by
  induction fuel generalizing parts with
  | zero => rfl
  | succ fuel ih =>
      cases parts with
      | nil => rfl
      | cons first tail =>
          cases tail with
          | nil => simp [mergeRuns]
          | cons second rest =>
              exact (ih _).trans (mergePairs_perm le _)

/-- Current complete ordinals are mandatory even for differential repair.
The output's permutation and final order certify the exact stable reference;
the previous order has no authority to suppress newly matching evidence. -/
def repairIndexed (weights : List Nat) (source : Indexed items) (positions : List Nat) :
    Option ({ranked : List Evidence // ranked = rankedEvidence weights items} × List Nat) :=
  let previous := replayIndexed source positions
  if size : previous.length = source.count then
    have original : previous.Perm items.zipIdx := by
      have complete : (replay items positions).length = items.length := by
        simpa only [previous, replayIndexed_reference, source.countExact] using size
      simpa only [previous, replayIndexed_reference] using replay_perm items positions complete
    let prepared := previous.map (Keyed.make weights weights.toArray rfl)
    have preparedExact : prepared.map (·.original) = previous := by
      simp only [prepared, List.map_map, Function.comp_def, Keyed.make]
      exact List.map_id previous
    if sorted : chain Keyed.order prepared = true then
      some (⟨previous.map Prod.fst, sorted_exact weights items previous original
        (by simpa only [preparedExact] using Keyed.chain_sorted prepared sorted)⟩,
        previous.map Prod.snd)
    else
      let parts := runs Keyed.order prepared
      let ranked := mergeRuns Keyed.order parts.length parts
      let ordinals := ranked.map (·.original)
      if sorted : chain Keyed.order ranked = true then
        some (⟨ordinals.map Prod.fst, sorted_exact weights items ordinals
          (by
            have retained := (mergeRuns_perm Keyed.order parts.length parts).map Keyed.original
            simp only [parts, runs_flatten, preparedExact] at retained
            exact retained.trans original)
          (Keyed.chain_sorted ranked sorted)⟩,
          ordinals.map Prod.snd)
      else none
  else none

def positions (weights : List Nat) (items : List Evidence) : List Nat :=
  ((items.zipIdx.toArray.mergeSort (stableOrder weights)).toList).map Prod.snd

theorem generated_exact (weights : List Nat) (items : List Evidence) :
    ((items.zipIdx.toArray.mergeSort (stableOrder weights)).toList).map Prod.fst =
      rankedEvidence weights items := by
  simp only [Array.toList_mergeSort]
  change (items.zipIdx.mergeSort (List.zipIdxLE (order weights.toArray))).map (·.1) = _
  rw [List.mergeSort_zipIdx]
  simp only [rankedEvidence, Array.toList_mergeSort]
  congr 1
  funext a b
  exact order_reference _ a b

/-- Sort once on a miss. The result and replay positions share this ordered
list; no verification sort or second sorting pass is performed. -/
def generate (weights : List Nat) (items : List Evidence) :
    {ranked : List Evidence // ranked = rankedEvidence weights items} × List Nat :=
  let indexed := (items.zipIdx.toArray.mergeSort (stableOrder weights)).toList
  (⟨indexed.map Prod.fst, generated_exact weights items⟩, indexed.map Prod.snd)

end Eggshell.Matcher.EvidenceReplay
