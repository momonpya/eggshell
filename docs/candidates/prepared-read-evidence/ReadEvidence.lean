module
public import tools.research.PreparedPlanMetadata
public import tools.KeyPostings
@[expose] public section

namespace Eggshell.Synapses.ReadEvidence

def bindingKey (read : Read) := (read.binding,read.occurrence)
def ownerKey (read : Read) := read.binding.owner

/-- Immutable, query-independent indexes. A query combines references to
parts instead of flattening all metadata and rebuilding both directories. -/
structure Part where
  rows : Array Read
  bindings : KeyPostings.Index bindingKey rows
  owners : KeyPostings.Index ownerKey rows

def Part.prepare (rows : Array Read) : Part :=
  ⟨rows,KeyPostings.prepare bindingKey rows,KeyPostings.prepare ownerKey rows⟩

/-- The descriptor itself remains the authority for these exact values.
The equality is a proof and adds no retained descriptor copy to this cache. -/
structure Cached (descriptor : OwnerPalette.Descriptor) where
  part : Part
  exact : PreparedPlanMetadata.reads descriptor = some part.rows

def prepare? (descriptor : OwnerPalette.Descriptor) : Option (Cached descriptor) :=
  match found : PreparedPlanMetadata.reads descriptor with
  | none => none
  | some rows => some ⟨Part.prepare rows,found⟩

theorem prepare_present (descriptor : OwnerPalette.Descriptor) :
    (prepare? descriptor).isSome = (PreparedPlanMetadata.reads descriptor).isSome := by
  unfold prepare?
  split <;> simp_all

/-- The full sequence is a logical specification. Verified lookup uses it
only in proof fields; it is not needed as an executable query-time value. -/
def sourceRows (parts : Array Part) : Array Read := parts.flatMap (·.rows)

def rawBinding (parts : Array Part) (key : Binding × Occurrence) : Array Read :=
  parts.flatMap (fun part => part.bindings.lookup key)

def rawOwner (parts : Array Part) (owner : String) : Array Read :=
  parts.flatMap (fun part => part.owners.lookup owner)

theorem binding_exact (parts : Array Part) (key : Binding × Occurrence) :
    rawBinding parts key = (sourceRows parts).filterMap
      (fun read => if bindingKey read == key then some read else none) := by
  simp only [rawBinding,sourceRows,Array.filterMap_flatMap]
  congr 1
  funext part
  exact KeyPostings.Index.lookup_exact ..

theorem owner_exact (parts : Array Part) (owner : String) :
    rawOwner parts owner = (sourceRows parts).filterMap
      (fun read => if ownerKey read == owner then some read else none) := by
  simp only [rawOwner,sourceRows,Array.filterMap_flatMap]
  congr 1
  funext part
  exact KeyPostings.Index.lookup_exact ..

private theorem selected_member (values : Array Read) (accept : Read → Bool) (read : Read)
    (present : read ∈ values.filterMap (fun row => if accept row then some row else none)) :
    read ∈ values := by
  obtain ⟨prior,member,chosen⟩ := Array.mem_filterMap.mp present
  split at chosen <;> simp_all

