module
public import tools.research.PreparedCitationCoordinates
public import tools.research.PreparedCitationLinks
@[expose] public section
namespace Eggshell.Plugin.PublishedCitations
open Lean Eggshell.Research.PreparedCitationCoordinates

/-- Output geometry and the literal read plan are independent of the current
question, producer rank, and the provenance selected from federated DBs. -/
structure Prepared (source : String) where
  workChars : Nat
  rows : Array (ContextSpan source)
  numbered : List (Nat × ContextSpan source)
  plans : List (String × Nat × Nat)

def prepare (source work : String) : Prepared source :=
  let layout := (decodedToolText? source).map DecodedLayout.make
  let text := layout.map (·.decoded.text) |>.getD source
  let rows := contextRecordSpans source layout
  ⟨work.length+1,rows.toArray,numbered (rows.zip (text.splitOn "\n")),nativeReadPrefix work⟩

def Prepared.project (data : Prepared source) (records : List SourceEvidence.Record) :
    Eggshell.Research.PreparedCitationCoordinates.Data source :=
  ⟨data.workChars,(records.flatMap (·.files)).map (·.relative),
    data.numbered ++ (nativeReadRowsUsing data.rows data.plans records).map Prod.swap⟩

theorem prepared_owner_exact (owner : OutcomeEdge) (records : List SourceEvidence.Record) :
    (do
      let source ← Matcher.atomText? owner.outcome
      let work ← Matcher.atomText? owner.work
      pure (⟨source,(prepare source work).project records⟩ : Sigma Eggshell.Research.PreparedCitationCoordinates.Data)) =
    Eggshell.Research.PreparedCitationCoordinates.prepare owner records := rfl

/-- Wire metadata contains coordinates only, never original or decoded text. -/
structure Stored where
  characters : Nat
  workChars : Nat
  rows : Array (Nat × Nat)
  numbered : List (Nat × Nat × Nat)
  plans : List (String × Nat × Nat)
  deriving ToJson,FromJson

def Stored.valid (data : Stored) : Prop :=
  (∀ row ∈ data.rows, row.1 < row.2 ∧ row.2 ≤ data.characters) ∧
  (∀ row ∈ data.numbered, row.2.1 < row.2.2 ∧ row.2.2 ≤ data.characters)

instance (data : Stored) : Decidable data.valid := inferInstanceAs (Decidable (_ ∧ _))

structure Ready where
  stored : Stored
  bounded : stored.valid

/-- Coordinates are fixed-width records. Flat columns avoid JSON tuple
containers while preserving every integer and the original record order. -/
def packPairs : List (Nat × Nat) → List Nat
  | [] => []
  | (a,b)::rest => a::b::packPairs rest

def unpackPairs : List Nat → Except String (List (Nat × Nat))
  | [] => .ok []
  | a::b::rest => ((a,b)::·) <$> unpackPairs rest
  | _ => .error "incomplete published coordinate pair"

def packTriples : List (Nat × Nat × Nat) → List Nat
  | [] => []
  | (a,b,c)::rest => a::b::c::packTriples rest

def unpackTriples : List Nat → Except String (List (Nat × Nat × Nat))
  | [] => .ok []
  | a::b::c::rest => ((a,b,c)::·) <$> unpackTriples rest
  | _ => .error "incomplete published numbered coordinate"

theorem unpack_pack_pairs (rows : List (Nat × Nat)) : unpackPairs (packPairs rows) = .ok rows := by
  induction rows with
  | nil => rfl
  | cons row rest ih =>
    rcases row with ⟨a,b⟩
    simp only [packPairs,unpackPairs,ih]
    rfl

theorem unpack_pack_triples (rows : List (Nat × Nat × Nat)) : unpackTriples (packTriples rows) = .ok rows := by
  induction rows with
  | nil => rfl
  | cons row rest ih =>
    rcases row with ⟨a,b,c⟩
    simp only [packTriples,unpackTriples,ih]
    rfl

structure Packed where
  characters : Nat
  workChars : Nat
  rows : List Nat
  numbered : List Nat
  plans : List (String × Nat × Nat)
  deriving ToJson,FromJson

def Stored.pack (data : Stored) : Packed :=
  ⟨data.characters,data.workChars,packPairs data.rows.toList,packTriples data.numbered,data.plans⟩

def Packed.unpack (data : Packed) : Except String Stored := do
  return ⟨data.characters,data.workChars,(← unpackPairs data.rows).toArray,
    ← unpackTriples data.numbered,data.plans⟩

theorem unpack_pack_exact (data : Stored) : data.pack.unpack = .ok data := by
  cases data
  simp only [Stored.pack,Packed.unpack,unpack_pack_pairs,unpack_pack_triples]
  simp only [bind,Except.bind,Array.toArray_toList]
  rfl

instance : ToJson Ready := ⟨fun value => toJson value.stored.pack⟩
instance : FromJson Ready where
  fromJson? json := do
    let packed : Packed ← fromJson? json
    let stored ← packed.unpack
    if bounded : stored.valid then return ⟨stored,bounded⟩
    else throw "published citation coordinates exceed their original output"

