#!/usr/bin/env python3
"""Audit existing native README records without invoking a model or changing a DB."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


def read(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def counts(values):
    return dict(sorted(Counter(values).items()))


def audit(attempt, terms):
    result = read(attempt / 'result.json') if (attempt / 'result.json').exists() else None
    commands = {}
    raw = attempt / 'rpc/exchange.jsonl'
    for line in raw.open():
        message = json.loads(line)['message']
        if message.get('method') != 'item/completed':
            continue
        item = message['params']['item']
        if item['type'] == 'commandExecution':
            commands[item['id']] = item
    groups = {}
    for item in commands.values():
        groups.setdefault(item['command'], []).append(item)
    duplicates = [dict(command=command, occurrences=len(items),
        ids=[item['id'] for item in items],
        exitCodes=[item.get('exitCode') for item in items],
        sameOutput=len({item.get('aggregatedOutput', '') for item in items}) == 1)
        for command, items in groups.items() if len(items) > 1]

    hook_path = attempt / 'hooks-completed.json'
    hooks = read(hook_path) if hook_path.exists() else []
    receipts = []
    for path in sorted((attempt / 'data/receipts').glob('*/search.json')):
        record = read(path)
        request = path.parent / 'request.json'
        event = read(request)['data']['event'] if request.exists() else None
        numerics = []
        for numeric in sorted(path.parent.glob('numerical-*.json')):
            data = read(numeric)['data']
            counters = data.get('counters', {})
            corpus = data.get('corpus', {})
            numerics.append(dict(status=data.get('status'), purpose=corpus.get('purpose'),
                documents=corpus.get('documents'), durableDocuments=corpus.get('durableDocuments'),
                sourceAbsent=counters.get('source', {}).get('absent'),
                sourceUnusable=counters.get('source', {}).get('unusable'),
                sourceEncodeUs=counters.get('encoder', {}).get('sourceEncodeUs')))
        data = record['data']
        published = path.parent / 'published.json'
        context = None
        if published.exists():
            output = json.loads(read(published)['data']['output'])
            context = output.get('hookSpecificOutput', {}).get('additionalContext')
        receipts.append(dict(receipt=path.parent.name, event=event,
            disposition=data.get('disposition'), reason=data.get('reason'), trace=data.get('trace'),
            searchStartedMs=data.get('searchStartedMs'),
            semanticDeadlineMs=data.get('semanticDeadlineMs'),
            semanticFinishDeadlineMs=data.get('semanticFinishDeadlineMs'),
            observedMs=record['observedMs'], numerical=numerics,
            publishedContextCharacters=len(context) if context is not None else None,
            publishedContextHasNonWhitespace=bool(context and context.strip()),
            publishedIncomplete=bool(context and 'EGGSHELL SEARCH INCOMPLETE' in context)))
    initial = attempt / 'packet-1-0.txt'
    text = initial.read_text() if initial.exists() else ''
    trace = attempt / 'data/semantic/matcher-trace.jsonl'
    malformed = []
    if trace.exists():
        for number, line in enumerate(trace.open(), 1):
            try:
                json.loads(line)
            except json.JSONDecodeError:
                malformed.append(number)
    numerical = [numeric for row in receipts for numeric in row['numerical']]
    failures = [row for row in receipts if any(numeric['status'] == 'failed' for numeric in row['numerical'])]
    return dict(attempt=str(attempt), completed=bool(result and result['completed']),
        usage=result.get('usage') if result else None,
        rawRpcSha256=digest(raw), completedCommandItems=len(commands),
        completedCommandExecutions=sum(item.get('exitCode') is not None for item in commands.values()),
        commandItemStatuses=counts(item.get('status') or 'unreported' for item in commands.values()),
        commandsWithoutReportedExit=[item['id'] for item in commands.values() if item.get('exitCode') is None],
        duplicateCommands=duplicates, hookCounts=counts(h['eventName'] for h in hooks),
        incompleteHookCounts=counts(h['eventName'] for h in hooks
            if any('EGGSHELL SEARCH INCOMPLETE' in e.get('text', '') for e in h['entries'])),
        numericalStatusCounts=counts(n['status'] for n in numerical),
        numericalFailures=len(failures),
        failedNumericalWithMissingDurableWindows=sum(any(n['status'] == 'failed' and
            n['documents'] == n['durableDocuments'] and (n['sourceAbsent'] or 0) > 0
            for n in row['numerical']) for row in failures),
        initialBodySha256=digest(initial) if initial.exists() else None,
        initialTermCounts={term: text.count(term) for term in terms},
        toolOutputsContainingTerms={term: [item['id'] for item in commands.values()
            if term in (item.get('aggregatedOutput') or '')] for term in terms},
        malformedLegacyMatcherTraceLines=malformed,
        receipts=receipts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--attempt', action='append', type=Path, required=True)
    parser.add_argument('--term', action='append', default=[])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = dict(scope='Observed records only; not a causal attribution, token forecast, or quality approval',
        generationModelCalls=0, databaseWrites=0, productionAdoption=False,
        auditorSha256=digest(Path(__file__)),
        attempts=[audit(path, args.term) for path in args.attempt])
    # Refuse to replace an earlier diagnostic record.
    with args.output.open('x') as output:
        json.dump(report, output, ensure_ascii=False, indent=2)
        output.write('\n')
    for row in report['attempts']:
        print(json.dumps({key: row[key] for key in ['attempt', 'completed',
            'completedCommandExecutions', 'incompleteHookCounts', 'numericalFailures',
            'failedNumericalWithMissingDurableWindows']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
