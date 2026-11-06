module
public import Lean.Data.Json.FromToJson
@[expose] public section
namespace Eggshell.Research.AbandonedHeap
open Lean
@[extern "eggshell_research_abandoned_enable"] opaque enable : IO Unit
@[extern "eggshell_research_abandoned_snapshot"] opaque snapshotRaw (census : Bool) : IO String
@[extern "eggshell_research_abandoned_thread_id"] opaque threadId : IO Nat
@[extern "eggshell_research_abandoned_thread_alive"] opaque threadAlive (identity : @& Nat) : IO Bool

/-- Areas count the allocator's pre-collection bookkeeping, including delayed
remote frees. A block census first consolidates those free lists in the
allocator's diagnostic API. Neither is a whole-process reachability proof. -/
def snapshot (census : Bool := false) : IO Json := do
  let raw ← snapshotRaw census
  let fields ← (raw.splitOn "\n").filterMapM fun line => do
    if line.isEmpty then return none
    let [key,value] := line.splitOn "=" | throw (IO.userError "invalid abandoned heap observation")
    let some value := value.toNat? | throw (IO.userError "invalid abandoned heap counter")
    return some (key,toJson value)
  let value := Json.mkObj fields
  unless value.getObjValD "version" == toJson (223 : Nat) && value.getObjValD "enabled" == toJson (1 : Nat) do
    throw (IO.userError "abandoned observation lacks its required ABI/enablement")
  return value
end Eggshell.Research.AbandonedHeap
