module

public import Eggshell.SearchUnicode
public import Eggshell.Frequency
public import Lean.Data.Json.FromToJson
public import tools.RetrievalCategories

@[expose] public section

namespace Eggshell.RetrievalResearch

@[extern "log1p"] opaque log1p (x : Float) : Float

def asciiTerm (c : Char) : Bool :=
  ('a' ≤ c && c ≤ 'z') || ('0' ≤ c && c ≤ '9') || "_./:-".contains c

def anchor (term : String) : Bool :=
  term.toList.any fun c => "_/:.".contains c || SearchUnicode.isDigit c

/-- Every overlapping pair, rather than disjoint two-character blocks. -/
def pairs : List Char → List String
  | left :: right :: rest => String.ofList [left, right] :: pairs (right :: rest)
  | _ => []

theorem pairs_tail (head : Char) (rest : List Char) (pair : String)
    (present : pair ∈ pairs rest) : pair ∈ pairs (head :: rest) := by
  cases rest with
  | nil => simp [pairs] at present
  | cons next tail => exact List.mem_cons_of_mem _ present

/-- Any adjacent source pair is retained, including pairs inside unknown words.
This concerns a single normalized script run; no cross-boundary or equality
claim is made about arbitrary original strings. -/
theorem adjacent_pair_present (before after : List Char) (left right : Char) :
    String.ofList [left, right] ∈ pairs (before ++ left :: right :: after) := by
  induction before with
  | nil => exact List.mem_cons_self
  | cons head rest ih => exact pairs_tail head _ _ ih

def script (c : Char) : Bool :=
  let n := c.toNat
  Unicode.letterNumber c && (
    (0x3040 ≤ n && n ≤ 0x30ff) || (0x31f0 ≤ n && n ≤ 0x31ff) ||
    (0x3400 ≤ n && n ≤ 0x9fff) || (0xf900 ≤ n && n ≤ 0xfaff) ||
    (0x20000 ≤ n && n ≤ 0x323af) || (0x1100 ≤ n && n ≤ 0x11ff) ||
    (0x3130 ≤ n && n ≤ 0x318f) || (0xa960 ≤ n && n ≤ 0xa97f) ||
    (0xac00 ≤ n && n ≤ 0xd7ff) || (0xff66 ≤ n && n ≤ 0xff9f))

structure Terms where
  primary : List String := []
  auxiliary : List String := []
  deriving Repr, Lean.ToJson

structure StableTerms where
  entries : Array String := #[]
  seen : Std.HashSet String := {}

def StableTerms.add (state : StableTerms) (term : String) : StableTerms :=
  if state.seen.contains term then state
  else {entries := state.entries.push term, seen := state.seen.insert term}

/-- Pure retrieval experiment. Words/paths retain their ordinary boundaries;
Kana/Han/Hangul runs supply overlapping pairs with single-scalar auxiliaries.
Unicode letters, numbers and combining marks are retained. Width folding is
limited to ASCII/Kana. Identity matching never calls this function; accents
are preserved instead of being unconditionally deleted.
-/
def terms (text : String) : Terms := Id.run do
  let mut primary : StableTerms := {}
  let mut auxiliary : StableTerms := {}
  let mut word : Array Char := #[]
  let mut previous : Option Char := none
  for wide in Unicode.widthFold text do
    for c in SearchUnicode.fold wide do
      let attached := (!word.isEmpty || previous.isSome) && Unicode.mark c
      if Unicode.letterNumber c || asciiTerm c || attached then
        if script c || (attached && previous.isSome) then
          if !word.isEmpty then
            primary := primary.add (String.ofList word.toList)
            word := #[]
          if let some before := previous then
            for pair in pairs [before, c] do primary := primary.add pair
          auxiliary := auxiliary.add (String.singleton c)
          previous := some c
        else
          previous := none
          word := word.push c
      else
        if !word.isEmpty then
          primary := primary.add (String.ofList word.toList)
          word := #[]
        previous := none
  if !word.isEmpty then primary := primary.add (String.ofList word.toList)
  return {primary := primary.entries.toList, auxiliary := auxiliary.entries.toList}

/-- Lane tags contain no punctuation/digits, so anchor detection still sees
only the original term. Different lanes cannot collide. -/
def tokens (text : String) : List String :=
  let parsed := terms text
  parsed.primary.map ("P" ++ ·) ++ parsed.auxiliary.map ("A" ++ ·)

def rankRows (query : String) (rows : List α) (contains : α → String → Bool)
    (frequency : String → Nat) (anchors : Bool) (population : Nat := rows.length) : List Nat :=
  let wanted := (tokens query).filter fun term => !anchors || anchor term
  let scored := rows.zipIdx.filterMap fun (row, index) =>
    let scores := wanted.foldl (fun (scores : Float × Float) term =>
      if contains row term then
        let value := log1p (population.toFloat / (frequency term).toFloat)
        if term.startsWith "P" then (scores.1 + value, scores.2)
        else (scores.1, scores.2 + value)
      else scores) (0.0, 0.0)
    if scores.1 > 0 || scores.2 > 0 then some (scores.1, scores.2, index) else none
  ((scored.mergeSort fun a b => a.1 > b.1 ||
    (a.1 == b.1 && (a.2.1 > b.2.1 || (a.2.1 == b.2.1 && a.2.2 ≤ b.2.2)))).map (·.2.2))

/-- Primary matches dominate; single-character evidence only breaks a tie.
For a single-character question the primary score is zero for every row.
There is no language dictionary, stopword list or hand-tuned blending weight.
-/
def rank (query : Terms) (documents : List Terms) : List Nat := Id.run do
  let primaryCounts := Frequency.full (documents.map (·.primary))
  let auxiliaryCounts := Frequency.full (documents.map (·.auxiliary))
  let score := fun (wanted : List String) (read : Terms → List String)
      (counts : Std.HashMap String Nat) row =>
    wanted.foldl (fun total term =>
      if (read row).contains term then
        let frequency := counts.getD term 0
        total + log1p (documents.length.toFloat / frequency.toFloat)
      else total) (0 : Float)
  let rows := documents.zipIdx.filterMap fun (doc, index) =>
    let primary := score query.primary (·.primary) primaryCounts doc
    let auxiliary := score query.auxiliary (·.auxiliary) auxiliaryCounts doc
    if primary > 0 || auxiliary > 0 then some (primary, auxiliary, index) else none
  return ((rows.mergeSort fun a b =>
    a.1 > b.1 || (a.1 == b.1 && (a.2.1 > b.2.1 ||
      (a.2.1 == b.2.1 && a.2.2 ≤ b.2.2)))).map (·.2.2))

end Eggshell.RetrievalResearch
