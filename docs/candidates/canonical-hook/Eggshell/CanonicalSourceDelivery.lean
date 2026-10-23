module
public import Eggshell.CanonicalSourcePacket
@[expose] public section

namespace Eggshell.Synapses.CanonicalSource.Delivery
open Lean

def implementation : String := Blake3.hex (Blake3.digest "eggshell.shared-source-delivery".toUTF8 [
  (include_str "CanonicalSourceDelivery.lean").toUTF8,(include_str "CanonicalSourcePacket.lean").toUTF8,
  (include_str "Handoff.lean").toUTF8])

def rowKey (key : Key) : String := "c:" ++ Index.contentKey key.file ++ ":" ++ toString key.line

def merge (parts : Array StoredRow) : Except String (Array StoredRow) := do
  let mut atoms : Std.HashMap Key Atom := {}
  for row in parts do
    unless row.key.file.valid && 0 < row.key.line && !row.code.contains '\n' && !row.origins.isEmpty &&
        row.origins.all (fun origin => origin.occurrence.valid && origin.binding.valid) do
      throw "invalid shared original row"
    if let some previous := atoms[row.key]? then
      unless previous.code == row.code do throw "conflicting shared original code"
      let origins := row.origins.foldl (fun origins origin => origins.insert origin) previous.origins
      atoms := atoms.insert row.key {previous with origins}
    else
      let origins := row.origins.foldl (fun origins origin => origins.insert origin) ({} : Std.HashSet Origin)
      atoms := atoms.insert row.key ⟨row.code,origins⟩
  return ((Registry.mk atoms).store).qsort fun a b =>
    if a.key.file == b.key.file then a.key.line < b.key.line
    else (toJson a.key.file).compress < (toJson b.key.file).compress

structure Part where
  rows : Array StoredRow
  plan : String := ""
  deriving BEq, ToJson, FromJson

def Part.owners (part : Part) : List String :=
  hashDistinct (part.rows.toList.flatMap fun row => row.origins.toList.map (·.binding.owner))

def Part.keys (part : Part) : List String :=
  (if part.plan.isEmpty then [] else [part.plan]) ++ part.rows.toList.map (fun row => rowKey row.key)

def Part.render (part : Part) : String :=
  let files := part.rows.foldl (fun files row => files.insert row.key.file) ({} : Std.HashSet File)
  let files := files.toArray.qsort fun a b => (toJson a).compress < (toJson b).compress
  Packet.wrapper ++ "".intercalate (files.toList.map fun file =>
    let rows := part.rows.filter (·.key.file == file)
    let frame := Packet.fileFrame file rows
    frame.leading ++ "".intercalate (rows.toList.map Packet.rowText) ++ frame.trailing) ++ Packet.footer

def Part.remaining (part : Part) (acknowledged : List String) : Option Part :=
  if !part.plan.isEmpty && acknowledged.contains part.plan then none else
  let rows := part.rows.filter fun row => !acknowledged.contains (rowKey row.key)
  if rows.isEmpty then none else some {part with rows}

theorem acknowledged_plan_cannot_refill (part : Part) (acknowledged : List String)
    (named : part.plan.isEmpty = false) (accepted : acknowledged.contains part.plan = true) :
    part.remaining acknowledged = none := by
  unfold Part.remaining
  rw [named,accepted]
  rfl

theorem remaining_row_was_planned (part next : Part) (acknowledged : List String)
    (remaining : part.remaining acknowledged = some next) (row : StoredRow) (member : row ∈ next.rows) :
    row ∈ part.rows ∧ acknowledged.contains (rowKey row.key) = false := by
  unfold Part.remaining at remaining
  split at remaining
  · contradiction
  · dsimp only at remaining
    split at remaining
    · contradiction
    · cases remaining
      simpa [Bool.not_eq_true] using Array.mem_filter.mp member

/-- Origin lookup is built once from ready DB payloads, restricted to actual
already-admitted owners. A producer cannot admit another owner by this map. -/
def byOwner (registry : Registry) (allowed : Std.HashSet (String × String)) : Std.HashMap String (Array StoredRow) :=
  registry.atoms.fold (fun found key atom => Id.run do
    let mut origins : Std.HashMap String (Array Origin) := {}
    for origin in atom.origins do
      if allowed.contains (origin.binding.database,origin.binding.owner) then
        origins := origins.insert origin.binding.owner ((origins[origin.binding.owner]?).getD #[] |>.push origin)
    return origins.fold (fun found owner references => found.insert owner
      ((found[owner]?).getD #[] |>.push ⟨key,atom.code,references⟩)) found) {}

/-- Positions are explicitly labelled metadata and never counted as code
delivery. Keep the original available domain fixed while receipts subtract. -/
def locators (rows : Array StoredRow) : String := Id.run do
  let ordered := rows.qsort fun a b =>
    if a.key.file == b.key.file then a.key.line < b.key.line
    else (toJson a.key.file).compress < (toJson b.key.file).compress
  let mut ranges : Array Range := #[]
  for row in ordered do
    if let some previous := ranges.back? then
      if previous.file == row.key.file && row.key.line ≤ previous.last+1 then
        ranges := ranges.pop.push {previous with last := max previous.last row.key.line}
        continue
    ranges := ranges.push ⟨row.key.file,row.key.line,row.key.line⟩
  if ranges.isEmpty then return ""
  return "\nSAVED SOURCE POSITIONS\nPositions alone are not delivered code; CODE blocks contain the delivered rows.\n" ++
    "\n".intercalate (ranges.toList.map fun range => (toJson range).compress) ++ "\nEND SAVED SOURCE POSITIONS\n"

end Eggshell.Synapses.CanonicalSource.Delivery
