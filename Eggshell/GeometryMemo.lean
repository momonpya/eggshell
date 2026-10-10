module

public import Eggshell.RankMemo
public import Eggshell.SelectionReplay

@[expose] public section
namespace Eggshell.Matcher.GeometryMemo
open LogicalText

/-- Complete inputs to coverage ranking. A changed document count, relevant
term frequency, original span, or normalized spelling changes this key.
Union representatives and unrelated owner text are not coverage inputs. -/
structure Input where
  past : LogicalText.T
  current : LogicalText.T
  pastWeights : List Nat
  currentWeights : List Nat
  novelty : Nat
  pastLocator : UInt64 := hash past
  currentLocator : UInt64 := hash current
  deriving DecidableEq, BEq

/-- The expensive immutable logical text is hashed at compilation, once.
These small addresses only locate candidates; equality below still checks
all original bytes, spans, weights and count before semantic reuse. -/
abbrev Locator := UInt64 × UInt64 × UInt64 × UInt64 × Nat

def Input.locator (input : Input) : Locator :=
  (input.pastLocator, input.currentLocator, hash input.pastWeights,
    hash input.currentWeights, input.novelty)

def reference (input : Input) : List (Coverage × Coverage) :=
  pairedCoverages (makePattern input.past) (makePattern input.current)
    input.pastWeights input.currentWeights input.novelty

structure Entry where
  input : Input
  result : List (Coverage × Coverage)
  exact : result = reference input

abbrev Cache := Std.HashMap Locator Entry

structure Result (input : Input) where
  result : List (Coverage × Coverage)
  reused : Bool
  exact : result = reference input

/-- A hash only selects a bucket. Full input equality is checked again before
transporting the stored proof. Empty alignments are reusable too. -/
def lookup (cache : Cache) (input : Input) : Option (Result input) := do
  let entry ← cache[input.locator]?
  if same : entry.input = input then
    pure ⟨entry.result, true, same ▸ entry.exact⟩
  else none

def get (cache : Cache) (input : Input) : Result input :=
  match lookup cache input with
  | some found => found
  | none => ⟨reference input, false, rfl⟩

def provider (cache : Cache) : CoverageProvider := fun past current pw cw novelty =>
  (get cache ⟨past.logical, current.logical, pw, cw, novelty, past.locator, current.locator⟩).result

theorem provider_exact (cache : Cache) : provider cache = pairedCoverages := by
  funext past current pw cw novelty
  change (get cache _).result = _
  rw [(get cache _).exact]
  simp only [reference, ← Pattern.canonical past, ← Pattern.canonical current]

structure Prepared where
  cache : Cache
  reused : Nat
  computed : Nat

/-- Retain only the demanded keys. An old result with changed ranking inputs
is recomputed; unused past demands are never refreshed. -/
def prepareUsing (previous : Cache) (ranks : RankMemo.Cache) : List Input → Prepared
  | [] => ⟨{}, 0, 0⟩
  | input :: rest =>
      let found : Result input := match lookup previous input with
        | some found => found
        | none =>
            let result := pairedCoveragesUsing (RankMemo.provider ranks)
              (makePattern input.past) (makePattern input.current)
              input.pastWeights input.currentWeights input.novelty
            ⟨result, false, by
              change pairedCoveragesUsing (RankMemo.provider ranks) _ _ _ _ _ = _
              rw [RankMemo.provider_exact]; rfl⟩
      let tail := prepareUsing previous ranks rest
      ⟨tail.cache.insert input.locator ⟨input, found.result, found.exact⟩,
        tail.reused + if found.reused then 1 else 0,
        tail.computed + if found.reused then 0 else 1⟩

def prepare (previous : Cache) := prepareUsing previous {}

structure Persistent where
  prepared : Prepared
  saved : RankMemo.Saved := []
  charged : Nat := 0
  bounded : charged ≤ RankMemo.allowance := by decide
  replayed : Nat := 0
  repaired : Nat := 0

