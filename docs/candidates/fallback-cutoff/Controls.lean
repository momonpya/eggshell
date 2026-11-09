import Eggshell.OperationPool
open Lean Eggshell Eggshell.Plugin
namespace FallbackBoundaryControls
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def handoff (text : String) : Handoff := {
  text,reason := "controlled original body",deliveredGraphs := [],completed := 0,advisory := 1,
  localUnions := 0,coveredFragments := [],blocksCurrent := false }
def request (started deadline cutoff : Nat) : Worker.Search := {
  pending := {
    sessionId := "deadline-control"
    turnId := "turn"
    cwd := "/"
    prompt := "fixed question"
    profile := "work"
    semanticMatcher := some ["unused-controlled-provider"]
    read := []
    write := none
    handoffChars := 500000
    projection := .automatic }
  state := {profile := "work"}
  work := "fixed-work"
  enforce := false
  startedAt := started
  deadline
  semanticCutoff := some cutoff }
def exercise (mode : String) (oldCutoff : Bool) : IO Json := do
  let now ← IO.monoMsNow
  let cutoff := if mode == "already-expired" then now-1 else now+35
  let query := request now (now+2500) cutoff
  let lexicalCalls ← IO.mkRef (0 : Nat)
  let result ← try
    let found ← Worker.executeUsing query fun phase signal => do
      let phase := if oldCutoff && phase.route == .lexical then {phase with semanticCutoff := query.semanticCutoff} else phase
      OperationPool.ownedPhase phase.deadline (phase.semanticCutoff.getD phase.deadline) (fun ready => do
        if phase.route == .lexical then
          lexicalCalls.modify (·+1)
          return some (handoff "ORIGINAL-LEXICAL-BODY")
        if mode == "ready-then-failed" then
          ready
          IO.sleep 60
          throw (IO.userError "controlled provider failure after readiness")
        if mode == "semantic-body" then return some (handoff "SEMANTIC-BODY")
        if mode == "semantic-empty" then return none
        while !(← IO.checkCanceled) do IO.sleep 1
        throw (IO.userError "controlled semantic cancellation")) signal
    pure (Json.mkObj [("returned",toJson true),("body",toJson (found.handoff.map (·.text))),
      ("route",toJson found.trace.route),("semantic",toJson found.trace.semantic)])
    catch error => pure (Json.mkObj [("returned",toJson false),("error",toJson error.toString)])
  let elapsed := (← IO.monoMsNow)-now
  let result := result.setObjVal! "mode" (toJson mode) |>.setObjVal! "emulatedOldCutoff" (toJson oldCutoff)
    |>.setObjVal! "elapsedMs" (toJson elapsed) |>.setObjVal! "lexicalActionCalls" (toJson (← lexicalCalls.get))
  if ["already-expired","timed-out-before-ready","ready-then-failed"].contains mode then
    if oldCutoff then check (result.getObjValD "returned" == toJson false) "old cutoff unexpectedly admitted lexical body"
    else check (result.getObjValD "body" == toJson (some "ORIGINAL-LEXICAL-BODY")) "remaining hook deadline did not deliver lexical body"
  else if mode == "semantic-body" then
    check (result.getObjValD "body" == toJson (some "SEMANTIC-BODY") && (← lexicalCalls.get) == 0) "semantic body regressed"
  else
    check (result.getObjValD "returned" == toJson true && result.getObjValD "body" == Json.null && (← lexicalCalls.get) == 0)
      "valid empty semantic result became a fallback"
  check (elapsed < 2500 && !(← IO.checkCanceled)) "control exceeded upstream lifetime or cancelled its caller"
  return result
def run (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "fresh fallback control record required"
  let mut rows := #[]
  for _ in [:3] do
    for mode in ["already-expired","timed-out-before-ready","ready-then-failed"] do
      rows := rows.push (← exercise mode true)
      rows := rows.push (← exercise mode false)
    for mode in ["semantic-body","semantic-empty"] do rows := rows.push (← exercise mode false)
  IO.FS.writeFile output (Json.mkObj [("cases",toJson rows),("allPassed",toJson true),
    ("usesActualWorkerExecuteAndOwnedPhase",toJson true),("oldBehaviorEmulatedOnlyByRestoringOldCutoff",toJson true),
    ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end FallbackBoundaryControls
def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "OUTPUT required")
  FallbackBoundaryControls.run (.mk output)

#print axioms Eggshell.Plugin.Worker.Search.lexical_discards_semantic_cutoff
#print axioms Eggshell.Plugin.Worker.Search.lexical_uses_remaining_hook
