module

public import Eggshell.LogicalText
public import Eggshell.Persistence
public import Eggshell.IncrementalQuotient
public import Eggshell.Frequency
public import Eggshell.TextParts

@[expose] public section

namespace Eggshell.Matcher

open Eggshell.LogicalText

def atomText? : Value → Option String
  | .atom bytes => String.fromUTF8? bytes
  | .apply _ _ => none

/--
A logical interval remembers both its exact normalized bytes and its unit
ordinals.  Match preparation therefore never rescans an Atom to rediscover the
same byte-to-unit correspondence.
-/
abbrev IndexedSpan := LogicalText.IndexedSpan

namespace IndexedSpan

def units (span : IndexedSpan) : List Nat :=
  (List.range (span.last - span.first)).map (span.first + ·)

end IndexedSpan

def indexedSpan? (logical : LogicalText.T) (span : ByteSpan) : Option IndexedSpan := do
  let ordinals := LogicalText.unitsIn logical span
  let first ← ordinals.head?
  let final ← ordinals.getLast?
  pure { span, first, last := final + 1 }

abbrev SurfaceIndex := LogicalText.SurfaceIndex
abbrev surfaceIndex := LogicalText.surfaceIndex
abbrev surfaceKeys := LogicalText.surfaceKeys

structure Pattern where
  /-- Keep the original text without normalizing an unused Outcome. Work and
  Context consumers force this one shared, canonical interpretation. -/
  logicalCache : Thunk LogicalText.T
  /-- Work anchors are built once, only when a Work join asks for them. -/
  surfaceCache : Thunk SurfaceIndex
  keysCache : Thunk (Std.HashSet String)
  /-- Outcome context asks only for exact single-unit occurrences. -/
  contextCache : Thunk SurfaceIndex
  /-- A locator for rebuildable memo entries, never semantic identity. -/
  locatorCache : Thunk UInt64
  surfaceExact : surfaceCache.get = surfaceIndex logicalCache.get
  keysExact : keysCache.get = surfaceKeys surfaceCache.get
  contextExact : contextCache.get = LogicalText.contextSurfaceIndex logicalCache.get
  locatorExact : locatorCache.get = hash logicalCache.get

def Pattern.logical (pattern : Pattern) : LogicalText.T := pattern.logicalCache.get
def Pattern.locator (pattern : Pattern) : UInt64 := pattern.locatorCache.get
def Pattern.surface (pattern : Pattern) : SurfaceIndex := pattern.surfaceCache.get
def Pattern.surfaces (pattern : Pattern) : Std.HashSet String := pattern.keysCache.get
def Pattern.contextSurface (pattern : Pattern) : SurfaceIndex := pattern.contextCache.get

def makePatternLazy (logical : Thunk LogicalText.T) : Pattern :=
  let surface := Thunk.mk fun _ => surfaceIndex logical.get
  {
    logicalCache := logical
    surfaceCache := surface
    keysCache := Thunk.mk fun _ => surfaceKeys surface.get
    contextCache := Thunk.mk fun _ => LogicalText.contextSurfaceIndex logical.get
    locatorCache := Thunk.mk fun _ => hash logical.get
    surfaceExact := rfl
    keysExact := rfl
    contextExact := rfl
    locatorExact := rfl
  }

def makePattern (logical : LogicalText.T) : Pattern :=
  makePatternLazy (.pure logical)

theorem Pattern.canonical (pattern : Pattern) : pattern = makePattern pattern.logical := by
  cases pattern with
  | mk logical surface surfaces context locator surfaceExact keysExact contextExact locatorExact =>
    have logicalValue : logical = Thunk.pure logical.get := Thunk.ext rfl
    have surfaceValue : surface = Thunk.mk (fun _ => surfaceIndex logical.get) :=
      Thunk.ext surfaceExact
    have keysValue : surfaces = Thunk.mk (fun _ => surfaceKeys (surfaceIndex logical.get)) :=
      Thunk.ext (keysExact.trans (congrArg surfaceKeys surfaceExact))
    have contextValue : context = Thunk.mk (fun _ => LogicalText.contextSurfaceIndex logical.get) :=
      Thunk.ext contextExact
    have locatorValue : locator = Thunk.mk (fun _ => hash logical.get) :=
      Thunk.ext locatorExact
    simp only [makePattern, makePatternLazy, Pattern.logical]
    congr 1

theorem Pattern.contextSurface_exact (pattern : Pattern) (key : String) :
    pattern.contextSurface.getD key [] =
      (pattern.surface.getD key []).filter LogicalText.singleUnit := by
  rw [Pattern.contextSurface, pattern.contextExact, Pattern.surface, pattern.surfaceExact]
  exact LogicalText.contextSurfaceIndex_exact pattern.logical key

def compile (normalize : Normalizer) (text : String) : Pattern :=
  makePatternLazy (Thunk.mk fun _ => LogicalText.build normalize text)

/-- Laziness changes evaluation time only. Every Pattern field, including
ordered anchors, normalized/source positions and the locator, is the same
as the complete eager compiler for any normalizer and original text. -/
theorem compile_eager_exact (normalize : Normalizer) (text : String) :
    compile normalize text = makePattern (LogicalText.build normalize text) :=
  Pattern.canonical (compile normalize text)

/-!
Native Work remains one persistent Atom and one Outcome owner.  The matcher
uses this private, rebuildable shell view only to prevent evidence from two
independent clauses being combined into a fragment that never occurred.
-/

inductive ShellQuote where
  | plain
  | single
  | double
  deriving Repr, DecidableEq

structure ShellSplit where
  quote : ShellQuote := .plain
  escaped : Bool := false
  parentheses : Nat := 0
  braces : Nat := 0
  current : List Char := []
  clauses : List String := []

namespace ShellSplit

def append (state : ShellSplit) (character : Char) : ShellSplit :=
  { state with current := character :: state.current }

def close (state : ShellSplit) : ShellSplit :=
  let clause := String.ofList state.current.reverse |>.trimAscii.copy
  if clause.isEmpty then { state with current := [] }
  else { state with current := [], clauses := clause :: state.clauses }

def topLevel (state : ShellSplit) : Bool :=
  state.quote = .plain && state.parentheses = 0 && state.braces = 0

end ShellSplit

def shellControlProgram (command : String) : Bool :=
  let text := command.trimAscii
  ["for ", "while ", "until ", "if ", "case ", "select ", "function "].any
      (fun marker => text.startsWith marker) ||
    ["; do", "; then", "; done", "; fi", "; esac"].any fun marker =>
      text.contains marker

/--
Split only unconditional top-level shell sequencing.  Quoted separators,
substitutions, pipelines, conditional `||`, and control programs stay atomic.
-/
def shellClauses (command : String) : List String :=
  if shellControlProgram command then [command.trimAscii.copy]
  else
    let rec scan (characters : List Char) (state : ShellSplit) : ShellSplit :=
      match characters with
      | [] => state.close
      | character :: tail =>
          if state.escaped then
            scan tail { (state.append character) with escaped := false }
          else match state.quote with
          | .single =>
              let state := state.append character
              scan tail (if character = '\'' then { state with quote := .plain } else state)
          | .double =>
              let state := state.append character
              if character = '\\' then scan tail { state with escaped := true }
              else scan tail (if character = '"' then { state with quote := .plain } else state)
          | .plain =>
              if character = '\\' then
                scan tail { (state.append character) with escaped := true }
              else if character = '\'' then
                scan tail { (state.append character) with quote := .single }
              else if character = '"' then
                scan tail { (state.append character) with quote := .double }
              else if character = '(' then
                scan tail { (state.append character) with
                  parentheses := state.parentheses + 1 }
              else if character = ')' then
                scan tail { (state.append character) with
                  parentheses := state.parentheses - 1 }
              else if character = '{' then
                scan tail { (state.append character) with braces := state.braces + 1 }
              else if character = '}' then
                scan tail { (state.append character) with braces := state.braces - 1 }
              else if state.topLevel && (character = ';' || character = '\n') then
                scan tail state.close
              else if state.topLevel && character = '&' then
                scan tail state.close
              else scan tail (state.append character)
      termination_by characters.length
    let clauses := (scan command.toList {}).clauses.reverse
    if clauses.isEmpty then [command.trimAscii.copy] else clauses

theorem shellClauses_ne_nil (command : String) : shellClauses command ≠ [] := by
  simp only [shellClauses]
  split
  · simp
  · split <;> simp_all

def shellTool (name : String) : Bool :=
  let normalized := name.toLower
  normalized = "bash" || normalized = "shell"

/-- Extract the shell program from lossless canonical native input for matching only. -/
def shellCommand? (input : String) : Option String := do
  let json ← (Lean.Json.parse input).toOption
  let command ← (json.getObjVal? "command").toOption
  command.getStr?.toOption

/-- A match-only view of one canonical `tool\ninput` Work Atom. -/
def nativeWorkSurfaces (text : String) : List String :=
  match text.splitOn "\n" with
  | [] => [text]
  | tool :: input =>
      if shellTool tool then
        let encoded := "\n".intercalate input
        let command := (shellCommand? encoded).getD encoded
        (shellClauses command).map (tool ++ "\n" ++ ·)
      else [text]

theorem nativeWorkSurfaces_ne_nil (text : String) : nativeWorkSurfaces text ≠ [] := by
  cases parts : text.splitOn "\n" with
  | nil => simp [nativeWorkSurfaces, parts]
  | cons tool input =>
      simp only [nativeWorkSurfaces, parts]
      split
      · intro empty
        exact shellClauses_ne_nil
          ((shellCommand? ("\n".intercalate input)).getD ("\n".intercalate input))
          (List.map_eq_nil_iff.mp empty)
      · simp

structure WorkPattern where
  pattern : Pattern
  value : Value
  /-- True only when this pattern denotes the complete persistent Work owner. -/
  whole : Bool

def compileWorkPatterns (normalize : Normalizer)
    (text : String) (native : Bool) : List WorkPattern :=
  let owner : WorkPattern := {
    pattern := compile normalize text
    value := .text text
    whole := true
  }
  if !native then [owner]
  else
    match nativeWorkSurfaces text with
    | [surface] => [{
        pattern := compile normalize surface
        value := .text text
        whole := true
      }]
    | fragments => owner :: fragments.map fun fragment => {
        pattern := compile normalize fragment
        value := .text fragment
        whole := false
      }

structure CompiledDemand (normalize : Normalizer) (text : String) (native : Bool) where
  pattern : Pattern
  workPatterns : List WorkPattern
  patternExact : pattern = compile normalize text
  patternsExact : workPatterns = compileWorkPatterns normalize text native

def CompiledDemand.make (normalize : Normalizer) (text : String) (native : Bool) :
    CompiledDemand normalize text native :=
  ⟨compile normalize text, compileWorkPatterns normalize text native, rfl, rfl⟩

theorem CompiledDemand.canonical (demand : CompiledDemand normalize text native) :
    demand = CompiledDemand.make normalize text native := by
  cases demand with
  | mk pattern workPatterns patternExact patternsExact =>
    subst pattern
    subst workPatterns
    rfl

abbrev DemandProvider (normalize : Normalizer) :=
  (text : String) → (native : Bool) → CompiledDemand normalize text native

def demandProvider (normalize : Normalizer) (current : String) (native : Bool)
    (demand : CompiledDemand normalize current native) : DemandProvider normalize := fun text framed =>
  if same : text = current ∧ framed = native then
    ⟨demand.pattern, demand.workPatterns,
      by rw [same.1]; exact demand.patternExact,
      by rw [same.1, same.2]; exact demand.patternsExact⟩
  else CompiledDemand.make normalize text framed

theorem demandProvider_exact (normalize : Normalizer) (current : String) (native : Bool)
    (demand : CompiledDemand normalize current native) :
    demandProvider normalize current native demand = CompiledDemand.make normalize := by
  funext text framed
  exact CompiledDemand.canonical _

/-- Every rebuildable match view retains its complete authoritative Work owner. -/
theorem compileWorkPatterns_has_whole (normalize : Normalizer)
    (text : String) (native : Bool) :
    ∃ pattern ∈ compileWorkPatterns normalize text native,
      pattern.value = .text text ∧ pattern.whole = true := by
  simp only [compileWorkPatterns]
  split
  · simp
  · cases surfaces : nativeWorkSurfaces text with
    | nil => simp
    | cons first rest =>
        cases rest with
        | nil => simp
        | cons second rest => simp

/--
Whole native invocations are authoritative owners, not fragment search
domains.  Once an invocation has observable clause boundaries, comparisons
use those clauses only; otherwise an orderless match could combine a path from
one clause with a range or symbol from another and invent Work that never ran.
-/
def comparisonPatterns (patterns : List WorkPattern) : List WorkPattern :=
  let clauses := patterns.filter (!·.whole)
  if clauses.isEmpty then patterns else clauses

theorem comparisonPatterns_clause_only {patterns : List WorkPattern}
    (hasClause : (patterns.filter (!·.whole)).isEmpty = false)
    {pattern : WorkPattern} (member : pattern ∈ comparisonPatterns patterns) :
    pattern.whole = false := by
  simp only [comparisonPatterns, hasClause, Bool.false_eq_true, ↓reduceIte,
    List.mem_filter] at member
  simpa using member.2

structure Evidence where
  query : IndexedSpan
  target : IndexedSpan
  deriving Repr, DecidableEq, BEq, Hashable

/--
Every exact one-to-three-unit anchor remains evidence, but lookup is indexed
instead of comparing every query position with every target position.
-/
def surfaceEvidenceFromQuery (query target : Pattern) : List Evidence :=
  query.surface.fold (fun evidence gram spans =>
    spans.foldl (fun evidence querySpan =>
      (target.surface.getD gram []).foldl
          (fun evidence targetSpan =>
            { query := querySpan, target := targetSpan } :: evidence)
          evidence) evidence) []

def surfaceEvidenceFromTarget (query target : Pattern) : List Evidence :=
  target.surface.fold (fun evidence gram spans =>
    spans.foldl (fun evidence targetSpan =>
      (query.surface.getD gram []).foldl
          (fun evidence querySpan =>
            { query := querySpan, target := targetSpan } :: evidence)
          evidence) evidence) []

/-- The indexed join scans its smaller side; orientation of Evidence never changes. -/
def surfaceEvidence (query target : Pattern) : List Evidence :=
  if query.surface.size ≤ target.surface.size then
    surfaceEvidenceFromQuery query target
  else
    surfaceEvidenceFromTarget query target

def evidenceWeight (weights : Array Nat) (evidence : Evidence) : Nat :=
  evidence.query.units.foldl (fun total ordinal =>
    total + weights.getD ordinal 1) 0

def preferredEvidence (weights : Array Nat)
    (left right : Evidence) : Bool :=
  if evidenceWeight weights left != evidenceWeight weights right then
    evidenceWeight weights left > evidenceWeight weights right
  else if left.query.units.length != right.query.units.length then
    left.query.units.length > right.query.units.length
  else if left.target.units.length != right.target.units.length then
    left.target.units.length < right.target.units.length
  else if left.target.span.start != right.target.span.start then
    left.target.span.start < right.target.span.start
  else left.query.span.start < right.query.span.start

def rankedEvidence (weights : List Nat) (items : List Evidence) : List Evidence :=
  let weights := weights.toArray
  (items.toArray.mergeSort fun left right =>
    !preferredEvidence weights right left).toList

/-- Sorting evidence changes extraction cost only; it cannot invent or drop evidence. -/
theorem mem_rankedEvidence (weights : List Nat) (items : List Evidence)
    (item : Evidence) :
    item ∈ rankedEvidence weights items ↔ item ∈ items := by
  simp [rankedEvidence]

structure Coverage where
  coveredUnits : List Nat
  totalUnits : Nat
  coveredWeight : Nat
  totalWeight : Nat
  distinctiveAnchors : Nat
  querySpans : List ByteSpan
  targetSpans : List ByteSpan
  deriving Repr, DecidableEq

namespace Coverage

def complete (coverage : Coverage) : Bool :=
  coverage.totalUnits != 0 && coverage.coveredUnits.length = coverage.totalUnits

/--
Semantic completion is exact: every logical unit must occur in the current
Demand. Extraction cost never changes this judgment.
-/
theorem complete_iff_units (coverage : Coverage) :
    coverage.complete = true ↔
      coverage.totalUnits != 0 ∧
        coverage.coveredUnits.length = coverage.totalUnits := by
  simp [complete]

/--
Coverage magnitude is an extraction cost, not an admission threshold. A
natural-language overlap may be weak yet useful advisory work; only complete
forward coverage may erase a proposed operation.
-/
def compareScore (left right : Coverage) : Ordering :=
  compare (left.coveredWeight * right.totalWeight)
    (right.coveredWeight * left.totalWeight)

end Coverage

/-
An anchor identifies Work only when it is rare in the current Outcome corpus.
The criterion is relative rather than vocabulary-specific: a unit may occur in
at most one eighth of candidates, with one occurrence admitted in a small
corpus. Common repository roots and transport syntax therefore lose authority,
while symbols and natural-language terms retain it when they distinguish Work.
-/
def rareAnchor (noveltyCeiling weight : Nat) : Bool :=
  let candidateCount := noveltyCeiling - 1
  let documentFrequency := noveltyCeiling - weight
  documentFrequency ≤ Nat.max 1 (candidateCount / 8)

theorem rareAnchor_iff_frequency_bound (noveltyCeiling weight : Nat) :
    rareAnchor noveltyCeiling weight = true ↔
      noveltyCeiling - weight ≤ Nat.max 1 ((noveltyCeiling - 1) / 8) := by
  simp [rareAnchor]

def distinctiveAnchorCount (query : Pattern) (weights : List Nat)
    (noveltyCeiling : Nat) (covered : List Nat) : Nat :=
  let units := query.logical.units.toArray
  let frequencies := weights.toArray
  (hashDistinct (covered.filterMap fun ordinal =>
    if rareAnchor noveltyCeiling (frequencies.getD ordinal 0) then
      match units[ordinal]? with
      | some unit => if unit.text.isEmpty then none else some unit.text
      | none => none
    else none)).length

/-- Constant-time ordinal reads and hashed deduplication preserve every
original rarity decision, including duplicates and out-of-range positions. -/
theorem distinctiveAnchorCount_exact (query : Pattern) (weights : List Nat)
    (noveltyCeiling : Nat) (covered : List Nat) :
    distinctiveAnchorCount query weights noveltyCeiling covered =
      (covered.filterMap fun ordinal =>
        if rareAnchor noveltyCeiling (weights.getD ordinal 0) then
          match query.logical.units[ordinal]? with
          | some unit => if unit.text.isEmpty then none else some unit.text
          | none => none
        else none).eraseDups.length := by
  simp only [distinctiveAnchorCount, HashDistinct.reference, Array.getD_eq_getD_getElem?,
    List.getElem?_toArray, List.getD_eq_getElem?_getD]

def workSelectionStep (selected : List Evidence) (candidate : Evidence) : List Evidence :=
    let queryUsed := selected.flatMap (·.query.units)
    let targetUsed := selected.flatMap (·.target.units)
    if candidate.query.units.any queryUsed.contains ||
        candidate.target.units.any targetUsed.contains then selected
    else selected ++ [candidate]

def workSelection (ranked : List Evidence) : List Evidence := ranked.foldl workSelectionStep []

/-- Scoring and original span order are separate from greedy selection. -/
def coverageOf (query : Pattern) (weights : List Nat)
    (noveltyCeiling : Nat) (selected : List Evidence) : Option Coverage :=
  if selected.isEmpty then none else
  let workUnits := List.range query.logical.units.length
  let covered := selected.flatMap (·.query.units) |> hashDistinct
  let coveredWeight := covered.foldl (fun total ordinal =>
    total + weights.getD ordinal 1) 0
  let totalWeight := workUnits.foldl (fun total ordinal =>
    total + weights.getD ordinal 1) 0
  some {
    coveredUnits := covered
    totalUnits := workUnits.length
    coveredWeight
    totalWeight
    distinctiveAnchors := distinctiveAnchorCount query weights noveltyCeiling covered
    querySpans := selected.map (·.query.span) |> hashDistinct
    targetSpans := selected.map (·.target.span) |> hashDistinct
  }

