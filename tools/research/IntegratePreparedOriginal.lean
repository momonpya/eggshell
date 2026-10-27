import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

/-- Preserve the independent old renderer loop in the native audit, then
replace only its query-invariant preparation with published recipes. -/
def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "isolated checkout required")
  let path := System.FilePath.mk directory / "Eggshell/Handoff.lean"
  let source ← IO.FS.readFile path
  let first := "def prepareOriginalRecords ("
  let last := "/-- Prepare the immutable record/structure index once per owner."
  let [before,tail] := source.splitOn first | throw (IO.userError "ambiguous original preparation")
  let [body,after] := tail.splitOn last | throw (IO.userError "ambiguous preparation boundary")
  let audit := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/tools/research/OriginalStructureAudit.lean"
  unless !(← audit.pathExists) do throw (IO.userError "preserve original preparation reference")
  IO.FS.writeFile audit ("import Eggshell.Handoff\nopen Lean Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter\n\n" ++
    "private def referenceOriginalRecords (" ++ body)
  let replacement := "def prepareOriginalRecords (familyIndex : Nat) (family : Family) :\n" ++
    "    List UnitPlan × List (Nat × Nat) := Id.run do\n" ++
    "  let some source := Matcher.atomText? family.owner.outcome | return ([],[])\n" ++
    "  let some envelope := family.template.context | return ([],[])\n" ++
    "  let some prepared := family.original | return ([],[])\n" ++
    "  let original := IndexedCharacters.make source\n" ++
    "  let workChars := (Matcher.atomText? family.owner.work).getD \"\" |>.length\n" ++
    "  let cues := ((rankedContextRanges source (workChars+1)\n" ++
    "    (family.windows ++ family.references).eraseDups).map fun range => (range.start,range.stop)) ++\n" ++
    "    (family.synapticRanges ++ family.outputCues).map (fun (_,a,b) => (a,b))\n" ++
    "  let mut units := []\n" ++
    "  for span in prepared do\n" ++
    "    let some required := span.range? source | return ([],[])\n" ++
    "    let fragment := originalRecordFragment original required span.decoded\n" ++
    "    let ranges := [(required.start,required.stop)]\n" ++
    "    let selectedCues := cues.filterMap fun (a,b) =>\n" ++
    "      let first := max a required.start\n" ++
    "      let last := min b required.stop\n" ++
    "      if first < last then some (first,last) else none\n" ++
    "    let context := {envelope with fragments := [fragment],cues := selectedCues}\n" ++
    "    let slice := {family.template with context := some context,keys := context.keys,text := context.render}\n" ++
    "    units := {family := familyIndex,slice,ranges} :: units\n" ++
    "  return (units.reverse,cues)\n\n"
  IO.FS.writeFile path (before ++ replacement ++ last ++ after)
