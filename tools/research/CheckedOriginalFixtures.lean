module
public import tools.research.CheckedOriginalRecipe
@[expose] public section
namespace Eggshell.Research.CheckedOriginalFixtures
open Lean Eggshell.Synapses Eggshell.Synapses.CanonicalSource
def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def rejected (action : IO Unit) : IO Bool := do
  try action; return false
  catch _ => return true

def row (database : String) (line : Nat) (code : String) : StoredRow :=
  ⟨⟨⟨"resource",String.ofList (List.replicate 64 'a'),4096⟩,line⟩,code,
    #[⟨⟨"session","turn","call"⟩,⟨database,"owner","work",line*10,line*10+8⟩⟩]⟩

def compile (rows : Array StoredRow) : IO CheckedOriginal.Recipe := do
  let stored ← IO.ofExcept (CanonicalSource.Recipe.compile rows)
  IO.ofExcept (CheckedOriginal.check stored)

def reference (previous incoming : CheckedOriginal.Recipe) : IO CanonicalSource.Recipe.Stored := do
  if previous.rows.isEmpty then return incoming.stored
  let merged ← IO.ofExcept (Delivery.merge (previous.rows ++ incoming.rows))
  if merged == previous.rows then return previous.stored
  let records ← IO.ofExcept (CanonicalSource.Recipe.combine previous.rows incoming.rows merged previous.records incoming.records)
  return ⟨merged,records⟩

def verify : IO Unit := do
  let first ← compile #[row "project-a" 1 "alpha();"]
  let same ← compile #[row "project-a" 1 "alpha();"]
  let extraOrigin ← compile #[row "project-b" 1 "alpha();"]
  let extraRow ← compile #[row "project-b" 2 "beta();"]
  let empty ← compile #[]
  for (left,right) in [(first,same),(first,extraOrigin),(first,extraRow),(empty,first),(first,empty)] do
    let combined ← IO.ofExcept (CheckedOriginal.combine left right)
    ensure (combined.stored == (← reference left right)) "typed federation differs from complete raw reference"
    let checked ← IO.ofExcept (CanonicalSource.Recipe.check combined.rows combined.records)
    ensure (combined.layout.catalogue.map (List.map Fin.val) == checked.catalogue.map (List.map Fin.val))
      "typed federation changed record catalogue"
  let conflicting ← compile #[row "project-b" 1 "different();"]
  ensure ((CheckedOriginal.combine first conflicting).toOption.isNone) "conflicting source bytes were accepted"
  ensure ((CheckedOriginal.check ⟨first.rows,[⟨[99],none,100⟩]⟩).toOption.isNone) "outside record index was accepted"
  let ready ← IO.ofExcept (PreparedOwnerArena.prepare "project-a" "owner" first.stored)
  ensure ((CheckedOriginal.ofResident ready).stored == first.stored) "resident bridge changed original rows"
  let wire : CanonicalSource.Shared.Projection := ⟨toJson "scope",#[("owner",first.rows)],.hit,#[("owner",first.records)]⟩
  let checked ← CheckedOriginal.fromProjection "project-a" wire
  ensure (toJson checked.raw == toJson wire) "checked projection changed wire data"
  ensure (← rejected (do let _ ← CheckedOriginal.fromProjection "project-b" wire; pure ()))
    "remote original crossed its database scope"
  ensure (← rejected (do
    let _ ← CheckedOriginal.fromProjection "project-a" {wire with layouts := #[("other",first.records)]}
    pure ())) "remote layout crossed its owner domain"

end Eggshell.Research.CheckedOriginalFixtures
