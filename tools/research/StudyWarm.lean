import Eggshell.PreparedInputs
import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean Eggshell
namespace Eggshell.Research.StudyWarm

structure Coverage where
  database : DB.Sidecar.Owner
  revision : Nat
  model : String
  windows : Nat
  valid : Nat
  missing : Nat
  invalid : Nat
  encoderContract : String
  deriving FromJson,ToJson

structure Source where
  prepared : Option PreparedInputs.Reference
  after : Coverage
  requested : Nat
  batches : Nat
  deriving FromJson,ToJson

structure Database where
  path : String
  sources : Array Source
  deriving FromJson,ToJson

structure Response where
  databases : Array Database
  deriving FromJson,ToJson

/-- Readiness carries the complete expected original inventory, not the
presence of an arbitrary successful row. Private usage is not a prerequisite. -/
structure Checked (heads : Array DB.PageMap.Head) (model encoder : String) where
  frame : PreparedInputs.Frame
  bound : frame.boundTo (heads.toList.map some) model encoder = true

theorem Checked.original_inventory (ready : Checked heads model encoder) :
    ready.frame.originals = heads.toList.map some :=
  PreparedInputs.Frame.original_inventory _ _ _ _ ready.bound

theorem Checked.prepared_inventory (ready : Checked heads model encoder) :
    ready.frame.inputs.map (·.source) = heads := by
  simpa using PreparedInputs.Frame.input_inventory _ _ _ _ ready.bound

def validate (response : Response) (paths : Array String) (heads : Array DB.PageMap.Head)
    (model encoder : String) (repeated : Bool) : Except String (Checked heads model encoder) := do
  unless response.databases.map (·.path) == paths do throw "warm changed the requested logical database inventory"
  let mut references := #[]
  for database in response.databases do
    for source in database.sources do
      let some reference := source.prepared | throw "warm omitted its complete prepared source frame"
      unless source.after.database.database == reference.source.identity &&
          source.after.revision == reference.source.revision && source.after.model == model &&
          source.after.encoderContract == encoder && source.after.missing == 0 &&
          source.after.invalid == 0 && source.after.valid == source.after.windows do
        throw "warm has incomplete, foreign or non-numerical coverage"
      if reference.population > 0 then
        unless reference.windows.isSome && reference.lexical.isSome && reference.numeric.isSome &&
            reference.canonical.isSome && reference.shared.isSome do
          throw "warm omitted a required public index"
      if repeated then
        unless source.requested == 0 && source.batches == 0 do throw "repeat warm encoded original windows"
      references := references.push reference
  let frame : PreparedInputs.Frame := ⟨PreparedInputs.implementation,heads.toList.map some,references,none⟩
  if bound : frame.boundTo (heads.toList.map some) model encoder = true then return ⟨frame,bound⟩
  else throw "warm changed a complete original head, model, encoder or producer"

def decode (stdout : String) (paths : Array String) (heads : Array DB.PageMap.Head)
    (model encoder : String) (repeated : Bool := false) : Except String (Checked heads model encoder) := do
  let response ← Json.parse stdout >>= fromJson?
  validate response paths heads model encoder repeated

end Eggshell.Research.StudyWarm

#print axioms Eggshell.Research.StudyWarm.Checked.original_inventory
#print axioms Eggshell.Research.StudyWarm.Checked.prepared_inventory
