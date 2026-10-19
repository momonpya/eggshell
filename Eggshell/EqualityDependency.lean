module

public import Eggshell.CongruenceSound
public import Eggshell.QuotientAuthority

@[expose] public section

namespace Eggshell.EqualityDependency

open QuotientBuilder QuotientBuilder.Partition

/-- Literal equality and current explicit Union edges, without Apply congruence. -/
inductive UnionPath (edges : List UnionEdge) : Value → Value → Prop where
  | refl (value) : UnionPath edges value value
  | edge (edge) : edge ∈ edges → UnionPath edges edge.left edge.right
  | symm : UnionPath edges left right → UnionPath edges right left
  | trans : UnionPath edges left middle → UnionPath edges middle right → UnionPath edges left right

theorem UnionPath.generated {edges left right} (path : UnionPath edges left right) :
    Eggshell.Equivalent edges left right := by
  induction path with
  | refl value => exact .refl value
  | edge edge member => exact .union edge member
  | symm _ ih => exact .symm ih
  | trans _ _ first second => exact .trans first second

private def Paths (edges : List UnionEdge) (partition : RawPartition) : Prop :=
  ∀ query, ∀ member ∈ lookup partition query, UnionPath edges member query

private theorem paths_empty (edges : List UnionEdge) : Paths edges [] := by
  intro query member present
  have same : member = query := by simpa [lookup, takeClass] using present
  subst member
  exact .refl query

private theorem paths_merge {edges : List UnionEdge} {partition : RawPartition}
    (valid : Valid partition) (paths : Paths edges partition) (left right : Value)
    (joined : UnionPath edges left right) : Paths edges (merge partition left right) := by
  intro query member present
  rw [merge_lookup valid] at present
  split at present
  · exact paths query member present
  · split at present
    · rename_i _ inside
      have toLeft : UnionPath edges query left := by
        rcases List.mem_append.mp inside with first | second
        · exact paths left query first
        · exact .trans (paths right query second) (.symm joined)
      apply UnionPath.trans _ (.symm toLeft)
      rcases List.mem_append.mp present with first | second
      · exact paths left member first
      · exact .trans (paths right member second) (.symm joined)
    · exact paths query member present

private theorem paths_explicit {edges : List UnionEdge} {partition : RawPartition}
    (valid : Valid partition) (paths : Paths edges partition) (updates : List UnionEdge)
    (current : ∀ edge ∈ updates, edge ∈ edges) : Paths edges (mergeExplicit partition updates) := by
  induction updates generalizing partition with
  | nil => exact paths
  | cons edge tail ih =>
    exact ih (merge_valid valid edge.left edge.right)
      (paths_merge valid paths edge.left edge.right (.edge edge (current edge (by simp))))
      (fun next member => current next (by simp [member]))

/-- This partition accepts mixed Atom/Apply generators as well as atomic ones.
It is a diagnostic reference, not an additional build on the hook's hot path. -/
structure DirectIndex (edges : List UnionEdge) where
  quotient : Quotient
  exact : certify (mergeExplicit [] edges) = some quotient

def DirectIndex.make (edges : List UnionEdge) : DirectIndex edges :=
  match found : certify (mergeExplicit [] edges) with
  | some quotient => ⟨quotient, found⟩
  | none => False.elim (by
      obtain ⟨quotient, certified⟩ := Authority.certify_exists
        (explicit_valid valid_nil edges) (Authority.explicit_safe valid_nil Authority.empty_safe edges)
      rw [found] at certified
      contradiction)

