"""Share exact prefix decisions within each immutable decoded source layout."""
from context_candidate import once

TARGETS = '''
lean_lib ContextPrefixResearch where
  roots := #[`tools.ExactLazyMemo, `tools.PairDecisions]

lean_exe context_prefix_tests where
  root := `tools.ContextPrefixTests
'''
HELPERS = ['ExactLazyMemo.lean', 'PairDecisions.lean', 'ContextPrefixTests.lean']

PREFIX = '''def scalarPrefixHolds (source content : String) (first second : Nat) : Prop :=
  (source.take first).copy = "\\\"" ++ encodedTextBody ((content.take second).copy)

instance : DecidableRel (scalarPrefixHolds source content) := fun first second =>
  inferInstanceAs (Decidable ((source.take first).copy =
    "\\\"" ++ encodedTextBody ((content.take second).copy)))

def scalarPrefixDepth (source content : String) : Nat :=
  ((source.length + 1) * (content.length + 1)).log2 + 1

abbrev ScalarPrefixMemo (source content : String) :=
  PairDecisions (scalarPrefixHolds source content) (content.length + 1) (scalarPrefixDepth source content)

'''


def handoff(source):
    source = once(source, 'public import tools.ExactMemo\n',
        'public import tools.ExactMemo\npublic import tools.PairDecisions\n')
    source = once(source, '/-- Request-local layout of one immutable scalar.',
        PREFIX + '/-- Request-local layout of one immutable scalar.')
    source = once(source, '  content : IndexedCharacters decoded.text\n',
        '  content : IndexedCharacters decoded.text\n  prefixes : ScalarPrefixMemo source decoded.text\n')
    source = once(source, '    IndexedCharacters.make source, ⟨chars.toArray, rfl⟩⟩',
        '''    IndexedCharacters.make source, ⟨chars.toArray, rfl⟩,
    PairDecisions.make _ (decoded.text.length + 1) (scalarPrefixDepth source decoded.text)⟩''')
    source = once(source, '  | mk decoded chars charsExact widths widthsExact original content =>',
        '  | mk decoded chars charsExact widths widthsExact original content prefixes =>')
    source = once(source, '    rw [IndexedCharacters.is_canonical original, IndexedCharacters.is_canonical content]',
        '''    rw [IndexedCharacters.is_canonical original, IndexedCharacters.is_canonical content,
      PairDecisions.is_canonical prefixes]''')
    lo = source.index('def decodedEvidenceUsingIndexed? (')
    hi = source.index('@[csimp] theorem decodedEvidenceUsingIndexed_compiled', lo)
    decoder = source[lo:hi]
    start = decoder.index('          if prefixExact :')
    first = decoder.index(' then\n', start) + len(' then\n')
    stop = decoder.index('\n          else none)', first)
    body = decoder[first:stop].replace('              by\n', '''              by
                change (source.take original.start).copy = "\\\"" ++
                  encodedTextBody ((decoded.text.take content.start).copy) at prefixExact
''')
    body = '\n'.join('  ' + line for line in body.splitlines())
    decoder = decoder[:start] + '''          layout.prefixes.branch original.start content.start
            (fun prefixExact =>
''' + body + ''')
            (fun _ => none))''' + decoder[stop + len('\n          else none)'):]
    source = source[:lo] + decoder + source[hi:]
    return once(source, '    IndexedCharacters.branch₂_exact, EvidenceRange.text] <;> rfl',
        '''    IndexedCharacters.branch₂_exact, EvidenceRange.text]
  simp only [PairDecisions.branch_function_eq, scalarPrefixHolds]
  rfl''')


def audit(source):
    source = once(source, '  for theoremName in #[', '''  for theoremName in #[``Eggshell.ExactLazyMemo.read_exact,
      ``Eggshell.PairDecisions.read_eq, ``Eggshell.PairDecisions.decision_eq,
      ``Eggshell.PairDecisions.branch_exact, ``Eggshell.PairDecisions.branch_function_eq,''')
    return source + '''
run_meta do
  let environment ← getEnv
  let some declaration := environment.find? ``Eggshell.Plugin.decodedEvidenceUsingIndexed? |
    throwError "Missing exact prefix decoder"
  let some body := declaration.value? | throwError "Prefix decoder has no body"
  for required in #[``Eggshell.PairDecisions.branch, ``Eggshell.IndexedCharacters.branch₂] do
    unless body.getUsedConstants.contains required do
      throwError "Decoder bypasses a certified scalar decision: {required}"
'''
