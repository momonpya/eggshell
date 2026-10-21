#!/usr/bin/env python3
"""Freeze a new six-stage comparison with no imported answering-model calls.

Only the common saved source is reused. All 54 fresh/current/candidate calls
and every native preparation belong to the new isolated study.
"""
import argparse
import hashlib
from pathlib import Path
import shutil

import readme_benchmark as bench
from memory_guard import require_guard
from readme_matched import study
from readme_preparation import prepare_native_trial
from readme_token_dispatch import CODE, OLD, admit, order, status
from readme_trial import read, sha, validate_prepared_trial
from semantic_latency import graph_files, save

TOOLS = Path(__file__).resolve().parent
EX = Path('/Users/ovm/.codex/experiments/eggshell')
CURRENT = EX / 'window-centroid-20261020/construction-3/checkout'
CONTROL = '415bcc2cd64412dad79d089da89f20533048901e5536f3d7206bdaa372b6f6f4'
PINNED = CODE + ['prepare_token_restart.py', 'prepare_token_stage.py',
                 'audit_token_stage.py', 'owned_daemon.py']


def new_slots(base):
    """Every study path is newly owned by this comparison, including controls."""
    return [dict(**item, study=str(base / item['condition']),
                 arm='fresh' if item['condition'] == 'fresh' else 'candidate',
                 label=f"stage{item['stage']}-{item['condition']}-r{item['repetition']}")
            for item in sorted(order(), key=lambda item: (item['repetition'], item['stage']))]


def qualified_source(construction, qualification):
    result = read(construction / 'result.json')
    checked = read(qualification / 'result.json')
    protocol = read(qualification / 'protocol.json')
    source = construction / 'checkout'
    if (not result['complete'] or not checked['complete'] or
            not checked['allStoredFullProbesDelivered'] or
            protocol['candidate'] != result['runtimeSha256'] or
            sha(source / '.lake/build/bin/eggshell') != result['runtimeSha256']):
        raise ValueError('Stored-source delivery and the exact candidate must qualify before freezing')
    return source, result['runtimeSha256'], protocol