def Prepared.store (data : Prepared source) : Ready :=
  ⟨⟨source.length,data.workChars,data.rows.map (fun row => (row.start,row.stop)),
    data.numbered.map (fun (number,row) => (number,row.start,row.stop)),data.plans⟩,by
      constructor
      · intro row member
        obtain ⟨span,_,rfl⟩ := Array.mem_map.mp member
        exact ⟨span.ordered,span.within⟩
      · intro row member
        obtain ⟨⟨number,span⟩,_,rfl⟩ := List.mem_map.mp member
        exact ⟨span.ordered,span.within⟩⟩

/-- Bind integer coordinates to the caller's already admitted scalar. This
does no JSON decoding, character scanning, line splitting or shell parsing.
The span proofs are reused; the small typed wrappers are request-local. -/
def Ready.bind (data : Ready) (source : String) (same : data.stored.characters = source.length) : Prepared source :=
  ⟨data.stored.workChars,
    data.stored.rows.attach.map (fun row =>
      ⟨row.val.1,row.val.2,(data.bounded.1 row.val row.property).1,
        same ▸ (data.bounded.1 row.val row.property).2⟩),
    data.stored.numbered.attach.map (fun row =>
      (row.val.1,⟨row.val.2.1,row.val.2.2,(data.bounded.2 row.val row.property).1,
        same ▸ (data.bounded.2 row.val row.property).2⟩)),data.stored.plans⟩

theorem bind_store_exact (data : Prepared source) : data.store.bind source rfl = data := by
  cases data with
  | mk work rows numbered plans =>
    simp only [Prepared.store,Ready.bind]
    congr 1
    · apply Array.ext
      · simp
      · intro index first second
        simp

    · apply List.ext_getElem
      · simp
      · intro index first second
        simp

theorem store_characters (data : Prepared source) : data.store.stored.characters = source.length := rfl
theorem store_workChars (data : Prepared source) : data.store.stored.workChars = data.workChars := rfl
theorem prepare_workChars (source work : String) : (prepare source work).workChars = work.length+1 := rfl

def compile (source work : Option String) : Option Ready := do
  pure (prepare (← source) (← work)).store

def queryUsing (parse : Nat → String → String → List (Nat × Nat))
    (ready : Option Ready) (owner : OutcomeEdge) (records : List SourceEvidence.Record)
    (texts : List (Nat × String)) : Except String (Option Result) := do
  match ready,Matcher.atomText? owner.outcome,Matcher.atomText? owner.work with
  | none,none,_ | none,_,none => return none
  | some data,some source,some work =>
    if same : data.stored.characters = source.length then
      unless data.stored.workChars == work.length+1 do throw "published citation Work length changed"
      return ((data.bind source same).project records).queryUsing parse texts
    else throw "published citation output length changed"
  | _,_,_ => throw "published citation availability changed"

def query (ready : Option Ready) (owner : OutcomeEdge) (records : List SourceEvidence.Record)
    (texts : List (Nat × String)) : Except String (Option Result) :=
  queryUsing (fun _ => citedLineIntervals) ready owner records texts

theorem query_using_exact (parser : PreparedCitationLinks.Parser) (valid : PreparedCitationLinks.Parser.valid parser)
    (ready : Option Ready) (owner : OutcomeEdge) (records : List SourceEvidence.Record)
    (texts : List (Nat × String)) :
    queryUsing parser.parse ready owner records texts = query ready owner records texts := by
  have same : parser.parse = fun _ => citedLineIntervals := by
    funext id text relative
    exact parser.parse_exact valid id text relative
  rw [same]
  rfl

structure Metadata where
  coordinates : Option Ready
  links : PreparedCitationLinks.Links
  deriving ToJson,FromJson

def metadata (source : String) (work : Option String) : Metadata :=
  ⟨compile (some source) work,PreparedCitationLinks.prepare source⟩

theorem query_compiled_exact (owner : OutcomeEdge) (records : List SourceEvidence.Record)
    (texts : List (Nat × String)) :
    query (compile (Matcher.atomText? owner.outcome) (Matcher.atomText? owner.work)) owner records texts =
      .ok (rankedCitedObservationCoordinates texts owner records) := by
  rw [← Eggshell.Research.PreparedCitationCoordinates.query_prepare_exact]
  rw [← prepared_owner_exact]
  cases source : Matcher.atomText? owner.outcome <;> cases work : Matcher.atomText? owner.work
  all_goals simp [compile,query,queryUsing,source,work,bind,Option.bind,
    Eggshell.Research.PreparedCitationCoordinates.query,store_characters,store_workChars,
    prepare_workChars,bind_store_exact]
  all_goals rfl

#print axioms prepared_owner_exact
#print axioms bind_store_exact
#print axioms unpack_pack_exact
#print axioms query_compiled_exact
#print axioms query_using_exact
end Eggshell.Plugin.PublishedCitations
