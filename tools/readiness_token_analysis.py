#!/usr/bin/env python3
"""Audit completed readiness-cohort turns without changing inputs or model calls."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def completed(study, planned, protocol):
    condition, label = planned['condition'], planned['label']
    path = study / condition / 'attempts' / label
    result_file = path / 'result.json'
    if not result_file.exists():
        return dict(condition=condition, repetition=planned['repetition'], label=label,
            state='no-final-record' if path.exists() else 'not-submitted',
            failedRecordPresent=(path / 'failure.json').exists(), finalUsageKnown=False)
    result = read(result_file)
    usage = result.get('usage')
    assert result['completed'] and usage is not None
    assert usage['totalTokens'] == usage['inputTokens'] + usage['outputTokens']
    invocation = read(path / 'invocation.json')
    assert (invocation['model'], invocation['effort'], invocation['promptSha256']) == (
        protocol['model'], protocol['effort'], protocol['promptSha256'])
    assert invocation['transportSha256'] == protocol['transportSha256']
    assert sha(path / 'runner.py') == protocol['runnerSha256']
    assert sha(path / 'transport.py') == protocol['transportSha256']
    packets = read(path / 'delivered-packets.json')
    if condition != 'fresh':
        assert read(path / 'input-snapshot.json')['files'] == protocol['sourceGraphFiles']
        initial = [p for p in packets if p['event'] == 'userPromptSubmit']
        assert len(initial) == 1 and initial[0]['sha256'] == protocol['expectedInitialBodySha256']
        shutdown = read(path / 'shutdown.json')
        assert shutdown['exit_code'] == shutdown['daemon_exit_code'] == 0
    traces = Counter()
    probes = Counter()
    numerical = Counter()
    encodes = []
    source_readiness = []
    completed_reuse = []
    for file in (path / 'data/receipts').glob('*/search.json'):
        data = read(file)['data']
        traces[data['trace']['semantic']] += 1
        if data.get('completed') is not None and data['completed'] > 0:
            completed_reuse.append(dict(completed=data['completed'], equalityOrigin=data.get('equalityOrigin')))
        for row in file.parent.glob('numerical-*.json'):
            value = read(row)['data']
            numerical[value['status']] += 1
            source = value['counters']['source']
            assert set(source) == {'hit', 'absent', 'unusable'}
            probes.update(source)
            encodes.append((value['counters'].get('encoder') or {}).get('sourceEncodeUs'))
        readiness = file.parent / 'source-readiness.json'
        if readiness.exists():
            source_readiness.append(read(readiness)['data'])
    commands = {}
    items = Counter()
    usage_events = 0
    for line in (path / 'rpc/exchange.jsonl').open():
        message = json.loads(line)['message']
        if message.get('method') == 'item/completed':
            item = message['params']['item']
            items[item['type']] += 1
            if item['type'] == 'commandExecution':
                commands[item['id']] = item
        if message.get('method') == 'thread/tokenUsage/updated':
            usage_events += 1
    hooks = read(path / 'hooks-completed.json')
    recorded_usage = read(path / 'usage.json')
    return dict(condition=condition, repetition=planned['repetition'], label=label,
        state='completed', finalUsageKnown=True, usage=usage, elapsedSeconds=result['elapsedSeconds'],
        rawRpcSha256=sha(path / 'rpc/exchange.jsonl'), answerSha256=sha(path / 'answer.txt'),
        apiErrors=len(recorded_usage['errors']), modelReroutes=len(recorded_usage['reroutes']),
        hookCount=len(hooks), maxHookMs=max((h['durationMs'] for h in hooks), default=0),
        allHooksWithin30Seconds=all(h['durationMs'] < 30000 for h in hooks),
        semanticStatuses=dict(traces), numericalStatuses=dict(numerical),
        observedSourceProbes=dict(probes), sourceEncodeCounters=encodes,
        preparationReceipts=source_readiness, reportedCompletedReuse=completed_reuse,
        deliveredContextBytes=sum(p['bytes'] for p in packets), contextPackets=len(packets),
        completedCommandItems=len(commands),
        aggregatedCommandOutputBytes=sum(len((item.get('aggregatedOutput') or '').encode()) for item in commands.values()),
        completedItemTypes=dict(items), tokenUsageUpdateEvents=usage_events)


def audit(study):
    protocol = read(study / 'protocol.json')
    rows = [completed(study, planned, protocol) for planned in protocol['fixedOrder']]
    pairs = []
    for repetition in range(protocol['repetitions']):
        available = {r['condition']:r for r in rows if r['repetition'] == repetition and r['finalUsageKnown']}
        if set(available) != {'fresh', 'parent', 'candidate'}:
            continue
        fresh, parent, candidate = [available[name]['usage']['totalTokens'] for name in ['fresh','parent','candidate']]
        pairs.append(dict(repetition=repetition, freshTokens=fresh, parentTokens=parent, candidateTokens=candidate,
            parentSavingVsFresh=1-parent/fresh, candidateSavingVsFresh=1-candidate/fresh,
            candidateChangeVsParent=candidate/parent-1))
    complete = all(r['finalUsageKnown'] for r in rows)
    return dict(scope=protocol['scope'], plannedCalls=len(rows), completedCalls=sum(r['finalUsageKnown'] for r in rows),
        complete=complete, pairs=pairs, rows=rows,
        knownFinalTokens=sum(r['usage']['totalTokens'] for r in rows if r['finalUsageKnown']),
        sourceProbesMeaning='Observed provider probes, including partial failed scans; not unique DB-window coverage',
        usageEventMeaning='Raw notification count; does not establish the number of provider requests or a causal explanation',
        qualityAccepted=False, productionAdoption=False,
        adoptionGate='This cell does not replace all-topic first/history comparisons or source-supported quality review')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--study', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.study)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ['plannedCalls','completedCalls','complete','pairs','knownFinalTokens','qualityAccepted','productionAdoption']}))
