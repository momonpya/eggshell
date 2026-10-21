#!/usr/bin/env python3
"""Join original evidence, actual delivery, commands and inclusive trial usage."""
import argparse
import json
from pathlib import Path

from readme_matched import normalized
from readme_trial import evidence_parts, read, sha
from semantic_latency import graph_files, save


def audit(base, stage, output):
    if output.exists():
        raise ValueError('Preserve earlier audits')
    if sha(base / 'plan.json') != (base / 'plan.sha256').read_text().strip():
        raise ValueError('Frozen plan changed')
    plan = read(base / 'plan.json')
    inventory = read(base / 'sources' / f'stage{stage}.json')
    rows = []
    for slot in [s for s in plan['slots'] if s['stage'] == stage]:
        attempt = Path(slot['study']) / 'attempts' / slot['label']
        row = dict(slot=slot, attempt=str(attempt), attempted=attempt.exists(),
                   complete=False, qualityAccepted=False)
        rows.append(row)
        if not attempt.exists():
            continue
        if not (attempt / 'usage.json').exists():
            row.update(finalUsageKnown=False, usage=None)
            continue
        usage = read(attempt / 'usage.json')
        row.update(finalUsageKnown=usage['finalUsageKnown'], usage=usage['total'],
                   failure=read(attempt / 'failure.json') if (attempt / 'failure.json').exists() else None)
        if not (attempt / 'result.json').exists():
            continue
        result = read(attempt / 'result.json')
        ready = read(attempt / 'prepared-trial.json')
        invocation = read(attempt / 'invocation.json')
        if (not result['completed'] or not usage['finalUsageKnown'] or row['failure'] or
                any(usage[k] for k in ['errors', 'reroutes', 'hookFailures'])):
            raise ValueError('Invalid completed trial; retain costs: ' + str(attempt))
        if result['usage'] != usage['total'] or usage['total']['totalTokens'] != sum(
                usage['total'][k] for k in ['inputTokens', 'outputTokens']):
            raise ValueError('Inconsistent inclusive token accounting')
        if (ready['sourceSnapshot']['files'] != inventory['sourceGraphFiles'] or
                invocation['model'] != plan['model'] or invocation['effort'] != plan['effort'] or
                invocation['promptSha256'] != sha(attempt / 'prompt.txt')):
            raise ValueError('Trial condition differs from the frozen study')
        initial = []
        packets = read(attempt / 'delivered-packets.json')
        for packet in packets:
            if sha(attempt / packet['file']) != packet['sha256']:
                raise ValueError('Captured packet changed')
            if packet['event'] == 'userPromptSubmit':
                initial += evidence_parts((attempt / packet['file']).read_text())
        commands = []
        for line in (attempt / 'rpc/exchange.jsonl').open():
            message = json.loads(line).get('message', {})
            if message.get('method') == 'item/completed' and message['params'].get('threadId') == result['threadId']:
                item = message['params']['item']
                if item['type'] == 'commandExecution':
                    commands.append(item)
        facts = []
        for fact in inventory['facts']:
            facts.append(dict(name=fact['name'], storedFullExcerptOwners=fact['fullExcerptOwners'],
                actualInitialFullExcerptOwners=[owner for owner, text in initial
                    if owner in fact['fullExcerptOwners'] and normalized(fact['excerpt']) in normalized(text)],
                laterCommandsWithFullExcerpt=[dict(id=c['id'], command=c['command']) for c in commands
                    if normalized(fact['excerpt']) in normalized(c.get('aggregatedOutput') or '')]))
        if slot['condition'] != 'fresh':
            if (read(attempt / 'keep.json')['exitCode'] != 0 or any(
                    read(attempt / 'shutdown.json')[k] != 0 for k in ['exit_code', 'daemon_exit_code']) or
                    graph_files(attempt / 'output.egg') != result['outputGraphFiles']):
                raise ValueError('Saved output or shutdown differs from completion record')
        row.update(complete=True, invocation=invocation, elapsedSeconds=result['elapsedSeconds'],
            initialPackets=[p for p in packets if p['event'] == 'userPromptSubmit'], facts=facts,
            commandCount=len(commands), commands=[dict(id=c['id'], command=c['command']) for c in commands],
            answer=str(attempt / 'answer.txt'), answerSha256=sha(attempt / 'answer.txt'))
    comparisons = []
    for repetition in range(3):
        group = {r['slot']['condition']: r for r in rows if r['slot']['repetition'] == repetition}
        if not all(r['complete'] for r in group.values()):
            continue
        if len({r['invocation']['promptSha256'] for r in group.values()}) != 1 or len({
                r['invocation']['transportSha256'] for r in group.values()}) != 1:
            raise ValueError('Matched prompt or transport differs')
        f, c, old = [group[k]['usage']['totalTokens'] for k in ['fresh', 'candidate', 'current']]
        comparisons.append(dict(repetition=repetition, fresh=f, candidate=c, current=old,
            freshRelativeReductionPercent=100 * (f-c) / f,
            currentRelativeReductionPercent=100 * (old-c) / old))
    report = dict(stage=stage, topic=(stage-1) % 3 + 1, lap=1 if stage <= 3 else 2,
        trials=rows, comparisons=comparisons, complete=all(r['complete'] for r in rows),
        knownConsumedTokens=sum(r['usage']['totalTokens'] for r in rows if r.get('usage')),
        attemptedFinalUsageUnknown=[r['slot']['label'] for r in rows if r['attempted'] and not r.get('finalUsageKnown')],
        planSha256=sha(base / 'plan.json'), seedAcquisitionSeparate=True, qualityAccepted=False,
        productionAdoption=False, limitations=[
            'Every repetition is retained; incomplete or failed usage is never zero.',
            'Observed source delivery and fewer rereads do not establish internal model attention.',
            'No quality or implementation acceptance follows from token savings alone.'])
    save(output, report)
    print(json.dumps({k:report[k] for k in ['stage', 'complete', 'comparisons', 'knownConsumedTokens']}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--stage', type=int, choices=range(1, 7), required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    audit(args.base, args.stage, args.output)
