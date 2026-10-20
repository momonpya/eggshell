"""Reuse checked scalar-range decoding without changing list results."""
from context_candidate import once

TARGETS = '''
lean_lib ContextMemoResearch where
  roots := #[`tools.ExactMemo, `tools.IndexedCharacters]

lean_exe context_memo_tests where
  root := `tools.ContextMemoTests
'''
HELPERS = ['ExactMemo.lean', 'IndexedCharacters.lean', 'ContextMemoTests.lean']

RANGES = '''theorem EvidenceRange.coordinates_injective (left right : EvidenceRange source)
    (first : left.start = right.start) (last : left.stop = right.stop) : left = right := by
  cases left
  cases right
  cases first
  cases last
  rfl

instance : BEq (EvidenceRange source) where
  beq left right := left.start == right.start && left.stop == right.stop

instance : LawfulBEq (EvidenceRange source) where
  eq_of_beq := by
    intro left right same
    exact EvidenceRange.coordinates_injective left right
      (eq_of_beq (Bool.and_eq_true_iff.mp same).1) (eq_of_beq (Bool.and_eq_true_iff.mp same).2)
  rfl := by intro range; simp [BEq.beq]

instance : Hashable (EvidenceRange source) where
  hash range := hash (range.start, range.stop)

'''


def handoff(source):
    source = once(source, 'public import Eggshell.PluginModel\n',
        'public import Eggshell.PluginModel\npublic import tools.ExactMemo\npublic import tools.IndexedCharacters\n')
    source = once(source, '  widthsExact : widths = encodedCharacterWidths chars\n',
        '  widthsExact : widths = encodedCharacterWidths chars\n' +
        '  original : IndexedCharacters source\n  content : IndexedCharacters decoded.text\n')
    source = once(source, '  ⟨decoded, chars, rfl, encodedCharacterWidths chars, rfl⟩',
        '  ⟨decoded, chars, rfl, encodedCharacterWidths chars, rfl,\n' +
        '    IndexedCharacters.make source, ⟨chars.toArray, rfl⟩⟩')
    source = once(source, '''  | mk decoded chars charsExact widths widthsExact =>
    subst chars
    subst widths
    rfl''', '''  | mk decoded chars charsExact widths widthsExact original content =>
    subst chars
    subst widths
    rw [IndexedCharacters.is_canonical original, IndexedCharacters.is_canonical content]
    rfl''')
    lo = source.index('def decodedEvidenceUsing? (')
    hi = source.index('def decodedEvidence? (', lo)
    decoder = once(source[lo:hi], 'def decodedEvidenceUsing? (', 'def decodedEvidenceUsingIndexed? (')
    start = decoder.index('      if reencoded : encodedTextBody content.text = original.text then')
    first = decoder.index('\n', start) + 1
    stop = decoder.index('\n      else none', first)
    body = '\n'.join('  ' + line for line in decoder[first:stop].splitlines())
    decoder = decoder[:start] + '''      layout.content.branch₂ content.start (content.stop - content.start)
        layout.original original.start (original.stop - original.start)
        (fun left right => encodedTextBody left = right)
        (fun reencoded =>
''' + body + ''')
        (fun _ => none)''' + decoder[stop + len('\n      else none'):]
    decoder += '''@[csimp] theorem decodedEvidenceUsingIndexed_compiled :
    @decodedEvidenceUsing? = @decodedEvidenceUsingIndexed? := by
  funext source layout requested
  simp only [decodedEvidenceUsing?, decodedEvidenceUsingIndexed?,
    IndexedCharacters.branch₂_exact, EvidenceRange.text] <;> rfl

'''
    source = source[:hi] + decoder + source[hi:]
    lo = source.index('def prepareContextualOwnerPlan (')
    hi = source.index('theorem prepareContextualOwnerPlan_exact', lo)
    plan = once(source[lo:hi], '          let decoded := (decodedToolText? source).map DecodedLayout.make',
        '''          let decoded := (decodedToolText? source).map DecodedLayout.make
          let originalChars := match decoded with
            | some layout => layout.original
            | none => IndexedCharacters.make source''')
    plan = once(plan, 'original := view.range.text',
        'original := originalChars.slice view.range.start (view.range.stop - view.range.start)')
    source = source[:lo] + plan + source[hi:]
    source = once(source, 'simp only [prepareContextualOwnerPlan, prepareContextualOwnerPart, outcome, work]',
        'simp only [prepareContextualOwnerPlan, prepareContextualOwnerPart, outcome, work,\n' +
        '      IndexedCharacters.slice_exact, EvidenceRange.text]')
    source = once(source, 'def EvidenceRange.text (range : EvidenceRange source)',
        RANGES + 'def EvidenceRange.text (range : EvidenceRange source)')
    lo = source.index('def prepareContextViews (')
    hi = source.index('theorem prepared_context_views_bounded', lo)
    original = source[lo:hi]
    fast = once(original, 'def prepareContextViews (', 'def prepareContextViewsFast (')
    fast = once(fast, '  ranges.flatMap fun range =>', '  let candidates := ranges.flatMap fun range =>')
    fast = once(fast, '''    alternatives.filterMap fun candidate => match decoded with
      | none => some (EvidenceView.original candidate)
      | some value => (decodedEvidenceUsing? value candidate).map EvidenceView.decoded''',
        '''    alternatives
  ExactMemo.filterMap (fun candidate => match decoded with
    | none => some (EvidenceView.original candidate)
    | some value => (decodedEvidenceUsing? value candidate).map EvidenceView.decoded) candidates''')
    fast += '''@[csimp] theorem prepareContextViews_compiled : @prepareContextViews = @prepareContextViewsFast := by
  funext source records heads decoded ranges
  unfold prepareContextViews prepareContextViewsFast
  rw [ExactMemo.filterMap_exact]
  induction ranges with
  | nil => rfl
  | cons first rest ih => simp only [List.flatMap_cons, List.filterMap_append, ih]

'''
    source = source[:hi] + fast + source[hi:]
    lo = source.index('def prepareCueViews (')
    hi = source.index('/-- Overlap removal occurs', lo)
    fast = once(source[lo:hi], 'def prepareCueViews (', 'def prepareCueViewsFast (')
    fast = once(fast, '  (coverage ++ fallback ++ context).filterMap fun candidate => match decoded with',
        '  ExactMemo.filterMap (fun candidate => match decoded with')
    fast = once(fast, '(decodedEvidenceUsing? layout candidate).map EvidenceView.decoded',
        '(decodedEvidenceUsing? layout candidate).map EvidenceView.decoded) (coverage ++ fallback ++ context)')
    fast += '''@[csimp] theorem prepareCueViews_compiled : @prepareCueViews = @prepareCueViewsFast := by
  funext source records heads decoded ranges
  unfold prepareCueViews prepareCueViewsFast
  rw [ExactMemo.filterMap_exact]

'''
    return source[:hi] + fast + source[hi:]


