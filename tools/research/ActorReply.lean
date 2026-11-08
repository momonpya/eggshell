module
public import Eggshell.OperationWire
@[expose] public section

namespace Eggshell.Research.ActorReply
open Lean Plugin

/-- Construct the existing complete operation envelope on the producer.
Only the resulting string crosses the operation promise, not its JSON tree. -/
def complete (id : String) (payload : Json) : String :=
  (toJson ({id,completed := true,payload} : OperationWire.Reply)).compress

def empty (id : String) (busy : Bool := false) : String :=
  (toJson ({id,completed := false,payload := Json.null,busy} : OperationWire.Reply)).compress

/-- Preserve the previous payload admission test and its envelope headroom. -/
def checked (id : String) (payload : Json) (budget : Nat) : Option String :=
  if payload.compress.utf8ByteSize+1024 ≤ budget then some (complete id payload) else none

theorem complete_wire (id : String) (payload : Json) : complete id payload =
    (toJson ({id,completed := true,payload,busy := false} : OperationWire.Reply)).compress := rfl

theorem empty_wire (id : String) (busy : Bool) : empty id busy =
    (toJson ({id,completed := false,payload := Json.null,busy} : OperationWire.Reply)).compress := rfl

theorem checked_exact (id : String) (payload : Json) (budget : Nat) :
    checked id payload budget =
      ((some payload).filter (fun value => value.compress.utf8ByteSize+1024 ≤ budget)).map (complete id) := by
  unfold checked
  by_cases fits : payload.compress.utf8ByteSize+1024 ≤ budget <;> simp [Option.filter,fits]

theorem checked_admitted (id : String) (payload : Json) (budget : Nat)
    (fits : payload.compress.utf8ByteSize+1024 ≤ budget) :
    checked id payload budget = some (complete id payload) := by simp [checked,fits]

theorem checked_rejected (id : String) (payload : Json) (budget : Nat)
    (large : budget < payload.compress.utf8ByteSize+1024) : checked id payload budget = none := by
  simp [checked,Nat.not_le_of_lt large]

end Eggshell.Research.ActorReply
