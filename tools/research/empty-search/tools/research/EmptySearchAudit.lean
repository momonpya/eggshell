import Eggshell.PluginHooks
import Lean

open Lean Eggshell Eggshell.Plugin

namespace Eggshell.Research.EmptySearchAudit

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

/-- The empty constructor is reachable only for a current accepted reply whose
payload successfully decodes to no new Handoff. Transport absence is different. -/
theorem accepted_empty_reply (stamp : RequestStamp) (turn : String)
    (epoch now budget : Nat) (json : Json)
    (currentTurn : stamp.turn = turn) (currentEpoch : stamp.epoch = epoch)
    (accepted : stamp.accepts turn epoch now = true)
    (parsed : (fromJson? json : Except String (Option Handoff)) = .ok none) :
    (Worker.SearchDelivery.ofReply stamp turn epoch now budget (some json)).handoff = none := by
  simp [Worker.SearchDelivery.ofReply, Worker.SearchDelivery.handoff,
    currentTurn, currentEpoch, accepted, parsed]

open Lean in
run_meta do
  for name in #[``accepted_empty_reply, ``empty_search_has_no_authority,
      ``empty_search_preserves_status] do
    for axiomName in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains axiomName do
        throwError "Empty search contract uses an unapproved axiom: {name}, {axiomName}"
  logInfo "Audited accepted empty worker result and authority-free status metadata"

private def classify {stamp : RequestStamp} {turn : String} {epoch now budget : Nat}
    (delivery : Worker.SearchDelivery stamp turn epoch now budget) : String :=
  match delivery with
  | .obsolete => "obsolete"
  | .incomplete _ _ => "incomplete"
  | .empty _ => "empty"
  | .found _ _ _ _ => "found"

private def run : IO Json := do
  let stamp : RequestStamp := {turn := "current",epoch := 7,deadline := 1000}
  let valid := Worker.SearchDelivery.ofReply stamp "current" 7 500 1000 (some Json.null)
  check (classify valid == "empty") "valid empty reply did not decode as empty"
  let mut records := #[]
  for route in [SearchRoute.configured,.lexical] do
    for status in [SemanticSearchStatus.notRequested,.completed,.pending,.timedOut,.failed] do
      let trace : SearchTrace := {
        route,semantic := status,semanticMs := 14000,lexicalMs := 8000,warmMs := 1,warmRequests := 1 }
      let metadata := emptySearchResult trace
      check (metadata.text.isEmpty && metadata.deliveredGraphs.isEmpty &&
        metadata.completed == 0 && metadata.advisory == 0 && metadata.localUnions == 0 &&
        metadata.coveredFragments.isEmpty && !metadata.blocksCurrent &&
        metadata.sourceRecords.isEmpty && metadata.sourceUses.isEmpty &&
        metadata.sourceCheckpoints.isEmpty && metadata.packet.isNone)
        "empty status metadata gained body, source checkpoint or control authority"
      check (toJson metadata.search == toJson (some trace)) "empty result changed observed status"
      check (metadata.reason != "search-incomplete") "valid empty result became incomplete"
      let stdout := withSearchNotice (some metadata) emptyHook
      let json ← IO.ofExcept (Json.parse stdout)
      check ((json.getObjVal? "hookSpecificOutput").toOption.isNone)
        "empty result injected an additionalContext body"
      let notice := (json.getObjValAs? String "systemMessage").toOption
      let expectedNotice := route == .lexical && status != .notRequested
      check (notice.isSome == expectedNotice) "degraded-search notice was lost or invented"
      check ((stdout.splitOn "SEARCH INCOMPLETE").length == 1) "empty result printed incomplete body"
      records := records.push (Json.mkObj [("route",toJson route),("semantic",toJson status),
        ("reason",toJson metadata.reason),("stdout",json),("bodyBytes",toJson metadata.text.utf8ByteSize),
        ("authority",toJson false)])
  let failed : List (String × Option Json × String × Nat × Nat × String) := [
    ("missing",none,"current",7,500,"incomplete"),
    ("malformed",some (toJson true),"current",7,500,"incomplete"),
    ("expired-empty",some Json.null,"current",7,1000,"incomplete"),
    ("wrong-turn",some Json.null,"other",7,500,"obsolete"),
    ("wrong-epoch",some Json.null,"current",8,500,"obsolete")]
  let mut failures := #[]
  for (label,reply,turn,epoch,now,wanted) in failed do
    let result := Worker.SearchDelivery.ofReply stamp turn epoch now 1000 reply
    check (classify result == wanted) s!"invalid reply promoted to empty: {label}"
    failures := failures.push (Json.mkObj [("case",toJson label),("actual",toJson (classify result))])
  let oversized := {pendingSearch with text := String.ofList (List.replicate (Config.nativeHandoffBytes+1) 'x')}
  let result := Worker.SearchDelivery.ofReply stamp "current" 7 500
    (Config.nativeHandoffBytes+2) (some (toJson (some oversized)))
  check (classify result == "incomplete") "oversized bytes became publishable empty"
  let pending := Worker.SearchDelivery.ofReply stamp "current" 7 500 1000 (some (toJson (some pendingSearch)))
  check ((pending.handoff.map (·.reason)) == some "search-incomplete") "actual pending result was hidden"
  return Json.mkObj [("routeStatusCases",toJson records),("invalidReplies",toJson failures),
    ("oversizedBytesRejected",toJson true),("actualPendingRetained",toJson true),
    ("acceptedEmptyDistinct",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]

end Eggshell.Research.EmptySearchAudit

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "EmptySearchAudit NEW-OUTPUT.json")
  let path := System.FilePath.mk output
  unless !(← path.pathExists) do throw (IO.userError "keep prior empty-search audit")
  let result ← Eggshell.Research.EmptySearchAudit.run
  IO.FS.writeFile path result.pretty
  IO.println (Json.mkObj [("routeStatusCases",toJson (10 : Nat)),
    ("acceptedEmptyDistinct",toJson true),("actualPendingRetained",toJson true)]).compress
