module
public import Lean.Data.Json.FromToJson
@[expose] public section
namespace Eggshell.Research.AllocatorDiagnostics
open Lean
@[extern "eggshell_research_allocator_owner"] opaque ownerRaw : IO String
/-- Diagnostic-only owner-thread areas. No global counter, collection,
foreign heap traversal or production decision depends on this value. -/
def owner : IO Json := do
  let raw ← ownerRaw
  let fields ← (raw.splitOn "\n").filterMapM fun line => do
    if line.isEmpty then return none
    let [key,value] := line.splitOn "=" | throw (IO.userError "invalid owner heap field")
    let some number := value.toNat? | throw (IO.userError "invalid owner heap number")
    return some (key,toJson number)
  let result := Json.mkObj fields
  unless result.getObjValD "version" == toJson (223 : Nat) do
    throw (IO.userError "unexpected installed allocator")
  return result.setObjVal! "ownerOnlyNotWholeProcessLiveBytes" (toJson true)
end Eggshell.Research.AllocatorDiagnostics
