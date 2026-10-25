module
public import Eggshell.LexicalReads
public import Eggshell.SourceDelta
public import Eggshell.SearchRank

@[expose] public section
namespace Eggshell.LexicalAdvice
open Lean DB Persistence.Store

/-- Query-invariant weights are evaluated once. Per-row Float additions keep
the reference term order and separate primary/auxiliary lanes exactly. -/
def rankPrepared (query : String) (rows : List α) (contains : α → String → Bool)
    (frequency : String → Nat) (anchors : Bool) (population : Nat) : List Nat :=
  let weights := ((RetrievalResearch.tokens query).filter fun term =>
    !anchors || RetrievalResearch.anchor term).map fun term =>
      (term,RetrievalResearch.log1p (population.toFloat / (frequency term).toFloat))
  let scored := rows.zipIdx.filterMap fun (row,index) =>
    let scores := weights.foldl (fun (scores : Float × Float) term =>
      if contains row term.1 then
        if term.1.startsWith "P" then (scores.1+term.2,scores.2)
        else (scores.1,scores.2+term.2)
      else scores) (0.0,0.0)
    if scores.1 > 0 || scores.2 > 0 then some (scores.1,scores.2,index) else none
  ((scored.mergeSort fun a b => a.1 > b.1 ||
    (a.1 == b.1 && (a.2.1 > b.2.1 || (a.2.1 == b.2.1 && a.2.2 ≤ b.2.2)))).map (·.2.2))

theorem rank_prepared_exact (query : String) (rows : List α) (contains : α → String → Bool)
    (frequency : String → Nat) (anchors : Bool) (population : Nat) :
    rankPrepared query rows contains frequency anchors population =
      SearchRank.rankRows query rows contains frequency anchors population := by
  simp only [rankPrepared,SearchRank.rankRows,RetrievalResearch.rankRows,List.foldl_map]

structure Posting where
  rows : List (Nat × Nat)
  frequency : Nat
  complete : rows.length = frequency

/-- These rows are checksum-checked nomination hints. Opening already binds
the lexical publication to this source's incarnation, authority and stamp.
No live source owner or Work is read here, and no equality is created. -/
def posting (reader : RetrievalResearch.Index.Reader source) (term : String) : IO Posting := do
  let some found ← findTerm? reader.index reader.index.get term | return ⟨[],0,rfl⟩
  let rows ← directory reader.index (key "posting" found.id)
  let frequency ← getNat reader.index.get (key "frequency" found.id)
  if complete : rows.length = frequency then
    unless frequency ≤ reader.expected.candidates &&
        rows.all (fun row => row.1 < reader.expected.roots) &&
        (Std.HashSet.ofList (rows.map Prod.snd)).size == rows.length do
      throw (IO.userError "invalid advisory lexical posting population or order")
    return ⟨rows,frequency,complete⟩
  else throw (IO.userError "advisory lexical posting frequency disagrees")

structure Result where
  source : Snapshot
  reader : RetrievalResearch.Index.Reader source
  ordinals : Std.HashMap Nat Nat
  ranked : List Nat
  anchors : List Nat
  postingRows : Nat
  elapsedMs : Nat

/-- Complete lexical nominations use index ordinals. Original membership and
the indexed/live ordinal agreement are deferred to the consumed owners below.
An unavailable index is never a successful empty query. -/
def query (source : Snapshot) (text : String) (receipt : Option String := none) : IO Result := do
  let started ← IO.monoMsNow
  let some reader ← RetrievalResearch.Index.open? source |
    throw (IO.userError "advisory lexical index is pending explicit/background warm")
  let mut postings : Std.HashMap String (Std.HashSet Nat) := {}
  let mut frequencies : Std.HashMap String Nat := {}
  let mut owners : Std.HashSet Nat := {}
  let mut ordinals : Std.HashMap Nat Nat := {}
  let mut postingRows := 0
  for term in SearchRank.terms text do
    let found ← posting reader term
    postings := postings.insert term (Std.HashSet.ofList (found.rows.map Prod.snd))
    frequencies := frequencies.insert term found.frequency
    postingRows := postingRows+found.rows.length
    for (ordinal,owner) in found.rows do
      if let some previous := ordinals[owner]? then
        unless previous == ordinal do throw (IO.userError "lexical hints disagree about an original ordinal")
      ordinals := ordinals.insert owner ordinal
      owners := owners.insert owner
  let ordered ← owners.toList.mapM fun owner => do
    let some ordinal := ordinals[owner]? | throw (IO.userError "lexical ordinal directory lost its owner")
    return (ordinal,owner)
  let rows := ((ordered.mergeSort (fun a b => a.1 ≤ b.1)).map Prod.snd).toArray
  let contains := fun owner term => (postings.getD term {}).contains owner
  let rank := fun anchors =>
    (rankPrepared text rows.toList contains (frequencies.getD · 0) anchors reader.expected.candidates).filterMap (rows[·]?)
  let ranked := rank false
  let anchors := rank true
  let elapsed := (← IO.monoMsNow)-started
  Receipt.observe receipt ("lexical-advice-"++source.head.identity) (Json.mkObj [
    ("postingRows",toJson postingRows),("owners",toJson rows.size),
    ("originalOwnerChecks",toJson (0 : Nat)),("elapsedMs",toJson elapsed),
    ("authority",toJson "advisory-only"),("completePostingCounts",toJson true)])
  return ⟨source,reader,ordinals,ranked,anchors,postingRows,elapsed⟩

/-- Selected hints still pass the same three original scalar checks. Source
header, reverse candidate and original window directory checks follow in the
existing selective original reader. No hint can supply a replacement Work. -/
def originals (result : Result) (owners : List Nat) (receipt : Option String := none) :
    IO (List SearchDocument) := do
  let source := result.source
  unless owners.length ≤ 256 && (Std.HashSet.ofList owners).size == owners.length do
    throw (IO.userError "excess or duplicate consumed lexical owners")
  for owner in owners do
    let some ordinal := result.ordinals[owner]? |
      throw (IO.userError "consumed lexical owner was never nominated")
    let indexed ← result.reader.index.get (key "owner" owner)
    let member ← source.get (key "member" owner)
    let candidate ← source.get (key "candidate" owner)
    let some _checked := LexicalReads.OwnerWitness.check? ordinal indexed member candidate |
      throw (IO.userError "consumed lexical hint disagrees with its original source")
    pure ()
  let documents ← SourceDelta.documents source owners
  unless documents.length == owners.length do throw (IO.userError "consumed lexical owner disappeared")
  Receipt.observe receipt ("lexical-consumed-"++source.head.identity) (Json.mkObj [
    ("originalOwnerChecks",toJson owners.length),("documents",toJson documents.length),
    ("source",toJson source.head),("advisoryOnly",toJson true)])
  return documents

end Eggshell.LexicalAdvice
