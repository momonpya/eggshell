#!/usr/bin/env python3
"""Audit saved native-hook certification counts without dispatching a model.

Join receipts by the actual model thread/session ID, excluding preparation
sessions. `dispatch.completed` is process success, never a reuse count.
`search.completed` is recorded after delivery reconciliation; null means no
Handoff object, not zero matches in the internal discovery.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def aggregate(receipts):
    counts = [r['completed'] for r in receipts if r['completed'] is not None]
    return dict(searchReceipts=len(receipts), explicitCountReceipts=len(counts),
                explicitCompletedSum=sum(counts),
                positiveCompletedReceipts=sum(c > 0 for c in counts),
                noHandoffCountUnavailable=sum(r['completed'] is None for r in receipts),
                dispositions=dict(Counter(r['disposition'] for r in receipts)),
                equalityOriginPresent=sum(r['equalityOrigin'] is not None for r in receipts))


def audit(study):
    retired = read(study / 'retired.json')
    rows = []
    for trial in retired['rows']:
        if trial['condition'] == 'fresh':
            continue
        attempt = Path(trial['attempt'])
        session = read(attempt / 'thread.json')['thread']['id']
        manifest = read(attempt / 'prepared-trial.json')
        hooks = read(attempt / 'hooks-completed.json')
        reported = Counter(h['eventName'].lower() for h in hooks)
        root = study / trial['condition'] / 'prepared' / trial['label'] / 'data/receipts'
        requests = Counter()
        excluded = Counter()
        searches = []
        missing = []
        for directory in sorted(root.iterdir()):
            request_path = directory / 'request.json'
            if not request_path.exists():
                continue
            request = read(request_path)['data']
            if request['session'] != session:
                excluded[request['event']] += 1
                continue
            event = request['event']
            requests[event] += 1
            search_path = directory / 'search.json'
            if not search_path.exists():
                if event in ('UserPromptSubmit', 'PreToolUse', 'PostToolUse'):
                    missing.append(str(directory))
                continue
            data = read(search_path)['data']
            count = data['completed']
            assert count is None or (type(count) is int and count >= 0)
            reason_count = re.search(r'\bcompleted=(\d+)\b', data.get('reason') or '')
            if reason_count:
                assert count == int(reason_count[1])
            if count is None:
                assert data['disposition'] in ('empty', 'reconciled-empty'), data
            published = directory / 'published.json'
            dispatch = directory / 'dispatch.json'
            assert published.exists() and dispatch.exists()
            assert read(published)['data']['replyComplete'] is True
            assert read(dispatch)['data']['completed'] is True
            searches.append(dict(receipt=directory.name, event=event,
                lane='initial' if event == 'UserPromptSubmit' else 'during-turn',
                request=str(request_path), requestSha256=sha(request_path),
                search=str(search_path), searchSha256=sha(search_path),
                publishedSha256=sha(published), completed=count,
                disposition=data['disposition'], equalityOrigin=data['equalityOrigin'],
                reason=data.get('reason'), initialSearch=data['initialSearch']))
        # SessionEnd occurs after hooks-completed.json is captured. All other
        # actual native callbacks must match the app-server notification list.
        assert all(reported[event.lower()] == n for event, n in requests.items()
                   if event != 'SessionEnd'), (trial['label'], reported, requests)
        assert all(requests[event] == sum(r['event'] == event for r in searches)
                   for event in ('UserPromptSubmit', 'PreToolUse', 'PostToolUse'))
        assert not missing, missing
        packets = read(attempt / 'delivered-packets.json')
        assert all(sha(attempt / p['file']) == p['sha256'] for p in packets)
        rows.append(dict(label=trial['label'], condition=trial['condition'],
            stage=trial['stage'], repetition=trial['repetition'], session=session,
            model=manifest['model'], effort=manifest['effort'],
            runtimeSha256=manifest['memory']['runtimeSha256'],
            attempt=str(attempt), threadSha256=sha(attempt / 'thread.json'),
            hooksSha256=sha(attempt / 'hooks-completed.json'),
            deliveredPacketsSha256=sha(attempt / 'delivered-packets.json'),
            actualRequestEvents=dict(requests), appReportedHookEvents=dict(reported),
            excludedOtherSessionEvents=dict(excluded),
            initial=aggregate([r for r in searches if r['lane'] == 'initial']),
            duringTurn=aggregate([r for r in searches if r['lane'] == 'during-turn']),
            receipts=searches))
    by_stage = []
    for arm in sorted({r['condition'] for r in rows}):
        for stage in sorted({r['stage'] for r in rows}):
            trials = [r for r in rows if r['condition'] == arm and r['stage'] == stage]
            receipts = [receipt for r in trials for receipt in r['receipts']]
            by_stage.append(dict(condition=arm, stage=stage,
                repetitions=[r['repetition'] for r in trials],
                initial=aggregate([r for r in receipts if r['lane'] == 'initial']),
                duringTurn=aggregate([r for r in receipts if r['lane'] == 'during-turn'])))
    receipts = [receipt for r in rows for receipt in r['receipts']]
    return dict(scope='All saved completed memory-arm model trials in retired study; not later native-only development gates',
        study=str(study), retiredSha256=sha(study / 'retired.json'),
        complete=True, modelTrials=len(rows), modelCalls=0, newSeedCalls=0,
        initial=aggregate([r for r in receipts if r['lane'] == 'initial']),
        duringTurn=aggregate([r for r in receipts if r['lane'] == 'during-turn']),
        all=aggregate(receipts), byStage=by_stage, rows=rows,
        interpretation=[
            'Counts are published/reconciled certified reuse, not merely successful hook processes.',
            'Null is preserved: no Handoff object was available after reconciliation; internal discovery/certification counts are unknown.',
            'Preparation sessions are excluded by exact session ID; all actual initial and tool callbacks are covered.',
            'This retired LLVM investigation study cannot establish an empirical advantage for certification when no certified delivery was observed.',
            'Later native-only delivery gates do not evaluate certification during an answering model turn.'
        ], scriptSha256=sha(Path(__file__)))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--study', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.study)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ['complete', 'modelTrials', 'initial', 'duringTurn', 'all']}))