def workCoverage (query : Pattern) (weights : List Nat)
    (noveltyCeiling : Nat) (ranked : List Evidence) : Option Coverage :=
  coverageOf query weights noveltyCeiling (workSelection ranked)

def sameLogicalUnits (left right : Pattern) : Bool :=
  left.logical.units.map (·.text) == right.logical.units.map (·.text)

def completeCoverage (pattern : Pattern) (weights : List Nat)
    (noveltyCeiling : Nat) : Coverage :=
  let covered := List.range pattern.logical.units.length
  {
    coveredUnits := covered
    totalUnits := covered.length
    coveredWeight := weights.foldl (· + ·) 0
    totalWeight := weights.foldl (· + ·) 0
    distinctiveAnchors := distinctiveAnchorCount pattern weights noveltyCeiling covered
    querySpans := pattern.logical.units.map (·.logical)
    targetSpans := pattern.logical.units.map (·.logical)
  }

abbrev RankProvider := List Nat → Pattern → Pattern → List Evidence

def referenceRank (weights : List Nat) (query target : Pattern) : List Evidence :=
  rankedEvidence weights (surfaceEvidence query target)

/-- Ranking weights may change while the structural join remains identical.
The evidence provider supplies the complete ordered join, including misses. -/
def pairedCoveragesUsing (rank : RankProvider) (query target : Pattern)
    (queryWeights targetWeights : List Nat) (noveltyCeiling : Nat) :
    List (Coverage × Coverage) :=
  if LogicalText.isEmpty query.logical || LogicalText.isEmpty target.logical ||
      queryWeights.length != query.logical.units.length ||
      targetWeights.length != target.logical.units.length then []
  else if sameLogicalUnits query target then
    [(completeCoverage query queryWeights noveltyCeiling,
      completeCoverage target targetWeights noveltyCeiling)]
  else
    let forward := rank queryWeights query target
    let reverse := rank targetWeights target query
    match workCoverage query queryWeights noveltyCeiling forward,
        workCoverage target targetWeights noveltyCeiling reverse with
    | some queryInTarget, some targetInQuery => [(queryInTarget, targetInQuery)]
    | _, _ => []

/-- Every aligned unit participates; no best-fragment shortcut closes it. -/
def pairedCoverages := pairedCoveragesUsing referenceRank

theorem pairedCoveragesUsing_exact (rank : RankProvider)
    (exact : rank = referenceRank) :
    pairedCoveragesUsing rank = pairedCoverages := by
  subst rank
  rfl

/-
Outcome text is fallible context, never equality authority.  Its coverage is
therefore the exact orderless multiset intersection of normalized units.  Each
target occurrence is consumed once, avoiding the quadratic Cartesian product
of repeated words in large native results while preserving concrete source
spans for the handoff.
-/
/-- The remaining map is updated once per consumed occurrence. -/
def consumeContext : List LogicalText.Unit → List Nat → Nat →
    SurfaceIndex → List Nat → Nat → List ByteSpan →
    List ByteSpan → (List Nat × Nat × List ByteSpan × List ByteSpan)
  | [], _, _, _, covered, coveredWeight, querySpans, targetSpans =>
      (covered.reverse, coveredWeight, querySpans.reverse, targetSpans.reverse)
  | _, [], _, _, covered, coveredWeight, querySpans, targetSpans =>
      (covered.reverse, coveredWeight, querySpans.reverse, targetSpans.reverse)
  | unit :: units, weight :: rest, ordinal, remaining, covered,
      coveredWeight, querySpans, targetSpans =>
      let occurrences := (remaining.getD unit.text []).filter LogicalText.singleUnit
      match occurrences with
      | [] => consumeContext units rest (ordinal + 1) remaining covered
          coveredWeight querySpans targetSpans
      | targetSpan :: tail =>
          consumeContext units rest (ordinal + 1) (remaining.insert unit.text tail)
            (ordinal :: covered) (coveredWeight + weight)
            (unit.logical :: querySpans) (targetSpan.span :: targetSpans)

/-- A unit-only context directory carries its invariant through every pop.
There is no runtime filtering or cached-body hash premise in this capability. -/
structure ContextDirectory where
  index : SurfaceIndex
  valid : ∀ key span, span ∈ index.getD key [] → LogicalText.singleUnit span = true

def ContextDirectory.insert (directory : ContextDirectory) (key : String)
    (items : List IndexedSpan) (valid : ∀ span ∈ items, LogicalText.singleUnit span = true) :
    ContextDirectory := ⟨directory.index.insert key items, by
      intro requested span present
      simp only [Std.HashMap.getD_insert] at present
      split at present
      · exact valid span present
      · exact directory.valid requested span present⟩

theorem ContextDirectory.filtered (directory : ContextDirectory) (key : String) :
    (directory.index.getD key []).filter LogicalText.singleUnit = directory.index.getD key [] :=
  List.filter_eq_self.mpr (fun span present => directory.valid key span present)

/-- The queue head is the next exact original occurrence. Advancing one word
retains the tail by reference; repeated words never scan all remaining spans. -/
def consumeUnitContext : List LogicalText.Unit → List Nat → Nat →
    ContextDirectory → List Nat → Nat → List ByteSpan →
    List ByteSpan → (List Nat × Nat × List ByteSpan × List ByteSpan)
  | [], _, _, _, covered, coveredWeight, querySpans, targetSpans =>
      (covered.reverse, coveredWeight, querySpans.reverse, targetSpans.reverse)
  | _, [], _, _, covered, coveredWeight, querySpans, targetSpans =>
      (covered.reverse, coveredWeight, querySpans.reverse, targetSpans.reverse)
  | unit :: units, weight :: rest, ordinal, remaining, covered,
      coveredWeight, querySpans, targetSpans =>
      match occurrences : remaining.index.getD unit.text [] with
      | [] => consumeUnitContext units rest (ordinal + 1) remaining covered
          coveredWeight querySpans targetSpans
      | targetSpan :: tail =>
          let next := remaining.insert unit.text tail (fun span present =>
            remaining.valid unit.text span (by
              rw [occurrences]; exact List.mem_cons_of_mem targetSpan present))
          consumeUnitContext units rest (ordinal + 1) next
            (ordinal :: covered) (coveredWeight + weight)
            (unit.logical :: querySpans) (targetSpan.span :: targetSpans)

/-- Full operational refinement, including exhausted queues, repeated and
absent words, invalid weight lengths, both span lists and accumulated scores. -/
theorem consumeUnitContext_exact (units : List LogicalText.Unit) (weights : List Nat)
    (ordinal : Nat) (remaining : ContextDirectory) (covered : List Nat)
    (coveredWeight : Nat) (querySpans targetSpans : List ByteSpan) :
    consumeUnitContext units weights ordinal remaining covered coveredWeight querySpans targetSpans =
      consumeContext units weights ordinal remaining.index covered coveredWeight querySpans targetSpans := by
  induction units generalizing weights ordinal remaining covered coveredWeight querySpans targetSpans with
  | nil => rfl
  | cons unit units ih =>
      cases weights with
      | nil => rfl
      | cons weight rest =>
          simp only [consumeUnitContext, consumeContext, remaining.filtered unit.text]
          split
          · rename_i occurrences
            conv => rhs; rw [occurrences]
            exact ih rest (ordinal + 1) remaining covered coveredWeight querySpans targetSpans
          · rename_i span tail occurrences
            conv => rhs; rw [occurrences]
            exact ih rest (ordinal + 1) _ (ordinal :: covered) (coveredWeight + weight)
              (unit.logical :: querySpans) (span.span :: targetSpans)

namespace ContextPlan

/-- Geometry alone: one instruction per queried unit, including every
negative lookup. Frequency and population never enter this durable plan. -/
abbrev Instructions := List (Option ByteSpan)

def generate : List LogicalText.Unit → ContextDirectory → Instructions
  | [], _ => []
  | unit :: units, remaining =>
      match occurrences : remaining.index.getD unit.text [] with
      | [] => none :: generate units remaining
      | span :: tail =>
          some span.span :: generate units (remaining.insert unit.text tail
            (fun next present => remaining.valid unit.text next (by
              rw [occurrences]; exact List.mem_cons_of_mem span present)))

/-- Check the complete current multiset, not just the old positive matches.
New matches, missing occurrences, changed spans and trailing instructions all
invalidate the hint. Accepted geometry is scored with today's weights. -/
def check : List LogicalText.Unit → ContextDirectory → Instructions → Bool
  | [], _, instructions => instructions.isEmpty
  | _ :: _, _, [] => false
  | unit :: units, remaining, instruction :: rest =>
      match occurrences : remaining.index.getD unit.text [] with
      | [] => decide (instruction = none) && check units remaining rest
      | span :: tail =>
          decide (instruction = some span.span) && check units
            (remaining.insert unit.text tail (fun next present =>
              remaining.valid unit.text next (by
                rw [occurrences]; exact List.mem_cons_of_mem span present))) rest

theorem check_exact (units : List LogicalText.Unit) (remaining : ContextDirectory)
    (instructions : Instructions) (accepted : check units remaining instructions = true) :
    instructions = generate units remaining := by
  induction units generalizing remaining instructions with
  | nil => cases instructions <;> simp_all [check, generate]
  | cons unit units ih =>
      cases instructions with
      | nil => simp [check] at accepted
      | cons instruction rest =>
          simp only [check] at accepted
          split at accepted
          · rename_i occurrences
            have facts := Bool.and_eq_true_iff.mp accepted
            have first := of_decide_eq_true facts.1
            have tail := ih remaining rest facts.2
            simp only [generate]
            rw [first, tail]
            split <;> simp_all
          · rename_i span tail occurrences
            have facts := Bool.and_eq_true_iff.mp accepted
            have first := of_decide_eq_true facts.1
            have later := ih _ rest facts.2
            simp only [generate]
            rw [first, later]
            split
            · rename_i other
              rw [occurrences] at other
              cases other
            · rename_i next later other
              have same := List.cons.inj (occurrences.symm.trans other)
              rcases same with ⟨rfl, rfl⟩
              rfl

theorem check_generate (units : List LogicalText.Unit) (remaining : ContextDirectory) :
    check units remaining (generate units remaining) = true := by
  induction units generalizing remaining with
  | nil => rfl
  | cons unit units ih =>
      simp only [generate]
      split
      · rename_i occurrences
        simp only [check]
        split
        · simpa using ih remaining
        · rename_i span tail other
          rw [occurrences] at other
          cases other
      · rename_i span tail occurrences
        simp only [check]
        split
        · rename_i other
          rw [occurrences] at other
          cases other
        · rename_i next later other
          have same := List.cons.inj (occurrences.symm.trans other)
          rcases same with ⟨rfl, rfl⟩
          simpa using ih _

/-- Keep the old list cell only when both this instruction and the complete
suffix still agree. A changed prefix shares its unchanged suffix; no failed
whole-plan check is followed by a second directory traversal. -/
def repairHead (instruction : Option ByteSpan) (saved : Instructions)
    (next : Instructions × Bool) : Instructions × Bool :=
  match saved with
  | [] => (instruction :: next.1, false)
  | prior :: _ =>
      if prior = instruction ∧ next.2 = true then (saved, true)
      else (instruction :: next.1, false)

private theorem repairHead_exact (instruction : Option ByteSpan) (saved : Instructions)
    (next : Instructions × Bool) (expected : Instructions)
    (tailExact : next.1 = expected)
    (tailSame : next.2 = true ↔ saved.tail = expected) :
    (repairHead instruction saved next).1 = instruction :: expected ∧
      ((repairHead instruction saved next).2 = true ↔ saved = instruction :: expected) := by
  cases saved with
  | nil => simp [repairHead, tailExact]
  | cons prior rest =>
      simp only [List.tail_cons] at tailSame
      by_cases same : prior = instruction ∧ next.2 = true
      · obtain ⟨rfl, reused⟩ := same
        have tail := tailSame.mp reused
        simp [repairHead, reused, tail]
      · have different : ¬ (prior = instruction ∧ rest = expected) := by
          intro equal
          exact same ⟨equal.1, tailSame.mpr equal.2⟩
        simp [repairHead, same, tailExact, List.cons.injEq, different]

/-- Repair every demanded lookup once, including old misses, new matches,
deleted occurrences and shifted spans. Saved positions are advice only.
The Boolean reports complete reuse, not completion of a partial answer. -/
def repair : List LogicalText.Unit → ContextDirectory → Instructions → Instructions × Bool
  | [], _, saved => ([], saved.isEmpty)
  | unit :: units, remaining, saved =>
      match occurrences : remaining.index.getD unit.text [] with
      | [] => repairHead none saved (repair units remaining saved.tail)
      | span :: tail =>
          let next := remaining.insert unit.text tail (fun item present =>
            remaining.valid unit.text item (by
              rw [occurrences]; exact List.mem_cons_of_mem span present))
          repairHead (some span.span) saved (repair units next saved.tail)

/-- The executing repair produces exactly the complete original plan for
arbitrary persisted bytes after decoding. No unchanged-source or hash premise
is used. Its reuse flag is true exactly when the entire old plan still agrees. -/
theorem repair_exact (units : List LogicalText.Unit) (remaining : ContextDirectory)
    (saved : Instructions) :
    (repair units remaining saved).1 = generate units remaining ∧
      ((repair units remaining saved).2 = true ↔ saved = generate units remaining) := by
  induction units generalizing remaining saved with
  | nil => cases saved <;> simp [repair, generate]
  | cons unit units ih =>
      simp only [repair, generate]
      split
      · exact repairHead_exact none saved _ _ (ih remaining saved.tail).1
          (ih remaining saved.tail).2
      · exact repairHead_exact _ saved _ _ (ih _ saved.tail).1 (ih _ saved.tail).2

def score : List LogicalText.Unit → List Nat → Nat → Instructions →
    List Nat → Nat → List ByteSpan → List ByteSpan →
    (List Nat × Nat × List ByteSpan × List ByteSpan)
  | [], _, _, _, covered, weight, querySpans, targetSpans =>
      (covered.reverse, weight, querySpans.reverse, targetSpans.reverse)
  | _, [], _, _, covered, weight, querySpans, targetSpans =>
      (covered.reverse, weight, querySpans.reverse, targetSpans.reverse)
  | _, _, _, [], covered, weight, querySpans, targetSpans =>
      (covered.reverse, weight, querySpans.reverse, targetSpans.reverse)
  | unit :: units, weight :: weights, ordinal, instruction :: rest,
      covered, coveredWeight, querySpans, targetSpans =>
      match instruction with
      | none => score units weights (ordinal + 1) rest covered coveredWeight querySpans targetSpans
      | some span => score units weights (ordinal + 1) rest (ordinal :: covered)
          (coveredWeight + weight) (unit.logical :: querySpans) (span :: targetSpans)

/-- The executing score interpreter refines the former weighted consumer for
arbitrary weights, short lists, accumulated state and source normalizers. -/
theorem score_generate_exact (units : List LogicalText.Unit) (weights : List Nat)
    (ordinal : Nat) (remaining : ContextDirectory) (covered : List Nat)
    (weight : Nat) (querySpans targetSpans : List ByteSpan) :
    score units weights ordinal (generate units remaining) covered weight querySpans targetSpans =
      consumeUnitContext units weights ordinal remaining covered weight querySpans targetSpans := by
  induction units generalizing weights ordinal remaining covered weight querySpans targetSpans with
  | nil => rfl
  | cons unit units ih =>
      cases weights with
      | nil => rfl
      | cons first rest =>
          simp only [generate, consumeUnitContext]
          split
          · rename_i occurrences
            simp only [score]
            exact ih rest (ordinal + 1) remaining covered weight querySpans targetSpans
          · rename_i span tail occurrences
            simp only [score]
            exact ih rest (ordinal + 1) _ (ordinal :: covered) (weight + first)
              (unit.logical :: querySpans) (span.span :: targetSpans)

/-- Compact canonical position wire representation; no owner body or score
is copied. Zero is a negative lookup, successor/start plus stop is a span. -/
def encode : Instructions → List Nat
  | [] => []
  | none :: rest => 0 :: encode rest
  | some span :: rest => (span.start + 1) :: span.stop :: encode rest

def decode : List Nat → Option Instructions
  | [] => some []
  | 0 :: rest => (none :: ·) <$> decode rest
  | (start + 1) :: stop :: rest => (some ⟨start, stop⟩ :: ·) <$> decode rest
  | _ :: [] => none

theorem decode_encode (instructions : Instructions) :
    decode (encode instructions) = some instructions := by
  induction instructions with
  | nil => rfl
  | cons instruction rest ih =>
      cases instruction with
      | none => simp [encode, decode, ih]
      | some span => cases span; simp [encode, decode, ih]

end ContextPlan

def ContextEquivalent (left right : SurfaceIndex) : Prop :=
  ∀ key, (left.getD key []).filter LogicalText.singleUnit =
    (right.getD key []).filter LogicalText.singleUnit

theorem ContextEquivalent.insert {left right : SurfaceIndex}
    (same : ContextEquivalent left right) (key : String) (items : List IndexedSpan) :
    ContextEquivalent (left.insert key items) (right.insert key items) := by
  intro query
  simp only [Std.HashMap.getD_insert]
  split
  · rfl
  · exact same query

theorem consumeContext_congr (units : List LogicalText.Unit) (weights : List Nat)
    (ordinal : Nat) (covered : List Nat) (coveredWeight : Nat)
    (querySpans targetSpans : List ByteSpan) {left right : SurfaceIndex}
    (same : ContextEquivalent left right) :
    consumeContext units weights ordinal left covered coveredWeight querySpans targetSpans =
      consumeContext units weights ordinal right covered coveredWeight querySpans targetSpans := by
  induction units generalizing weights ordinal left right covered coveredWeight querySpans targetSpans with
  | nil => rfl
  | cons unit units ih =>
    cases weights with
    | nil => rfl
    | cons weight rest =>
      simp only [consumeContext]
      rw [same unit.text]
      cases occurrences : (right.getD unit.text []).filter LogicalText.singleUnit with
      | nil => exact ih rest (ordinal + 1) covered coveredWeight querySpans targetSpans same
      | cons span tail =>
        exact ih rest (ordinal + 1) (ordinal :: covered) (coveredWeight + weight)
          (unit.logical :: querySpans) (span.span :: targetSpans) (same.insert unit.text tail)

/-- Grounding observes only keys present in the current query, including
negative lookups. Unrelated units are not context dependencies. The exact
occurrence list/order, rather than a positive-hit subset, remains required. -/
theorem consumeContext_requested_congr (units : List LogicalText.Unit) (weights : List Nat)
    (ordinal : Nat) (covered : List Nat) (coveredWeight : Nat)
    (querySpans targetSpans : List ByteSpan) {left right : SurfaceIndex}
    (same : ∀ unit ∈ units, (left.getD unit.text []).filter LogicalText.singleUnit =
      (right.getD unit.text []).filter LogicalText.singleUnit) :
    consumeContext units weights ordinal left covered coveredWeight querySpans targetSpans =
      consumeContext units weights ordinal right covered coveredWeight querySpans targetSpans := by
  induction units generalizing weights ordinal left right covered coveredWeight querySpans targetSpans with
  | nil => rfl
  | cons unit units ih =>
      cases weights with
      | nil => rfl
      | cons weight rest =>
          simp only [consumeContext]
          rw [same unit (by simp)]
          cases occurrences : (right.getD unit.text []).filter LogicalText.singleUnit with
          | nil =>
              exact ih rest (ordinal + 1) covered coveredWeight querySpans targetSpans
                (fun next member => same next (by simp [member]))
          | cons span tail =>
              apply ih rest (ordinal + 1) (ordinal :: covered) (coveredWeight + weight)
                (unit.logical :: querySpans) (span.span :: targetSpans)
              intro next member
              simp only [Std.HashMap.getD_insert]
              split
              · rfl
              · exact same next (by simp [member])

def Pattern.contextDemand (target query : Pattern) : SurfaceIndex :=
  LogicalText.contextDemandIndex target.logical
    (Std.HashSet.ofList (query.logical.units.map (·.text)))