def binding (parts : Array Part) (key : Binding × Occurrence) :
    Array {read : Read // read ∈ sourceRows parts} :=
  (rawBinding parts key).attach.map fun read => ⟨read.val,by
    apply selected_member (sourceRows parts) (fun row => bindingKey row == key)
    simpa only [binding_exact] using read.property⟩

def owner (parts : Array Part) (name : String) :
    Array {read : Read // read ∈ sourceRows parts} :=
  (rawOwner parts name).attach.map fun read => ⟨read.val,by
    apply selected_member (sourceRows parts) (fun row => ownerKey row == name)
    simpa only [owner_exact] using read.property⟩

theorem binding_values (parts : Array Part) (key : Binding × Occurrence) :
    (binding parts key).map Subtype.val = rawBinding parts key := by
  simp [binding,Array.map_map]

theorem owner_values (parts : Array Part) (name : String) :
    (owner parts name).map Subtype.val = rawOwner parts name := by
  simp [owner,Array.map_map]

/-- Apply a selected-owner predicate after a small lookup with exactly the
same result as filtering the complete universe before building the index. -/
theorem binding_filtered (parts : Array Part) (key : Binding × Occurrence) (accept : Read → Bool) :
    (rawBinding parts key).filter accept = ((sourceRows parts).filter accept).filterMap
      (fun read => if bindingKey read == key then some read else none) := by
  rw [binding_exact,Array.filter_filterMap,Array.filterMap_filter]
  congr 1
  funext read
  split <;> cases chosen : accept read <;> simp_all

theorem owner_filtered (parts : Array Part) (name : String) (accept : Read → Bool) :
    (rawOwner parts name).filter accept = ((sourceRows parts).filter accept).filterMap
      (fun read => if ownerKey read == name then some read else none) := by
  rw [owner_exact,Array.filter_filterMap,Array.filterMap_filter]
  congr 1
  funext read
  split <;> cases chosen : accept read <;> simp_all

/-- Published metadata belongs to one exact owner. This proof permits an
owner directory to exclude unrelated parts without losing any binding. -/
structure Owned where
  name : String
  part : Part
  homogeneous : ∀ read ∈ part.rows, ownerKey read = name

def Owned.prepare? (name : String) (part : Part) : Option Owned :=
  if checked : part.rows.all (fun read => ownerKey read == name) then
    some ⟨name,part,fun read member => beq_iff_eq.mp (Array.all_eq_true_iff_forall_mem.mp checked read member)⟩
  else none

theorem Owned.foreign_binding_empty (part : Owned) (key : Binding × Occurrence)
    (foreign : part.name ≠ key.1.owner) : part.part.bindings.lookup key = #[] := by
  rw [KeyPostings.Index.lookup_exact]
  apply Array.filterMap_eq_empty_iff.mpr
  intro read member
  have different : bindingKey read ≠ key := by
    intro same
    have names := congrArg (fun value : Binding × Occurrence => value.1.owner) same
    exact foreign ((part.homogeneous read member).symm.trans names)
  simp [different]

theorem Owned.foreign_owner_empty (part : Owned) (name : String)
    (foreign : part.name ≠ name) : part.part.owners.lookup name = #[] := by
  rw [KeyPostings.Index.lookup_exact]
  apply Array.filterMap_eq_empty_iff.mpr
  intro read member
  have different : ownerKey read ≠ name := by simpa [part.homogeneous read member] using foreign
  simp [different]

private theorem flatMap_selected {α β : Type} (values : Array α) (accept : α → Bool)
    (emit : α → Array β) (missing : ∀ value, accept value = false → emit value = #[]) :
    (values.filterMap (fun value => if accept value then some value else none)).flatMap emit =
      values.flatMap emit := by
  apply Array.toList_inj.mp
  simp only [Array.toList_flatMap,Array.toList_filterMap]
  cases values with
  | mk values =>
    induction values with
    | nil => simp
    | cons value rest ih =>
      cases selected : accept value <;> simp_all

structure Routes where
  parts : Array Owned
  directory : KeyPostings.Index (·.name) parts

def Routes.prepare (parts : Array Owned) : Routes := ⟨parts,KeyPostings.prepare (·.name) parts⟩

def Routes.sourceRows (routes : Routes) : Array Read :=
  _root_.Eggshell.Synapses.ReadEvidence.sourceRows (routes.parts.map (·.part))

def Routes.binding (routes : Routes) (key : Binding × Occurrence) : Array Read :=
  (routes.directory.lookup key.1.owner).flatMap (fun part => part.part.bindings.lookup key)

def Routes.owner (routes : Routes) (name : String) : Array Read :=
  (routes.directory.lookup name).flatMap (fun part => part.part.owners.lookup name)

theorem Routes.binding_exact (routes : Routes) (key : Binding × Occurrence) :
    routes.binding key = rawBinding (routes.parts.map (·.part)) key := by
  rw [Routes.binding,KeyPostings.Index.lookup_exact]
  have missing (part : Owned) (different : (part.name == key.1.owner) = false) :
      part.part.bindings.lookup key = #[] := part.foreign_binding_empty key (by simpa using different)
  rw [flatMap_selected routes.parts _ _ missing]
  simp [rawBinding,Array.flatMap_map]

theorem Routes.owner_exact (routes : Routes) (name : String) :
    routes.owner name = rawOwner (routes.parts.map (·.part)) name := by
  rw [Routes.owner,KeyPostings.Index.lookup_exact]
  have missing (part : Owned) (different : (part.name == name) = false) :
      part.part.owners.lookup name = #[] := part.foreign_owner_empty name (by simpa using different)
  rw [flatMap_selected routes.parts _ _ missing]
  simp [rawOwner,Array.flatMap_map]

def Routes.bindingMembers (routes : Routes) (key : Binding × Occurrence) :
    Array {read : Read // read ∈ routes.sourceRows} :=
  (routes.binding key).attach.map fun ⟨read,present⟩ => ⟨read,by
    apply selected_member routes.sourceRows (fun row => bindingKey row == key)
    rw [Routes.binding_exact,_root_.Eggshell.Synapses.ReadEvidence.binding_exact] at present
    exact present⟩

def Routes.ownerMembers (routes : Routes) (name : String) :
    Array {read : Read // read ∈ routes.sourceRows} :=
  (routes.owner name).attach.map fun ⟨read,present⟩ => ⟨read,by
    apply selected_member routes.sourceRows (fun row => ownerKey row == name)
    rw [Routes.owner_exact,_root_.Eggshell.Synapses.ReadEvidence.owner_exact] at present
    exact present⟩

theorem Routes.bindingMembers_values (routes : Routes) (key : Binding × Occurrence) :
    (routes.bindingMembers key).map Subtype.val = routes.binding key := by
  simp [Routes.bindingMembers,Array.map_map]

theorem Routes.ownerMembers_values (routes : Routes) (name : String) :
    (routes.ownerMembers name).map Subtype.val = routes.owner name := by
  simp [Routes.ownerMembers,Array.map_map]

end Eggshell.Synapses.ReadEvidence
