#!/usr/bin/env python3
"""Matched parent/candidate/fresh diagnostic for the retained LLVM topic-3 cell.

This fixes three repetitions before generation. It does not replace the remaining
first/history and topic-1/2 adoption requirements, or submit a public token arm.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

import readme_benchmark as bench
from semantic_latency import execute, graph_files, receipt_for, save
from owned_daemon import shutdown_owned

ROOT = Path(__file__).resolve().parents[1]
EXPERIMENTS = Path('/Users/ovm/.codex/experiments/eggshell')
BASE = EXPERIMENTS / 'readme-readiness-tokens-20261021'
GUARD = ROOT / '.lake/hook-audit/readiness-tokens-guarded.py'
COMMON = EXPERIMENTS / 'readme-window-centroid-20261020/checkpoints/stage-2-public/work.egg'
RUNTIMES = {
    'parent': (EXPERIMENTS / 'complete-index-20261021/construction-3/candidate/checkout',
        '57cceba86ee4b1e00bb35f0289ee0766b270c636fe47379e53ae1fde3e2d03cb'),
    'candidate': (EXPERIMENTS / 'source-readiness-20261021/construction-3/checkout',
        '19affc5411fbebb89f26373b00b9db77566b9c0a973dfdbd023b677a0e4c7745'),
}
ORDER = [(r, condition) for r, sequence in enumerate([
    ['fresh', 'parent', 'candidate'], ['parent', 'candidate', 'fresh'],
    ['candidate', 'fresh', 'parent']]) for condition in sequence]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clone(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    assert not destination.exists()
    subprocess.run(['/bin/cp', '-cR', str(source), str(destination)], check=True)


def choose(condition):
    bench.BASE = BASE / condition
    if condition != 'fresh':
        bench.CANDIDATE = RUNTIMES[condition][0]
    return 'fresh' if condition == 'fresh' else 'candidate'


def require_space():
    if shutil.disk_usage(BASE).free < 4*1024**3:
        raise OSError('Need 4 GiB free before another model trial; keep existing attempts')


def qualify_initial(condition):
    case = BASE / 'native-preflight' / condition
    case.mkdir(parents=True)
    arm = choose(condition)
    env = json.loads((bench.BASE / 'environments' / arm / 'environment.json').read_text())
    env['EGGSHELL_DATA_ROOT'] = str(case / 'data')
    binary = Path(env['EGGSHELL_PREFIX']) / 'libexec/eggshell'
    active = BASE / 'active/work.egg'
    clone(BASE / 'checkpoint/work.egg', active)
    session = 'readiness-cohort-preflight-' + condition
    log = (case / 'manager.log').open('wb')
    manager = subprocess.Popen([str(binary), 'codex-daemon', session], cwd=bench.LLVM, env=env,
        stdout=log, stderr=subprocess.STDOUT)
    try:
        expires = time.monotonic()+10
        while not (case / 'data/sessions' / session / 'daemon.json').exists():
            assert manager.poll() is None and time.monotonic() < expires
            time.sleep(.005)
        for event in ['SessionStart', 'UserPromptSubmit']:
            payload = dict(hook_event_name=event, session_id=session, turn_id='first',
                cwd=str(bench.LLVM), _eggshell_config=env['EGGSHELL_CONFIG'])
            if event == 'UserPromptSubmit':
                payload['prompt'] = (BASE / 'prompt.txt').read_text()
            output, timing = execute([binary, 'codex-hook'], case / event, env, bench.LLVM,
                (json.dumps(payload)+'\n').encode(), timeout=35)
            assert timing['elapsedMs'] < 30000
        body = json.loads(output)['hookSpecificOutput']['additionalContext']
        (case / 'body.txt').write_text(body)
        receipt = receipt_for(case / 'data', session)
        search = json.loads((receipt / 'search.json').read_text())['data']
        numbers = [json.loads(p.read_text())['data'] for p in receipt.glob('numerical-*.json')]
        assert search['trace']['semantic'] == 'completed'
        assert numbers and all(n['status']=='completed' and
            (n['counters'].get('encoder') or {}).get('sourceEncodeUs')==0 for n in numbers)
        result = dict(bodySha256=sha(case / 'body.txt'), elapsedMs=timing['elapsedMs'],
            sourceEncodingInSearch=0, search=search, numerical=numbers)
    finally:
        try:
            shutdown_owned(manager, binary, env, bench.LLVM, case / 'shutdown.json')
        finally:
            log.close()
    active.rename(case / 'output.egg')
    save(case / 'result.json', result)
    return result


def prepare():
    require = shutil.disk_usage(EXPERIMENTS).free
    assert require >= 4*1024**3, 'Reclaim only generated caches before preparation'
    BASE.mkdir(mode=0o700)
    shutil.copy2(__file__, BASE / 'prepared-driver.py')
    prompts = json.loads((ROOT / 'docs/benchmarks/llvm-three-topics.json').read_text())
    prompt = prompts['prompts'][3].replace('<LLVM_SOURCE>', str(bench.LLVM))
    (BASE / 'prompt.txt').write_text(prompt)
    original = graph_files(COMMON)
    clone(COMMON, BASE / 'checkpoint/work.egg')
    fixed = dict(scope='Topic 3 first-lap causal diagnostic; all other adoption cells remain open',
        model='gpt-5.6-luna', effort='xhigh', repetitions=3, topic=3,
        activeDatabase=str(BASE / 'active/work.egg'), generationAllowed=False, scheduledLabels=[],
        sourceGraphFiles=original, seedAcquisitionCalls=0, seedCostSeparate=True,
        promptSha256=sha(BASE / 'prompt.txt'), driverSha256=sha(Path(__file__)),
        transportSha256=sha(ROOT / 'tools/pilot_server.py'),
        runnerSha256=sha(ROOT / 'tools/readme_benchmark.py'),
        guardSha256=sha(GUARD),
        fixedOrder=[dict(repetition=r, condition=c, label=f'{c}-topic3-r{r}') for r,c in ORDER],
        accounting='input plus output including cached input and failed usage; unknown is not zero',
        current='Complete-index centroid parent, not public main', publicTokenArm=False,
        adoptionRequiresAllFirstAndHistoryCells=True, productionAdoption=False)
    save(BASE / 'protocol.json', fixed)
    for condition in ['fresh', 'parent', 'candidate']:
        sub = BASE / condition
        sub.mkdir()
        local = dict(fixed, condition=condition)
        if condition != 'fresh':
            source, runtime = RUNTIMES[condition]
            assert sha(source / '.lake/build/bin/eggshell') == runtime
            local.update(candidate=runtime, candidateSource=str(source))
        save(sub / 'protocol.json', local)
        arm = choose(condition)
        bench.prepare_fresh() if arm == 'fresh' else bench.prepare(arm)
    # Prepare one common portable cache, including both installed provider identities.
    for condition in ['parent', 'candidate']:
        arm = choose(condition)
        case = BASE / 'cache-preparation' / condition
        case.mkdir(parents=True)
        env = json.loads((bench.BASE / 'environments' / arm / 'environment.json').read_text())
        binary = Path(env['EGGSHELL_PREFIX']) / 'libexec/eggshell'
        config = case / 'eggshell.toml'
        config.write_text('default = "work"\nsemantic_matcher = '+json.dumps([str(binary),'search-provider'])+
            '\n[eggs]\nwork = '+json.dumps(str(BASE / 'checkpoint/work.egg'))+
            '\n[profiles.work]\nread = ["work"]\nwrite = "work"\n')
        for phase in ['warm','repeat']:
            local = dict(env, EGGSHELL_CONFIG=str(config), EGGSHELL_DATA_ROOT=str(case / (phase+'-data')))
            result = bench.execute([binary,'egg','warm','work'], local, case / (phase+'.json'), 180)
            row = json.loads(result.stdout)['databases'][0]
            assert row['after']['missing']==row['after']['invalid']==0
            assert row['requested']==row['batches']==0
            if phase=='repeat':
                assert row['lexical']['hydrated']==row['lexical']['added']==0
    assert graph_files(BASE / 'checkpoint/work.egg') == original == graph_files(COMMON)
    readiness = {condition:qualify_initial(condition) for condition in ['parent','candidate']}
    assert readiness['parent']['bodySha256']==readiness['candidate']['bodySha256']==\
        'b400ef432319f610a29cb0595469968ac67741b0c4e2761ab95d5d7aaf391033'
    criteria = EXPERIMENTS / 'readme-window-order-20261021/source-review-criteria.json'
    shutil.copy2(criteria, BASE / 'source-review-criteria.json')
    fixed.update(ready=True, nativePreflight=readiness,
        expectedInitialBodySha256=readiness['candidate']['bodySha256'])
    save(BASE / 'protocol.json', fixed)
    print(json.dumps(dict(ready=True, plannedModelCalls=9, answeringModelCallsSoFar=0,
        sourceGraphFilesUnchanged=True, publicTokenArm=False)), flush=True)


def usage_record(path):
    result = json.loads((path / 'result.json').read_text()) if (path / 'result.json').exists() else None
    reported = result.get('usage') if result else None
    if reported:
        assert reported['totalTokens']==reported['inputTokens']+reported['outputTokens']
    known = reported
    raw = path / 'rpc/exchange.jsonl'
    if known is None and raw.exists():
        for line in raw.open():
            try:message=json.loads(line)['message']
            except (ValueError,KeyError):continue
            if message.get('method')=='thread/tokenUsage/updated':
                known=message['params']['tokenUsage']['total']
    return dict(finalUsageKnown=bool(result and result['completed'] and reported),
        knownUsage=known, unknownFinalUsage=not bool(result and result['completed'] and reported))


def run():
    plan = json.loads((BASE / 'protocol.json').read_text())
    assert plan['ready'] and sha(Path(__file__))==plan['driverSha256']
    assert sha(ROOT / 'tools/readme_benchmark.py')==plan['runnerSha256']
    assert sha(ROOT / 'tools/pilot_server.py')==plan['transportSha256']
    assert sha(GUARD)==plan['guardSha256']
    assert subprocess.check_output(['codex','--version'],text=True).strip()=='codex-cli 0.145.0'
    lock=(BASE / 'cohort.guard').open('ab');fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
    ledger=[]
    try:
        for repetition,condition in ORDER:
            arm=choose(condition);label=f'{condition}-topic3-r{repetition}'
            protocol=bench.BASE / 'protocol.json';local=json.loads(protocol.read_text())
            attempt=bench.BASE / 'attempts' / label
            if attempt.exists():
                accounted=usage_record(attempt)
                assert accounted['finalUsageKnown'], 'Never resubmit an existing incomplete turn'
            else:
                require_space()
                assert not subprocess.check_output(['git','status','--porcelain'],cwd=bench.LLVM,text=True).strip()
                assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=bench.LLVM,text=True).strip()==\
                    '6dfe1677ab8dffbc6ec13d53a1e0215d75147689'
                if condition!='fresh':
                    binary=Path(json.loads((bench.BASE/'environments/candidate/environment.json').read_text())['EGGSHELL_PREFIX'])/'libexec/eggshell'
                    assert sha(binary)==local['candidate']
                    active=BASE/'active/work.egg'
                    if active.exists():
                        destination=BASE/'displaced'/label;destination.parent.mkdir(exist_ok=True)
                        active.rename(destination)
                    clone(BASE/'checkpoint/work.egg',active)
                    assert graph_files(active)==plan['sourceGraphFiles']
                local['scheduledLabels']=[label];save(protocol,local)
                save(BASE/'active-call.json',dict(condition=condition,label=label,pid=os.getpid(),
                    startedUtc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())))
                print(json.dumps(dict(starting=label)),flush=True)
                try:
                    bench.model_turn(arm,label,3)
                finally:
                    local['scheduledLabels']=[];save(protocol,local)
            accounted=usage_record(attempt)
            assert accounted['finalUsageKnown']
            invocation=json.loads((attempt/'invocation.json').read_text())
            assert (invocation['model'],invocation['effort'],invocation['promptSha256'])==\
                ('gpt-5.6-luna','xhigh',plan['promptSha256'])
            if condition!='fresh':
                assert json.loads((attempt/'input-snapshot.json').read_text())['files']==plan['sourceGraphFiles']
                packets=json.loads((attempt/'delivered-packets.json').read_text())
                initial=[p for p in packets if p['event']=='userPromptSubmit']
                assert len(initial)==1 and initial[0]['sha256']==plan['expectedInitialBodySha256']
            ledger.append(dict(condition=condition,repetition=repetition,label=label,attempt=str(attempt),**accounted))
            save(BASE/'accounting.json',ledger)
            print(json.dumps(dict(completed=label,inclusiveTokens=accounted['knownUsage']['totalTokens'])),flush=True)
        save(BASE/'execution.json',dict(complete=True,submittedTurns=9,qualityAccepted=False,productionAdoption=False))
    finally:
        all_attempts=[]
        for condition in ['fresh','parent','candidate']:
            choose(condition)
            local=json.loads((bench.BASE/'protocol.json').read_text());local['scheduledLabels']=[]
            save(bench.BASE/'protocol.json',local)
            for path in (bench.BASE/'attempts').glob('*'):
                if path.is_dir():all_attempts.append(dict(attempt=str(path),**usage_record(path)))
        save(BASE/'all-attempt-accounting.json',all_attempts)
        assert graph_files(BASE/'checkpoint/work.egg')==plan['sourceGraphFiles']
        lock.close()


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['prepare','run'])
    prepare() if parser.parse_args().action=='prepare' else run()
