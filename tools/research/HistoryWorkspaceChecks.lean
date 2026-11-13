import tools.research.HistoryDecision
import tools.research.HistoryProtocolQualification
import Lean.Data.Json.Parser
open Lean HistoryAccess HistoryWorkspace HistoryDecision
namespace HistoryWorkspaceChecks
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def readArgs (document first : Nat) : Json := Json.mkObj [("document",toJson document),("first",toJson first)]
def action (name : String) (args : Json) : Json := args.setObjVal! "action" (toJson name)
def batchJson (actions : Array Json) : Json := Json.mkObj [("actions",toJson actions)]
def selectArgs (receipt first stop : Nat) : Json := Json.mkObj [
  ("spans",toJson #[Json.mkObj [("receipt",toJson receipt),("first",toJson first),("stop",toJson stop)]])]
def selected (receipt first stop : Nat) : Json := batchJson #[action "select_evidence" (selectArgs receipt first stop)]
def userData (request : Json) : IO Json := do
  let messages ← IO.ofExcept (request.getObjValAs? (Array Json) "messages")
  let some message := messages[1]? | throw (IO.userError "model request lost its user data")
  IO.ofExcept ((message.getObjValAs? String "content") >>= Json.parse)
def run (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve the workspace contract result"
  let original := "Observed guard\n"++String.ofList (List.replicate 220 'a')++
    "\nif (pending > limit) return deferred;\notherwise retry();\n"
  let json := "{\"サービス\":\"青磁\",\"保持日数\":17,\"満杯時破棄\":false}"
  let store := prepare "project-A/snapshot-checked" #[
    ⟨"guard-original","MCP read resource A",original⟩,⟨"policy-original","MCP read resource B",json⟩,
    ⟨"large-original","arbitrary original observation",String.ofList (List.replicate 30000 'x')⟩]
  let empty ← IO.ofExcept (HistoryWorkspace.empty store)
  let (first,reply,_) ← IO.ofExcept (HistoryWorkspace.execute store empty "read_history" (readArgs 0 0))
  check (reply.getObjValD "text" == toJson original) "read did not return the immutable original"
  let initialCharge := first.session.readCharacters
  let (legacy,_,_) ← IO.ofExcept (HistoryAccess.execute store first.session "read_history" (readArgs 0 0))
  check (legacy.readCharacters == initialCharge*2 && legacy.seen.size == 2)
    "unchanged baseline did not reproduce repeated-read charging"
  let mut reused := first
  for _ in [:12] do
    let (next,reply,_) ← IO.ofExcept (HistoryWorkspace.execute store reused "read_history" (readArgs 0 0))
    check (reply.getObjValD "receipt" == toJson (0 : Nat)) "cached page acquired another receipt"
    reused := next
  check (reused.pages.size == 1 && reused.session.readCharacters == initialCharge)
    "reopening the same original consumed the read budget"
  let (afterList,_,_) ← IO.ofExcept (HistoryWorkspace.execute store reused "list_history" (Json.mkObj [("cursor",toJson (0 : Nat))]))
  let commands := batchJson #[action "read_history" (readArgs 1 0)]
  let (afterSecond,results,_) ← IO.ofExcept (HistoryDecision.run store afterList 6 commands)
  let request := HistoryDecision.request store afterSecond "Inspect the guard and policy" 5 results
  let data ← userData request
  let opened ← IO.ofExcept ((data.getObjValD "workspace").getObjValAs? (Array Json) "opened_originals")
  check (opened.size == 2 && opened[0]!.getObjValD "text" == toJson original &&
    opened[1]!.getObjValD "text" == toJson json) "a prior read disappeared or was reduced to a preview"
  let modelResults ← IO.ofExcept (data.getObjValAs? (Array Json) "last_results")
  check (!((modelResults[0]!.getObjValD "reply").getObjVal? "text").isOk)
    "last read text was duplicated outside the complete workspace"
  check (!(request.getObjVal? "tools").isOk && request.getObjValD "response_format" != Json.null)
    "candidate retained the optional native-tool protocol"
  let (picked,_,done) ← IO.ofExcept (HistoryDecision.run store afterSecond 1 (selected 0 235 original.length))
  check done "valid prior-read selection did not finish"
  let payload ← IO.ofExcept ((HistoryAccess.payload store picked.session).getArr?)
  check (payload.size == 1 && payload[0]!.getObjValD "snapshot" == toJson store.snapshot &&
    payload[0]!.getObjValD "owner" == toJson "guard-original" &&
    payload[0]!.getObjValD "text" == toJson (slice store.originals[0]!.text 235 original.length))
    "final payload changed original text or provenance"
  let refused := fun (value : Except String (State store × Json × Bool)) => !value.isOk
  let selectionRefused := fun (value : Except String (State store × Json × Bool)) =>
    match value with
    | .error _ => true
    | .ok (unchanged,results,finished) => !finished && unchanged.session.selected.isEmpty &&
        ((results.getArr?).toOption.any fun values => values.any fun result =>
          ((result.getObjValD "reply").getObjVal? "error").isOk)
  check (refused (HistoryWorkspace.execute store empty "select_evidence" (selectArgs 0 0 1)))
    "unread selection was accepted"
  check (selectionRefused (HistoryDecision.run store afterSecond 1 (selected 9 0 1))) "unknown receipt was accepted as evidence"
  check (selectionRefused (HistoryDecision.run store afterSecond 1 (selected 0 0 (original.length+1))))
    "selection escaped the returned original"
  check (!(HistoryDecision.batch 1 (batchJson #[action "read_history" (readArgs 0 0)])).isOk)
    "final decision allowed another read loop"
  check ((HistoryDecision.batch 6 (batchJson #[action "read_history" (readArgs 1 0),
    action "select_evidence" (Json.mkObj [("spans",toJson (#[] : Array Json))])])).isOk == false)
    "selection could observe a read from the same unreturned batch"
  check (!(HistoryDecision.decode (action "write_file" (Json.mkObj [("path",toJson "/tmp/forbidden")]))).isOk)
    "model acquired filesystem write authority"
  check (!(HistoryDecision.decode ((action "read_history" (readArgs 0 0)).setObjVal! "path" (toJson "/tmp/forbidden"))).isOk)
    "unknown action fields bypassed the schema"
  check (!(HistoryWorkspace.check store "project-B/snapshot-checked" afterSecond.session).isOk)
    "foreign project snapshot accepted the same receipt numbers"
  check (!(HistoryWorkspace.check store store.snapshot {empty.session with selected := #[⟨0,0,1⟩]}).isOk)
    "restored state manufactured an unread selection"
  check (!(HistoryWorkspace.check store store.snapshot {first.session with readCharacters := initialCharge+1}).isOk)
    "restored state had an inconsistent read charge"
  check ((HistoryWorkspace.check store store.snapshot {first.session with
    seen := first.session.seen++first.session.seen,readCharacters := initialCharge*2}).isOk == false)
    "duplicate pages were admitted into the workspace"
  let mut large := empty
  for page in [:6] do
    let (next,_,_) ← IO.ofExcept (HistoryWorkspace.execute store large "read_history" (readArgs 2 (page*2400)))
    large := next
  check (large.session.readCharacters == 14400 &&
    refused (HistoryWorkspace.execute store large "read_history" (readArgs 2 14400))) "read ceiling changed"
  let (sameLarge,_,_) ← IO.ofExcept (HistoryWorkspace.execute store large "read_history" (readArgs 2 0))
  check (sameLarge.session.readCharacters == 14400) "cached reopening failed near the read ceiling"
  check (HistoryDecision.contextFits 7808 && !HistoryDecision.contextFits 7809) "context capacity silently grew"
  let (noneSelected,_,ended) ← IO.ofExcept (HistoryDecision.run store picked 1
    (batchJson #[action "no_evidence" (Json.mkObj [])]))
  check (ended && noneSelected.session.selected.isEmpty) "no-evidence action retained an older selection"
  IO.FS.writeFile output (Json.mkObj [("allPassed",toJson true),
    ("priorFullOriginalRetained",toJson true),("unicodeJsonPreserved",toJson true),
    ("cachedReadKeepsReceiptAndBudget",toJson true),("originalTextAppearsOnce",toJson true),
    ("snapshotAndReadAuthorityChecked",toJson true),("invalidActionAndBatchRejected",toJson true),
    ("capacityRefusesWithoutDroppingText",toJson true),("readCharacterLimit",toJson (16000 : Nat)),
    ("modelContextLimit",toJson (8192 : Nat)),("modelCalls",toJson (0 : Nat)),
    ("actualHookDelivery",toJson false),("adopted",toJson false)]).compress
end HistoryWorkspaceChecks
#print axioms HistoryWorkspace.Page.original_characters
#print axioms HistoryWorkspace.Page.inside_original
#print axioms HistoryWorkspace.State.visible_domain
#print axioms HistoryWorkspace.State.read_bound
#print axioms HistoryWorkspace.reuse_preserves_state
#print axioms HistoryDecision.context_bound
def main : List String → IO Unit
  | ["prepare",root] => HistoryProtocolQualification.prepare (.mk root)
  | ["assess",root,manifest,output] => HistoryProtocolQualification.assess (.mk root) (.mk manifest) (.mk output)
  | [output] => HistoryWorkspaceChecks.run (.mk output)
  | _ => throw (IO.userError "HistoryWorkspaceChecks NEW-RESULT")