theorem Pattern.contextDemand_exact (target query : Pattern) (unit : LogicalText.Unit)
    (requested : unit ∈ query.logical.units) :
    (target.contextDemand query).getD unit.text [] = target.contextSurface.getD unit.text [] := by
  unfold contextDemand Pattern.contextSurface
  rw [target.contextExact]
  apply LogicalText.contextDemandIndex_exact
  simp only [Std.HashSet.contains_ofList, List.contains_iff_mem]
  exact List.mem_map.mpr ⟨unit, requested, rfl⟩

def surfaceContextCoverWith (initial : SurfaceIndex) (query target : Pattern)
    (weights : List Nat) (noveltyCeiling : Nat) : Option Coverage :=
  if LogicalText.isEmpty query.logical || LogicalText.isEmpty target.logical ||
      weights.length != query.logical.units.length then none
  else
    let (covered, coveredWeight, querySpans, targetSpans) :=
      consumeContext query.logical.units weights 0 initial [] 0 [] []
    if covered.isEmpty then none else
      some {
        coveredUnits := covered
        totalUnits := query.logical.units.length
        coveredWeight
        totalWeight := weights.foldl (· + ·) 0
        distinctiveAnchors :=
          distinctiveAnchorCount query weights noveltyCeiling covered
        querySpans
        targetSpans
      }

def Pattern.contextDirectory (target query : Pattern) : ContextDirectory :=
  ⟨target.contextDemand query, by
    intro key span present
    exact LogicalText.contextDemandIndex_single target.logical _ key span present⟩

def surfaceContextCoverUnits (initial : ContextDirectory) (query target : Pattern)
    (weights : List Nat) (noveltyCeiling : Nat) : Option Coverage :=
  if LogicalText.isEmpty query.logical || LogicalText.isEmpty target.logical ||
      weights.length != query.logical.units.length then none
  else
    let (covered, coveredWeight, querySpans, targetSpans) :=
      consumeUnitContext query.logical.units weights 0 initial [] 0 [] []
    if covered.isEmpty then none else
      some {
        coveredUnits := covered
        totalUnits := query.logical.units.length
        coveredWeight
        totalWeight := weights.foldl (· + ·) 0
        distinctiveAnchors := distinctiveAnchorCount query weights noveltyCeiling covered
        querySpans
        targetSpans
      }

theorem surfaceContextCoverUnits_exact (initial : ContextDirectory) (query target : Pattern)
    (weights : List Nat) (noveltyCeiling : Nat) :
    surfaceContextCoverUnits initial query target weights noveltyCeiling =
      surfaceContextCoverWith initial.index query target weights noveltyCeiling := by
  simp only [surfaceContextCoverUnits, surfaceContextCoverWith, consumeUnitContext_exact]

def surfaceContextCover (query target : Pattern)
    (weights : List Nat) (noveltyCeiling : Nat) : Option Coverage :=
  surfaceContextCoverUnits (target.contextDirectory query) query target weights noveltyCeiling

/-- A checked geometric plan can be reused under arbitrary frequency and
population changes. Scores and the original spans are always reconstructed. -/
def surfaceContextCoverPlan (instructions : ContextPlan.Instructions) (query target : Pattern)
    (weights : List Nat) (noveltyCeiling : Nat) : Option Coverage :=
  if LogicalText.isEmpty query.logical || LogicalText.isEmpty target.logical ||
      weights.length != query.logical.units.length then none
  else
    let (covered, coveredWeight, querySpans, targetSpans) :=
      ContextPlan.score query.logical.units weights 0 instructions [] 0 [] []
    if covered.isEmpty then none else some {
      coveredUnits := covered
      totalUnits := query.logical.units.length
      coveredWeight
      totalWeight := weights.foldl (· + ·) 0
      distinctiveAnchors := distinctiveAnchorCount query weights noveltyCeiling covered
      querySpans, targetSpans }

theorem surfaceContextCoverPlan_exact (query target : Pattern)
    (instructions : ContextPlan.Instructions)
    (exact : instructions = ContextPlan.generate query.logical.units (target.contextDirectory query))
    (weights : List Nat) (noveltyCeiling : Nat) :
    surfaceContextCoverPlan instructions query target weights noveltyCeiling =
      surfaceContextCover query target weights noveltyCeiling := by
  subst instructions
  simp only [surfaceContextCoverPlan, surfaceContextCover, surfaceContextCoverUnits,
    ContextPlan.score_generate_exact]

abbrev ContextProvider := Pattern → Pattern → List Nat → Nat → Option Coverage

/-- The actual demand directory is observationally identical to the former
full unit directory for every query, weight list, population and source. -/
theorem surfaceContextCover_demand_exact (query target : Pattern)
    (weights : List Nat) (noveltyCeiling : Nat) :
    surfaceContextCover query target weights noveltyCeiling =
      surfaceContextCoverWith target.contextSurface query target weights noveltyCeiling := by
  unfold surfaceContextCover
  rw [surfaceContextCoverUnits_exact]
  change surfaceContextCoverWith (target.contextDemand query) query target weights noveltyCeiling = _
  unfold surfaceContextCoverWith
  rw [consumeContext_requested_congr query.logical.units weights 0 [] 0 [] []
    (left := target.contextDemand query) (right := target.contextSurface)
    (fun unit present => by rw [target.contextDemand_exact query unit present])]

/-- Entire coverage agrees with the eager full-gram interpreter. This includes
occurrence multiplicity/order, both span lists, weights, rarity and rejection. -/
theorem surfaceContextCover_exact (query target : Pattern)
    (weights : List Nat) (noveltyCeiling : Nat) :
    surfaceContextCover query target weights noveltyCeiling =
      surfaceContextCoverWith target.surface query target weights noveltyCeiling := by
  have same : ContextEquivalent target.contextSurface target.surface := by
    intro key
    rw [target.contextSurface_exact]
    simp only [List.filter_filter, Bool.and_self]
  rw [surfaceContextCover_demand_exact]
  unfold surfaceContextCoverWith
  rw [consumeContext_congr query.logical.units weights 0 [] 0 [] [] same]

def fragmentJudgment (priorInDemand demandInPrior : Coverage)
    (sameFragment subwork pastWholeWork groundedFragment : Bool) :
    ApplicabilityJudgment :=
  /-
  Local equality and applicability are separate. A whole historical Work may
  control the current plan only when it is wholly contained in the Demand. A
  smaller run-local fragment may control only that same fragment when actual
  result bytes ground it. The fragment need not equal the larger invocation
  that carried it; the unmatched Demand remains open. Ungrounded overlap stays
  advisory.
  -/
  let reusable := sameFragment && subwork &&
    ((pastWholeWork && priorInDemand.complete) ||
      (groundedFragment &&
        (priorInDemand.complete || demandInPrior.complete)))
  let direction := if reusable then .pastWorkInsideCurrentDemand
    else if priorInDemand.complete then .pastWorkInsideCurrentDemand
    else if demandInPrior.complete then .currentDemandInsidePastWork
    else .overlapping
  { direction, reusableOutcome := reusable }

/-- Completion requires local identity and one complete, observed positive subwork. -/
theorem fragment_completion_requires_local_identity
    (priorInDemand demandInPrior : Coverage)
    (sameFragment subwork pastWholeWork groundedFragment : Bool)
    (completed : (fragmentJudgment priorInDemand demandInPrior
      sameFragment subwork pastWholeWork groundedFragment).delivery = .completed) :
    sameFragment = true ∧ subwork = true ∧
      ((pastWholeWork = true ∧ priorInDemand.complete = true) ∨
        (groundedFragment = true ∧
          (priorInDemand.complete = true ∨ demandInPrior.complete = true))) := by
  have reusable := ApplicabilityJudgment.completed_only_for_forward_reusable completed |>.2
  simp only [fragmentJudgment, Bool.and_eq_true, Bool.or_eq_true] at reusable
  exact ⟨reusable.1.1, reusable.1.2, reusable.2⟩

/-- Equality may reconnect a parent turn, but only an All child may erase Work. -/
theorem parent_turn_never_completes
    (priorInDemand demandInPrior : Coverage)
    (sameFragment pastWholeWork groundedFragment : Bool) :
    (fragmentJudgment priorInDemand demandInPrior sameFragment false
      pastWholeWork groundedFragment).delivery =
      .advisory := by
  simp [fragmentJudgment, ApplicabilityJudgment.delivery]

structure WorkAlignment where
  priorInDemand : Coverage
  demandInPrior : Coverage
  /-- True exactly when the Outcome owner occupies an All-child position. -/
  subwork : Bool
  /-- A match-only clause may reconnect its owner, but cannot complete that owner. -/
  pastWholeWork : Bool
  /-- The whole current and historical Work already share one active equivalence class. -/
  wholeWorkIdentity : Bool
  /-- The selected fragments share one active run-local equivalence class. -/
  fragmentIdentity : Bool
  currentFragment : Value
  pastFragment : Value
  currentSpan : ByteSpan
  pastSpan : ByteSpan

/--
Equality and context have different witnesses.  A child Operation is grounded
by the fragment currently being proposed; a parent Turn only nominates a prior
subtree, so its Outcome is grounded against the whole current Demand.
-/
def WorkAlignment.contextDemand (aligned : WorkAlignment) (current : Value) : Value :=
  if aligned.subwork then aligned.currentFragment else current

theorem WorkAlignment.parent_contextDemand {aligned : WorkAlignment} {current : Value}
    (parent : aligned.subwork = false) :
    aligned.contextDemand current = current := by
  simp [WorkAlignment.contextDemand, parent]

theorem WorkAlignment.subwork_contextDemand {aligned : WorkAlignment} {current : Value}
    (subwork : aligned.subwork = true) :
    aligned.contextDemand current = aligned.currentFragment := by
  simp [WorkAlignment.contextDemand, subwork]

/-- Outcome text may satisfy a Demand fragment, but never establishes Work identity. -/
structure ContextAlignment where
  demandInOutcome : Coverage
  /-- Exact source lines carrying the matched Outcome evidence, never new authority. -/
  outcomeFragment : Option Value := none
  alreadyVisible : Bool := false

/-- One Outcome owner with independent Work-identity and positive-result lanes. -/
structure Match where
  demand : Value
  edge : OutcomeEdge
  work : WorkAlignment
  context : Option ContextAlignment := none
  /-- External relatedness is deliverable context, never equality authority. -/
  retrieved : Bool := false

namespace Match

def groundedContext (matched : Match) : Bool :=
  matched.context.any fun context =>
    context.demandInOutcome.coveredWeight != 0

/-- Historical Outcome bytes may ground advice; bytes from the current result may not. -/
def transportGroundedContext (matched : Match) : Bool :=
  matched.context.any fun context =>
    !context.alreadyVisible && context.demandInOutcome.coveredWeight != 0

theorem transportGroundedContext_is_grounded {matched : Match}
    (transported : matched.transportGroundedContext = true) :
    matched.groundedContext = true := by
  cases context : matched.context with
  | none => simp [transportGroundedContext, context] at transported
  | some value =>
      simp [transportGroundedContext, groundedContext, context] at transported ⊢
      exact transported.2

/-- A native fragment is grounded only by result bytes projected from its owner. -/
def groundedOutcomeFragment (matched : Match) : Bool :=
  matched.context.any fun context =>
    context.demandInOutcome.coveredWeight != 0 &&
      context.outcomeFragment.isSome

def workJudgment (matched : Match) : ApplicabilityJudgment :=
  fragmentJudgment matched.work.priorInDemand matched.work.demandInPrior
    matched.work.fragmentIdentity matched.work.subwork matched.work.pastWholeWork
    matched.groundedOutcomeFragment

def judgment (matched : Match) : ApplicabilityJudgment :=
  if matched.retrieved then
    { direction := .overlapping, reusableOutcome := false }
  else matched.workJudgment

def applicability (matched : Match) : Applicability :=
  if matched.judgment.delivery = .completed then .completed
  else .advisory

def projectionWork (matched : Match) : Value :=
  /-
  A child Outcome may satisfy one demanded fragment. A parent Turn is advisory
  for the current Demand; making the whole parent an All-child would incorrectly
  demand every unrelated historical sibling. The original owner remains Exact
  provenance on the projected Outcome.
  -/
  if matched.work.subwork then matched.work.currentFragment else matched.demand

theorem parent_projection_keeps_current_demand {matched : Match}
    (parent : matched.work.subwork = false) :
    matched.projectionWork = matched.demand := by
  simp [projectionWork, parent]

def projectionOutcome (matched : Match) : Value :=
  /-
  Authority remains the whole durable Outcome. Semantic relatedness selects
  that observed result, independently of lexical overlap inside its body.
  A parent synthesis and a whole Operation also keep the whole result, while a bounded
  native clause carries only the exact result fragment that grounded it. The
  derived Outcome cites its durable owner as Exact provenance.
  -/
  if matched.retrieved || !matched.work.subwork || matched.work.wholeWorkIdentity ||
      (matched.workJudgment.delivery = .completed &&
        matched.work.pastWholeWork && matched.work.priorInDemand.complete) then
    matched.edge.outcome
  else
    (matched.context.bind (·.outcomeFragment)).getD matched.edge.outcome

/-- Semantic nomination cannot silently replace an observed tool result with
one lexical line. This retains evidence, without granting Work identity. -/
theorem retrieved_projection_keeps_owner (matched : Match)
    (nominated : matched.retrieved = true) :
    matched.projectionOutcome = matched.edge.outcome := by
  simp [projectionOutcome, nominated]

/-- A transported result is either its authority or exact bytes grounded in it. -/
theorem projectionOutcome_is_owned_or_grounded (matched : Match) :
    matched.projectionOutcome = matched.edge.outcome ∨
      ∃ context fragment,
        matched.context = some context ∧
        context.outcomeFragment = some fragment ∧
        matched.projectionOutcome = fragment := by
  unfold projectionOutcome
  split
  · exact Or.inl rfl
  · cases matched.context with
    | none =>
        left
        rfl
    | some context =>
        cases projected : context.outcomeFragment with
        | none =>
            left
            simp [projected]
        | some fragment =>
            right
            exact ⟨context, fragment, rfl, projected, by simp [projected]⟩

/--
Local fragment identity derives one ordinary run-local Outcome.  Its Exact
observation is the durable Outcome relation that supplied the result, so the
derived edge neither invents an outcome nor becomes persistent authority.
-/
def projectedEdge (matched : Match) : OutcomeEdge :=
  if matched.projectionWork == matched.edge.work &&
      matched.projectionOutcome == matched.edge.outcome then matched.edge else
    .make matched.projectionWork matched.projectionOutcome [matched.edge.relation]
      (by simp) (by simp [maxOutcomeObservations])

@[simp]
theorem projectedEdge_outcome (matched : Match) :
    matched.projectedEdge.outcome = matched.projectionOutcome := by
  unfold projectedEdge
  split
  · rename_i accepted
    simp only [Bool.and_eq_true, beq_iff_eq] at accepted
    exact accepted.2.symm
  · rfl

/-- A fragment projection either is its durable owner or cites that owner exactly. -/
theorem projectedEdge_has_owner_provenance (matched : Match) :
    matched.projectedEdge = matched.edge ∨
      matched.edge.relation ∈ matched.projectedEdge.observations := by
  unfold projectedEdge
  split
  · exact Or.inl rfl
  · exact Or.inr (by simp [OutcomeEdge.make])

def demandCoverage (matched : Match) : Option Coverage :=
  some matched.work.demandInPrior

/--
Work identity nominates automatic handoff. Outcome text never creates Union;
it only proves that an already-Unioned Work fragment has an observed owner.
-/
def automatic (matched : Match) : Bool :=
  if matched.retrieved then true else
  /-
  Completion and delivery are separate. A complete subwork may control one
  replan; one positive-weight result match may still connect fallible advice.
  Neither case lets zero-weight transport syntax enter Demand.
  -/
  if matched.work.subwork then
    matched.work.fragmentIdentity &&
      (matched.workJudgment.delivery = .completed ||
        matched.transportGroundedContext ||
        (matched.groundedContext &&
          (matched.work.priorInDemand.complete ||
            matched.work.demandInPrior.complete ||
            matched.work.priorInDemand.distinctiveAnchors != 0 ||
            matched.work.demandInPrior.distinctiveAnchors != 0)))
  else
    /-
    A parent Turn is never completed by this lane. Intent verbs normally do
    not reappear in an observed result, so requiring complete result coverage
    would discard the shared synthesis that links two different inquiries.
    One corpus-distinctive Work anchor in the result is sufficient for advisory
    projection; it cannot create Union or erase Work.
    -/
    matched.work.wholeWorkIdentity ||
      (matched.work.fragmentIdentity && matched.groundedContext &&
        (matched.work.priorInDemand.distinctiveAnchors > 1 ||
          matched.work.demandInPrior.distinctiveAnchors > 1))

/-- Grounded parent synthesis is deliverable advice without becoming Work completion. -/
theorem grounded_parent_context_is_automatic (matched : Match)
    (parent : matched.work.subwork = false)
    (identity : matched.work.fragmentIdentity = true)
    (grounded : matched.groundedContext = true)
    (anchors : matched.work.priorInDemand.distinctiveAnchors > 1 ∨
      matched.work.demandInPrior.distinctiveAnchors > 1) :
    matched.automatic = true := by
  simp [automatic, parent, identity, grounded, anchors]

/-- Partial child identity alone may saturate, but cannot transport an ungrounded result. -/
theorem advisory_subwork_automatic_requires_grounded_context (matched : Match)
    (intrinsic : matched.retrieved = false)
    (subwork : matched.work.subwork = true)
    (advisory : matched.workJudgment.delivery ≠ .completed)
    (automatic : matched.automatic = true) :
  matched.groundedContext = true := by
  simp [Match.automatic, intrinsic, subwork, advisory] at automatic
  rcases automatic.2 with transported | grounded
  · exact transportGroundedContext_is_grounded transported
  · exact grounded.1

end Match

def materializeFragment (source : LogicalText.T) (spans : List ByteSpan) :
    Option (Value × ByteSpan) := do
  let sourceSpans ← LogicalText.sourceSpans? source spans
  let fragments ← sourceSpans.mapM (LogicalText.sourceSlice? source)
  let sourceSpan ← LogicalText.envelope? sourceSpans
  /-
  This Atom is semantic identity, not a display excerpt.  Joining selected
  source pieces with whitespace preserves their units without inventing an
  ellipsis token that would make the derived fragment impossible to cover.
  -/
  let fragment := " ".intercalate fragments
  if fragment.trimAscii.isEmpty then none else pure (.text fragment, sourceSpan)

def sourcePartStep (sourceSpans : List ByteSpan) (separator : String)
    (state : Nat × List String) (line : String) : Nat × List String :=
  let stop := state.1 + line.toUTF8.size
  let intersects := sourceSpans.any fun span =>
    span.start < stop && state.1 < span.stop
  (stop + separator.toUTF8.size,
    if intersects then line :: state.2 else state.2)

def sourcePartEnd : List ByteSpan → Nat
  | [] => 0
  | span :: rest => max span.stop (sourcePartEnd rest)

theorem sourcePartEnd_bounds (spans : List ByteSpan) (span : ByteSpan)
    (present : span ∈ spans) : span.stop ≤ sourcePartEnd spans := by
  induction spans with
  | nil => simp at present
  | cons head rest ih =>
      rcases List.mem_cons.mp present with equal | member
      · subst span; exact Nat.le_max_left ..
      · exact Nat.le_trans (ih member) (Nat.le_max_right ..)

/-- Beyond the greatest requested byte position, no later line can intersect
any request, including empty, overlapping or out-of-source spans. -/
theorem sourcePartStep_afterEnd (spans : List ByteSpan) (separator : String)
    (state : Nat × List String) (line : String)
    (past : sourcePartEnd spans ≤ state.1) :
    (sourcePartStep spans separator state line).2 = state.2 ∧
      sourcePartEnd spans ≤ (sourcePartStep spans separator state line).1 := by
  have absent : spans.any (fun span =>
      span.start < state.1 + line.toUTF8.size && state.1 < span.stop) = false := by
    apply Bool.eq_false_iff.mpr
    intro found
    obtain ⟨span, member, intersects⟩ := List.any_eq_true.mp found
    have bound := sourcePartEnd_bounds spans span member
    simp only [Bool.and_eq_true, decide_eq_true_eq] at intersects
    omega
  simp only [sourcePartStep, absent, Bool.false_eq_true, ↓reduceIte]
  exact ⟨trivial, by omega⟩

