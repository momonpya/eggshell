"""Validate a prepared README trial before dispatch and retain its observed cost.

The preparation manifest binds a native preflight to one canonical snapshot,
question, runtime and private state. It is a measurement admission check, not a
proof of answer quality, memory causality or production adoption.
"""
import hashlib
import json
from pathlib import Path
import re
import tomllib

from semantic_latency import graph_files, save


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read(path):
    return json.loads(Path(path).read_text())


def tree_files(directory):
    return {str(p.relative_to(directory)): sha(p) for p in directory.rglob('*') if p.is_file()}


def publication_preserved(report, source, database):
    """Permit only derived rows and metadata for verified neutral revisions."""
    require(Path(report['before']) == source and Path(report['after']) == database,
            'Publication audit belongs to another pair of snapshots')
    require(report['authoritativeGraphEqual'] is True, 'Authoritative source changed')
    require(report['beforeRoots'] == report['afterRoots'] and
            report['beforeUnions'] == report['afterUnions'], 'Roots or unions changed')
    revisions = set()
    for publication in report['publications']:
        require(publication['neutral'] is True and not publication['added'] and
                not publication['removed'] and publication['unionsChanged'] is False,
                'Preparation published new authoritative evidence')
        revisions.add(str(publication['revision']))
    for row in report['changedRows']:
        if row['derived'] is True:
            continue
        match = re.fullmatch(r'change:(\d+)(?::\d+)?', row['key'])
        require(match is not None and match[1] in revisions,
                'Non-derived change is not metadata for a verified neutral revision')


def evidence_parts(body):
    return [(part.split('\n', 1)[0],
             part.split('  GROUNDED OUTCOME\n', 1)[1].split('  TRACE\n', 1)[0])
            for part in body.split('\nWORK GRAPH ') if '  GROUNDED OUTCOME\n' in part]