/-- The executable comparison is exactly explicit-edge reachability. In
particular, a negative result rules out every Union-only proof, not just a
particular parent pointer or a sampled path. -/
theorem DirectIndex.same_iff (index : DirectIndex edges) (left right : Value) :
    index.quotient.toEquality.same left right = true ↔ UnionPath edges left right := by
  constructor
  · intro same
    have heads : (lookup (mergeExplicit [] edges) left).headD left =
        (lookup (mergeExplicit [] edges) right).headD right := by
      simpa only [Quotient.same_iff_canonical_eq,
        certify_lookup (explicit_valid valid_nil edges) index.exact] using same
    exact .symm (paths_explicit valid_nil (paths_empty edges) edges
      (fun _ member => member) left right
        ((heads_equal (explicit_valid valid_nil edges) left right).mp heads))
  · intro path
    induction path with
    | refl value => exact index.quotient.toEquality.reflexive value
    | edge edge member =>
      have connected := CongruenceComplete.explicit_connected [] valid_nil edges edge member
      simpa only [Quotient.same_iff_canonical_eq,
        certify_lookup (explicit_valid valid_nil edges) index.exact,
        CongruenceComplete.canonical] using connected
    | symm _ ih => exact index.quotient.toEquality.symmetric ih
    | trans _ _ first second => exact index.quotient.toEquality.transitive first second

theorem DirectIndex.generated (index : DirectIndex edges) :
    CongruenceSound.QuotientSound edges index.quotient :=
  fun left right same => ((index.same_iff left right).mp same).generated

inductive Kind where
  | notEquivalent
  | literal
  | persistentUnion
  /-- A current local edge is needed for this direct path. Its causal ancestry
  remains unresolved; it must not be counted as a congruence-free delivery. -/
  | localUnion
  | congruence
  deriving BEq, DecidableEq, Repr

def classify (full : Equality) (stored : DirectIndex persistent)
    (current : DirectIndex (persistent ++ runLocal)) (left right : Value) : Kind :=
  if !full.same left right then .notEquivalent
  else if left == right then .literal
  else if stored.quotient.toEquality.same left right then .persistentUnion
  else if current.quotient.toEquality.same left right then .localUnion
  else .congruence

theorem persistent_has_union_path (full : Equality) (stored : DirectIndex persistent)
    (current : DirectIndex (persistent ++ runLocal)) (left right : Value)
    (kind : classify full stored current left right = .persistentUnion) :
    UnionPath persistent left right := by
  unfold classify at kind
  split at kind <;> try contradiction
  split at kind <;> try contradiction
  split at kind
  · exact (stored.same_iff left right).mp (by assumption)
  · split at kind <;> contradiction

theorem local_has_current_union_path (full : Equality) (stored : DirectIndex persistent)
    (current : DirectIndex (persistent ++ runLocal)) (left right : Value)
    (kind : classify full stored current left right = .localUnion) :
    UnionPath (persistent ++ runLocal) left right ∧ ¬ UnionPath persistent left right := by
  unfold classify at kind
  split at kind <;> try contradiction
  split at kind <;> try contradiction
  split at kind <;> try contradiction
  split at kind
  · constructor
    · exact (current.same_iff left right).mp (by assumption)
    · intro path
      have same := (stored.same_iff left right).mpr path
      contradiction
  · contradiction

/-- A generated positive comparison outside explicit closure requires an Apply
step in any explanation. This is about one comparison, not a whole delivery. -/
theorem congruence_is_necessary (full : Equality) (stored : DirectIndex persistent)
    (current : DirectIndex (persistent ++ runLocal))
    (generated : ∀ left right, full.same left right = true →
      Eggshell.Equivalent (persistent ++ runLocal) left right)
    (left right : Value) (kind : classify full stored current left right = .congruence) :
    Eggshell.Equivalent (persistent ++ runLocal) left right ∧
      ¬ UnionPath (persistent ++ runLocal) left right := by
  unfold classify at kind
  split at kind <;> try contradiction
  next positive =>
    have same : full.same left right = true := by simpa using positive
    split at kind <;> try contradiction
    split at kind <;> try contradiction
    split at kind <;> try contradiction
    constructor
    · exact generated left right same
    · intro path
      have connected := (current.same_iff left right).mpr path
      contradiction

end Eggshell.EqualityDependency