def freeze(base, construction, qualification):
    require_guard(dict(memoryGuardSha256=sha(TOOLS / 'memory_guard.py')))
    if base.exists():
        raise ValueError('Keep all existing preparations and attempts; choose a new study')
    source, runtime, template = qualified_source(construction, qualification)
    if sha(CURRENT / '.lake/build/bin/eggshell') != CONTROL:
        raise ValueError('The current development control changed')
    initial = {k:read(OLD / 'checkpoints/stage1/ready.json')[k] for k in ['directory', 'files']}
    if graph_files(Path(initial['directory'])) != initial['files']:
        raise ValueError('Original common saved source changed')
    inventory = EX / 'readme-reuse-tokens-20261021/sources/stage1.json'
    if read(inventory)['sourceGraphFiles'] != initial['files']:
        raise ValueError('Source inventory belongs to another saved source')
    slots = new_slots(base)
    if len(slots) != 54 or any(status(slot) is not None for slot in slots):
        raise ValueError('A restarted comparison needs 54 unattempted calls')
    base.mkdir(parents=True, mode=0o700)
    (base / 'harness').mkdir()
    for name in PINNED:
        shutil.copy2(TOOLS / name, base / 'harness' / name)
    paths = {condition:str(base / condition) for condition in ['fresh', 'current', 'candidate']}
    save(base / 'plan.json', dict(model='gpt-5.6-luna', effort='xhigh', slots=slots, paths=paths,
        code={name:sha(TOOLS / name) for name in PINNED},
        runtimes=dict(current=CONTROL, candidate=runtime), sourceWorkspace=str(bench.LLVM),
        initialSource=initial, questionsSha256=sha(bench.ROOT / 'docs/benchmarks/llvm-three-topics.json'),
        firstLapMinimumReduction=70, retainedLapMinimumReduction=90,
        criterion='Each topic/lap has three equal new repetitions; retain individual totals, paired mean, range and ratio of sums; inspect original DB, actual delivery and answer quality',
        nextHistory='candidate repetition 0 fixed before generation',
        evaluationOrder='Complete the six-stage sequence for repetition 0, then 1 and 2; each stage retains one common predeclared r0 history for all repetitions and conditions',
        accounting='input + output; cached once; failed usage retained; unknown never zero; seed separate',
        reusedCompletedControls={}, reusedCandidateTrials=[], newAnsweringCalls=54,
        newSeedAcquisition=False, sourceInventorySha256=sha(inventory),
        sourceQualification=dict(directory=str(qualification), resultSha256=sha(qualification / 'result.json')),
        publicIncluded=False, automaticResubmission=False, qualityAccepted=False, productionAdoption=False))
    (base / 'plan.sha256').write_text(sha(base / 'plan.json') + '\n')
    (base / 'sources').mkdir()
    shutil.copy2(inventory, base / 'sources/stage1.json')
    for condition, directory in paths.items():
        cell = Path(directory); cell.mkdir(mode=0o700)
        protocol = dict(template)
        protocol.update(candidateSource=str(source if condition == 'candidate' else CURRENT),
            candidate=runtime if condition == 'candidate' else CONTROL,
            model='gpt-5.6-luna', effort='xhigh', activeDatabase=str(cell / 'active/work.egg'),
            generationAllowed=False, scheduledLabels=[], sourceSnapshots={'1':initial},
            preparedTrialDigests={}, matchedPlanSha256=sha(base / 'plan.json'),
            trials={slot['label']:{k:slot[k] for k in ['arm', 'topic', 'stage', 'repetition']}
                    for slot in slots if slot['condition'] == condition},
            scope='Entirely new fixed token/quality comparison; no old control or candidate trial reuse')
        save(cell / 'protocol.json', protocol)
        with study(cell):
            bench.prepare_fresh() if condition == 'fresh' else bench.prepare('candidate')
    prompts = read(bench.ROOT / 'docs/benchmarks/llvm-three-topics.json')['prompts']
    for slot in [s for s in slots if s['stage'] == 1]:
        cell, label = Path(slot['study']), slot['label']
        if slot['condition'] != 'fresh':
            prepare_native_trial(cell, label, base / 'sources/stage1.json')
            continue
        case = cell / 'prepared' / label; case.mkdir(parents=True)
        protocol = read(cell / 'protocol.json')
        environment_file = cell / 'environments/fresh/environment.json'
        environment = read(environment_file)
        prompt = prompts[slot['topic']].replace('<LLVM_SOURCE>', str(bench.LLVM))
        ready = dict(label=label, **protocol['trials'][label], model='gpt-5.6-luna', effort='xhigh',
            sourceWorkspace=str(bench.LLVM), promptSha256=hashlib.sha256(prompt.encode()).hexdigest(),
            **{k:protocol[k] for k in ['runnerSha256', 'transportSha256', 'trialGateSha256', 'memoryGuardSha256']},
            environmentSha256=sha(environment_file),
            configurationSha256=sha(Path(environment['CODEX_HOME']) / 'config.toml'),
            sourceSnapshot=initial, files={}, memory=None)
        save(case / 'ready.json', ready)
        protocol['preparedTrialDigests'][label] = sha(case / 'ready.json')
        save(cell / 'protocol.json', protocol)
        validate_prepared_trial(cell, protocol, 'fresh', label, slot['topic'], prompt, environment_file)
    admit(base, 1)
    save(base / 'prepared.json', dict(firstStageAdmitted=True, planSha256=sha(base / 'plan.json'),
        completedControlsReused=0, previousCandidateResultsReused=0, answeringModelCalls=0,
        productionAdoption=False, qualityAccepted=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--construction', type=Path, required=True)
    parser.add_argument('--qualification', type=Path, required=True)
    args = parser.parse_args()
    freeze(args.base, args.construction, args.qualification)
