#!/usr/bin/env python3
"""Coordinate the matched README study; never replace or retry an attempted slot.

All heavy actions run serially under memory_guard.py. The immutable plan fixes
54 calls before generation: six stages, three repetitions, three conditions.
Each stage uses one saved graph for both memory conditions. Candidate r0, fixed
in advance, supplies the next common history. Quality review remains separate.
"""
import argparse
from collections import defaultdict
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import select
import shutil
import subprocess

import readme_benchmark as bench
from memory_guard import require_guard
from readme_preparation import clone, prepare_native_trial
from readme_trial import evidence_parts, read, sha, tree_files, validate_prepared_trial
from semantic_latency import environment, execute, graph_files, save

EXPERIMENTS = Path('/Users/ovm/.codex/experiments/eggshell')
PUBLIC = EXPERIMENTS / 'readme-delivery-sequence-20261021/replay-3/public-warm/checkout'
CANDIDATE = EXPERIMENTS / 'window-centroid-20261020/construction-3/checkout'
SOURCE = bench.LLVM
ROOT = bench.ROOT
TOOLS = Path(__file__).resolve().parent
RUNTIMES = {
    'public': '959809379df896e464da5419398187b714d26fc90d87004f434a36be681bd2f3',
    'candidate': '415bcc2cd64412dad79d089da89f20533048901e5536f3d7206bdaa372b6f6f4'}
PUBLIC_COMMIT = '51873167c11c447a0af67e73430b5ab6635b2a65'
LLVM_COMMIT = '6dfe1677ab8dffbc6ec13d53a1e0215d75147689'
SEED = EXPERIMENTS / 'readme-window-centroid-20261020/checkpoints/seed/work.egg'
SEED_RECEIPT = EXPERIMENTS / 'readme-luna-20261020/checkpoints/seed/seed.json'
PUBLIC_CACHE = EXPERIMENTS / 'readme-delivery-parity-20261020/inspection-2/variants/public-warm/seed/provider-cache'
ASSET_PREFIX = EXPERIMENTS / 'readme-window-centroid-20261020/environments/candidate/prefix'
AUDITOR = EXPERIMENTS / 'first-segment-control-20261020/construction-1/checkout/.lake/build/bin/publication_audit'
PRODUCER = PUBLIC / '.lake/build/bin/rebuild_lexical_snapshot'
INPUTS = PUBLIC / '.lake/build/bin/delivery_audit'
DOMAIN = CANDIDATE / '.lake/build/bin/window_domain_audit'
CODE = ['readme_matched.py', 'readme_benchmark.py', 'readme_preparation.py',
        'readme_trial.py', 'memory_guard.py', 'pilot_server.py', 'owned_daemon.py',
        'pilot_hook_probe.py', 'pilot_preflight.py', 'semantic_latency.py', 'context_native_probe.py']


def slots(stage):
    topic = (stage - 1) % 3 + 1
    for repetition, order in enumerate([
            ['fresh', 'public', 'candidate'], ['public', 'candidate', 'fresh'],
            ['candidate', 'fresh', 'public']]):
        for condition in order:
            yield dict(label=f'stage{stage}-{condition}-r{repetition}', condition=condition,
                       arm='fresh' if condition == 'fresh' else 'candidate', topic=topic,
                       stage=stage, repetition=repetition)


def normalized(text):
    lines = []
    for line in text.splitlines():
        if re.fullmatch(r'(?:ORIGINAL )?CHARS \[\d+,\d+\)(?: decoded)?|DECODED JSON STRING DATA', line.strip()):
            continue
        line = re.sub(r'^\s*\d+\s*\t', '', line).strip()
        if line:
            lines.append(line)
    return '\n'.join(lines)


