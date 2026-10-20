#!/usr/bin/env python3
"""Save the four fixed scale fixtures once using the original retrieval policy."""
import argparse
import fcntl
import json
from pathlib import Path
import shutil
import subprocess
import time

from context_native_probe import environment, sha
from semantic_latency import graph_files, save


COUNTS = [2, 1024, 10000, 50000]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--producer-build', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args(); build = args.producer_build.resolve(); output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=args.resume, mode=0o700)
    producer = build / 'checkout/.lake/build/bin/retrieval_scale'
    qualified = json.loads((build / 'result.json').read_text())
    sealed = json.loads((build / 'manifest.json').read_text())
    if not qualified['passed'] or sha(producer) != qualified['scaleProducerSha256']:
        raise ValueError('The original-policy scale producer is not qualified')
    for name in ['Eggshell/GraphStore.lean', 'Eggshell/SearchRank.lean']:
        if sha(build / 'checkout' / name) != sealed['sourceHashes'][name]:
            raise ValueError('The seed producer contains a changed save-time retrieval policy')
    protocol = Path(__file__).resolve().parents[1] / 'docs/semantic-scale-protocol.md'
    declaration = dict(counts=COUNTS, producerSha256=sha(producer),
        producerContract=sha(build / 'checkout/tools/RetrievalScale.lean'),
        producerManifestSha256=sha(build / 'manifest.json'), protocolSha256=sha(protocol),
        helpers={name: sha(Path(__file__).with_name(name)) for name in
                 ['prepare_scale_fixtures.py', 'context_native_probe.py', 'semantic_latency.py']},
        savePolicy={name: sealed['sourceHashes'][name] for name in ['Eggshell/GraphStore.lean', 'Eggshell/SearchRank.lean']},
        generationModelCalls=0, embeddingCalls=0, productionAdoption=False)
    manifest = output / 'manifest.json'
    if args.resume:
        if json.loads(manifest.read_text()) != declaration:
            raise ValueError('Resume requires the identical producer, protocol and fixed counts')
    else:
        save(manifest, declaration); shutil.copy2(protocol, output / 'protocol.md')
        shutil.copy2(Path(__file__), output / 'runner.py')
    config = output / 'empty.toml'
    config.write_text('default = "empty"\nsemantic_matcher = false\n[profiles.empty]\nread = []\n')
    prefix = output / 'empty-prefix'; prefix.mkdir(exist_ok=True)
    env = environment(output / 'preparation-data', config, prefix)
    # A persistent file is not evidence of a live producer; this native lock is.
    with (output / 'preparation.guard').open('a') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        completed = []
        for count in COUNTS:
            directory = output / 'seeds' / str(count); fixture = directory / 'fixture.json'
            saved = directory / 'saved-snapshot.json'
            if saved.exists():
                previous = json.loads(saved.read_text())
                if previous['graphFilesSha256'] != graph_files(directory / 'source.egg'):
                    raise ValueError('A completed common fixture changed')
                completed.append(previous); continue
            logs = output / 'prepare' / str(count); logs.mkdir(parents=True, exist_ok=True)
            old = [int(p.name.split('.')[0].split('-')[1]) for p in logs.glob('attempt-*.*')]
            attempt = max(old, default=0) + 1; stem = f'attempt-{attempt:03}'
            command = [str(producer), 'prepare', str(directory), str(count)]
            started = time.monotonic(); code = None; timed_out = False
            with (logs / (stem + '.stdout')).open('xb') as stdout, (logs / (stem + '.stderr')).open('xb') as stderr:
                try:
                    code = subprocess.run(command, env=env, cwd=output, stdout=stdout, stderr=stderr, timeout=7200).returncode
                except subprocess.TimeoutExpired:
                    timed_out = True; raise
                finally:
                    save(logs / (stem + '.json'), dict(command=command, exitCode=code,
                        timedOut=timed_out, elapsedSeconds=time.monotonic() - started))
            if code:
                raise RuntimeError('Scale producer failed; retain its prefix and logs')
            value = json.loads(fixture.read_text())
            if (value['requestedWindows'] != count or value['windowReferences'] != count
                    or value['uniqueWindows'] != count or value['documents'] != (count - 31 if count >= 32 else count)
                    or value['producerContract'] != declaration['producerContract']):
                raise ValueError('The common fixture count or producer contract differs')
            result = dict(fixture=value, graphFilesSha256=graph_files(directory / 'source.egg'),
                          sourceSaved=True, warmComplete=False)
            save(saved, result); completed.append(result)
            print(json.dumps(dict(savedWindows=count, owners=value['documents'], warmComplete=False)), flush=True)
        save(output / 'result.json', dict(passed=True, fixtures=completed,
            generationModelCalls=0, embeddingCalls=0, productionAdoption=False))


if __name__ == '__main__':
    main()
