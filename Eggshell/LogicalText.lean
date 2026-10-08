module

public import Std
public import Init.Data.String.Lemmas.Iterate

@[expose] public section

namespace Eggshell.LogicalText

/-- Half-open UTF-8 byte range. -/
structure ByteSpan where
  start : Nat
  stop : Nat
  deriving Repr, DecidableEq, BEq, Hashable, Ord

namespace ByteSpan

def valid (span : ByteSpan) : Bool := span.start < span.stop

def touches (left right : ByteSpan) : Bool :=
  left.start ≤ right.stop && right.start ≤ left.stop

def merge (left right : ByteSpan) : ByteSpan :=
  { start := Nat.min left.start right.start, stop := Nat.max left.stop right.stop }

end ByteSpan

/--
One normalized grapheme together with the exact source bytes that produced it.
Normalization is an input to the matcher, so the semantic algorithm and its
proofs do not depend on an operating-system Unicode implementation.
-/
structure Piece where
  text : String
  source : ByteSpan
  deriving Repr, DecidableEq

abbrev Normalizer := String → List Piece

def asciiWordCharacter (character : Char) : Bool :=
  character.val < 128 && (character.isAlphanum || character = '_')

def asciiCompoundCharacter (character : Char) : Bool :=
  asciiWordCharacter character || character = '/' || character = '.'

def dropTrailingDots (characters : List Char) : List Char :=
  (characters.reverse.dropWhile (· = '.')).reverse

/--
Code paths and dotted identifiers are one logical unit. A leading `./` is only
relative-shell spelling, and sentence-final dots carry no identity.
-/
def canonicalAsciiCompound (text : String) : String :=
  let characters := if text.startsWith "./" then text.toList.drop 2 else text.toList
  String.ofList (dropTrailingDots characters)

/--
Natural-language matching uses logical tokens, not coincident characters.
ASCII words are units, while paths and dotted identifiers remain indivisible
compound units; other ASCII syntax is a boundary. Non-ASCII scalars remain
units so unsegmented scripts need no language-specific tokenizer. Every unit
retains its exact source bytes.
-/
@[inline] def normalizeCharacters {ρ : Type} [ForIn Id ρ Char] (characters : ρ) : List Piece := Id.run do
  let mut pieces : Array Piece := #[]
  let mut word := ""
  let mut wordStart := 0
  let mut wordBytes := 0
  let mut offset := 0
  for character in characters do
    let original := String.singleton character
    let bytes := original.toUTF8.size
    if asciiCompoundCharacter character then
      if word.isEmpty then wordStart := offset
      word := word ++ original.toLower
      wordBytes := wordBytes + bytes
    else
      if !word.isEmpty then
        pieces := pieces.push {
          text := canonicalAsciiCompound word
          source := { start := wordStart, stop := wordStart + wordBytes }
        }
        word := ""
        wordBytes := 0
      pieces := pieces.push {
        text := if character.val < 128 || character.isWhitespace then " "
          else original.toLower
        source := { start := offset, stop := offset + bytes }
      }
    offset := offset + bytes
  if !word.isEmpty then
    pieces := pieces.push {
      text := canonicalAsciiCompound word
      source := { start := wordStart, stop := wordStart + wordBytes }
    }
  return pieces.toList

/-- Iterate the original UTF-8 string directly. No full character array or
linked list is allocated before normalization begins. -/
def logicalNormalizer : Normalizer := fun text => normalizeCharacters text

/-- Exact units and byte provenance for every valid String, including Unicode
and arbitrary token lengths; iteration does not impose a text-size limit. -/
theorem logicalNormalizer_list_exact (text : String) :
    logicalNormalizer text = normalizeCharacters text.toList := by
  simp only [logicalNormalizer, normalizeCharacters, String.forIn_eq_forIn_toList]

structure Unit where
  logical : ByteSpan
  source : ByteSpan
  text : String
  deriving Repr, DecidableEq, BEq, Hashable

structure T where
  original : String
  text : String
  units : List Unit
  deriving Repr, DecidableEq, BEq, Hashable

def whitespacePiece (piece : Piece) : Bool :=
  !piece.text.isEmpty && piece.text.toList.all Char.isWhitespace

