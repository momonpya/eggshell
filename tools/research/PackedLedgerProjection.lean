module
public import Eggshell.DeliveryLedger
public import tools.research.ScopedIntervals
@[expose] public section

namespace Eggshell.Research.PackedLedgerProjection
open Synapses DeliveryLedger Plugin

abbrev Scope := String × Subject
abbrev Entry := ScopedIntervals.Entry Scope

def rowScope (row : Row) : Scope := (row.database,row.source.subject)

def rowAt (row : Row) (scope : Scope) (position : Nat) : Prop :=
  rowScope row = scope ∧ row.source.first ≤ position ∧ position ≤ row.source.last

def entry? (row : Row) : Option Entry :=
  if ordered : row.source.first < row.source.last+1 then
    some ⟨rowScope row,⟨row.source.first,row.source.last+1,ordered⟩⟩ else none

def toRow (entry : Entry) : Row :=
  ⟨entry.scope.1,⟨entry.scope.2,entry.span.start,entry.span.stop-1⟩⟩

theorem entry_covers (row : Row) (scope : Scope) (position : Nat) :
    (∃ entry,entry? row = some entry ∧ entry.covers scope position) ↔ rowAt row scope position := by
  unfold entry?
  split
  · constructor
    · rintro ⟨entry,equal,inside⟩
      cases Option.some.inj equal
      change rowScope row = scope ∧ row.source.first ≤ position ∧ position < row.source.last+1 at inside
      exact ⟨inside.1,inside.2.1,by omega⟩
    · rintro ⟨same,lower,upper⟩
      exact ⟨_,rfl,same,lower,by change position < row.source.last+1; omega⟩
  · constructor
    · rintro ⟨_,equal,_⟩; cases equal
    · rintro ⟨_,lower,upper⟩; omega

theorem toRow_covers (entry : Entry) (scope : Scope) (position : Nat) :
    rowAt (toRow entry) scope position ↔ entry.covers scope position := by
  change (entry.scope = scope ∧ entry.span.start ≤ position ∧ position ≤ entry.span.stop-1) ↔
    entry.scope = scope ∧ entry.span.start ≤ position ∧ position < entry.span.stop
  rw [Nat.le_sub_one_iff_lt (Nat.zero_lt_of_lt entry.span.ordered)]

def packRows (rows : Array Row) : Array Row :=
  (ScopedIntervals.pack (rows.filterMap entry?)).map toRow

theorem packRows_covers (rows : Array Row) (scope : Scope) (position : Nat) :
    (∃ row ∈ packRows rows,rowAt row scope position) ↔ ∃ row ∈ rows,rowAt row scope position := by
  have mapped : (∃ row ∈ packRows rows,rowAt row scope position) ↔
      ∃ entry ∈ ScopedIntervals.pack (rows.filterMap entry?),entry.covers scope position := by
    simp only [packRows,Array.mem_map]
    constructor
    · rintro ⟨row,⟨entry,member,same⟩,inside⟩
      exact ⟨entry,member,(toRow_covers entry scope position).mp (same ▸ inside)⟩
    · rintro ⟨entry,member,inside⟩
      exact ⟨toRow entry,⟨entry,member,rfl⟩,(toRow_covers entry scope position).mpr inside⟩
  rw [mapped,ScopedIntervals.pack_covers]
  constructor
  · rintro ⟨entry,member,inside⟩
    obtain ⟨row,inputMember,converted⟩ := Array.mem_filterMap.mp member
    exact ⟨row,inputMember,(entry_covers row scope position).mp ⟨entry,converted,inside⟩⟩
  · rintro ⟨row,member,inside⟩
    obtain ⟨entry,converted,inside⟩ := (entry_covers row scope position).mpr inside
    exact ⟨entry,Array.mem_filterMap.mpr ⟨row,member,converted⟩,inside⟩

theorem packed_bounds (rows : Array Row) (row : Row) (member : row ∈ packRows rows) :
    row.source.first ≤ row.source.last := by
  obtain ⟨entry,_,same⟩ := Array.mem_map.mp member
  have ordered := entry.span.ordered
  rw [← same]
  dsimp only [toRow]
  omega

