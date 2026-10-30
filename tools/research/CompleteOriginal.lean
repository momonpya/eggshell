module
public import Eggshell.OriginalStructure
@[expose] public section

namespace Eggshell.Research.CompleteOriginal
open Lean

open Eggshell.Plugin OriginalStructure

/-- Publication stores positions only, not another copy of the output body.
The character count is an erased index, and completeness is kernel checked. -/
structure Layout (characters : Nat) where
  spans : Array Span
  complete : OriginalStructure.complete characters spans = true
  bounds : spans.all (fun span => span.first < span.limit && span.limit ≤ characters) = true

def check? (characters : Nat) (spans : Array Span) : Option (Layout characters) :=
  if complete : OriginalStructure.complete characters spans = true then
    if bounds : spans.all (fun span => span.first < span.limit && span.limit ≤ characters) = true then
      some ⟨spans,complete,bounds⟩ else none
  else none

/-- This runs when preparing the original view, never in the search fitter.
String delimiters remain as original ranges beside the decoded string data. -/
def prepare (source : String) : Except String (Layout source.length) := do
  let characters := source.length
  let spans : Array Span := if (decodedToolText? source).isSome &&
      source.startsWith "\"" && source.endsWith "\"" && characters ≥ 2 then
      #[⟨0,1,false⟩] ++
        (if 2 < characters then #[⟨1,characters-1,true⟩] else #[]) ++
        #[⟨characters-1,characters,false⟩]
    else if characters == 0 then #[] else #[⟨0,characters,false⟩]
  let some prepared := check? characters spans | throw "complete original layout is invalid"
  return prepared

theorem Layout.keeps_position (prepared : Layout characters) (position : Nat) (inside : position < characters) :
    ∃ span ∈ prepared.spans, span.first ≤ position ∧ position < span.limit :=
  OriginalStructure.complete_position characters prepared.spans position prepared.complete inside

theorem Layout.source_bound (prepared : Layout characters) (span : Span) (present : span ∈ prepared.spans) :
    span.first < span.limit ∧ span.limit ≤ characters := by
  have ready := (Array.all_eq_true'.mp prepared.bounds) span present
  simpa only [Bool.and_eq_true,decide_eq_true_eq] using ready

end Eggshell.Research.CompleteOriginal