def build (normalize : Normalizer) (original : String) : T :=
  Id.run do
    let mut output := ByteArray.empty
    let mut units : Array Unit := #[]
    let mut pendingSpace := false
    for piece in normalize original do
      if whitespacePiece piece then
        pendingSpace := true
      else if !piece.text.isEmpty then
        if pendingSpace && !output.isEmpty && output.get! (output.size - 1) != 32 then
          output := output.push 32
        let start := output.size
        let bytes := piece.text.toUTF8
        output := output ++ bytes
        units := units.push {
          logical := { start, stop := start + bytes.size }
          source := piece.source
          text := piece.text
        }
        pendingSpace := false
    return {
      original
      text := (String.fromUTF8? output).getD ""
      units := units.toList
    }

def logical (original : String) : T := build logicalNormalizer original

def isEmpty (text : T) : Bool := text.units.isEmpty

def byteSlice? (text : String) (span : ByteSpan) : Option String := do
  if span.start ≥ span.stop || span.stop > text.toUTF8.size then none else
  String.fromUTF8? (text.toUTF8.extract span.start span.stop)

def logicalSlice? (text : T) (span : ByteSpan) : Option String :=
  byteSlice? text.text span

def sourceSlice? (text : T) (span : ByteSpan) : Option String :=
  byteSlice? text.original span

/-- Materialize UTF-8 once for a repeated positional scan. The original
source remains in the erased index; a buffer from another text cannot be
passed as its prepared slicing capability. -/
structure ByteSource (text : String) where
  bytes : ByteArray
  exact : bytes = text.toUTF8

def ByteSource.make (text : String) : ByteSource text := ⟨text.toUTF8, rfl⟩

def ByteSource.slice? (source : ByteSource text) (span : ByteSpan) : Option String :=
  if span.start ≥ span.stop || span.stop > source.bytes.size then none else
    String.fromUTF8? (source.bytes.extract span.start span.stop)

/-- Includes invalid, reversed, empty, out-of-bounds and non-scalar UTF-8
ranges. No valid-normalizer premise is needed to avoid repeated conversion. -/
theorem ByteSource.slice_exact (source : ByteSource text) (span : ByteSpan) :
    source.slice? span = byteSlice? text span := by
  unfold slice? byteSlice?
  rw [source.exact]

def unitsIn (text : T) (span : ByteSpan) : List Nat :=
  let rec visit : List Unit → Nat → List Nat
    | [], _ => []
    | unit :: tail, ordinal =>
        let rest := visit tail (ordinal + 1)
        if span.start ≤ unit.logical.start && unit.logical.stop ≤ span.stop then
          ordinal :: rest
        else rest
  visit text.units 0

def envelope? : List ByteSpan → Option ByteSpan
  | [] => none
  | head :: tail => some (tail.foldl ByteSpan.merge head)

def sourceSpan? (text : T) (logical : ByteSpan) : Option ByteSpan :=
  unitsIn text logical |>.filterMap (text.units[·]? |>.map (·.source)) |> envelope?

def coalesce (spans : List ByteSpan) : List ByteSpan :=
  let ordered := (spans.toArray.mergeSort fun left right =>
    left.start < right.start || (left.start = right.start && left.stop ≤ right.stop)).toList
  match ordered with
  | [] => []
  | head :: tail =>
      (tail.foldl (fun reversed next =>
        match reversed with
        | [] => [next]
        | current :: rest =>
            if current.touches next then current.merge next :: rest
            else next :: reversed) [head]).reverse

/-- Exact source pieces selected by logical evidence, without unmatched gaps. -/
def sourceSpans? (text : T) (logicalSpans : List ByteSpan) : Option (List ByteSpan) := do
  let spans := logicalSpans.filterMap (sourceSpan? text) |> coalesce
  if spans.isEmpty then none else pure spans

def sourceEnvelope? (text : T) (logicalSpans : List ByteSpan) : Option ByteSpan := do
  envelope? (← sourceSpans? text logicalSpans)

def unitSpan? (text : T) (first width : Nat) : Option ByteSpan := do
  if width = 0 then none else
  let head ← text.units[first]?
  let last ← text.units[first + width - 1]?
  pure { start := head.logical.start, stop := last.logical.stop }

/-- Random access into a prepared unit table; no prefix traversal per anchor. -/
def indexedUnitSpan? (units : Array Unit) (first width : Nat) : Option ByteSpan := do
  if width = 0 then none else
  let head ← units[first]?
  let last ← units[first + width - 1]?
  pure { start := head.logical.start, stop := last.logical.stop }

theorem indexedUnitSpan_exact (text : T) (first width : Nat) :
    indexedUnitSpan? text.units.toArray first width = unitSpan? text first width := by
  simp only [indexedUnitSpan?, unitSpan?, List.getElem?_toArray]

