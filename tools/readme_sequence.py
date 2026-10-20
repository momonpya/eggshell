#!/usr/bin/env python3
"""Execute frozen matched README cells without resubmitting an existing turn."""
import argparse
import json
from pathlib import Path
import subprocess
import shutil

import readme_benchmark as bench
from context_native_probe import sha
from semantic_latency import graph_files, save


def attempt_path(label):
    attempt = bench.BASE / 'attempts' / label
    references = bench.BASE / 'fresh-references.json'
    if not attempt.exists() and label.startswith('fresh-') and references.exists():
        for reference in json.loads(references.read_text()):
            source = Path(reference['source'])
            if source.name == label:
                return source
    return attempt


def complete(label):
    attempt = attempt_path(label)
    result = json.loads((attempt / 'result.json').read_text())
    if not result['completed'] or result['usage'] is None:
        raise ValueError('Completed native turn with reported usage required: ' + label)
    if result['usage']['totalTokens'] != result['usage']['inputTokens'] + result['usage']['outputTokens']:
        raise ValueError('Inclusive usage disagrees: ' + label)
    return result


def observe_or_run(arm, label, topic):
    attempt = attempt_path(label)
    if attempt.exists():
        # A running or failed turn needs inspection. Its existence never
        # authorizes submitting the same measured model request a second time.
        return complete(label)
    bench.generation_protocol(arm, label)
    require_disk_space()
    bench.model_turn(arm, label, topic)
    return complete(label)


def require_disk_space():
    if shutil.disk_usage(bench.BASE).free < 2 * 1024**3:
        raise OSError('Need 2 GiB free before starting more benchmark work; preserve existing attempts')


def clone(source, destination):
    if destination.exists():
        raise ValueError('Snapshot destination already exists: ' + str(destination))
    subprocess.run(['/bin/cp', '-cR', str(source), str(destination)], check=True)


def restore(checkpoint, label):
    active = bench.active_database()
    before = bench.BASE / 'displaced' / (label + '.egg')
    before.parent.mkdir(exist_ok=True)
    if active.exists():
        active.rename(before)
    clone(checkpoint / 'work.egg', active)
    expected = graph_files(checkpoint / 'work.egg')
    if graph_files(active) != expected:
        raise ValueError('Common input graph changed during restoration')
    save(bench.BASE / 'inputs' / (label + '.json'), dict(checkpoint=str(checkpoint), graphFiles=expected))


def warm(checkpoint):
    database = checkpoint / 'work.egg'
    before = graph_files(database)
    env = json.loads((bench.BASE / 'environments/candidate/environment.json').read_text())
    env['EGGSHELL_DATA_ROOT'] = str(checkpoint / 'warm-data')
    config = checkpoint / 'warm.toml'
    binary = Path(env['EGGSHELL_PREFIX']) / 'libexec/eggshell'
    config.write_text('default = "work"\nsemantic_matcher = ' +
        json.dumps([str(binary), 'search-provider']) + '\n[eggs]\nwork = ' + json.dumps(str(database)) +
        '\n[profiles.work]\nread = ["work"]\nwrite = "work"\n')
    env['EGGSHELL_CONFIG'] = str(config)
    rows = []
    for phase in ['warm', 'repeat']:
        record = checkpoint / ('db-' + phase + '.json')
        if record.exists():
            captured = json.loads(record.read_text())
            if captured['exitCode'] != 0:
                raise ValueError('Retained warm failed; inspect before continuing')
            if captured['command'][-3:] != ['egg', 'warm', 'work']:
                raise ValueError('Retained warm did not select the configured writable DB')
        else:
            require_disk_space()
            local = dict(env, EGGSHELL_DATA_ROOT=str(checkpoint / ('warm-' + phase + '-data')))
            captured = bench.execute([binary, 'egg', 'warm', 'work'], local, record, 600)
            captured = dict(exitCode=captured.returncode, stdout=captured.stdout)
        row = json.loads(captured['stdout'])['databases'][0]
        after = row['after']
        if not (after['valid'] == after['windows'] > 0 and after['missing'] == after['invalid'] == 0):
            raise ValueError('Common checkpoint is not fully warm')
        if phase == 'repeat' and (row['requested'] or row['batches'] or row['lexical']['hydrated'] or row['lexical']['added']):
            raise ValueError('Warm repetition performed source work')
        rows.append(row)
    if graph_files(database) != before:
        raise ValueError('Warm changed the common source graph')
    if not (database / 'derived').is_dir():
        raise ValueError('Configured writable checkpoint did not acquire DB-owned cache')
    save(checkpoint / 'portable-warm-summary.json', dict(complete=True, rows=rows,
        graphFilesUnchanged=True, databaseOwned=True,
        independentPrivateDataRoots=[str(checkpoint / ('warm-' + phase + '-data')) for phase in ['warm', 'repeat']]))


