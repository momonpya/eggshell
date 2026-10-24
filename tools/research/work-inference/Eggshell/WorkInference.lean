module
public import Eggshell.GraphStore
public import Eggshell.Matcher

@[expose] public section
namespace Eggshell.WorkInference
open Matcher Persistence.Store

/-- Opaque source references carry identity/provenance; they contain no invented
Outcome payload. Recommendation membership is an independent Boolean lane. -/
structure Input (α : Type) where
  source : α
  view : WorkView
  retrieved : Bool

structure Prepared (α : Type) where
  source : α
  work : WorkAlignment
  retrieved : Bool

def prepare (input : Input α) (cover : CoverageProvider) (quotient : Quotient)
    (corpus : Corpus) (current : Value) (pattern : Pattern) (patterns : List WorkPattern)
    (native : Bool) : List (Prepared α) :=
  (input.view.preparedWorks cover quotient corpus current pattern patterns input.retrieved native).map
    fun (work,retrieved) => ⟨input.source,work,retrieved⟩

def pass (inputs : List (Input α)) (cover : CoverageProvider) (quotient : Quotient)
    (corpus : Corpus) (current : Value) (pattern : Pattern) (patterns : List WorkPattern)
    (native : Bool) : List (Prepared α) :=
  (inputs.filter fun input => Matcher.sharesSurface pattern input.view.pattern || input.retrieved).flatMap
    fun input => prepare input cover quotient corpus current pattern patterns native

/-- The Work pass needs global weights and membership, but carries no candidate
Outcome payloads even inside its corpus argument. -/
theorem pass_candidates_irrelevant (inputs : List (Input α)) (cover : CoverageProvider)
    (quotient : Quotient) (corpus : Corpus) (candidates : List Candidate) (current : Value)
    (pattern : Pattern) (patterns : List WorkPattern) (native : Bool) :
    pass inputs cover quotient {corpus with candidates := candidates} current pattern patterns native =
      pass inputs cover quotient corpus current pattern patterns native := rfl

def Prepared.propose (row : Prepared α) (quotient : Quotient) (inquiry : Value) : Option UnionEdge :=
  row.work.localUnion? quotient inquiry row.retrieved

/-- A sufficient zero-effect test using the production delivery conditions,
not a relevance threshold. Children are retained for result-grounded reuse. -/
def Prepared.inert (row : Prepared α) (quotient : Quotient) (inquiry : Value) : Bool :=
  !row.retrieved && !row.work.subwork && !row.work.wholeWorkIdentity &&
    !(row.work.priorInDemand.distinctiveAnchors > 1 || row.work.demandInPrior.distinctiveAnchors > 1) &&
    (row.propose quotient inquiry).isNone

/-- No possible result context can turn an inert Work comparison into delivery
or Union authority. This does not itself prove scheduler/quotient-domain pruning. -/
theorem Prepared.inert_effects (row : Prepared α) (quotient : Quotient) (inquiry : Value)
    (matched : Match) (work : matched.work = row.work) (retrieved : matched.retrieved = row.retrieved)
    (inert : row.inert quotient inquiry = true) :
    matched.automatic = false ∧ Matcher.localUnion? quotient inquiry matched = none := by
  cases proposal : row.propose quotient inquiry with
  | some edge => simp [Prepared.inert,proposal] at inert
  | none =>
    cases nomination : row.retrieved <;> cases child : row.work.subwork <;>
      cases whole : row.work.wholeWorkIdentity <;>
      simp_all [Prepared.inert, Prepared.propose, Matcher.Match.automatic, Matcher.localUnion?]

def unions (rows : List (Prepared α)) (quotient : Quotient) (inquiry : Value) : List UnionEdge :=
  Matcher.distinctLocalUnions (rows.filterMap (fun row => row.propose quotient inquiry))

theorem Prepared.retrieved_never_proposes (row : Prepared α) (quotient : Quotient)
    (inquiry : Value) (retrieved : row.retrieved = true) :
    row.propose quotient inquiry = none := by
  simp [propose, WorkAlignment.localUnion?, retrieved]

