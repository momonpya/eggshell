#!/usr/bin/env python3
"""Isolate first-segment scoring while retaining the current cache and delivery.

This is an experimental control, never a proposed production repair. It reads
the same fully encoded bundles but scores only their first segment. Stored
coverage must not be reported as scored coverage for this control.
"""
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
OUTPUT = EXPERIMENTS / 'first-segment-control-20261020/construction-1'


def main():
    original = BASE / 'checkout'
    expected = json.loads((BASE / 'result.json').read_text())['candidateSha256']
    if sha(original / '.lake/build/bin/eggshell') != expected:
        raise ValueError('The qualified input runtime changed')
    OUTPUT.mkdir(parents=True, exist_ok=False, mode=0o700)
    checkout = OUTPUT / 'checkout'
    subprocess.run(['/bin/cp', '-cR', str(original), str(checkout)], check=True)
    source = checkout / 'Eggshell/SearchProvider.lean'
    before = source.read_text()
    needle = '    pure (cached.vector.map Json.str)'
    if before.count(needle) != 2:
        raise ValueError('Reinspect the source/query bundle read boundaries')
    source.write_text(before.replace(needle, '    pure ((cached.vector.extract 0 1).map Json.str)'))
    shutil.copy2(ROOT / 'tools/DeliveryAudit.lean', checkout / 'tools/DeliveryAudit.lean')
    with (checkout / 'lakefile.lean').open('a') as stream:
        stream.write('\nlean_exe delivery_audit where\n  root := `tools.DeliveryAudit\n')
    save(OUTPUT / 'manifest.json', dict(base=str(BASE), baseRuntimeSha256=expected,
        sourceBeforeSha256=sha(original / 'Eggshell/SearchProvider.lean'),
        sourceAfterSha256=sha(source), numericalRuntimeUnchanged=sha(checkout / 'runtime/embedding.py') ==
            sha(original / 'runtime/embedding.py'),
        scope='Only source/query bundle projection into scoring changes; model, encoding, persistence, cache ownership, warm, index tickets, lexical terms, deadlines and delivery are retained',
        coverage='Full bundles are stored and validated, but only first segments are scored; this control does not claim full-context retrieval',
        generationModelCalls=0, productionAdoption=False))
    env = dict(os.environ, LEAN_NUM_THREADS='1', HF_HUB_OFFLINE='1')
    env.pop('EGGSHELL_CONFIG', None)
    execute(['lake', '--no-cache', 'build', 'eggshell', 'delivery_audit', 'Eggshell.ContractAudit'],
            OUTPUT / 'build', env, checkout, timeout=600)
    if sha(original / '.lake/build/bin/eggshell') != expected or sha(original / 'Eggshell/SearchProvider.lean') != json.loads((OUTPUT / 'manifest.json').read_text())['sourceBeforeSha256']:
        raise ValueError('The control changed its qualified input')
    save(OUTPUT / 'result.json', dict(passed=True, candidateSha256=sha(checkout / '.lake/build/bin/eggshell'),
        scope='Build only; public-body equivalence and native readiness still require validation',
        generationModelCalls=0, productionAdoption=False))


if __name__ == '__main__':
    main()
