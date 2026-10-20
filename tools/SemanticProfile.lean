import Eggshell.Install

open Lean Eggshell

/-- Complete configured search outside the hook deadline, with the same
publication, question, workspace and receipt in every diagnostic variant.
No memo or source publication is written. This is not a native-hook sample. -/
def main (arguments : List String) : IO UInt32 := do
  let [database, question, receipt] := arguments |
    throw (IO.userError "expected database, question and fixed receipt")
  unless Receipt.validId receipt do throw (IO.userError "invalid diagnostic receipt")
  let binary := (← IO.appPath).withFileName "eggshell"
  let started ← IO.monoMsNow
  let selection : Config.Selection := {
    label := "semantic-delivery-profile", read := [⟨"source", .mk database⟩], write := none
    semanticMatcher := some [binary.toString, "search-provider"], handoffChars := 120000
    handoffBytes := some Config.nativeHandoffBytes }
  let context : Plugin.SourceContext := {
    workspace := (← IO.currentDir), deadline := started + 890000, question, receipt := some receipt }
  let result ← Plugin.automaticHandoff selection question [] false
    (sourceContext := some context) (publishMemo := false)
  IO.println (Json.mkObj [("elapsedMs", toJson ((← IO.monoMsNow) - started)),
    ("receipt", toJson receipt), ("handoff", toJson result),
    ("newNativeHooks", toJson (0 : Nat)), ("generationModelCalls", toJson (0 : Nat)),
    ("productionAdoption", toJson false)]).compress
  pure 0