structure Gram where
  span : ByteSpan
  first : Nat
  last : Nat
  text : String
  deriving Repr, DecidableEq

/-- Keep byte slicing and ordinal construction identical for every width. -/
def gramsAt (text : T) (units : Array Unit) (width : Nat) : List Gram :=
    if width > units.size then [] else
    let source := ByteSource.make text.text
    (List.range (units.size - width + 1)).filterMap fun first => do
      let span ← indexedUnitSpan? units first width
      let surface ← source.slice? span
      pure { span, first, last := first + width, text := surface }

/-- All one-to-three-unit anchors, longest first. -/
def grams (text : T) : List Gram :=
  let units := text.units.toArray
  [3, 2, 1].flatMap (gramsAt text units)

/-- The actual indexed implementation preserves every anchor and its order,
including invalid byte ranges, empty units and arbitrary normalizer output. -/
theorem grams_exact (text : T) :
    grams text = [3, 2, 1].flatMap (fun width =>
      if width > text.units.length then [] else
      (List.range (text.units.length - width + 1)).filterMap fun first => do
        let span ← unitSpan? text first width
        let surface ← logicalSlice? text span
        pure { span, first, last := first + width, text := surface }) := by
  simp only [grams, List.flatMap_cons, List.flatMap_nil, gramsAt,
    List.size_toArray, indexedUnitSpan_exact, ByteSource.slice_exact]
  rfl

theorem gramsAt_width {text : T} {units : Array Unit} {width : Nat} {gram : Gram}
    (present : gram ∈ gramsAt text units width) : gram.last = gram.first + width := by
  unfold gramsAt at present
  split at present
  · simp at present
  · obtain ⟨first, _, occurrence⟩ := List.mem_filterMap.mp present
    cases spanFound : indexedUnitSpan? units first width with
    | none => simp [spanFound] at occurrence
    | some span =>
        simp only [ByteSource.slice_exact] at occurrence
        cases surfaceFound : byteSlice? text.text span with
        | none => simp [spanFound, surfaceFound] at occurrence
        | some surface =>
          simp [spanFound, surfaceFound] at occurrence
          cases occurrence
          rfl

/-- Shared search representation. Persistence and the matcher use the same
gram-key constructor, so nomination cannot disagree about punctuation,
normalization or overlapping unit boundaries. -/
structure IndexedSpan where
  span : ByteSpan
  first : Nat
  last : Nat
  deriving Repr, DecidableEq, BEq, Hashable

abbrev SurfaceIndex := Std.HashMap String (List IndexedSpan)

def indexGrams (items : List Gram) (initial : SurfaceIndex := {}) : SurfaceIndex :=
  items.foldl (fun index gram =>
    let span : IndexedSpan := { span := gram.span, first := gram.first, last := gram.last }
    index.insert gram.text (span :: index.getD gram.text [])) initial

def surfaceIndex (text : T) : SurfaceIndex := indexGrams (grams text)

/-- Context consumes single units, never two/three-unit Work anchors. -/
def contextSurfaceIndex (text : T) : SurfaceIndex :=
  indexGrams (gramsAt text text.units.toArray 1)

def singleUnit (span : IndexedSpan) : Bool := span.last = span.first + 1

/-- Lookup specification includes the reverse occurrence order of the stored
index. It does not assume normalizer output has valid or disjoint spans. -/
theorem indexGrams_lookup (items : List Gram) (initial : SurfaceIndex) (key : String) :
    (indexGrams items initial).getD key [] =
      (items.filterMap fun gram =>
        if gram.text == key then
          some ({ span := gram.span, first := gram.first, last := gram.last } : IndexedSpan)
        else none).reverse ++ initial.getD key [] := by
  induction items generalizing initial with
  | nil => simp [indexGrams]
  | cons gram rest ih =>
    simp only [indexGrams, List.foldl_cons]
    rw [← indexGrams, ih, Std.HashMap.getD_insert]
    by_cases matchKey : gram.text = key
    · subst key
      simp only [BEq.rfl, ↓reduceIte, List.filterMap_cons, List.reverse_cons,
        List.append_assoc, List.singleton_append]
    · simp only [show (gram.text == key) = false from beq_eq_false_iff_ne.mpr matchKey,
        Bool.false_eq_true, ↓reduceIte, List.filterMap_cons]

