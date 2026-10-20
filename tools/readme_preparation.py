"""Prepare one audited native trial without invoking an answering model."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

import readme_benchmark as bench
from memory_guard import require_guard
from owned_daemon import shutdown_owned
from readme_trial import publication_preserved, sha, tree_files, validate_prepared_trial
from semantic_latency import execute, graph_files, receipt_for, save


def clone(source, destination):
    if destination.exists():
        raise ValueError('Inspect existing prepared state instead of replacing it: ' + str(destination))
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['/bin/cp', '-cR', str(source), str(destination)], check=True)


def prepare_native_trial(base, label, evidence_file, private_template=None, provider_template=None):
    protocol_file = base / 'protocol.json'
    protocol = json.loads(protocol_file.read_text())
    require_guard(protocol)
    if protocol['generationAllowed'] or protocol['scheduledLabels']:
        raise ValueError('Close generation while preparing a native trial')
    trial = protocol['trials'][label]
    if trial['arm'] != 'candidate':
        raise ValueError('Native memory preparation needs the internal candidate arm')
    case = base / 'prepared' / label
    case.mkdir(parents=True, exist_ok=False)
    environment_file = base / 'environments/candidate/environment.json'
    environment = json.loads(environment_file.read_text())
    binary = Path(environment['EGGSHELL_PREFIX']) / 'libexec/eggshell'
    if sha(binary) != protocol['candidate']:
        raise ValueError('Installed runtime differs from the frozen condition')
    snapshot = protocol['sourceSnapshots'][str(trial['stage'])]
    source = Path(snapshot['directory'])
    original = graph_files(source)
    if original != snapshot['files']:
        raise ValueError('Canonical source changed before preparation')
    database = Path(protocol['activeDatabase'])
    if database.exists():
        displaced = base / 'displaced' / label
        displaced.parent.mkdir(exist_ok=True)
        if displaced.exists():
            raise ValueError('A displaced trial is already present')
        database.rename(displaced)
    clone(source, database)
    data = case / 'data'
    if private_template is None:
        data.mkdir()
    else:
        clone(private_template, data)
    matcher = [str(binary), 'search-provider']
    if provider_template is not None:
        cache = case / 'provider-cache'
        clone(provider_template, cache)
        matcher += ['--cache', str(cache)]
    config = case / 'config.toml'
    config.write_text('default = "work"\nsemantic_matcher = ' + json.dumps(matcher) +
        '\n[eggs]\nwork = ' + json.dumps(str(database)) +
        '\n[profiles.work]\nread = ["work"]\nwrite = "work"\nhandoff_chars = 120000\n')
    local = dict(environment, EGGSHELL_CONFIG=str(config), EGGSHELL_DATA_ROOT=str(data))
    if protocol['structuredReceiptsAvailable']:
        raw, _ = execute([binary, 'egg', 'warm', 'work'], case / 'warm', local, bench.LLVM, timeout=240)
        warm = json.loads(raw)['databases'][0]
        if warm['after']['missing'] or warm['after']['invalid']:
            raise ValueError('Source warm did not finish')
    prompts = json.loads((bench.ROOT / 'docs/benchmarks/llvm-three-topics.json').read_text())['prompts']
    prompt = prompts[trial['topic']].replace('<LLVM_SOURCE>', str(bench.LLVM))
    sessions = protocol['nativePreparationSessions']
    if sessions not in [1, 2]:
        raise ValueError('Fix one qualification, or one warmup plus one qualification, before generation')
    steps = []
    for index in range(sessions):
        call = case / f'native-{index}'
        call.mkdir()
        session = f'prepare-{label}-{index}'
        log = (call / 'manager.log').open('wb')
        manager = subprocess.Popen([str(binary), 'codex-daemon', session], cwd=bench.LLVM, env=local,
                                   stdout=log, stderr=subprocess.STDOUT)
        try:
            endpoint = data / 'sessions' / session / 'daemon.json'
            deadline = time.monotonic() + 10
            while not endpoint.exists():
                if manager.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('Native preparation daemon did not become ready')
                time.sleep(.01)
            for event in ['SessionStart', 'UserPromptSubmit']:
                request = dict(hook_event_name=event, session_id=session, turn_id='first',
                    cwd=str(bench.LLVM), _eggshell_config=str(config))
                if event == 'UserPromptSubmit':
                    request['prompt'] = prompt
                raw, timing = execute([binary, 'codex-hook'], call / event, local, bench.LLVM,
                                      (json.dumps(request) + '\n').encode(), timeout=35)
            response = json.loads(raw)
            body = response.get('hookSpecificOutput', {}).get('additionalContext', '')
            (call / 'body.txt').write_text(body)
            steps.append(dict(session=session, elapsedMs=timing['elapsedMs'], bodySha256=sha(call / 'body.txt'),
                incomplete='EGGSHELL SEARCH INCOMPLETE' in body))
        finally:
            try:
                shutdown_owned(manager, binary, local, bench.LLVM, call / 'shutdown.json')
            finally:
                if manager.poll() is None:
                    manager.terminate()
                    manager.wait(timeout=5)
                log.close()
    auditor = Path(protocol['publicationAuditor'])
    if sha(auditor) != protocol['publicationAuditorSha256']:
        raise ValueError('Publication auditor changed')
    raw, _ = execute([auditor, source, database], case / 'publication', local, bench.LLVM, timeout=120)
    publication_preserved(json.loads(raw), source, database)
    if graph_files(source) != original:
        raise ValueError('Preparing a trial changed the canonical source')
    call = case / f'native-{sessions - 1}'
    session = steps[-1]['session']
    shutil.copy2(data / 'sessions' / session / 'state.json', case / 'preflight-state.json')
    shutil.copy2(evidence_file, case / 'evidence.json')
    files = ['config.toml', 'preflight-state.json', 'evidence.json', 'publication/stdout',
        str(call.relative_to(case) / 'UserPromptSubmit/stdin'),
        str(call.relative_to(case) / 'UserPromptSubmit/stdout'),
        str(call.relative_to(case) / 'UserPromptSubmit/record.json'),
        str(call.relative_to(case) / 'body.txt'), str(call.relative_to(case) / 'shutdown.json')]
    memory = dict(runtimeSha256=sha(binary), database=str(database), graphFiles=graph_files(database),
        configuration='config.toml', dataRoot='data', privateFiles=tree_files(data),
        publication='publication/stdout', preflightInput=files[4], preflightStdout=files[5],
        preflightTiming=files[6], body=files[7], shutdown=files[8], preflightState='preflight-state.json',
        preflightSession=session, evidenceAudit='evidence.json', searchReceipt=None, numericalReceipts=None)
    if provider_template is not None:
        memory.update(providerCache='provider-cache', providerFiles=tree_files(case / 'provider-cache'))
    if protocol['structuredReceiptsAvailable']:
        receipt = receipt_for(data, session)
        published = json.loads((receipt / 'published.json').read_text())['data']
        acknowledged = json.loads((receipt / 'ack.json').read_text())['data']
        if published['output'].encode() != (call / 'UserPromptSubmit/stdout').read_bytes() or not acknowledged['offerAccepted']:
            raise ValueError('Native receipt does not acknowledge the captured stdout')
        memory['searchReceipt'] = str((receipt / 'search.json').relative_to(case))
        memory['numericalReceipts'] = [str(p.relative_to(case)) for p in sorted(receipt.glob('numerical-*.json'))]
        files += [memory['searchReceipt'], *memory['numericalReceipts']]
    ready = dict(label=label, **{key:trial[key] for key in ['arm', 'topic', 'stage', 'repetition']},
        model=protocol['model'], effort=protocol['effort'], sourceWorkspace=protocol['sourceWorkspace'],
        promptSha256=hashlib.sha256(prompt.encode()).hexdigest(),
        **{key:protocol[key] for key in ['runnerSha256', 'transportSha256', 'trialGateSha256', 'memoryGuardSha256']},
        environmentSha256=sha(environment_file), configurationSha256=sha(Path(environment['CODEX_HOME']) / 'config.toml'),
        sourceSnapshot=snapshot, memory=memory, files={relative:sha(case / relative) for relative in files},
        preparationSessions=steps, initialization=dict(privateTemplate=str(private_template) if private_template else None,
            providerTemplate=str(provider_template) if provider_template else None))
    save(case / 'ready.json', ready)
    protocol.setdefault('preparedTrialDigests', {})[label] = sha(case / 'ready.json')
    save(protocol_file, protocol)
    prepared = validate_prepared_trial(base, protocol, 'candidate', label, trial['topic'], prompt, environment_file)
    clone(database, case / 'input.egg')
    if graph_files(case / 'input.egg') != memory['graphFiles']:
        raise ValueError('Prepared input snapshot differs from the qualified active DB')
    save(case / 'qualification.json', dict(admitted=True, expectedBodySha256=prepared['expectedBodySha256'],
        facts=prepared['facts'], answeringModelCalls=0, productionAdoption=False))
    return prepared