def reconstruct(inputs, domain, prompts):
    windows = {row['id']: row['text'] for row in inputs}
    if len(windows) != len(inputs) or any(hashlib.sha256(v.encode()).hexdigest() != k for k, v in windows.items()):
        raise ValueError('Invalid or duplicate content-addressed source input')
    groups = defaultdict(list)
    for row in domain:
        groups[row['relation']].append(row)
    documents, used = [], set()
    for owner, rows in groups.items():
        text = ''
        ordered = sorted(rows, key=lambda r: r['position'])
        if [r['position'] for r in ordered] != list(range(len(ordered))):
            raise ValueError('Incomplete document window positions')
        for row in ordered:
            window = windows[row['discovery']]
            start = row['position'] * 384
            if start > len(text) or text[start:] != window[:len(text) - start]:
                raise ValueError('Source windows disagree on overlap')
            text += window[len(text) - start:]
            used.update([row['discovery'], row['focus']])
        parsed = None
        for match in re.finditer('\n', text):
            try:
                evidence = json.loads(text[match.end():])
            except json.JSONDecodeError:
                continue
            if isinstance(evidence, str):
                parsed = dict(owner=owner, work=text[:match.start()], evidence=evidence, kind='observation')
                break
        if parsed is None:
            matches = [p for p in prompts if text.startswith(p + '\n')]
            if len(matches) != 1:
                raise ValueError('Unknown original source document shape: ' + owner)
            parsed = dict(owner=owner, work=matches[0], evidence=text[len(matches[0]) + 1:], kind='answer')
        documents.append(parsed)
    if used != set(windows):
        raise ValueError('Domain and original input keys differ')
    return documents


@contextmanager
def study(base):
    previous = bench.BASE
    bench.BASE = base
    try:
        yield
    finally:
        bench.BASE = previous


def freeze(base):
    require_guard(dict(memoryGuardSha256=sha(TOOLS / 'memory_guard.py')))
    if base.exists():
        raise ValueError('Keep the existing study; do not replace its plan')
    current = subprocess.check_output(['git', 'ls-remote', 'https://github.com/momonpya/eggshell.git',
                                       'refs/heads/main'], text=True).split()[0]
    if current != PUBLIC_COMMIT:
        raise ValueError('Public main changed; qualify that source before freezing a new study')
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=SOURCE, text=True).strip() != LLVM_COMMIT:
        raise ValueError('LLVM snapshot changed')
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=SOURCE, text=True).strip():
        raise ValueError('LLVM source is dirty')
    for condition, source in [('public', PUBLIC), ('candidate', CANDIDATE)]:
        if sha(source / '.lake/build/bin/eggshell') != RUNTIMES[condition]:
            raise ValueError('Frozen runtime changed: ' + condition)
    base.mkdir(parents=True, mode=0o700)
    code = base / 'harness'; code.mkdir()
    for filename in CODE:
        shutil.copy2(TOOLS / filename, code / filename)
    shutil.copy2(ROOT / 'docs/benchmarks/llvm-three-topics.json', base / 'questions.json')
    shutil.copy2(ROOT / 'docs/benchmarks/readme-memory-facts.json', base / 'facts.json')
    shutil.copy2(SEED_RECEIPT, base / 'seed-acquisition.json')
    plan = dict(model='gpt-5.6-luna', effort='xhigh', sourceWorkspace=str(SOURCE), sourceCommit=LLVM_COMMIT,
        publicCommit=PUBLIC_COMMIT, runtimes=RUNTIMES, repetitions=3, stages=6, answeringCalls=54,
        freshCalls=18, memoryCalls=36, order=[s for stage in range(1, 7) for s in slots(stage)],
        nextHistory='candidate repetition 0, never selected by token count or quality',
        seed=dict(directory=str(SEED), files=graph_files(SEED), receiptSha256=sha(SEED_RECEIPT),
                  acquisitionRepeated=False),
        code={n:sha(TOOLS / n) for n in CODE}, questionsSha256=sha(base / 'questions.json'),
        factsSha256=sha(base / 'facts.json'), codexExecutable=str(Path(shutil.which('codex')).resolve()),
        helpers={str(p):sha(p) for p in [AUDITOR, PRODUCER, INPUTS, DOMAIN]},
        nativePreparationSessions=2, initialPrivateQueryState='empty in every repetition',
        warmCondition='all exact original source inputs indexed off hook; repeat warm does no work',
        accounting='input + output, cached once, reasoning in output; failures retained, unknown never zero',
        automaticResubmission=False, qualityAccepted=False, productionAdoption=False,
        limitations=['Literal source support and native admission are not proof of answer correctness.',
                    'Static LLVM test expectations are not passing executable tests.',
                    'Missing exact source excerpt does not imply all equivalent knowledge is absent.'])
    plan['codexExecutableSha256'] = sha(plan['codexExecutable'])
    save(base / 'plan.json', plan)
    (base / 'plan.sha256').write_text(sha(base / 'plan.json') + '\n')
    for condition in ['fresh', 'public', 'candidate']:
        cell = base / condition; cell.mkdir()
        protocol = dict(model=plan['model'], effort=plan['effort'], sourceWorkspace=str(SOURCE),
            sourceCommit=LLVM_COMMIT, codexExecutableSha256=plan['codexExecutableSha256'],
            generationAllowed=False, scheduledLabels=[], sourceSnapshots={}, preparedTrialDigests={},
            trials={s['label']:{k:s[k] for k in ['arm', 'topic', 'stage', 'repetition']}
                    for s in plan['order'] if s['condition'] == condition},
            runnerSha256=plan['code']['readme_benchmark.py'], transportSha256=plan['code']['pilot_server.py'],
            trialGateSha256=plan['code']['readme_trial.py'], memoryGuardSha256=plan['code']['memory_guard.py'],
            publicationAuditor=str(AUDITOR), publicationAuditorSha256=sha(AUDITOR),
            candidateSource=str(PUBLIC if condition == 'public' else CANDIDATE),
            candidate=RUNTIMES['public' if condition == 'public' else 'candidate'],
            structuredReceiptsAvailable=condition == 'candidate', nativePreparationSessions=2,
            activeDatabase=str(cell / 'active/work.egg'), productionAdoption=False,
            matchedPlanSha256=sha(base / 'plan.json'))
        save(cell / 'protocol.json', protocol)


