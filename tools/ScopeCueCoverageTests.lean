import Eggshell.Handoff

open Eggshell Eggshell.Plugin

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def checkedRange (source : String) (start stop : Nat) : IO (EvidenceRange source) := do
  if bounds : start < stop ∧ stop ≤ source.length ∧ stop - start ≤ 2048 then
    pure ⟨start, stop, bounds.1, bounds.2.1, bounds.2.2⟩
  else throw (IO.userError "invalid bounded fixture range")

def main : IO Unit := do
  let line := "  " ++ String.ofList (List.replicate 97 'a') ++ "\n"
  let source := "".intercalate (List.replicate 50 line)
  let first ← checkedRange source 200 700
  let second ← checkedRange source 2200 2700
  let records := contextRecordSpans source none
  let views := prepareCueViews records [] none [first, second]
  let owner := OutcomeEdge.make (.text "work") (.text source) [] (by simp) (by simp)
  let selected := views.foldl (fun state view => offerContextView state owner none view)
    (ContextSelection.empty : ContextSelection source 1100)
  for position in [250, 2250] do
    require (selected.views.any fun view => decide (view.range.covers position))
      "padding displaced a second independent original cue"
  let labels := "    case A:\n    case B:\n"
  let observation := "      chosen();\n"
  let labeledSource := labels ++ observation ++ source
  let cue ← checkedRange labeledSource labels.length (labels.length + observation.length)
  let records := contextRecordSpans labeledSource none
  let heads := contextStructureHeads labeledSource none
  let views := prepareCueViews records heads none [cue]
  require (views.head?.any fun view => view.range.start == 0 &&
    view.range.stop == labels.length + observation.length)
    "the minimum cue dropped its indented original conditions"
  require ((prepareCueViews records heads none []).isEmpty) "empty nomination invented evidence"
  IO.println "scope-cue-coverage: 3 cases passed"
