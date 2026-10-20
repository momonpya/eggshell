#!/usr/bin/env python3
"""Reject plausible-looking incomplete native benchmark evidence."""
from copy import deepcopy
import argparse
import hashlib
import json
from pathlib import Path

from semantic_scale import classify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-fixture', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    fixture = dict(windowReferences=3, uniqueWindows=2, documents=2, bodyMarker='ORIGINAL_SAVED_BODY')
    stdout = (json.dumps(dict(hookSpecificOutput=dict(additionalContext='ORIGINAL_SAVED_BODY'))) + '\n').encode()
    record = dict(exitCode=0, elapsedMs=4999)
    published = dict(output=stdout.decode(), sha256=hashlib.sha256(stdout).hexdigest(), bytes=len(stdout),
                     replyComplete=True, flushedMs=10, deadlineMs=20)
    ack = dict(offerAccepted=True, rpcCompleted=True)
    search = dict(trace=dict(semantic='completed', route='configured'))
    numerical = [dict(status='completed', corpus=dict(purpose='discovery', documents=2, durableDocuments=2,
        windowReferences=3), counters=dict(scoredWindows=3,
            sourceInput=dict(windows=3, vectors=5, embeddedCharacters=12, tokenizerMappedCharacters=12),
            source=dict(hit=2, absent=0, unusable=0), encoder=dict(sourceEncodeUs=0)))]
    def evaluate(**changes):
        values = dict(stdout=stdout, record=record, published=published, ack=ack,
                      search=search, numerical=numerical, fixture=fixture)
        values.update(changes)
        return classify(**values)['gatePassed']
    assert evaluate(), 'Complete references with reused distinct cached keys must pass'
    checks = 1
    for path, value in [
        (['status'], 'running'), (['corpus', 'windowReferences'], 2), (['corpus', 'documents'], 1),
        (['counters', 'scoredWindows'], 2), (['counters', 'sourceInput', 'windows'], 2),
        (['counters', 'sourceInput', 'vectors'], 2),
        (['counters', 'sourceInput', 'embeddedCharacters'], 11),
        (['counters', 'source', 'hit'], 1), (['counters', 'source', 'absent'], 1),
        (['counters', 'encoder', 'sourceEncodeUs'], 1)]:
        changed = deepcopy(numerical); target = changed[0]
        for key in path[:-1]:
            target = target[key]
        target[path[-1]] = value
        assert not evaluate(numerical=changed), 'Incomplete or repaired discovery was accepted: ' + str(path)
        checks += 1
    for changes in [
        dict(published=None), dict(published=dict(published, sha256='different')),
        dict(published=dict(published, flushedMs=21)), dict(published=dict(published, replyComplete=False)),
        dict(ack=dict(ack, offerAccepted=False)), dict(ack=dict(ack, rpcCompleted=False)),
        dict(record=dict(record, elapsedMs=5000)), dict(record={}),
        dict(search=dict(trace=dict(semantic='pending', route='lexical'))), dict(numerical=[])]:
        assert not evaluate(**changes), 'Invalid publication, ACK, timing or route was accepted'
        checks += 1
    notice = (json.dumps(dict(systemMessage='ORIGINAL_SAVED_BODY', hookSpecificOutput=dict(additionalContext='notice only'))) + '\n').encode()
    notice_pub = dict(published, output=notice.decode(), sha256=hashlib.sha256(notice).hexdigest(), bytes=len(notice))
    assert not evaluate(stdout=notice, published=notice_pub), 'A notice-only response became original body delivery'
    checks += 1
    native = []
    if args.native_fixture:
        if args.output is None:
            parser.error('--output is required for native receipt replay')
        args.output.mkdir(parents=True, exist_ok=False, mode=0o700)
        seed = json.loads((args.native_fixture / 'reused-fixture.json').read_text())['seed']
        expected = dict(windowReferences=seed['windows'], uniqueWindows=seed['windows'],
                        documents=seed['documents'], bodyMarker='CONTEXT_ORIGINAL_BODY')
        for layout, label, should_pass in [
            ('database', 'database', True), ('database', 'database-cached', True),
            ('private-overlay', 'private-overlay', True), ('private-overlay', 'private-overlay-cached', True),
            ('private-overlay', 'changed-assets', False)]:
            cell = args.native_fixture / layout
            receipt_id = json.loads((cell / (label + '-result.json')).read_text())['receipt']
            receipt = cell / 'data/receipts' / receipt_id
            def stage(name):
                return json.loads((receipt / (name + '.json')).read_text())['data']
            stdout_path = cell / (label + '-hook/stdout')
            result = classify(stdout_path.read_bytes(),
                json.loads((cell / (label + '-hook/record.json')).read_text()),
                stage('published'), stage('ack'), stage('search'),
                [json.loads(p.read_text())['data'] for p in receipt.glob('numerical-*.json')], expected)
            assert result['gatePassed'] == should_pass, 'Native receipt classification differs: ' + label
            native.append(dict(label=label, expected=should_pass, result=result,
                stdoutSha256=hashlib.sha256(stdout_path.read_bytes()).hexdigest()))
        (args.output / 'result.json').write_text(json.dumps(dict(passed=True, cases=native,
            newNativeHooks=0, generationModelCalls=0), indent=2) + '\n')
    print(json.dumps(dict(passed=True, checks=checks, recordedNativeCases=len(native),
                          newNativeHooks=0, generationModelCalls=0)))


if __name__ == '__main__':
    main()