def Persistent.retain (state : Persistent) (key : String) (positions : List Nat)
    (reused : Bool) : Persistent :=
  let state := {state with
    replayed := state.replayed + if reused then 1 else 0
    repaired := state.repaired + if reused then 0 else 1}
  if state.saved.any (·.1 == key) then state else
  let cost := RankMemo.codec.encodedSize [(key, positions)]
  if fits : state.charged + cost ≤ RankMemo.allowance then
    {state with
      saved := (key, positions) :: state.saved
      charged := state.charged + cost
      bounded := fits}
  else state

/-- Selection traces are checked against every current ranked candidate.
Changed frequency may leave the same trace valid, while scores are always
reconstructed from current weights and population. No serialized Coverage
or evidence payload becomes authoritative. -/
def obtainCoverage (reader : Option (RankMemo.Reader .selection)) (state : Persistent)
    (query target : Pattern) (weights : List Nat) (novelty : Nat) (ranked : List Evidence) :
    IO ({ cover : Option Coverage // cover = workCoverage query weights novelty ranked } × Persistent) := do
  let key := RankMemo.binding query target
  let eligible := reader.isSome && 32 ≤ ranked.length && ranked.length ≤ RankMemo.frontierAllowance
  let saved ← if eligible then
      match reader with
      | some reader => pure ((← reader.get key).head?.map (·.2))
      | none => pure none
    else pure none
  let found := SelectionReplay.obtain ranked saved
  let cover : { cover : Option Coverage // cover = workCoverage query weights novelty ranked } :=
    ⟨coverageOf query weights novelty found.1.val, by rw [found.1.property]; rfl⟩
  let state := if eligible then state.retain key found.2.1 found.2.2 else state
  return (cover, state)

def obtainPair (reader : Option (RankMemo.Reader .selection)) (state : Persistent)
    (ranks : RankMemo.Cache) (input : Input) : IO (Result input × Persistent) := do
  let past := makePattern input.past
  let current := makePattern input.current
  if empty : LogicalText.isEmpty input.past || LogicalText.isEmpty input.current ||
      input.pastWeights.length != input.past.units.length ||
      input.currentWeights.length != input.current.units.length then
    return (⟨[], false, by
      simp only [reference, pairedCoverages, pairedCoveragesUsing,
        show (makePattern input.past).logical = input.past from rfl,
        show (makePattern input.current).logical = input.current from rfl, empty, ↓reduceIte]⟩, state)
  else
    if same : sameLogicalUnits past current then
      return (⟨[(completeCoverage past input.pastWeights input.novelty,
        completeCoverage current input.currentWeights input.novelty)], false, by
          change _ = pairedCoveragesUsing referenceRank past current input.pastWeights input.currentWeights input.novelty
          simp only [pairedCoveragesUsing,
            show past.logical = input.past from rfl,
            show current.logical = input.current from rfl,
            empty, same, Bool.false_eq_true, ↓reduceIte]⟩, state)
    else
      let forward := RankMemo.provider ranks input.pastWeights past current
      let reverse := RankMemo.provider ranks input.currentWeights current past
      let (first, state) ← obtainCoverage reader state past current input.pastWeights input.novelty forward
      let (second, state) ← obtainCoverage reader state current past input.currentWeights input.novelty reverse
      let result := match first.val, second.val with
        | some forward, some reverse => [(forward, reverse)]
        | _, _ => []
      return (⟨result, false, by
        have forwardExact : forward = referenceRank input.pastWeights past current := by
          simp only [forward, RankMemo.provider_exact]
        have reverseExact : reverse = referenceRank input.currentWeights current past := by
          simp only [reverse, RankMemo.provider_exact]
        calc result = (match workCoverage past input.pastWeights input.novelty forward,
            workCoverage current input.currentWeights input.novelty reverse with
            | some a, some b => [(a, b)] | _, _ => []) := by
              dsimp only [result]; rw [first.property, second.property]; rfl
          _ = reference input := by
            rw [forwardExact, reverseExact]
            change _ = pairedCoveragesUsing referenceRank past current input.pastWeights input.currentWeights input.novelty
            simp only [pairedCoveragesUsing,
              show past.logical = input.past from rfl,
              show current.logical = input.current from rfl,
              empty, same, Bool.false_eq_true, ↓reduceIte]
            cases workCoverage past input.pastWeights input.novelty (referenceRank input.pastWeights past current) <;>
              cases workCoverage current input.currentWeights input.novelty (referenceRank input.currentWeights current past) <;> rfl⟩, state)

/-- Only active demands repair traces. Entry carries the whole canonical
coverage equality into the actual existing matcher API. -/
def prepareUsingM (previous : Cache) (ranks : RankMemo.Cache)
    (reader : Option (RankMemo.Reader .selection)) (initial : Persistent) (inputs : List Input) :
    IO Persistent := do
  let mut state := {initial with prepared := ⟨{}, 0, 0⟩}
  for input in inputs.reverse do
    let (found, updated) ← match lookup previous input with
      | some found => pure (found, state)
      | none => obtainPair reader state ranks input
    state := updated
    let prepared := state.prepared
    state := {state with prepared :=
      ⟨prepared.cache.insert input.locator ⟨input, found.result, found.exact⟩,
       prepared.reused + if found.reused then 1 else 0,
       prepared.computed + if found.reused then 0 else 1⟩}
  return state

/-- Current complete ranking dependencies nominate the only persisted orders
to validate. Equal logical units and empty inputs use the cheap direct path. -/
def addRanks (coverage : Cache) (previous : RankMemo.Saved)
    (input : Input) (prepared : RankMemo.Prepared) : RankMemo.Prepared :=
  let needsJoin := !LogicalText.isEmpty input.past && !LogicalText.isEmpty input.current &&
    input.pastWeights.length == input.past.units.length &&
    input.currentWeights.length == input.current.units.length &&
    input.past.units.map (·.text) != input.current.units.map (·.text)
  if (lookup coverage input).isSome || !needsJoin then prepared else
    let past := makePattern input.past
    let current := makePattern input.current
    (prepared.add previous input.pastWeights past current).add previous
      input.currentWeights current past

/-- A discovery pass adds only its current demands to the same bounded rank
frontier. It does not refresh other persisted queries or publish per pass. -/
def prepareRanksFrom (prepared : RankMemo.Prepared) (coverage : Cache)
    (previous : RankMemo.Saved) (inputs : List Input) : RankMemo.Prepared :=
  inputs.foldr (addRanks coverage previous) prepared

def prepareRanks (coverage : Cache) (previous : RankMemo.Saved) (inputs : List Input) :
    RankMemo.Prepared := prepareRanksFrom {} coverage previous inputs

/-- The real indexed controller loads only the orders required by the current
pass. Persisted bytes supply advice, never Entry proofs: `addRanks` constructs
each exact current-domain certificate, even after a collision or corruption.
The reader retains positive and negative loads for this pinned request. -/
def prepareRanksFromM (reader : Option RankMemo.Reader) (prepared : RankMemo.Prepared)
    (coverage : Cache) (previous : RankMemo.Saved) (inputs : List Input) :
    IO RankMemo.Prepared := do
  let some reader := reader | return prepareRanksFrom prepared coverage previous inputs
  let mut prepared := prepared
  for input in inputs.reverse do
    let needsJoin := !LogicalText.isEmpty input.past && !LogicalText.isEmpty input.current &&
      input.pastWeights.length == input.past.units.length &&
      input.currentWeights.length == input.current.units.length &&
      input.past.units.map (·.text) != input.current.units.map (·.text)
    if (lookup coverage input).isSome || !needsJoin then continue
    let past := makePattern input.past
    let current := makePattern input.current
    prepared ← prepared.addM reader input.pastWeights past current
    prepared ← prepared.addM reader input.currentWeights current past
  return prepared

/-- Every IO outcome still inhabits the existing proof-carrying cache. This
contract covers arbitrary advice, not a premise that persisted hints are good. -/
theorem prepared_provider_exact (prepared : RankMemo.Prepared) :
    RankMemo.provider prepared.cache = referenceRank := RankMemo.provider_exact _

theorem prepareRanksFrom_bounded (prepared : RankMemo.Prepared) (coverage : Cache)
    (previous : RankMemo.Saved) (inputs : List Input) :
    (prepareRanksFrom prepared coverage previous inputs).charged ≤ RankMemo.allowance :=
  (prepareRanksFrom prepared coverage previous inputs).bounded

/-- Only candidates admitted to the demanded Work enter the rank cache.
Includes failed comparisons, so absence does not become a permanent miss. -/
def inputsPrepared (corpus : Corpus) (current : String)
    (semantic : SemanticNominations) (native : Bool)
    (prepared : CompiledDemand normalize current native) : List Input :=
  let demand := Value.text current
  let query := prepared.pattern
  let queryPatterns := prepared.workPatterns
  (admittedCandidates query corpus semantic).flatMap fun candidate =>
    (candidate.intrinsicPairs Quotient.literal demand query queryPatterns).map fun pair =>
      ⟨pair.past.logical, pair.current.logical,
        corpus.informationWeights pair.past candidate.native,
        corpus.informationWeights pair.current native, corpus.population + 1,
        pair.past.locator, pair.current.locator⟩

/-- Ranking inputs for the shallow Work lane, without an Outcome edge. -/
def inputsWork (corpus : Corpus) (work : WorkView) (current : String) (native : Bool)
    (prepared : CompiledDemand normalize current native) : List Input :=
  if !sharesSurface prepared.pattern work.pattern then [] else
    (work.intrinsicPairs Quotient.literal (.text current) prepared.pattern prepared.workPatterns).map fun pair =>
      ⟨pair.past.logical, pair.current.logical,
        corpus.informationWeights pair.past work.native,
        corpus.informationWeights pair.current native, corpus.population + 1,
        pair.past.locator, pair.current.locator⟩

theorem inputsWork_exact (corpus : Corpus) (candidate : Candidate) (current : String)
    (native : Bool) (prepared : CompiledDemand normalize current native) :
    inputsWork corpus candidate.workView current native prepared =
      inputsPrepared {corpus with candidates := [candidate]} current {} native prepared := by
  by_cases shared : sharesSurface prepared.pattern candidate.work
  <;> simp [inputsWork, inputsPrepared, admittedCandidates, nominated,
    SemanticNominations.contains, externallyNominated, Candidate.workView,
    Candidate.intrinsicPairs, shared, Corpus.informationWeights]
  intro pair _
  constructor <;> rfl

def inputs (normalize : Normalizer) (corpus : Corpus) (current : String)
    (semantic : SemanticNominations) (native : Bool) : List Input :=
  inputsPrepared corpus current semantic native (CompiledDemand.make normalize current native)

theorem changed_input_rejected (entry : Entry) (input : Input)
    (different : entry.input ≠ input) (cache : Cache) (found : cache[input.locator]? = some entry) :
    lookup cache input = none := by simp [lookup, found, different]

namespace Context

/-- Geometry depends on complete normalized bytes/spans in both directions,
including missing units. Frequency and population are score dependencies. -/
structure Input where
  query : LogicalText.T
  target : LogicalText.T
  queryLocator : UInt64
  targetLocator : UInt64
  deriving DecidableEq

def Input.locator (input : Input) : UInt64 × UInt64 :=
  (input.queryLocator, input.targetLocator)

def reference (input : Input) : ContextPlan.Instructions :=
  ContextPlan.generate input.query.units
    ((makePattern input.target).contextDirectory (makePattern input.query))

structure Entry where
  input : Input
  instructions : ContextPlan.Instructions
  exact : instructions = reference input

abbrev Cache := Std.HashMap (UInt64 × UInt64) Entry

def lookup (cache : Cache) (input : Input) : Option { plan : ContextPlan.Instructions // plan = reference input } := do
  let entry ← cache[input.locator]?
  if same : entry.input = input then pure ⟨entry.instructions, same ▸ entry.exact⟩
  else none

def provider (cache : Cache) : ContextProvider := fun query target weights novelty =>
  let input : Input := ⟨query.logical, target.logical, query.locator, target.locator⟩
  match lookup cache input with
  | none => surfaceContextCover query target weights novelty
  | some plan => surfaceContextCoverPlan plan.val query target weights novelty

theorem provider_exact (cache : Cache) : provider cache = surfaceContextCover := by
  funext query target weights novelty
  simp only [provider]
  split
  · rfl
  · rename_i plan _present
    apply surfaceContextCoverPlan_exact
    have exact := plan.property
    simpa only [reference, ← Pattern.canonical query, ← Pattern.canonical target] using exact

/-- Repair each demanded lookup once, retaining unchanged suffixes rather
than rejecting and regenerating the entire plan. Arbitrary corruption,
collisions or changed source geometry cannot supply a proof. -/
def obtain (saved : Option (List Nat)) (input : Input) : Entry × Bool :=
  let query := makePattern input.query
  let target := makePattern input.target
  let directory := target.contextDirectory query
  match saved.bind ContextPlan.decode with
  | some instructions =>
      let repaired := ContextPlan.repair query.logical.units directory instructions
      (⟨input, repaired.1, (ContextPlan.repair_exact _ _ _).1⟩, repaired.2)
  | none => (⟨input, ContextPlan.generate query.logical.units directory, rfl⟩, false)

structure Prepared where
  cache : Cache := {}
  saved : RankMemo.Saved := []
  charged : Nat := 0
  bounded : charged ≤ RankMemo.allowance := by decide
  reused : Nat := 0
  repaired : Nat := 0
  memoryReused : Nat := 0

/-- An operation's stable Work locator nominates advice after its Outcome
changes. It is never source identity or authority: the complete current
lookup sequence is repaired and certified before use. Locator collisions
can lose reuse, but cannot make a stale span escape the certifier. -/
def hintKey (query : Pattern) (operation : UInt64) : String :=
  toString query.locator ++ ":" ++ toString operation

/-- Same DB, same bounded slot reader and canonical payload wire as Work
orders. Only demanded plans are repaired; tiny queries stay on the direct lane.
No score, original body or unrelated request is serialized or refreshed. -/
def Prepared.addM (state : Prepared) (reader : Option (RankMemo.Reader .context))
    (query target : Pattern) (operation : UInt64 := target.locator) : IO Prepared := do
  let count := query.logical.units.length
  if count < 32 || count > RankMemo.frontierAllowance || LogicalText.isEmpty target.logical then
    return state
  let input : Input := ⟨query.logical, target.logical, query.locator, target.locator⟩
  if (lookup state.cache input).isSome then
    return {state with memoryReused := state.memoryReused + 1}
  let key := hintKey query operation
  let saved ← match reader with
    | none => pure none
    | some reader => pure ((← reader.get key).head?.map (·.2))
  let (entry, reused) := obtain saved input
  let state := {state with
    cache := state.cache.insert input.locator entry
    reused := state.reused + if reused then 1 else 0
    repaired := state.repaired + if reused then 0 else 1}
  if reader.isNone || state.saved.any (·.1 == key) then return state
  let retained := (key, ContextPlan.encode entry.instructions)
  let cost := RankMemo.codec.encodedSize [retained]
  if fits : state.charged + cost ≤ RankMemo.allowance then
    return {state with saved := retained :: state.saved, charged := state.charged + cost, bounded := fits}
  else return state

theorem changed_input_rejected (entry : Entry) (input : Input)
    (different : entry.input ≠ input) (cache : Cache) (found : cache[input.locator]? = some entry) :
    lookup cache input = none := by simp [lookup, found, different]

/-- Execute grounding once. Preparing a plan must not score forward context
again merely to decide whether a reverse calculation is required. -/
def groundPatternsM (normalize : Normalizer) (corpus : Corpus)
    (pastNative native : Bool) (evidence : Option String) (outcome query : Pattern)
    (reader : Option (RankMemo.Reader .context)) (initial : Prepared)
    (operation : UInt64 := outcome.locator) :
    IO ({ found : Option ContextAlignment // found =
      groundContextPatterns normalize corpus pastNative native evidence outcome query } × Prepared) := do
  let state ← initial.addM reader query outcome operation
  let forward := provider state.cache query outcome (corpus.informationWeights query native)
    (corpus.population + 1)
  have forwardExact : surfaceContextCover query outcome (corpus.informationWeights query native)
      (corpus.population + 1) = forward := by
    rw [← provider_exact state.cache]
  match present : forward with
  | some coverage =>
      return (⟨some {
        demandInOutcome := coverage
        outcomeFragment := materializeContext outcome.logical coverage.targetSpans pastNative
        alreadyVisible := false }, by
          simp only [groundContextPatterns, groundContextPatternsUsing, forwardExact, present]
          rfl⟩, state)
  | none =>
      match available : evidence with
      | none => return (⟨none, by
          simp only [groundContextPatterns, groundContextPatternsUsing, forwardExact, present, available]
          rfl⟩, state)
      | some value =>
          let pattern := makePattern (LogicalText.build normalize value)
          let state ← state.addM reader outcome pattern
          let reverse := provider state.cache outcome pattern (corpus.informationWeights outcome)
            (corpus.population + 1)
          have reverseExact : surfaceContextCover outcome pattern (corpus.informationWeights outcome)
              (corpus.population + 1) = reverse := by
            rw [← provider_exact state.cache]
          return (⟨reverse.map (fun coverage => { demandInOutcome := coverage, alreadyVisible := true }), by
            simp only [groundContextPatterns, groundContextPatternsUsing, forwardExact, present, available]
            change _ = (do
              let coverage ← surfaceContextCover outcome pattern (corpus.informationWeights outcome)
                (corpus.population + 1)
              pure ({demandInOutcome := coverage, alreadyVisible := true} : ContextAlignment))
            rw [reverseExact]
            cases reverse <;> rfl⟩, state)

def groundRowM (row : PreparedMatch normalize current text) (corpus : Corpus)
    (native : Bool) (evidence : Option String) (reader : Option (RankMemo.Reader .context))
    (initial : Prepared) : IO ({ found : Match // found = row.ground corpus native evidence } × Prepared) := do
  match outcomePresent : row.candidate.outcome, queryPresent : row.contextQuery with
  | some outcome, some query =>
      let (context, state) ← groundPatternsM normalize corpus row.candidate.native native evidence
        outcome query reader initial row.candidate.work.locator
      return (⟨{
        demand := current, edge := row.candidate.edge, work := row.work
        retrieved := row.retrieved, context := context.val }, by
          unfold PreparedMatch.ground PreparedMatch.groundUsing
          simp only [outcomePresent, queryPresent]
          congr 1
          exact context.property⟩, state)
  | _, _ => return (⟨row.ground corpus native evidence, rfl⟩, initial)

/-- Only the executed direction is prepared. Returned Matches retain the
complete old Matcher equality, including original fragments and both misses. -/
def groundM (rows : List (PreparedMatch normalize current text)) (corpus : Corpus)
    (native : Bool) (evidence : Option String) (reader : Option (RankMemo.Reader .context))
    (initial : Prepared) :
    IO ({ found : List Match // found = rows.map (fun row => row.ground corpus native evidence) } × Prepared) :=
  match rows with
  | [] => pure (⟨[], rfl⟩, initial)
  | row :: rest => do
      let (head, state) ← groundRowM row corpus native evidence reader initial
      let (tail, state) ← groundM rest corpus native evidence reader state
      return (⟨head.val :: tail.val, by
        simp only [List.map_cons, head.property, tail.property]⟩, state)

end Context

end Eggshell.Matcher.GeometryMemo
