import Eggshell.Install

open Lean Eggshell Eggshell.Plugin

/-- An explicit native demand shared by every implementation in a diagnostic.
It does not recreate transport scheduling or certify a token improvement. -/
structure DeliveryDemand where
  pending : PendingTurn
  current : String
  initialClaims : List String
  staged : Bool
  deriving FromJson

/-- All compared native publishers reconcile the reply against delivery claims.
Retain both packets instead of treating an internal result as published text. -/
def auditFinalize (handoff : Option Handoff) (claims : List String) (chars : Nat) :
    Option Handoff :=
  handoff.bind fun value =>
    (value.reconcileDelivery claims chars Config.nativeHandoffBytes).map (·.handoff)

def main (arguments : List String) : IO UInt32 := do
  try
    let [database, demandFile, cache, output] := arguments |
      throw (IO.userError "delivery_demand_audit DB DEMAND_JSON CACHE OUTPUT")
    let demand ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk demandFile)) >>=
      fromJson? (α := DeliveryDemand))
    let pending := demand.pending
    let observed := (observedRoots pending).map nativeHistoryKey
    let claims := (demand.initialClaims ++ observed).eraseDups
    let staged ← if demand.staged then IO.ofExcept (stagedGraphValues pending)
      else pure []
    let snapshot ← DB.PageMap.pin (.mk database)
    let membership ← staged.mapM fun value => do
      pure (← Persistence.Store.findNode? snapshot value).isSome
    let workspace := System.FilePath.mk pending.cwd
    let targets := SourceEvidence.workTargets? workspace demand.current
    let started ← IO.monoMsNow
    let provider := (← IO.appPath).withFileName "eggshell"
    let selection : Config.Selection := {
      label := pending.profile, read := [⟨"work", .mk database⟩], write := none
      semanticMatcher := some [provider.toString, "search-provider", "--cache", cache]
      handoffChars := pending.handoffChars, handoffBytes := some Config.nativeHandoffBytes }
    let context : SourceContext := {
      workspace, deadline := started + 300000, question := pending.prompt
      targets, native := true }
    let handoff ← automaticHandoff selection demand.current claims true none staged true
      pending.localUnion (some context)
    let reconciled := auditFinalize handoff claims pending.handoffChars
    IO.FS.writeFile (.mk output) (Json.mkObj [
      ("scope", toJson "Warm shared native demand; not historical transport or token replay"),
      ("elapsedMs", toJson ((← IO.monoMsNow) - started)),
      ("current", toJson demand.current), ("question", toJson pending.prompt),
      ("targets", toJson targets), ("claims", toJson claims),
      ("observedClaims", toJson observed),
      ("stagedValues", toJson (staged.map Persistence.valueToJson)),
      ("stagedRootsPublished", toJson membership),
      ("handoff", toJson handoff), ("reconciled", toJson reconciled)]).compress
    return 0
  catch error =>
    IO.eprintln s!"delivery demand audit: {error}"
    return 1
