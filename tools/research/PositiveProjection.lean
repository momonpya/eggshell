module
public import Eggshell.PacketReceipt
public import Eggshell.DeliveryLedger
public import Std.Data.HashSet.Lemmas
@[expose] public section

namespace Eggshell.Research.PositiveProjection
open Synapses

abbrev Identity := Binding × Occurrence × Range

def identity (read : Read) : Identity := (read.binding,read.occurrence,read.source)

/-- The exact native origin triples represented in the final shared part.
The project, Work, occurrence and immutable file identity remain in the key. -/
def identities (rows : Array CanonicalSource.StoredRow) : List Identity :=
  rows.toList.flatMap fun row => row.origins.toList.map fun origin =>
    (origin.binding,origin.occurrence,⟨.file row.key.file,row.key.line,row.key.line⟩)

def sharedPolicy (rows : Array CanonicalSource.StoredRow) : Read → Bool :=
  let present := Std.HashSet.ofList (identities rows)
  fun read => present.contains (identity read)

def sharedReads (rows : Array CanonicalSource.StoredRow) (evidence : Array Read) : Array Read :=
  let accepts := sharedPolicy rows
  evidence.filter fun read => read.valid && accepts read

/-- Materialized data, rather than a curried predicate whose preparation
can be moved into the per-read filter by arity expansion. -/
inductive Policy where
  | reject
  | shared (keys : Std.HashSet Identity)
  | context (owner : String) (ranges : Array (Nat × Nat))

def Policy.accepts (policy : Policy) (read : Read) : Bool :=
  match policy with
  | .reject => false
  | .shared keys => keys.contains (identity read)
  | .context owner ranges => read.binding.owner == owner &&
    ranges.any (fun (first,limit) => first ≤ read.binding.first && read.binding.limit ≤ limit)

def prepareShared (rows : Array CanonicalSource.StoredRow) : Policy :=
  .shared (Std.HashSet.ofList (identities rows))

@[noinline,nospecialize] def select (policy : Policy) (evidence : Array Read) : Array Read :=
  evidence.filter fun read => read.valid && policy.accepts read

theorem prepared_shared_exact (rows : Array CanonicalSource.StoredRow) (evidence : Array Read) :
    select (prepareShared rows) evidence = sharedReads rows evidence := rfl

theorem selected_was_prepared (policy : Policy) (evidence : Array Read) (read : Read)
    (selected : read ∈ select policy evidence) : read ∈ evidence ∧ read.valid = true := by
  have kept := Array.mem_filter.mp selected
  exact ⟨kept.1,(Bool.and_eq_true_iff.mp kept.2).1⟩

theorem shared_policy_exact (rows : Array CanonicalSource.StoredRow) (read : Read) :
    sharedPolicy rows read = (identities rows).contains (identity read) := by
  simp [sharedPolicy]

theorem selected_was_verified (rows : Array CanonicalSource.StoredRow) (evidence : Array Read)
    (read : Read) (selected : read ∈ sharedReads rows evidence) :
    read ∈ evidence ∧ read.valid = true := by
  have kept := Array.mem_filter.mp selected
  exact ⟨kept.1,(Bool.and_eq_true_iff.mp kept.2).1⟩

theorem selected_has_native_origin (rows : Array CanonicalSource.StoredRow) (evidence : Array Read)
    (read : Read) (selected : read ∈ sharedReads rows evidence) :
    ∃ row ∈ rows, ∃ origin ∈ row.origins,
      read.binding = origin.binding ∧ read.occurrence = origin.occurrence ∧
      read.source = ⟨.file row.key.file,row.key.line,row.key.line⟩ := by
  have kept := (Bool.and_eq_true_iff.mp (Array.mem_filter.mp selected).2).2
  change sharedPolicy rows read = true at kept
  rw [shared_policy_exact] at kept
  have member := List.contains_iff_mem.mp kept
  simp only [identities,List.mem_flatMap,List.mem_map,Array.mem_toList_iff] at member
  obtain ⟨row,rowPresent,origin,originPresent,same⟩ := member
  exact ⟨row,rowPresent,origin,originPresent,congrArg (fun key : Identity => key.1) same.symm,
    congrArg (fun key : Identity => key.2.1) same.symm,congrArg (fun key : Identity => key.2.2) same.symm⟩

/-- In particular, the source-byte witness established during preparation
is preserved. Unchecked neighbours do not revoke another selected witness. -/
theorem selected_preserves_witness (rows : Array CanonicalSource.StoredRow) (evidence : Array Read)
    (verified : Read → Prop) (prepared : ∀ read ∈ evidence, verified read)
    (read : Read) (selected : read ∈ sharedReads rows evidence) : verified read :=
  prepared read (selected_was_verified rows evidence read selected).1

def checked (rows : Array DeliveryLedger.Row) (bindings : Array Binding) (coverageComplete : Bool) : DeliveryLedger.Projection :=
  let verified := rows.all DeliveryLedger.Row.valid && bindings.all Binding.valid
  {rows,bindings,verified,complete := coverageComplete && verified}

/-- Positive validation is independent of complete presentation knowledge. -/
theorem checked_is_valid (rows : Array DeliveryLedger.Row) (bindings : Array Binding) (coverageComplete : Bool)
    (accepted : (checked rows bindings coverageComplete).verified = true) :
    rows.all DeliveryLedger.Row.valid = true ∧ bindings.all Binding.valid = true := by
  exact Bool.and_eq_true_iff.mp accepted

theorem incomplete_keeps_verified_ranges (rows : Array DeliveryLedger.Row) (bindings : Array Binding) :
    (checked rows bindings false).verified = (checked rows bindings true).verified ∧
      (checked rows bindings false).rows = rows ∧ (checked rows bindings false).complete = false := by
  exact ⟨rfl,rfl,rfl⟩

theorem complete_requires_verified (rows : Array DeliveryLedger.Row) (bindings : Array Binding) (coverageComplete : Bool)
    (complete : (checked rows bindings coverageComplete).complete = true) :
    (checked rows bindings coverageComplete).verified = true := (Bool.and_eq_true_iff.mp complete).2

#print axioms shared_policy_exact
#print axioms selected_has_native_origin
#print axioms selected_preserves_witness
#print axioms checked_is_valid
#print axioms prepared_shared_exact
#print axioms selected_was_prepared
#print axioms incomplete_keeps_verified_ranges
#print axioms complete_requires_verified
end Eggshell.Research.PositiveProjection
