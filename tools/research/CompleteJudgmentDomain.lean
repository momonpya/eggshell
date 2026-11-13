import tools.research.HistoryWorkspace
import Eggshell.ObservationContext
import Eggshell.Sha256
open Lean Eggshell HistoryAccess

/- Isolated scoring-input transport. A page is an immutable original slice,
not a ranked capsule, answer, Match, Union or completion certificate. -/
namespace CompleteJudgmentDomain
structure Document where
  owner : String
  work : String
  invocation : String
  source : String
  deriving FromJson, ToJson

structure Origin where
  document : Nat
  first : Nat
  stop : Nat
  deriving BEq, FromJson, ToJson

structure PagePayload where
  content : String
  first : Nat
  stop : Nat
  text : String
  origins : Array Origin
  deriving FromJson, ToJson

structure Catalogue where
  private mk ::
  snapshot : Json
  documents : Array Document
  units : Array PagePayload
  paths : Array (Array Nat)
  identities : Array Synapses.Original
  identityExact : identities = documents.map (fun document =>
    Synapses.ObservationContext.originalSubject document.work document.source)

theorem Catalogue.original_identities (catalogue : Catalogue) : catalogue.identities =
    catalogue.documents.map (fun document =>
      Synapses.ObservationContext.originalSubject document.work document.source) := catalogue.identityExact

def bounds (size width index : Nat) : Nat × Nat :=
  (index*width,min size ((index+1)*width))

/-- Every character has a bounded page, including a non-divisible tail.
This says nothing about that character's relevance to a future question. -/
theorem character_has_page (positive : 0 < width) (inside : position < size) :
    (bounds size width (position/width)).1 ≤ position ∧
      position < (bounds size width (position/width)).2 := by
  have lower := Nat.div_mul_le_self position width
  have upper : position < (position/width+1)*width :=
    (Nat.div_lt_iff_lt_mul positive).mp (Nat.lt_succ_self (position/width))
  simp only [bounds]
  omega

def originals (documents : Array Document) : Array Original := documents.map fun document =>
  let view := Synapses.Extraction.layoutView document.source
  ⟨⟨document.owner,document.invocation,document.source⟩,view.text.toList.toArray,view.offsets⟩

def store (snapshot : Json) (documents : Array Document) : Store :=
  ⟨snapshot.compress,originals documents,{},{}⟩

def check (condition : Bool) (message : String) : Except String Unit :=
  unless condition do throw message

/-- Uses the existing reader's 2,400-character pages, with no query, golden,
top-k, preview, or truncation. Text is shared for equal complete pages;
each observation retains its own Work and original coordinates. -/
def prepare (snapshot : Json) (documents : Array Document) (width : Nat) : Except String Catalogue := do
  check (0 < width && width ≤ 2400) "page width must fit the unchanged original-read API"
  let source := store snapshot documents
  let identities := documents.map fun document =>
    Synapses.ObservationContext.originalSubject document.work document.source
  let mut units : Array PagePayload := #[]
  let mut byKey : Std.HashMap (String × Nat × Nat) Nat := {}
  let mut paths := #[]
  for document in [:documents.size] do
    let some original := source.originals[document]? | throw "original directory is incomplete"
    let some identity := identities[document]? | throw "original identity is absent"
    check (original.offsets.size == original.text.size+1) "original coordinate map is incomplete"
    let digest := identity.content
    let mut path := #[]
    let mut position := 0
    while position < original.text.size do
      let stop := min original.text.size (position+width)
      let page ← HistoryWorkspace.Page.check source ⟨document,position,stop⟩
      let some firstRaw := original.offsets[position]? | throw "page start has no original coordinate"
      let some stopRaw := original.offsets[stop]? | throw "page stop has no original coordinate"
      check (firstRaw < stopRaw && stopRaw ≤ identity.chars)
        "page does not map to its immutable original"
      let key := (digest,position,stop)
      let origin : Origin := ⟨document,firstRaw,stopRaw⟩
      let id ← match byKey[key]? with
        | some id => do
            let some unit := units[id]? | throw "payload directory names an absent page"
            check (unit.text == page.text) "equal payload key has different original text"
            units := units.set! id {unit with origins := unit.origins.push origin}
            pure id
        | none => do
            let id := units.size
            units := units.push ⟨digest,position,stop,page.text,#[origin]⟩
            byKey := byKey.insert key id
            pure id
      path := path.push id
      position := stop
    -- This independent, linear check is preparation work, never a hook read.
    let texts ← path.toList.mapM fun id => do
      let some page := units[id]? | throw "original path names an absent page"
      pure page.text
    let restored := String.join texts
    check (restored == String.ofList original.text.toList) "page directory lost, reordered or duplicated original text"
    paths := paths.push path
  return ⟨snapshot,documents,units,paths,identities,rfl⟩

def ranges (catalogue : Catalogue) : Except String (Array Synapses.Range) := do
  let mut result := #[]
  for unit in catalogue.units do
    for origin in unit.origins do
      let some identity := catalogue.identities[origin.document]? | throw "payload has an absent original Work"
      result := result.push (Synapses.Range.original identity origin.first origin.stop)
  return result

/-- A numerical provider must account for every supplied page exactly once.
Missing, duplicate or foreign IDs cannot masquerade as complete scoring. -/
def completeScores (size : Nat) (ids : Array Nat) : Bool :=
  let known := Std.HashSet.ofArray ids
  ids.size == size && ids.all (· < size) && known.size == size && (List.range size).all known.contains

theorem complete_scores_size (accepted : completeScores size ids = true) : ids.size = size := by
  simp only [completeScores,Bool.and_eq_true,beq_iff_eq] at accepted
  exact accepted.1.1.1

theorem complete_scores_cover (accepted : completeScores size ids = true) (inside : index < size) :
    (Std.HashSet.ofArray ids).contains index = true := by
  simp only [completeScores,Bool.and_eq_true] at accepted
  exact List.all_eq_true.mp accepted.2 index (List.mem_range.mpr inside)

end CompleteJudgmentDomain
