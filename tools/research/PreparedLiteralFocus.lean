module
public import tools.QueryLiterals
@[expose] public section
namespace Eggshell.Research.PreparedLiteralFocus

/-- Publication data: identifier components of each immutable original window.
No question, score, receipt, deadline or authority is part of these facts. -/
structure Ready (documents : List String) where
  words : List (List (List String))
  exact : words = documents.map QueryLiterals.identifiers

def prepare (documents : List String) : Ready documents :=
  ⟨documents.map QueryLiterals.identifiers,rfl⟩

def Ready.focus {documents : List String} (ready : Ready documents)
    (question : String) (ranked : List Nat) : QueryLiterals.Focus :=
  let literals := QueryLiterals.query question
  let channels := literals.map fun literal =>
    let matching := (ready.words.zipIdx.filter fun (names,_) => names.any fun identifier =>
      literal.length < identifier.length && QueryLiterals.suffix literal identifier).map Prod.snd
    (ranked.filter matching.contains ++ matching.filter (fun index => !ranked.contains index)).toArray
  let hints := (List.range ready.words.length).flatMap fun rank => channels.filterMap (·[rank]?)
  let selected := SearchRank.select ready.words.length ranked.length [] (hints ++ ranked)
  {windows := selected,anchors := selected.filter hints.contains}

theorem Ready.focus_exact {documents : List String} (ready : Ready documents)
    (question : String) (ranked : List Nat) :
    ready.focus question ranked = QueryLiterals.focus question documents ranked := by
  simp only [Ready.focus,ready.exact,List.length_map,QueryLiterals.focus]
  by_cases empty : (QueryLiterals.query question).isEmpty = true
  · have queryNil : QueryLiterals.query question = [] := List.nil_of_isEmpty empty
    simp [queryNil]
  · simp [empty]

#print axioms Ready.focus_exact
end Eggshell.Research.PreparedLiteralFocus
