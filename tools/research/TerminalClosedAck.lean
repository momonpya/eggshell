import Eggshell.PluginHooks
open Lean Eggshell.Plugin
def main : List String → IO Unit
  | [mode] => do
    let pending : PendingTurn := {
      sessionId := "closed-ack"
      turnId := "original-turn"
      cwd := "/metadata-only"
      prompt := "original query"
      profile := "work"
      semanticMatcher := none
      read := []
      write := none
      handoffChars := 500000
      closed := true
      finalMessage := some "original answer"
      projection := .automatic }
    let offer : DeliveryOffer := {
      id := "staged-offer"
      stamp := {turn := pending.turnId,epoch := 3,deadline := 1000}
      graphs := []
      text := "stale staged delivery"
      reason := "metadata boundary" }
    let state : ThreadState := {profile := "work",epoch := 3,offers := [offer]}
    let basis : AcknowledgmentBasis := ⟨offer,none,3,[]⟩
    let accepted := basis.accepts state pending 0
    IO.println (Json.mkObj [("pendingClosed",toJson pending.closed),("sameEpoch",toJson true),
      ("acknowledgmentAccepted",toJson accepted),("databaseIO",toJson false)]).compress
    if (mode == "baseline" && !accepted) || (mode == "fixed" && accepted) then
      throw (IO.userError "closed-turn acknowledgment did not have the expected policy")
    unless mode == "baseline" || mode == "fixed" do throw (IO.userError "expected baseline or fixed")
  | _ => throw (IO.userError "TerminalClosedAck baseline|fixed")
