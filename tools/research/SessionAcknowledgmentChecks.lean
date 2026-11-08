import Eggshell.PluginHooks

open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.SessionAcknowledgmentChecks

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def metadata (line : Nat) : Synapses.DeliveryLedger.Projection := {
  verified := true, complete := true, rows := #[{database := "project",source := {
    subject := .file {relative := "input",fingerprint := String.ofList (List.replicate 64 'a'),bytes := 100},
    first := line,last := line }}] }

private def offer (id : String) (line now : Nat) : DeliveryOffer := {
  id,stamp := ⟨"turn",3,now+120000⟩,graphs := [id],text := id,reason := id,projection := metadata line }

private def setup (session : String) (offers : List DeliveryOffer) : IO Unit := do
  let files ← sessionFiles session
  check (!(← files.directory.pathExists)) "test refuses an old session"
  writeJson files.state ({profile := "work",epoch := 3,offers} : ThreadState)
  writeJson files.pending ({
    sessionId := session,turnId := "turn",cwd := "/fixture",prompt := "test",
    profile := "work",semanticMatcher := none,read := [],write := none,handoffChars := 500000,
    projection := .none} : PendingTurn)

private def state (session : String) : IO ThreadState := do
  let some value ← readState? (← sessionFiles session) | throw (IO.userError "missing test state")
  return value

private def savedLines (session : String) : IO (Array Nat) := do
  let some reference := (← state session).confirmedDelivery | return #[]
  return (← Synapses.DeliveryLedger.lookup reference "project").map (·.first) |>.qsort (· < ·)

/-- Deterministic interleavings use the same capture, ledger preparation and
compare-and-publish helpers as acknowledge. The unreferenced ledger commit
simulates a process disappearing immediately before session publication. -/
private def interleaving (kind : String) : IO Json := do
  let session := "ack-interleave-" ++ kind
  let first := offer "first" 1 (← IO.monoMsNow)
  setup session [first]
  let some basis ← acknowledgmentBasis? session first.id | throw (IO.userError "capture failed")
  let staged ← Synapses.DeliveryLedger.confirm session basis.epoch basis.previous basis.offer.projection
  withSession session fun files => do
    let current ← state session
    match kind with
    | "compact" => writeJson files.state (compactState current)
    | "disabled" => writeJson files.state {current with enabled := false}
    | "turn" =>
      let some pending ← readPendingBase? files | throw (IO.userError "missing turn")
      writeJson files.pending {pending with turnId := "next-turn"}
    | "replacement" =>
      let replacement := {first with text := "replacement",projection := metadata 2}
      writeJson files.state {current with offers := [replacement]}
    | "expired" => pure ()
    | "previous-head" => pure ()
    | _ => throw (IO.userError "unknown interleaving")
  let basis ← if kind == "expired" then do
      let expired := {first with stamp := {first.stamp with deadline := (← IO.monoMsNow)}}
      withSession session fun files => do
        let current ← state session
        writeJson files.state {current with offers := [expired]}
      pure {basis with offer := expired}
    else pure basis
  if kind == "previous-head" then
    let second := offer "second" 2 (← IO.monoMsNow)
    withSession session fun files => do
      let current ← state session
      writeJson files.state {current with offers := second :: current.offers}
    check (← acknowledge session second.id) "competing genuine ACK failed"
  check (!(← finishAcknowledgment session basis staged (← prepareAcknowledgment basis))) s!"accepted stale {kind} ACK"
  check ((← savedLines session) != #[1]) s!"stale {kind} head escaped into context"
  -- Resume from the actual accepted head, not the newest abandoned ledger
  -- root. This also tests recovery without any in-memory transaction state.
  let current ← state session
  let nextBase := offer "next" 3 (← IO.monoMsNow)
  let next := {nextBase with stamp := ⟨"turn",current.epoch+1,(← IO.monoMsNow)+120000⟩}
  withSession session fun files => do
    writeJson files.state {current with enabled := true,epoch := current.epoch+1,offers := [next]}
    let some pending ← readPendingBase? files | throw (IO.userError "missing turn")
    writeJson files.pending {pending with turnId := "turn"}
  check (← acknowledge session next.id) s!"next ACK failed after {kind}"
  let expected := if kind == "previous-head" then #[2,3] else #[3]
  check ((← savedLines session) == expected) s!"abandoned {kind} rows leaked into a later context"
  return Json.mkObj [("kind",toJson kind),("staleRejected",toJson true),("exactNextLines",toJson expected)]

private def concurrent : IO Json := do
  let session := "ack-concurrent"
  let now ← IO.monoMsNow
  let first := offer "first" 1 now
  let second := offer "second" 2 now
  setup session [first,second]
  let a ← IO.asTask (acknowledge session first.id) .dedicated
  let b ← IO.asTask (acknowledge session second.id) .dedicated
  check (← IO.ofExcept a.get) "first concurrent ACK failed"
  check (← IO.ofExcept b.get) "second concurrent ACK failed"
  check ((← savedLines session) == #[1,2]) "concurrent ACK lost an accepted head"
  let current ← state session
  check current.offers.isEmpty "concurrent ACK retained an offer"
  return Json.mkObj [("kind",toJson "concurrent"),("bothAccepted",toJson true),("exactLines",toJson (#[1,2] : Array Nat))]

private def expiredEntry : IO Json := do
  let session := "ack-expired-entry"
  let base := offer "expired" 1 0
  let stale := {base with stamp := ⟨"turn",3,0⟩}
  setup session [stale]
  check (!(← acknowledge session stale.id)) "expired ACK entry was accepted"
  check ((← state session).confirmedDelivery.isNone) "expired ACK created a context head"
  return Json.mkObj [("kind",toJson "expired-entry"),("rejectedWithoutLedger",toJson true)]

private def abandonedTail : IO Json := do
  let session := "ack-abandoned-tail"
  let first := offer "accepted" 1 (← IO.monoMsNow)
  setup session [first]
  check (← acknowledge session first.id) "initial accepted head failed"
  let second := offer "abandoned" 2 (← IO.monoMsNow)
  withSession session fun files => do
    let current ← state session
    writeJson files.state {current with offers := [second]}
  let some basis ← acknowledgmentBasis? session second.id | throw (IO.userError "missing abandoned basis")
  let staged ← Synapses.DeliveryLedger.confirm session basis.epoch basis.previous second.projection
  withSession session fun files => do
    let current ← state session
    writeJson files.state {current with epoch := 4,offers := []}
  check (!(← finishAcknowledgment session basis staged (← prepareAcknowledgment basis))) "abandoned tail escaped after a turn change"
  let nextBase := offer "next" 3 (← IO.monoMsNow)
  let next := {nextBase with stamp := {nextBase.stamp with epoch := 4}}
  withSession session fun files => do
    let current ← state session
    writeJson files.state {current with offers := [next]}
  check (← acknowledge session next.id) "next ACK after abandoned tail failed"
  check ((← savedLines session) == #[1,3]) "unreferenced physical tail leaked through an accepted historical head"
  return Json.mkObj [("kind",toJson "abandoned-tail"),("exactLines",toJson (#[1,3] : Array Nat))]

def run (output : String) : IO Unit := do
  let mut results := #[]
  for kind in #["compact","disabled","turn","replacement","expired","previous-head"] do
    results := results.push (← interleaving kind)
  results := results.push (← concurrent)
  results := results.push (← expiredEntry)
  results := results.push (← abandonedTail)
  writeJson (.mk output) (Json.mkObj [("checks",toJson results),("answeringModelCalls",toJson (0 : Nat))])

end Eggshell.Research.SessionAcknowledgmentChecks
