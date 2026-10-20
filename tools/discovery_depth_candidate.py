"""Exact depth-count acceleration; apply only inside an isolated checkout."""
from context_candidate import once


COUNT = '''/-- A full relation value decides membership after the hash lookup.
This counts projected owners only; it does not filter the matching domain. -/
def projectedOutcomeCount (original projected : List OutcomeEdge) : Nat :=
  let known := Std.HashSet.ofList (original.map (·.relation))
  (projected.filter fun edge => !known.contains edge.relation).length

theorem projectedOutcomeCount_exact (original projected : List OutcomeEdge) :
    projectedOutcomeCount original projected =
      (projected.filter fun edge =>
        !(original.any fun saved => saved.relation == edge.relation)).length := by
  unfold projectedOutcomeCount
  dsimp only
  apply congrArg List.length
  apply List.filter_congr
  intro edge _
  rw [Std.HashSet.contains_ofList, List.contains_map]
  exact congrArg Bool.not (List.any_congr rfl (fun _ => BEq.comm))

'''


def handoff(source):
    source = once(source, 'public import Eggshell.PluginModel',
        'public import Std.Data.HashSet.Lemmas\npublic import Eggshell.PluginModel')
    source = once(source, '/-- Multi-pass discovery over a pinned indexed source.',
        COUNT + '/-- Multi-pass discovery over a pinned indexed source.')
    return once(source, '''      (projected.outcomes.filter fun edge =>
        !((sourceOutcomes state).any fun original => original.relation == edge.relation)).length + 1)''',
        '''      projectedOutcomeCount (sourceOutcomes state) projected.outcomes + 1)''')
