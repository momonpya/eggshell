#!/usr/bin/env python3
"""Prepare the next common history from the predeclared candidate r0 output.

This never generates an answer or republishes the authoritative graph. Native
delivery qualification and the frozen dispatcher's stored-evidence gate still
decide whether the next stage can start.
"""
import argparse
import hashlib
import json
from pathlib import Path

import readme_benchmark as bench
from readme_matched import DOMAIN, INPUTS, normalized, reconstruct, restore_input
from readme_preparation import clone, prepare_native_trial
from readme_token_dispatch import admit, checked, status
from readme_trial import read, sha, validate_prepared_trial
from semantic_latency import execute, graph_files, save


def history_reference_slots(plan, stage):
    """Independent later repetitions cannot change the predeclared r0 history."""
    preceding = [s for s in plan['slots'] if s['stage'] == stage - 1 and s['repetition'] == 0]
    if len(preceding) != 3 or {s['condition'] for s in preceding} != {'fresh', 'current', 'candidate'}:
        raise ValueError('Common history requires the complete fixed r0 matched triple')
    return preceding


def checkpoint(base, plan, stage):
    preceding = history_reference_slots(plan, stage)
    if not all(status(s) is not None for s in preceding):
        raise ValueError('Finish the fixed preceding r0 matched triple before advancing history')
    parent = next(s for s in preceding if s['condition'] == 'candidate' and s['repetition'] == 0)
    attempt = Path(parent['study']) / 'attempts' / parent['label']
    source = attempt / 'output.egg'
    original = status(parent)['outputGraphFiles']
    if graph_files(source) != original:
        raise ValueError('Predeclared common-history output changed')
    if read(attempt / 'keep.json')['exitCode'] != 0 or any(
            read(attempt / 'shutdown.json')[k] != 0 for k in ['exit_code', 'daemon_exit_code']):
        raise ValueError('Common-history save or owned shutdown did not finish')
    directory = base / 'checkpoints' / f'stage{stage}'
    if (directory / 'ready.json').exists():
        ready = read(directory / 'ready.json')
        if (ready['files'] != original or graph_files(Path(ready['directory'])) != original or
                ready['evidenceSha256'] != sha(base / 'sources' / f'stage{stage}.json')):
            raise ValueError('Prepared common history changed')
        return ready
    directory.mkdir(parents=True, exist_ok=False)
    database = directory / 'work.egg'
    clone(source, database)
    cell = Path(parent['study'])
    environment = read(cell / 'environments/candidate/environment.json')
    binary = Path(environment['EGGSHELL_PREFIX']) / 'libexec/eggshell'
    if sha(binary) != plan['runtimes']['candidate']:
        raise ValueError('Candidate runtime differs from the frozen plan')
    config = directory / 'warm.toml'
    config.write_text('default = "work"\n[eggs]\nwork = ' + json.dumps(str(database)) +
        '\n[profiles.work]\nread = ["work"]\nwrite = "work"\nhandoff_chars = 120000\n')
    warm = []
    for name in ['warm', 'repeat']:
        local = dict(environment, EGGSHELL_CONFIG=str(config),
                     EGGSHELL_DATA_ROOT=str(directory / (name + '-data')))
        raw, _ = execute([binary, 'egg', 'warm', 'work'], directory / name,
                         local, bench.LLVM, timeout=300)
        row = json.loads(raw)['databases'][0]
        if row['after']['missing'] or row['after']['invalid']:
            raise ValueError('Common source warm is incomplete')
        if name == 'repeat' and (any(row[k] for k in ['requested', 'batches']) or
                                any(row['lexical'][k] for k in ['added', 'hydrated'])):
            raise ValueError('Independent private state repeated source indexing')
        warm.append(row)
    if graph_files(database) != original or graph_files(source) != original:
        raise ValueError('Off-hook indexing changed the authoritative common history')
    raw, _ = execute([INPUTS, 'inputs', database], directory / 'inputs', environment, bench.LLVM)
    inputs = [json.loads(line) for line in raw.decode().splitlines()]
    raw, _ = execute([DOMAIN, database], directory / 'domain', environment, bench.LLVM)
    domain = [json.loads(line) for line in raw.decode().splitlines()]
    prompts = [p.replace('<LLVM_SOURCE>', str(bench.LLVM)) for p in
               read(bench.ROOT / 'docs/benchmarks/llvm-three-topics.json')['prompts']]
    documents = reconstruct(inputs, domain, prompts)
    save(directory / 'documents.json', documents)
    if any(row['after']['valid'] != len(inputs) for row in warm):
        raise ValueError('Warm input coverage differs from the original source export')
    topic = (stage - 1) % 3 + 1
    facts = []
    for feature in read(bench.ROOT / 'docs/benchmarks/readme-memory-facts.json')['facts']:
        if topic not in feature['topics']:
            continue
        path = bench.LLVM / feature['path']
        excerpt = '\n'.join(path.read_text().splitlines()[feature['first'] - 1:feature['last']])
        if not all(anchor in excerpt for anchor in feature['anchors']):
            raise ValueError('Fixed source anchors changed: ' + feature['name'])
        facts.append(dict(**feature, sourceSha256=sha(path), excerpt=excerpt,
            storedOwners=[d['owner'] for d in documents if all(a in d['evidence'] for a in feature['anchors'])],
            fullExcerptOwners=[d['owner'] for d in documents if normalized(excerpt) in normalized(d['evidence'])]))
    evidence = base / 'sources' / f'stage{stage}.json'
    if evidence.exists():
        raise ValueError('Preserve the existing source inventory')
    save(evidence, dict(sourceGraphFiles=original, documents=len(documents),
        uniqueInputs=len(inputs), facts=facts,
        qualifications=['Original outcome evidence only; source presence is not a quality verdict.']))
    ready = dict(directory=str(database), files=original, source=str(source),
        sourceFiles=original, documents=len(documents), uniqueInputs=len(inputs), warm=warm,
        evidenceSha256=sha(evidence), newSeedAcquisition=False)
    save(directory / 'ready.json', ready)
    return ready


