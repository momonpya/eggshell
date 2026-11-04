import Main
open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.SingleSearchChecks
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def body : Handoff := {pendingSearch with text := "frozen-controller-body",reason := "controller-complete"}
def request (started cutoff deadline : Nat) : Worker.Search := {
  pending := {
    sessionId := "controller",turnId := "turn",cwd := "/",prompt := "frozen query",profile := "work",
    semanticMatcher := some ["/bin/cat"],read := ["frozen-source"],write := none,handoffChars := 120000,
    projection := .automatic,inputBoundary := some ⟨toJson "private-cut"⟩,
    preparedInputs := some ⟨toJson "prepared-cut"⟩}
  state := {profile := "work"},work := "frozen work",enforce := false,startedAt := started,
  semanticCutoff := some cutoff,deadline,originals := some [],prepared := some #[] }
def sameInputs (original actual : Worker.Search) : Bool :=
  toJson original.pending == toJson actual.pending && toJson original.prepared == toJson actual.prepared &&
  toJson original.originals == toJson actual.originals && toJson original.owners == toJson actual.owners &&
  original.identity == actual.identity

/-- An intentionally unresponsive native worker owns a real descendant.
The parent consumes this first diagnostic line before using the worker pipe. -/
def blocking : IO UInt32 := do
  let child ← IO.Process.spawn {cmd := "/bin/sleep",args := #["600"],stdin := .null,stdout := .null,stderr := .null}
  let output ← IO.getStdout
  output.putStrLn (toString child.pid)
  output.flush
  try
    let _ ← child.wait
    pure 0
  finally
    try child.kill catch _ => pure ()

def blockedSlot : IO (Worker.Slot × Nat) := do
  let child : Worker.Child ← IO.Process.spawn {
    cmd := (← IO.appPath).toString,args := #["single-search-blocking"],setsid := true,
    stdin := .piped,stdout := .piped,stderr := .null }
  let line ← child.stdout.getLine
  let some descendant := line.trimAscii.toString.toNat? | throw (IO.userError "controlled descendant did not start")
  return (⟨← Std.Mutex.new (),← Std.Mutex.new (.open (some child))⟩,descendant)

def policy (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier controller checks"
  IO.FS.createDir root
  let mut rows := #[]
  for label in ["body","empty","failed","pending","queued-expired","ready"] do
    let started ← IO.monoMsNow
    let cutoff := if label == "queued-expired" then started-1 else started+100
    let query := request (started-2) cutoff (started+1500)
    let semanticCalls ← IO.mkRef 0
    let lexicalCalls ← IO.mkRef 0
    let readyCalls ← IO.mkRef 0
    let result ← Worker.executeUsing query (fun actual ready => do
      check (sameInputs query actual) "a phase replaced the exact original or private boundary"
      if actual.route == .lexical then
        lexicalCalls.modify (·+1)
        return some body
      semanticCalls.modify (·+1)
      if label == "failed" then throw (IO.userError "controlled semantic failure")
      if label == "pending" then return some pendingSearch
      if label == "empty" then return none
      if label == "ready" then ready (← IO.monoMsNow); IO.sleep 150
      return some body) (fun _ => readyCalls.modify (·+1))
    let semantic ← semanticCalls.get
    let lexical ← lexicalCalls.get
    let retry := ["failed","pending","queued-expired"].contains label
    check (lexical == (if retry then 1 else 0)) s!"wrong fallback count: {label}"
    check (semantic == (if label == "queued-expired" then 0 else 1)) s!"semantic work restarted: {label}"
    check (result.handoff.isNone == (label == "empty")) "accepted empty result became transport failure or a body"
    check (result.trace.route == (if retry then .lexical else .configured)) "trace changed the actual route"
    check (result.trace.warmRequests == 0 && result.trace.warmMs == 0) "a phase invented warm work"
    let expected : SemanticSearchStatus := if label == "failed" then .failed else if label == "pending" then .pending
      else if label == "queued-expired" then .timedOut else .completed
    check (result.trace.semantic == expected) s!"wrong semantic outcome: {label}"
    if label == "ready" then
      check ((← readyCalls.get) == 1 && (← IO.monoMsNow) > cutoff) "early readiness did not retain the original finish window"
    let decoded ← IO.ofExcept (fromJson? (toJson result) : Except String Worker.SearchReply)
    check (toJson decoded == toJson result) "structured reply lost status or accepted empty"
    let stamp : RequestStamp := {turn := query.pending.turnId,epoch := query.state.epoch,deadline := query.deadline}
    if label == "empty" then
      match Worker.SearchDelivery.ofReply stamp stamp.turn stamp.epoch (← IO.monoMsNow) 120000 (some (toJson decoded.handoff)) with
      | .empty _ => pure ()
      | _ => throw (IO.userError "accepted empty reply changed its delivery classification")
    match Worker.SearchDelivery.ofReply stamp stamp.turn stamp.epoch stamp.deadline 120000 (some (toJson decoded.handoff)) with
    | .incomplete _ _ => pure ()
    | _ => throw (IO.userError "a late reply passed the original deadline")
    rows := rows.push (Json.mkObj [("case",toJson label),("semanticCalls",toJson semantic),
      ("lexicalCalls",toJson lexical),("trace",toJson result.trace),("elapsedMs",toJson ((← IO.monoMsNow)-started))])
  let (slot,descendant) ← blockedSlot
  try
    let started ← IO.monoMsNow
    let query := request started (started+80) (started+2000)
    let reply ← Worker.executeUsing query fun actual signal => do
      check (sameInputs query actual) "blocked worker fallback changed its frozen input"
      if actual.route == .lexical then
        check (!(← Numerical.alive descendant)) "fallback overlapped the retired worker descendant"
        return some body
      let some window := Worker.OpenWindow.check (started+80) (← IO.monoMsNow) |
        throw (IO.userError "controlled worker missed its initial window")
      let some result ← Worker.exchangeSlot slot "search" (toJson actual) (started+80)
          (some {identity := actual.identity,finishReady := true,onReady := signal}) window |
        throw (IO.userError "owned worker retired without a reply")
      IO.ofExcept (fromJson? result : Except String (Option Handoff))
    check (reply.trace.route == .lexical && reply.trace.semantic == .timedOut &&
      (← IO.monoMsNow)-started < 1000) "blocked worker group was not retired before fallback"
    rows := rows.push (Json.mkObj [("case",toJson "blocked-worker-group"),("descendantRetired",toJson true),
      ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("trace",toJson reply.trace)])
  finally Worker.closeSlot slot
  let (slot,descendant) ← blockedSlot
  try
    let started ← IO.monoMsNow
    let query := request started (started+1000) (started+2000)
    let some window := Worker.OpenWindow.check (started+1000) (← IO.monoMsNow) |
      throw (IO.userError "cancelled worker missed its initial window")
    let owned ← IO.asTask (Worker.exchangeSlot slot "search" (toJson query) (started+1000)
      (some {identity := query.identity}) window) .dedicated
    IO.sleep 15
    IO.cancel owned
    let result ← TaskDeadline.wait owned ((← IO.monoMsNow)+1000)
    check (result.isNone && !(← Numerical.alive descendant)) "cancelled worker retained its descendant"
    rows := rows.push (Json.mkObj [("case",toJson "cancelled-worker-group"),("descendantRetired",toJson true),
      ("elapsedMs",toJson ((← IO.monoMsNow)-started))])
  finally Worker.closeSlot slot
  let started ← IO.monoMsNow
  let query := request started (started+1000) (started+2000)
  let pid ← IO.mkRef 0
  let lexical ← IO.mkRef 0
  let owned ← IO.asTask (Worker.executeUsing query fun actual _ => do
    if actual.route == .lexical then lexical.modify (·+1); return some body
    SemanticMatcher.withProvider ["/bin/cat"] fun running => do
      pid.set running.child.pid.toNat
      SemanticMatcher.withResponseDeadline running do
        let _ ← running.child.stdout.getLine
        pure (some body)) .dedicated
  while (← pid.get) == 0 do
    check (!(← IO.hasFinished owned) && (← IO.monoMsNow) < started+1000) "controlled provider did not start"
    IO.sleep 5
  IO.cancel owned
  let cancelled ← (TaskDeadline.wait owned ((← IO.monoMsNow)+1000)).toBaseIO
  check (cancelled.toOption.isNone && (← lexical.get) == 0 && !(← Numerical.alive (← pid.get)))
    "cancelled request started fallback or retained a provider"
  rows := rows.push (Json.mkObj [("case",toJson "cancelled"),("noFallback",toJson true),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started))])
  let expired ← IO.monoMsNow
  let touched ← IO.mkRef false
  let rejected ← try
    let _ ← Worker.executeUsing (request expired expired expired) fun _ _ => do
      touched.set true
      pure (some body)
    pure false
    catch _ => pure true
  check (rejected && !(← touched.get)) "expired upstream request started work"
  IO.FS.writeFile (root/"report.json") ((Json.mkObj [("allPassed",toJson true),("cases",toJson rows),
    ("expiredBeforeAction",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress++"\n")
end Eggshell.Research.SingleSearchChecks