theorem sourcePartSuffix_stable (spans : List ByteSpan) (separator : String)
    (state : Nat × List String) (past : sourcePartEnd spans ≤ state.1)
    (parts : List String) :
    (parts.foldl (sourcePartStep spans separator) state).2 = state.2 := by
  induction parts generalizing state with
  | nil => rfl
  | cons part rest ih =>
      obtain ⟨same, later⟩ := sourcePartStep_afterEnd spans separator state part past
      exact (ih _ later).trans same

def sourcePartProjection (spans : List ByteSpan) (separator : String) :
    TextParts.Projection (Nat × List String) (List String) :=
  let limit := sourcePartEnd spans
  {
  step := sourcePartStep spans separator
  finish := fun state => state.2.reverse
  done := fun state => decide (limit ≤ state.1)
  stable := fun state done rest => congrArg List.reverse
    (sourcePartSuffix_stable spans separator state (of_decide_eq_true done) rest) }

/-- Exact intersecting source parts, stopping as soon as the last demanded
range has passed. No irrelevant suffix scan, copied whole-parts list,
quadratic append or additional save-time indexing. -/
def intersectingSourceParts (sourceSpans : List ByteSpan) (separator source : String) :
    List String :=
  TextParts.foldProjection (sourcePartProjection sourceSpans separator) (0, []) source separator

theorem intersectingSourceParts_exact (sourceSpans : List ByteSpan) (separator source : String) :
    intersectingSourceParts sourceSpans separator source =
      ((source.splitOn separator).foldl (init := (0, [])) fun (offset, selected) line =>
        let stop := offset + line.toUTF8.size
        let intersects := sourceSpans.any fun span =>
          span.start < stop && offset < span.stop
        (stop + separator.toUTF8.size,
          if intersects then selected ++ [line] else selected)).2 := by
  rw [intersectingSourceParts, TextParts.foldProjection_exact]
  change ((source.splitOn separator).foldl (sourcePartStep sourceSpans separator) (0, [])).2.reverse = _
  have exact := List.foldl_hom (fun state : Nat × List String => (state.1, state.2.reverse))
    (g₁ := sourcePartStep sourceSpans separator)
    (g₂ := fun (offset, selected) line =>
      let stop := offset + line.toUTF8.size
      let intersects := sourceSpans.any fun span => span.start < stop && offset < span.stop
      (stop + separator.toUTF8.size, if intersects then selected ++ [line] else selected))
    (l := source.splitOn separator) (init := (0, [])) (by
      intro state line
      simp only [sourcePartStep]
      split <;> simp [List.reverse_cons])
  exact congrArg Prod.snd exact.symm

/--
Project only native result records.  A turn Outcome is already one coherent
natural-language synthesis and crosses the graph boundary whole, once.  A
native result can be arbitrarily large, so only its exact intersecting lines
cross while the durable owner remains whole in `.egg`.
-/
def materializeContext (source : LogicalText.T) (spans : List ByteSpan)
    (native : Bool) :
    Option Value := do
  if !native then none
  let sourceSpans ← LogicalText.sourceSpans? source spans
  /-
  Canonical native JSON retains string newlines as `\n`. Project those logical
  lines without flattening the authoritative object, its keys, or its types.
  -/
  let separator := if source.original.contains "\\n" then "\\n" else "\n"
  let selected := intersectingSourceParts sourceSpans separator source.original
  let fragment := "\n".intercalate selected
  if fragment.trimAscii.isEmpty then none else pure (.text fragment)

/-- The only searchable Work owners are existing positive Outcome relations. -/
def outcomeCandidates (graph : WorkGraph) : List OutcomeEdge := graph.outcomes

@[simp]
theorem outcomeCandidates_eq (graph : WorkGraph) :
    outcomeCandidates graph = graph.outcomes := rfl

/-- The Work comparison input contains no result, observation payload or
fabricated Outcome edge. It is compiled directly from the pinned Work lane. -/
structure WorkView where
  value : Value
  pattern : Pattern
  patterns : List WorkPattern
  native : Bool

def WorkView.compile (normalize : Normalizer) (work : Value) (native : Bool) : Option WorkView := do
  let text ← atomText? work
  pure {
    value := work
    pattern := Matcher.compile normalize text
    patterns := compileWorkPatterns normalize text native
    native
  }

structure Candidate where
  edge : OutcomeEdge
  work : Pattern
  /-- Rebuildable structural views of the same persistent Work owner. -/
  workPatterns : List WorkPattern
  outcome : Option Pattern
  /-- Exact occurrence distinguishes native operations from ordinary All children. -/
  native : Bool

/--
Native and turn occurrences already have opposite semantic orientation. A
native occurrence cites `[observed outcome, invoked Work]`; a turn occurrence
cites `[requested Work, final outcome]`. Relation position therefore recovers
the boundary without an Atom kind or a second persistent operator.
-/
def nativeOccurrenceFor (edge : OutcomeEdge) : Value → Bool :=
  Relation.observesOutcomeWork edge.outcome edge.work

def nativeOutcome (edge : OutcomeEdge) : Bool :=
  edge.observations.any (nativeOccurrenceFor edge)

theorem OutcomeEdge.native_has_oriented_occurrence {edge : OutcomeEdge}
    (native : nativeOutcome edge = true) :
    ∃ occurrence ∈ edge.observations, nativeOccurrenceFor edge occurrence = true := by
  exact List.any_eq_true.mp native

def Candidate.workView (candidate : Candidate) : WorkView := {
  value := candidate.edge.work, pattern := candidate.work,
  patterns := candidate.workPatterns, native := candidate.native }

/-- One legal Work-to-Work comparison; clauses never cross this boundary. -/
structure PatternPair where
  past : Pattern
  current : Pattern
  pastValue : Value
  currentValue : Value
  pastWhole : Bool
  retrieved : Bool := false

def WorkView.intrinsicPairs (candidate : WorkView) (quotient : Quotient)
    (current : Value) (currentPattern : Pattern)
    (currentPatterns : List WorkPattern) : List PatternPair :=
  if quotient.toEquality.same current candidate.value then [{
    past := candidate.pattern
    current := currentPattern
    pastValue := candidate.value
    currentValue := current
    pastWhole := true
  }] else
    comparisonPatterns candidate.patterns |>.flatMap fun past =>
      comparisonPatterns currentPatterns |>.map fun present => {
        past := past.pattern
        current := present.pattern
        pastValue := past.value
        currentValue := present.value
        pastWhole := past.whole
      }

def WorkView.retrievalPair (candidate : WorkView) (current : Value)
    (currentPattern : Pattern) : PatternPair := {
  past := candidate.pattern
  current := currentPattern
  pastValue := candidate.value
  currentValue := current
  pastWhole := true
  retrieved := true
}


def Candidate.intrinsicPairs (candidate : Candidate) (quotient : Quotient)
    (current : Value) (currentPattern : Pattern) (currentPatterns : List WorkPattern) : List PatternPair :=
  candidate.workView.intrinsicPairs quotient current currentPattern currentPatterns

def Candidate.retrievalPair (candidate : Candidate) (current : Value)
    (currentPattern : Pattern) : PatternPair := candidate.workView.retrievalPair current currentPattern

/--
One immutable compilation of every Outcome owner. Candidate indexes are
rebuildable acceleration only; the authoritative candidate universe remains
exactly `graph.outcomes`.
-/
structure Corpus where
  candidates : List Candidate
  /-- A demand view may load fewer owners. Novelty still belongs to the full
  published candidate population, never the number of hydrated bodies. -/
  population : Nat := candidates.length
  /-- Frequency semantics are extensional. Physical hash-table bucket order
  must not make an equivalent incremental computation a different corpus. -/
  frequency : String → Nat
  subworks : List Value
  parents : List AllEdge := []

/-- Change only the optional context pattern; original authority and Work
structure are retained byte-for-byte. -/
def Candidate.withOutcome (candidate : Candidate) (outcome : Option Pattern) : Candidate :=
  {candidate with outcome}

namespace Corpus

/-- Work-only compiler on the actual owner, including native orientation.
No result text is decoded or normalized by this phase. -/
def compileWorkCandidate (normalize : Normalizer) (edge : OutcomeEdge) : Option Candidate := do
  let text ← atomText? edge.work
  pure {
    edge
    work := compile normalize text
    workPatterns := compileWorkPatterns normalize text (nativeOutcome edge)
    outcome := none
    native := nativeOutcome edge
  }

def finishCandidate (normalize : Normalizer) (candidate : Candidate) : Candidate :=
  candidate.withOutcome ((atomText? candidate.edge.outcome).map fun text =>
    compile normalize text)

theorem finishCandidate_eager_exact (normalize : Normalizer) (candidate : Candidate) :
    finishCandidate normalize candidate = candidate.withOutcome
      ((atomText? candidate.edge.outcome).map fun text =>
        makePattern (LogicalText.build normalize text)) := by
  cases decoded : atomText? candidate.edge.outcome <;>
    simp [finishCandidate, decoded, compile_eager_exact]

def compileCandidate (normalize : Normalizer) (edge : OutcomeEdge) : Option Candidate := do
    let text ← atomText? edge.work
    let work := compile normalize text
    let native := nativeOutcome edge
    let workPatterns := compileWorkPatterns normalize text native
    /-
    Outcome text is a positive-relation surface lane, not equality authority.
    -/
    let outcome := (atomText? edge.outcome).map fun text =>
      compile normalize text
    pure { edge, work, workPatterns, outcome, native }

/-- The two phases are precisely the existing complete compiler, not a
second interpretation of native Work, result framing or provenance. -/
theorem compileCandidate_phases (normalize : Normalizer) (owner : OutcomeEdge) :
    compileCandidate normalize owner =
      (compileWorkCandidate normalize owner).map (finishCandidate normalize) := by
  cases work : atomText? owner.work <;>
    simp [compileCandidate, compileWorkCandidate, work, finishCandidate, Candidate.withOutcome]

theorem compileWorkCandidate_owner {normalize : Normalizer} {owner : OutcomeEdge}
    {candidate : Candidate} (compiled : compileWorkCandidate normalize owner = some candidate) :
    candidate.edge = owner := by
  cases work : atomText? owner.work with
  | none => simp [compileWorkCandidate, work] at compiled
  | some text =>
      simp [compileWorkCandidate, work] at compiled
      rw [← compiled]

theorem finishCandidate_compiled {normalize : Normalizer} {owner : OutcomeEdge}
    {candidate : Candidate} (compiled : compileWorkCandidate normalize owner = some candidate) :
    compileCandidate normalize owner = some (finishCandidate normalize candidate) := by
  rw [compileCandidate_phases, compiled]
  rfl

theorem compiled_work_view (normalize : Normalizer) (owner : OutcomeEdge) :
    (compileWorkCandidate normalize owner).map Candidate.workView =
      WorkView.compile normalize owner.work (nativeOutcome owner) := by
  cases work : atomText? owner.work <;>
    simp [compileWorkCandidate, WorkView.compile, Candidate.workView, work]

/-- A shallow Work view which agrees with the original owner's Work and
native orientation reconstructs precisely the production compiler candidate. -/
theorem compiled_work_view_candidate {normalize : Normalizer} {owner : OutcomeEdge}
    {view : WorkView} (compiled : WorkView.compile normalize owner.work (nativeOutcome owner) = some view) :
    compileWorkCandidate normalize owner = some {
      edge := owner, work := view.pattern, workPatterns := view.patterns,
      outcome := none, native := view.native } := by
  cases text : atomText? owner.work with
  | none => simp [WorkView.compile, text] at compiled
  | some text =>
      simp [WorkView.compile, text] at compiled
      rw [← compiled]
      simp [compileWorkCandidate, text]

namespace OutcomeMemo

/-- Only the result-body compilation is shared. The certificate names the
complete original Value and normalizer, including invalid UTF-8/non-Atom
results. Native Work, receipt positions and source authority stay in each
independent Candidate. -/
structure Compiled (normalize : Normalizer) (value : Value) where
  pattern : Option Pattern
  exact : pattern = (atomText? value).map (Matcher.compile normalize)

def Compiled.make (normalize : Normalizer) (value : Value) : Compiled normalize value :=
  ⟨(atomText? value).map (Matcher.compile normalize), rfl⟩

structure Entry (normalize : Normalizer) where
  value : Value
  compiled : Compiled normalize value

abbrev Cache (normalize : Normalizer) := Std.HashMap UInt64 (Entry normalize)

structure Prepared (normalize : Normalizer) (value : Value) where
  cache : Cache normalize
  compiled : Compiled normalize value
  reused : Bool

/-- A locator cannot identify a body. Check the entire original Value before
transporting its compilation certificate, even on a forced hash collision.
The request-local table retains existing immutable objects, not copied bodies.
It never refreshes other demands or creates a persistent whole-text cache. -/
def prepare (cache : Cache normalize) (value : Value) : Prepared normalize value :=
  match decoded : atomText? value with
  | none => ⟨cache, ⟨none, by simp [decoded]⟩, false⟩
  | some text =>
      let locator := hash value
      match cache[locator]? with
      | some entry =>
          if same : entry.value = value then
            ⟨cache, same ▸ entry.compiled, true⟩
          else
            let compiled : Compiled normalize value :=
              ⟨some (Matcher.compile normalize text), by simp [decoded]⟩
            ⟨cache.insert locator ⟨value, compiled⟩, compiled, false⟩
      | none =>
          let compiled : Compiled normalize value :=
            ⟨some (Matcher.compile normalize text), by simp [decoded]⟩
          ⟨cache.insert locator ⟨value, compiled⟩, compiled, false⟩

theorem prepare_exact (cache : Cache normalize) (value : Value) :
    (prepare cache value).compiled.pattern = (atomText? value).map (Matcher.compile normalize) :=
  (prepare cache value).compiled.exact

theorem different_body_not_reused (cache : Cache normalize) (value : Value)
    (entry : Entry normalize) (found : cache[hash value]? = some entry)
    (different : entry.value ≠ value) : (prepare cache value).reused = false := by
  unfold prepare
  split
  · rfl
  · simp only [found, different, ↓reduceDIte]

/-- A cheap nontextual result does not hash a potentially giant structured
Value or allocate an entry merely to cache the constant negative result. -/
theorem nontext_preserves_cache (cache : Cache normalize) (value : Value)
    (nontext : atomText? value = none) : (prepare cache value).cache = cache := by
  unfold prepare
  split
  · rfl
  · simp_all

def finish (candidate : Candidate) (compiled : Compiled normalize candidate.edge.outcome) :
    Candidate := candidate.withOutcome compiled.pattern

/-- Complete compiler equality retains both original authority and every
logical byte span; a reused body does not substitute another owner's edge. -/
theorem finish_exact (candidate : Candidate)
    (compiled : Compiled normalize candidate.edge.outcome) :
    finish candidate compiled = finishCandidate normalize candidate := by
  simp only [finish, finishCandidate, compiled.exact]

end OutcomeMemo

/-- Forward request-local reuse while preserving full compiler list order.
The reference compiler remains the specification, including every rejected
nontextual Work. -/
def compileCandidatesUsing (normalize : Normalizer) (cache : OutcomeMemo.Cache normalize) :
    List OutcomeEdge → List Candidate × OutcomeMemo.Cache normalize
  | [] => ([], cache)
  | owner :: rest =>
      match compileWorkCandidate normalize owner with
      | none => compileCandidatesUsing normalize cache rest
      | some work =>
          let prepared := OutcomeMemo.prepare cache work.edge.outcome
          let tail := compileCandidatesUsing normalize prepared.cache rest
          (OutcomeMemo.finish work prepared.compiled :: tail.1, tail.2)

theorem compileCandidatesUsing_exact (normalize : Normalizer)
    (cache : OutcomeMemo.Cache normalize) (owners : List OutcomeEdge) :
    (compileCandidatesUsing normalize cache owners).1 =
      owners.filterMap (compileCandidate normalize) := by
  induction owners generalizing cache with
  | nil => rfl
  | cons owner rest ih =>
      cases prepared : compileWorkCandidate normalize owner with
      | none => simp [compileCandidatesUsing, prepared, compileCandidate_phases, ih]
      | some work =>
          simp [compileCandidatesUsing, prepared, compileCandidate_phases,
            OutcomeMemo.finish_exact, ih]

/-- A structured or opaque Work has no textual comparison pattern. This is
the production compiler's decision, independent of the size of its Outcome. -/
theorem compileCandidate_nontext (normalize : Normalizer) (edge : OutcomeEdge)
    (nontext : atomText? edge.work = none) :
    compileCandidate normalize edge = none := by
  simp [compileCandidate, nontext]

theorem compileCandidate_owner {normalize : Normalizer} {owner : OutcomeEdge}
    {candidate : Candidate} (compiled : compileCandidate normalize owner = some candidate) :
    candidate.edge = owner := by
  cases text : atomText? owner.work with
  | none => simp [compileCandidate, text] at compiled
  | some value =>
      simp [compileCandidate, text] at compiled
      rw [← compiled]

theorem compileCandidate_atom_work {normalize : Normalizer} {owner : OutcomeEdge}
    {candidate : Candidate} (compiled : compileCandidate normalize owner = some candidate) :
    QuotientBuilder.AtomQuotient.isAtom owner.work = true := by
  cases work : owner.work with
  | atom bytes => rfl
  | apply operator arguments => simp [compileCandidate, atomText?, work] at compiled

/-- Filtering only owners which the production compiler already rejects
preserves every compiled candidate in its original order. -/
theorem compileCandidates_textual (normalize : Normalizer) (owners : List OutcomeEdge) :
    ((owners.filter fun edge => (atomText? edge.work).isSome).filterMap
      (compileCandidate normalize)) = owners.filterMap (compileCandidate normalize) := by
  induction owners with
  | nil => rfl
  | cons owner rest ih =>
      cases text : atomText? owner.work with
      | none => simp [text, compileCandidate, ih]
      | some value => simp [text, List.filterMap_cons, ih]

def candidateTerms (candidate : Candidate) : List String :=
  (candidate.work :: candidate.outcome.toList).flatMap (fun pattern =>
    pattern.logical.units.map (·.text)) |> hashDistinct

def workScoringTerms (work : WorkView) (query : CompiledDemand normalize text native) : List String :=
  hashDistinct ((query.pattern :: query.workPatterns.map (·.pattern) ++
    work.pattern :: work.patterns.map (·.pattern)).flatMap
      (fun pattern => pattern.logical.units.map (·.text)))

/-- Comparison patterns only: result words are demanded later by an actual
context query, never merely because an owner has been hydrated. -/
def workScoringPatterns (candidates : List Candidate)
    (query : CompiledDemand normalize text native) : List Pattern :=
  query.pattern :: query.workPatterns.map (·.pattern) ++
    candidates.flatMap (fun candidate => candidate.work :: candidate.workPatterns.map (·.pattern))

def workTerms (candidates : List Candidate)
    (query : CompiledDemand normalize text native) : List String :=
  hashDistinct ((workScoringPatterns candidates query).flatMap
    fun pattern => pattern.logical.units.map (·.text))

theorem workTerms_has_unit (candidates : List Candidate)
    (query : CompiledDemand normalize text native) (pattern : Pattern)
    (member : pattern ∈ workScoringPatterns candidates query)
    (unit : LogicalText.Unit) (present : unit ∈ pattern.logical.units) :
    unit.text ∈ workTerms candidates query := by
  apply (HashDistinct.mem _ _).mpr
  exact List.mem_flatMap.mpr ⟨pattern, member, List.mem_map.mpr ⟨unit, present, rfl⟩⟩

theorem workScoringPatterns_query (candidates : List Candidate)
    (query : CompiledDemand normalize text native) (pattern : Pattern)
    (member : pattern ∈ query.pattern :: query.workPatterns.map (·.pattern)) :
    pattern ∈ workScoringPatterns candidates query :=
  List.mem_append_left _ member

