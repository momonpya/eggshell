#!/usr/bin/env python3
"""Isolate complete window-rank fusion from bounded IO pulls and delivery."""
import argparse
import os
from pathlib import Path
import shutil

from memory_guard import require_guard
from readme_preparation import clone
from readme_trial import sha
from semantic_latency import execute, save

ROOT = Path(__file__).resolve().parents[1]
BASE = Path('/Users/ovm/.codex/experiments/eggshell/scope-context-20261021/construction-3/checkout')
RUNTIME = '63a457d12b4f635722a03cb2a798583a84ff19ba29112edb992127da5d709bff'


def once(source, before, after):
    if source.count(before) != 1:
        raise ValueError('Reinspect the rank boundary: ' + before[:100])
    return source.replace(before, after)


ORDER = '''/-- Complete numerical order of an existing document, independent of a
bounded request for source bytes. Validate length before sorting provider data. -/
structure CompleteWindowOrder (document : Persistence.Store.SearchDocument) where
  indices : List Nat
  size : indices.length = document.windows.length
  complete : indices.mergeSort (· ≤ ·) = List.range document.windows.length

def CompleteWindowOrder.check? (document : Persistence.Store.SearchDocument) (indices : List Nat) :
    Option (CompleteWindowOrder document) :=
  if size : indices.length = document.windows.length then
    if complete : indices.mergeSort (· ≤ ·) = List.range document.windows.length then
      some ⟨indices, size, complete⟩ else none
  else none

theorem CompleteWindowOrder.existing (order : CompleteWindowOrder document) (index : Nat)
    (present : index ∈ order.indices) : index < document.windows.length := by
  have sorted : index ∈ order.indices.mergeSort (· ≤ ·) := List.mem_mergeSort.mpr present
  rw [order.complete] at sorted
  exact List.mem_range.mp sorted

theorem CompleteWindowOrder.covers (order : CompleteWindowOrder document) (index : Nat)
    (within : index < document.windows.length) : index ∈ order.indices := by
  have sorted : index ∈ order.indices.mergeSort (· ≤ ·) := by
    rw [order.complete]
    exact List.mem_range.mpr within
  exact List.mem_mergeSort.mp sorted

structure IndexedWindowRanking (documents : List Persistence.Store.SearchDocument) where
  document : Persistence.Store.SearchDocument
  owned : document ∈ documents
  positions : CompleteWindowOrder document

def IndexedWindowRanking.indices (ranking : IndexedWindowRanking documents) : List Nat :=
  ranking.positions.indices

'''

RESOLVE = '''def completeWindowRankings (documents : List Persistence.Store.SearchDocument)
    (response : IndexedResponse) : Except String (List (IndexedWindowRanking documents)) :=
  response.ranked.mapM fun index => do
    match owned : documents[index]? with
    | none => throw "foreign complete window order"
    | some document => do
      let some choice := response.evidence.find? (·.document == index) |
        throw "missing complete window order"
      let some positions := CompleteWindowOrder.check? document choice.indices |
        throw "window order is not the complete original document"
      pure ⟨document, List.mem_of_getElem? owned, positions⟩

'''


