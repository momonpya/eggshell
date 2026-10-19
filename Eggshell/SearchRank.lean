module

public import Eggshell.SearchUnicode
public import Eggshell.Frequency
public import Lean.Data.Json

@[expose] public section

namespace Eggshell.SearchRank

@[extern "log1p"] opaque log1p (x : Float) : Float

def asciiTerm (c : Char) : Bool :=
  ('a' ≤ c && c ≤ 'z') || ('0' ≤ c && c ≤ '9') || "_./:-".contains c

def singleTerm (c : Char) : Bool :=
  (0x3040 ≤ c.toNat && c.toNat ≤ 0x30ff) || (0x3400 ≤ c.toNat && c.toNat ≤ 0x9fff)

def rawTerms (text : String) : List String := Id.run do
  let folded := text.toList.flatMap (SearchUnicode.fold · |>.toList)
  let mut result := []
  let mut current := ""
  for c in folded do
    if asciiTerm c then current := current.push c
    else
      if !current.isEmpty then result := result ++ [current]; current := ""
      if singleTerm c then result := result ++ [String.singleton c]
  if !current.isEmpty then result := result ++ [current]
  return result

def terms (text : String) : List String := (rawTerms text).eraseDups

theorem deduplicated_nodup [BEq α] [LawfulBEq α] (xs : List α) : xs.eraseDups.Nodup := by
  match xs with
  | [] => simp
  | x :: tail =>
    rw [List.eraseDups_cons, List.nodup_cons]
    constructor
    · simp
    · exact deduplicated_nodup (tail.filter fun y => !y == x)
termination_by xs.length
decreasing_by
  have := List.length_filter_le (fun y => !y == x) tail
  simp only [List.length_cons]
  omega

theorem terms_nodup (text : String) : (terms text).Nodup :=
  deduplicated_nodup (rawTerms text)

def anchor (term : String) : Bool :=
  term.toList.any fun c => "_/:.".contains c || SearchUnicode.isDigit c

def scoreOrder (a b : Float × Nat) : Bool :=
  a.1 > b.1 || (a.1 == b.1 && a.2 ≤ b.2)

def rankRows (query : String) (rows : List α) (contains : α → String → Bool)
    (frequency : String → Nat) (anchors : Bool) (population : Nat := rows.length) : List Nat :=
  let wanted := (terms query).filter fun term => !anchors || anchor term
  let scores := rows.zipIdx.filterMap fun (row, index) =>
    let score := wanted.foldl (fun total term =>
      if contains row term then
        let count := frequency term
        total + log1p (population.toFloat / count.toFloat)
      else total) (0 : Float)
    if score > 0 then some (score, index) else none
  (scores.mergeSort scoreOrder).map (·.2)

def rankDocuments (query : String) (documents : List (List String))
    (frequency : String → Nat) (anchors : Bool) : List Nat :=
  rankRows query documents List.contains frequency anchors

/-- The indexed reader supplies complete query-term postings and global
counts. Row enumeration preserves the provider's existing stable tie-break;
source text and every unrelated document term remain unread. -/
theorem rankRows_map (query : String) (rows : List α) (project : α → β)
    (contains : β → String → Bool) (frequency : String → Nat) (anchors : Bool) :
    rankRows query (rows.map project) contains frequency anchors =
      rankRows query rows (fun row term => contains (project row) term) frequency anchors := by
  simp only [rankRows, List.length_map, List.zipIdx_map, List.filterMap_map]
  rfl

/-- The oracle preserves query-term order, floating-point operations and the
stable index tie-break. No mathematical rearrangement of Float sums is used. -/
def referenceLexical (query : String) (candidates : List String)
    (anchors := false) : List Nat :=
  let documents := candidates.map terms
  rankDocuments query documents (fun term => (documents.filter (·.contains term)).length) anchors

theorem document_count_exact (candidates : List String) (term : String) :
    Frequency.count (candidates.map terms) term =
      ((candidates.map terms).filter (·.contains term)).length := by
  induction candidates with
  | nil => rfl
  | cons text rest ih =>
      simp only [List.map_cons, Frequency.count_cons, (terms_nodup text).count, ih,
        List.filter_cons, List.contains_eq_mem]
      split <;> simp_all [Nat.add_comm]

theorem document_frequency_append (left right : List (List String)) (term : String) :
    ((left ++ right).filter (·.contains term)).length =
      (left.filter (·.contains term)).length + (right.filter (·.contains term)).length := by
  simp

/-- Reusable document compilation and a certified signed frequency index.
Its candidate sequence includes deletions, corrections and order changes. -/
structure Corpus (candidates : List String) where
  documents : List (List String)
  exact : documents = candidates.map terms
  frequencies : Frequency.Index documents

def Corpus.build (candidates : List String) : Corpus candidates :=
  let documents := candidates.map terms
  ⟨documents, rfl, Frequency.Index.empty.replace documents [] documents (by intro term; simp)⟩

/-- Unchanged prefix/suffix terms are reused. Only the changed region is
parsed, subtracted and added; zero counts disappear from the signed map. -/
def Corpus.revise {before : List String} (previous : Corpus before)
    (after : List String) : Corpus after :=
  let region := Frequency.affectedRegion before after
  let left := previous.documents.take region.left.length
  let removed := (previous.documents.drop region.left.length).take region.removed.length
  let right := previous.documents.drop (region.left.length + region.removed.length)
  have leftExact : left = region.left.map terms := by
    simp [left, previous.exact, region.old, List.map_append]
  have removedExact : removed = region.removed.map terms := by
    simp [removed, previous.exact, region.old, List.map_append, List.append_assoc]
  have rightExact : right = region.right.map terms := by
    simp [right, previous.exact, region.old, List.map_append, List.append_assoc,
      ← List.drop_drop]
  let added := region.added.map terms
  let documents := left ++ added ++ right
  have exact : documents = after.map terms := by
    simp [documents, leftExact, rightExact, added, region.current, List.map_append]
  let frequencies := previous.frequencies.replace documents removed added (by
    intro term
    rw [previous.exact, exact, removedExact]
    simp only [region.old, region.current, List.map_append, Frequency.count_append]
    dsimp only [added]
    omega)
  ⟨documents, exact, frequencies⟩

