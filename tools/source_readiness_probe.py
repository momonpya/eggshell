#!/usr/bin/env python3
"""Replay captured tool observations through native hooks, without model turns."""
from pathlib import Path
import argparse
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import time

from semantic_latency import execute, graph_files, save
from owned_daemon import shutdown_owned

EXPERIMENTS = Path('/Users/ovm/.codex/experiments/eggshell')
BASE = EXPERIMENTS / 'readme-complete-index-20261021'
OUTPUT = EXPERIMENTS / 'readme-source-readiness-20261021'
CONSTRUCTION = EXPERIMENTS / 'source-readiness-20261021/construction-2'
LLVM = Path('/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=OUTPUT)
    parser.add_argument('--observations', type=Path,
        default=BASE / 'native-no-wait/recorded-observations.json')
    parser.add_argument('--case', action='append', choices=['baseline-immediate',
        'candidate-immediate', 'candidate-index-blocked', 'baseline-ready'])
    parser.add_argument('--construction', type=Path, default=CONSTRUCTION)
    args = parser.parse_args()
    output = args.output
    output.mkdir(mode=0o700)
    shutil.copy2(__file__, output / 'executed-runner.py')
    original_protocol = json.loads((BASE / 'protocol.json').read_text())
    manifest = json.loads((args.construction / 'manifest.json').read_text())
    baseline = Path(original_protocol['candidateSource']) / '.lake/build/bin/eggshell'
    candidate = Path(manifest['checkout']) / '.lake/build/bin/eggshell'
    assert sha(baseline) == original_protocol['candidate']
    assert sha(candidate) == manifest['runtimeSha256']
    cases = [('baseline-immediate', baseline, False), ('candidate-immediate', candidate, False),
             ('candidate-index-blocked', candidate, True), ('baseline-ready', baseline, False)]
    names = args.case or ['baseline-immediate', 'candidate-immediate', 'candidate-index-blocked']
    cases = [case for case in cases if case[0] in names]
    save(output / 'protocol.json', dict(scope='Identical saved DB, session/turn, question and captured observations through native hooks',
        generationAllowed=False, scheduledLabels=[], answeringModelCalls=0,
        externalWarmWait='baseline-ready' in names, sourceCommandsExecuted=False, adoptionEvidence=False,
        observationsPath=str(args.observations), observationsSha256=sha(args.observations),
        cases=[dict(name=n, runtimeSha256=sha(b), holdIndexClaim=held) for n,b,held in cases]))
    env_base = json.loads((BASE / 'environments/candidate/environment.json').read_text())
    common = EXPERIMENTS / 'readme-window-centroid-20261020/checkpoints/stage-2-public/work.egg'
    original = graph_files(common)
    active = Path(original_protocol['activeDatabase'])
    if active.exists():
        active.rename(output / 'previous-active.egg')
    reference = EXPERIMENTS / 'readme-window-centroid-20261020/attempts/stage3-candidate-r0'
    observations = json.loads(args.observations.read_text())
    assert len(observations) == 2
    save(output / 'recorded-observations.json', observations)
    session = 'source-readiness-native'
    rows = []
    for name, binary, hold in cases:
        case = output / name
        case.mkdir()
        subprocess.run(['/bin/cp', '-cR', str(common), str(active)], check=True)
        assert graph_files(active) == original
        config = case / 'eggshell.toml'
        config.write_text('default = "work"\nsemantic_matcher = ' +
            json.dumps([str(binary), 'search-provider']) + '\n[eggs]\nwork = ' +
            json.dumps(str(active)) + '\n[profiles.work]\nread = ["work"]\nwrite = "work"\nhandoff_chars = 120000\n')
        env = dict(env_base, EGGSHELL_CONFIG=str(config), EGGSHELL_DATA_ROOT=str(case / 'data'),
                   LEAN_NUM_THREADS='1', HF_HUB_OFFLINE='1')
        log = (case / 'manager.log').open('wb')
        manager = subprocess.Popen([str(binary), 'codex-daemon', session], cwd=LLVM, env=env,
            stdout=log, stderr=subprocess.STDOUT)
        lock = None
        steps = []

        def hook(event, label, tool=None):
            payload = dict(hook_event_name=event, session_id=session, turn_id='first',
                cwd=str(LLVM), _eggshell_config=str(config))
            if event == 'UserPromptSubmit':
                payload['prompt'] = (reference / 'prompt.txt').read_text()
            if tool:
                payload.update(tool_name=tool['name'], tool_use_id=tool['useId'],
                    tool_input=json.loads(tool['input']))
                if event == 'PostToolUse':
                    payload['tool_response'] = json.loads(tool['response'])
            output, record = execute([binary, 'codex-hook'], case / label, env, LLVM,
                (json.dumps(payload)+'\n').encode(), timeout=35)
            assert record['elapsedMs'] < 30000
            steps.append(dict(event=event, label=label, elapsedMs=record['elapsedMs'], outputSha256=sha(case / label / 'stdout')))
            return json.loads(output)

        try:
            endpoint = case / 'data/sessions' / session / 'daemon.json'
            expires = time.monotonic()+10
            while not endpoint.exists():
                assert manager.poll() is None and time.monotonic() < expires
                time.sleep(.005)
            hook('SessionStart', 'session-start')
            initial = hook('UserPromptSubmit', 'prompt')
            initial_body = initial['hookSpecificOutput']['additionalContext']
            assert initial_body == (BASE / 'native-preflight-topic3/body.txt').read_text()
            pre = hook('PreToolUse', 'first-pre', observations[0])
            assert pre.get('decision') != 'block'
            if hold:
                identity = json.loads((active / 'head').read_text())['identity']
                lock = (active / 'derived' / identity / 'index.guard').open('ab')
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                save(case / 'held-index-claim.json', dict(path=str(Path(lock.name)), managerPid=manager.pid,
                    lockOwnerPid=os.getpid(),
                    scope='Fault injection only; excludes independent warm completion until second-pre returns'))
            hook('PostToolUse', 'first-post', observations[0])
            if name == 'baseline-ready':
                started = time.monotonic()
                identity = json.loads((active / 'head').read_text())['identity']
                marker = None
                while time.monotonic()-started < 25:
                    for path in (active / 'derived' / identity / 'indexes').glob('*/warm'):
                        value = json.loads(path.read_text())
                        if value['database'] == identity and value['candidates'] == 59:
                            marker = dict(path=str(path), checkpoint=value,
                                waitedMs=1000*(time.monotonic()-started))
                            break
                    if marker:
                        break
                    assert manager.poll() is None
                    time.sleep(.025)
                assert marker is not None
                save(case / 'external-warm-barrier.json', marker)
            hook('PreToolUse', 'second-pre', observations[1])
            receipts = []
            for path in (case / 'data/receipts').glob('*/request.json'):
                request = json.loads(path.read_text())
                if request['data']['event'] == 'PreToolUse':
                    receipts.append((request['observedMs'], path.parent))
            assert len(receipts) == 2
            receipt = max(receipts, key=lambda row: row[0])[1]
            published = json.loads((receipt / 'published.json').read_text())['data']
            assert published['output'].encode() == (case / 'second-pre/stdout').read_bytes()
            assert published['sha256'] == sha(case / 'second-pre/stdout')
            search = json.loads((receipt / 'search.json').read_text())['data']
            numerical = [json.loads(p.read_text())['data'] for p in sorted(receipt.glob('numerical-*.json'))]
            readiness = receipt / 'source-readiness.json'
            readiness = json.loads(readiness.read_text())['data'] if readiness.exists() else None
            counters = [(n['counters'].get('encoder') or {}).get('sourceEncodeUs') for n in numerical]
            if name == 'candidate-immediate':
                assert readiness and readiness['complete'], readiness
                assert search['trace']['semantic'] == 'completed', search
                assert counters and all(c == 0 for c in counters), counters
            if name == 'baseline-ready':
                assert search['trace']['semantic'] == 'completed'
                assert counters and all(c == 0 for c in counters)
            if hold:
                assert readiness and not readiness['complete']
                assert search['trace']['route'] == 'lexical'
                assert not numerical, 'A readiness timeout must not start a numerical provider'
            row = dict(case=name, runtimeSha256=sha(binary), receipt=receipt.name,
                steps=steps, readiness=readiness, search=search, numerical=numerical,
                sourceEncodeCounters=counters, initialStdoutSha256=sha(case / 'prompt/stdout'),
                continuationStdoutSha256=sha(case / 'second-pre/stdout'),
                maxHookMs=max(step['elapsedMs'] for step in steps),
                answeringModelCalls=0, productionAdoption=False)
        finally:
            if lock:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
                lock.close()
            try:
                shutdown = shutdown_owned(manager, binary, env, LLVM, case / 'shutdown.json')
            finally:
                log.close()
        row['shutdown'] = shutdown
        active.rename(case / 'output.egg')
        rows.append(row)
        save(case / 'result.json', row)
        print(json.dumps({k: row[k] for k in ['case','receipt','readiness','sourceEncodeCounters','continuationStdoutSha256','maxHookMs']}), flush=True)
    assert graph_files(common) == original
    by_name = {row['case']: row for row in rows}
    comparison = all(name in by_name for name in ['baseline-immediate', 'candidate-immediate'])
    save(output / 'summary.json', dict(rows=rows, sameInitialReply=len({r['initialStdoutSha256'] for r in rows}) == 1,
        sameImmediateContinuationReply=(by_name['baseline-immediate']['continuationStdoutSha256'] ==
            by_name['candidate-immediate']['continuationStdoutSha256']) if comparison else None,
        commonGraphFilesUnchanged=True, originalSourceGraphFiles=original,
        answeringModelCalls=0, tokenEffectEstablished=False, productionAdoption=False))


if __name__ == '__main__':
    main()