def checked_plan(base):
    if sha(base / 'plan.json') != (base / 'plan.sha256').read_text().strip():
        raise ValueError('Immutable study plan changed')
    plan = read(base / 'plan.json')
    require_guard(dict(memoryGuardSha256=plan['code']['memory_guard.py']))
    for filename, digest in plan['code'].items():
        if sha(TOOLS / filename) != digest or sha(base / 'harness' / filename) != digest:
            raise ValueError('Frozen harness changed: ' + filename)
    for path, digest in plan['helpers'].items():
        if sha(path) != digest:
            raise ValueError('Frozen diagnostic helper changed')
    for filename, key in [('questions.json', 'questionsSha256'), ('facts.json', 'factsSha256')]:
        if sha(base / filename) != plan[key]:
            raise ValueError('Frozen source criteria changed')
    if graph_files(SEED) != plan['seed']['files'] or sha(SEED_RECEIPT) != plan['seed']['receiptSha256']:
        raise ValueError('Original seed changed')
    for condition, source in [('public', PUBLIC), ('candidate', CANDIDATE)]:
        if sha(source / '.lake/build/bin/eggshell') != plan['runtimes'][condition]:
            raise ValueError('Study runtime changed')
    return plan


def index_public(directory, previous, inputs, env):
    cache = directory / 'provider-cache'
    clone(previous, cache)
    ids = {row['id'] for row in inputs}
    removed = []
    for path in (cache / 'vectors').glob('*.json'):
        row = read(path)
        if hashlib.sha256(row['text'].encode()).hexdigest() not in ids:
            removed.append(dict(file=path.name, sha256=sha(path)))
            path.unlink()  # Only this new, private cache; no old source cache is altered.
    save(directory / 'excluded-nonsource-cache.json', removed)
    command = [str(PUBLIC / '.lake/build/bin/eggshell'), 'search-provider', '--cache', str(cache), '--lane', 'index']
    receipts = []
    with (directory / 'index-stderr.log').open('xb') as errors:
        provider = subprocess.Popen(command, cwd=SOURCE, env=env, stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, stderr=errors, text=True)
        try:
            for offset in range(0, len(inputs), 32):
                batch = inputs[offset:offset+32]
                provider.stdin.write(json.dumps(dict(index=batch)) + '\n'); provider.stdin.flush()
                if not select.select([provider.stdout], [], [], 180)[0]:
                    raise TimeoutError('Public source indexing timed out')
                response = json.loads(provider.stdout.readline())
                if response.get('indexed') != [r['id'] for r in batch]:
                    raise ValueError('Public source indexing acknowledgement disagrees')
                receipts.append(response)
                save(directory / 'index-progress.json', dict(complete=False, receipts=receipts))
            provider.stdin.close()
            if provider.wait(timeout=10):
                raise RuntimeError('Public source indexing failed')
        finally:
            if provider.poll() is None:
                provider.terminate(); provider.wait(timeout=5)
    save(directory / 'index.json', dict(complete=True, inputs=len(inputs), receipts=receipts))


