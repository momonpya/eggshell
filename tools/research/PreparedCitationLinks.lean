module
public import Eggshell.CitationCoordinates
public import Std.Data.HashMap.Lemmas
@[expose] public section
namespace Eggshell.Plugin.PreparedCitationLinks
open Lean
abbrev Links := List (String × String)

/-- Markdown structure, independent of the later target file or rank. -/
def prepare (text : String) : Links :=
  let parts := (text.splitOn "](")
  (parts.drop 1).zipIdx.filterMap fun (tail,index) => do
    let before ← parts[index]?
    let label ← (before.splitOn "[").getLast?
    let target ← (tail.splitOn ")").head?
    pure (label,target)

def intervals (links : Links) (relative : String) : List (Nat × Nat) :=
  if !SourceEvidence.safeRelative relative then [] else
    links.filterMap fun (label,target) => do
      let destination ← citationTarget? target relative
      let explicitRange := [relative ++ ":",relative ++ "#L"].any fun marker =>
        ((target.splitOn marker).drop 1).any fun bounds =>
          !(bounds.toList.dropWhile Char.isDigit).isEmpty
      let basename := (relative.splitOn "/").getLast?.getD relative
      let displayed := (label.splitOn (basename ++ ":")).drop 1
      match displayed with
      | [] => some destination
      | [bounds] => do
          let shown ← citationBounds? bounds
          if shown.1 == destination.1 && (!explicitRange || shown.2 == destination.2) then some shown else none
      | _ => none

theorem prepared_intervals_exact (text relative : String) :
    intervals (prepare text) relative = citedLineIntervals text relative := by
  unfold intervals citedLineIntervals
  split
  · rfl
  · simp only [prepare,List.filterMap_filterMap]
    congr 1
    funext entry
    rcases entry with ⟨tail,index⟩
    cases before : (text.splitOn "](")[index]? with
    | none => rfl
    | some prior =>
      simp only [bind,Option.bind,Option.pure_def]
      cases label : (prior.splitOn "[").getLast? <;>
        cases target : (tail.splitOn ")").head? <;> rfl

abbrev Parser := Std.HashMap Nat (String × Links)
def Parser.valid (parser : Parser) : Prop :=
  ∀ (id : Nat) (text : String) (links : Links), parser[id]? = some (text,links) → links = prepare text

def Parser.parse (parser : Parser) (id : Nat) (text relative : String) : List (Nat × Nat) :=
  match parser[id]? with
  | none => citedLineIntervals text relative
  | some (expected,links) => if expected == text then intervals links relative else citedLineIntervals text relative

theorem Parser.parse_exact (parser : Parser) (valid : Parser.valid parser) (id : Nat) (text relative : String) :
    parser.parse id text relative = citedLineIntervals text relative := by
  unfold parse
  cases found : parser[id]? with
  | none => rfl
  | some entry =>
    rcases entry with ⟨expected,links⟩
    by_cases same : expected = text
    · subst expected
      simp only [beq_self_eq_true,if_true]
      rw [valid id text links found,prepared_intervals_exact]
    · simp [same]

theorem Parser.empty_valid : Parser.valid ({} : Parser) := by simp [valid]

theorem Parser.insert_valid (parser : Parser) (valid : Parser.valid parser) (id : Nat) (text : String) :
    Parser.valid (parser.insert id (text,prepare text)) := by
  intro probe expected links found
  by_cases same : id = probe
  · subst probe
    have values : (text,prepare text) = (expected,links) := by simpa using found
    cases values
    rfl
  · apply valid probe expected links
    simpa [Std.HashMap.getElem?_insert,same] using found

def Parser.prepare (texts : List (Nat × String)) : Parser :=
  texts.foldl (fun parser (id,text) => parser.insert id (text,PreparedCitationLinks.prepare text)) {}

theorem Parser.prepared_valid (texts : List (Nat × String)) : Parser.valid (Parser.prepare texts) := by
  have step : ∀ (rows : List (Nat × String)) (parser : Parser), Parser.valid parser →
      Parser.valid (rows.foldl (fun parser (id,text) => parser.insert id (text,PreparedCitationLinks.prepare text)) parser) := by
    intro rows
    induction rows with
    | nil => intro parser valid; exact valid
    | cons row rows ih =>
      intro parser valid
      exact ih _ (Parser.insert_valid parser valid row.1 row.2)
  exact step texts {} Parser.empty_valid

#print axioms prepared_intervals_exact
#print axioms Parser.parse_exact
#print axioms Parser.prepared_valid
end Eggshell.Plugin.PreparedCitationLinks