def validate_prepared_trial(base, protocol, arm, label, topic, prompt, environment_file):
    """Fail before opening App Server when preparation is missing or stale."""
    require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', label or '') is not None,
            'A trial needs a stable label')
    case = base / 'prepared' / label
    manifest = case / 'ready.json'
    expected = protocol.get('preparedTrialDigests', {}).get(label)
    require(expected is not None and manifest.is_file() and sha(manifest) == expected,
            'Freeze a verified preparation manifest before starting this trial')
    ready = read(manifest)
    planned = protocol['trials'][label]
    require(planned['arm'] == arm and planned['topic'] == topic,
            'Trial arm or topic differs from the frozen plan')
    for key in ['arm', 'topic', 'stage', 'repetition']:
        require(ready[key] == planned[key], 'Prepared trial differs from the frozen plan: ' + key)
    require(ready['label'] == label and ready['model'] == protocol['model'] and
            ready['effort'] == protocol['effort'] == 'xhigh', 'Prepared model settings differ')
    require(ready['promptSha256'] == hashlib.sha256(prompt.encode()).hexdigest(),
            'Prepared question differs')
    require(ready['sourceWorkspace'] == protocol['sourceWorkspace'], 'Prepared workspace differs')
    for name, filename in [('runnerSha256', 'readme_benchmark.py'),
                           ('transportSha256', 'pilot_server.py'),
                           ('trialGateSha256', 'readme_trial.py'),
                           ('memoryGuardSha256', 'memory_guard.py')]:
        require(ready[name] == protocol[name] == sha(Path(__file__).with_name(filename)),
                'Freeze the same runner, transport and admission checks for every condition')
    require(ready['environmentSha256'] == sha(environment_file), 'Prepared environment changed')
    environment = read(environment_file)
    account_config = Path(environment['CODEX_HOME']) / 'config.toml'
    require(ready['configurationSha256'] == sha(account_config), 'Model configuration changed')
    snapshot = protocol['sourceSnapshots'][str(planned['stage'])]
    source = Path(snapshot['directory'])
    require(ready['sourceSnapshot'] == snapshot and graph_files(source) == snapshot['files'],
            'Canonical saved snapshot changed')
    files = ready['files']
    for relative, digest in files.items():
        path = (case / relative).resolve()
        require(path.is_relative_to(case.resolve()) and path.is_file() and sha(path) == digest,
                'Prepared evidence file changed: ' + relative)

    def checked(relative):
        require(relative in files, 'Evidence file is not sealed: ' + relative)
        return case / relative

    memory = ready['memory']
    if arm == 'fresh':
        require(memory is None, 'Fresh trial has memory preparation')
        return dict(manifest=ready, environment=environment, expectedBodySha256=None)
    require(isinstance(memory, dict), 'Memory trial has no native preparation')
    database = Path(protocol['activeDatabase'])
    binary = Path(environment['EGGSHELL_PREFIX']) / 'libexec/eggshell'
    require(memory['runtimeSha256'] == protocol['candidate'] == sha(binary), 'Selected runtime changed')
    require(memory['database'] == str(database) and graph_files(database) == memory['graphFiles'],
            'Prepared active snapshot changed')
    config = checked(memory['configuration'])
    config_data = tomllib.loads(config.read_text())
    require(config_data['default'] == 'work' and config_data['eggs']['work'] == str(database) and
            config_data['profiles']['work']['read'] == ['work'] and
            config_data['profiles']['work']['write'] == 'work' and
            config_data['profiles']['work']['handoff_chars'] == 120000,
            'Memory configuration does not target the prepared DB and budget')
    data = (case / memory['dataRoot']).resolve()
    require(data.is_relative_to(case.resolve()) and data.is_dir(), 'Private state is not prepared')
    require(not list(data.glob('sessions/*/daemon.json')), 'A preparation daemon endpoint remains')
    require(tree_files(data) == memory['privateFiles'], 'Prepared private state changed')
    matcher = config_data.get('semantic_matcher')
    if matcher is not None:
        require(isinstance(matcher, list) and len(matcher) in [2, 4] and
                matcher[1] == 'search-provider' and sha(matcher[0]) == memory['runtimeSha256'],
                'Semantic provider differs from the selected runtime')
        if len(matcher) == 4:
            require(matcher[2] == '--cache' and memory.get('providerCache') is not None,
                    'Explicit provider cache is not sealed')
            cache = (case / memory['providerCache']).resolve()
            require(cache.is_relative_to(case.resolve()) and cache.is_dir() and
                    str(cache) == matcher[3] and tree_files(cache) == memory['providerFiles'],
                    'Prepared provider cache changed or is outside this private trial')
    environment.update(EGGSHELL_DATA_ROOT=str(data), EGGSHELL_CONFIG=str(config))
    report = read(checked(memory['publication']))
    publication_preserved(report, source, database)
    require(report['beforeHead'] == read(source / 'head') and
            report['afterHead'] == read(database / 'head'), 'Publication audit is stale')
    timing = read(checked(memory['preflightTiming']))
    require(timing['exitCode'] == 0 and 0 < timing['elapsedMs'] < 30000,
            'Native preflight failed or missed the hook deadline')
    request = read(checked(memory['preflightInput']))
    require(request['hook_event_name'] == 'UserPromptSubmit' and request['prompt'] == prompt and
            request['cwd'] == protocol['sourceWorkspace'] and request['_eggshell_config'] == str(config) and
            request['session_id'] == memory['preflightSession'],
            'Native preflight used another question, workspace, config or session')
    output = read(checked(memory['preflightStdout']))
    body = output.get('hookSpecificOutput', {}).get('additionalContext')
    require(isinstance(body, str) and bool(body.strip()) and 'EGGSHELL SEARCH INCOMPLETE' not in body,
            'Native preflight did not deliver a memory body')
    require(sha(checked(memory['body'])) == hashlib.sha256(body.encode()).hexdigest(),
            'Preflight body differs from captured stdout')
    state = read(checked(memory['preflightState']))
    require(state['lastHandoff'] == body and bool(state['deliveredGraphs']),
            'Native preflight body was not acknowledged')
    identity = read(database / 'head')['identity']
    for claim in state['deliveredGraphs']:
        if claim.startswith('a:'):
            _, frontier = json.loads(claim[2:])
            require(frontier['identity'] == identity and type(frontier['nextRoot']) is int and
                    frontier['nextRoot'] >= 0, 'Preflight contains a foreign or invalid DB advisory frontier')
    shutdown = read(checked(memory['shutdown']))
    require(shutdown['exit_code'] == shutdown['daemon_exit_code'] == 0,
            'Preparation daemon did not shut down cleanly')
    search = memory['searchReceipt']
    if protocol['structuredReceiptsAvailable']:
        require(search is not None and bool(memory['numericalReceipts']), 'Native search receipts are missing')
        require(read(checked(search))['data']['trace']['semantic'] == 'completed',
                'Warm semantic preflight did not complete')
        purposes = set()
        for relative in memory['numericalReceipts']:
            numerical = read(checked(relative))['data']
            purposes.add(numerical['corpus']['purpose'])
            source_count = numerical['counters']['source']
            require(numerical['status'] == 'completed' and source_count['absent'] == 0 and
                    source_count['unusable'] == 0 and source_count['hit'] > 0 and
                    numerical['counters']['encoder']['sourceEncodeUs'] == 0,
                    'Native preflight encoded missing sources or has unusable vectors')
        require(purposes == {'discovery', 'focus'}, 'Native preflight did not qualify both numerical lanes')
    else:
        require(search is None and memory['numericalReceipts'] is None,
                'Unavailable public receipt counters must stay unknown')
    inventory = read(checked(memory['evidenceAudit']))
    require(inventory['sourceGraphFiles'] == snapshot['files'] and bool(inventory['facts']),
            'Stored-memory audit belongs to another source')
    parts = evidence_parts(body)
    facts = []
    for fact in inventory['facts']:
        require(bool(fact['anchors']) and all(isinstance(a, str) and a for a in fact['anchors']),
                'Memory fact needs explicit source anchors')
        delivered = [owner for owner, evidence in parts if all(a in evidence for a in fact['anchors'])]
        facts.append(dict(name=fact['name'], storedOwners=fact['storedOwners'], deliveredOwners=delivered))
    require(any(set(f['storedOwners']) & set(f['deliveredOwners']) for f in facts),
            'No audited stored fact appears in the preflight evidence body')
    return dict(manifest=ready, environment=environment, facts=facts,
                expectedBodySha256=hashlib.sha256(body.encode()).hexdigest())


