module
public import tools.research.PreparedSourceView
public import Std.Data.HashMap.Lemmas
@[expose] public section

namespace Eggshell.Synapses.OwnerMetadataImage
open Lean

/-- Immutable references captured after query-view admission. No cache owner,
promise, mutable reference, mutex or CAS capability is present in this value. -/
structure Image where
  identity : String
  values : Std.HashMap String PreparedSourceView.OwnerReady := {}

def Image.lookup? (image : Image) (identity owner : String) : Option PreparedSourceView.OwnerReady :=
  if identity = image.identity then image.values[owner]? else none

def Image.insert (image : Image) (owner : String) (ready : PreparedSourceView.OwnerReady) : Image :=
  {image with values := image.values.insert owner ready}

theorem Image.insert_same (image : Image) (owner : String) (ready : PreparedSourceView.OwnerReady) :
    (image.insert owner ready).lookup? image.identity owner = some ready := by
  simp [insert,lookup?]

theorem Image.foreign_rejected (image : Image) (identity owner : String)
    (different : identity ≠ image.identity) : image.lookup? identity owner = none := by
  simp [lookup?,different]

theorem Image.insert_other (image : Image) (owner other : String) (ready : PreparedSourceView.OwnerReady)
    (different : owner ≠ other) :
    (image.insert owner ready).lookup? image.identity other = image.lookup? image.identity other := by
  simp [insert,lookup?,Std.HashMap.getElem?_insert,different]

theorem Image.lookup_is_read (image : Image) (identity owner : String) :
    image.lookup? identity owner = (if identity = image.identity then image.values[owner]? else none) := rfl

end Eggshell.Synapses.OwnerMetadataImage
