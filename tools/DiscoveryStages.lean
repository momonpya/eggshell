import Eggshell.Install

open Lean Eggshell

private structure Request where
  database : String
  provider : String
  workspace : String
  question : String
  receipt : String
  delivered : List String
  lexical : Bool
  deriving FromJson

/-- Complete one frozen first/history request outside the native deadline.
The same request and provider executable are shared by both profiling legs.
No graph memo, publication, native offer or ACK is written by this helper. -/
def main (arguments : List String) : IO UInt32 := do
  let [path] := arguments | throw (IO.userError "expected one fixed request file")
  let request ← IO.ofExcept (Json.parse (← IO.FS.readFile path) >>= fromJson? (α := Request))
  unless Receipt.validId request.receipt do throw (IO.userError "invalid fixed receipt")
  let started ← IO.monoMsNow
  let selection : Config.Selection := {
    label := "discovery-stages", read := [⟨"source", .mk request.database⟩], write := none
    semanticMatcher := if request.lexical then none else some [request.provider, "search-provider"]
    handoffChars := 120000, handoffBytes := some Config.nativeHandoffBytes }
  let context : Plugin.SourceContext := {
    workspace := .mk request.workspace, deadline := started + 890000
    question := request.question, receipt := some request.receipt }
  let result ← Plugin.automaticHandoff selection request.question request.delivered false
    (sourceContext := some context) (publishMemo := false)
  IO.println (Json.mkObj [("elapsedMs", toJson ((← IO.monoMsNow) - started)),
    ("handoff", toJson result), ("newNativeHooks", toJson (0 : Nat)),
    ("generationModelCalls", toJson (0 : Nat)), ("productionAdoption", toJson false)]).compress
  pure 0