def main(output, identifier_context):
    require_guard(dict(memoryGuardSha256=sha(ROOT / 'tools/memory_guard.py')))
    if output.exists() or sha(BASE / '.lake/build/bin/eggshell') != RUNTIME:
        raise ValueError('Preserve the existing research candidates')
    output.mkdir(parents=True)
    checkout = output / 'checkout'
    clone(BASE, checkout)
    shutil.copy2(__file__, output / 'executed-constructor.py')
    provider = checkout / 'Eggshell/SearchProvider.lean'
    changed = once(provider.read_text(),
        '  positions := ((score, position) :: state.positions).mergeSort SearchRank.scoreOrder |>.take 16 }',
        '  positions := (score, position) :: state.positions }')
    changed = once(changed, '      evidence := (index, result.positions.map Prod.snd) :: evidence',
        '      evidence := (index, (result.positions.mergeSort SearchRank.scoreOrder).map Prod.snd) :: evidence')
    provider.write_text(changed)
    matcher = checkout / 'Eggshell/SemanticMatcher.lean'
    changed = once(matcher.read_text(), 'structure IndexedSearch (documents : List Persistence.Store.SearchDocument) where',
        ORDER + 'structure IndexedSearch (documents : List Persistence.Store.SearchDocument) where')
    changed = once(changed, '  order : IndexedOrder documents\n',
        '  order : IndexedOrder documents\n  windowOrders : List (IndexedWindowRanking documents)\n')
    changed = once(changed, '    return some ⟨[], [], order⟩',
        '    return some ⟨[], [], order, []⟩')
    changed = once(changed, 'def indexedNominations (documents : List Persistence.Store.SearchDocument)',
        RESOLVE + 'def indexedNominations (documents : List Persistence.Store.SearchDocument)')
    changed = once(changed, '      let related ← IO.ofExcept (indexedNominations documents response)\n', '''      let windowOrders ← IO.ofExcept (completeWindowRankings documents response)
      -- Bounded nomination and IO still use the same strongest 16 windows.
      -- Complete orders are used only when fusing original evidence ranks.
      let response := {response with evidence := response.evidence.map fun choice =>
        {choice with indices := choice.indices.take 16}}
      let related ← IO.ofExcept (indexedNominations documents response)
''')
    changed = once(changed, '      pure (some ⟨related, ranking, order⟩)',
        '      pure (some ⟨related, ranking, order, windowOrders⟩)')
    matcher.write_text(changed)
    handoff = checkout / 'Eggshell/Handoff.lean'
    changed = handoff.read_text()
    changed = once(changed, '  pure (some (observed.ranking.map (·.document.owner),\n    observed.ranking.map fun row => (row.document.owner, row.indices)))',
        '  pure (some (observed.windowOrders.map (·.document.owner),\n    observed.windowOrders.map fun row => (row.document.owner, row.indices)))')
    changed = once(changed, '  let rows := result.ranking.filterMap fun row =>',
        '  let rows := result.windowOrders.filterMap fun row =>')
    changed = once(changed, '  SearchRank.select windows.length semantic.length []\n',
        '  SearchRank.select windows.length (min 16 semantic.length) []\n')
    changed = once(changed, '  SearchRank.selected_within_budget _ _ _ _\n', '''  Nat.le_trans (SearchRank.selected_within_budget windows.length (min 16 semantic.length) [] _)
    (Nat.min_le_right _ _)
''')
    if identifier_context:
        for name in ['IdentifierContext.lean', 'IdentifierContextTests.lean']:
            shutil.copy2(ROOT / 'tools' / name, checkout / 'tools' / name)
        changed = once(changed, 'public import Eggshell.SemanticMatcher',
            'public import tools.IdentifierContext\npublic import Eggshell.SemanticMatcher')
        changed = once(changed, '    (SearchRank.fused [semantic, SearchRank.lexical question windows])',
            '    (SearchRank.fused [semantic, SearchRank.lexical (identifierContext question) (windows.map identifierContext)])')
    handoff.write_text(changed)
    shutil.copy2(ROOT / 'tools/CompleteWindowOrderTests.lean', checkout / 'tools/CompleteWindowOrderTests.lean')
    with (checkout / 'lakefile.lean').open('a') as stream:
        stream.write('\nlean_exe complete_window_order_tests where\n  root := `tools.CompleteWindowOrderTests\n')
        if identifier_context:
            stream.write('\nlean_lib IdentifierContextResearch where\n  roots := #[`tools.IdentifierContext]\n')
            stream.write('\nlean_exe identifier_context_tests where\n  root := `tools.IdentifierContextTests\n')
    sources = [provider, matcher, handoff]
    if identifier_context:
        sources.append(checkout / 'tools/IdentifierContext.lean')
    save(output / 'manifest.json', dict(base=str(BASE), baseRuntimeSha256=RUNTIME,
        identifierContext=identifier_context, constructorSha256=sha(__file__),
        sources={str(p.relative_to(checkout)):sha(p) for p in sources},
        answeringModelCalls=0, productionAdoption=False))
    env = dict(os.environ, LEAN_NUM_THREADS='1', HF_HUB_OFFLINE='1')
    tests = ['complete_window_order_tests', 'scope_context_tests']
    if identifier_context:
        tests.append('identifier_context_tests')
    execute(['lake', '--no-cache', 'build', 'eggshell', *tests, 'Eggshell.ContractAudit'],
            output / 'build', env, checkout, timeout=900)
    for target in tests:
        execute([checkout / '.lake/build/bin' / target], output / target, env, checkout)
    for relative in ['runtime/embedding.py', 'Eggshell/MiniLM.lean', 'Eggshell/PluginHooks.lean', 'Eggshell/Worker.lean']:
        if sha(BASE / relative) != sha(checkout / relative):
            raise ValueError('The rank refinement changed another numerical or authority boundary')
    save(output / 'result.json', dict(complete=True, runtimeSha256=sha(checkout / '.lake/build/bin/eggshell'),
        answeringModelCalls=0, qualityAccepted=False, productionAdoption=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--identifier-context', action='store_true')
    args = parser.parse_args()
    main(args.output, args.identifier_context)
