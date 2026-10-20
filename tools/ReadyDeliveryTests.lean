import Eggshell.Install

open Lean Eggshell Eggshell.Plugin

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

/-- A child pipe fixture, exercising the actual exchange/cancellation boundary.
It never calls a model or treats its progress frame as a delivered body. -/
private def worker : IO UInt32 := do
  let input ← IO.getStdin
  let output ← IO.getStdout
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let request ← IO.ofExcept (Json.parse line)
    let identity ← IO.ofExcept (request.getObjValAs? Worker.SearchIdentity "identity")
    let mode ← IO.ofExcept (request.getObjValAs? String "mode")
    let emit := fun frame => do
      output.putStrLn (toJson (frame : Worker.SearchFrame)).compress
      output.flush
    if mode == "no-ready" then IO.sleep 2000
    else if mode == "malformed" then
      output.putStrLn "not a search frame"
      output.flush
      IO.sleep 2000
    else if mode == "late" then
      IO.sleep 220
      emit (.ready identity)
      IO.sleep 2000
    else if mode == "foreign-reply" then
      emit (.reply {identity with turn := "other-turn"} none)
      IO.sleep 2000
    else
      IO.sleep 30
      let actual := if mode == "foreign-turn" then {identity with turn := "other-turn"}
        else if mode == "foreign-epoch" then {identity with epoch := identity.epoch + 1}
        else if mode == "foreign-receipt" then {identity with receipt := some "other-receipt"}
        else if mode == "foreign-deadline" then {identity with deadline := identity.deadline + 1000}
        else identity
      emit (.ready actual)
      if mode == "duplicates" then
        for _ in List.range 20 do
          IO.sleep 60
          emit (.ready identity)
      else if mode == "ready-only" || mode.startsWith "foreign-" then IO.sleep 2000
      else IO.sleep 230
    let body := {pendingSearch with text := "ORIGINAL_CLOCK_BODY", reason := "fixture"}
    emit (.reply identity (some body))
  pure 0

private def scenario : IO UInt32 := do
  let mut rows := []
  let cases := [("finish", true, true), ("continuation", false, false),
    ("no-ready", true, false), ("foreign-turn", true, false),
    ("foreign-epoch", true, false), ("foreign-receipt", true, false),
    ("foreign-deadline", true, false), ("foreign-reply", true, false),
    ("late", true, false), ("malformed", true, false),
    ("ready-only", true, false), ("duplicates", true, false)]
  try
    for (mode, finishReady, succeeds) in cases do
      let started ← IO.monoMsNow
      let identity : Worker.SearchIdentity := {
        turn := "same-turn", epoch := 7, deadline := started + 550, receipt := some mode }
      let ready ← IO.mkRef ([] : List Nat)
      let policy : Worker.SearchPolicy := {
        identity, finishReady, onReady := fun now => ready.modify (· ++ [now]) }
      let payload := Json.mkObj [("identity", toJson identity), ("mode", toJson mode)]
      let response ← Worker.exchange ("progress-" ++ mode) "search" payload
        (started + 160) (some policy)
      let elapsed := (← IO.monoMsNow) - started
      check (elapsed < 850) s!"{mode}: exchange exceeded the upstream deadline and cancellation allowance"
      if succeeds then
        let some response := response | throw (IO.userError "ready search was killed at the discovery cutoff")
        let body ← IO.ofExcept (fromJson? response : Except String (Option Handoff))
        check (body.any (·.text == "ORIGINAL_CLOCK_BODY")) "progress was confused with a final body"
        check (elapsed ≥ 230 && (← ready.get).length == 1) "ready completion did not cross the old cutoff"
      else
        check response.isNone s!"{mode}: a stalled/foreign/late/progress-only search returned a body"
        if mode == "ready-only" then
          check (elapsed ≥ 500) "checked progress did not retain the original remaining deadline"
        else
          check (elapsed < 450) s!"{mode}: invalid or disallowed progress extended the discovery cutoff"
      if mode.startsWith "foreign-" || mode == "late" || mode == "no-ready" || mode == "malformed" then
        check (← ready.get).isEmpty s!"{mode}: foreign/invalid/late progress was recorded as ready"
      rows := rows ++ [Json.mkObj [("mode", toJson mode), ("elapsedMs", toJson elapsed),
        ("body", toJson succeeds), ("readyFrames", toJson (← ready.get).length)]]
    let mut checks := 0
    let expected : Worker.SearchIdentity := {turn := "t", epoch := 3, deadline := 1000, receipt := some "r"}
    for actual in [expected, {expected with turn := "x"}, {expected with epoch := 4},
        {expected with receipt := none}, {expected with deadline := 1001}] do
      for cutoff in [0, 1, 100, 1000, 1200] do
        for arrived in [0, 1, 99, 100, 999, 1000, 1200] do
          for allowed in [false, true] do
            let result := Worker.readyDeadline expected actual allowed cutoff arrived
            check (result ≤ expected.deadline) "progress extended the original deadline"
            unless allowed && expected == actual && arrived < cutoff do
              check (result ≤ cutoff) "unready/foreign/late progress extended the cutoff"
            checks := checks + 1
    let stamp : RequestStamp := {turn := "t", epoch := 3, deadline := 1000}
    let pending := some (toJson (some pendingSearch))
    let mut completionChecks := 0
    for finishReady in [false, true] do
      for ready in [false, true] do
        let completion := configuredSearchDeadline finishReady ready 100 1000
        check (completion == if finishReady && ready then 1000 else 100)
          "status and transport completion deadlines diverged"
        check (toJson (incompleteSemanticStatus pending 200 completion) ==
            toJson (if finishReady && ready then SemanticSearchStatus.pending else .timedOut))
          "a ready but pending result was mislabeled as a discovery timeout"
        completionChecks := completionChecks + 1
    for phase in [0, 1, 100, 1000, 1200] do
      check (configuredSearchDeadline false false phase 1000 ≤ 1000)
        "status extended the upstream deadline"
      completionChecks := completionChecks + 1
    let frame := toJson (Worker.SearchFrame.ready expected)
    for (turn, epoch, now) in [("t", 3, 999), ("x", 3, 999), ("t", 4, 999), ("t", 3, 1000)] do
      match Worker.SearchDelivery.ofReply stamp turn epoch now 120000 (some frame) with
      | .found .. => throw (IO.userError "a progress frame became a Handoff")
      | _ => pure ()
    IO.println (Json.mkObj [("passed", toJson true), ("policyChecks", toJson checks),
      ("completionChecks", toJson completionChecks),
      ("nativePipeCases", toJson rows), ("generationModelCalls", toJson (0 : Nat)),
      ("productionAdoption", toJson false)]).compress
    pure 0
  finally Worker.shutdown

def main (arguments : List String) : IO UInt32 := do
  if arguments == ["codex-worker", "search"] then return ← worker
  scenario
