#!/usr/bin/env python3
"""Dispatch fixed token comparisons after the stored-evidence delivery gate.

Fresh/current/candidate record token and answer variation under fixed conditions.
Relevant required original DB evidence delivery determines acceptance; quality
and token variation alone do not reject a delivery implementation. Public main
is excluded. Nothing is automatically adopted or retried.
"""
import argparse
import hashlib
from pathlib import Path
import shutil

import readme_benchmark as bench
from memory_guard import require_guard
from readme_matched import normalized, restore_input, study
from readme_trial import evidence_parts, read, sha, validate_prepared_trial
from semantic_latency import graph_files, save

TOOLS = Path(__file__).resolve().parent
OLD = Path('/Users/ovm/.codex/experiments/eggshell/readme-matched-20261021')
CODE = ['readme_token_dispatch.py', 'readme_benchmark.py', 'readme_trial.py',
        'readme_preparation.py', 'readme_matched.py', 'memory_guard.py', 'pilot_server.py']


def order():
    for stage in range(1, 7):
        for repetition, conditions in enumerate([
                ['fresh', 'candidate', 'current'], ['candidate', 'current', 'fresh'],
                ['current', 'fresh', 'candidate']]):
            for condition in conditions:
                yield dict(stage=stage, topic=(stage - 1) % 3 + 1,
                           repetition=repetition, condition=condition)


def freeze(base, candidate):
    require_guard(dict(memoryGuardSha256=sha(TOOLS / 'memory_guard.py')))
    if base.exists():
        raise ValueError('Preserve the existing token comparison')
    base.mkdir(parents=True)
    (base / 'harness').mkdir()
    for name in CODE:
        shutil.copy2(TOOLS / name, base / 'harness' / name)
    paths = dict(fresh=str(OLD / 'fresh'), current=str(OLD / 'candidate'), candidate=str(candidate))
    protocols = {k:read(Path(v) / 'protocol.json') for k, v in paths.items()}
    slots = []
    for slot in order():
        stage, repetition, condition = slot['stage'], slot['repetition'], slot['condition']
        if condition == 'candidate':
            label = 'scope-topic1' if stage == 1 and repetition == 0 else f'tokens-stage{stage}-r{repetition}'
        else:
            arm = 'fresh' if condition == 'fresh' else 'candidate'
            label = f'stage{stage}-{arm}-r{repetition}'
        slots.append(dict(**slot, study=paths[condition], label=label,
                          arm='fresh' if condition == 'fresh' else 'candidate'))
    source = read(OLD / 'checkpoints/stage1/ready.json')
    save(base / 'plan.json', dict(model='gpt-5.6-luna', effort='xhigh', slots=slots,
        code={n:sha(TOOLS / n) for n in CODE}, paths=paths,
        runtimes={k:v['candidate'] for k, v in protocols.items() if k != 'fresh'},
        sourceWorkspace=str(bench.LLVM), initialSource={k:source[k] for k in ['directory', 'files']},
        questionsSha256=sha(bench.ROOT / 'docs/benchmarks/llvm-three-topics.json'),
        tokenReductionReferences=dict(firstLap=70, retainedLap=90),
        adoptionCriterion='Required question-relevant original DB evidence delivery; token reduction and answer quality are separate observations, not rejection gates',
        criterion='Every lap/topic reported separately over three equal repetitions; no best-run selection',
        nextHistory='candidate repetition 0, fixed before any answering model',
        accounting='input + output, cached once, failed consumption retained, unknown never zero; seed separate',
        publicIncluded=False, automaticResubmission=False, qualityAccepted=False, productionAdoption=False))
    (base / 'plan.sha256').write_text(sha(base / 'plan.json') + '\n')


