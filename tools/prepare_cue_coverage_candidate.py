#!/usr/bin/env python3
"""Spend bounded original cue/condition coverage before wider neighborhoods."""
import argparse
import os
from pathlib import Path
import shutil

from memory_guard import require_guard
from readme_preparation import clone
from readme_trial import sha
from semantic_latency import execute, save

ROOT = Path(__file__).resolve().parents[1]
BASE = Path('/Users/ovm/.codex/experiments/eggshell/scope-context-20261021/construction-6/checkout')
RUNTIME = 'c5190c41f6570ed2c76bca7ecd39a1f7cc24fb51763266f432bb05af40d2bf43'


def main(output):
    require_guard(dict(memoryGuardSha256=sha(ROOT / 'tools/memory_guard.py')))
    if output.exists() or sha(BASE / '.lake/build/bin/eggshell') != RUNTIME:
        raise ValueError('Preserve existing research candidates')
    output.mkdir(parents=True)
    checkout = output / 'checkout'
    clone(BASE, checkout)
    shutil.copy2(__file__, output / 'executed-constructor.py')
    path = checkout / 'Eggshell/Handoff.lean'
    before = path.read_text()
    tuple_end = '    (complete, required, coherent)\n'
    if before.count(tuple_end) != 2:
        raise ValueError('Reinspect both reference and compiled cue builders')
    changed = before.replace(tuple_end, '''    -- Minimum coverage carries original scope labels too. Padding is
    -- optional; the conditions of its original cue are not.
    let complete := if bounds : scope.start < complete.start ∧ complete.stop - scope.start ≤ 2048 then
      (⟨scope.start, complete.stop, Nat.lt_trans bounds.1 complete.ordered,
        complete.within, bounds.2⟩ : EvidenceRange source)
      else complete
''' + tuple_end)
    coverage = '  let coverage := candidates.map (fun (_, required, _) => required)'
    fallback = '''  let fallback := candidates.filterMap fun (complete, required, _) =>
    if required.start == complete.start && required.stop == complete.stop then none else some complete'''
    if changed.count(coverage) != 2 or changed.count(fallback) != 2 or changed.count('coverage ++ fallback ++ context') != 2:
        raise ValueError('Reinspect minimum coverage and neighborhood alternatives')
    changed = changed.replace(coverage, '  let coverage := candidates.map (fun (complete, _, _) => complete)')
    changed = changed.replace(fallback, '''  let neighborhoods := candidates.filterMap fun (complete, required, _) =>
    if required.start == complete.start && required.stop == complete.stop then none else some required''')
    changed = changed.replace('coverage ++ fallback ++ context', 'coverage ++ neighborhoods ++ context')
    comment = '''  -- A compact neighborhood can still exceed the remaining space. Retain
  -- its smaller original cue/entry as an alternative, rather than dropping
  -- a required scope boundary merely because its optional context cannot fit.'''
    changed = changed.replace(comment, '''  -- Admit original cues and their conditions before spending remaining
  -- capacity on larger neighborhoods. Optional padding cannot outrun a cue.''')
    path.write_text(changed)
    shutil.copy2(ROOT / 'tools/ScopeCueCoverageTests.lean', checkout / 'tools/ScopeCueCoverageTests.lean')
    with (checkout / 'lakefile.lean').open('a') as stream:
        stream.write('\nlean_exe scope_cue_coverage_tests where\n  root := `tools.ScopeCueCoverageTests\n')
    save(output / 'manifest.json', dict(base=str(BASE), baseRuntimeSha256=RUNTIME,
        sourceBeforeSha256=sha(BASE / 'Eggshell/Handoff.lean'), sourceAfterSha256=sha(path),
        answeringModelCalls=0, productionAdoption=False))
    env = dict(os.environ, LEAN_NUM_THREADS='1', HF_HUB_OFFLINE='1')
    tests = ['scope_cue_coverage_tests', 'scope_context_tests', 'complete_window_order_tests',
             'identifier_context_tests']
    execute(['lake', '--no-cache', 'build', 'eggshell', *tests, 'Eggshell.ContractAudit'],
            output / 'build', env, checkout, timeout=900)
    for test in tests:
        execute([checkout / '.lake/build/bin' / test], output / test, env, checkout)
    for relative in ['Eggshell/SearchProvider.lean', 'Eggshell/SemanticMatcher.lean',
                     'runtime/embedding.py', 'Eggshell/MiniLM.lean', 'Eggshell/PluginHooks.lean', 'Eggshell/Worker.lean']:
        if sha(BASE / relative) != sha(checkout / relative):
            raise ValueError('Cue coverage changed another numerical or authority boundary')
    save(output / 'result.json', dict(complete=True, runtimeSha256=sha(checkout / '.lake/build/bin/eggshell'),
        answeringModelCalls=0, productionAdoption=False, qualityAccepted=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    main(parser.parse_args().output)
