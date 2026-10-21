import Eggshell.Handoff

open Eggshell Eggshell.Plugin

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def scopeCheck (numbered gap : Bool) : IO Unit := do
  let label₁ := if numbered then "  40\t    case A:\n" else "    case A:\n"
  let label₂ := if numbered then "  41\t    case B:\n" else "    case B:\n"
  let result := if numbered then
      (if gap then "  90\t      chosen();\n" else "  42\t      chosen();\n")
    else "      chosen();\n"
  let source := label₁ ++ label₂ ++ result
  let start := (label₁ ++ label₂).length
  let heads := contextStructureHeads source none true
  require ((contextStructureHeads source none).all (·.2.isNone))
    "scope supplementation changed original cue planning"
  require (heads.contains (0, some 0)) "first indented label was dropped"
  require (heads.contains (label₁.length, some label₁.length)) "second indented label was dropped"
  if bounds : start < source.length ∧ source.length - start ≤ 2048 then
    let cue : EvidenceRange source := ⟨start, source.length, bounds.1, Nat.le_refl _, bounds.2⟩
    let context := prerequisiteContextRange (contextRecordSpans source none) heads cue
    require (context.start == if gap then start else 0)
      "scope labels were lost or crossed a numbered read gap"
    require (context.stop == source.length) "original result was clipped"
  else throw (IO.userError "invalid small test fixture")

def main : IO Unit := do
  scopeCheck false false
  scopeCheck true false
  scopeCheck true true
  let source := "    label:\n        value\n"
  require ((contextStructureHeads source none true).contains (0, some 0))
    "generic indented record heading was dropped"
  let plain := "one unstructured line"
  require ((contextStructureHeads plain none).isEmpty) "unstructured text invented a heading"
  let earlier := "    case old:\n      prior();\n}\n\n"
  let function := "int next() {\n"
  let result := "  chosen();\n"
  let source := earlier ++ function ++ result
  let start := (earlier ++ function).length
  if bounds : start < source.length ∧ source.length - start ≤ 2048 then
    let cue : EvidenceRange source := ⟨start, source.length, bounds.1, Nat.le_refl _, bounds.2⟩
    let context := prerequisiteContextRange (contextRecordSpans source none)
      (contextStructureHeads source none true) cue
    require (earlier.length ≤ context.start) "a previous branch contaminated the following function"
  else throw (IO.userError "invalid outdent fixture")
  IO.println "scope-context: 6 checks passed"
