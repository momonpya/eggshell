module
public import tools.research.ReplyOwnershipChecks
public import tools.research.ActorReply
@[expose] public section
open Lean Eggshell Eggshell.Plugin

#print axioms Eggshell.Research.ActorReply.complete_wire
#print axioms Eggshell.Research.ActorReply.empty_wire
#print axioms Eggshell.Research.ActorReply.checked_exact

-- The promise's runtime value has no Handoff, SearchReply or JSON-tree field.
example : OperationPool.Job → IO.Promise (Option String) := OperationPool.Job.reply

namespace Eggshell.Research.ActorReplyChecks
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)

def codec (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh actor reply codec output required"
  IO.FS.createDirAll root
  let large := String.ofList (List.replicate (4*1024*1024) 'x')
  let payloads := #[Json.null,toJson true,toJson (0 : Nat),toJson "日本語・한글・é・😀\n\t\"\\",
    Json.mkObj [("result",toJson large),("tail",toJson "末尾\n")]]
  let id := String.ofList (List.replicate 64 'a')
  let mut checks := 0
  for payload in payloads do
    let expected : OperationWire.Reply := {id,completed := true,payload}
    let encoded := ActorReply.complete id payload
    check (encoded == (toJson expected).compress) "producer changed operation bytes"
    let decoded ← IO.ofExcept (Json.parse encoded >>= fromJson? (α := OperationWire.Reply))
    check (toJson decoded == toJson expected) "operation wire roundtrip changed fields"
    let amount := payload.compress.utf8ByteSize+1024
    check (ActorReply.checked id payload amount == some encoded &&
      (ActorReply.checked id payload (amount-1)).isNone) "old admission boundary changed"
    checks := checks+4
  for busy in [false,true] do
    let expected : OperationWire.Reply := {id,completed := false,payload := Json.null,busy}
    check (ActorReply.empty id busy == (toJson expected).compress) "empty or busy changed operation bytes"
    let decoded ← IO.ofExcept (Json.parse (ActorReply.empty id busy) >>= fromJson? (α := OperationWire.Reply))
    check (toJson decoded == toJson expected) "empty or busy wire fields changed"
    checks := checks+2
  IO.FS.writeFile (root/"result.json") (Json.mkObj [("checks",toJson checks),
    ("completeEmptyBusyWireByteExact",toJson true),("unicodeEscapesAndLargePayloadRoundtrip",toJson true),
    ("oldPayloadAdmissionBoundaryExact",toJson true),("promiseRuntimePayload",toJson "Option String"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.ActorReplyChecks