theorem workScoringPatterns_candidate (candidates : List Candidate)
    (query : CompiledDemand normalize text native) (candidate : Candidate)
    (present : candidate ∈ candidates) (pattern : Pattern)
    (member : pattern ∈ candidate.work :: candidate.workPatterns.map (·.pattern)) :
    pattern ∈ workScoringPatterns candidates query :=
  List.mem_append_right _ (List.mem_flatMap.mpr ⟨candidate, present, member⟩)

/-- The complete scoring read domain includes decoded native clauses. The
owner's serialized Work terms alone need not contain those spellings. -/
def scoringTerms (candidates : List Candidate) (query : CompiledDemand normalize text native) : List String :=
  let patterns := query.pattern :: query.workPatterns.map (·.pattern) ++
    candidates.flatMap (fun candidate => candidate.work ::
      candidate.workPatterns.map (·.pattern) ++ candidate.outcome.toList)
  hashDistinct (patterns.flatMap fun pattern => pattern.logical.units.map (·.text))

theorem workScoringTerms_exact (candidate : Candidate)
    (query : CompiledDemand normalize text native) :
    workScoringTerms candidate.workView query = scoringTerms [candidate.withOutcome none] query := by
  simp [workScoringTerms, scoringTerms, Candidate.workView, Candidate.withOutcome]

theorem stored_owner_terms_exact (owner : OutcomeEdge) :
    Persistence.Store.ownerTermsFor owner =
      ((compileCandidate logicalNormalizer owner).toList.map candidateTerms).flatten := by
  simp only [Persistence.Store.ownerTermsFor,
    show Persistence.Store.text? = atomText? from rfl]
  cases work : atomText? owner.work with
  | none => simp [work, compileCandidate]
  | some text =>
      cases outcome : atomText? owner.outcome <;>
        simp [work, outcome, compileCandidate, candidateTerms, compile, makePatternLazy,
          Pattern.logical, Thunk.get, LogicalText.logical]

theorem stored_work_surfaces_exact (owner : OutcomeEdge) :
    Persistence.Store.ownerWorkSurfaces owner =
      ((compileCandidate logicalNormalizer owner).toList.map
        (fun candidate => candidate.work.surfaces.toList)).flatten := by
  simp only [Persistence.Store.ownerWorkSurfaces,
    show Persistence.Store.text? = atomText? from rfl]
  cases work : atomText? owner.work with
  | none => simp [work, compileCandidate]
  | some text =>
      simp [work, compileCandidate,
        compile, makePatternLazy, LogicalText.surfaceNames, LogicalText.logical,
        Pattern.surfaces, Thunk.get]

def ownerRows (normalize : Normalizer) (owners : List OutcomeEdge) : List (List String) :=
  owners.map fun owner => ((compileCandidate normalize owner).toList.map candidateTerms).flatten

theorem ownerRows_append (normalize : Normalizer) (left right : List OutcomeEdge) :
    ownerRows normalize (left ++ right) = ownerRows normalize left ++ ownerRows normalize right :=
  List.map_append

theorem ownerRows_length (normalize : Normalizer) (owners : List OutcomeEdge) :
    (ownerRows normalize owners).length = owners.length := by simp [ownerRows]

theorem ownerRows_count (normalize : Normalizer) (owners : List OutcomeEdge) (unit : String) :
    Frequency.count (ownerRows normalize owners) unit =
      Frequency.count ((owners.filterMap (compileCandidate normalize)).map candidateTerms) unit := by
  induction owners with
  | nil => rfl
  | cons owner rest ih =>
    change Frequency.count
        (((compileCandidate normalize owner).toList.map candidateTerms).flatten ::
          ownerRows normalize rest) unit = _
    cases found : compileCandidate normalize owner <;>
      simp [found, Frequency.count_cons, ih]

/-- The pre-incremental document-frequency fold remains the reference. -/
def referenceFrequencies (candidates : List Candidate) : Std.HashMap String Nat :=
  candidates.foldl (fun counts candidate =>
    (candidateTerms candidate).foldl (fun counts unit =>
      counts.insert unit (counts.getD unit 0 + 1)) counts) {}

theorem full_frequencies_exact (candidates : List Candidate) :
    Frequency.full (candidates.map candidateTerms) = referenceFrequencies candidates := by
  simp [Frequency.full, Frequency.fullUnits, referenceFrequencies, List.foldl_map]

def fromCandidates (candidates : List Candidate) (subworks : List Value)
    (parents : List AllEdge := []) : Corpus :=
  let subworks := subworks.eraseDups
  let frequencies := referenceFrequencies candidates
  { candidates, frequency := fun unit => frequencies.getD unit 0, subworks, parents }

theorem referenceFrequency_count (candidates : List Candidate) (unit : String) :
    (referenceFrequencies candidates).getD unit 0 =
      Frequency.count (candidates.map candidateTerms) unit := by
  rw [← full_frequencies_exact, Frequency.full_exact]

/-- Add the small, unpublished owner suffix without rescanning the durable
source's terms. The published population remains independent of hydration. -/
def appendCandidates (corpus : Corpus) (suffix : List Candidate) : Corpus :=
  let frequencies := referenceFrequencies suffix
  { corpus with
    candidates := corpus.candidates ++ suffix
    population := corpus.population + suffix.length
    frequency := fun unit => corpus.frequency unit + frequencies.getD unit 0 }

theorem appendCandidates_exact (left right : List Candidate) (subworks : List Value)
    (parents : List AllEdge) :
    (fromCandidates left subworks parents).appendCandidates right =
      fromCandidates (left ++ right) subworks parents := by
  simp only [appendCandidates, fromCandidates, List.length_append]
  congr 1
  funext unit
  simp only [referenceFrequency_count, List.map_append, Frequency.count_append]

def build (normalize : Normalizer) (graph : WorkGraph) : Corpus :=
  fromCandidates ((outcomeCandidates graph).filterMap
    (compileCandidate normalize)) graph.subworks graph.all

/-- Population, frequencies, clause patterns and parent ordering are all
preserved, not just the ids of a sampled query's candidates. -/
theorem build_textual_projection (normalize : Normalizer) (graph : WorkGraph) :
    build normalize {graph with outcomes := graph.outcomes.filter fun edge =>
      (atomText? edge.work).isSome} = build normalize graph := by
  simp only [build, outcomeCandidates, WorkGraph.subworks, compileCandidates_textual]

/-
Staged Outcomes extend the immutable corpus by compiling only unseen owners.
Document frequencies are rebuilt from the small compiled index; committed
Work patterns are not rescanned at every hook.
-/
def extend (normalize : Normalizer) (corpus : Corpus)
    (graph : WorkGraph) : Corpus :=
  let unseen := graph.outcomes.filter fun edge => corpus.candidates.all fun candidate =>
    candidate.edge.relation != edge.relation
  fromCandidates (corpus.candidates ++ unseen.filterMap
    (compileCandidate normalize)) (corpus.subworks ++ graph.subworks)
    (corpus.parents ++ graph.all)

/--
Numeric ranges and one- or two-letter transport words carry no independent
Work identity. They still participate in exact surface coverage, but `rg`,
`nl`, and similar scaffolding cannot by themselves nominate a Work fragment.
One non-ASCII scalar remains meaningful because many languages encode a whole
word in one scalar.
-/
def identifyingUnit (unit : String) : Bool :=
  match unit.toList with
  | [] => false
  | first :: rest => first.val ≥ 128 ||
      ((first.isAlpha || first = '_') && rest.length ≥ 2)

/-- Exact, rebuildable document novelty; never persistent semantic authority. -/
def unitWeight (corpus : Corpus) (unit : String) : Nat :=
  if !identifyingUnit unit then 0 else
  corpus.population + 1 -
    Nat.min corpus.population (corpus.frequency unit)

/--
Native operation framing is positional. The tool constructor, operation verb,
and option names cannot become identity merely because their spelling is rare
in one corpus. The same words remain ordinary natural language elsewhere.
-/
def weightedUnits (weightFor : String → Nat) (pattern : Pattern)
    (native : Bool) : List Nat :=
  let rec visit : List LogicalText.Unit → Nat → List Nat
    | [], _ => []
    | unit :: rest, ordinal =>
        let precededByDash := if unit.source.start = 0 then false else
          pattern.logical.original.toUTF8.get! (unit.source.start - 1) == 45
        let weight := if native && (ordinal < 2 || precededByDash) then 0
          else weightFor unit.text
        weight :: visit rest (ordinal + 1)
  visit pattern.logical.units 0

def informationWeights (corpus : Corpus) (pattern : Pattern)
    (native : Bool := false) : List Nat :=
  weightedUnits corpus.unitWeight pattern native

/-- Only actual query units can affect their positional weights. This also
retains native framing and dash suppression exactly. -/
theorem weightedUnits_congr (left right : String → Nat) (pattern : Pattern) (native : Bool)
    (agree : ∀ unit ∈ pattern.logical.units, left unit.text = right unit.text) :
    weightedUnits left pattern native = weightedUnits right pattern native := by
  have visit (units : List LogicalText.Unit) (ordinal : Nat)
      (subset : ∀ unit ∈ units, unit ∈ pattern.logical.units) :
      weightedUnits.visit left pattern native units ordinal =
        weightedUnits.visit right pattern native units ordinal := by
    induction units generalizing ordinal with
    | nil => rfl
    | cons unit rest ih =>
      simp only [weightedUnits.visit]
      rw [agree unit (subset unit List.mem_cons_self)]
      rw [ih (ordinal + 1) (fun next member => subset next (List.mem_cons_of_mem unit member))]
  exact visit pattern.logical.units 0 (fun _ member => member)

/-- Demand-scoped scoring reads use the full published population. Missing
unrequested words cannot change a weight when all units of this pattern agree. -/
theorem informationWeights_congr (left right : Corpus) (pattern : Pattern) (native : Bool)
    (population : left.population = right.population)
    (frequencies : ∀ unit ∈ pattern.logical.units,
      left.frequency unit.text = right.frequency unit.text) :
    left.informationWeights pattern native = right.informationWeights pattern native := by
  apply weightedUnits_congr
  intro unit member
  simp only [unitWeight, population, frequencies unit member]

end Corpus

/--
Exact symmetric intersection.  Scanning the smaller immutable key set changes
only cost: a surface is shared iff either set contains a key from the other.
-/
def sharesSurface (left right : Pattern) : Bool :=
  if left.surfaces.size ≤ right.surfaces.size then
    left.surfaces.any right.surfaces.contains
  else
    right.surfaces.any left.surfaces.contains

/-- The complete posting key domain is precisely the matcher's symmetric
surface admission domain; neither a digest nor a one-word approximation is
used to drop candidates. -/
theorem sharesSurface_keys (left right : Pattern) :
    sharesSurface left right = true ↔
      ∃ surface ∈ left.surfaces.toList, surface ∈ right.surfaces.toList := by
  unfold sharesSurface
  split
  · simp only [Std.HashSet.any_eq_true_iff_exists_mem,
      Std.HashSet.contains_iff_mem, Std.HashSet.mem_toList]
  · simp only [Std.HashSet.any_eq_true_iff_exists_mem,
      Std.HashSet.contains_iff_mem, Std.HashSet.mem_toList]
    constructor
    · rintro ⟨surface, first, second⟩
      exact ⟨surface, second, first⟩
    · rintro ⟨surface, first, second⟩
      exact ⟨surface, second, first⟩

/-- The exact keys written by Intern.root nominate precisely the compiled
owner's Work surface lane, including case normalization and negative keys. -/
theorem stored_work_surface_admission (owner : OutcomeEdge) (candidate : Candidate)
    (compiled : Corpus.compileCandidate LogicalText.logicalNormalizer owner = some candidate)
    (query : Pattern) :
    sharesSurface query candidate.work = true ↔
      ∃ surface ∈ query.surfaces.toList,
        surface ∈ Persistence.Store.ownerWorkSurfaces owner := by
  have stored := Corpus.stored_work_surfaces_exact owner
  rw [compiled] at stored
  simp only [Option.toList_some, List.map_cons, List.map_nil,
    List.flatten_cons, List.flatten_nil, List.append_nil] at stored
  rw [stored]
  exact sharesSurface_keys query candidate.work

def externallyNominated (relations : List Value) (candidate : Candidate) : Bool :=
  relations.contains candidate.edge.relation

structure SemanticNominations where
  related : List Value := []
  /-- Busy or failed search is not a completed search with zero matches. -/
  pending : Bool := false
  deriving DecidableEq

def SemanticNominations.contains (nominations : SemanticNominations)
    (candidate : Candidate) : Bool :=
  externallyNominated nominations.related candidate

def nominated (query : Pattern)
    (semantic : SemanticNominations) (candidate : Candidate) : Bool :=
  sharesSurface query candidate.work ||
    semantic.contains candidate

/--
Every admitted item remains an existing positive Outcome owner. An optional
semantic process can nominate an owner but cannot manufacture Work, Outcome,
provenance, or a relation outside the authoritative corpus.
-/
def admittedCandidates (query : Pattern)
    (corpus : Corpus) (semantic : SemanticNominations) : List Candidate :=
  corpus.candidates.filter (nominated query semantic)

/-- Keep scoring and topology dependencies while selecting only demanded
owners. In particular, an unrelated new document still changes population
and document frequency; it is not hidden by this view. -/
def Corpus.select (corpus : Corpus) (keep : Candidate → Bool) : Corpus :=
  { corpus with candidates := corpus.candidates.filter keep }

theorem selected_admissions_exact (corpus : Corpus) (keep : Candidate → Bool)
    (query : Pattern) (semantic : SemanticNominations)
    (complete : ∀ candidate ∈ corpus.candidates,
      nominated query semantic candidate = true → keep candidate = true) :
    admittedCandidates query (corpus.select keep) semantic =
      admittedCandidates query corpus semantic := by
  simp only [admittedCandidates, Corpus.select, List.filter_filter]
  apply List.filter_congr
  intro candidate member
  cases admitted : nominated query semantic candidate with
  | false => simp
  | true => simp [complete candidate member admitted]

theorem admittedCandidate_has_outcome_owner
    {query : Pattern} {corpus : Corpus} {semantic : SemanticNominations}
    {candidate : Candidate}
    (admitted : candidate ∈ admittedCandidates query corpus semantic) :
    candidate ∈ corpus.candidates := by
  exact (List.mem_filter.mp admitted).1

/--
The candidate universe is exactly the owners of Outcome relations. Arbitrary
Atoms can provide evidence, but only an Outcome owner can erase completed work.
-/
abbrev CoverageProvider := Pattern → Pattern → List Nat → List Nat → Nat →
  List (Coverage × Coverage)

/-- The ordered Work comparison stage does not inspect result text. Every
weight still comes from the complete published population and frequencies. -/
def WorkView.alignments (candidate : WorkView) (cover : CoverageProvider)
    (quotient : Quotient) (corpus : Corpus) (current : Value)
    (currentPattern : Pattern) (currentPatterns : List WorkPattern)
    (retrieved : Bool) (currentNative : Bool) :
    List (PatternPair × Coverage × Coverage) :=
  let noveltyCeiling := corpus.population + 1
  let related := if retrieved then
    [candidate.retrievalPair current currentPattern] else []
  let pairs := related ++ candidate.intrinsicPairs quotient current currentPattern currentPatterns
  pairs.flatMap fun pair =>
    let pastWeights := corpus.informationWeights pair.past candidate.native
    let currentWeights := corpus.informationWeights pair.current currentNative
    let alignments := if pair.retrieved then
      [(completeCoverage pair.past pastWeights noveltyCeiling,
        completeCoverage pair.current currentWeights noveltyCeiling)]
      else cover pair.past pair.current pastWeights currentWeights noveltyCeiling
    alignments.map fun (priorInDemand, demandInPrior) => (pair, priorInDemand, demandInPrior)


def Candidate.workAlignments (candidate : Candidate) (cover : CoverageProvider)
    (quotient : Quotient) (corpus : Corpus) (current : Value)
    (currentPattern : Pattern) (currentPatterns : List WorkPattern)
    (semantic : SemanticNominations) (currentNative : Bool) :
    List (PatternPair × Coverage × Coverage) :=
  candidate.workView.alignments cover quotient corpus current currentPattern currentPatterns
    (externallyNominated semantic.related candidate) currentNative

theorem Candidate.workAlignments_outcome_independent (candidate : Candidate)
    (outcome : Option Pattern) (cover : CoverageProvider) (quotient : Quotient)
    (corpus : Corpus) (current : Value) (pattern : Pattern) (patterns : List WorkPattern)
    (semantic : SemanticNominations) (native : Bool) :
    (candidate.withOutcome outcome).workAlignments cover quotient corpus current pattern patterns semantic native =
      candidate.workAlignments cover quotient corpus current pattern patterns semantic native := rfl

theorem comparisonPatterns_subset {pattern : WorkPattern} {patterns : List WorkPattern}
    (member : pattern ∈ comparisonPatterns patterns) : pattern ∈ patterns := by
  unfold comparisonPatterns at member
  dsimp only at member
  split at member
  · exact member
  · exact (List.mem_filter.mp member).1

/-- Every Work frequency lookup belongs to the complete comparison domain,
including decoded clauses and the independent retrieval lane. -/
theorem WorkView.pair_patterns (candidate : WorkView) (quotient : Quotient)
    (current : Value) (pattern : Pattern) (patterns : List WorkPattern) (retrieved : Bool)
    (pair : PatternPair)
    (member : pair ∈ (if retrieved then [candidate.retrievalPair current pattern] else []) ++
      candidate.intrinsicPairs quotient current pattern patterns) :
    pair.past ∈ candidate.pattern :: candidate.patterns.map (·.pattern) ∧
      pair.current ∈ pattern :: patterns.map (·.pattern) := by
  rcases List.mem_append.mp member with related | intrinsic
  · cases retrieved with
    | false => simp at related
    | true =>
      simp only [↓reduceIte, List.mem_singleton] at related
      subst pair
      exact ⟨List.mem_cons_self, List.mem_cons_self⟩
  · unfold intrinsicPairs at intrinsic
    split at intrinsic
    · simp only [List.mem_singleton] at intrinsic
      subst pair
      exact ⟨List.mem_cons_self, List.mem_cons_self⟩
    · rcases List.mem_flatMap.mp intrinsic with ⟨past, pastMember, present⟩
      rcases List.mem_map.mp present with ⟨now, nowMember, equality⟩
      subst pair
      exact ⟨List.mem_cons_of_mem _ (List.mem_map.mpr
        ⟨past, comparisonPatterns_subset pastMember, rfl⟩),
        List.mem_cons_of_mem _ (List.mem_map.mpr
          ⟨now, comparisonPatterns_subset nowMember, rfl⟩)⟩

theorem WorkView.alignments_weights_congr (candidate : WorkView) (cover : CoverageProvider)
    (quotient : Quotient) (left right : Corpus) (current : Value)
    (pattern : Pattern) (patterns : List WorkPattern) (retrieved native : Bool)
    (population : left.population = right.population)
    (pastWeights : ∀ p ∈ candidate.pattern :: candidate.patterns.map (·.pattern),
      left.informationWeights p candidate.native = right.informationWeights p candidate.native)
    (currentWeights : ∀ p ∈ pattern :: patterns.map (·.pattern),
      left.informationWeights p native = right.informationWeights p native) :
    candidate.alignments cover quotient left current pattern patterns retrieved native =
      candidate.alignments cover quotient right current pattern patterns retrieved native := by
  unfold alignments
  rw [List.flatMap_def, List.flatMap_def]
  apply congrArg List.flatten
  apply List.map_congr_left
  intro pair member
  have domain := candidate.pair_patterns quotient current pattern patterns retrieved pair member
  rw [population, pastWeights pair.past domain.1, currentWeights pair.current domain.2]

