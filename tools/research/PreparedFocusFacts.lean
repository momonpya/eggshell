module
public import tools.research.SourceProjectionDictionary
public import Eggshell.SearchRank
@[expose] public section
namespace Eggshell.Synapses.PreparedFocusFacts
open Lean _root_.Eggshell.Research.SourceProjectionWire

def implementation : String := Blake3.hex (Blake3.digest "eggshell.prepared-focus".toUTF8 [
  (include_str "PreparedFocusFacts.lean").toUTF8,
  (include_str "../../Eggshell/SearchRank.lean").toUTF8,
  (include_str "../../Eggshell/SearchUnicode.lean").toUTF8,
  (include_str "../../Eggshell/Frequency.lean").toUTF8,
  (include_str "../RetrievalGrams.lean").toUTF8,
  (include_str "../RetrievalCategories.lean").toUTF8])

/-- Original search windows keep their positions. Only the Work prefix is
removed from their lexical evidence, exactly as in the existing focus. -/
def trim (workChars : Nat) (originals : List String) : List String :=
  originals.zipIdx.map fun (window,index) => (window.drop (workChars+1-index*384)).copy

def evidence (work outcome : String) : List String :=
  trim work.length (SearchRank.windows (work++"\n"++outcome))

structure Stored where
  owner : String
  work : String
  originalWindows : List String
  dictionary : Array String
  windows : List (List Nat)
  deriving ToJson,FromJson

def encode (owner work : String) (originals : List String) (rows : List (List String)) : Stored :=
  let terms := directory rows.flatten
  ⟨owner,work,originals,terms.values.toArray,rows.map (·.map terms.index)⟩

def Stored.decode (stored : Stored) : Option (List (List String)) :=
  stored.windows.mapM fun row => row.mapM (stored.dictionary[·]?)

theorem encoded_rows_exact (owner work : String) (originals : List String)
    (rows : List (List String)) : (encode owner work originals rows).decode = some rows := by
  let terms := directory rows.flatten
  have one (row : List String) (present : ∀ word ∈ row, word ∈ terms.values) :
      (row.map terms.index).mapM (terms.values.toArray[·]?) = some row := by
    induction row with
    | nil => rfl
    | cons word rest ih =>
      simp only [List.map_cons,List.mapM_cons]
      rw [terms.resolves word (present word (by simp))]
      rw [ih (by intro unit member; exact present unit (by simp [member]))]
      rfl
  have allRows (remaining : List (List String))
      (present : ∀ row ∈ remaining, ∀ word ∈ row, word ∈ terms.values) :
      (remaining.map (·.map terms.index)).mapM (fun row => row.mapM (terms.values.toArray[·]?)) = some remaining := by
    induction remaining with
    | nil => rfl
    | cons row rest ih =>
      simp only [List.map_cons,List.mapM_cons]
      rw [one row (present row (by simp))]
      rw [ih (by intro words member; exact present words (by simp [member]))]
      rfl
  exact allRows rows (by
    intro row member word inside
    apply (directory_member rows.flatten word).mpr
    exact List.mem_flatten.mpr ⟨row,member,inside⟩)

def compile (owner workKey work outcome : String) : Stored :=
  let originals := SearchRank.windows (work++"\n"++outcome)
  encode owner workKey (originals.map Persistence.Store.windowKey)
    ((trim work.length originals).map SearchRank.terms)

theorem compiled_rows_exact (owner workKey work outcome : String) :
    (compile owner workKey work outcome).decode = some ((evidence work outcome).map SearchRank.terms) :=
  encoded_rows_exact ..

structure Ready where
  stored : Stored
  rows : List (List String)
  decoded : stored.decode = some rows

/-- Validation/decoding belongs to the shared preparation owner, not to a
question's ranking loop. No original text is retained in this value. -/
def check (owner : String) (stored : Stored) : Except String Ready := do
  unless stored.owner == owner && stored.originalWindows.length == stored.windows.length &&
      !stored.originalWindows.isEmpty &&
      stored.originalWindows.all (fun key => key.length == 64) do
    throw "prepared focus facts changed owner or original window domain"
  match decoded : stored.decode with
  | none => throw "prepared focus term ordinal is outside its immutable dictionary"
  | some rows => return ⟨stored,rows,decoded⟩

def Ready.matches (ready : Ready) (owner work : String) (windows : List String) : Bool :=
  ready.stored.owner == owner && ready.stored.work == work && ready.stored.originalWindows == windows

def Ready.rank (ready : Ready) (question : String) (semantic : List Nat) : List Nat :=
  let lexical := SearchRank.rankDocuments question ready.rows
    (fun term => (ready.rows.filter (·.contains term)).length) false
  SearchRank.select ready.rows.length semantic.length [] (SearchRank.fused [semantic,lexical])

theorem Ready.rank_is_original (ready : Ready) (question : String) (semantic : List Nat)
    (index : Nat) (selected : index ∈ ready.rank question semantic) : index < ready.rows.length :=
  SearchRank.selected_is_existing _ _ _ _ _ selected

theorem Ready.rank_bounded (ready : Ready) (question : String) (semantic : List Nat) :
    (ready.rank question semantic).length ≤ semantic.length := SearchRank.selected_within_budget ..

theorem Ready.rank_distinct (ready : Ready) (question : String) (semantic : List Nat) :
    (ready.rank question semantic).Nodup := SearchRank.selected_no_duplicates ..

def prepared (owner workKey work outcome : String) : Ready :=
  ⟨compile owner workKey work outcome,(evidence work outcome).map SearchRank.terms,compiled_rows_exact ..⟩

theorem prepared_rank_exact (owner workKey work outcome question : String) (semantic : List Nat) :
    (prepared owner workKey work outcome).rank question semantic =
      SearchRank.select (evidence work outcome).length semantic.length []
        (SearchRank.fused [semantic,SearchRank.lexical question (evidence work outcome)]) := by
  rw [SearchRank.lexical_exact]
  simp only [prepared,Ready.rank,SearchRank.referenceLexical,List.length_map]

theorem prepared_positions (owner workKey work outcome : String) :
    (prepared owner workKey work outcome).rows.length =
      (SearchRank.windows (work++"\n"++outcome)).length := by
  simp [prepared,evidence,trim]

theorem mismatched_work_refused (ready : Ready) (owner work : String) (windows : List String)
    (different : ready.stored.work ≠ work) : ready.matches owner work windows = false := by
  simp [Ready.matches,different]
end Eggshell.Synapses.PreparedFocusFacts