def checked(base):
    if sha(base / 'plan.json') != (base / 'plan.sha256').read_text().strip():
        raise ValueError('Frozen comparison plan changed')
    plan = read(base / 'plan.json')
    require_guard(dict(memoryGuardSha256=plan['code']['memory_guard.py']))
    for name, digest in plan['code'].items():
        if sha(TOOLS / name) != digest or sha(base / 'harness' / name) != digest:
            raise ValueError('Frozen comparison harness changed: ' + name)
    if sha(bench.ROOT / 'docs/benchmarks/llvm-three-topics.json') != plan['questionsSha256']:
        raise ValueError('Frozen comparison questions changed')
    return plan


def status(slot):
    attempt = Path(slot['study']) / 'attempts' / slot['label']
    if not attempt.exists():
        return None
    if not (attempt / 'result.json').exists() or (attempt / 'failure.json').exists():
        raise ValueError('Retain incomplete attempt and its costs; do not resubmit: ' + str(attempt))
    result, usage = read(attempt / 'result.json'), read(attempt / 'usage.json')
    if not result['completed'] or not usage['finalUsageKnown'] or result['usage'] != usage['total']:
        raise ValueError('Unknown or inconsistent final usage: ' + str(attempt))
    return result


def history_reference_slots(plan, stage):
    """Independent repetitions cannot change the predeclared r0 history."""
    preceding = [s for s in plan['slots'] if s['stage'] == stage - 1 and s['repetition'] == 0]
    if len(preceding) != 3 or {s['condition'] for s in preceding} != {'fresh', 'current', 'candidate'}:
        raise ValueError('Common history requires the complete fixed r0 matched triple')
    return preceding


def prior_answer(documents, text=None, work=None):
    answers = [d for d in documents if d['kind'] == 'answer' and
               (text is None or d['evidence'].strip() == text.strip()) and
               (work is None or d['work'] == work)]
    if not answers or len({d['evidence'] for d in answers}) != 1:
        raise ValueError('The predeclared prior answer is missing or ambiguous in the saved DB')
    evidence = answers[0]['evidence']
    return dict(owners=[d['owner'] for d in answers], text=evidence,
                sha256=hashlib.sha256(evidence.encode()).hexdigest())


def memory_delivery_report(inventory, body):
    """Record original history without requiring an entire previous answer.

    The captured body and source integrity are checked by native preparation.
    Relevance is judged against the current question. Whole-answer presence and
    incidental examples are diagnostics, not substitutes for that review.
"""
    prior = inventory['priorAnswer']
    if not prior['text'] or hashlib.sha256(prior['text'].encode()).hexdigest() != prior['sha256']:
        raise ValueError('Invalid saved prior-answer inventory')
    parts = evidence_parts(body)
    if not parts:
        raise ValueError('No captured DB evidence in the delivered body')
    delivered = [owner for owner in prior['owners'] if normalized(prior['text']) in normalized(
        '\n'.join(text for actual, text in parts if actual == owner))]
    required = [f for f in inventory['facts'] if f['fullExcerptOwners']]
    missing = [f['name'] for f in required if not any(
        owner in f['fullExcerptOwners'] and normalized(f['excerpt']) in normalized(text)
        for owner, text in parts)]
    return dict(priorAnswerFullOwners=delivered, storedSourceProbes=[f['name'] for f in required],
                deliveredOwners=list(dict.fromkeys(owner for owner, _ in parts)),
                priorAnswerScope='diagnostic; the complete previous answer is not required',
                missingSourceProbes=missing, relevanceReviewRequired=True,
                sourceProbeScope='diagnostic; quality is judged against the actual question, not mandatory unrequested examples')


