#!/usr/bin/env python3
"""Measure first and subsequent prompts in six real, warm LLVM sessions."""
import argparse
import fcntl
import json
from pathlib import Path
import subprocess
import time

from context_native_probe import environment, sha, tree
from focus_warm_probe import clone
from owned_daemon import shutdown_owned
from pilot_memory_probe import protected_databases
from prepare_context_candidate import input_manifest
from prepare_discovery_candidate import sources
from semantic_latency import execute, save
from semantic_scale import check_subject, classify, config


def sample(binary, cell, env, fixture, session, turn, question):
    destination = cell / turn
    if destination.exists():
        raise ValueError('A measured hook must never be resubmitted')
    before = json.loads((cell / 'data/sessions' / session / 'state.json').read_text())
    payload = dict(hook_event_name='UserPromptSubmit', session_id=session, turn_id=turn,
        cwd=fixture['workspace'], prompt=question, _eggshell_config=str(cell / 'config.toml'))
    failure = None
    try:
        execute([binary, 'codex-hook'], destination, env, cell,
            (json.dumps(payload, ensure_ascii=False) + '\n').encode(), timeout=35)
    except Exception as error:
        failure = f'{type(error).__name__}: {error}'
    output = (destination / 'stdout').read_bytes()
    timing = json.loads((destination / 'record.json').read_text())
    receipts = []
    for path in (cell / 'data/receipts').glob('*/request.json'):
        request = json.loads(path.read_text())['data']
        if (request.get('session'), request.get('turn'), request.get('event')) == (session, turn, 'UserPromptSubmit'):
            receipts.append(path.parent)
    if len(receipts) != 1:
        raise ValueError('Measured hook lost its unique receipt')
    receipt = receipts[0]
    def stage(name):
        path = receipt / (name + '.json')
        return json.loads(path.read_text())['data'] if path.exists() else None
    numerical = [json.loads(p.read_text())['data'] for p in sorted(receipt.glob('numerical-*.json'))]
    search = stage('search')
    row = classify(output, timing, stage('published'), stage('ack'), search, numerical, fixture)
    first = turn == 'first'
    policy = bool(search and search['initialSearch'] == first
        and search['semanticDeadlineMs'] <= search['deadlineMs']
        and search['semanticDeadlineMs'] - search['searchStartedMs'] <=
            min(15000 if first else 4500, (search['deadlineMs'] - search['searchStartedMs']) // 2))
    state = json.loads((cell / 'data/sessions' / session / 'state.json').read_text())
    policy = policy and state.get('searchStarted') is True and (first or before.get('searchStarted') is True)
    # A subsequent prompt may correctly omit a source already present in history.
    # Keep its actual body/ACK fields; do not count an empty result as a new delivery.
    passed = (policy and row['semanticComplete'] and row['publicationConfirmed']
        and timing.get('exitCode') == 0 and row['elapsedMs'] < (30000 if first else 5000)
        and (not first or row['sourceBodyDelivered'] and row['acknowledgementConfirmed']))
    return dict(row, session=session, turn=turn, question=question, initial=first,
        declaredBudgetPassed=passed, schedulingPolicyConfirmed=policy,
        retainedDeliveryKeysBefore=len(before['deliveredGraphs']),
        retainedDeliveryKeysAfter=len(state['deliveredGraphs']),
        receipt=receipt.name, observerError=failure, stdoutSha256=sha(destination / 'stdout'))


def run(args):
    build = args.build.resolve(); ready = args.ready_native.resolve(); scale = args.scale.resolve()
    output = args.output.resolve(); prefix = args.prefix.resolve()
    source = Path(__file__).resolve().parents[1]
    if any(output.is_relative_to(p) or p.is_relative_to(output) for p in [build, ready, scale, source]):
        raise ValueError('Use a separate observation directory')
    qualified = json.loads((build / 'result.json').read_text())
    frozen = json.loads((build / 'manifest.json').read_text())['sources']
    binary = build / 'checkout/.lake/build/bin/eggshell'
    if not qualified['passed'] or sha(binary) != qualified['candidateSha256'] or sources(build / 'checkout') != frozen:
        raise ValueError('Qualified candidate changed')
    original = json.loads((ready / 'result.json').read_text())
    if not original['inspectionComplete'] or not original['sourceAndVectorBytesUnchanged']:
        raise ValueError('Use the completed warm LLVM inputs')
    sealed = json.loads((scale / 'manifest.json').read_text())
    fixture = next(row for row in sealed['fixtures'] if row['label'] == 'actual-llvm')
    models = prefix / 'share/eggshell/minilm'
    if input_manifest(models) != sealed['encoderInputs']:
        raise ValueError('Encoder assets changed')
    check_subject(fixture)
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    save(output / 'manifest.json', dict(candidateSha256=qualified['candidateSha256'],
        qualificationManifestSha256=sha(build / 'manifest.json'), runnerSha256=sha(Path(__file__)),
        readyManifestSha256=sha(ready / 'manifest.json'), scaleManifestSha256=sha(scale / 'manifest.json'),
        fixture=fixture, layouts=['database', 'private-overlay'], questionsPerLayout=3,
        plannedNativeHooks=12, initialLimitMs=30000, continuationLimitMs=5000,
        semanticCapsMs=dict(initial=15000, continuation=4500),
        sequence='first prompt, then identical question in the same live session; delivered evidence stays in history',
        ownedDaemons=True, shutdownHelperSha256=sha(source / 'tools/owned_daemon.py'),
        oldFiveSecondClassificationRetained=True, generationModelCalls=0, productionAdoption=False))
    rows = []
    with (scale / 'run.guard').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for layout in ['database', 'private-overlay']:
            setup = json.loads((ready / layout / 'setup.json').read_text())
            if tree(ready / layout / 'source.egg') != setup['sourceTree']:
                raise ValueError('Original warm snapshot changed')
            for repetition, question in enumerate(fixture['questions']):
                cell = output / f'{layout}-{repetition}'; cell.mkdir(mode=0o700)
                database = cell / 'source.egg'; clone(ready / layout / 'source.egg', database)
                data = cell / 'data'; data.mkdir()
                protected = [database]
                if layout == 'private-overlay':
                    clone(ready / layout / 'data/read-cache', data / 'read-cache')
                    protected.append(data / 'read-cache')
                config(cell / 'config.toml', binary, database)
                env = environment(data, cell / 'config.toml', prefix)
                # A copied private index must be prepared for this runtime/data
                # root before measuring hooks. A copied directory is not evidence
                # that the destination satisfies the warm contract.
                vector_roots = list(database.glob('derived/**/vectors')) + list(data.glob('read-cache/**/vectors'))
                original_vectors = {str(path): tree(path) for path in vector_roots}
                source_before = tree(database)
                with protected_databases([database]):
                    raw, warm_timing = execute([binary, 'egg', 'warm', 'source'], cell / 'warm', env, cell, timeout=180)
                    warm = json.loads(raw)['databases'][0]
                    raw, doctor_timing = execute([binary, 'egg', 'doctor'], cell / 'doctor', env, cell, timeout=180)
                    doctor = json.loads(raw)['databases'][0]
                if (warm['requested'] or warm['batches'] or warm['after']['missing'] or warm['after']['invalid']
                        or warm['after']['valid'] != warm['after']['windows']
                        or doctor['state'] != 'warm' or not doctor['lexical']['ready']):
                    raise ValueError('Destination did not satisfy the complete warm precondition without encoding')
                if tree(database) != source_before or any(tree(Path(path)) != value for path, value in original_vectors.items()):
                    raise ValueError('Destination preparation changed source/vector bytes')
                if (data / 'read-cache').exists() and data / 'read-cache' not in protected:
                    protected.append(data / 'read-cache')
                before = [tree(path) for path in protected]
                save(cell / 'setup.json', dict(warm=warm, warmTiming=warm_timing,
                    doctor=doctor, doctorTiming=doctor_timing, sourceTree=source_before,
                    originalVectors=original_vectors, originalSourceAndVectorBytesUnchanged=True))
                session = f'initial-policy-{layout}-{repetition}'
                # Keep the manager owned by this runner so the descendant RSS
                # guard cannot lose it during rapid daemonization/reparenting.
                with protected_databases(protected), (cell / 'daemon.log').open('wb') as log:
                    daemon = subprocess.Popen([str(binary), 'codex-daemon', session],
                        env=env, cwd=cell, stdout=log, stderr=subprocess.STDOUT)
                    try:
                        expires = time.monotonic() + 5
                        while not (data / 'sessions' / session / 'daemon.json').exists():
                            if daemon.poll() is not None or time.monotonic() > expires:
                                raise RuntimeError('Owned daemon failed to publish its endpoint')
                            time.sleep(.005)
                        payload = dict(hook_event_name='SessionStart', session_id=session, turn_id='start',
                            cwd=fixture['workspace'], _eggshell_config=str(cell / 'config.toml'))
                        execute([binary, 'codex-hook'], cell / 'start', env, cell,
                            (json.dumps(payload) + '\n').encode(), timeout=35)
                        for turn in ['first', 'continuation']:
                            row = dict(sample(binary, cell, env, fixture, session, turn, question),
                                layout=layout, repetition=repetition)
                            rows.append(row); save(output / 'results.json', rows)
                            print(json.dumps({key: row[key] for key in ['layout', 'repetition', 'turn',
                                'elapsedMs', 'semanticComplete', 'sourceBodyDelivered', 'declaredBudgetPassed']}), flush=True)
                    finally:
                        shutdown_owned(daemon, binary, env, cell, cell / 'shutdown.json')
                if [tree(path) for path in protected] != before:
                    raise ValueError('Hook changed source or vector bytes')
    if sources(build / 'checkout') != frozen or sha(binary) != qualified['candidateSha256']:
        raise ValueError('Qualification changed')
    check_subject(fixture)
    if input_manifest(models) != sealed['encoderInputs']:
        raise ValueError('Encoder assets changed')
    save(output / 'result.json', dict(inspectionComplete=True, nativeHooks=len(rows),
        initialPassCount=sum(r['declaredBudgetPassed'] for r in rows if r['initial']),
        continuationPassCount=sum(r['declaredBudgetPassed'] for r in rows if not r['initial']),
        sourceAndVectorBytesUnchanged=True, generationModelCalls=0, productionAdoption=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['build', 'ready-native', 'scale', 'output', 'prefix']:
        parser.add_argument('--' + name, type=Path, required=True)
    run(parser.parse_args())
