module
public import tools.research.OwnerPalette
@[expose] public section

namespace Eggshell.Synapses.PreparedPlanMetadata
open Lean CanonicalSource

/-- A planning shell is deliberately not a Delivery.Part: it has no code and
cannot be rendered as original evidence or used as a completed operation. -/
structure Shell where
  keys : Array Key
  owners : List String
  deriving BEq,ToJson,FromJson

def descriptorKeys (descriptor : OwnerPalette.Descriptor) : Option (Array Key) :=
  descriptor.rows.mapM fun row => do return ⟨← descriptor.files[row.file]?,row.line⟩

def describe (owner : String) (descriptor : OwnerPalette.Descriptor) : Option Shell := do
  return ⟨← descriptorKeys descriptor,[owner]⟩

def combine (shells : Array Shell) : Shell :=
  let keys := (hashDistinct ((shells.flatMap (·.keys)).toList)).toArray.qsort fun a b =>
    if a.file == b.file then a.line < b.line else (toJson a.file).compress < (toJson b.file).compress
  ⟨keys,hashDistinct (shells.toList.flatMap (·.owners))⟩

def locators (shell : Shell) : String := Id.run do
  let ordered := shell.keys.qsort fun a b =>
    if a.file == b.file then a.line < b.line else (toJson a.file).compress < (toJson b.file).compress
  let mut ranges : Array Range := #[]
  for key in ordered do
    if let some previous := ranges.back? then
      if previous.subject == .file key.file && key.line ≤ previous.last+1 then
        ranges := ranges.pop.push {previous with last := max previous.last key.line}
        continue
    ranges := ranges.push ⟨key.file,key.line,key.line⟩
  if ranges.isEmpty then return ""
  return "\nSAVED SOURCE POSITIONS\nPositions alone are not delivered code; CODE blocks contain the delivered rows.\n" ++
    "\n".intercalate ((Delivery.Locations.pack ranges.toList).map fun group => (toJson group).compress) ++
    "\nEND SAVED SOURCE POSITIONS\n"

/-- The authenticated descriptor suffices for receipt coordinates. Code is
still fetched and validated before it enters an actual delivery packet. -/
def reads (descriptor : OwnerPalette.Descriptor) : Option (Array Read) := do
  let rows ← descriptor.rows.mapM fun row => do
    let file ← descriptor.files[row.file]?
    let origins ← row.origins.mapM descriptor.origin?
    return origins.map fun origin =>
      (⟨origin.occurrence,⟨.file file,row.line,row.line⟩,origin.binding,#[]⟩ : Read)
  return rows.flatten

end Eggshell.Synapses.PreparedPlanMetadata
