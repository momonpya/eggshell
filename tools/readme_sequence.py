#!/usr/bin/env python3
"""Execute frozen matched README cells without resubmitting an existing turn."""
import argparse
import json
from pathlib import Path
import subprocess

from readme_benchmark import BASE, LLVM, model_turn, execute
from semantic_latency import graph_files, save


def complete(label):
    attempt = BASE / 'attempts' / label
    result = json.loads((attempt / 'result.json').read_text())
    if not result['completed'] or result['usage'] is None:
        raise ValueError('Completed native turn with reported usage required: ' + label)
    if result['usage']['totalTokens'] != result['usage']['inputTokens'] + result['usage']['outputTokens']:
        raise ValueError('Inclusive usage disagrees: ' + label)
    return result


def observe_or_run(arm, label, topic):
    attempt = BASE / 'attempts' / label
    if attempt.exists():
        # A running or failed turn needs inspection. Its existence never
        # authorizes submitting the same measured model request a second time.
        return complete(label)
    model_turn(arm, label, topic)
    return complete(label)


def clone(source, destination):
    if destination.exists():
        raise ValueError('Snapshot destination already exists: ' + str(destination))
    subprocess.run(['/bin/cp', '-cR', str(source), str(destination)], check=True)


def restore(checkpoint, label):
    active = BASE / 'active/work.egg'
    before = BASE / 'displaced' / (label + '.egg')
    before.parent.mkdir(exist_ok=True)
    if active.exists():
        active.rename(before)
    clone(checkpoint / 'work.egg', active)
    expected = graph_files(checkpoint / 'work.egg')
    if graph_files(active) != expected:
        raise ValueError('Common input graph changed during restoration')
    save(BASE / 'inputs' / (label + '.json'), dict(checkpoint=str(checkpoint), graphFiles=expected))


def warm(checkpoint):
    database = checkpoint / 'work.egg'
    before = graph_files(database)
    env = json.loads((BASE / 'environments/candidate/environment.json').read_text())
    env['EGGSHELL_DATA_ROOT'] = str(checkpoint / 'warm-data')
    config = checkpoint / 'warm.toml'
    config.write_text('default = "work"\n[eggs]\nwork = ' + json.dumps(str(database)) +
        '\n[profiles.work]\nread = ["work"]\nwrite = "work"\n')
    env['EGGSHELL_CONFIG'] = str(config)
    binary = Path(env['EGGSHELL_PREFIX']) / 'libexec/eggshell'
    rows = []
    for phase in ['warm', 'repeat']:
        record = checkpoint / ('db-' + phase + '.json')
        if record.exists():
            captured = json.loads(record.read_text())
            if captured['exitCode'] != 0:
                raise ValueError('Retained warm failed; inspect before continuing')
        else:
            captured = execute([binary, 'egg', 'warm', database], env, record, 600)
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
        graphFilesUnchanged=True, databaseOwned=True, freshPrivateDataRoot=str(checkpoint / 'warm-data')))


def run(stage):
    if stage not in range(1, 7):
        raise ValueError('Expected one of the six predeclared stages')
    topic = (stage - 1) % 3 + 1
    checkpoint = BASE / 'checkpoints' / ('seed' if stage == 1 else f'stage-{stage-1}')
    if not json.loads((checkpoint / 'portable-warm-summary.json').read_text())['complete']:
        raise ValueError('Complete the common checkpoint before model trials')
    original = graph_files(checkpoint / 'work.egg')
    reports = []
    for repetition in range(3):
        reference = f'fresh-topic{topic}-r{repetition}'
        observe_or_run('fresh', reference, topic)
        for arm in (['public-main', 'candidate'] if repetition != 1 else ['candidate', 'public-main']):
            label = f'stage{stage}-{arm}-r{repetition}'
            attempt = BASE / 'attempts' / label
            if not attempt.exists():
                restore(checkpoint, label)
            result = observe_or_run(arm, label, topic)
            observed = json.loads((attempt / 'input-snapshot.json').read_text())['files']
            if observed != original:
                raise ValueError('Compared cells started from different saved graphs')
            output = attempt / 'output.egg'
            if not output.exists():
                raise ValueError('Completed turn lacks its own archived output graph; inspect before resuming')
            if graph_files(output) != result['outputGraphFiles']:
                raise ValueError('Completed output graph changed')
            reports.append(dict(stage=stage, topic=topic, repetition=repetition, arm=arm,
                reference=reference, label=label, result=result))
            save(BASE / 'results' / f'stage-{stage}.json', reports)
            if arm == 'candidate' and repetition == 0:
                next_checkpoint = BASE / 'checkpoints' / f'stage-{stage}'
                if not next_checkpoint.exists():
                    next_checkpoint.mkdir()
                    clone(output, next_checkpoint / 'work.egg')
    if graph_files(checkpoint / 'work.egg') != original:
        raise ValueError('Measured calls changed the protected common checkpoint')
    warm(BASE / 'checkpoints' / f'stage-{stage}')
    save(BASE / 'results' / f'stage-{stage}-complete.json', dict(completed=True, cells=len(reports),
        topic=topic, priorCheckpointGraphFiles=original, source=LLVM.as_posix(), productionAdoption=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=int, choices=range(1, 7), required=True)
    run(parser.parse_args().stage)
