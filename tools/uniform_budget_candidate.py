"""Use the original hook deadline for both first and subsequent warm searches."""
from context_candidate import once

TARGETS = '''
lean_exe uniform_budget_tests where
  root := `tools.UniformBudgetTests
'''
HELPERS = ['UniformBudgetTests.lean']


def hooks(source):
    source = once(source, '''def semanticSearchBudgetMs : Nat := 4500

def initialSemanticSearchBudgetMs : Nat := 15000

def semanticSearchDeadline (initial : Bool) (now deadline : Nat) : Nat :=
  min deadline (now + min (if initial then initialSemanticSearchBudgetMs else semanticSearchBudgetMs)
    ((deadline - now) / 2))''', '''def semanticSearchBudgetMs : Nat := 15000

def semanticSearchDeadline (now deadline : Nat) : Nat :=
  min deadline (now + min semanticSearchBudgetMs ((deadline - now) / 2))''')
    source = once(source, '''theorem semantic_deadline_preserves_upstream (initial : Bool) (now deadline : Nat) :
    semanticSearchDeadline initial now deadline ≤ deadline''', '''theorem semantic_deadline_preserves_upstream (now deadline : Nat) :
    semanticSearchDeadline now deadline ≤ deadline''')
    source = once(source, '''theorem semantic_deadline_reserves_fallback (initial : Bool) (now deadline : Nat) :
    semanticSearchDeadline initial now deadline ≤ now + (deadline - now) / 2''', '''theorem semantic_deadline_reserves_fallback (now deadline : Nat) :
    semanticSearchDeadline now deadline ≤ now + (deadline - now) / 2''')
    source = once(source, 'semanticSearchDeadline (!initial.searchStarted) started deadline',
        'semanticSearchDeadline started deadline')
    source = once(source, 'finishReady := semantic && !initial.searchStarted',
        'finishReady := semantic')
    return once(source, 'Once initial nominations are ready, status uses the same overall deadline',
        'Once checked nominations are ready, status uses the same overall deadline')


def model(source):
    return once(source, '''The first eligible search consumes its longer budget even on failure or empty output.
  This is scheduling state, independent of delivery acknowledgement or compaction.''',
        '''Record first versus subsequent eligible searches, including failed or empty results.
  This diagnostic marker is independent of acknowledgement, compaction and deadline allocation.''')


def deadline_tests(source):
    return source.replace('initialSemanticSearchBudgetMs', 'semanticSearchBudgetMs')


def old_fixture(source):
    # This historical executable remains buildable; its old execution records
    # retain their original 15s/4.5s protocol. Run the new fixture for this policy.
    source = once(source, 'else allocation ≤ 4500', 'else allocation ≤ 15000')
    source = once(source, 'semanticSearchDeadline initial now deadline',
        'semanticSearchDeadline now deadline')
    source = once(source, 'let cap := if initial then 15000 else 4500', 'let cap := 15000')
    return once(source, 'semanticSearchDeadline true now (now - 1)',
        'semanticSearchDeadline now (now - 1)')


SOURCES = {'Eggshell/PluginHooks.lean': hooks, 'Eggshell/PluginModel.lean': model,
           'tests/SemanticDeadlineTests.lean': deadline_tests,
           'tools/InitialBudgetTests.lean': old_fixture}