/-- The Work phase returns an original alignment without inspecting or
normalizing its Outcome. It is also the producer of the exact context query. -/
def Candidate.prepareWork (candidate : Candidate) (quotient : Quotient) (corpus : Corpus)
    (current : Value) (alignment : PatternPair × Coverage × Coverage) : Option WorkAlignment := do
  let edge := candidate.edge
  let (pair, priorInDemand, demandInPrior) := alignment
  let pastComplete := priorInDemand.complete
  let currentComplete := demandInPrior.complete
  let (pastSpans, currentSpans) ←
    if pastComplete then
      some (priorInDemand.querySpans, priorInDemand.targetSpans)
    else if currentComplete then
      some (demandInPrior.targetSpans, demandInPrior.querySpans)
    else if priorInDemand.compareScore demandInPrior != .lt then
      some (priorInDemand.querySpans, priorInDemand.targetSpans)
    else
      some (demandInPrior.targetSpans, demandInPrior.querySpans)
  let pastSpan ← LogicalText.envelope? pastSpans
  let currentSpan ← LogicalText.envelope? currentSpans
  let pastFragment := if priorInDemand.coveredUnits.length =
      pair.past.logical.units.length then pair.pastValue else
    (materializeFragment pair.past.logical pastSpans).map (·.1) |>.getD pair.pastValue
  let currentFragment := if demandInPrior.coveredUnits.length =
      pair.current.logical.units.length then pair.currentValue else
    (materializeFragment pair.current.logical currentSpans).map (·.1) |>.getD pair.currentValue
  let subwork := corpus.subworks.any (quotient.toEquality.same edge.work)
  let wholeWorkIdentity := quotient.toEquality.same current edge.work
  let preliminaryWork : WorkAlignment := {
    priorInDemand
    demandInPrior
    subwork
    pastWholeWork := pair.pastWhole
    wholeWorkIdentity
    fragmentIdentity := quotient.toEquality.same currentFragment pastFragment
    currentFragment
    pastFragment
    currentSpan
    pastSpan
  }
  pure preliminaryWork

/-- Subwork storage is a membership dependency. Keeping the exact answer
for this owner preserves the complete WorkAlignment, including completion
authority, rather than merely its score or selected id. -/
theorem Candidate.prepareWork_subworks_exact (candidate : Candidate) (quotient : Quotient)
    (corpus : Corpus) (subworks : List Value) (parents : List AllEdge)
    (current : Value) (alignment : PatternPair × Coverage × Coverage)
    (same : subworks.any (quotient.toEquality.same candidate.edge.work) =
      corpus.subworks.any (quotient.toEquality.same candidate.edge.work)) :
    candidate.prepareWork quotient {corpus with subworks, parents} current alignment =
      candidate.prepareWork quotient corpus current alignment := by
  unfold prepareWork
  simp only [same]

/-- Query actually used by context grounding, including a derived child
fragment. Its terms cannot be guessed from the original serialized demand. -/
def contextPattern (normalize : Normalizer) (current : Value) (text : String)
    (work : WorkAlignment) : Pattern :=
  compile normalize ((atomText? (work.contextDemand current)).getD text)