def audit(source):
    source = once(source, '  for theoremName in #[', '''  for theoremName in #[``Eggshell.ExactMemo.map_exact,
      ``Eggshell.ExactMemo.filterMap_exact, ``Eggshell.Plugin.prepareContextViews_compiled,
      ``Eggshell.Plugin.prepareCueViews_compiled, ``Eggshell.IndexedCharacters.slice_exact,
      ``Eggshell.IndexedCharacters.decide₂_eq, ``Eggshell.Plugin.decodedEvidenceUsingIndexed_compiled,''')
    return source + '''
example : @Eggshell.Plugin.prepareContextViews = @Eggshell.Plugin.prepareContextViewsFast :=
  Eggshell.Plugin.prepareContextViews_compiled
example : @Eggshell.Plugin.prepareCueViews = @Eggshell.Plugin.prepareCueViewsFast :=
  Eggshell.Plugin.prepareCueViews_compiled
example : @Eggshell.Plugin.decodedEvidenceUsing? = @Eggshell.Plugin.decodedEvidenceUsingIndexed? :=
  Eggshell.Plugin.decodedEvidenceUsingIndexed_compiled

run_meta do
  let environment ← getEnv
  for caller in #[``Eggshell.Plugin.prepareContextViewsFast, ``Eggshell.Plugin.prepareCueViewsFast] do
    let some declaration := environment.find? caller | throwError "Missing memoized context caller"
    let some body := declaration.value? | throwError "Memoized context caller has no body"
    for required in #[``Eggshell.ExactMemo.filterMap, ``Eggshell.Plugin.decodedEvidenceUsing?] do
      unless body.getUsedConstants.contains required do
        throwError "Context memo bypasses exact result or scalar validation: {caller}, {required}"
'''
