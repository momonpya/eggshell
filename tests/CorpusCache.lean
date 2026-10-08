module

public import Eggshell.Matcher

@[expose] public section
namespace Eggshell.TestOracle.CorpusCache
open LogicalText Matcher

/-- A compiled owner includes its deduplicated terms. Reuse requires the
complete owner, never just a hash or previously selected evidence. -/
structure Entry (normalize : Normalizer) where
  owner : OutcomeEdge
  candidate : Option Candidate
  terms : List String
  exact : candidate = Corpus.compileCandidate normalize owner
  termsExact : terms = (candidate.toList.map Corpus.candidateTerms).flatten

structure Index (normalize : Normalizer) where
  owners : List OutcomeEdge
  entries : Std.HashMap Value (Entry normalize)
  rows : List (List String)
  rowsExact : rows = Corpus.ownerRows normalize owners
  frequencies : Frequency.Index rows

def Index.empty (normalize : Normalizer) : Index normalize :=
  ⟨[], {}, [], rfl, Frequency.Index.empty⟩

instance : EmptyCollection (Index normalize) := ⟨Index.empty normalize⟩

structure Compiled (normalize : Normalizer) (owner : OutcomeEdge) where
  candidate : Option Candidate
  terms : List String
  exact : candidate = Corpus.compileCandidate normalize owner
  termsExact : terms = (candidate.toList.map Corpus.candidateTerms).flatten

def lookup (normalize : Normalizer) (entries : Std.HashMap Value (Entry normalize))
    (owner : OutcomeEdge) : Option (Compiled normalize owner) := do
  let entry ← entries[owner.relation]?
  if same : entry.owner = owner then
    pure ⟨entry.candidate, entry.terms, same ▸ entry.exact, entry.termsExact⟩
  else none

def compile (normalize : Normalizer) (previous : Index normalize) (owner : OutcomeEdge) :
    Compiled normalize owner :=
  match lookup normalize previous.entries owner with
  | some prepared => prepared
  | none =>
      let candidate := Corpus.compileCandidate normalize owner
      ⟨candidate, (candidate.toList.map Corpus.candidateTerms).flatten, rfl, rfl⟩

structure Batch (normalize : Normalizer) (owners : List OutcomeEdge) where
  candidates : List Candidate
  entries : Std.HashMap Value (Entry normalize)
  rows : List (List String)
  freshCompiles : Nat
  exact : candidates = owners.filterMap (Corpus.compileCandidate normalize)
  rowsExact : rows = Corpus.ownerRows normalize owners

/-- Preserve current owner order and prune deleted entries. Only a new or
corrected owner compiles text or computes its distinct terms. -/
def prepareOwners (normalize : Normalizer) (previous : Index normalize) :
    (owners : List OutcomeEdge) → Batch normalize owners
  | [] => ⟨[], {}, [], 0, rfl, rfl⟩
  | owner :: owners =>
      let compiled := compile normalize previous owner
      let rest := prepareOwners normalize previous owners
      { candidates := compiled.candidate.toList ++ rest.candidates
        entries := rest.entries.insert owner.relation
          ⟨owner, compiled.candidate, compiled.terms, compiled.exact, compiled.termsExact⟩
        rows := compiled.terms :: rest.rows
        freshCompiles := rest.freshCompiles +
          if (lookup normalize previous.entries owner).isSome then 0 else 1
        exact := by
          rw [compiled.exact, rest.exact]
          cases found : Corpus.compileCandidate normalize owner <;> simp [found]
        rowsExact := by
          change compiled.terms :: rest.rows = _
          rw [compiled.termsExact, compiled.exact, rest.rowsExact]
          rfl }

/-- Taking one owner region reads only row pointers outside the changed
middle. Logical units of retained owners are never traversed here. -/
def middle (rows : List (List String)) (left count : Nat) : List (List String) :=
  (rows.drop left).take count

theorem middle_exact (normalize : Normalizer) (left changed right : List OutcomeEdge) :
    middle (Corpus.ownerRows normalize (left ++ changed ++ right)) left.length changed.length =
      Corpus.ownerRows normalize changed := by
  simp [middle, Corpus.ownerRows_append, ← Corpus.ownerRows_length normalize left,
    ← Corpus.ownerRows_length normalize changed]

def revise (normalize : Normalizer) (previous : Index normalize)
    (owners : List OutcomeEdge) (batch : Batch normalize owners) :
    Index normalize × Nat :=
  let region := Frequency.affectedRegion previous.owners owners
  let removed := middle previous.rows region.left.length region.removed.length
  let added := middle batch.rows region.left.length region.added.length
  have removedExact : removed = Corpus.ownerRows normalize region.removed := by
    simp only [removed, previous.rowsExact, region.old, middle_exact]
  have addedExact : added = Corpus.ownerRows normalize region.added := by
    simp only [added, batch.rowsExact, region.current, middle_exact]
  let frequencies := previous.frequencies.replace batch.rows removed added (by
    intro unit
    rw [previous.rowsExact, batch.rowsExact, removedExact, addedExact]
    simp only [region.old, region.current, Corpus.ownerRows_append, Frequency.count_append]
    omega)
  (⟨owners, batch.entries, batch.rows, batch.rowsExact, frequencies⟩,
    (removed.map List.length).sum + (added.map List.length).sum)

structure Prepared (normalize : Normalizer) (graph : WorkGraph) where
  corpus : Corpus
  index : Index normalize
  freshCompiles : Nat
  /-- Number of distinct owner terms passed to signed frequency updates. -/
  frequencyTouches : Nat
  exact : corpus = Corpus.build normalize graph

def prepare (normalize : Normalizer) (previous : Index normalize) (graph : WorkGraph) :
    Prepared normalize graph :=
  let batch := prepareOwners normalize previous (outcomeCandidates graph)
  let revised := revise normalize previous (outcomeCandidates graph) batch
  let index := revised.1
  let touches := revised.2
  let frequency := fun unit => (index.frequencies.counts.getD unit 0).toNat
  have frequenciesExact : frequency =
      fun unit => (Corpus.referenceFrequencies batch.candidates).getD unit 0 := by
    funext unit
    dsimp only [frequency]
    rw [Frequency.Index.read_exact, Frequency.full_exact,
      index.rowsExact, Corpus.ownerRows_count]
    change Frequency.count (((outcomeCandidates graph).filterMap
      (Corpus.compileCandidate normalize)).map Corpus.candidateTerms) unit = _
    rw [← batch.exact, ← Corpus.full_frequencies_exact, Frequency.full_exact]
  let corpus : Corpus := {
    candidates := batch.candidates
    frequency := frequency
    subworks := graph.subworks.eraseDups
    parents := graph.all }
  { corpus := corpus
    index := index
    freshCompiles := batch.freshCompiles
    frequencyTouches := touches
    exact := by
      dsimp only [corpus]
      rw [frequenciesExact]
      change Corpus.fromCandidates batch.candidates graph.subworks graph.all = _
      rw [batch.exact]
      rfl }

theorem prepare_exact (normalize : Normalizer) (previous : Index normalize) (graph : WorkGraph) :
    (prepare normalize previous graph).corpus = Corpus.build normalize graph :=
  (prepare normalize previous graph).exact

end Eggshell.TestOracle.CorpusCache