def checkpoint(base, plan, stage):
    directory = base / 'checkpoints' / f'stage{stage}'
    if (directory / 'ready.json').exists():
        ready = read(directory / 'ready.json')
        if (graph_files(directory / 'work.egg') != ready['files'] or
                graph_files(Path(ready['source'])) != ready['sourceFiles'] or
                sha(directory / 'evidence.json') != ready['evidenceSha256'] or
                tree_files(directory / 'provider-cache') != ready['providerFiles']):
            raise ValueError('Prepared common checkpoint changed')
        return ready
    if directory.exists():
        raise ValueError('Inspect the interrupted checkpoint; never rerun completed commands')
    source = SEED
    if stage > 1:
        require_stage_complete(base, stage - 1)
        attempt = base / 'candidate/attempts' / f'stage{stage - 1}-candidate-r0'
        result = read(attempt / 'result.json')
        source = attempt / 'output.egg'
        if graph_files(source) != result['outputGraphFiles']:
            raise ValueError('Predeclared common-history output changed')
        if read(attempt / 'keep.json')['exitCode'] != 0 or read(attempt / 'shutdown.json')['daemon_exit_code'] != 0:
            raise ValueError('Common history did not finish saving')
    directory.mkdir(parents=True)
    env = environment(directory / 'helper-data')
    env['EGGSHELL_PREFIX'] = str(ASSET_PREFIX)
    database = directory / 'work.egg'
    original = graph_files(source)
    raw, _ = execute([PRODUCER, source, database], directory / 'rebuild', env, SOURCE)
    rebuilt = json.loads(raw)
    if not rebuilt['authoritativeGraphEqual'] or not rebuilt['stableRootAndOwnerIds']:
        raise ValueError('Common publication changed source authority or owner identities')
    raw, _ = execute([INPUTS, 'inputs', database], directory / 'inputs', env, SOURCE)
    inputs = [json.loads(line) for line in raw.decode().splitlines()]
    raw, _ = execute([DOMAIN, database], directory / 'domain', env, SOURCE)
    domain = [json.loads(line) for line in raw.decode().splitlines()]
    prompts = [p.replace('<LLVM_SOURCE>', str(SOURCE)) for p in read(base / 'questions.json')['prompts']]
    documents = reconstruct(inputs, domain, prompts)
    save(directory / 'documents.json', documents)
    if len(documents) != rebuilt['documents']:
        raise ValueError('Document inventory differs from the checked graph')
    old_id, new_id = read(source / 'head')['identity'], read(database / 'head')['identity']
    old_vectors = source / 'derived' / old_id / 'semantic/vectors'
    clone(old_vectors, database / 'derived' / new_id / 'semantic/vectors')
    config = directory / 'warm.toml'
    config.write_text('default = "work"\n[eggs]\nwork = ' + json.dumps(str(database)) +
        '\n[profiles.work]\nread = ["work"]\nwrite = "work"\nhandoff_chars = 120000\n')
    env['EGGSHELL_CONFIG'] = str(config)
    warm = []
    for name in ['warm', 'repeat']:
        local = dict(env, EGGSHELL_DATA_ROOT=str(directory / (name + '-data')))
        raw, _ = execute([CANDIDATE / '.lake/build/bin/eggshell', 'egg', 'warm', 'work'],
                         directory / name, local, SOURCE, timeout=300)
        row = json.loads(raw)['databases'][0]
        if row['after']['missing'] or row['after']['invalid'] or row['after']['valid'] != len(inputs):
            raise ValueError('Common source warm is incomplete')
        if name == 'repeat' and any(row[k] for k in ['requested', 'batches']):
            raise ValueError('Independent private state repeated source embedding')
        if name == 'repeat' and any(row['lexical'][k] for k in ['added', 'hydrated']):
            raise ValueError('Independent private state rebuilt warm lexical data')
        warm.append(row)
    previous = PUBLIC_CACHE if stage == 1 else base / 'checkpoints' / f'stage{stage - 1}' / 'provider-cache'
    index_public(directory, previous, inputs, env)
    if graph_files(source) != original:
        raise ValueError('Preparing the new checkpoint changed its source')
    files = graph_files(database)
    facts = []
    for feature in read(base / 'facts.json')['facts']:
        path = SOURCE / feature['path']
        excerpt = '\n'.join(path.read_text().splitlines()[feature['first'] - 1:feature['last']])
        if not all(a in excerpt for a in feature['anchors']):
            raise ValueError('Source fact anchors changed: ' + feature['name'])
        facts.append(dict(**feature, sourceSha256=sha(path), excerpt=excerpt,
            storedOwners=[d['owner'] for d in documents if all(a in d['evidence'] for a in feature['anchors'])],
            fullExcerptOwners=[d['owner'] for d in documents if normalized(excerpt) in normalized(d['evidence'])]))
    topic = (stage - 1) % 3 + 1
    save(directory / 'evidence.json', dict(sourceGraphFiles=files, documents=len(documents),
        uniqueInputs=len(inputs), facts=[f for f in facts if topic in f['topics']],
        qualifications=plan['limitations']))
    ready = dict(directory=str(database), files=files, source=str(source), sourceFiles=original,
        documents=len(documents), uniqueInputs=len(inputs), warm=warm,
        evidenceSha256=sha(directory / 'evidence.json'), providerFiles=tree_files(directory / 'provider-cache'),
        newSeedAcquisition=False)
    save(directory / 'ready.json', ready)
    return ready


