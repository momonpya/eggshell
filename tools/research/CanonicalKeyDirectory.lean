module
public import Eggshell.CanonicalSourceDelivery
public import Std.Data.DHashMap.Basic
@[expose] public section

namespace Eggshell.Research.CanonicalKeyDirectory
open Eggshell.Synapses Eggshell.Synapses.CanonicalSource

/-- Full immutable file identity indexes a proven prefix. Hash-map collisions
cannot replace file equality. Proofs erase; runtime values are just strings. -/
structure Prepared where
  prefixes : Std.DHashMap File (fun file => {text : String // text = Index.contentKey file}) := {}

def Prepared.prefix (prepared : Prepared) (file : File) : String :=
  match prepared.prefixes.get? file with
  | some cached => cached.val
  | none => Index.contentKey file

theorem Prepared.prefix_exact (prepared : Prepared) (file : File) :
    prepared.prefix file = Index.contentKey file := by
  unfold Prepared.prefix
  cases prepared.prefixes.get? file with
  | none => rfl
  | some cached => exact cached.property

def prepare (rows : Array StoredRow) : Prepared := Id.run do
  let mut prefixes := ({} : Prepared).prefixes
  for row in rows do
    unless prefixes.contains row.key.file do
      prefixes := prefixes.insert row.key.file ⟨Index.contentKey row.key.file,rfl⟩
  return ⟨prefixes⟩

def Prepared.rowKey (prepared : Prepared) (key : Key) : String :=
  "c:" ++ prepared.prefix key.file ++ ":" ++ toString key.line

theorem Prepared.rowKey_exact (prepared : Prepared) (key : Key) :
    prepared.rowKey key = Delivery.rowKey key := by
  simp only [Prepared.rowKey,Prepared.prefix_exact,Delivery.rowKey]

def Prepared.keys (prepared : Prepared) (part : Delivery.Part) : List String :=
  (if part.plan.isEmpty then [] else [part.plan]) ++
    part.rows.toList.map (fun row => prepared.rowKey row.key)

theorem Prepared.keys_exact (prepared : Prepared) : prepared.keys = Delivery.Part.keys := by
  funext part
  simp only [Prepared.keys,Prepared.rowKey_exact,Delivery.Part.keys]

end Eggshell.Research.CanonicalKeyDirectory