def prepare(base, stage):
    plan = checked(base)
    slots = [s for s in plan['slots'] if s['stage'] == stage]
    if any(status(s) is not None for s in slots):
        raise ValueError('Preserve preparation after generation starts')
    for path in plan['paths'].values():
        protocol = read(Path(path) / 'protocol.json')
        if protocol['generationAllowed'] or protocol['scheduledLabels']:
            raise ValueError('Close all generation before preparing another stage')
    common = checkpoint(base, plan, stage)
    snapshot = {k:common[k] for k in ['directory', 'files']}
    prompts = read(bench.ROOT / 'docs/benchmarks/llvm-three-topics.json')['prompts']
    for condition in ['fresh', 'current', 'candidate']:
        cell = Path(plan['paths'][condition])
        protocol = read(cell / 'protocol.json')
        if str(stage) in protocol['sourceSnapshots'] and protocol['sourceSnapshots'][str(stage)] != snapshot:
            raise ValueError('Existing prepared source snapshot differs')
        protocol['sourceSnapshots'][str(stage)] = snapshot
        for slot in [s for s in slots if s['condition'] == condition]:
            trial = {k:slot[k] for k in ['arm', 'topic', 'stage', 'repetition']}
            if slot['label'] in protocol['trials'] and protocol['trials'][slot['label']] != trial:
                raise ValueError('Existing planned trial differs')
            protocol['trials'][slot['label']] = trial
        save(cell / 'protocol.json', protocol)
        for slot in [s for s in slots if s['condition'] == condition]:
            label, arm = slot['label'], slot['arm']
            case = cell / 'prepared' / label
            environment_file = cell / 'environments' / arm / 'environment.json'
            prompt = prompts[slot['topic']].replace('<LLVM_SOURCE>', str(bench.LLVM))
            if case.exists():
                if not (case / 'ready.json').exists() or (arm != 'fresh' and not (case / 'qualification.json').exists()):
                    raise ValueError('Inspect interrupted preparation without repeating hooks: ' + label)
                if arm != 'fresh':
                    restore_input(cell, label, preparation_only=True)
                validate_prepared_trial(cell, read(cell / 'protocol.json'), arm, label,
                                        slot['topic'], prompt, environment_file)
                continue
            if arm != 'fresh':
                prepare_native_trial(cell, label, base / 'sources' / f'stage{stage}.json')
            else:
                case.mkdir(parents=True)
                protocol = read(cell / 'protocol.json')
                environment = read(environment_file)
                ready = dict(label=label, **protocol['trials'][label], model=plan['model'], effort=plan['effort'],
                    sourceWorkspace=str(bench.LLVM), promptSha256=hashlib.sha256(prompt.encode()).hexdigest(),
                    **{k:protocol[k] for k in ['runnerSha256', 'transportSha256', 'trialGateSha256', 'memoryGuardSha256']},
                    environmentSha256=sha(environment_file),
                    configurationSha256=sha(Path(environment['CODEX_HOME']) / 'config.toml'),
                    sourceSnapshot=snapshot, files={}, memory=None)
                save(case / 'ready.json', ready)
                protocol['preparedTrialDigests'][label] = sha(case / 'ready.json')
                save(cell / 'protocol.json', protocol)
                validate_prepared_trial(cell, protocol, arm, label, slot['topic'], prompt, environment_file)
    admit(base, stage)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--stage', type=int, choices=range(2, 7), required=True)
    args = parser.parse_args()
    prepare(args.base, args.stage)