def restore_input(cell, label, preparation_only=False):
    protocol = read(cell / 'protocol.json')
    database = Path(protocol['activeDatabase'])
    prepared = cell / 'prepared' / label
    if graph_files(prepared / 'input.egg') != read(prepared / 'ready.json')['memory']['graphFiles']:
        raise ValueError('Qualified input backup changed')
    if database.exists():
        target = cell / 'displaced' / (('qualification-' if preparation_only else 'dispatch-') + label)
        if target.exists() and not preparation_only:
            raise ValueError('This dispatch was already started; inspect it instead of resubmitting')
        if preparation_only:
            index = 0
            while target.exists():
                index += 1
                target = cell / 'displaced' / f'qualification-{label}-{index}'
        target.parent.mkdir(parents=True, exist_ok=True)
        database.rename(target)
    clone(prepared / 'input.egg', database)


def prepare_stage(base, stage):
    plan = checked_plan(base)
    if any((base / s['condition'] / 'attempts' / s['label']).exists() for s in slots(stage)):
        raise ValueError('This stage already started generation; preserve its preparation')
    common = checkpoint(base, plan, stage)
    for condition in ['fresh', 'public', 'candidate']:
        cell = base / condition
        protocol = read(cell / 'protocol.json')
        if protocol['scheduledLabels'] or protocol['generationAllowed']:
            raise ValueError('Close generation before preparation')
        protocol['sourceSnapshots'][str(stage)] = {k:common[k] for k in ['directory', 'files']}
        save(cell / 'protocol.json', protocol)
        arm = 'fresh' if condition == 'fresh' else 'candidate'
        with study(cell):
            if not (cell / 'environments' / arm).exists():
                bench.prepare_fresh() if condition == 'fresh' else bench.prepare('candidate')
            for slot in [s for s in slots(stage) if s['condition'] == condition]:
                label = slot['label']
                case = cell / 'prepared' / label
                if case.exists():
                    if not (case / 'ready.json').exists() or (condition != 'fresh' and not (case / 'qualification.json').exists()):
                        raise ValueError('Inspect the interrupted preparation without repeating native hooks: ' + label)
                    if condition != 'fresh':
                        restore_input(cell, label, preparation_only=True)
                    protocol = read(cell / 'protocol.json')
                    prompt = read(base / 'questions.json')['prompts'][slot['topic']].replace('<LLVM_SOURCE>', str(SOURCE))
                    validate_prepared_trial(cell, protocol, arm, label, slot['topic'], prompt,
                                            cell / 'environments' / arm / 'environment.json')
                    continue
                if condition != 'fresh':
                    prepare_native_trial(cell, label, base / 'checkpoints' / f'stage{stage}' / 'evidence.json',
                        provider_template=base / 'checkpoints' / f'stage{stage}' / 'provider-cache'
                        if condition == 'public' else None)
                else:
                    case.mkdir(parents=True)
                    environment_file = cell / 'environments/fresh/environment.json'
                    env = read(environment_file)
                    prompt = read(base / 'questions.json')['prompts'][slot['topic']].replace('<LLVM_SOURCE>', str(SOURCE))
                    protocol = read(cell / 'protocol.json')
                    ready = dict(label=label, **protocol['trials'][label], model=plan['model'], effort=plan['effort'],
                        sourceWorkspace=str(SOURCE), promptSha256=hashlib.sha256(prompt.encode()).hexdigest(),
                        **{k:protocol[k] for k in ['runnerSha256', 'transportSha256', 'trialGateSha256', 'memoryGuardSha256']},
                        environmentSha256=sha(environment_file), configurationSha256=sha(Path(env['CODEX_HOME']) / 'config.toml'),
                        sourceSnapshot=protocol['sourceSnapshots'][str(stage)], files={}, memory=None)
                    save(case / 'ready.json', ready)
                    protocol['preparedTrialDigests'][label] = sha(case / 'ready.json')
                    save(cell / 'protocol.json', protocol)
                    validate_prepared_trial(cell, protocol, arm, label, slot['topic'], prompt, environment_file)
    admission = {s['label']:sha(base / s['condition'] / 'prepared' / s['label'] / 'ready.json') for s in slots(stage)}
    save(base / 'checkpoints' / f'stage{stage}' / 'admitted.json', dict(source=common, preparations=admission,
        allConditionsPreparedBeforeGeneration=True, answeringModelCalls=0))