def run(stage, checkpoint=None):
    if stage not in range(1, 7):
        raise ValueError('Expected one of the six predeclared stages')
    topic = (stage - 1) % 3 + 1
    protocol = json.loads((bench.BASE / 'protocol.json').read_text())
    environment = json.loads((bench.BASE / 'environments/candidate/environment.json').read_text())
    if sha(Path(environment['EGGSHELL_PREFIX']) / 'libexec/eggshell') != protocol['candidate']:
        raise ValueError('The installed candidate changed')
    checkpoint = checkpoint or bench.BASE / 'checkpoints' / ('seed' if stage == 1 else f'stage-{stage-1}')
    if not json.loads((checkpoint / 'portable-warm-summary.json').read_text())['complete']:
        raise ValueError('Complete the common checkpoint before model trials')
    original = graph_files(checkpoint / 'work.egg')
    reports = []
    for repetition in range(3):
        reference = f'fresh-topic{topic}-r{repetition}'
        observe_or_run('fresh', reference, topic)
        for arm in ['candidate']:
            label = f'stage{stage}-{arm}-r{repetition}'
            attempt = bench.BASE / 'attempts' / label
            if not attempt.exists():
                bench.generation_protocol(arm, label)
                restore(checkpoint, label)
            result = observe_or_run(arm, label, topic)
            executed_protocol = json.loads((attempt / 'protocol.json').read_text())
            archive = attempt / 'sequence-runner.py'
            if not archive.exists():
                if sha(Path(__file__)) != executed_protocol['sequenceRunnerSha256']:
                    raise ValueError('Cannot verify the executed sequence runner; keep the original attempt')
                shutil.copy2(Path(__file__), archive)
            if sha(archive) != executed_protocol['sequenceRunnerSha256']:
                raise ValueError('The archived sequence runner differs from its executed protocol')
            observed = json.loads((attempt / 'input-snapshot.json').read_text())['files']
            if observed != original:
                raise ValueError('Compared cells started from different saved graphs')
            reference_invocation = json.loads((attempt_path(reference) / 'invocation.json').read_text())
            invocation = json.loads((attempt / 'invocation.json').read_text())
            if any(invocation[key] != reference_invocation[key] for key in ['model', 'effort', 'promptSha256']):
                raise ValueError('Fresh and memory use different questions or model settings')
            expected_body = protocol.get('stageInitialBodies', {}).get(str(stage))
            if expected_body:
                packets = json.loads((attempt / 'delivered-packets.json').read_text())
                initial = [packet for packet in packets if packet['event'] == 'userPromptSubmit']
                if len(initial) != 1 or initial[0]['sha256'] != expected_body:
                    raise ValueError('The measured initial body differs from the native preflight')
            output = attempt / 'output.egg'
            if not output.exists():
                raise ValueError('Completed turn lacks its own archived output graph; inspect before resuming')
            if graph_files(output) != result['outputGraphFiles']:
                raise ValueError('Completed output graph changed')
            reports.append(dict(stage=stage, topic=topic, repetition=repetition, arm=arm,
                reference=reference, referenceSource=str(attempt_path(reference)),
                referenceResult=complete(reference), label=label, result=result))
            save(bench.BASE / 'results' / f'stage-{stage}.json', reports)
            if arm == 'candidate' and repetition == 0:
                next_checkpoint = bench.BASE / 'checkpoints' / f'stage-{stage}'
                if not next_checkpoint.exists():
                    next_checkpoint.mkdir()
                    clone(output, next_checkpoint / 'work.egg')
    if graph_files(checkpoint / 'work.egg') != original:
        raise ValueError('Measured calls changed the protected common checkpoint')
    warm(bench.BASE / 'checkpoints' / f'stage-{stage}')
    save(bench.BASE / 'results' / f'stage-{stage}-complete.json', dict(completed=True, cells=len(reports),
        topic=topic, priorCheckpointGraphFiles=original, source=bench.LLVM.as_posix(), productionAdoption=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=int, choices=range(1, 7), required=True)
    parser.add_argument('--study', type=Path)
    parser.add_argument('--checkpoint', type=Path)
    args = parser.parse_args()
    if args.study:
        bench.BASE = args.study
        bench.CANDIDATE = Path(json.loads((bench.BASE / 'protocol.json').read_text())['candidateSource'])
    run(args.stage, args.checkpoint)
