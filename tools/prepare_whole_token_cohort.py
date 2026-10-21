#!/usr/bin/env python3
"""Freeze the complete-observation study, reusing six matched completed controls.

The original comparison remains intact. Reuse is explicit before any new
answering-model call; no previous candidate result becomes a new runtime result.
"""
import argparse
import hashlib
from pathlib import Path
import shutil

import readme_benchmark as bench
from memory_guard import require_guard
from readme_matched import normalized, restore_input, study
from readme_preparation import prepare_native_trial
from readme_token_dispatch import CODE, OLD, checked, order, status
from readme_trial import evidence_parts, read, sha, validate_prepared_trial
from semantic_latency import graph_files, save

TOOLS = Path(__file__).resolve().parent
EX = Path('/Users/ovm/.codex/experiments/eggshell')
QUALIFIED = EX / 'scope-context-20261021/native-9'
SOURCE = EX / 'scope-context-20261021/construction-8/checkout'
CURRENT = EX / 'window-centroid-20261020/construction-3/checkout'
RUNTIME = '57db4ef538ed35bd463908421f590b9835a0a64c92942abaa0b22efd7833819d'
CONTROL = '415bcc2cd64412dad79d089da89f20533048901e5536f3d7206bdaa372b6f6f4'
PINNED = CODE + ['prepare_whole_token_cohort.py', 'prepare_token_stage.py', 'audit_token_stage.py']


def completed_manifest(cell, slot, plan, prompt):
    """A completed trial legitimately consumes private state; audit its actual run."""
    attempt = cell / 'attempts' / slot['label']
    manifest = read(attempt / 'prepared-trial.json')
    invocation = read(attempt / 'invocation.json')
    usage = read(attempt / 'usage.json')
    if (invocation['model'] != plan['model'] or invocation['effort'] != plan['effort'] or
            invocation['promptSha256'] != hashlib.sha256(prompt.encode()).hexdigest() or
            invocation['transportSha256'] != plan['code']['pilot_server.py'] or
            sha(attempt / 'runner.py') != plan['code']['readme_benchmark.py'] or
            sha(attempt / 'trial-gate.py') != plan['code']['readme_trial.py'] or
            any(usage[k] for k in ['errors', 'reroutes', 'hookFailures'])):
        raise ValueError('Archived actual model condition differs')
    packets = read(attempt / 'delivered-packets.json')
    if any(sha(attempt / p['file']) != p['sha256'] for p in packets):
        raise ValueError('Archived actual delivery changed')
    if slot['condition'] == 'fresh':
        if packets or invocation['runtimeSha256'] is not None:
            raise ValueError('Archived fresh run had memory')
    else:
        initial = [p for p in packets if p['event'] == 'userPromptSubmit']
        if (invocation['runtimeSha256'] != plan['runtimes']['current'] or len(initial) != 1 or
                initial[0]['sha256'] != read(attempt / 'admission.json')['expectedBodySha256'] or
                read(attempt / 'input-snapshot.json')['files'] != manifest['memory']['graphFiles'] or
                graph_files(attempt / 'output.egg') != status(slot)['outputGraphFiles'] or
                read(attempt / 'keep.json')['exitCode'] != 0 or
                any(read(attempt / 'shutdown.json')[key] != 0 for key in ['exit_code', 'daemon_exit_code'])):
            raise ValueError('Archived actual memory input, delivery or saved output differs')
    return manifest


