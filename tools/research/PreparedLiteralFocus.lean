module
public import tools.QueryLiterals
public import Lean.Data.Json.FromToJson
@[expose] public section
namespace Eggshell.Research.PreparedLiteralFocus

/-- Publication data: identifier components of each immutable original window.
No question, score, receipt, deadline or authority is part of these facts. -/
structure Ready (documents : List String) where
  words : List (List (List String))
  exact : words = documents.map QueryLiterals.identifiers

def prepare (documents : List String) : Ready documents :=
  ⟨documents.map QueryLiterals.identifiers,rfl⟩

def focusWords (words : List (List (List String)))
    (question : String) (ranked : List Nat) : QueryLiterals.Focus :=
  let literals := QueryLiterals.query question
  let channels := literals.map fun literal =>
    let matching := (words.zipIdx.filter fun (names,_) => names.any fun identifier =>
      literal.length < identifier.length && QueryLiterals.suffix literal identifier).map Prod.snd
    (ranked.filter matching.contains ++ matching.filter (fun index => !ranked.contains index)).toArray
  let hints := (List.range words.length).flatMap fun rank => channels.filterMap (·[rank]?)
  let selected := SearchRank.select words.length ranked.length [] (hints ++ ranked)
  {windows := selected,anchors := selected.filter hints.contains}

def Ready.focus {documents : List String} (ready : Ready documents)
    (question : String) (ranked : List Nat) : QueryLiterals.Focus := focusWords ready.words question ranked

theorem Ready.focus_exact {documents : List String} (ready : Ready documents)
    (question : String) (ranked : List Nat) :
    ready.focus question ranked = QueryLiterals.focus question documents ranked := by
  simp only [Ready.focus,focusWords,ready.exact,List.length_map,QueryLiterals.focus]
  by_cases empty : (QueryLiterals.query question).isEmpty = true
  · have queryNil : QueryLiterals.query question = [] := List.nil_of_isEmpty empty
    simp [queryNil]
  · simp [empty]

/-- The producer binds these facts to one immutable owner/work/window domain.
They cannot represent an observation, an equality, or completion authority. -/
structure Data where
  owner : String
  work : String
  windows : List String
  words : List (List (List String))
  deriving BEq,Lean.ToJson,Lean.FromJson

def Data.matches (data : Data) (owner work : String) (windows : List String) : Bool :=
  data.owner == owner && data.work == work && data.windows == windows && data.words.length == windows.length

def Data.focus (data : Data) (question : String) (ranked : List Nat) : QueryLiterals.Focus :=
  focusWords data.words question ranked

theorem Data.focus_exact (data : Data) (documents : List String)
    (question : String) (ranked : List Nat) (exact : data.words = documents.map QueryLiterals.identifiers) :
    data.focus question ranked = QueryLiterals.focus question documents ranked := by
  exact (Ready.focus_exact (⟨data.words,exact⟩ : Ready documents) question ranked)

theorem Data.foreign_work_rejected (data : Data) (owner work : String) (windows : List String)
    (different : data.work ≠ work) : data.matches owner work windows = false := by
  simp [Data.matches,different]

#print axioms Ready.focus_exact
#print axioms Data.focus_exact
#print axioms Data.foreign_work_rejected
end Eggshell.Research.PreparedLiteralFocus
