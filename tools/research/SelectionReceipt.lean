module
public import Eggshell.Receipt
public import Lean.Data.Json.Parser
@[expose] public section
namespace Eggshell.Receipt
open Lean

def partName (area field : String) (index : Nat) : String := s!"selection-{area}-{field}-{index}"

/-- Explicit diagnostics use bounded array parts. The ordinary receipt writer
and its 8 MiB bound are unchanged; a failed diagnostic cannot change delivery. -/
def observeSelection (id : Option String) (enabled : Bool) (data : Json) : IO Unit := do
  if !enabled || id.isNone then return ← observe id "selection-plan" data
  let some id := id | return
  try
    let mut root := data
    let mut descriptors := #[]
    for area in ["selectorInput","selectionWitness"] do
      let value := root.getObjValD area
      let some object := value.getObj?.toOption | continue
      let mut shortened := value
      for (field,value) in object.toArray do
        let some rows := value.getArr?.toOption | continue
        let count := (rows.size+1023)/1024
        for index in [:count] do
          write id (partName area field index) (Json.arr (rows.extract (index*1024) ((index+1)*1024)))
        descriptors := descriptors.push (Json.mkObj [("area",toJson area),("field",toJson field),
          ("parts",toJson count),("rows",toJson rows.size)])
        shortened := shortened.setObjVal! field Json.null
      root := root.setObjVal! area shortened
    write id "selection-plan" (root.setObjVal! "diagnosticParts" (toJson descriptors))
  catch error => observe (some id) "selection-plan-failure" (toJson (error.toString.take 512).copy)

def readFrame (path : System.FilePath) : IO (Json × Nat) := do
  let metadata ← path.symlinkMetadata
  unless metadata.type == .file && metadata.byteSize.toNat ≤ 8*1024*1024 do
    throw (IO.userError "invalid diagnostic part or native frame bound")
  let text ← IO.FS.readFile path
  return (← IO.ofExcept (Json.parse text),metadata.byteSize.toNat)

/-- Reassemble only the completed manifest, retaining part identity and order.
Missing parts and malformed manifests are errors, never empty observations. -/
def readSelection (directory : System.FilePath) : IO Json := do
  FileSystem.rejectSymlinkAncestors directory
  let (root,bytes) ← readFrame (directory / "selection-plan.json")
  let id ← IO.ofExcept (root.getObjValAs? String "receipt")
  let pid ← IO.ofExcept (root.getObjValAs? Nat "pid")
  unless validId id && directory.fileName == some id && root.getObjValD "stage" == toJson "selection-plan" do
    throw (IO.userError "selection manifest belongs to another receipt")
  let mut data := root.getObjValD "data"
  let some descriptors := (data.getObjValAs? (Array Json) "diagnosticParts").toOption | return data
  unless descriptors.size ≤ 32 do throw (IO.userError "too many diagnostic fields")
  let mut total := bytes
  let mut seen : Std.HashSet String := {}
  for descriptor in descriptors do
    let area ← IO.ofExcept (descriptor.getObjValAs? String "area")
    let field ← IO.ofExcept (descriptor.getObjValAs? String "field")
    let count ← IO.ofExcept (descriptor.getObjValAs? Nat "parts")
    let rows ← IO.ofExcept (descriptor.getObjValAs? Nat "rows")
    let key := area ++ ":" ++ field
    unless ["selectorInput","selectionWitness"].contains area && !field.isEmpty && field.length ≤ 32 &&
        field.toList.all Char.isAlphanum && !seen.contains key && count == (rows+1023)/1024 && rows ≤ 1000000 do
      throw (IO.userError "invalid or duplicate diagnostic field")
    seen := seen.insert key
    let mut values := #[]
    for index in [:count] do
      let stage := partName area field index
      let path := directory / (stage ++ ".json")
      let metadata ← path.symlinkMetadata
      unless total+metadata.byteSize.toNat ≤ 32*1024*1024 do throw (IO.userError "diagnostic assembly exceeds its bound")
      let (part,size) ← readFrame path
      total := total+size
      unless part.getObjValD "receipt" == toJson id && part.getObjValD "pid" == toJson pid &&
          part.getObjValD "stage" == toJson stage do throw (IO.userError "diagnostic part changed its receipt identity")
      let chunk ← IO.ofExcept ((part.getObjValD "data").getArr?)
      unless chunk.size == min 1024 (rows-index*1024) do throw (IO.userError "diagnostic part is incomplete or reordered")
      values := values ++ chunk
    unless values.size == rows do throw (IO.userError "diagnostic field lost rows")
    data := data.setObjVal! area ((data.getObjValD area).setObjVal! field (Json.arr values))
  return data

end Eggshell.Receipt