def first_admission(base):
    """Validate all nine inputs, allowing only the predeclared completed controls."""
    plan = checked(base)
    slots = [slot for slot in plan['slots'] if slot['stage'] == 1]
    digests = {}
    prompts = read(bench.ROOT / 'docs/benchmarks/llvm-three-topics.json')['prompts']
    inventory = read(base / 'sources/stage1.json')
    for slot in slots:
        cell, label = Path(slot['study']), slot['label']
        result = status(slot)
        reused = plan['reusedCompletedControls'].get(label)
        if reused is not None:
            if result is None or slot['condition'] == 'candidate':
                raise ValueError('A declared reused control is missing or substitutes a candidate')
            for relative, digest in reused['files'].items():
                if sha(cell / relative) != digest:
                    raise ValueError('A reused completed control changed: ' + label)
        elif result is not None:
            raise ValueError('A new candidate was attempted before admission')
        protocol = read(cell / 'protocol.json')
        if protocol['model'] != plan['model'] or protocol['effort'] != plan['effort']:
            raise ValueError('Matched model or effort differs')
        if reused is None and slot['condition'] != 'fresh':
            if protocol['candidate'] != plan['runtimes'][slot['condition']]:
                raise ValueError('Matched runtime differs')
            restore_input(cell, label, preparation_only=True)
        prompt = prompts[slot['topic']].replace('<LLVM_SOURCE>', str(bench.LLVM))
        if reused is not None:
            manifest = completed_manifest(cell, slot, plan, prompt)
        else:
            prepared = validate_prepared_trial(cell, protocol, slot['arm'], label, slot['topic'], prompt,
                cell / 'environments' / slot['arm'] / 'environment.json')
            manifest = prepared['manifest']
        if manifest['sourceSnapshot'] != plan['initialSource']:
            raise ValueError('Initial saved source differs')
        if slot['condition'] == 'candidate':
            body = (cell / 'prepared' / label / manifest['memory']['body']).read_text()
            parts = evidence_parts(body)
            missing = [f['name'] for f in inventory['facts'] if f['fullExcerptOwners'] and
                not any(owner in f['fullExcerptOwners'] and normalized(f['excerpt']) in normalized(text)
                        for owner, text in parts)]
            if missing:
                raise ValueError('Stored full source is missing: ' + ', '.join(missing))
        digests[label] = sha(cell / 'prepared' / label / 'ready.json')
    if (base / 'stages/stage1.json').exists():
        raise ValueError('Preserve the existing admission')
    save(base / 'stages/stage1.json', dict(source=plan['initialSource'], preparations=digests,
        model=plan['model'], effort=plan['effort'], sourceFactsSha256=sha(base / 'sources/stage1.json'),
        reusedControls=list(plan['reusedCompletedControls'])))


def freeze(base):
    require_guard(dict(memoryGuardSha256=sha(TOOLS / 'memory_guard.py')))
    if base.exists():
        raise ValueError('Preserve the existing cohort and any preparation')
    qualification = read(QUALIFIED / 'result.json')
    if (not qualification['allStoredFullProbesDelivered'] or
            read(QUALIFIED / 'protocol.json')['candidate'] != RUNTIME or
            sha(SOURCE / '.lake/build/bin/eggshell') != RUNTIME or
            sha(CURRENT / '.lake/build/bin/eggshell') != CONTROL):
        raise ValueError('Frozen source delivery or runtime changed')
    initial = {k:read(OLD / 'checkpoints/stage1/ready.json')[k] for k in ['directory', 'files']}
    if graph_files(Path(initial['directory'])) != initial['files']:
        raise ValueError('Original saved source changed')
    paths = {condition:str(base / condition) for condition in ['fresh', 'current', 'candidate']}
    slots, reused = [], {}
    for item in order():
        condition, stage, repetition = item['condition'], item['stage'], item['repetition']
        arm = 'fresh' if condition == 'fresh' else 'candidate'
        label = ('scope-topic1' if stage == 1 and repetition == 0 else f'tokens-stage{stage}-r{repetition}') \
            if condition == 'candidate' else f'stage{stage}-{arm}-r{repetition}'
        cell = Path(paths[condition])
        if stage == 1 and condition != 'candidate':
            cell = OLD / arm
            slot = dict(**item, arm=arm, study=str(cell), label=label)
            result = status(slot)
            if result is None:
                raise ValueError('All six archived matched controls must be complete before freezing reuse')
            files = [f'attempts/{label}/{name}' for name in [
                'result.json', 'usage.json', 'invocation.json', 'prepared-trial.json', 'prompt.txt', 'answer.txt']]
            files.append(f'prepared/{label}/ready.json')
            reused[label] = dict(study=str(cell), files={name:sha(cell / name) for name in files},
                totalTokens=result['usage']['totalTokens'])
        slots.append(dict(**item, arm=arm, study=str(cell), label=label))
    base.mkdir(parents=True, mode=0o700)
    (base / 'harness').mkdir()
    for name in PINNED:
        shutil.copy2(TOOLS / name, base / 'harness' / name)
    save(base / 'plan.json', dict(model='gpt-5.6-luna', effort='xhigh', slots=slots, paths=paths,
        code={name:sha(TOOLS / name) for name in PINNED}, runtimes=dict(current=CONTROL, candidate=RUNTIME),
        sourceWorkspace=str(bench.LLVM), initialSource=initial,
        questionsSha256=sha(bench.ROOT / 'docs/benchmarks/llvm-three-topics.json'),
        firstLapMinimumReduction=70, retainedLapMinimumReduction=90,
        criterion='Each lap/topic has three equal repetitions; report individual totals, mean, range and ratio of sums; verified delivery/quality variation is model dispersion, not a reason to change delivery',
        nextHistory='candidate repetition 0 fixed before generation, never chosen by performance',
        accounting='input + output; cached once; failed consumption retained; unknown never zero; seed separate',
        reusedCompletedControls=reused, reusedCandidateTrials=[], newAnsweringCalls=48,
        reuseLimit='Only the six complete stage-1 fresh/current controls with the same saved source, prompt, model, effort and harness; chronological reuse is reported and not a new independent control sample',
        priorComparison=dict(directory=str(EX / 'readme-reuse-tokens-20261021'),
            auditSha256=sha(EX / 'readme-reuse-tokens-20261021/audits/stage1-complete.json'),
            candidateResultsImported=False),
        publicIncluded=False, automaticResubmission=False, qualityAccepted=False, productionAdoption=False))
    (base / 'plan.sha256').write_text(sha(base / 'plan.json') + '\n')
    (base / 'sources').mkdir()
    shutil.copy2(EX / 'readme-reuse-tokens-20261021/sources/stage1.json', base / 'sources/stage1.json')
    for condition, directory in paths.items():
        cell = Path(directory)
        cell.mkdir()
        protocol = read(QUALIFIED / 'protocol.json')
        protocol.update(candidateSource=str(SOURCE if condition == 'candidate' else CURRENT),
            candidate=RUNTIME if condition == 'candidate' else CONTROL,
            activeDatabase=str(cell / 'active/work.egg'), generationAllowed=False, scheduledLabels=[],
            sourceSnapshots={'1':initial}, preparedTrialDigests={}, matchedPlanSha256=sha(base / 'plan.json'),
            trials={s['label']:{k:s[k] for k in ['arm', 'topic', 'stage', 'repetition']}
                    for s in slots if s['study'] == directory},
            scope='Complete-observation matched token/quality evaluation; no automatic adoption')
        save(cell / 'protocol.json', protocol)
        with study(cell):
            bench.prepare_fresh() if condition == 'fresh' else bench.prepare('candidate')
    candidate = Path(paths['candidate'])
    for slot in [s for s in slots if s['stage'] == 1 and s['condition'] == 'candidate']:
        prepare_native_trial(candidate, slot['label'], base / 'sources/stage1.json')
    first_admission(base)
    save(base / 'prepared.json', dict(firstStageAdmitted=True, planSha256=sha(base / 'plan.json'),
        completedControlsReused=6, previousCandidateResultsReused=0, answeringModelCalls=0,
        productionAdoption=False, qualityAccepted=False))