/-- Reuse the already compiled complete demand when its original bytes are
the actual context query. Derived fragments still compile their own original
text. The certificate prevents sharing merely similar or sparse patterns. -/
def reusedContextPattern (demand : CompiledDemand normalize text native) (current : Value)
    (work : WorkAlignment) : { pattern : Pattern // pattern = contextPattern normalize current text work } :=
  if same : ((atomText? (work.contextDemand current)).getD text) = text then
    ⟨demand.pattern, by
      unfold contextPattern
      rw [same]
      exact demand.patternExact⟩
  else ⟨contextPattern normalize current text work, rfl⟩

theorem reusedContextPattern_same (demand : CompiledDemand normalize text native)
    (current : Value) (work : WorkAlignment)
    (same : ((atomText? (work.contextDemand current)).getD text) = text) :
    (reusedContextPattern demand current work).val = demand.pattern := by
  simp only [reusedContextPattern, same, ↓reduceDIte]

theorem reusedContextPattern_exact (demand : CompiledDemand normalize text native)
    (current : Value) (work : WorkAlignment) :
    (reusedContextPattern demand current work).val = contextPattern normalize current text work :=
  (reusedContextPattern demand current work).property

/-- Both context directions retain their complete original coverage rules. -/
def groundContextPatternsUsing (cover : ContextProvider) (normalize : Normalizer) (corpus : Corpus)
    (pastNative currentNative : Bool) (evidenceText : Option String)
    (outcomePattern contextDemandPattern : Pattern) : Option ContextAlignment := do
  let noveltyCeiling := corpus.population + 1
  let contextDemandWeights := corpus.informationWeights contextDemandPattern
    currentNative
  /-
  Result coverage grounds an already-Unioned Work fragment in observed
  bytes. It never creates equality: external retrieval stays advisory,
  and the original Outcome relation remains Exact provenance.
  -/
  match cover contextDemandPattern outcomePattern contextDemandWeights
      noveltyCeiling with
  | some demandInOutcome =>
      pure {
        demandInOutcome
        outcomeFragment := materializeContext outcomePattern.logical
          demandInOutcome.targetSpans pastNative
        alreadyVisible := false
      }
  | none =>
      let evidence ← evidenceText
      let evidencePattern := makePattern (LogicalText.build normalize evidence)
      let outcomeWeights := corpus.informationWeights outcomePattern
      let outcomeInContext ← cover outcomePattern evidencePattern
        outcomeWeights noveltyCeiling
      pure {
        demandInOutcome := outcomeInContext
        alreadyVisible := true
      }

def groundContextPatterns := groundContextPatternsUsing surfaceContextCover

theorem groundContextPatternsUsing_exact (cover : ContextProvider)
    (exact : cover = surfaceContextCover) :
    groundContextPatternsUsing cover = groundContextPatterns := by
  subst cover; rfl

/-- Ground the prepared Work with unchanged forward/reverse context rules. -/
def Candidate.groundContext (candidate : Candidate) (normalize : Normalizer)
    (corpus : Corpus) (current : Value) (currentText : String) (currentNative : Bool)
    (evidenceText : Option String) (work : WorkAlignment) : Option ContextAlignment := do
  let outcomePattern ← candidate.outcome
  groundContextPatterns normalize corpus candidate.native currentNative evidenceText outcomePattern
    (contextPattern normalize current currentText work)

/-- Ordered Work projection, independent of all Outcome context weights. -/
def Candidate.preparedWorks (candidate : Candidate) (cover : CoverageProvider)
    (quotient : Quotient) (corpus : Corpus) (current : Value)
    (pattern : Pattern) (patterns : List WorkPattern) (semantic : SemanticNominations)
    (native : Bool) : List (WorkAlignment × Bool) :=
  (candidate.workAlignments cover quotient corpus current pattern patterns semantic native).filterMap
    fun alignment => (candidate.prepareWork quotient corpus current alignment).map
      fun work => (work, alignment.1.retrieved)

/-- Grounding is evaluated only after an actual Work alignment exists.
Failed grounding leaves the same original Match with context absent. -/
def Candidate.findMatches (candidate : Candidate) (normalize : Normalizer)
    (cover : CoverageProvider) (quotient : Quotient) (corpus : Corpus)
    (current : Value) (currentText : String) (currentNative : Bool)
    (demand : CompiledDemand normalize currentText currentNative)
    (evidenceText : Option String) (semantic : SemanticNominations) : List Match :=
  (candidate.preparedWorks cover quotient corpus current demand.pattern demand.workPatterns
    semantic currentNative).map fun (work, retrieved) => {
      demand := current, edge := candidate.edge, work, retrieved
      context := candidate.groundContext normalize corpus current currentText currentNative evidenceText work }

/-- The query is certified against the actual derived Work fragment and
original owner. A sparse or invented Pattern cannot enter this stage. -/
structure PreparedMatch (normalize : Normalizer) (current : Value) (text : String) where
  candidate : Candidate
  work : WorkAlignment
  retrieved : Bool
  contextQuery : Option Pattern
  contextExact : contextQuery = candidate.outcome.map
    (fun _ => contextPattern normalize current text work)

def PreparedMatch.make (normalize : Normalizer) (current : Value) (text : String)
    (demand : CompiledDemand normalize text native)
    (candidate : Candidate) (work : WorkAlignment) (retrieved : Bool) :
    PreparedMatch normalize current text := {
  candidate, work, retrieved
  contextQuery := candidate.outcome.map (fun _ => (reusedContextPattern demand current work).val)
  contextExact := congrArg (fun pattern => candidate.outcome.map (fun _ => pattern))
    (reusedContextPattern_exact demand current work) }

def PreparedMatch.groundUsing (row : PreparedMatch normalize current text)
    (cover : ContextProvider) (corpus : Corpus)
    (native : Bool) (evidence : Option String) : Match := {
  demand := current, edge := row.candidate.edge, work := row.work, retrieved := row.retrieved
  context := do
    let outcome ← row.candidate.outcome
    let query ← row.contextQuery
    groundContextPatternsUsing cover normalize corpus row.candidate.native native evidence outcome query }

def PreparedMatch.ground (row : PreparedMatch normalize current text) :=
  row.groundUsing surfaceContextCover

theorem PreparedMatch.groundUsing_exact (row : PreparedMatch normalize current text)
    (cover : ContextProvider) (exact : cover = surfaceContextCover)
    (corpus : Corpus) (native : Bool) (evidence : Option String) :
    row.groundUsing cover corpus native evidence = row.ground corpus native evidence := by
  subst cover; rfl

theorem PreparedMatch.ground_exact (row : PreparedMatch normalize current text)
    (corpus : Corpus) (native : Bool) (evidence : Option String) :
    row.ground corpus native evidence = {
      demand := current, edge := row.candidate.edge, work := row.work, retrieved := row.retrieved
      context := row.candidate.groundContext normalize corpus current text native evidence row.work } := by
  unfold ground groundUsing Candidate.groundContext groundContextPatterns
  rw [row.contextExact]
  cases outcome : row.candidate.outcome <;> rfl

/-- Context frequency dependencies are taken from executed Work projections.
Only an evidence-present reverse lane can query all result units. -/
def contextTerms (rows : List (PreparedMatch normalize current text)) (reverse : Bool) : List String :=
  (rows.foldl (fun state row =>
    (row.contextQuery.toList ++ if reverse then row.candidate.outcome.toList else []).foldl
      (fun state pattern => pattern.logical.units.foldl
        (fun state unit => HashDistinct.step state unit.text) state) state)
    (({} : Std.HashMap String _root_.Unit), [])).2.reverse

/-- Streaming the finite read domain retains exactly the old first-occurrence
order without allocating all repeated query-unit lists across owners. -/
theorem contextTerms_exact (rows : List (PreparedMatch normalize current text)) (reverse : Bool) :
    contextTerms rows reverse = hashDistinct (rows.flatMap fun row =>
      (row.contextQuery.toList ++ if reverse then row.candidate.outcome.toList else []).flatMap
        fun pattern => pattern.logical.units.map (·.text)) := by
  simp only [contextTerms, hashDistinct, List.foldl_flatMap, List.foldl_map, HashDistinct.step]

theorem Candidate.findMatches_no_work (candidate : Candidate) (normalize : Normalizer)
    (cover : CoverageProvider) (quotient : Quotient) (corpus : Corpus)
    (current : Value) (text : String) (native : Bool)
    (demand : CompiledDemand normalize text native) (evidence : Option String)
    (semantic : SemanticNominations)
    (empty : candidate.workAlignments cover quotient corpus current demand.pattern
      demand.workPatterns semantic native = []) :
    candidate.findMatches normalize cover quotient corpus current text native demand evidence semantic = [] := by
  simp only [Candidate.findMatches, Candidate.preparedWorks, empty, List.filterMap_nil,
    List.map_nil]

/-- Outcome normalization cannot turn a failed Work comparison into a match.
The premise is evaluated on the Work-only candidate used by the real reader. -/
theorem Candidate.finish_no_work (candidate : Candidate) (normalize : Normalizer)
    (cover : CoverageProvider) (quotient : Quotient) (corpus : Corpus)
    (current : Value) (text : String) (native : Bool)
    (demand : CompiledDemand normalize text native) (evidence : Option String)
    (semantic : SemanticNominations)
    (empty : candidate.workAlignments cover quotient corpus current demand.pattern
      demand.workPatterns semantic native = []) :
    (Corpus.finishCandidate normalize candidate).findMatches normalize cover quotient corpus
      current text native demand evidence semantic = [] := by
  apply Candidate.findMatches_no_work
  simpa only [Corpus.finishCandidate, Candidate.workAlignments_outcome_independent] using empty

theorem Candidate.findMatches_select (candidate : Candidate) (normalize : Normalizer)
    (cover : CoverageProvider) (quotient : Quotient) (corpus : Corpus) (keep : Candidate → Bool)
    (current : Value) (text : String) (native : Bool)
    (demand : CompiledDemand normalize text native) (evidence : Option String)
    (semantic : SemanticNominations) :
    candidate.findMatches normalize cover quotient (corpus.select keep) current text native
      demand evidence semantic =
    candidate.findMatches normalize cover quotient corpus current text native demand evidence semantic := rfl

def findInUsing (normalize : Normalizer) (demandProvider : DemandProvider normalize)
    (cover : CoverageProvider) (quotient : Quotient)
    (corpus : Corpus) (current : Value) (currentText : String)
    (evidenceText : Option String := none)
    (semantic : SemanticNominations := {})
    (currentNative : Bool := false) : List Match :=
  let demand := demandProvider currentText currentNative
  -- Admission remains Work-to-Work. Outcome only grounds an existing match;
  -- semantic nominations are an independent advisory lane placed first.
  (admittedCandidates demand.pattern corpus semantic).flatMap fun candidate =>
    candidate.findMatches normalize cover quotient corpus current currentText currentNative demand evidenceText semantic

def prepareInUsing (normalize : Normalizer) (cover : CoverageProvider) (quotient : Quotient)
    (corpus : Corpus) (current : Value) (text : String) (native : Bool)
    (query : CompiledDemand normalize text native) (semantic : SemanticNominations) :
    List (PreparedMatch normalize current text) :=
  (admittedCandidates query.pattern corpus semantic).flatMap fun candidate =>
    (candidate.preparedWorks cover quotient corpus current query.pattern query.workPatterns semantic native).map
      fun (work, retrieved) => PreparedMatch.make normalize current text query candidate work retrieved

/-- One preparation followed by grounding, with no repeated Work coverage or
normalization of the actual context query, is the complete ordered matcher. -/
theorem prepareInUsing_exact (normalize : Normalizer) (cover : CoverageProvider)
    (quotient : Quotient) (corpus : Corpus) (current : Value) (text : String) (native : Bool)
    (query : CompiledDemand normalize text native) (evidence : Option String)
    (semantic : SemanticNominations) :
    (prepareInUsing normalize cover quotient corpus current text native query semantic).map
      (fun row => row.ground corpus native evidence) =
      findInUsing normalize (demandProvider normalize text native query) cover quotient corpus
        current text evidence semantic native := by
  unfold prepareInUsing findInUsing Candidate.findMatches
  simp only [List.map_flatMap, List.map_map, Function.comp_def, PreparedMatch.ground_exact]
  have demand : demandProvider normalize text native query text native = query := by
    simp [demandProvider]
  rw [demand]
  rfl

/-- Context reads may add other frequencies without rerunning Work coverage.
This universal contract accounts for every intrinsic/retrieved pair and every
decoded native clause, rather than only weights seen in an earlier match. -/
theorem prepareInUsing_frequency_congr (normalize : Normalizer) (cover : CoverageProvider)
    (quotient : Quotient) (left right : Corpus) (current : Value) (text : String) (native : Bool)
    (query : CompiledDemand normalize text native) (semantic : SemanticNominations)
    (candidates : left.candidates = right.candidates)
    (population : left.population = right.population) (subworks : left.subworks = right.subworks)
    (frequencies : ∀ unit ∈ Corpus.workTerms left.candidates query,
      left.frequency unit = right.frequency unit) :
    prepareInUsing normalize cover quotient left current text native query semantic =
      prepareInUsing normalize cover quotient right current text native query semantic := by
  have weights (pattern : Pattern) (framed : Bool)
      (present : pattern ∈ Corpus.workScoringPatterns left.candidates query) :
      left.informationWeights pattern framed = right.informationWeights pattern framed := by
    apply Corpus.informationWeights_congr _ _ _ _ population
    intro unit member
    exact frequencies unit.text (Corpus.workTerms_has_unit _ _ _ present unit member)
  have admissions : admittedCandidates query.pattern left semantic =
      admittedCandidates query.pattern right semantic := by
    simp only [admittedCandidates, candidates]
  unfold prepareInUsing
  rw [← admissions, List.flatMap_def, List.flatMap_def]
  apply congrArg List.flatten
  apply List.map_congr_left
  intro candidate member
  have owner := admittedCandidate_has_outcome_owner member
  have alignment := candidate.workView.alignments_weights_congr cover quotient left right current
    query.pattern query.workPatterns (externallyNominated semantic.related candidate) native population
    (fun p h => weights p candidate.native
      (Corpus.workScoringPatterns_candidate _ _ candidate owner p h))
    (fun p h => weights p native (Corpus.workScoringPatterns_query _ _ p h))
  unfold Candidate.preparedWorks Candidate.workAlignments
  rw [alignment]
  have work : candidate.prepareWork quotient left current =
      candidate.prepareWork quotient right current := by
    funext alignment
    unfold Candidate.prepareWork
    rw [subworks]
  simp only [work]

/-- Every finite context read is an actual unit lookup in a certified query
or, when evidence exists, in the complete reverse Outcome query. -/
theorem contextTerms_has_unit (rows : List (PreparedMatch normalize current text)) (reverse : Bool)
    (row : PreparedMatch normalize current text) (present : row ∈ rows) (pattern : Pattern)
    (member : pattern ∈ row.contextQuery.toList ++
      if reverse then row.candidate.outcome.toList else [])
    (unit : LogicalText.Unit) (inPattern : unit ∈ pattern.logical.units) :
    unit.text ∈ contextTerms rows reverse := by
  rw [contextTerms_exact]
  apply (HashDistinct.mem _ _).mpr
  exact List.mem_flatMap.mpr ⟨row, present,
    List.mem_flatMap.mpr ⟨pattern, member, List.mem_map.mpr ⟨unit, inPattern, rfl⟩⟩⟩

theorem groundContextPatterns_weights_congr (normalize : Normalizer) (left right : Corpus)
    (pastNative native : Bool) (evidence : Option String) (outcome query : Pattern)
    (population : left.population = right.population)
    (forward : left.informationWeights query native = right.informationWeights query native)
    (reverse : evidence.isSome = true →
      left.informationWeights outcome = right.informationWeights outcome) :
    groundContextPatterns normalize left pastNative native evidence outcome query =
      groundContextPatterns normalize right pastNative native evidence outcome query := by
  unfold groundContextPatterns groundContextPatternsUsing
  rw [population, forward]
  dsimp only
  split
  · rfl
  · cases present : evidence with
    | none => rfl
    | some value =>
      rw [reverse (by simp [present])]

/-- Unrequested document words cannot change any grounded Match. Forward
and reverse misses, source bytes and their original ordering are preserved. -/
theorem groundPrepared_frequency_congr (rows : List (PreparedMatch normalize current text))
    (left right : Corpus) (native : Bool) (evidence : Option String)
    (population : left.population = right.population)
    (frequencies : ∀ unit ∈ contextTerms rows evidence.isSome,
      left.frequency unit = right.frequency unit) :
    rows.map (fun row => row.ground left native evidence) =
      rows.map (fun row => row.ground right native evidence) := by
  apply List.map_congr_left
  intro row member
  unfold PreparedMatch.ground PreparedMatch.groundUsing
  congr 1
  cases outcome : row.candidate.outcome with
  | none => rfl
  | some out =>
    cases query : row.contextQuery with
    | none => rfl
    | some demand =>
      apply groundContextPatterns_weights_congr _ _ _ _ _ _ _ _ population
      · apply Corpus.informationWeights_congr _ _ _ _ population
        intro unit inPattern
        exact frequencies unit.text (contextTerms_has_unit rows evidence.isSome row member demand
          (by simp [query]) unit inPattern)
      · intro reverse
        apply Corpus.informationWeights_congr _ _ _ _ population
        intro unit inPattern
        exact frequencies unit.text (contextTerms_has_unit rows evidence.isSome row member out
          (by simp [reverse, outcome]) unit inPattern)

/-- The production two-phase execution is the ordinary full matcher when
context reads preserve Work weights. The prepared Work is used once. -/
theorem prepareAndGround_exact (normalize : Normalizer) (cover : CoverageProvider)
    (quotient : Quotient) (left right : Corpus) (current : Value) (text : String) (native : Bool)
    (query : CompiledDemand normalize text native) (evidence : Option String)
    (semantic : SemanticNominations) (candidates : left.candidates = right.candidates)
    (population : left.population = right.population) (subworks : left.subworks = right.subworks)
    (frequencies : ∀ unit ∈ Corpus.workTerms left.candidates query,
      left.frequency unit = right.frequency unit) :
    (prepareInUsing normalize cover quotient left current text native query semantic).map
      (fun row => row.ground right native evidence) =
      findInUsing normalize (demandProvider normalize text native query) cover quotient right
        current text evidence semantic native := by
  rw [prepareInUsing_frequency_congr normalize cover quotient left right current text native
    query semantic candidates population subworks frequencies]
  exact prepareInUsing_exact normalize cover quotient right current text native query evidence semantic

/-- Removing precisely failed Work comparisons preserves all ordered matches,
including result grounding. Global frequency, population and topology stay
unchanged; the claim is for this demanded quotient, not a permanent miss. -/
theorem findInUsing_work_projection_exact (normalize : Normalizer)
    (demands : DemandProvider normalize) (cover : CoverageProvider) (quotient : Quotient)
    (corpus : Corpus) (keep : Candidate → Bool) (current : Value) (text : String)
    (evidence : Option String) (semantic : SemanticNominations) (native : Bool)
    (complete : ∀ candidate ∈ corpus.candidates,
      candidate.workAlignments cover quotient corpus current (demands text native).pattern
        (demands text native).workPatterns semantic native ≠ [] → keep candidate = true) :
    findInUsing normalize demands cover quotient (corpus.select keep) current text evidence semantic native =
      findInUsing normalize demands cover quotient corpus current text evidence semantic native := by
  have admissions : admittedCandidates (demands text native).pattern (corpus.select keep) semantic =
      (admittedCandidates (demands text native).pattern corpus semantic).filter keep := by
    simp only [admittedCandidates, Corpus.select, List.filter_filter]
    congr 1
    funext candidate
    exact Bool.and_comm _ _
  have filterExact (rows : List Candidate)
      (subset : ∀ candidate ∈ rows, candidate ∈ corpus.candidates) :
      (rows.filter keep).flatMap (fun candidate => candidate.findMatches normalize cover
        quotient corpus current text native (demands text native) evidence semantic) =
      rows.flatMap (fun candidate => candidate.findMatches normalize cover quotient corpus
        current text native (demands text native) evidence semantic) := by
    induction rows with
    | nil => rfl
    | cons row rest ih =>
      have tail := ih (fun candidate member => subset candidate (List.mem_cons_of_mem row member))
      cases kept : keep row with
      | true => simp [kept, tail]
      | false =>
        have empty : row.workAlignments cover quotient corpus current (demands text native).pattern
            (demands text native).workPatterns semantic native = [] := by
          exact Classical.byContradiction fun nonempty => by
            have retained := complete row (subset row (List.mem_cons_self)) nonempty
            simp [kept] at retained
        have rejected := Candidate.findMatches_no_work row normalize cover quotient corpus
          current text native (demands text native) evidence semantic empty
        simp [kept, rejected, tail]
  unfold findInUsing
  dsimp only
  rw [admissions]
  simp only [Candidate.findMatches_select]
  exact filterExact _ (fun candidate member => admittedCandidate_has_outcome_owner member)

def findIn (normalize : Normalizer) (quotient : Quotient)
    (corpus : Corpus) (current : Value) (currentText : String)
    (evidenceText : Option String := none) (semantic : SemanticNominations := {})
    (currentNative : Bool := false) : List Match :=
  findInUsing normalize (CompiledDemand.make normalize) pairedCoverages quotient corpus current currentText
    evidenceText semantic currentNative

/-- Empty complete Work postings imply an empty full match list when the
external nomination lane is absent. Result text, scoring, equality and the
evidence-present reverse lane cannot create a Work admission. -/
theorem findIn_no_surface_admissions (normalize : Normalizer) (quotient : Quotient)
    (corpus : Corpus) (current : Value) (text : String) (evidence : Option String) (native : Bool)
    (absent : ∀ candidate ∈ corpus.candidates,
      sharesSurface (CompiledDemand.make normalize text native).pattern candidate.work = false) :
    findIn normalize quotient corpus current text evidence {} native = [] := by
  have noAdmissions : admittedCandidates (CompiledDemand.make normalize text native).pattern
      corpus {} = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro candidate member
    simp [nominated, absent candidate member, SemanticNominations.contains,
      externallyNominated]
  simp [findIn, findInUsing, noAdmissions]

/-- The whole production match list is independent of nontextual owners.
This preserves scores, fragments, context and applicability for a fixed
quotient, not merely a candidate count. -/
theorem findIn_textual_projection (normalize : Normalizer) (quotient : Quotient)
    (graph : WorkGraph) (current : Value) (text : String) (evidence : Option String)
    (semantic : SemanticNominations) (native : Bool) :
    findIn normalize quotient (Corpus.build normalize
      {graph with outcomes := graph.outcomes.filter fun edge => (atomText? edge.work).isSome})
      current text evidence semantic native =
    findIn normalize quotient (Corpus.build normalize graph) current text evidence semantic native := by
  rw [Corpus.build_textual_projection]

/-- Complete ordered matches, including coverage, fragments, native framing
and applicability, are unchanged by a complete admission projection. This is
stronger than comparing a set of selected owner ids. -/
theorem findInUsing_selected_exact (normalize : Normalizer)
    (demands : DemandProvider normalize) (cover : CoverageProvider)
    (quotient : Quotient) (corpus : Corpus) (keep : Candidate → Bool)
    (current : Value) (text : String) (evidence : Option String)
    (semantic : SemanticNominations) (native : Bool)
    (complete : ∀ candidate ∈ corpus.candidates,
      nominated (demands text native).pattern semantic candidate = true →
        keep candidate = true) :
    findInUsing normalize demands cover quotient (corpus.select keep) current text
      evidence semantic native =
    findInUsing normalize demands cover quotient corpus current text evidence semantic native := by
  unfold findInUsing
  dsimp only
  rw [selected_admissions_exact corpus keep _ semantic complete]
  rfl

theorem findInUsing_no_admissions (normalize : Normalizer)
    (demands : DemandProvider normalize) (cover : CoverageProvider)
    (quotient : Quotient) (corpus : Corpus) (current : Value) (text : String)
    (evidence : Option String) (semantic : SemanticNominations) (native : Bool)
    (empty : admittedCandidates (demands text native).pattern corpus semantic = []) :
    findInUsing normalize demands cover quotient corpus current text evidence semantic native = [] := by
  unfold findInUsing
  dsimp only
  rw [empty]
  rfl

theorem findInUsing_exact (normalize : Normalizer) (demands : DemandProvider normalize)
    (demandExact : demands = CompiledDemand.make normalize) (cover : CoverageProvider)
    (exact : cover = pairedCoverages) : findInUsing normalize demands cover = findIn normalize := by
  subst cover
  subst demands
  rfl

def find (normalize : Normalizer) (quotient : Quotient)
    (graph : WorkGraph) (current : Value) (currentText : String) : List Match :=
  findIn normalize quotient (Corpus.build normalize graph)
    current currentText none {}

def localUnion? (quotient : Quotient) (inquiry : Value)
    (matched : Match) : Option UnionEdge := do
  if matched.retrieved then none
  let aligned := matched.work
  /-
  Surface and configured semantic matching nominate only reversible
  Inquiry-local equality. Applicability separately proves whether the selected
  historical Outcome may erase a complete small Work; otherwise the Union
  remains advisory context.
  -/
  if !aligned.priorInDemand.complete && !aligned.demandInPrior.complete &&
      aligned.priorInDemand.coveredWeight = 0 &&
      aligned.demandInPrior.coveredWeight = 0 then none else
  if quotient.toEquality.same aligned.currentFragment aligned.pastFragment then none
  else if exactSafe : Value.sameExactFootprint
      aligned.currentFragment aligned.pastFragment then
    some {
      left := aligned.currentFragment
      right := aligned.pastFragment
      scope := .run inquiry
      exactAuthority := Value.sameExactFootprint_sound exactSafe
    }
  else none

/-- A matcher nomination can only produce reversible Inquiry-local equality. -/
theorem localUnion_is_run_scoped {quotient : Quotient} {inquiry : Value}
    {matched : Match} {edge : UnionEdge}
    (created : localUnion? quotient inquiry matched = some edge) :
    edge.scope = .run inquiry := by
  simp only [localUnion?] at created
  split at created <;> try contradiction
  split at created <;> try contradiction
  split at created <;> try contradiction
  split at created <;> try contradiction
  next =>
    have equality := Option.some.inj created
    subst edge
    rfl

/-- Broad semantic retrieval can expose an Outcome but cannot assert identity. -/
theorem retrieved_never_unions (quotient : Quotient) (inquiry : Value)
    (matched : Match) (retrieved : matched.retrieved = true) :
    localUnion? quotient inquiry matched = none := by
  simp [localUnion?, retrieved]

/-- Broad semantic retrieval is always advisory, independent of its score. -/
theorem retrieved_is_advisory (matched : Match)
    (retrieved : matched.retrieved = true) :
    matched.judgment.delivery = .advisory := by
  simp [Match.judgment, retrieved, ApplicabilityJudgment.delivery]

/-- Transport-only overlap cannot nominate fragment identity. -/
theorem no_complete_or_informative_fragment_no_local_union {quotient : Quotient}
    {inquiry : Value} {matched : Match} {aligned : WorkAlignment}
    (work : matched.work = aligned)
    (pastIncomplete : aligned.priorInDemand.complete = false)
    (currentIncomplete : aligned.demandInPrior.complete = false)
    (past : aligned.priorInDemand.coveredWeight = 0)
    (current : aligned.demandInPrior.coveredWeight = 0) :
    localUnion? quotient inquiry matched = none := by
  simp [localUnion?, work, pastIncomplete, currentIncomplete, past, current]

/-- Advisory result evidence cannot create or change a Local Union. -/
theorem localUnion_ignores_context (quotient : Quotient) (inquiry : Value)
    (matched : Match) :
    localUnion? quotient inquiry { matched with context := none } =
      localUnion? quotient inquiry matched := by
  rfl

def distinctLocalUnions (edges : List UnionEdge) : List UnionEdge :=
  edges.foldl (fun accepted edge =>
    if UnionEdge.newPair accepted edge.left edge.right then accepted ++ [edge]
    else accepted) []

theorem distinctLocalUnions_mem {edges : List UnionEdge} {edge : UnionEdge}
    (present : edge ∈ distinctLocalUnions edges) : edge ∈ edges := by
  let step := fun (accepted : List UnionEdge) (next : UnionEdge) =>
    if UnionEdge.newPair accepted next.left next.right then accepted ++ [next] else accepted
  have loop (pending accepted : List UnionEdge) (member : edge ∈ pending.foldl step accepted) :
      edge ∈ accepted ∨ edge ∈ pending := by
    induction pending generalizing accepted with
    | nil => exact Or.inl member
    | cons next pending ih =>
        simp only [List.foldl_cons, step] at member
        split at member
        · rcases ih _ member with kept | later
          · rcases List.mem_append.mp kept with before | last
            · exact Or.inl before
            · exact Or.inr (List.mem_cons.mpr (Or.inl (by simpa using last)))
          · exact Or.inr (List.mem_cons_of_mem _ later)
        · rcases ih _ member with kept | later
          · exact Or.inl kept
          · exact Or.inr (List.mem_cons_of_mem _ later)
  rcases loop edges [] present with impossible | original
  · simp at impossible
  · exact original

def Match.continuationWork (matched : Match) : Value :=
  matched.projectionWork

/--
A parent match reconnects its existing positive subtree; a child match keeps
the locally identified fragment.  In both cases the current Work stays open.
-/
def continuation? (current : Value) (currentText : String)
    (hits : List Match) : Option AllEdge :=
  let work := hits.filterMap fun matched =>
    if matched.applicability != .irrelevant && matched.work.subwork then
      some matched.continuationWork
    else none
  let work := work |> hashDistinct |>.filter (current != ·)
  if work.isEmpty then none else
    let children := work ++ [HandoffRemainder.value currentText]
    if nonempty : children ≠ [] then
      if excludes : current ∉ children then some (.make current children nonempty excludes)
      else none
    else none

/-- Every synthesized continuation is open by construction. -/
theorem continuation_has_open_remainder {current : Value} {currentText : String}
    {hits : List Match} {edge : AllEdge}
    (created : continuation? current currentText hits = some edge) :
    HandoffRemainder.value currentText ∈ edge.children := by
  simp only [continuation?] at created
  split at created <;> try contradiction
  split at created <;> try contradiction
  split at created <;> try contradiction
  next nonempty excludes =>
    have equal := Option.some.inj created
    subst edge
    simp

theorem continuation_parent {current : Value} {currentText : String}
    {hits : List Match} {edge : AllEdge}
    (created : continuation? current currentText hits = some edge) :
    edge.parent = current := by
  simp only [continuation?] at created
  split at created <;> try contradiction
  split at created <;> try contradiction
  split at created <;> try contradiction
  next nonempty excludes =>
    have equal := Option.some.inj created
    subst edge
    rfl

structure Discovery where
  view : RunView
  hits : List Match
  current : Value
  passes : Nat
  /-- Sparse IO must retain the complete graph's traversal depth. -/
  extractionFuel : Option Nat := none

def Match.admission? (matched : Match) : Option OutcomeAdmission :=
  if matched.automatic then some {
    demand := matched.projectionWork
    relation := matched.projectedEdge.relation
    judgment := matched.judgment
  } else none

/-- Extract policy is a projection of selected Matches, never a second authority. -/
def admissions (hits : List Match) : List OutcomeAdmission :=
  hits.filterMap Match.admission?

def Discovery.policy (discovery : Discovery) : OutcomePolicy :=
  .admitted (admissions discovery.hits)

theorem admission_has_automatic_match {hits : List Match} {admission : OutcomeAdmission}
    (present : admission ∈ admissions hits) :
    ∃ matched ∈ hits, matched.automatic = true ∧
      admission.demand = matched.projectionWork ∧
      admission.relation = matched.projectedEdge.relation ∧
      admission.judgment = matched.judgment := by
  simp only [admissions, List.mem_filterMap] at present
  obtain ⟨matched, member, created⟩ := present
  unfold Match.admission? at created
  split at created
  · rename_i automatic
    simp only [Option.some.injEq] at created
    subst admission
    exact ⟨matched, member, automatic, rfl, rfl, rfl⟩
  · contradiction

def sameMatch (left right : Match) : Bool :=
  left.demand == right.demand && left.edge.relation == right.edge.relation &&
    left.work.currentFragment == right.work.currentFragment &&
    left.work.pastFragment == right.work.pastFragment

def upsertMatch (previous : List Match) (matched : Match) : List Match :=
  matched :: previous.filter (fun existing => !sameMatch matched existing)

def addMatches (previous newMatches : List Match) : List Match :=
  newMatches.foldl upsertMatch previous

def projectMatches (base : WorkGraph) (hits : List Match) : WorkGraph :=
  let outcomes := hits.foldl (fun current matched =>
    if !matched.automatic then current
    else
      let edge := matched.projectedEdge
      if current.any (fun existing => existing.relation == edge.relation) then current
      else current ++ [edge]) base.outcomes
  { base with outcomes }

def demandedMatchesUsing (normalize : Normalizer) (demands : DemandProvider normalize)
    (cover : CoverageProvider)
    (corpus : Corpus) (view : RunView) (current : Value)
    (evidenceText : Option String) (semantic : SemanticNominations)
    (currentNative : Bool) (tasks : List Value) : List Match :=
  tasks.flatMap fun task =>
    match atomText? task with
    | some text => findInUsing normalize demands cover view.quotient corpus task text
        (if task == current then evidenceText else none)
        (if task == current then semantic else {})
        (task == current && currentNative)
    | none => []

def demandedMatches (normalize : Normalizer) :=
  demandedMatchesUsing normalize (CompiledDemand.make normalize) pairedCoverages

/--
A run-local continuation child is the result of a Match already accumulated in
this saturation. Re-matching that synthetic child would let advisory overlap
re-enter as a smaller Demand and incorrectly promote itself to completed Work.
Only the root or Demand newly exposed by the authoritative graph is matchable.
-/
def freshDemand (current : Value) (runAll : List AllEdge) (task : Value) : Bool :=
  task == current || runAll.all fun edge => !edge.children.contains task

theorem continuation_child_is_not_fresh {current child : Value}
    {runAll : List AllEdge} {edge : AllEdge}
    (edgeMember : edge ∈ runAll) (childMember : child ∈ edge.children)
    (different : child ≠ current) :
    freshDemand current runAll child = false := by
  unfold freshDemand
  rw [show (child == current) = false by simpa using different]
  simp only [Bool.false_or]
  apply List.all_eq_false.mpr
  exact ⟨edge, edgeMember, by simp [childMember]⟩

def newLocalUnions (view : RunView) (inquiry : Value)
    (hits : List Match) : List UnionEdge :=
  distinctLocalUnions <| hits.filterMap (localUnion? view.quotient inquiry)

theorem newLocalUnions_origin {view : RunView} {inquiry : Value} {hits : List Match}
    {edge : UnionEdge} (present : edge ∈ newLocalUnions view inquiry hits) :
    ∃ matched ∈ hits, localUnion? view.quotient inquiry matched = some edge ∧
      edge.scope = .run inquiry := by
  obtain ⟨matched, member, generated⟩ := List.mem_filterMap.mp (distinctLocalUnions_mem present)
  exact ⟨matched, member, generated, localUnion_is_run_scoped generated⟩

def rootContinuation? (graph : WorkGraph) (equality : Equality)
    (current : Value) (currentText : String) (hits : List Match) : Option AllEdge := do
  if !(graph.decompositionsFor equality current).isEmpty then none else
  continuation? current currentText (hits.filter fun matched =>
    matched.demand == current && matched.automatic)

/-- Match fragments refine one external continuation; they cannot create independent plans. -/
theorem rootContinuation_parent {graph : WorkGraph} {equality : Equality}
    {current : Value} {currentText : String} {hits : List Match} {edge : AllEdge}
    (created : rootContinuation? graph equality current currentText hits = some edge) :
    edge.parent = current := by
  simp only [rootContinuation?] at created
  split at created <;> try contradiction
  next => exact continuation_parent created

def addContinuations (previous proposed : List AllEdge) : List AllEdge :=
  proposed.foldl (fun accepted edge =>
    if accepted.any (fun existing => existing.relation == edge.relation) then accepted
    else accepted ++ [edge]) previous

/-- A terminal root is certified against the actual discovery transitions.
The constructor cannot be used for a root which exposes another decomposition,
adds equality, projects another owner, or opens a continuation. -/
structure TerminalRoot (view : RunView) (current : Value) (text : String) where
  hits : List Match
  fresh : HandoffRemainder.isValue current = false
  rootUnchanged : view.graph.decompositionsFor view.quotient.toEquality current = []
  unionsUnchanged : newLocalUnions view current hits = []
  ownersUnchanged : projectMatches view.graph (addMatches [] hits) = view.graph
  continuationUnchanged :
    rootContinuation? view.graph view.quotient.toEquality current text (addMatches [] hits) = none

def TerminalRoot.check? (view : RunView) (current : Value) (text : String)
    (hits : List Match) : Option (TerminalRoot view current text) :=
  if fresh : HandoffRemainder.isValue current = false then
   if root : view.graph.decompositionsFor view.quotient.toEquality current = [] then
    if unions : newLocalUnions view current hits = [] then
      if owners : projectMatches view.graph (addMatches [] hits) = view.graph then
        if continuation : rootContinuation? view.graph view.quotient.toEquality
            current text (addMatches [] hits) = none then
          some ⟨hits, fresh, root, unions, owners, continuation⟩
        else none
      else none
    else none
   else none
  else none

def TerminalRoot.discovery (terminal : TerminalRoot view current text) : Discovery := {
  view, hits := addMatches [] terminal.hits, current, passes := 0 }

/-- The empty native boundary is a genuine fixed point even when unrelated
All edges and Outcome bodies exist elsewhere in the source. -/
def TerminalRoot.empty (view : RunView) (current : Value) (text : String)
    (fresh : HandoffRemainder.isValue current = false)
    (noParent : view.graph.decompositionsFor view.quotient.toEquality current = []) :
    TerminalRoot view current text := {
  hits := [], fresh, rootUnchanged := noParent
  unionsUnchanged := rfl
  ownersUnchanged := rfl
  continuationUnchanged := by
    simp [addMatches, rootContinuation?, noParent, continuation?, hashDistinct] }

theorem TerminalRoot.changed_union_rejected (view : RunView) (current : Value)
    (text : String) (hits : List Match) (changed : newLocalUnions view current hits ≠ []) :
    check? view current text hits = none := by
  simp [check?, changed]

theorem TerminalRoot.changed_projection_rejected (view : RunView) (current : Value)
    (text : String) (hits : List Match)
    (changed : projectMatches view.graph (addMatches [] hits) ≠ view.graph) :
    check? view current text hits = none := by
  simp [check?, changed]

theorem TerminalRoot.changed_demand_rejected (view : RunView) (current : Value)
    (text : String) (hits : List Match)
    (changed : rootContinuation? view.graph view.quotient.toEquality current text (addMatches [] hits) ≠ none) :
    check? view current text hits = none := by
  simp [check?, changed]

/--
Candidate discovery, Run-local equality, quotient rebuilding, positive relation
projection, and Extract share one graph. Discovery authority remains run-local;
an observer may retain checked acceleration instructions at completed boundaries.
-/
def extractAt (view : RunView) (policy : OutcomePolicy) (current : Value)
    (fuel : Option Nat) : Extraction :=
  match fuel with
  | none => view.extractWith policy current
  | some fuel => Extract.runWithPolicyFuel view.graph view.quotient.toEquality policy fuel current

/-- One discovery controller owns both the reference calculation and lazy IO.
The loader may extend the original-owner projection only at a demanded match
boundary. It cannot replace the Union, continuation or extraction rules. -/
def discoverUsingM? {m : Type → Type} [Monad m] {σ : Type}
    (initial : σ) (all : List AllEdge) (sourceOwners : σ → List OutcomeEdge)
    (storedValues : σ → List Value)
    (depth : σ → WorkGraph → Option Nat)
    (evaluate : σ → RunView → List Value → m (σ × List Match))
    (inquiry : Value) (persistent : List UnionEdge) (currentText : String)
    (iterations : Nat) (enableLocalUnion : Bool)
    (views : IncrementalQuotient.ViewProvider := IncrementalQuotient.ViewProvider.reference)
    (recordView : List Value → RunView → m _root_.Unit := fun _ _ => pure ())
    (recordPlan : List Value → RunView → Option QuotientBuilder.CongruenceMemo.Entry → m _root_.Unit :=
      fun _ _ _ => pure ())
    (sourceAll : σ → List AllEdge := fun _ => all)
    (prepare : σ → List UnionEdge → List AllEdge → m σ := fun state _ _ => pure state) :
    m (Option Discovery) := do
  let sourceGraph := fun state : σ => ({ all := sourceAll state, outcomes := sourceOwners state } : WorkGraph)
  let current := Value.text currentText
  let roots (state : σ) (localUnions : List UnionEdge) (runAll : List AllEdge) :=
    current :: storedValues state ++ localUnions.flatMap (fun edge =>
      [edge.left, edge.right]) ++ runAll.map (·.relation)
  let rec saturate : IncrementalQuotient.ViewProvider → Nat → Nat → σ → (localUnions : List UnionEdge) → List AllEdge →
      List Match →
      Option (QuotientBuilder.AtomQuotient.Index (persistent ++ localUnions)) → m (Option Discovery)
    | _, 0, _, _, _, _, _, _ => pure none
    | views, fuel + 1, passes, state, localUnions, runAll, accumulated, index => do
        let state ← prepare state localUnions runAll
        let base := sourceGraph state
        let graph := projectMatches { base with all := runAll ++ base.all } accumulated
        let currentRoots := roots state localUnions runAll
        let produced := views graph currentRoots persistent localUnions index
        let some view := produced.val | return none
        let nextViews := IncrementalQuotient.ViewProvider.advance views produced.plan
        recordPlan currentRoots view produced.plan
        recordView currentRoots view
        let policy := OutcomePolicy.admitted (admissions accumulated)
        let demanded := (extractAt view policy current (depth state graph)).discovery
        let matchable := demanded.filter fun task =>
          !HandoffRemainder.isValue task && freshDemand current runAll task
        let (state, passHits) ← evaluate state view matchable
        /-
        Retrieval-only mode keeps the identical candidate and graph projection
        lanes, but grants neither equality nor work erasure. Marking every hit
        retrieved makes that causal boundary explicit in the existing judgment.
        -/
        let passHits := if enableLocalUnion then passHits else
          passHits.map fun matched => { matched with retrieved := true }
        let accumulated := addMatches accumulated passHits
        let proposed := if enableLocalUnion then
          newLocalUnions view inquiry passHits else []
        if !proposed.isEmpty then
          let nextIndex := index.bind fun previous => by
            simpa only [List.append_assoc] using previous.append? proposed
          saturate nextViews fuel (passes + 1) state (localUnions ++ proposed) runAll accumulated nextIndex
        else
          let proposedAll := match rootContinuation? graph view.quotient.toEquality
              current currentText accumulated with
            | some edge => [edge]
            | none => []
          /-
          Only an All that connects another Work subtree can expose new Demand.
          The remainder-only frame is installed in the final view without
          feeding its synthetic open leaf back into the same matcher run.
          -/
          let bridges := proposedAll.filter (fun edge => edge.children.length > 1)
          let nextRunAll := addContinuations runAll bridges
          let newAll := nextRunAll.length != runAll.length
          if newAll then
            saturate nextViews fuel (passes + 1) state localUnions nextRunAll accumulated index
          else
            let finalRunAll := addContinuations runAll proposedAll
            let state ← prepare state localUnions finalRunAll
            let finalBase := sourceGraph state
            let finalGraph := projectMatches
              { finalBase with all := finalRunAll ++ finalBase.all } accumulated
            let finalRoots := roots state localUnions finalRunAll
            let produced := nextViews finalGraph finalRoots persistent localUnions index
            let some finalView := produced.val | return none
            recordView finalRoots finalView
            recordPlan finalRoots finalView produced.plan
            pure (some {
              view := finalView
              hits := accumulated
              current
              passes
              extractionFuel := depth state finalGraph
            })
  saturate views iterations 0 initial [] [] []
    ((QuotientBuilder.AtomQuotient.prepare persistent).map (·.beginRun))

/-- The whole production loop, not just sampled representatives, is unchanged
by a certified view provider. Includes every pass and final extraction view. -/
theorem discoverUsingM_views_exact {m : Type → Type} [Monad m] {σ : Type}
    (initial : σ) (all : List AllEdge) (sourceOwners : σ → List OutcomeEdge)
    (storedValues : σ → List Value) (depth : σ → WorkGraph → Option Nat)
    (evaluate : σ → RunView → List Value → m (σ × List Match))
    (inquiry : Value) (persistent : List UnionEdge) (currentText : String)
    (iterations : Nat) (enableLocalUnion : Bool) (views : IncrementalQuotient.ViewProvider)
    (recordView : List Value → RunView → m _root_.Unit := fun _ _ => pure ())
    (sourceAll : σ → List AllEdge := fun _ => all)
    (prepare : σ → List UnionEdge → List AllEdge → m σ := fun state _ _ => pure state) :
    discoverUsingM? initial all sourceOwners storedValues depth evaluate inquiry persistent
      currentText iterations enableLocalUnion views recordView (fun _ _ _ => pure ()) sourceAll prepare =
    discoverUsingM? initial all sourceOwners storedValues depth evaluate inquiry persistent
      currentText iterations enableLocalUnion IncrementalQuotient.ViewProvider.reference recordView
        (fun _ _ _ => pure ()) sourceAll prepare := by
  unfold discoverUsingM?
  let sourceGraph := fun state : σ => ({all := sourceAll state, outcomes := sourceOwners state} : WorkGraph)
  let current := Value.text currentText
  let roots := fun (state : σ) (localUnions : List UnionEdge) (runAll : List AllEdge) =>
    current :: storedValues state ++ localUnions.flatMap (fun edge => [edge.left, edge.right]) ++
      runAll.map (·.relation)
  have loop (views : IncrementalQuotient.ViewProvider) (fuel passes : Nat) (state : σ) (localUnions : List UnionEdge)
      (runAll : List AllEdge) (accumulated : List Match)
      (index : Option (QuotientBuilder.AtomQuotient.Index (persistent ++ localUnions))) :
      discoverUsingM?.saturate depth evaluate inquiry persistent currentText enableLocalUnion
        recordView (fun _ _ _ => pure ()) prepare
        sourceGraph current roots views fuel passes state localUnions runAll accumulated index =
      discoverUsingM?.saturate depth evaluate inquiry persistent currentText enableLocalUnion
        recordView (fun _ _ _ => pure ()) prepare sourceGraph current roots
        IncrementalQuotient.ViewProvider.reference fuel passes state localUnions runAll accumulated index := by
    induction fuel generalizing views passes state localUnions runAll accumulated index with
    | zero => rfl
    | succ fuel ih =>
        simp only [discoverUsingM?.saturate, IncrementalQuotient.ViewProvider.result_exact,
          IncrementalQuotient.ViewProvider.reference_plan, IncrementalQuotient.ViewProvider.advance_none, ih]
  exact loop views iterations 0 initial [] [] [] _

def discoverInUsing? (normalize : Normalizer) (demands : DemandProvider normalize)
    (cover : CoverageProvider) (inquiry : Value)
    (storedValues : List Value) (persistent : List UnionEdge)
    (base : WorkGraph) (corpus : Corpus) (currentText : String)
    (evidenceText : Option String := none) (semantic : SemanticNominations := {})
    (enableLocalUnion : Bool := true) (currentNative : Bool := false)
    (views : IncrementalQuotient.ViewProvider := IncrementalQuotient.ViewProvider.reference) :
    Option Discovery :=
  let semanticBound := (.text currentText :: storedValues).flatMap Value.semanticNodes
    |> hashDistinct |>.length
  discoverUsingM? (m := Id) () base.all (fun _ => base.outcomes)
    (fun _ => storedValues) (fun _ _ => none)
    (fun state view tasks => (state, demandedMatchesUsing normalize demands cover corpus view
      (.text currentText) evidenceText semantic currentNative tasks))
    inquiry persistent currentText ((semanticBound + 1) * (base.outcomes.length + 1) + 1)
    enableLocalUnion views

theorem discoverInUsing_views_exact (normalize : Normalizer) (demands : DemandProvider normalize)
    (cover : CoverageProvider) (inquiry : Value) (storedValues : List Value)
    (persistent : List UnionEdge) (base : WorkGraph) (corpus : Corpus) (currentText : String)
    (evidenceText : Option String) (semantic : SemanticNominations)
    (enableLocalUnion currentNative : Bool) (views : IncrementalQuotient.ViewProvider) :
    discoverInUsing? normalize demands cover inquiry storedValues persistent base corpus currentText
      evidenceText semantic enableLocalUnion currentNative views =
    discoverInUsing? normalize demands cover inquiry storedValues persistent base corpus currentText
      evidenceText semantic enableLocalUnion currentNative := by
  unfold discoverInUsing?
  exact discoverUsingM_views_exact ..

def discoverIn? (normalize : Normalizer) (inquiry : Value)
    (storedValues : List Value) (persistent : List UnionEdge)
    (base : WorkGraph) (corpus : Corpus) (currentText : String)
    (evidenceText : Option String := none) (semantic : SemanticNominations := {})
    (enableLocalUnion : Bool := true) (currentNative : Bool := false)
    (views : IncrementalQuotient.ViewProvider := IncrementalQuotient.ViewProvider.reference) :
    Option Discovery :=
  discoverInUsing? normalize (CompiledDemand.make normalize) pairedCoverages inquiry storedValues persistent base corpus
    currentText evidenceText semantic enableLocalUnion currentNative views

/-- The terminal constructor produces the same first fixed point as the
actual discovery loop. Neither a heuristic iteration limit nor a selected-id
comparison substitutes for equality of the complete Discovery result. -/
theorem TerminalRoot.discovery_exact (normalize : Normalizer)
    (demands : DemandProvider normalize) (cover : CoverageProvider)
    (storedValues : List Value) (persistent : List UnionEdge)
    (view : RunView) (corpus : Corpus) (text : String)
    (evidence : Option String) (native : Bool)
    (terminal : TerminalRoot view (.text text) text)
    (initial : IncrementalQuotient.make? view.graph (.text text :: storedValues)
      persistent [] ((QuotientBuilder.AtomQuotient.prepare persistent).map (·.beginRun)) = some view)
    (matchedExact : demandedMatchesUsing normalize demands cover corpus view (.text text)
      evidence {} native [.text text] = terminal.hits) :
    discoverInUsing? normalize demands cover (.text text) storedValues persistent view.graph
      corpus text evidence {} true native = some terminal.discovery := by
  have root := Extract.runWithPolicy_unadmitted_root view.graph view.quotient.toEquality
    (.text text) terminal.rootUnchanged
  have projectEmpty (graph : WorkGraph) : projectMatches graph [] = graph := rfl
  have one : [Value.text text].eraseDups = [Value.text text] := rfl
  simp [discoverInUsing?, discoverUsingM?, discoverUsingM?.saturate, bind, pure, extractAt, projectEmpty,
    IncrementalQuotient.ViewProvider.result_exact,
    initial, admissions, RunView.extractWith, root, one,
    Extraction.fromSelection, Extraction.finalize, Selection.openWork,
    freshDemand, terminal.fresh, matchedExact, terminal.unionsUnchanged,
    terminal.ownersUnchanged, terminal.continuationUnchanged,
    addContinuations, TerminalRoot.discovery]

theorem discoverInUsing_exact (normalize : Normalizer) (demands : DemandProvider normalize)
    (demandExact : demands = CompiledDemand.make normalize) (cover : CoverageProvider)
    (exact : cover = pairedCoverages) : discoverInUsing? normalize demands cover = discoverIn? normalize := by
  subst cover
  subst demands
  rfl

/-- Convenience boundary for callers without a reusable daemon-side corpus. -/
def discover? (normalize : Normalizer) (inquiry : Value)
    (storedValues : List Value) (persistent : List UnionEdge)
    (currentText : String) : Option Discovery :=
  let base := WorkGraph.fromValues storedValues
  discoverIn? normalize inquiry storedValues persistent base
    (Corpus.build normalize base) currentText none {}

def extraction (discovery : Discovery) : Extraction :=
  extractAt discovery.view discovery.policy discovery.current discovery.extractionFuel

theorem extraction_sound (discovery : Discovery) :
    (extraction discovery).selection.validFor discovery.view.graph
      discovery.view.quotient.toEquality discovery.policy discovery.current := by
  cases fuelEq : discovery.extractionFuel with
  | none =>
      simpa only [extraction, extractAt, fuelEq, RunView.extractWith] using
        Extract.runWithPolicy_sound discovery.view.graph discovery.view.quotient.toEquality
          discovery.policy discovery.current
  | some fuel =>
      simpa only [extraction, extractAt, fuelEq] using
        Extract.runWithPolicyFuel_sound discovery.view.graph discovery.view.quotient.toEquality
          discovery.policy fuel discovery.current

theorem completed_match_is_forward_and_reusable {matched : Match}
    (completed : matched.judgment.delivery = .completed) :
    matched.judgment.direction = .pastWorkInsideCurrentDemand ∧
      matched.judgment.reusableOutcome = true :=
  ApplicabilityJudgment.completed_only_for_forward_reusable completed

theorem completed_match_has_local_subwork {matched : Match}
    (completed : matched.judgment.delivery = .completed) :
    matched.work.fragmentIdentity = true ∧ matched.work.subwork = true ∧
      ((matched.work.pastWholeWork = true ∧
          matched.work.priorInDemand.complete = true) ∨
        (matched.groundedOutcomeFragment = true ∧
          (matched.work.priorInDemand.complete = true ∨
            matched.work.demandInPrior.complete = true))) ∧
      (matched.projectedEdge = matched.edge ∨
        matched.edge.relation ∈ matched.projectedEdge.observations) := by
  unfold Match.judgment at completed
  split at completed
  · simp [ApplicabilityJudgment.delivery] at completed
  · unfold Match.workJudgment at completed
    have reusable := fragment_completion_requires_local_identity _ _ _ _ _ _ completed
    exact ⟨reusable.1, reusable.2.1, reusable.2.2,
      Match.projectedEdge_has_owner_provenance matched⟩

/--
End-to-end connection theorem: every Work erased by Matcher→Extract comes from
an automatic Match over an existing Outcome owner and passed the forward,
reusable applicability gate. Candidate similarity alone is insufficient.
-/
theorem extraction_completed_has_match {discovery : Discovery} {demand : Value}
    {edge : OutcomeEdge}
    (used : (demand, edge) ∈
      (extraction discovery).selection.completedUses) :
    ∃ matched ∈ discovery.hits,
      matched.automatic = true ∧ matched.projectionWork = demand ∧
      matched.projectedEdge.relation = edge.relation ∧
      matched.judgment.direction = .pastWorkInsideCurrentDemand ∧
      matched.judgment.reusableOutcome = true ∧
      matched.work.fragmentIdentity = true ∧
      matched.work.subwork = true ∧
      ((matched.work.pastWholeWork = true ∧
          matched.work.priorInDemand.complete = true) ∨
        (matched.groundedOutcomeFragment = true ∧
          (matched.work.priorInDemand.complete = true ∨
            matched.work.demandInPrior.complete = true))) ∧
      (matched.projectedEdge = matched.edge ∨
        matched.edge.relation ∈ matched.projectedEdge.observations) ∧
      edge.outcome ∈ (extraction discovery).priorOutcomes := by
  have valid := extraction_sound discovery
  have sound := Selection.completedUse_sound valid used
  obtain ⟨admission, member, demandEq, relationEq, delivered⟩ :=
    OutcomePolicy.admitted_delivery_witness sound.2.2 (by decide)
  obtain ⟨matched, hit, automatic, matchDemand, matchRelation, matchJudgment⟩ :=
    admission_has_automatic_match member
  have completed : matched.judgment.delivery = .completed := by
    rw [← matchJudgment, delivered]
  have applicable := completed_match_is_forward_and_reusable completed
  have grounded := completed_match_has_local_subwork completed
  exact ⟨matched, hit, automatic, matchDemand.symm.trans demandEq,
    matchRelation.symm.trans relationEq, applicable.1, applicable.2,
    grounded.1, grounded.2.1, grounded.2.2.1, grounded.2.2.2,
    (extraction discovery).prior_visible _
      (Selection.completedUse_outcome_is_prior used)⟩

/-- Advisory delivery is likewise selected Match data, never free-floating retrieval. -/
theorem extraction_advisory_has_match {discovery : Discovery} {demand : Value}
    {edge : OutcomeEdge}
    (used : (demand, edge) ∈
      (extraction discovery).selection.advisoryUses) :
    ∃ matched ∈ discovery.hits,
      matched.automatic = true ∧ matched.projectionWork = demand ∧
      matched.projectedEdge.relation = edge.relation ∧
      matched.judgment.delivery = .advisory := by
  have valid := extraction_sound discovery
  have sound := Selection.advisoryUse_sound valid used
  obtain ⟨admission, member, demandEq, relationEq, delivered⟩ :=
    OutcomePolicy.admitted_delivery_witness sound.2.2 (by decide)
  obtain ⟨matched, hit, automatic, matchDemand, matchRelation, matchJudgment⟩ :=
    admission_has_automatic_match member
  exact ⟨matched, hit, automatic, matchDemand.symm.trans demandEq,
    matchRelation.symm.trans relationEq, matchJudgment ▸ delivered⟩

end Eggshell.Matcher
