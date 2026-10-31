module
public import Eggshell.CanonicalSourcePrepared
public import tools.research.PreparedOwnerArena
@[expose] public section

namespace Eggshell.Synapses.CheckedOriginal
open Lean CanonicalSource

/-- A layout and its source rows travel together. This is original-data
preparation, not a Match, a Union or a completed-operation certificate. -/
structure Recipe where
  stored : CanonicalSource.Recipe.Stored
  layout : CanonicalSource.Recipe.Checked stored.rows
  checked : CanonicalSource.Recipe.check stored.rows stored.records = .ok layout

def Recipe.rows (recipe : Recipe) := recipe.stored.rows
def Recipe.records (recipe : Recipe) := recipe.stored.records

def optionalRows : Option Recipe → Array CanonicalSource.StoredRow
  | none => #[]
  | some recipe => recipe.rows

def optionalChecked (value : Option Recipe) : Option (CanonicalSource.Recipe.Checked (optionalRows value)) :=
  match value with
  | none => none
  | some recipe => some recipe.layout

def check (stored : CanonicalSource.Recipe.Stored) : Except String Recipe :=
  match result : CanonicalSource.Recipe.check stored.rows stored.records with
  | .error message => .error message
  | .ok layout => .ok ⟨stored,layout,result⟩

def ofResident (ready : PreparedOwnerArena.Ready) : Recipe :=
  ⟨ready.stored,ready.layout,ready.checked⟩

theorem resident_payload (ready : PreparedOwnerArena.Ready) :
    (ofResident ready).stored = ready.stored := rfl

theorem resident_layout (ready : PreparedOwnerArena.Ready) :
    (ofResident ready).layout = ready.layout := rfl

theorem Recipe.all_original_rows (recipe : Recipe) (index : Fin recipe.rows.size) :
    index ∈ recipe.layout.catalogue.flatten := recipe.layout.catalogue_complete index

theorem check_payload (stored : CanonicalSource.Recipe.Stored) :
    (check stored).map (·.stored) =
      (CanonicalSource.Recipe.check stored.rows stored.records).map (fun _ => stored) := by
  unfold check
  split <;> simp_all [Except.map]

/-- Only a changed federated row domain needs a new layout. Incoming scoped
origins have already been checked at their authenticated source boundary. -/
def combine (previous incoming : Recipe) : Except String Recipe := do
  if previous.rows.isEmpty then return incoming
  let merged ← Delivery.merge (previous.rows ++ incoming.rows)
  if merged == previous.rows then return previous
  let entries := hashDistinct ((← CanonicalSource.Recipe.reindex previous.rows merged previous.records) ++
    (← CanonicalSource.Recipe.reindex incoming.rows merged incoming.records))
  check ⟨merged,entries⟩

theorem combine_unchanged (previous incoming : Recipe)
    (nonempty : previous.rows.isEmpty = false)
    (merged : Delivery.merge (previous.rows ++ incoming.rows) = .ok rows)
    (same : (rows == previous.rows) = true) :
    combine previous incoming = .ok previous := by
  unfold combine
  simp only [nonempty,Bool.false_eq_true,↓reduceIte,merged]
  change (if rows == previous.rows then (.ok previous : Except String Recipe) else _) = .ok previous
  simp [same]

structure Projection where
  identity : Json
  values : Array PreparedOwnerArena.Ready
  reuse : CanonicalSource.Shared.Reuse

def Projection.raw (projection : Projection) : CanonicalSource.Shared.Projection :=
  ⟨projection.identity,projection.values.map (fun ready => (ready.owner,ready.stored.rows)),
    projection.reuse,projection.values.map (fun ready => (ready.owner,ready.stored.records))⟩

/-- The remote path still validates all untrusted bytes. It returns the
checked result rather than discarding it and checking it in Handoff again. -/
def fromProjection (database : String) (raw : CanonicalSource.Shared.Projection) : IO Projection := do
  unless raw.rows.map Prod.fst == raw.layouts.map Prod.fst do
    throw (IO.userError "prepared row/layout domain differs")
  let values ← (raw.rows.zip raw.layouts).mapM fun ((owner,rows),(_,records)) =>
    IO.ofExcept (PreparedOwnerArena.prepare database owner ⟨rows,records⟩)
  return ⟨raw.identity,values,raw.reuse⟩

end Eggshell.Synapses.CheckedOriginal