def completed(base, slot):
    attempt = base / slot['condition'] / 'attempts' / slot['label']
    if not attempt.exists():
        return False
    if not (attempt / 'result.json').exists() or (attempt / 'failure.json').exists():
        raise ValueError('An attempted slot is incomplete; retain usage and do not resubmit: ' + slot['label'])
    result, usage = read(attempt / 'result.json'), read(attempt / 'usage.json')
    if (not result['completed'] or not usage['finalUsageKnown'] or result['usage'] != usage['total'] or
            usage.get('errors') or usage.get('reroutes') or usage.get('hookFailures')):
        raise ValueError('Completed slot has unknown or inconsistent usage')
    return True


def require_stage_complete(base, stage):
    if not all([completed(base, s) for s in slots(stage)]):
        raise ValueError('Finish every condition and repetition before advancing common history')


def run_next(base, stage):
    plan = checked_plan(base)
    if stage > 1:
        require_stage_complete(base, stage - 1)
    admission = read(base / 'checkpoints' / f'stage{stage}' / 'admitted.json')
    common = checkpoint(base, plan, stage)
    if admission['source'] != common or len(admission['preparations']) != 9:
        raise ValueError('Stage admission does not match the common saved checkpoint')
    for slot in slots(stage):
        cell = base / slot['condition']
        protocol = read(cell / 'protocol.json')
        digest = sha(cell / 'prepared' / slot['label'] / 'ready.json')
        if (digest != admission['preparations'][slot['label']] or
                protocol['preparedTrialDigests'][slot['label']] != digest or
                protocol['matchedPlanSha256'] != sha(base / 'plan.json') or
                protocol['sourceSnapshots'][str(stage)] != {k:common[k] for k in ['directory', 'files']}):
            raise ValueError('Stage qualification changed after admission')
    statuses = {s['label']:completed(base, s) for s in slots(stage)}
    for slot in slots(stage):
        if statuses[slot['label']]:
            continue
        cell, label = base / slot['condition'], slot['label']
        if slot['condition'] != 'fresh':
            restore_input(cell, label)
        protocol = read(cell / 'protocol.json')
        if protocol['scheduledLabels'] or protocol['generationAllowed']:
            raise ValueError('A previous dispatch remains open; inspect before resuming')
        protocol['scheduledLabels'] = [label]
        save(cell / 'protocol.json', protocol)
        try:
            with study(cell):
                bench.model_turn(slot['arm'], label, slot['topic'])
        finally:
            protocol['scheduledLabels'] = []
            save(cell / 'protocol.json', protocol)
        print(json.dumps(dict(completed=label, remainingInStage=sum(not completed(base, s) for s in slots(stage)),
                              productionAdoption=False)), flush=True)
        return
    print(json.dumps(dict(stage=stage, complete=True, productionAdoption=False)), flush=True)


