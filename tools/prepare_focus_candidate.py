#!/usr/bin/env python3
"""Qualify an isolated retrieval candidate without changing ordinary sources."""
import argparse
import importlib
import json
from pathlib import Path
import shutil

from context_native_probe import environment, sha
from prepare_discovery_candidate import sources, drain
from semantic_latency import execute, save


def run(args):
    candidate = importlib.import_module(args.candidate.replace('-', '_') + '_candidate')
    checks = args.candidate.replace('-', '_') + '_tests'
    source = Path(__file__).resolve().parents[1]
    base = args.base.resolve(); output = args.output.resolve()
    if any(output.is_relative_to(p) or p.is_relative_to(output) for p in [source, base]):
        raise ValueError('Use a separate qualification directory')
    qualified = json.loads((base / 'result.json').read_text())
    original = base / 'checkout'; runtime = original / '.lake/build/bin/eggshell'
    frozen_base = json.loads((base / 'manifest.json').read_text())['sources']
    if (not qualified['passed'] or sha(runtime) != qualified['candidateSha256']
            or sources(original) != frozen_base):
        raise ValueError('Use the unchanged qualified uninstrumented candidate')
    ordinary = source / '.lake/build/bin/eggshell'; ordinary_hash = sha(ordinary)
    output.mkdir(parents=True, exist_ok=False, mode=0o700); args.created_output = output
    checkout = output / 'checkout'
    import subprocess
    subprocess.run(['/bin/cp', '-cpR', str(original), str(checkout)], check=True, timeout=300)
    if hasattr(candidate, 'SOURCES'):
        transforms = candidate.SOURCES.items()
    else:
        transforms = [('Eggshell/Handoff.lean', candidate.handoff)]
        if args.candidate == 'focus-warm':
            transforms.append(('Eggshell/Warm.lean', candidate.warm))
        if hasattr(candidate, 'audit'):
            transforms.append(('Eggshell/ContractAudit.lean', candidate.audit))
    for name, transform in transforms:
        path = checkout / name
        path.write_text(transform(path.read_text()))
    for name in candidate.HELPERS:
        shutil.copy2(source / 'tools' / name, checkout / 'tools' / name)
    lakefile = checkout / 'lakefile.lean'
    lakefile.write_text(lakefile.read_text() + candidate.TARGETS)
    frozen = sources(checkout)
    save(output / 'manifest.json', dict(sources=frozen, baseResultSha256=sha(base / 'result.json'),
        baseManifestSha256=sha(base / 'manifest.json'), qualifiedBaselineSha256=sha(runtime),
        ordinaryRuntimeSha256=ordinary_hash, runnerSha256=sha(Path(__file__)),
        overlaySha256=sha(Path(candidate.__file__)), candidate=args.candidate, instrumentation=False,
        generationModelCalls=0, productionAdoption=False))
    config = output / 'empty.toml'
    config.write_text('default = "empty"\nsemantic_matcher = false\n[profiles.empty]\nread = []\n')
    data = output / 'data'; env = environment(data, config, args.prefix.resolve())
    execute(['lake', '--no-cache', 'build', 'eggshell', 'eggshell_tests', checks,
             'Eggshell.ContractAudit'], output / 'build', env, checkout, timeout=600)
    raw, focused = execute([checkout / '.lake/build/bin' / checks],
                           output / 'candidate-tests', env, checkout, timeout=60)
    regression_env = dict(env); regression_env.pop('EGGSHELL_CONFIG', None)
    _, regression = execute([checkout / '.lake/build/bin/eggshell_tests'],
                           output / 'regression', regression_env, checkout, timeout=600)
    recovery = drain(checkout / '.lake/build/bin/eggshell', data, env, output, checkout)
    if (sources(checkout) != frozen or sources(original) != frozen_base
            or sha(runtime) != qualified['candidateSha256'] or sha(ordinary) != ordinary_hash):
        raise ValueError('Qualification changed frozen sources or an ordinary executable')
    save(output / 'result.json', dict(passed=True, candidateSha256=sha(checkout / '.lake/build/bin/eggshell'),
        candidate=args.candidate, candidateTests=json.loads(raw), checkTiming=focused,
        regression=regression, indexRecovery=recovery,
        sourcesUnchanged=True, instrumentation=False, generationModelCalls=0, productionAdoption=False))
    print(json.dumps(dict(passed=True, regressionMs=regression['elapsedMs'], checkout=str(checkout))), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['base', 'output', 'prefix']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--candidate', choices=['focus-warm', 'context-plan', 'context-memo', 'context-prefix', 'directory-read', 'initial-budget'], default='focus-warm')
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        if getattr(args, 'created_output', None):
            save(args.created_output / 'failure.json', dict(error=f'{type(error).__name__}: {error}', productionAdoption=False))
        raise


if __name__ == '__main__':
    main()
