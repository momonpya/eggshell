module

public import Eggshell.SearchRank
public import tools.RetrievalCategories

@[expose] public section

namespace Eggshell.RetrievalResearch

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

def Terms.prependRun (state : Terms) (characters : List Char) (isScript : Bool) : Terms :=
  if characters.isEmpty then state else
  if isScript then {
    primary := (pairs characters).reverse ++ state.primary
    auxiliary := (characters.map String.singleton).reverse ++ state.auxiliary }
  else {state with primary := String.ofList characters :: state.primary}

/-- Pure retrieval experiment. Words/paths retain their ordinary boundaries;
Kana/Han/Hangul runs supply overlapping pairs with single-scalar auxiliaries.
Unicode letters, numbers and combining marks are retained. Width folding is
limited to ASCII/Kana. Identity matching never calls this function; accents
are preserved instead of being unconditionally deleted.
-/
def terms (text : String) : Terms := Id.run do
  let mut result : Terms := {}
  let mut run : Array Char := #[]
  let mut isScript := false
  for c in (Unicode.widthFold text).toList.flatMap (SearchUnicode.fold · |>.toList) do
    if Unicode.letterNumber c || SearchRank.asciiTerm c || (!run.isEmpty && Unicode.mark c) then
      let next := script c || (!run.isEmpty && Unicode.mark c && isScript)
      if !run.isEmpty && next != isScript then
        result := result.prependRun run.toList isScript
        run := #[]
      run := run.push c
      isScript := next
    else
      result := result.prependRun run.toList isScript
      run := #[]
  result := result.prependRun run.toList isScript
  return {primary := result.primary.reverse.eraseDups, auxiliary := result.auxiliary.reverse.eraseDups}

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
        total + SearchRank.log1p (documents.length.toFloat / frequency.toFloat)
      else total) (0 : Float)
  let rows := documents.zipIdx.filterMap fun (doc, index) =>
    let primary := score query.primary (·.primary) primaryCounts doc
    let auxiliary := score query.auxiliary (·.auxiliary) auxiliaryCounts doc
    if primary > 0 || auxiliary > 0 then some (primary, auxiliary, index) else none
  return ((rows.mergeSort fun a b =>
    a.1 > b.1 || (a.1 == b.1 && (a.2.1 > b.2.1 ||
      (a.2.1 == b.2.1 && a.2.2 ≤ b.2.2)))).map (·.2.2))

end Eggshell.RetrievalResearch