def Corpus.rank {candidates : List String} (corpus : Corpus candidates) (query : String)
    (anchors := false) : List Nat :=
  rankDocuments query corpus.documents (fun term => (corpus.frequencies.counts.getD term 0).toNat) anchors

theorem Corpus.rank_exact {candidates : List String} (corpus : Corpus candidates)
    (query : String) (anchors : Bool) : corpus.rank query anchors = referenceLexical query candidates anchors := by
  have frequencies : (fun term => (corpus.frequencies.counts.getD term 0).toNat) =
      fun term => ((candidates.map terms).filter (·.contains term)).length := by
    funext term
    rw [corpus.frequencies.exact, corpus.exact, document_count_exact]
    simp
  simp only [rank, referenceLexical, corpus.exact, frequencies]

def lexical (query : String) (candidates : List String) (anchors := false) : List Nat :=
  (Corpus.build candidates).rank query anchors

theorem lexical_exact (query : String) (candidates : List String) (anchors : Bool) :
    lexical query candidates anchors = referenceLexical query candidates anchors :=
  Corpus.rank_exact _ query anchors

def fused (rankings : List (List Nat)) : List Nat :=
  let ids := rankings.flatten.eraseDups
  let scores := ids.map fun id =>
    (rankings.foldl (fun score ranking =>
      match (ranking.zipIdx.find? (·.1 == id)) with
      | some (_, rank) => score + 1 / (61 + rank).toFloat
      | none => score) (0 : Float), id)
  (scores.mergeSort scoreOrder).map (·.2)

/-- All provider output goes through this constructor. It cannot invent an
    index, duplicate an outcome, or exceed the selected context budget. -/
def select (count limit : Nat) (anchors ranking : List Nat) : List Nat :=
  ((anchors ++ ranking).eraseDups.filter (· < count)).take limit

theorem selected_no_duplicates (n k : Nat) (a r : List Nat) : (select n k a r).Nodup := by
  exact (List.take_sublist k _).nodup (List.filter_sublist.nodup (deduplicated_nodup (a ++ r)))

theorem selected_within_budget (n k : Nat) (a r : List Nat) :
    (select n k a r).length ≤ k := by simp [select, List.length_take, Nat.min_le_left]

theorem selected_is_existing (n k : Nat) (a r : List Nat) (id : Nat)
    (member : id ∈ select n k a r) : id < n := by
  have h := List.mem_of_mem_take member
  have filtered := List.mem_filter.mp h
  simpa using filtered.2

theorem selected_was_ranked (n k : Nat) (a r : List Nat) (id : Nat)
    (member : id ∈ select n k a r) : id ∈ a ∨ id ∈ r := by
  have h := List.mem_of_mem_take member
  have filtered := (List.mem_filter.mp h).1
  simpa using filtered

theorem zero_budget_is_empty (n : Nat) (a r : List Nat) : select n 0 a r = [] := rfl

def windowsFrom : Nat → List Char → List String
  | 0, _ => []
  | count + 1, characters => String.ofList (characters.take 512) :: windowsFrom count (characters.drop 384)

theorem windowsFrom_exact (count : Nat) (characters : List Char) :
    windowsFrom count characters = (List.range count).map (fun index =>
      String.ofList ((characters.drop (index * 384)).take 512)) := by
  induction count generalizing characters with
  | zero => rfl
  | succ count ih =>
      simp only [windowsFrom, List.range_succ_eq_map, List.map_cons, Nat.zero_mul,
        List.drop_zero, List.map_map, ih]
      apply congrArg (List.cons (String.ofList (characters.take 512)))
      apply List.map_congr_left
      intro index _
      dsimp only [Function.comp_def]
      rw [List.drop_drop]
      have offset : 384 + index * 384 = index.succ * 384 := by omega
      rw [offset]

def windows (text : String) : List String :=
  let characters := text.toList
  windowsFrom ((max 1 characters.length + 383) / 384) characters

/-- Byte offsets advance with the consumed prefix, rather than rescanning
the original text. The projection is the very same window sequence. -/
def locatedWindowsFrom : Nat → Nat → List Char → List (Nat × String)
  | 0, _, _ => []
  | count + 1, offset, characters =>
      (offset, String.ofList (characters.take 512)) ::
        locatedWindowsFrom count
          (offset + (String.ofList (characters.take 384)).utf8ByteSize)
          (characters.drop 384)

theorem locatedWindowsFrom_exact (count offset : Nat) (characters : List Char) :
    (locatedWindowsFrom count offset characters).map Prod.snd = windowsFrom count characters := by
  induction count generalizing offset characters with
  | zero => rfl
  | succ count ih => simp only [locatedWindowsFrom, List.map_cons, windowsFrom, ih]

def locatedWindows (text : String) : List (Nat × String) :=
  locatedWindowsFrom ((max 1 text.toList.length + 383) / 384) 0 text.toList

theorem locatedWindows_exact (text : String) :
    (locatedWindows text).map Prod.snd = windows text :=
  locatedWindowsFrom_exact _ _ _

theorem windows_exact (text : String) :
    windows text = (List.range ((max 1 text.toList.length + 383) / 384)).map (fun index =>
      String.ofList ((text.toList.drop (index * 384)).take 512)) :=
  windowsFrom_exact _ _

end Eggshell.SearchRank
