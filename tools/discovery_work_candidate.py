"""Remove repeated Outcome projections and preserve exact Work demand order."""
from context_candidate import once


SUBWORKS = '''/-- Child membership depends on All edges alone. Do not materialize
every loaded Outcome merely to project this independent topology field. -/
def sourceSubworks (all : List AllEdge) : List Value :=
  hashDistinct (all.flatMap (·.children))

theorem sourceSubworks_exact (all : List AllEdge) (outcomes : List OutcomeEdge) :
    sourceSubworks all = ({all, outcomes} : WorkGraph).subworks :=
  HashDistinct.reference _

'''


def handoff(source):
    source = once(source, '/-- Multi-pass discovery over a pinned indexed source.',
        SUBWORKS + '/-- Multi-pass discovery over a pinned indexed source.')
    source = once(source, '  let graph := fun state : IndexedOwners => ({ all := sourceAll state, outcomes := sourceOutcomes state } : WorkGraph)\n', '')
    source = once(source, '  let corpusSubworks := fun state : IndexedOwners => (graph state).subworks ++ state.subworks',
        '  let corpusSubworks := fun state : IndexedOwners => sourceSubworks (sourceAll state) ++ state.subworks')
    start = source.index('def membershipDemand (saved staged : List Matcher.Candidate)')
    stop = source.index('theorem membership_demand_covers_staged', start)
    body = source[start:stop]
    body = once(body, '  works := ((saved ++ staged).map (·.edge.work)).eraseDups',
        '  works := hashDistinct ((saved ++ staged).map (·.edge.work))')
    if body.count('exact List.mem_eraseDups.mpr') != 2:
        raise ValueError('The complete Work membership-demand certificates changed')
    body = body.replace('exact List.mem_eraseDups.mpr', 'exact (HashDistinct.mem _ _).mpr')
    source = source[:start] + body + source[stop:]
    return once(source, '      for id in (ids ++ if task == currentValue then matchingIds else []).eraseDups do',
        '      for id in hashDistinct (ids ++ if task == currentValue then matchingIds else []) do')