def capture_attempt(attempt, thread_id, completed=False):
    """Read the flushed RPC log, including cost notifications on failed turns."""
    hooks, usage, errors, reroutes = [], None, [], []
    malformed = False
    with (attempt / 'rpc/exchange.jsonl').open() as stream:
        for line in stream:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                malformed = True
                break
            if record['direction'] != 'server':
                continue
            message = record['message']
            method = message.get('method')
            params = message.get('params', {})
            if method == 'hook/completed':
                hooks.append(params['run'])
            if method == 'thread/tokenUsage/updated' and params['threadId'] == thread_id:
                usage = params['tokenUsage']['total']
            if method == 'error':
                errors.append(message)
            if method == 'model/rerouted':
                reroutes.append(message)
    save(attempt / 'hooks-completed.json', hooks)
    packets = []
    for index, hook in enumerate(hooks):
        for position, entry in enumerate(hook['entries']):
            if entry['kind'] != 'context':
                continue
            body = entry['text']
            path = attempt / f'packet-{index}-{position}.txt'
            path.write_text(body)
            packets.append(dict(event=hook['eventName'], file=path.name,
                bytes=len(body.encode()), sha256=sha(path), elapsedMs=hook['durationMs'], status=hook['status']))
    save(attempt / 'delivered-packets.json', packets)
    valid_usage = usage is not None and all(type(usage.get(key)) is int and usage[key] >= 0
        for key in ['totalTokens', 'inputTokens', 'outputTokens'])
    valid_usage = valid_usage and usage['totalTokens'] == usage['inputTokens'] + usage['outputTokens']
    final_usage_known = completed and valid_usage and not malformed
    result = dict(total=usage, finalUsageKnown=final_usage_known,
                  unknownFinalUsage=not final_usage_known, inclusiveSumMatches=valid_usage,
                  malformedRpc=malformed, errors=errors, reroutes=reroutes,
                  hookFailures=[dict(event=h['eventName'], status=h['status'], elapsedMs=h['durationMs'])
                      for h in hooks if h['status'] != 'completed' or h['durationMs'] >= 30000])
    save(attempt / 'usage.json', result)
    return result, packets


def validate_observed_trial(prepared, usage, packets, arm):
    require(usage['finalUsageKnown'] and not usage['errors'] and not usage['reroutes'],
            'Trial usage is unknown or generation errored/rerouted; retain all costs')
    require(not usage['hookFailures'], 'A native hook failed or missed its deadline')
    require(all(p['status'] == 'completed' and p['elapsedMs'] < 30000 for p in packets),
            'A delivered hook failed or missed its deadline')
    initial = [p for p in packets if p['event'] == 'userPromptSubmit']
    if arm == 'fresh':
        require(not packets, 'Fresh generation received hook context')
    else:
        require(len(initial) == 1 and initial[0]['sha256'] == prepared['expectedBodySha256'],
                'Actual initial body differs from the qualified preflight; retain this attempt without resubmitting')