def admit(base, stage):
    plan = checked(base)
    slots = [s for s in plan['slots'] if s['stage'] == stage]
    if stage > 1:
        earlier = history_reference_slots(plan, stage)
        if not all([status(s) is not None for s in earlier]):
            raise ValueError('Finish the fixed preceding r0 matched triple before advancing history')
    if any(status(s) is not None for s in slots):
        raise ValueError('Stage generation already started; keep its admission')
    source = None
    digests = {}
    delivery_reports = {}
    prompts = read(bench.ROOT / 'docs/benchmarks/llvm-three-topics.json')['prompts']
    for slot in slots:
        cell, label = Path(slot['study']), slot['label']
        protocol = read(cell / 'protocol.json')
        if protocol['model'] != plan['model'] or protocol['effort'] != plan['effort']:
            raise ValueError('Comparison model or effort differs')
        if slot['condition'] != 'fresh' and protocol['candidate'] != plan['runtimes'][slot['condition']]:
            raise ValueError('Comparison runtime differs')
        if slot['condition'] != 'fresh':
            restore_input(cell, label, preparation_only=True)
        prompt = prompts[slot['topic']].replace('<LLVM_SOURCE>', str(bench.LLVM))
        prepared = validate_prepared_trial(cell, protocol, slot['arm'], label, slot['topic'], prompt,
            cell / 'environments' / slot['arm'] / 'environment.json')
        snapshot = prepared['manifest']['sourceSnapshot']
        if source is not None and snapshot != source:
            raise ValueError('Matched conditions use different saved snapshots')
        source = snapshot
        digests[label] = sha(cell / 'prepared' / label / 'ready.json')
        if slot['condition'] == 'candidate':
            inventory = read(base / 'sources' / f'stage{stage}.json')
            if inventory['sourceGraphFiles'] != snapshot['files']:
                raise ValueError('Stored evidence gate belongs to another snapshot')
            ready = prepared['manifest']
            body = (cell / 'prepared' / label / ready['memory']['body']).read_text()
            delivery_reports[label] = memory_delivery_report(inventory, body)
    if stage == 1 and source != plan['initialSource']:
        raise ValueError('Initial seed changed')
    if stage > 1:
        parent = next(s for s in plan['slots'] if s['stage'] == stage - 1 and
                      s['condition'] == 'candidate' and s['repetition'] == 0)
        output = Path(parent['study']) / 'attempts' / parent['label'] / 'output.egg'
        if graph_files(output) != source['files']:
            raise ValueError('Common history is not the predeclared candidate r0 output')
    target = base / 'stages' / f'stage{stage}.json'
    if target.exists():
        raise ValueError('Keep the existing stage admission')
    save(target, dict(source=source, preparations=digests, model=plan['model'], effort=plan['effort'],
                      sourceFactsSha256=sha(base / 'sources' / f'stage{stage}.json'),
                      deliveryReports=delivery_reports))


def dispatch(base):
    if (base / 'retired.json').exists():
        raise ValueError('This comparison is retired; preserve its calls and start a new fixed study')
    plan = checked(base)
    states = [status(s) for s in plan['slots']]
    index = next((i for i, state in enumerate(states) if state is None), None)
    if index is None:
        raise ValueError('All fixed calls completed; review required original evidence delivery and report quality/tokens separately')
    slot = plan['slots'][index]
    admission = read(base / 'stages' / f"stage{slot['stage']}.json")
    cell, label = Path(slot['study']), slot['label']
    if sha(cell / 'prepared' / label / 'ready.json') != admission['preparations'][label]:
        raise ValueError('Prepared input changed after stage admission')
    if slot['condition'] != 'fresh':
        restore_input(cell, label)
    protocol = read(cell / 'protocol.json')
    if protocol['generationAllowed'] or protocol['scheduledLabels']:
        raise ValueError('Another dispatch remains open')
    protocol['scheduledLabels'] = [label]
    save(cell / 'protocol.json', protocol)
    try:
        with study(cell):
            bench.model_turn(slot['arm'], label, slot['topic'])
    finally:
        protocol['scheduledLabels'] = []
        save(cell / 'protocol.json', protocol)
    save(base / f'completed-{index:02}.json', dict(slot=slot, result=status(slot),
        planSha256=sha(base / 'plan.json'), qualityAccepted=False, productionAdoption=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['freeze', 'admit', 'next'])
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--stage', type=int, choices=range(1, 7), default=1)
    args = parser.parse_args()
    if args.action == 'freeze': freeze(args.base, args.candidate)
    elif args.action == 'admit': admit(args.base, args.stage)
    else: dispatch(args.base)