def repair_preparation(base, previous):
    """Retain the failed setup plan and all successful native preparations."""
    require_guard(dict(memoryGuardSha256=sha(TOOLS / 'memory_guard.py')))
    if base.exists() or (previous / 'stages/stage1.json').exists():
        raise ValueError('Repair only an unadmitted setup into a new plan directory')
    plan = read(previous / 'plan.json')
    if sha(previous / 'plan.json') != (previous / 'plan.sha256').read_text().strip():
        raise ValueError('Previous setup plan changed')
    if any(status(s) is not None for s in plan['slots'] if s['condition'] == 'candidate'):
        raise ValueError('Cannot refreeze an attempted candidate')
    base.mkdir(parents=True, mode=0o700)
    (base / 'harness').mkdir()
    for name in PINNED:
        shutil.copy2(TOOLS / name, base / 'harness' / name)
    plan['code'] = {name:sha(TOOLS / name) for name in PINNED}
    plan['preparationRepair'] = dict(previous=str(previous), previousPlanSha256=sha(previous / 'plan.json'),
        reason='Completed reused controls must be checked against actual immutable run records, not their intentionally consumed preflight private state',
        slotOrderRuntimeSourceAndQuestionsUnchanged=True, nativePreparationsRepeated=False,
        newAnsweringCallsBeforeRepair=0)
    save(base / 'plan.json', plan)
    (base / 'plan.sha256').write_text(sha(base / 'plan.json') + '\n')
    (base / 'sources').mkdir()
    shutil.copy2(previous / 'sources/stage1.json', base / 'sources/stage1.json')
    for condition, directory in plan['paths'].items():
        path = Path(directory) / 'protocol.json'
        shutil.copy2(path, base / f'previous-{condition}-protocol.json')
        protocol = read(path)
        protocol['matchedPlanSha256'] = sha(base / 'plan.json')
        save(path, protocol)
    first_admission(base)
    save(base / 'prepared.json', dict(firstStageAdmitted=True, planSha256=sha(base / 'plan.json'),
        completedControlsReused=6, previousCandidateResultsReused=0, answeringModelCalls=0,
        productionAdoption=False, qualityAccepted=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True, type=Path)
    parser.add_argument('--repair-from', type=Path)
    args = parser.parse_args()
    repair_preparation(args.base, args.repair_from) if args.repair_from else freeze(args.base)
