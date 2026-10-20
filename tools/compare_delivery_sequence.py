#!/usr/bin/env python3
"""Replay a fixed observation prefix through warmed public/candidate delivery.

Only saved observations are supplied; their commands and the answering model
are never run. Every event uses a shared, fully published graph. Each condition
carries its own acknowledged delivery claims. This is a controlled delivery
counterfactual, not a replay of historical background scheduling or a token gate.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

import delivery_parity
from advisory_claims import rebind
from semantic_latency import execute, graph_files, save

ROOT = Path(__file__).resolve().parents[1]
EXPERIMENTS = Path('/Users/ovm/.codex/experiments/eggshell')
HISTORY = EXPERIMENTS / 'readme-continuation-audit-20261021'
STUDY = EXPERIMENTS / 'readme-public-equivalent-20261021'
ATTEMPT = STUDY / 'attempts/public-equivalent-topic3-r1'
PRIOR = EXPERIMENTS / 'readme-native-demand-parity-20261021/inspection-4'
LLVM = delivery_parity.LLVM
NAMES = ['public-warm', 'first-segment-control', 'complete-index-centroid']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clone(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['/bin/cp', '-cR', str(source), str(target)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--commands', type=int, default=19)
    parser.add_argument('--prepared', type=Path,
        help='Reuse verified private publications and warm records from a stopped diagnostic')
    args = parser.parse_args()
    assert 1 <= args.commands <= 19
    destination = args.output
    destination.mkdir(mode=0o700, parents=True)
    shutil.copy2(__file__, destination / 'executed-runner.py')
    shutil.copy2(ROOT / 'tools/DeliverySequenceAudit.lean', destination / 'executed-helper.lean')
    shutil.copy2(ROOT / 'tools/advisory_claims.py', destination / 'executed-advisory-claims.py')
    history = json.loads((HISTORY / 'r1-publication-history/summary.json').read_text())
    linked = json.loads((HISTORY / 'receipt-domains-and-cache-times.json').read_text())['rows']
    linked.sort(key=lambda row: json.loads((ATTEMPT / 'data/receipts' / row['receipt'] /
        'request.json').read_text())['observedMs'])
    assert len(linked) == 19
    observations = [json.loads(Path(row['recordedToolPath']).read_text()) for row in linked[:args.commands]]
    assert all(tool['useId'] == row['useId'] for tool, row in zip(observations, linked))
    request = json.loads((ATTEMPT / 'data/receipts' / linked[0]['receipt'] / 'request.json').read_text())['data']
    prompt = (STUDY / 'native-preflight-topic3/prompt.txt').read_text()
    source = Path(history['recordedDatabase'])
    source_files = graph_files(source)
    domains = {row['revision']: row for row in json.loads((HISTORY / 'r1-domains/summary.json').read_text())['rows']}
    heads = {head['revision']: head for head in history['heads']}
    for index, row in enumerate(linked[:args.commands]):
        revision = index + 2
        assert domains[revision]['documents'] == 58 + index
        for numerical in row['numerics']:
            assert revision in numerical['matchingRevisions']
        assert domains[revision + 1]['documents'] == 59 + index
    env = json.loads((STUDY / 'environments/candidate/environment.json').read_text())
    for key in ['EGGSHELL_CONFIG', 'CODEX_THREAD_ID']:
        env.pop(key, None)
    env.update(LEAN_NUM_THREADS='1', HF_HUB_OFFLINE='1')
    prior = json.loads((PRIOR / 'protocol.json').read_text())
    expected = {row['name']: row['runtimeSha256'] for row in prior['variants']}
    initial = EXPERIMENTS / 'readme-window-centroid-20261020/stage3-delivery-diagnosis'
    initial_packets = {name: json.loads((initial / (
        'centroid-uncensored' if name == 'complete-index-centroid' else name) /
        'handoff.json').read_text())['handoff'] for name in NAMES}
    logical_identity = heads[2]['identity']
    for packet in initial_packets.values():
        assert rebind(packet['deliveredGraphs'], prompt, logical_identity, logical_identity) == packet['deliveredGraphs']
    save(destination / 'protocol.json', dict(
        scope=__doc__, answeringModelCalls=0, sourceCommandsExecuted=False,
        generationAllowed=False, scheduledLabels=[], adoptionEvidence=False,
        commands=args.commands, eventsPerCondition=2 * args.commands,
        publicMain=prior['publicMain'], sourceFiles=source_files,
        observationsSha256=hashlib.sha256(json.dumps(observations,sort_keys=True).encode()).hexdigest(),
        observationReceiptIds=[row['receipt'] for row in linked[:args.commands]],
        warmedBeforeEveryEvent=True, synchronousAcknowledgement=True,
        historicalSchedulingReconstructed=False, nativeDeadlineGate=False,
        helperSourceSha256=sha(ROOT / 'tools/DeliverySequenceAudit.lean'), runtimes=expected,
        claimBindingSourceSha256=sha(ROOT / 'tools/advisory_claims.py'),
        initialBodySha256={name:hashlib.sha256(packet['text'].encode()).hexdigest()
            for name,packet in initial_packets.items()},
        preparedFrom=str(args.prepared) if args.prepared else None,
        logicalSourceIdentity=logical_identity,
        frontierBinding='Only advisory source IDs rebound after verified identical values/root IDs/order/windows; native observed and completion keys unchanged',
        pendingToolOrder='native receipt filename, matching loadToolReceipts',
        unpublishedStagedAllAllowed=True))
    save(destination / 'observations.json', observations)
    cases = {}
    for name in NAMES:
        case = destination / name
        case.mkdir()
        original = PRIOR / name / 'checkout'
        assert sha(original / '.lake/build/bin/eggshell') == expected[name]
        checkout = case / 'checkout'
        clone(original, checkout)
        shutil.copy2(ROOT / 'tools/DeliverySequenceAudit.lean', checkout / 'tools/DeliverySequenceAudit.lean')
        with (checkout / 'lakefile.lean').open('a') as stream:
            stream.write('\nlean_exe delivery_sequence_audit where\n  root := `tools.DeliverySequenceAudit\n')
        local = dict(env, EGGSHELL_DATA_ROOT=str(case / 'data'))
        execute(['lake', '--no-cache', 'build', 'delivery_sequence_audit'], case / 'build', local, checkout, timeout=300)
        assert sha(checkout / '.lake/build/bin/eggshell') == expected[name]
        cases[name] = dict(case=case, checkout=checkout, env=local,
            claims=initial_packets[name]['deliveredGraphs'], rows=[])
    # Rebuild only private publications with the public producer, preserving all
    # values, root/owner IDs and windows. Both sides read these identical bytes.
    public = cases['public-warm']
    rebuilder = public['checkout'] / '.lake/build/bin/rebuild_lexical_snapshot'
    prepared = {}
    for revision in range(2, args.commands + 3):
        if args.prepared:
            cell = args.prepared / 'publications' / str(revision)
            result = json.loads((cell / 'prepared.json').read_text())
            warm = json.loads((cell / 'warm/stdout').read_text())['databases'][0]
            assert json.loads((cell / 'warm/record.json').read_text())['exitCode'] == 0
            assert result['authoritativeGraphEqual'] and result['stableRootAndOwnerIds']
            assert result['documents'] == domains[revision]['documents']
            assert result['sourceHead'] == heads[revision]
            assert json.loads((cell / 'work.egg/head').read_text()) == result['destinationHead']
            assert warm['after']['missing'] == warm['after']['invalid'] == 0
            prepared[revision] = cell / 'work.egg'
            continue
        cell = destination / 'publications' / str(revision)
        raw = HISTORY / f'r1-domains/revision-{revision}/source.egg'
        assert json.loads((raw / 'head').read_text()) == heads[revision]
        database = cell / 'work.egg'
        stdout, _ = execute([rebuilder, raw, database], cell / 'rebuild', public['env'], LLVM, timeout=120)
        result = json.loads(stdout)
        assert result['authoritativeGraphEqual'] and result['stableRootAndOwnerIds']
        assert result['documents'] == domains[revision]['documents']
        save(cell / 'prepared.json', result)
        prepared[revision] = database
    final_database = prepared[args.commands + 2]
    cache = public['case'] / 'provider-cache'
    clone((args.prepared or PRIOR) / 'public-warm/provider-cache', cache)
    stdout, _ = execute([public['checkout'] / '.lake/build/bin/delivery_audit', 'inputs', final_database],
        public['case'] / 'inputs', public['env'], LLVM, timeout=120)
    delivery_parity.index_inputs('public-warm', public['case'], public['checkout'] / '.lake/build/bin/eggshell',
        public['env'], final_database, [json.loads(line) for line in stdout.decode().splitlines()])
    identity = json.loads((source / 'head').read_text())['identity']
    vectors = source / 'derived' / identity / 'semantic/vectors'
    modern = cases['complete-index-centroid']
    # Warm markers bind each private publication; cached immutable vectors can
    # be shared by content. No recorded publication or historical cache is edited.
    for revision, database in prepared.items():
        if args.prepared:
            continue
        cell = database.parent
        dbid = json.loads((database / 'head').read_text())['identity']
        clone(vectors, database / 'derived' / dbid / 'semantic/vectors')
        config = cell / 'warm.toml'
        config.write_text('default = "work"\n[eggs]\nwork = ' + json.dumps(str(database)) +
            '\n[profiles.work]\nread = ["work"]\nwrite = "work"\n')
        execute([modern['checkout'] / '.lake/build/bin/eggshell', 'egg', 'warm', 'work'],
            cell / 'warm', dict(modern['env'], EGGSHELL_CONFIG=str(config)), LLVM, timeout=180)
    active = destination / 'active/work.egg'
    inputs = []
    for index, tool in enumerate(observations):
        for event, count, revision in [('PreToolUse', index, index + 2), ('PostToolUse', index + 1, index + 3)]:
            # Native receipts are loaded by filename, not completion time.
            # The staged All edge retains that order and may be unpublished;
            # checkpoint saves publish single observations independently.
            prefix = [entry[1] for entry in sorted(
                (Path(row['recordedToolPath']).name, observation)
                for row, observation in zip(linked[:count], observations[:count]))]
            pending = dict(sessionId=request['session'], turnId=request['turn'], cwd=str(LLVM), prompt=prompt,
                profile='work', semanticMatcher=None, read=[], write=None, handoffChars=120000,
                localUnion=True, projection='automatic', tools=prefix, inFlight=[], sources=[],
                finalMessage=None, closed=False)
            current = linked[index]['work']
            assert current == tool['name'] + '\n' + tool['input']
            common = prepared[revision]
            before = graph_files(common)
            private_identity = json.loads((common / 'head').read_text())['identity']
            contexts = []
            for name in NAMES:
                variant = cases[name]
                cell = variant['case'] / f'{index:02}-{event}'
                cell.mkdir()
                clone(common, active)
                assert graph_files(active) == before
                bound = rebind(variant['claims'], prompt, logical_identity, private_identity)
                save(cell / 'claim-binding.json', dict(logicalSourceIdentity=logical_identity,
                    privateSourceIdentity=private_identity, stableRootAndOwnerIds=True,
                    originalClaims=variant['claims'], boundClaims=bound))
                demand = dict(pending=pending, current=current, claims=bound,
                    enforce=event=='PreToolUse', evidence=tool['response'] if event=='PostToolUse' else None)
                save(cell / 'demand.json', demand)
                execute([variant['checkout'] / '.lake/build/bin/delivery_sequence_audit', active,
                    cell / 'demand.json', variant['case'] / 'provider-cache', cell / 'handoff.json'],
                    cell / 'inspect', variant['env'], LLVM, timeout=310)
                result = json.loads((cell / 'handoff.json').read_text())
                raw, packet = result['handoff'], result['reconciled']
                assert raw is None or raw['reason'] != 'search-incomplete'
                assert all(result['observedRootsPublished'])
                assert graph_files(active) == before and graph_files(common) == before
                body = packet['text'] if packet else ''
                (cell / 'body.txt').write_text(body)
                variant['claims'] = rebind(result['nextClaims'], prompt, private_identity, logical_identity)
                row = dict(index=index,event=event,revision=revision,
                    bodySha256=sha(cell / 'body.txt'), bodyBytes=len(body.encode()),
                    completed=packet['completed'] if packet else 0,
                    blocksCurrent=packet['blocksCurrent'] if packet else False,
                    claims=len(variant['claims']),elapsedMs=result['elapsedMs'])
                variant['rows'].append(row)
                contexts.append({key:result[key] for key in ['current','question','targets','stagedValues','observedClaims']})
                shutil.rmtree(active)
                print(json.dumps(dict(implementation=name,**row)),flush=True)
                save(variant['case'] / 'partial-results.json',variant['rows'])
            assert contexts[0] == contexts[1] == contexts[2]
            left, control, candidate = [cases[name]['rows'][-1] for name in NAMES]
            assert cases['public-warm']['claims'] == cases['first-segment-control']['claims'], 'Public/control ledger divergence'
            inputs.append(dict(index=index,event=event,revision=revision,
                publicEqualsControl=left['bodySha256']==control['bodySha256'],
                publicEqualsCandidate=left['bodySha256']==candidate['bodySha256']))
            save(destination / 'partial-comparison.json',inputs)
    assert graph_files(source) == source_files
    save(destination / 'summary.json',dict(scope=__doc__,comparisons=inputs,
        rows={name:case['rows'] for name,case in cases.items()},
        sourceFilesUnchanged=True,answeringModelCalls=0,tokenEffectEstablished=False,
        nativeDeadlineGate=False,productionAdoption=False))


if __name__ == '__main__':
    main()
