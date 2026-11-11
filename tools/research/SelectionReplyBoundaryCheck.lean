module
public import tools.research.SelectionReplyBoundary
public import tools.research.SelectionReceipt
import Lean.Data.Json.FromToJson
@[expose] public section
namespace Eggshell.Research.SelectionReplyBoundaryCheck
open Lean Plugin

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)

/-- A wire-bound reproducer uses the actual captured private diagnostic and
the fixed canonical body. It is not a successful real-hook delivery claim. -/
def run (inputPath output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve reply-boundary evidence"
  let input ← read inputPath
  let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let trial : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "output"))
  let clients ← IO.ofExcept (fromJson? (α := Array Json) (← read (trial/"prime.json")))
  let some first := clients[0]? | throw (IO.userError "captured first prime missing")
  let receipt ← IO.ofExcept (first.getObjValAs? String "receipt")
  let diagnostics ← Receipt.readSelection (data/"receipts"/receipt)
  let topics ← IO.ofExcept (input.getObjValAs? (Array Json) "topics")
  let some topic := topics[0]? | throw (IO.userError "canonical topic missing")
  let body ← IO.FS.readFile (.mk (← IO.ofExcept (topic.getObjValAs? String "body")))
  let handoff : Handoff := {
    text := body,reason := "actual diagnostic / fixed body wire reproducer"
    deliveredGraphs := [],completed := 0,advisory := 0,localUnions := 0,
    coveredFragments := [],blocksCurrent := false,selectionPlan := some diagnostics}
  let reply : Worker.SearchReply := ⟨some handoff,⟨.completed,.configured,0,0,0,0⟩⟩
  let original := toJson reply
  let bounded := SelectionReplyBoundary.encode (SelectionReplyBoundary.forDelivery reply)
  let originalBytes := original.compress.utf8ByteSize
  let boundedBytes := bounded.compress.utf8ByteSize
  check (originalBytes+1024 > Daemon.maxFrameBytes && boundedBytes+1024 ≤ Daemon.maxFrameBytes)
    "actual private plan did not reproduce the original reply bound"
  let restored ← IO.ofExcept (fromJson? (α := Worker.SearchReply) bounded)
  check (restored.handoff.map (·.text) == some body && restored.handoff.all (·.selectionPlan.isNone))
    "private diagnostic removal changed the exact body or retained diagnostics"
  check (toJson (restored.handoff.map (·.acknowledgmentProjection)) ==
    toJson (reply.handoff.map (·.acknowledgmentProjection))) "private diagnostic removal changed ACK projection"
  let empty : Worker.SearchReply := {reply with handoff := none}
  let restoredEmpty ← IO.ofExcept (fromJson? (α := Worker.SearchReply)
    (SelectionReplyBoundary.encode (SelectionReplyBoundary.forDelivery empty)))
  check restoredEmpty.handoff.isNone "completed empty reply became evidence"
  IO.FS.writeFile output (Json.mkObj [("receipt",toJson receipt),("diagnosticBytes",toJson diagnostics.compress.utf8ByteSize),
    ("originalCompactReplyBytes",toJson originalBytes),("publicCompactReplyBytes",toJson boundedBytes),
    ("framingAllowanceBytes",toJson (1024 : Nat)),("unchangedFrameBoundBytes",toJson Daemon.maxFrameBytes),
    ("originalBoundRejectionReproduced",toJson true),("publicReplyFits",toJson true),
    ("exactBodyAndAckProjectionPreserved",toJson true),("completedEmptyPreserved",toJson true),
    ("actualHookVerified",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.SelectionReplyBoundaryCheck
