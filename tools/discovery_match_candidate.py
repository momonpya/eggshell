"""Compile a proved linear Match override in the isolated semantic kernel."""
from context_candidate import once


TARGETS = '''
lean_lib DiscoveryResearch where
  roots := #[`tools.KeyedOverride]

lean_exe keyed_override_tests where
  root := `tools.KeyedOverrideTests
'''

HELPERS = ['KeyedOverride.lean', 'KeyedOverrideTests.lean']

MATCHES = '''/-- This is precisely the existing duplicate key, including both original
fragment Values. The selected Match payload is never reconstructed from it. -/
def matchKey (matched : Match) : Value × Value × Value × Value :=
  (matched.demand, matched.edge.relation, matched.work.currentFragment, matched.work.pastFragment)

theorem sameMatch_key (left right : Match) :
    sameMatch left right = (matchKey left == matchKey right) := by
  change (((left.demand == right.demand && left.edge.relation == right.edge.relation) &&
    left.work.currentFragment == right.work.currentFragment) &&
    left.work.pastFragment == right.work.pastFragment) =
    (left.demand == right.demand && (left.edge.relation == right.edge.relation &&
      (left.work.currentFragment == right.work.currentFragment &&
        left.work.pastFragment == right.work.pastFragment)))
  simp only [Bool.and_assoc]

def addMatchesFast (previous added : List Match) : List Match :=
  KeyedOverride.merge matchKey previous added

theorem addMatchesFast_exact (previous added : List Match) :
    addMatchesFast previous added = addMatches previous added := by
  have step : KeyedOverride.put matchKey = upsertMatch := by
    funext rows item
    unfold KeyedOverride.put upsertMatch
    congr 1
    apply List.filter_congr
    intro old _
    rw [← sameMatch_key]
  unfold addMatchesFast
  rw [KeyedOverride.merge_exact]
  simp only [KeyedOverride.reference, addMatches, step]

/-- The kernel keeps the original fold specification. The compiler may use
the tail-recursive membership implementation only through this equality. -/
@[csimp] theorem addMatches_compiled : @addMatches = @addMatchesFast := by
  funext previous added
  exact (addMatchesFast_exact previous added).symm

'''


def matcher(source):
    source = once(source, 'public import Eggshell.LogicalText\n',
        'public import Eggshell.LogicalText\npublic import tools.KeyedOverride\n')
    return once(source, 'def projectMatches (base : WorkGraph)',
        MATCHES + 'def projectMatches (base : WorkGraph)')
