module

public import tests.CorpusCache
public import Eggshell.GeometryMemo
public import Eggshell.SaturationMemo

@[expose] public section
namespace Eggshell.TestOracle.SearchMemo
open Matcher LogicalText Plugin

/-- Test-only full-corpus memo model for checking incremental primitives.
Includes the full current universe, not only previously selected evidence.
New matches, removals, ordering, frequencies and topology cannot hide behind a
positive-only dependency trace. Presentation receipts and budget remain outside. -/
structure Input where
  sources : List String
  authorities : List Value
  origins : List (Value × Value)
  unionOrigins : List (UnionEdge × Value)
  values : List Value
  unions : List UnionEdge
  graph : WorkGraph
  current : String
  evidence : Option String
  semantic : SemanticNominations
  localUnion : Bool
  native : Bool
  deriving DecidableEq

structure PreparedDiscovery where
  discovery : Discovery
  extraction : Extraction
  exact : extraction = Matcher.extraction discovery

def finish (discovery : Discovery) : PreparedDiscovery :=
  ⟨discovery, Matcher.extraction discovery, rfl⟩

def evaluate (input : Input) (prepared : CorpusCache.Prepared logicalNormalizer input.graph) :
    Option PreparedDiscovery :=
  (discoverIn? logicalNormalizer (.text input.current) input.values input.unions input.graph
    prepared.corpus input.current input.evidence input.semantic input.localUnion input.native).map finish

def evaluateUsing (cache : GeometryMemo.Cache) (input : Input)
    (demand : CompiledDemand logicalNormalizer input.current input.native)
    (prepared : CorpusCache.Prepared logicalNormalizer input.graph)
    (plan : Option QuotientBuilder.CongruenceMemo.Entry := none) : Option PreparedDiscovery :=
  (discoverInUsing? logicalNormalizer
    (demandProvider logicalNormalizer input.current input.native demand)
    (GeometryMemo.provider cache) (.text input.current)
    input.values input.unions input.graph prepared.corpus input.current input.evidence
    input.semantic input.localUnion input.native
    (IncrementalQuotient.ViewProvider.withPlan plan)).map finish

theorem evaluateUsing_exact (cache : GeometryMemo.Cache) (input : Input)
    (demand : CompiledDemand logicalNormalizer input.current input.native)
    (prepared : CorpusCache.Prepared logicalNormalizer input.graph)
    (plan : Option QuotientBuilder.CongruenceMemo.Entry := none) :
    evaluateUsing cache input demand prepared plan = evaluate input prepared := by
  rw [evaluateUsing, discoverInUsing_views_exact, GeometryMemo.provider_exact, demandProvider_exact]
  rfl

def reference (input : Input) : Option PreparedDiscovery :=
  (discoverIn? logicalNormalizer (.text input.current) input.values input.unions input.graph
    (Corpus.build logicalNormalizer input.graph) input.current input.evidence
    input.semantic input.localUnion input.native).map finish

theorem evaluate_exact (input : Input) (prepared : CorpusCache.Prepared logicalNormalizer input.graph) :
    evaluate input prepared = reference input := by rw [evaluate, prepared.exact]; rfl

structure Entry where
  input : Input
  result : Option PreparedDiscovery
  exact : result = reference input
  ranks : GeometryMemo.Cache := {}
  demand : CompiledDemand logicalNormalizer input.current input.native :=
    CompiledDemand.make logicalNormalizer input.current input.native
  savedRanks : RankMemo.Saved := []
  rankReused : Nat := 0
  rankComputed : Nat := 0

abbrev Cache := Option Entry

structure Result (input : Input) where
  result : Option PreparedDiscovery
  exact : result = reference input

def lookup (cache : Cache) (input : Input) : Option (Result input) := do
  let entry ← cache
  if same : entry.input = input then
    pure ⟨entry.result, same ▸ entry.exact⟩
  else none

/-- Only the demanded input is updated. No background refresh of past queries;
a successful empty result is reusable, while busy/error notices never enter. -/
def getUsing (cache : Cache) (saved : RankMemo.Saved) (input : Input)
    (prepared : CorpusCache.Prepared logicalNormalizer input.graph)
    (savedSaturation : SaturationMemo.Saved := []) :
    Result input × Cache :=
  match lookup cache input with
  | some found => (found, cache)
  | none =>
      let previous := cache.map (·.ranks) |>.getD {}
      let demand : CompiledDemand logicalNormalizer input.current input.native :=
        match cache with
        | some entry =>
            if same : entry.input.current = input.current ∧ entry.input.native = input.native then
              ⟨entry.demand.pattern, entry.demand.workPatterns,
                by rw [← same.1]; exact entry.demand.patternExact,
                by rw [← same.1, ← same.2]; exact entry.demand.patternsExact⟩
            else CompiledDemand.make logicalNormalizer input.current input.native
        | none => CompiledDemand.make logicalNormalizer input.current input.native
      let requested := GeometryMemo.inputsPrepared prepared.corpus input.current input.semantic input.native demand
      let ranks := GeometryMemo.prepareRanks previous saved requested
      let ranking := GeometryMemo.prepareUsing previous ranks.cache requested
      -- Atom-only indexed equality already has its dependent Union index.
      -- General plans are demanded only when that fast kernel is insufficient.
      let general := !IncrementalQuotient.atomWork input.graph ||
        (QuotientBuilder.AtomQuotient.prepare input.unions).isNone
      let basis := SaturationMemo.Basis.make (if general then
        SaturationMemo.kernelValues (.text input.current :: input.values) input.unions else [])
      let plan := if general then SaturationMemo.restore basis savedSaturation else none
      let result := evaluateUsing ranking.cache input demand prepared plan
      let exact := (evaluateUsing_exact ranking.cache input demand prepared plan).trans
        (evaluate_exact input prepared)
      (⟨result, exact⟩, some ⟨input, result, exact, ranking.cache, demand,
        ranks.saved, ranks.reused, ranks.computed⟩)

def get (cache : Cache) := getUsing cache []

theorem getUsing_exact (cache : Cache) (saved : RankMemo.Saved) (input : Input)
    (prepared : CorpusCache.Prepared logicalNormalizer input.graph)
    (savedSaturation : SaturationMemo.Saved := []) :
    (getUsing cache saved input prepared savedSaturation).1.result = reference input :=
  (getUsing cache saved input prepared savedSaturation).1.exact

theorem get_exact (cache : Cache) (input : Input)
    (prepared : CorpusCache.Prepared logicalNormalizer input.graph) :
    (get cache input prepared).1.result = reference input :=
  (get cache input prepared).1.exact

theorem changed_input_rejected (entry : Entry) (input : Input) (different : entry.input ≠ input) :
    lookup (some entry) input = none := by simp [lookup, different]

end Eggshell.TestOracle.SearchMemo
