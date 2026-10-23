import tools.research.StudyAccounting

open Lean Eggshell.Research.StudyAccounting

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main : IO Unit := do
  let counters := Json.mkObj [("totalTokens",toJson (110 : Nat)),("inputTokens",toJson (100 : Nat)),
    ("outputTokens",toJson (10 : Nat)),("cachedInputTokens",toJson (80 : Nat)),
    ("reasoningOutputTokens",toJson (5 : Nat))]
  let measured ← IO.ofExcept (usage counters)
  let finished : State := {
    lastUsage := some measured
    terminal := some "completed"
    answer := some "synthetic"
    hookCount := 1 }
  check (acquisitionAccepted .seed true finished) "empty seed with an actual prompt hook rejected"
  check (!(acquisitionAccepted .seed false finished)) "seed without a prompt hook accepted"
  let injected : State := {finished with packets := #[⟨"userPromptSubmit","untrusted",1,1,"completed"⟩]}
  check (!(acquisitionAccepted .seed true injected)) "old memory injected into empty seed accepted"
  let fresh := {finished with hookCount := 0}
  check (acquisitionAccepted .fresh false fresh) "fresh with no hooks rejected"
  check (!(acquisitionAccepted .fresh false finished)) "fresh with hooks accepted"
  check (!(acquisitionAccepted .fresh false {fresh with packets := injected.packets})) "fresh with context accepted"
  check (!(acquisitionAccepted .seed true {finished with terminal := some "failed"})) "failed seed accepted"
  check (!(acquisitionAccepted .seed true {finished with lastUsage := none})) "unknown seed cost accepted"
  let scope : Scope := ⟨"thread","turn","untrusted"⟩
  check (((report scope injected).getObjValAs? Bool "protocolPassed").toOption == some true)
    "normal memory-trial body admission changed"
  IO.println (Json.mkObj [("checks",toJson (9 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("syntheticUsage",toJson (110 : Nat)),("productionAdoption",toJson false)]).compress
