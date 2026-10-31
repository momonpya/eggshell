module
public import tools.research.PreparedFileUnits
public import tools.research.PreparedSourceCosts
@[expose] public section

namespace Eggshell.Synapses.PublishedPlanMetadata
open Lean DB CanonicalSource

/-- Prepared data follows its actual producer bytes, without a manual format
number. Changing any layout/cost producer invalidates old preparation. -/
def implementation : String := Blake3.hex (Blake3.digest "eggshell.published-plan".toUTF8 [
  (include_str "PublishedPlanMetadata.lean").toUTF8,
  (include_str "PreparedFileUnits.lean").toUTF8,
  (include_str "PreparedSourceCosts.lean").toUTF8,
  (include_str "../../Eggshell/CanonicalSourceRecipe.lean").toUTF8,
  (include_str "../../Eggshell/CanonicalSourceRecords.lean").toUTF8,
  (include_str "../../Eggshell/CanonicalSourcePacket.lean").toUTF8])

structure Unit where
  indices : List Nat
  ranges : List (Nat × Nat)
  deriving BEq,DecidableEq,ToJson,FromJson

structure Stored where
  owner : String
  /-- Ordinals refer to the immutable recipe written in the same commit.
  Keys, file coordinates and complete provenance remain in that recipe. -/
  costs : Array (Nat × Nat)
  units : Array Unit
  deriving BEq,DecidableEq,ToJson,FromJson

/-- Exact length arithmetic avoids allocating a code-sized rendered string.
The decimal line address, tab and newline are still charged exactly. -/
def rowCost (row : StoredRow) : Nat × Nat :=
  let address := toString row.key.line
  (address.length+row.code.length+2,address.utf8ByteSize+row.code.utf8ByteSize+2)

theorem rowCost_exact (row : StoredRow) :
    rowCost row = ((Packet.rowText row).length,(Packet.rowText row).utf8ByteSize) := by
  have tab : "\t".length = 1 := by decide
  have newline : "\n".length = 1 := by decide
  have tabBytes : "\t".utf8ByteSize = 1 := by decide
  have newlineBytes : "\n".utf8ByteSize = 1 := by decide
  simp [rowCost,Packet.rowText,String.length_append,String.utf8ByteSize_append,
    tab,newline,tabBytes,newlineBytes] <;> omega

def build (owner : String) (stored : Recipe.Stored) (layout : Recipe.Checked stored.rows) : Stored :=
  { owner
    costs := stored.rows.map rowCost
    units := (PreparedFileUnits.base owner stored.rows layout).map fun unit =>
      ⟨unit.indices.map Fin.val,unit.ranges⟩ }

structure Ready (owner : String) (stored : Recipe.Stored) (layout : Recipe.Checked stored.rows) where
  metadata : Stored
  exact : metadata = build owner stored layout

def prepare (owner : String) (stored : Recipe.Stored) (layout : Recipe.Checked stored.rows) :
    Ready owner stored layout := ⟨build owner stored layout,rfl⟩

/-- Rehydration validates once per resident owner. It is never a per-query
fallback builder. A missing persisted plan means preparation is incomplete. -/
def check (owner : String) (stored : Recipe.Stored) (layout : Recipe.Checked stored.rows)
    (metadata : Stored) : Except String (Ready owner stored layout) :=
  if same : metadata = build owner stored layout then .ok ⟨metadata,same⟩
  else .error "published plan metadata differs from its original owner"

def name (owner : String) : String := "plan:" ++ owner

/-- The caller writes this in the same PageMap transaction as Recipe.write
and the preparation manifest. There is no independently advanced head. -/
def publish (writer : PageMap.Writer) (owner : String) (stored : Recipe.Stored) : IO _root_.Unit := do
  let layout ← IO.ofExcept (Recipe.check stored.rows stored.records)
  let bytes := (toJson (prepare owner stored layout).metadata).compress.toUTF8
  unless bytes.size ≤ 32*1024*1024 do throw (IO.userError "published plan metadata exceeds its owner bound")
  Persistence.Store.putPayload writer (name owner) bytes

def read (snapshot : PageMap.Snapshot) (owner : String) : IO Stored := do
  let descriptor ← snapshot.get (name owner)
  unless descriptor.isSome do throw (IO.userError "original owner has no published plan metadata")
  let size ← IO.ofExcept (PageMap.payloadSize descriptor)
  unless size ≤ 32*1024*1024 do throw (IO.userError "published plan metadata exceeds its owner bound")
  let bytes ← snapshot.readPayload (name owner)
  unless bytes.size ≤ 32*1024*1024 do throw (IO.userError "published plan metadata exceeds its owner bound")
  let some text := String.fromUTF8? bytes | throw (IO.userError "published plan metadata is not UTF-8")
  IO.ofExcept (Json.parse text >>= fromJson?)

theorem Ready.row_count (ready : Ready owner stored layout) :
    ready.metadata.costs.size = stored.rows.size := by
  rw [ready.exact]
  simp [build]

theorem Ready.costs_exact (ready : Ready owner stored layout) :
    ready.metadata.costs = stored.rows.map (fun row =>
      ((Packet.rowText row).length,(Packet.rowText row).utf8ByteSize)) := by
  rw [ready.exact]
  simp [build,rowCost_exact]

theorem Ready.owner_exact (ready : Ready owner stored layout) : ready.metadata.owner = owner := by
  rw [ready.exact]; rfl

/-- Ordinal tables combine only prepared costs. File captions depend on the
query's allowed origin set and are rendered once per file, never per code row. -/
def sourceDomain (rows : Array StoredRow) (costs : Std.HashMap Key (Nat × Nat))
    (frameCosts : Array (Nat × Nat)) : Except String Eggshell.Research.PreparedSourceCosts.Data := do
  let mut grouped : Std.HashMap File (Array StoredRow) := {}
  for row in rows do grouped := grouped.insert row.key.file ((grouped[row.key.file]?.getD #[]).push row)
  let mut charges := frameCosts
  let mut fileIds := {}
  let mut rowIds := {}
  let mut payloads := #[]
  for row in rows do
    unless fileIds.contains row.key.file do
      let frame := Packet.fileFrame row.key.file (grouped[row.key.file]?.getD #[])
      let text := frame.leading ++ frame.trailing
      fileIds := fileIds.insert row.key.file charges.size
      charges := charges.push (text.length,text.utf8ByteSize)
    let some cost := costs[row.key]? | throw "original row has no published cost"
    rowIds := rowIds.insert row.key charges.size
    payloads := payloads.push charges.size
    charges := charges.push cost
  return ⟨rows,charges,fileIds,rowIds,payloads⟩

end Eggshell.Synapses.PublishedPlanMetadata
