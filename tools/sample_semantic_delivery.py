#!/usr/bin/env python3
"""Sample the renderer of one owned complete configured-delivery diagnostic."""
import argparse
import json
from pathlib import Path
import subprocess
import time

from context_native_probe import environment, sha, tree
from pilot_memory_probe import protected_databases
from prepare_discovery_candidate import sources
from semantic_latency import save
from semantic_scale import check_subject


def run(args):
    profile = args.profile.resolve(); output = args.output.resolve()
    if output.is_relative_to(profile) or profile.is_relative_to(output):
        raise ValueError('Use a separate sampling directory')
    reference = json.loads((profile / 'result.json').read_text())
    manifest = json.loads((profile / 'manifest.json').read_text())
    checkout = profile / 'checkout'; helper = checkout / '.lake/build/bin/semantic_profile'
    if not reference['passed'] or sources(checkout) != manifest['sources']:
        raise ValueError('The reference diagnostic changed')
    expected_sources = manifest['sources']
    if args.candidate:
        candidate = args.candidate.resolve()
        measured = json.loads((candidate / 'result.json').read_text())
        prepared = json.loads((candidate / 'manifest.json').read_text())
        helper = Path(measured['timing']['args'][0]); checkout = helper.parents[3]
        expected_sources = prepared['sources']
        if (not measured['passed'] or not measured['exactHandoff'] or
                prepared['referenceManifestSha256'] != sha(profile / 'manifest.json') or
                prepared['database'] != manifest['database'] or prepared['question'] != manifest['question'] or
                prepared['receipt'] != manifest['receipt'] or sources(checkout) != expected_sources or
                sha(helper) != prepared['candidateHelperSha256']):
            raise ValueError('The frozen exact-Handoff candidate inspection changed')
    binary = checkout / '.lake/build/bin/eggshell'
    database = Path(manifest['database']); frozen = tree(database)
    fixture = manifest['fixture']; check_subject(fixture)
    helper_hash = sha(helper); runtime_hash = sha(binary)
    output.mkdir(parents=True, exist_ok=False, mode=0o700); args.created_output = output
    # Copy only the private, valid query cache. No source cache or receipt is
    # modified; the same fixed receipt is resolved below a fresh private root.
    data = output / 'data'; data.mkdir()
    subprocess.run(['/bin/cp', '-cpR', str(profile / 'data/queries'), str(data / 'queries')], check=True)
    env = environment(data, profile / 'empty.toml', args.prefix.resolve())
    trace = output / 'trace.log'; env['EGGSHELL_HANDOFF_TRACE'] = str(trace)
    command = [str(helper), str(database), manifest['question'], manifest['receipt']]
    save(output / 'manifest.json', dict(referenceManifestSha256=sha(profile / 'manifest.json'),
        referenceResultSha256=sha(profile / 'result.json'), helperSha256=helper_hash,
        runtimeSha256=runtime_hash, runnerSha256=sha(Path(__file__)), command=command,
        workspace=fixture['workspace'], sampleDurationSeconds=3, sampleIntervalMs=10,
        sampleExecutableSha256=sha(Path('/usr/bin/sample')), newNativeHooks=0,
        generationModelCalls=0, productionAdoption=False))
    with protected_databases([database]), (output / 'stdout').open('wb') as stdout, (output / 'stderr').open('wb') as stderr:
        started = time.monotonic()
        child = subprocess.Popen(command, cwd=fixture['workspace'], env=env, stdout=stdout, stderr=stderr)
        try:
            while not trace.exists() or 'ms source focus' not in trace.read_text():
                if child.poll() is not None or time.monotonic() - started > 40:
                    raise RuntimeError('The owned helper ended or never reached the renderer')
                time.sleep(.01)
            identity = subprocess.check_output(['ps', '-p', str(child.pid), '-o', 'pid=,lstart=,command='], text=True).strip()
            sample_command = ['/usr/bin/sample', str(child.pid), '3', '10', '-mayDie', '-file', str(output / 'sample.txt')]
            save(output / 'sample-target.json', dict(pid=child.pid, identity=identity,
                helperSha256=helper_hash, afterTrace=trace.read_text(), command=sample_command))
            sampled = subprocess.run(sample_command, capture_output=True, timeout=20)
            (output / 'sample-stdout').write_bytes(sampled.stdout)
            (output / 'sample-stderr').write_bytes(sampled.stderr)
            if sampled.returncode:
                raise RuntimeError('Native sampling failed')
            code = child.wait(timeout=120)
            if code:
                raise RuntimeError('The sampled helper failed')
        finally:
            if child.poll() is None:
                child.terminate(); child.wait(timeout=5)
    actual = json.loads((output / 'stdout').read_text())
    original = json.loads((profile / 'delivery/stdout').read_text())
    if (actual['handoff'] != original['handoff'] or tree(database) != frozen
            or sha(helper) != helper_hash or sha(binary) != runtime_hash or sources(checkout) != expected_sources):
        raise ValueError('Sampling changed complete delivery or frozen inputs')
    check_subject(fixture)
    save(output / 'result.json', dict(passed=True, exactHandoff=True, elapsedMs=actual['elapsedMs'],
        instrumentationOverheadIncluded=True, sourceAndCacheBytesUnchanged=True,
        newNativeHooks=0, generationModelCalls=0, productionAdoption=False))
    print(json.dumps(dict(passed=True, exactHandoff=True, elapsedMs=actual['elapsedMs'])), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['profile', 'prefix', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--candidate', type=Path,
        help='Sample an observed candidate only after its complete Handoff equals this reference')
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        if getattr(args, 'created_output', None):
            save(args.created_output / 'failure.json', dict(error=f'{type(error).__name__}: {error}', productionAdoption=False))
        raise


if __name__ == '__main__':
    main()
