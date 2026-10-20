#!/usr/bin/env python3
"""Build an isolated full-coverage scoring candidate; never activate it."""
import json
import os
from pathlib import Path
import shutil
import subprocess

from context_native_probe import sha
from semantic_latency import execute, save

ROOT = Path(__file__).resolve().parents[1]
EXPERIMENTS = Path('/Users/ovm/.codex/experiments/eggshell')
BASE = EXPERIMENTS / 'uniform-budget-qualified-20261020/construction-1'
OUTPUT = EXPERIMENTS / 'window-centroid-20261020/construction-3'


def main():
    original = BASE / 'checkout'
    expected = json.loads((BASE / 'result.json').read_text())['candidateSha256']
    if sha(original / '.lake/build/bin/eggshell') != expected:
        raise ValueError('The qualified input runtime changed')
    OUTPUT.mkdir(parents=True, exist_ok=False, mode=0o700)
    checkout = OUTPUT / 'checkout'
    subprocess.run(['/bin/cp', '-cR', str(original), str(checkout)], check=True)
    for name in ['WindowCentroid.lean', 'WindowCentroidTests.lean', 'DeliveryAudit.lean']:
        shutil.copy2(ROOT / 'tools' / name, checkout / 'tools' / name)
    source = checkout / 'Eggshell/SearchProvider.lean'
    before = source.read_text()
    needle = '    pure (cached.vector.map Json.str)'
    if before.count(needle) != 2:
        raise ValueError('Reinspect the source/query scoring projections')
    replacement = '''    let pooled ← IO.ofExcept (Eggshell.WindowCentroid.project cached.vector
      cached.coverage.sourceTokens (cached.coverage.contextTokens - 2) cached.coverage.overlapTokens)
    pure #[Json.str pooled]'''
    after = before.replace(needle, replacement)
    after = after.replace('public import tools.DirectoryReads\n',
                          'public import tools.DirectoryReads\npublic import tools.WindowCentroid\n')
    after = after.replace('structure IndexedMetrics where\n',
                          'structure IndexedMetrics where\n  scoringPolicy : String := "window centroid weighted by newly covered source tokens"\n')
    source.write_text(after)
    lakefile = checkout / 'lakefile.lean'
    text = lakefile.read_text()
    text += '\nlean_lib WindowCentroidResearch where\n  roots := #[`tools.WindowCentroid]\n'
    text += '\nlean_exe window_centroid_tests where\n  root := `tools.WindowCentroidTests\n'
    if '\nlean_exe delivery_audit where\n' not in text:
        text += '\nlean_exe delivery_audit where\n  root := `tools.DeliveryAudit\n'
    lakefile.write_text(text)
    save(OUTPUT / 'manifest.json', dict(base=str(BASE), baseRuntimeSha256=expected,
        sourceBeforeSha256=sha(original / 'Eggshell/SearchProvider.lean'),
        sourceAfterSha256=sha(source),
        numericalRuntimeUnchanged=sha(checkout / 'runtime/embedding.py') == sha(original / 'runtime/embedding.py'),
        scope='Only projection of full cached source/query bundles into scoring changes; one unit vector per original window; all segments have positive source-token weights',
        generationModelCalls=0, productionAdoption=False))
    env = dict(os.environ, LEAN_NUM_THREADS='1', HF_HUB_OFFLINE='1')
    env.pop('EGGSHELL_CONFIG', None)
    execute(['lake', '--no-cache', 'build', 'eggshell', 'window_centroid_tests',
             'delivery_audit', 'Eggshell.ContractAudit'], OUTPUT / 'build', env, checkout, timeout=600)
    execute([checkout / '.lake/build/bin/window_centroid_tests'], OUTPUT / 'checks',
            env, checkout, timeout=30)
    if sha(original / '.lake/build/bin/eggshell') != expected:
        raise ValueError('The isolated candidate changed its input runtime')
    save(OUTPUT / 'result.json', dict(passed=True,
        candidateSha256=sha(checkout / '.lake/build/bin/eggshell'),
        scope='Build and numerical boundary checks only; native deadline, token and quality gates remain untested',
        generationModelCalls=0, productionAdoption=False))


if __name__ == '__main__':
    main()
