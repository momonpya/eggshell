"""Give the first eligible search half the native deadline, capped at 15s."""
from context_candidate import once

TARGETS = '''
lean_exe initial_budget_tests where
  root := `tools.InitialBudgetTests
'''
HELPERS = ['InitialBudgetTests.lean']


def model(source):
    source = once(source, '  lastSearch : Option SearchTrace := none\n', '''  lastSearch : Option SearchTrace := none
  /-- The first eligible search consumes its longer budget even on failure or empty output.
  This is scheduling state, independent of delivery acknowledgement or compaction. -/
  searchStarted : Bool := false
''')
    return once(source, '  [("epoch", toJson (0 : Nat)),',
        '  [("searchStarted", toJson false), ("epoch", toJson (0 : Nat)),')


def hooks(source):
    source = once(source, '''def semanticSearchDeadline (now deadline : Nat) : Nat :=
  min deadline (now + min semanticSearchBudgetMs ((deadline - now) / 2))''', '''def initialSemanticSearchBudgetMs : Nat := 15000

def semanticSearchDeadline (initial : Bool) (now deadline : Nat) : Nat :=
  min deadline (now + min (if initial then initialSemanticSearchBudgetMs else semanticSearchBudgetMs)
    ((deadline - now) / 2))

theorem semantic_deadline_preserves_upstream (initial : Bool) (now deadline : Nat) :
    semanticSearchDeadline initial now deadline ≤ deadline := Nat.min_le_left _ _

theorem semantic_deadline_reserves_fallback (initial : Bool) (now deadline : Nat) :
    semanticSearchDeadline initial now deadline ≤ now + (deadline - now) / 2 := by
  exact Nat.le_trans (Nat.min_le_right _ _) (Nat.add_le_add_left (Nat.min_le_right _ _) _)
''')
    source = once(source, '''    pure (some state)
  let some initial := snapshot | return none
  if pending.projection == .none || pending.read.isEmpty then return none''', '''    if pending.projection == .none || pending.read.isEmpty then return none
    writeJson files.state {state with searchStarted := true}
    pure (some state)
  let some initial := snapshot | return none''')
    source = once(source, 'semanticSearchDeadline started deadline',
        'semanticSearchDeadline (!initial.searchStarted) started deadline')
    return once(source, '    ("deadlineMs", toJson deadline), ("trace", toJson trace),', '''    ("deadlineMs", toJson deadline), ("initialSearch", toJson (!initial.searchStarted)),
    ("semanticDeadlineMs", toJson firstDeadline), ("searchStartedMs", toJson started),
    ("trace", toJson trace),''')


def deadline_tests(source):
    # These are new-session fixtures, including the deliberately stalled provider.
    # Keep the former 4.5s gate results; this qualification tests the new policy.
    return source.replace('semanticSearchBudgetMs + 800', 'initialSemanticSearchBudgetMs + 800')


def audit(source):
    return once(source, '  for theoremName in #[', '''  for theoremName in #[``Eggshell.Plugin.semantic_deadline_preserves_upstream,
      ``Eggshell.Plugin.semantic_deadline_reserves_fallback,''')


SOURCES = {'Eggshell/PluginModel.lean': model, 'Eggshell/PluginHooks.lean': hooks,
           'tests/SemanticDeadlineTests.lean': deadline_tests, 'Eggshell/ContractAudit.lean': audit}
