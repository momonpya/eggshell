#!/usr/bin/env python3
"""Diagnose complete configured LLVM delivery after full focus warming."""
import argparse
import fcntl
import json
from pathlib import Path
import shutil
import subprocess

from context_native_probe import environment, sha, tree
from pilot_memory_probe import protected_databases
from prepare_context_candidate import input_manifest
from prepare_discovery_candidate import sources
from semantic_latency import execute, save
from semantic_scale import check_subject


def run(args):
    source = Path(__file__).resolve().parents[1]
    build = args.build.resolve(); native = args.native.resolve(); output = args.output.resolve()
    if any(output.is_relative_to(p) or p.is_relative_to(output) for p in [source, build, native]):
        raise ValueError('Use a separate profile directory')
    qualified = json.loads((build / 'result.json').read_text())
    observed = json.loads((native / 'result.json').read_text())
    manifest = json.loads((native / 'manifest.json').read_text())
    baseline_sources = sources(build / 'checkout')
    binary = build / 'checkout/.lake/build/bin/eggshell'
    if (not qualified['passed'] or sha(binary) != qualified['candidateSha256']
            or (manifest['candidateSha256'] != qualified['candidateSha256'] and not args.reference)
            or baseline_sources != json.loads((build / 'manifest.json').read_text())['sources']
            or not observed['inspectionComplete'] or observed['observedCacheOnlyFocusPassCount'] != 12):
        raise ValueError('Qualify and complete the original focus input collection first')
    fixture = manifest['fixture']; check_subject(fixture)
    database = native / 'database/source.egg'
    frozen = json.loads((database.parent / 'setup.json').read_text())['sourceTree']
    if tree(database) != frozen:
        raise ValueError('The fully warm source/cache publication changed')
    question = fixture['questions'][0]
    receipt = json.loads((database.parent / 'q0-fresh-result.json').read_text())['receipt']
    prefix = args.prefix.resolve(); support = prefix / 'share/eggshell/minilm'
    encoder = input_manifest(support)
    comparison = args.reference.resolve() if args.reference else None
    if comparison:
        compared = json.loads((comparison / 'manifest.json').read_text())
        if (not json.loads((comparison / 'result.json').read_text())['passed'] or
                sources(comparison / 'checkout') != compared['sources'] or
                compared['database'] != str(database) or compared['question'] != question or
                compared['receipt'] != receipt or compared['encoderInputs'] != encoder or
                compared['fixture']['workspace'] != fixture['workspace']):
            raise ValueError('The exact reference publication/question/receipt/workspace/encoder changed')
    ordinary = source / '.lake/build/bin/eggshell'; ordinary_hash = sha(ordinary)
    with (native / 'profile.guard').open('a') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        output.mkdir(parents=True, exist_ok=False, mode=0o700); args.created_output = output
        checkout = output / 'checkout'
        subprocess.run(['/bin/cp', '-cpR', str(build / 'checkout'), str(checkout)], check=True, timeout=300)
        helper = source / 'tools/SemanticProfile.lean'
        shutil.copy2(helper, checkout / 'tools/SemanticProfile.lean')
        lakefile = checkout / 'lakefile.lean'
        lakefile.write_text(lakefile.read_text() +
            '\nlean_exe semantic_profile where\n  root := `tools.SemanticProfile\n')
        frozen_checkout = sources(checkout)
        save(output / 'manifest.json', dict(qualifiedRuntime=qualified['candidateSha256'],
            nativeManifestSha256=sha(native / 'manifest.json'), nativeResultSha256=sha(native / 'result.json'),
            runnerSha256=sha(Path(__file__)), helperSourceSha256=sha(helper),
            sources=frozen_checkout, database=str(database), question=question, receipt=receipt,
            referenceManifestSha256=sha(comparison / 'manifest.json') if comparison else None,
            referenceOutputSha256=sha(comparison / 'delivery/stdout') if comparison else None,
            fixture=fixture, encoderInputs=encoder, ordinaryRuntimeSha256=ordinary_hash,
            purpose='standalone configured semantic delivery; not a hook or adoption comparison',
            instrumentation=False, newNativeHooks=0, generationModelCalls=0, productionAdoption=False))
        config = output / 'empty.toml'
        config.write_text('default = "empty"\nsemantic_matcher = false\n[profiles.empty]\nread = []\n')
        env = environment(output / 'data', config, prefix)
        execute(['lake', '--no-cache', 'build', 'semantic_profile'], output / 'build', env, checkout, timeout=600)
        if sha(checkout / '.lake/build/bin/eggshell') != qualified['candidateSha256']:
            raise ValueError('Diagnostic compilation changed the runtime')
        with protected_databases([database]):
            execute([checkout / '.lake/build/bin/eggshell', 'search-provider'], output / 'query-only-setup', env,
                fixture['workspace'], (json.dumps(dict(query=dict(text=question), candidates=[])) + '\n').encode())
            raw, timing = execute([checkout / '.lake/build/bin/semantic_profile', database, question, receipt],
                output / 'delivery', dict(env, EGGSHELL_HANDOFF_TRACE=str(output / 'trace.log')),
                fixture['workspace'], timeout=120)
        result = json.loads(raw)
        handoff = result['handoff']
        exact_handoff = None
        if comparison:
            exact_handoff = handoff == json.loads((comparison / 'delivery/stdout').read_text())['handoff']
            if not exact_handoff:
                raise ValueError('The complete Handoff differs from the fixed reference')
        if (handoff is None or handoff['reason'] == 'search-incomplete' or
                tree(database) != frozen or sources(checkout) != frozen_checkout or
                sources(build / 'checkout') != baseline_sources or sha(binary) != qualified['candidateSha256']
                or sha(ordinary) != ordinary_hash or input_manifest(support) != encoder):
            raise ValueError('Configured delivery was incomplete or changed frozen inputs')
        check_subject(fixture)
        numerical = [json.loads(p.read_text())['data'] for p in sorted((output / 'data/receipts' / receipt).glob('numerical-*.json'))]
        save(output / 'result.json', dict(passed=True, elapsedMs=result['elapsedMs'], timing=timing,
            exactHandoff=exact_handoff,
            goldBodyDelivered=fixture['bodyMarker'] in handoff['text'], numerical=numerical,
            sourceAndCacheBytesUnchanged=True, instrumentation=False,
            newNativeHooks=0, generationModelCalls=0, productionAdoption=False))
        print(json.dumps(dict(passed=True, elapsedMs=result['elapsedMs'],
            goldBodyDelivered=fixture['bodyMarker'] in handoff['text'])), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['build', 'native', 'prefix', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--reference', type=Path,
        help='Require the same complete Handoff from a frozen earlier diagnostic')
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        if getattr(args, 'created_output', None):
            save(args.created_output / 'failure.json', dict(error=f'{type(error).__name__}: {error}', productionAdoption=False))
        raise


if __name__ == '__main__':
    main()
