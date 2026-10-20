#!/usr/bin/env python3
"""Compare public delivery with isolated candidates on one retained native demand.

The first failed continuation has an initial offer followed by an empty pre-tool
and empty post-tool reply. Its shared ledger can therefore be reconstructed from
the acknowledged initial claims plus the one observed native Outcome. No model
turn or repository command is executed. This is a delivery diagnostic, not a
token benchmark or a replay of historical asynchronous scheduling.
"""
from pathlib import Path
import argparse
import hashlib
import json
import difflib
import shutil
import subprocess

from semantic_latency import execute, graph_files, save

ROOT = Path(__file__).resolve().parents[1]
EXPERIMENTS = Path('/Users/ovm/.codex/experiments/eggshell')
HISTORY = EXPERIMENTS / 'readme-continuation-audit-20261021'
PRIOR = HISTORY / 'first-failure-comparison'
STUDY = EXPERIMENTS / 'readme-public-equivalent-20261021'
ATTEMPT = STUDY / 'attempts/public-equivalent-topic3-r1'
LLVM = Path('/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project')
DESTINATION = EXPERIMENTS / 'readme-native-demand-parity-20261021'
VARIANTS = [
    ('public-warm', PRIOR / 'public-warm/checkout',
     '959809379df896e464da5419398187b714d26fc90d87004f434a36be681bd2f3'),
    ('first-segment-control', PRIOR / 'first-segment-control/checkout',
     '1163d25957be0c601044450f1459e708f77d3f30e109450cdb9820ce916207fc'),
    ('complete-index-centroid', EXPERIMENTS / 'complete-index-20261021/construction-3/candidate/checkout',
     '57cceba86ee4b1e00bb35f0289ee0766b270c636fe47379e53ae1fde3e2d03cb'),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clone(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['/bin/cp', '-cR', str(source), str(target)], check=True)


def packet_differences(destination, implementations):
    """Keep exact owner/excerpt differences; their size is not a token metric."""
    packets = {}
    bodies = {}
    for name in implementations:
        handoff = json.loads((destination / name / 'handoff.json').read_text())['reconciled']
        parts = (handoff.get('packet') or {}).get('parts', []) if handoff else []
        current = {}
        for part in parts:
            context = part['context']
            owner = context['owner'] if context else part['text'].splitlines()[0].removeprefix('WORK GRAPH ')
            assert owner not in current
            current[owner] = dict(partSha256=hashlib.sha256(part['text'].encode()).hexdigest(),
                context=context)
        packets[name] = current
        bodies[name] = (destination / name / 'reconciled-body.txt').read_text()
    public = packets['public-warm']
    rows = []
    for name, packet in packets.items():
        row = dict(implementation=name, parts=len(packet),
            removed=sorted(public.keys() - packet.keys()), added=sorted(packet.keys() - public.keys()),
            changed=sorted(key for key in public.keys() & packet.keys()
                if public[key]['partSha256'] != packet[key]['partSha256']))
        rows.append(row)
        (destination / (name + '-vs-public.diff')).write_text(''.join(difflib.unified_diff(
            bodies['public-warm'].splitlines(True), bodies[name].splitlines(True),
            fromfile='public-warm', tofile=name)))
    save(destination / 'packet-owner-differences.json', dict(
        scope='Exact shared-demand packet parts and contexts; not a relevance, quality or token verdict',
        rows=rows, packets=packets))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=DESTINATION)
    parser.add_argument('--resume', action='store_true',
        help='Reuse completed, verified commands; retain the original executed runner')
    args = parser.parse_args()
    destination = args.output
    destination.mkdir(mode=0o700, exist_ok=args.resume)
    runner = 'executed-resume-runner.py' if args.resume else 'executed-runner.py'
    assert not (destination / runner).exists()
    shutil.copy2(__file__, destination / runner)
    linked = json.loads((HISTORY / 'receipt-domains-and-cache-times.json').read_text())
    ordered = sorted(linked['rows'], key=lambda row: json.loads(
        (ATTEMPT / 'data/receipts' / row['receipt'] / 'request.json').read_text())['observedMs'])
    first, failure = ordered[:2]
    assert failure['receipt'].startswith('ab3d2b1b')
    receipts = ATTEMPT / 'data/receipts'
    cutoff = json.loads((receipts / failure['receipt'] / 'request.json').read_text())['observedMs']
    preceding = []
    for directory in receipts.iterdir():
        if not (directory / 'request.json').exists():
            continue
        request = json.loads((directory / 'request.json').read_text())
        if request['observedMs'] < cutoff:
            preceding.append((request['observedMs'], directory, request['data']))
    preceding.sort()
    assert [row[2]['event'] for row in preceding] == [
        'SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse']
    for _, directory, request in preceding[2:]:
        output = json.loads(json.loads((directory / 'published.json').read_text())['data']['output'])
        assert not output.get('hookSpecificOutput', {}).get('additionalContext')
        assert json.loads((directory / 'search.json').read_text())['data']['disposition'] in [
            'empty', 'reconciled-empty']
        ack = directory / 'ack.json'
        if ack.exists():
            assert json.loads(ack.read_text())['data']['offerAccepted'] is False
    initial_receipt = preceding[1][1]
    assert json.loads((initial_receipt / 'ack.json').read_text())['data']['offerAccepted'] is True
    initial = EXPERIMENTS / 'readme-window-centroid-20261020/stage3-delivery-diagnosis/public-warm'
    initial_handoff = json.loads((initial / 'handoff.json').read_text())['handoff']
    initial_output = json.loads(json.loads((initial_receipt / 'published.json').read_text())['data']['output'])
    assert initial_handoff['text'] == initial_output['hookSpecificOutput']['additionalContext']
    tool = json.loads(Path(first['recordedToolPath']).read_text())
    assert tool['useId'] == first['useId']
    session = preceding[1][2]['session']
    turn = preceding[1][2]['turn']
    pending = dict(sessionId=session, turnId=turn, cwd=str(LLVM),
        prompt=(STUDY / 'native-preflight-topic3/prompt.txt').read_text(),
        profile='work', semanticMatcher=None, read=[], write=None,
        handoffChars=120000, localUnion=True, projection='automatic',
        tools=[tool], inFlight=[], sources=[], finalMessage=None, closed=False)
    demand = dict(pending=pending, current=failure['work'],
        initialClaims=initial_handoff['deliveredGraphs'], staged=True)
    if (destination / 'demand.json').exists():
        assert args.resume and json.loads((destination / 'demand.json').read_text()) == demand
    else:
        save(destination / 'demand.json', demand)
    original = graph_files(PRIOR / 'prepared-common.egg')
    recorded = graph_files(ATTEMPT / 'output.egg')
    protocol = dict(
        scope='First failed continuation: same fully warm publication, observed ToolEvent, initial claims, native targets, staging and proposed Work',
        originalReceipt=failure['receipt'], precedingReceipts=[row[1].name for row in preceding],
        demandSha256=sha(destination / 'demand.json'), sourceGraphFiles=original,
        source= str(PRIOR / 'prepared-common.egg'), publicMain='51873167c11c447a0af67e73430b5ab6635b2a65',
        answeringModelCalls=0, generationAllowed=False, scheduledLabels=[],
        historicalCacheStateReconstructed=False, nativeTransportReplay=False,
        adoptionEvidence=False, variants=[dict(name=n, checkout=str(p), runtimeSha256=s)
            for n,p,s in VARIANTS])
    if (destination / 'protocol.json').exists():
        assert args.resume and json.loads((destination / 'protocol.json').read_text()) == protocol
    else:
        save(destination / 'protocol.json', protocol)
    env = json.loads((STUDY / 'environments/candidate/environment.json').read_text())
    for key in ['EGGSHELL_CONFIG', 'CODEX_THREAD_ID']:
        env.pop(key, None)
    env.update(LEAN_NUM_THREADS='1', HF_HUB_OFFLINE='1')
    rows = []
    contexts = []
    active = destination / 'active/work.egg'
    for name, original_checkout, runtime in VARIANTS:
        cell = destination / name
        cell.mkdir(exist_ok=args.resume)
        checkout = cell / 'checkout'
        assert sha(original_checkout / '.lake/build/bin/eggshell') == runtime
        source = (ROOT / 'tools/DeliveryDemandAudit.lean').read_text()
        local = dict(env, EGGSHELL_DATA_ROOT=str(cell / 'data'))
        if checkout.exists():
            assert args.resume
            assert (checkout / 'tools/DeliveryDemandAudit.lean').read_text() == source
            assert json.loads((cell / 'build/record.json').read_text())['exitCode'] == 0
        else:
            clone(original_checkout, checkout)
            assert '.reconcileDelivery' in (checkout / 'Eggshell/PluginHooks.lean').read_text()
            (checkout / 'tools/DeliveryDemandAudit.lean').write_text(source)
            with (checkout / 'lakefile.lean').open('a') as stream:
                stream.write('\nlean_exe delivery_demand_audit where\n  root := `tools.DeliveryDemandAudit\n')
            execute(['lake', '--no-cache', 'build', 'delivery_demand_audit'], cell / 'build', local, checkout)
        assert sha(checkout / '.lake/build/bin/eggshell') == runtime
        # Identical path as well as identical authoritative bytes in every arm.
        reused = (cell / 'handoff.json').exists()
        retained_database = cell / 'work.egg'
        if reused and retained_database.exists():
            assert args.resume and not active.exists()
            assert graph_files(retained_database) == original
        elif active.exists():
            assert args.resume and reused
        else:
            clone(PRIOR / 'first-segment-control/work.egg', active)
        database = retained_database if retained_database.exists() else active
        assert graph_files(database) == original
        helper = checkout / '.lake/build/bin/delivery_demand_audit'
        if reused:
            assert args.resume
            assert json.loads((cell / 'inspect/record.json').read_text())['exitCode'] == 0
        else:
            clone(PRIOR / 'public-warm/provider-cache', cell / 'provider-cache')
            execute([helper, active, destination / 'demand.json', cell / 'provider-cache', cell / 'handoff.json'],
                cell / 'inspect', local, LLVM, timeout=300)
        result = json.loads((cell / 'handoff.json').read_text())
        for stage in ['handoff', 'reconciled']:
            handoff = result[stage]
            assert handoff is None or handoff['reason'] != 'search-incomplete'
            body = handoff['text'] if handoff else ''
            (cell / (stage + '-body.txt')).write_text(body)
        context = {key: result[key] for key in ['current', 'question', 'targets', 'claims',
            'observedClaims', 'stagedValues', 'stagedRootsPublished']}
        contexts.append(context)
        assert len(result['observedClaims']) == 1
        assert len(result['claims']) == len(demand['initialClaims']) + 1
        expected_roots = 3 if tool['source'] is not None else 2
        assert len(result['stagedValues']) == expected_roots and all(result['stagedRootsPublished'])
        assert graph_files(database) == original
        if database == active:
            active.rename(retained_database)
        handoff = result['reconciled']
        row = dict(implementation=name, runtimeSha256=runtime,
            bodySha256=sha(cell / 'reconciled-body.txt'), bodyBytes=(cell / 'reconciled-body.txt').stat().st_size,
            rawBodySha256=sha(cell / 'handoff-body.txt'), helperSha256=sha(helper),
            demandSourceSha256=sha(checkout / 'tools/DeliveryDemandAudit.lean'),
            elapsedMs=result['elapsedMs'], claims=len(result['claims']), targets=result['targets'],
            reusedCompletedInspection=reused,
            blocksCurrent=handoff['blocksCurrent'] if handoff else False,
            completed=handoff['completed'] if handoff else 0,
            reason=handoff['reason'] if handoff else None)
        rows.append(row)
        print(json.dumps(row), flush=True)
        save(destination / 'partial-results.json', rows)
    assert contexts[0] == contexts[1] == contexts[2]
    assert graph_files(PRIOR / 'prepared-common.egg') == original
    assert graph_files(ATTEMPT / 'output.egg') == recorded
    differences = packet_differences(destination, [row['implementation'] for row in rows])
    save(destination / 'summary.json', dict(scope='Controlled warm native-demand diagnostic on one continuation boundary',
        rows=rows, packetDifferences=differences, identicalDemandContext=True, sourceGraphFilesUnchanged=True,
        publicEqualsFirstSegment=rows[0]['bodySha256'] == rows[1]['bodySha256'],
        publicEqualsCentroid=rows[0]['bodySha256'] == rows[2]['bodySha256'],
        nativeDeadlineGate=False, historicalTransportReplay=False,
        tokenEffectEstablished=False, answeringModelCalls=0, productionAdoption=False))


if __name__ == '__main__':
    main()