theorem gramsAt_lookup_single (text : T) (units : Array Unit) (width : Nat) (key : String) :
    ((gramsAt text units width).filterMap fun gram =>
      if gram.text == key then
        some ({ span := gram.span, first := gram.first, last := gram.last } : IndexedSpan)
      else none).filter singleUnit =
    if width = 1 then
      (gramsAt text units width).filterMap fun gram =>
        if gram.text == key then
          some ({ span := gram.span, first := gram.first, last := gram.last } : IndexedSpan)
        else none
    else [] := by
  split
  · rename_i equal
    apply List.filter_eq_self.mpr
    intro span present
    obtain ⟨gram, member, occurrence⟩ := List.mem_filterMap.mp present
    have ordinals := gramsAt_width member
    split at occurrence
    · simp only [Option.some.injEq] at occurrence
      cases occurrence
      simpa [singleUnit, equal] using ordinals
    · simp at occurrence
  · rename_i different
    apply List.filter_eq_nil_iff.mpr
    intro span present
    obtain ⟨gram, member, occurrence⟩ := List.mem_filterMap.mp present
    have ordinals := gramsAt_width member
    split at occurrence
    · simp only [Option.some.injEq] at occurrence
      cases occurrence
      simp only [singleUnit, ordinals, decide_eq_true_eq]
      omega
    · simp at occurrence

/-- The smaller context directory is the complete unit-only projection of
the full Work directory, including repeated units and their exact order. -/
theorem contextSurfaceIndex_exact (text : T) (key : String) :
    (contextSurfaceIndex text).getD key [] =
      ((surfaceIndex text).getD key []).filter singleUnit := by
  simp only [contextSurfaceIndex, surfaceIndex, indexGrams_lookup, Std.HashMap.getD_empty,
    List.append_nil, grams, List.flatMap_cons, List.flatMap_nil, List.filterMap_append,
    List.reverse_append, List.filter_append, List.filter_reverse]
  rw [gramsAt_lookup_single, gramsAt_lookup_single, gramsAt_lookup_single]
  simp

/-- A tail-recursive ordinal fold does not allocate a list of every position.
The list interpreter exists only in the erased refinement proof. -/
def foldPositions {α : Type} (step : α → Nat → α) (first : Nat) : Nat → α → α
  | 0, state => state
  | count + 1, state => foldPositions step (first + 1) count (step state first)

