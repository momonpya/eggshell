"""Replace the isolated discovery owner's sorted list by its ordinal tree."""
from context_candidate import once


ROWS = '''def IndexedOwners.rows (state : IndexedOwners) : List IndexedOwner :=
  state.owners.values

/-- The original publication ordinal is the sole key. Its checked tree
supplies stable original order without a second list or an ordinal field. -/
theorem IndexedOwners.original_order (state : IndexedOwners) :
    state.owners.toList.Pairwise (fun a b => compare a.1 b.1 = .lt) :=
  Std.TreeMap.ordered_keys_toList

'''


def handoff(source):
    source = once(source, 'public import Eggshell.PluginModel',
        'public import Std.Data.TreeMap.Lemmas\npublic import Eggshell.PluginModel')
    source = once(source, 'structure IndexedOwner where\n  ordinal : Nat\n',
        'structure IndexedOwner where\n')
    source = once(source, '  owners : List IndexedOwner := []',
        '  owners : Std.TreeMap Nat IndexedOwner := {}')
    source = once(source, 'def IndexedOwners.graph (owners : IndexedOwners)',
        ROWS + 'def IndexedOwners.graph (owners : IndexedOwners)')
    if source.count('owners.owners.map') != 3:
        raise ValueError('The owner projection sites changed')
    source = source.replace('owners.owners.map', 'owners.rows.map')
    source = once(source, '  exact exactRows owners.owners', '  exact exactRows owners.rows')
    source = once(source, '    ordinal, candidate\n', '    candidate\n')
    source = once(source, '    owners := (row :: state.owners).mergeSort (fun a b => a.ordinal ≤ b.ordinal)',
        '    owners := state.owners.insert ordinal row')
    membership = 'if state.owners.any (fun row => row.ordinal == ordinal) then return state'
    if source.count(membership) != 2:
        raise ValueError('The owner loader membership sites changed')
    source = source.replace(membership, 'if state.owners.contains ordinal then return state')
    source = once(source, '    state.owners.map (·.candidate.edge) ++ stagedGraph.outcomes',
        '    state.rows.map (·.candidate.edge) ++ stagedGraph.outcomes')
    return once(source, '''        related := if task == currentValue then state.owners.filterMap (fun row =>
          if semanticOrdinals.contains row.ordinal then some row.candidate.edge.relation else none) ++ matchedNominations.staged else [] }''',
        '''        related := if task == currentValue then state.owners.toList.filterMap (fun (ordinal, row) =>
          if semanticOrdinals.contains ordinal then some row.candidate.edge.relation else none) ++ matchedNominations.staged else [] }''')