def audit_stage(base, stage):
    plan = checked_plan(base)
    inventory = read(base / 'checkpoints' / f'stage{stage}' / 'evidence.json')
    trials = []
    for slot in slots(stage):
        attempt = base / slot['condition'] / 'attempts' / slot['label']
        if not attempt.exists():
            trials.append(dict(**slot, attempted=False))
            continue
        usage = read(attempt / 'usage.json') if (attempt / 'usage.json').exists() else None
        packets = read(attempt / 'delivered-packets.json') if (attempt / 'delivered-packets.json').exists() else []
        initial, all_parts = [], []
        for packet in packets:
            if sha(attempt / packet['file']) != packet['sha256']:
                raise ValueError('Captured delivery changed')
            parts = evidence_parts((attempt / packet['file']).read_text())
            all_parts.extend(parts)
            if packet['event'] == 'userPromptSubmit':
                initial.extend(parts)
        commands = []
        if (attempt / 'rpc/exchange.jsonl').exists():
            for line in (attempt / 'rpc/exchange.jsonl').open():
                try:
                    message = json.loads(line).get('message', {})
                except json.JSONDecodeError:
                    break  # The raw partial tail and unknown final usage remain retained.
                if message.get('method') == 'item/completed':
                    item = message['params']['item']
                    if item['type'] == 'commandExecution':
                        commands.append(item)
        facts = []
        for f in inventory['facts']:
            facts.append(dict(name=f['name'], storedOwners=f['storedOwners'], fullExcerptOwners=f['fullExcerptOwners'],
                initialAnchorOwners=[owner for owner, text in initial if all(a in text for a in f['anchors'])],
                initialExcerptOwners=[owner for owner, text in initial if normalized(f['excerpt']) in normalized(text)],
                anyDeliveryAnchorOwners=[owner for owner, text in all_parts if all(a in text for a in f['anchors'])],
                laterCommandOutputsWithAllAnchors=[dict(id=c['id'], command=c['command']) for c in commands
                    if all(a in (c.get('aggregatedOutput') or '') for a in f['anchors'])],
                laterCommandOutputsWithFullExcerpt=[dict(id=c['id'], command=c['command']) for c in commands
                    if normalized(f['excerpt']) in normalized(c.get('aggregatedOutput') or '')]))
        trials.append(dict(**slot, attempted=True, usage=usage, packets=packets, commands=len(commands), facts=facts,
            answer=str(attempt / 'answer.txt') if (attempt / 'answer.txt').exists() else None,
            answerSha256=sha(attempt / 'answer.txt') if (attempt / 'answer.txt').exists() else None,
            failure=read(attempt / 'failure.json') if (attempt / 'failure.json').exists() else None,
            qualityAccepted=False))
    directory = base / 'audits'; directory.mkdir(exist_ok=True)
    index = 0
    while (directory / f'stage{stage}-{index}.json').exists():
        index += 1
    save(directory / f'stage{stage}-{index}.json', dict(stage=stage, trials=trials,
        planSha256=sha(base / 'plan.json'), productionAdoption=False, qualityAccepted=False,
        qualifications=plan['limitations'], seedCostSeparate=True))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['init', 'prepare', 'next', 'audit'])
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--stage', type=int, choices=range(1, 7), default=1)
    args = parser.parse_args()
    if args.action == 'init':
        freeze(args.base)
    elif args.action == 'prepare':
        prepare_stage(args.base, args.stage)
    elif args.action == 'next':
        run_next(args.base, args.stage)
    else:
        audit_stage(args.base, args.stage)
