import Eggshell.Install

open Lean Eggshell Eggshell.Plugin

/-- One controlled call to the real delivery and reconciliation functions.
The caller supplies the complete observation prefix and acknowledged claims.
This does not emulate asynchronous workers or native transport deadlines. -/
structure SequenceDemand where
  pending : PendingTurn
  current : String
  claims : List String
  enforce : Bool
  evidence : Option String
  deriving FromJson

def main (arguments : List String) : IO UInt32 := do
  try
    let [database, demandFile, cache, output] := arguments |
      throw (IO.userError "delivery_sequence_audit DB DEMAND_JSON CACHE OUTPUT")
    let demand ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk demandFile)) >>=
      fromJson? (α := SequenceDemand))
    let pending := demand.pending
    let observed := (observedRoots pending).map nativeHistoryKey
    let claims := (demand.claims ++ observed).eraseDups
    let staged ← IO.ofExcept (stagedGraphValues pending)
    let snapshot ← DB.PageMap.pin (.mk database)
    unless (acceptedAdvisoryFrontier pending.prompt snapshot.head.identity claims).isSome do
      throw (IO.userError "acknowledged advisory frontier does not belong to the pinned source DB")
    let membership ← staged.mapM fun value => do
      pure (← Persistence.Store.findNode? snapshot value).isSome
    let observedMembership ← (observedRoots pending).mapM fun value => do
      pure (← Persistence.Store.findNode? snapshot value).isSome
    unless observedMembership.all id do
      throw (IO.userError "controlled publication omits an observed native outcome")
    let started ← IO.monoMsNow
    let provider := (← IO.appPath).withFileName "eggshell"
    let selection : Config.Selection := {
      label := pending.profile, read := [⟨"work", .mk database⟩], write := none
      semanticMatcher := some [provider.toString, "search-provider", "--cache", cache]
      handoffChars := pending.handoffChars, handoffBytes := some Config.nativeHandoffBytes }
    let workspace := System.FilePath.mk pending.cwd
    let context : SourceContext := {
      workspace, deadline := started + 300000, question := pending.prompt
      targets := SourceEvidence.workTargets? workspace demand.current
      native := demand.enforce || demand.evidence.isSome }
    let raw ← automaticHandoff selection demand.current claims demand.enforce
      (demand.evidence.map canonicalJson) staged true pending.localUnion (some context)
    let reconciled := raw.bind fun value =>
      (value.reconcileDelivery claims pending.handoffChars Config.nativeHandoffBytes).map (·.handoff)
    let acknowledged := reconciled.map (·.deliveredGraphs) |>.getD []
    let checkpoints := reconciled.map (fun value => value.sourceCheckpoints.map (·.key)) |>.getD []
    let next := (claims ++ checkpoints ++ acknowledged).eraseDups
    IO.FS.writeFile (.mk output) (Json.mkObj [
      ("scope", toJson "Controlled published observations and synchronous acknowledgement; no historical scheduling or token result"),
      ("elapsedMs", toJson ((← IO.monoMsNow) - started)),
      ("current", toJson demand.current), ("question", toJson pending.prompt),
      ("targets", toJson context.targets), ("claims", toJson claims),
      ("observedClaims", toJson observed),
      ("stagedValues", toJson (staged.map Persistence.valueToJson)),
      ("stagedRootsPublished", toJson membership),
      ("observedRootsPublished", toJson observedMembership),
      ("handoff", toJson raw), ("reconciled", toJson reconciled),
      ("nextClaims", toJson next)]).compress
    return 0
  catch error =>
    IO.eprintln s!"delivery sequence audit: {error}"
    return 1
