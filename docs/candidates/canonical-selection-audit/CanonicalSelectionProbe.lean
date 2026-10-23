import Eggshell.Handoff

open Lean Eggshell Eggshell.Plugin

/-- Diagnostic only: re-run the real first-request functions without a daemon
or memo publication. Expected source ranges are never inputs to this tool. -/
def main (args : List String) : IO Unit := do
  let [database,prompt,workspace,provider,result] := args |
    throw (IO.userError "CanonicalSelectionProbe DB PROMPT WORKSPACE PROVIDER RESULT")
  let question ← IO.FS.readFile (.mk prompt)
  let selection : Config.Selection := {
    label := "work", read := [⟨"work",.mk database⟩], write := some ⟨"work",.mk database⟩
    semanticMatcher := some [provider,"search-provider"]
    handoffChars := 120000, handoffBytes := some Config.nativeHandoffBytes }
  let context : SourceContext := {
    workspace := .mk workspace, deadline := (← IO.monoMsNow)+180000
    question, targets := SourceEvidence.workTargets? (.mk workspace) question }
  let raw ← automaticHandoff selection question [] false (sourceContext := some context) (publishMemo := false)
  IO.FS.writeFile (.mk result) (toJson raw).compress