def within (subject : Subject) (position : Nat) : Prop :=
  match subject with | .file _ => True | .original original => position ≤ original.chars

theorem valid_iff (row : Row) : row.valid = true ↔
    row.database.isEmpty = false ∧ row.source.subject.valid = true ∧
      0 < row.source.first ∧ row.source.first ≤ row.source.last ∧ within row.source.subject row.source.last := by
  cases kind : row.source.subject <;> simp [Row.valid,Range.valid,within,kind,and_assoc]

theorem packed_valid (rows : Array Row) (valid : rows.all Row.valid = true) :
    (packRows rows).all Row.valid = true := by
  apply Array.all_eq_true'.mpr
  intro result outputMember
  have bounds := packed_bounds rows result outputMember
  obtain ⟨first,firstMember,firstInside⟩ := (packRows_covers rows (rowScope result) result.source.first).mp
    ⟨result,outputMember,rfl,Nat.le_refl _,bounds⟩
  obtain ⟨last,lastMember,lastInside⟩ := (packRows_covers rows (rowScope result) result.source.last).mp
    ⟨result,outputMember,rfl,bounds,Nat.le_refl _⟩
  have firstValid := (valid_iff first).mp ((Array.all_eq_true'.mp valid) first firstMember)
  have lastValid := (valid_iff last).mp ((Array.all_eq_true'.mp valid) last lastMember)
  have sameDatabase := congrArg Prod.fst firstInside.1
  have sameSubject := congrArg Prod.snd firstInside.1
  have lastSubject := congrArg Prod.snd lastInside.1
  change first.database = result.database at sameDatabase
  change first.source.subject = result.source.subject at sameSubject
  apply (valid_iff result).mpr
  refine ⟨?_,?_,?_,bounds,?_⟩
  · rw [← sameDatabase]; exact firstValid.1
  · rw [← sameSubject]; exact firstValid.2.1
  · exact Nat.lt_of_lt_of_le firstValid.2.2.1 firstInside.2.1
  · have allowed := lastValid.2.2.2.2
    change last.source.subject = result.source.subject at lastSubject
    rw [lastSubject] at allowed
    cases kind : result.source.subject with
    | file _ => trivial
    | original original =>
      simp only [within,kind] at allowed ⊢
      exact Nat.le_trans lastInside.2.2 allowed

/-- Invalid metadata is returned unchanged, so normalization cannot turn an
invalid/unverified offer into an acceptable one by dropping malformed ranges. -/
def compact (projection : Projection) : Projection :=
  if projection.confirmable then {projection with rows := packRows projection.rows} else projection

theorem compact_covers (projection : Projection) (scope : Scope) (position : Nat) :
    (∃ row ∈ (compact projection).rows,rowAt row scope position) ↔
      ∃ row ∈ projection.rows,rowAt row scope position := by
  unfold compact
  split
  · exact packRows_covers _ _ _
  · rfl

theorem compact_bindings (projection : Projection) :
    (compact projection).bindings = projection.bindings := by unfold compact; split <;> rfl

theorem compact_verified (projection : Projection) :
    (compact projection).verified = projection.verified := by unfold compact; split <;> rfl

theorem compact_complete (projection : Projection) :
    (compact projection).complete = projection.complete := by unfold compact; split <;> rfl

theorem invalid_unchanged (projection : Projection) (invalid : projection.confirmable = false) :
    compact projection = projection := by simp [compact,invalid]

theorem compact_confirmable (projection : Projection) :
    (compact projection).confirmable = projection.confirmable := by
  unfold compact
  split
  · rename_i accepted
    have parts := Bool.and_eq_true_iff.mp accepted
    have positives := Bool.and_eq_true_iff.mp parts.1
    have rowsValid := packed_valid projection.rows positives.2
    change (projection.verified && (packRows projection.rows).all Row.valid &&
      projection.bindings.all Binding.valid) = projection.confirmable
    rw [rowsValid,positives.1,parts.2,accepted]
    rfl
  · rfl

end Eggshell.Research.PackedLedgerProjection