theorem Prepared.proposed_scope (row : Prepared α) (quotient : Quotient) (inquiry : Value)
    (edge : UnionEdge) (created : row.propose quotient inquiry = some edge) :
    edge.scope = .run inquiry := by
  simp only [propose, WorkAlignment.localUnion?] at created
  split at created <;> try contradiction
  split at created <;> try contradiction
  split at created <;> try contradiction
  split at created <;> try contradiction
  next exactSafe =>
    have same := Option.some.inj created
    subst edge
    rfl

def ofCandidate (source : α) (candidate : Candidate) (semantic : SemanticNominations) : Input α :=
  ⟨source,candidate.workView,Matcher.externallyNominated semantic.related candidate⟩

/-- For the same admitted candidates and fixed quotient, every ordered proposal
equals the result of the actual matcher after full Outcome grounding. There is
no top-K premise and no dependence on result bytes or evidence text. This is a
single-pass refinement, not a theorem about the discovery scheduler's fixpoint. -/
theorem complete_pass_exact (sources : List (α × Candidate)) (normalize : LogicalText.Normalizer)
    (cover : CoverageProvider) (view : RunView) (corpus : Corpus) (current : Value)
    (text : String) (native : Bool) (query : CompiledDemand normalize text native)
    (semantic : SemanticNominations) (evidence : Option String) (inquiry : Value) :
    unions (sources.flatMap fun (source,candidate) =>
      prepare (ofCandidate source candidate semantic) cover view.quotient corpus current
        query.pattern query.workPatterns native) view.quotient inquiry =
      Matcher.newLocalUnions view inquiry (sources.flatMap fun (_,candidate) =>
        candidate.findMatches normalize cover view.quotient corpus current text native query evidence semantic) := by
  unfold unions Matcher.newLocalUnions prepare ofCandidate Candidate.findMatches
  simp only [Candidate.preparedWorks_work_only, List.filterMap_flatMap, List.filterMap_map]
  rfl

theorem complete_admitted_pass_exact (sources : List (α × Candidate))
    (normalize : LogicalText.Normalizer) (cover : CoverageProvider) (view : RunView)
    (corpus : Corpus) (current : Value) (text : String) (native : Bool)
    (query : CompiledDemand normalize text native) (semantic : SemanticNominations)
    (evidence : Option String) (inquiry : Value) :
    unions (pass (sources.map fun (source,candidate) => ofCandidate source candidate semantic)
      cover view.quotient corpus current query.pattern query.workPatterns native) view.quotient inquiry =
      Matcher.newLocalUnions view inquiry
        (Matcher.findInUsing normalize (Matcher.demandProvider normalize text native query) cover
          view.quotient {corpus with candidates := sources.map Prod.snd} current text evidence semantic native) := by
  have demand : Matcher.demandProvider normalize text native query text native = query := by
    simp [Matcher.demandProvider]
  unfold pass unions prepare ofCandidate Matcher.newLocalUnions Matcher.findInUsing
    Matcher.admittedCandidates Matcher.nominated Matcher.SemanticNominations.contains
    Candidate.findMatches
  rw [demand]
  simp only [Candidate.preparedWorks_work_only,
    List.filter_map, List.flatMap_map, List.filterMap_flatMap, List.filterMap_map]
  rfl

/-- A reference remains scoped to the full source head. A local numeric id is
never a global/federated identity or a proof that another DB has the same Work. -/
structure Address where
  head : DB.PageMap.Head
  owner : Nat
  work : Nat
  outcome : Nat

/-- Reads original live membership, Work and occurrence structure, without
calling NodeReader.outcome or fabricating an Outcome edge. These are the same
source readers used by production Work admission; their IO is a trust boundary. -/
def load (reader : NodeReader snapshot) (owner : Nat) (retrieved : Bool := false) :
    IO (Input Address) := do
  let located ← reader.locateOutcome owner
  unless located.head == snapshot.head do throw (IO.userError "foreign Work inference origin")
  let origin ← reader.workOrigin located
  let some view := WorkView.compile LogicalText.logicalNormalizer origin.work origin.native |
    throw (IO.userError "nontextual Work inference origin")
  return ⟨⟨snapshot.head,owner,located.header.work,located.header.outcome⟩,view,retrieved⟩

end Eggshell.WorkInference