theorem foldPositions_exact {α : Type} (step : α → Nat → α)
    (first count : Nat) (state : α) :
    foldPositions step first count state = (List.range' first count).foldl step state := by
  induction count generalizing first state with
  | zero => simp [foldPositions]
  | succ count ih => simp [foldPositions, List.range'_succ, ih]

def contextGram? (text : T) (units : Array Unit) (first : Nat) : Option Gram := do
  let span ← indexedUnitSpan? units first 1
  let surface ← logicalSlice? text span
  pure { span, first, last := first + 1, text := surface }

def contextGramUsing? {text : T} (source : ByteSource text.text) (units : Array Unit)
    (first : Nat) : Option Gram := do
  let span ← indexedUnitSpan? units first 1
  let surface ← source.slice? span
  pure { span, first, last := first + 1, text := surface }

theorem contextGramUsing_exact (text : T) (source : ByteSource text.text)
    (units : Array Unit) (first : Nat) :
    contextGramUsing? source units first = contextGram? text units first := by
  simp only [contextGramUsing?, contextGram?, ByteSource.slice_exact, logicalSlice?]

def requestedGramStep (wanted : Std.HashSet String) (index : SurfaceIndex)
    (gram : Gram) : SurfaceIndex :=
  if wanted.contains gram.text then
    index.insert gram.text ({span := gram.span, first := gram.first, last := gram.last} ::
      index.getD gram.text [])
  else index

def optionalGramStep (wanted : Std.HashSet String) (index : SurfaceIndex)
    (gram : Option Gram) : SurfaceIndex :=
  gram.elim index (requestedGramStep wanted index)

theorem optionalGramStep_fold (wanted : Std.HashSet String) (positions : List Nat)
    (read : Nat → Option Gram) (initial : SurfaceIndex) :
    positions.foldl (fun index first => optionalGramStep wanted index (read first)) initial =
      (positions.filterMap read).foldl (requestedGramStep wanted) initial := by
  induction positions generalizing initial with
  | nil => rfl
  | cons first rest ih =>
      cases observed : read first with
      | none =>
          simp only [List.foldl_cons, List.filterMap_cons, observed]
          exact ih initial
      | some gram =>
          simp only [List.foldl_cons, List.filterMap_cons, observed]
          exact ih (requestedGramStep wanted initial gram)

/-- Only requested unit keys are retained. Occurrences preserve the complete
original reverse order, including duplicate and malformed logical spans. -/
def contextDemandIndex (text : T) (wanted : Std.HashSet String) : SurfaceIndex :=
  let units := text.units.toArray
  let source := ByteSource.make text.text
  foldPositions (fun index first => optionalGramStep wanted index
    (contextGramUsing? source units first)) 0 units.size {}

theorem requestedGramStep_lookup (wanted : Std.HashSet String) (items : List Gram)
    (initial : SurfaceIndex) (key : String) (requested : wanted.contains key = true) :
    (items.foldl (requestedGramStep wanted) initial).getD key [] =
      (indexGrams items initial).getD key [] := by
  induction items generalizing initial with
  | nil => rfl
  | cons gram rest ih =>
      simp only [List.foldl_cons]
      rw [ih]
      change (indexGrams rest (requestedGramStep wanted initial gram)).getD key [] =
        (indexGrams rest (initial.insert gram.text
          ({span := gram.span, first := gram.first, last := gram.last} :: initial.getD gram.text []))).getD key []
      rw [indexGrams_lookup, indexGrams_lookup]
      congr 1
      unfold requestedGramStep
      by_cases same : gram.text = key
      · simp [same, requested]
      · simp only [Std.HashMap.getD_insert]
        split <;> simp [Std.HashMap.getD_insert, same]

/-- Exact demanded lookup against the unchanged complete unit directory.
No promise that a hash identifies the source is used in this contract. -/
theorem contextDemandIndex_exact (text : T) (wanted : Std.HashSet String)
    (key : String) (requested : wanted.contains key = true) :
    (contextDemandIndex text wanted).getD key [] = (contextSurfaceIndex text).getD key [] := by
  unfold contextDemandIndex
  simp only [contextGramUsing_exact]
  rw [foldPositions_exact, ← List.range_eq_range', optionalGramStep_fold,
    requestedGramStep_lookup wanted _ _ key requested]
  unfold contextSurfaceIndex gramsAt
  split
  · have empty : text.units.toArray.size = 0 := by omega
    simp [empty, indexGrams]
  · have sameSize : text.units.toArray.size - 1 + 1 = text.units.toArray.size := by omega
    rw [sameSize]
    simp only [ByteSource.slice_exact]
    rfl

theorem requestedGramStep_unrequested (wanted : Std.HashSet String) (items : List Gram)
    (initial : SurfaceIndex) (key : String) (unrequested : wanted.contains key = false) :
    (items.foldl (requestedGramStep wanted) initial).getD key [] = initial.getD key [] := by
  induction items generalizing initial with
  | nil => rfl
  | cons gram rest ih =>
      simp only [List.foldl_cons]
      rw [ih]
      unfold requestedGramStep
      split
      · rename_i retained
        have different : gram.text ≠ key := by intro same; simp [same, unrequested] at retained
        simp [Std.HashMap.getD_insert, different]
      · rfl

/-- Unrequested words cannot occupy the demanded occurrence directory. -/
theorem contextDemandIndex_unrequested (text : T) (wanted : Std.HashSet String)
    (key : String) (unrequested : wanted.contains key = false) :
    (contextDemandIndex text wanted).getD key [] = [] := by
  unfold contextDemandIndex
  simp only [contextGramUsing_exact]
  rw [foldPositions_exact, optionalGramStep_fold,
    requestedGramStep_unrequested wanted _ _ key unrequested]
  simp

/-- Every demanded occurrence has width one, even for arbitrary normalizer
spans and negative lookups. This certificate permits consuming its queue
without filtering the entire remaining list on each repeated query word. -/
theorem contextDemandIndex_single (text : T) (wanted : Std.HashSet String)
    (key : String) (span : IndexedSpan)
    (present : span ∈ (contextDemandIndex text wanted).getD key []) :
    singleUnit span = true := by
  cases requested : wanted.contains key with
  | false =>
      rw [contextDemandIndex_unrequested text wanted key requested] at present
      contradiction
  | true =>
      rw [contextDemandIndex_exact text wanted key requested,
        contextSurfaceIndex_exact] at present
      exact (List.mem_filter.mp present).2

def surfaceKeys (index : SurfaceIndex) : Std.HashSet String :=
  index.fold (fun keys key _ => keys.insert key) {}

def surfaceNames (text : String) : List String :=
  (surfaceKeys (surfaceIndex (logical text))).toList

end Eggshell.LogicalText
