#!/usr/bin/env python3
"""Compare real delivery functions on identical publications without model turns."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import time

from semantic_latency import graph_files, save

ROOT = Path(__file__).resolve().parents[1]
EXPERIMENTS = Path('/Users/ovm/.codex/experiments/eggshell')
STUDY = EXPERIMENTS / 'readme-luna-20261020'
OUTPUT = EXPERIMENTS / 'readme-delivery-parity-20261020/inspection-2'
LLVM = Path('/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project')
VARIANTS = {
    'public-warm': STUDY / 'public-main-5187316/checkout',
    'retrieval-combined': EXPERIMENTS / 'retrieval-combined-20261020/construction-1/checkout',
    'discovery': EXPERIMENTS / 'discovery-candidate-qualified-20261020/construction-2/checkout',
    'match': EXPERIMENTS / 'discovery-match-qualified-20261020/construction-1/checkout',
    'focus-warm': EXPERIMENTS / 'focus-warm-qualified-20261020/construction-4/checkout',
    'context-plan': EXPERIMENTS / 'context-plan-qualified-20261020/construction-2/checkout',
    'context-memo': EXPERIMENTS / 'context-memo-qualified-20261020/construction-1/checkout',
    'context-prefix': EXPERIMENTS / 'context-prefix-qualified-20261020/construction-8/checkout',
    'directory-read': EXPERIMENTS / 'directory-read-qualified-20261020/construction-1/checkout',
    'initial-budget': EXPERIMENTS / 'initial-budget-qualified-20261020/construction-6/checkout',
    'rank-directory': EXPERIMENTS / 'rank-directory-qualified-20261020/construction-6/checkout',
    'ready-delivery': EXPERIMENTS / 'ready-delivery-qualified-20261020/construction-7/checkout',
    'owner-projection': EXPERIMENTS / 'owner-projection-qualified-20261020/construction-4/checkout',
    'uniform-budget': EXPERIMENTS / 'uniform-budget-qualified-20261020/construction-1/checkout',
    'uniform-public-provider': EXPERIMENTS / 'uniform-budget-qualified-20261020/construction-1/checkout',
    'first-segment-control': EXPERIMENTS / 'first-segment-control-20261020/construction-1/checkout',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clone(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['/bin/cp', '-cR', str(source), str(destination)], check=True)


def run_command(command, cwd, env, record, timeout=600):
    if record.exists():
        row = json.loads(record.read_text())
        if row['exitCode']:
            raise RuntimeError('Inspect the retained failed command: ' + str(record))
        return row
    started = time.monotonic()
    result = subprocess.run(list(map(str, command)), cwd=cwd, env=env, capture_output=True,
                            text=True, timeout=timeout)
    row = dict(command=list(map(str, command)), exitCode=result.returncode,
               elapsedSeconds=time.monotonic()-started, stdout=result.stdout, stderr=result.stderr)
    save(record, row)
    if result.returncode:
        raise RuntimeError('Delivery audit command failed: ' + str(record))
    return row


def prepare(name):
    original = VARIANTS[name]
    cell = OUTPUT / 'variants' / name
    checkout = cell / 'checkout'
    if not checkout.exists():
        clone(original, checkout)
        shutil.copy2(ROOT / 'tools/DeliveryAudit.lean', checkout / 'tools/DeliveryAudit.lean')
        lakefile = checkout / 'lakefile.lean'
        if '\nlean_exe delivery_audit where\n' not in lakefile.read_text():
            with lakefile.open('a') as stream:
                stream.write('\nlean_exe delivery_audit where\n  root := `tools.DeliveryAudit\n')
        save(cell / 'input.json', dict(original=str(original), runtimeSha256=sha(original / '.lake/build/bin/eggshell'),
            helperSha256=sha(ROOT / 'tools/DeliveryAudit.lean'), generationModelCalls=0))
    env = dict(os.environ, EGGSHELL_PREFIX=str(STUDY / 'environments/candidate/prefix'),
               EGGSHELL_DATA_ROOT=str(cell / 'data'), HF_HUB_OFFLINE='1', LEAN_NUM_THREADS='1')
    env.pop('EGGSHELL_CONFIG', None)
    env.pop('CODEX_THREAD_ID', None)
    run_command(['lake', '--no-cache', 'build', 'delivery_audit'], checkout, env, cell / 'build.json')
    if sha(checkout / '.lake/build/bin/eggshell') != json.loads((cell / 'input.json').read_text())['runtimeSha256']:
        raise ValueError('Building an inspection helper changed the frozen runtime')
    return cell, checkout, env


def index_inputs(name, cell, binary, env, database, inputs):
    record = cell / 'index.json'
    if record.exists():
        if not json.loads(record.read_text())['complete']:
            raise ValueError('Incomplete retained cache preparation')
        return
    identity = json.loads((database / 'head').read_text())['identity']
    previous = OUTPUT.parent / 'variants/public-warm/seed'
    prepared_seed = OUTPUT / 'variants/public-warm/seed'
    if name == 'public-warm' and cell != prepared_seed and not (cell / 'provider-cache').exists() and (prepared_seed / 'index.json').exists():
        if json.loads((prepared_seed / 'index.json').read_text())['complete']:
            clone(prepared_seed / 'provider-cache', cell / 'provider-cache')
            save(cell / 'reused-cache-hints.json', dict(source=str(prepared_seed),
                complete=False, verification='Provider validates model and exact text for every input below; encode all missing inputs before comparison'))
    if name == 'public-warm' and not (cell / 'provider-cache').exists() and (previous / 'index.json').exists():
        prior = json.loads((previous / 'index.json').read_text())
        prior_inputs = json.loads((previous / 'inputs.json').read_text())['stdout']
        if prior['complete'] and [json.loads(line) for line in prior_inputs.splitlines()] == inputs:
            clone(previous / 'provider-cache', cell / 'provider-cache')
            save(cell / 'reused-prepared-cache.json', dict(source=str(previous), inputsEqual=True))
    command = [str(binary), 'search-provider', '--cache', str(cell / 'provider-cache'), '--lane', 'index']
    receipts = []
    with (cell / 'index-stderr.log').open('wb') as errors:
        provider = subprocess.Popen(command, cwd=LLVM, env=env, stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, stderr=errors, text=True)
        try:
            for offset in range(0, len(inputs), 32):
                batch = inputs[offset:offset+32]
                request = {'index' if name == 'public-warm' else 'index_windows': batch}
                if name != 'public-warm':
                    request.update(cache=dict(database=identity, directory=str(database)), cache_storage='database')
                provider.stdin.write(json.dumps(request) + '\n'); provider.stdin.flush()
                if not select.select([provider.stdout], [], [], 180)[0]:
                    raise TimeoutError('Cache preparation response timed out')
                response = json.loads(provider.stdout.readline())
                if response.get('indexed') != [row['id'] for row in batch]:
                    raise ValueError('Cache preparation acknowledgement disagrees: ' + str(response))
                receipts.append(response)
            provider.stdin.close()
            if provider.wait(timeout=10):
                raise RuntimeError('Cache preparation process failed')
        finally:
            if provider.poll() is None:
                provider.terminate(); provider.wait(timeout=5)
    save(record, dict(complete=True, windows=len(inputs), receipts=receipts, generationModelCalls=0))


def inspect(name, checkpoint, topics, source_database=None):
    variant, checkout, env = prepare(name)
    helper = checkout / '.lake/build/bin/delivery_audit'
    binary = checkout / '.lake/build/bin/eggshell'
    cell = variant / checkpoint
    database = cell / 'work.egg'
    common = Path(source_database) if source_database else STUDY / 'checkpoints' / checkpoint / 'work.egg'
    original = graph_files(common)
    if not database.exists():
        clone(common, database)
    if graph_files(database) != original:
        raise ValueError('Delivery comparison changed its original publication')
    local_env = dict(env, EGGSHELL_DATA_ROOT=str(cell / 'data'))
    exported = run_command([helper, 'inputs', database], LLVM, local_env, cell / 'inputs.json')
    inputs = [json.loads(line) for line in exported['stdout'].splitlines()]
    index_inputs(name, cell, binary, local_env, database, inputs)
    if name != 'public-warm':
        config = cell / 'warm.toml'
        config.write_text('default = "audit"\nsemantic_matcher = ' +
            json.dumps([str(binary), 'search-provider']) + '\n[eggs]\nwork = ' +
            json.dumps(str(database)) + '\n[profiles.audit]\nread = ["work"]\nwrite = "work"\n')
        run_command([binary, 'egg', 'warm', 'work'], LLVM,
                    dict(local_env, EGGSHELL_CONFIG=str(config)), cell / 'warm.json')
    prompts = json.loads((ROOT / 'docs/benchmarks/llvm-three-topics.json').read_text())['prompts']
    for topic in topics:
        packet = cell / f'topic-{topic}.json'
        if packet.exists() and (json.loads(packet.read_text()).get('handoff') or {}).get('reason') == 'search-incomplete':
            # Keep the invalid preparation observation. This is a zero-generation
            # diagnostic, never a replay of an actual measured model request.
            packet.rename(cell / f'topic-{topic}-before-index-warm.json')
            (cell / f'topic-{topic}-command.json').rename(cell / f'topic-{topic}-before-index-warm-command.json')
        prompt = cell / f'topic-{topic}.txt'
        prompt.write_text(prompts[topic].replace('<LLVM_SOURCE>', str(LLVM)))
        command = [helper, 'inspect', database, prompt, cell / 'provider-cache', packet]
        if name == 'uniform-public-provider':
            classic = OUTPUT / 'variants/public-warm'
            if not (classic / checkpoint / 'index.json').exists():
                raise ValueError('Prepare the identical public source/focus cache first')
            command = [helper, 'inspect-provider', database, prompt,
                       classic / checkpoint / 'provider-cache', packet,
                       classic / 'checkout/.lake/build/bin/eggshell']
        run_command(command,
                    LLVM, local_env, cell / f'topic-{topic}-command.json')
        result = json.loads(packet.read_text())
        handoff = result['handoff']
        if not handoff or handoff['reason'] == 'search-incomplete':
            raise ValueError('No completed body; inspect before comparing: ' + str(packet))
        body = cell / f'topic-{topic}-body.txt'
        body.write_text(handoff['text'])
        if graph_files(database) != original or graph_files(common) != original:
            raise ValueError('Inspection changed the saved graph')
        save(cell / f'topic-{topic}-result.json', dict(runtimeSha256=sha(binary),
            checkpoint=checkpoint, topic=topic, sourceDatabase=str(common),
            graphFiles=original, promptSha256=sha(prompt),
            bodySha256=sha(body), bodyBytes=body.stat().st_size, reason=handoff['reason'],
            generationModelCalls=0, productionAdoption=False))
        print(json.dumps(dict(variant=name, checkpoint=checkpoint, topic=topic,
                             bodySha256=sha(body), reason=handoff['reason'])), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--variants', nargs='+', choices=list(VARIANTS), required=True)
    parser.add_argument('--checkpoint', choices=['seed', 'stage-1'], default='seed')
    parser.add_argument('--database', type=Path,
                        help='Use this one frozen common snapshot for every implementation')
    parser.add_argument('--topics', type=int, nargs='+', choices=[1, 2, 3], default=[1, 2, 3])
    args = parser.parse_args()
    for name in args.variants:
        inspect(name, args.checkpoint, args.topics, args.database)
