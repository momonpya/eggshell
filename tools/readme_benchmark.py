#!/usr/bin/env python3
"""Run the README LLVM study through native Codex, keeping every real attempt."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

from context_native_probe import sha
from pilot_hook_probe import vetted_hooks
from pilot_preflight import configuration
from pilot_server import Server
from owned_daemon import shutdown_owned
from readme_trial import capture_attempt, validate_observed_trial, validate_prepared_trial, sha as stream_sha
from memory_guard import require_guard
from semantic_latency import save, graph_files

LLVM = Path('/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project')
BASE = Path('/Users/ovm/.codex/experiments/eggshell/readme-luna-20261020')
ROOT = Path(__file__).resolve().parents[1]
CANDIDATE = Path('/Users/ovm/.codex/experiments/eggshell/uniform-budget-qualified-20261020/construction-1/checkout')


class BenchmarkServer(Server):
    # Native terminal-output notifications can exceed the metadata preflight's
    # 1 MiB admission limit. Bound capture without changing any model request.
    max_response_bytes = 32 * 1024 * 1024
    max_transcript_bytes = 256 * 1024 * 1024
    allowed_methods = Server.allowed_methods | {'thread/start', 'thread/read', 'thread/unsubscribe', 'turn/start'}
    allow_turn_events = True


def active_database():
    protocol = json.loads((BASE / 'protocol.json').read_text())
    return Path(protocol.get('activeDatabase', str(BASE / 'active/work.egg')))


def execute(command, env, destination, timeout=90):
    if destination.exists():
        raise ValueError('Refusing to repeat an existing preparation command: ' + str(destination))
    result = subprocess.run(list(map(str, command)), env=env, cwd=LLVM, capture_output=True,
                            text=True, timeout=timeout)
    save(destination, dict(command=list(map(str, command)), exitCode=result.returncode,
                           stdout=result.stdout, stderr=result.stderr))
    if result.returncode:
        raise RuntimeError('Preparation failed: ' + str(destination))
    return result


def prepare(arm):
    if arm != 'candidate':
        raise ValueError('Only the candidate has a memory environment')
    protocol = json.loads((BASE / 'protocol.json').read_text())
    require_guard(protocol)
    source = Path(protocol['candidateSource'])
    if sha(source / '.lake/build/bin/eggshell') != protocol['candidate']:
        raise ValueError('Preparation source differs from the frozen runtime')
    case = BASE / 'environments' / arm
    if case.exists():
        raise ValueError('Inspect existing environment before resuming it')
    case.mkdir(parents=True, mode=0o700)
    account = case / 'account'; account.mkdir(mode=0o700)
    temporary = case / 'tmp'; temporary.mkdir()
    prefix = case / 'prefix'
    assets = prefix / 'share/eggshell/minilm'
    assets.mkdir(parents=True)
    for name in ['fastembed-0.8.0', 'models', 'fastembed-0.8.0.model-ready']:
        subprocess.run(['/bin/cp', '-cR', str(Path('/Users/ovm/.local/share/eggshell/minilm') / name),
                        str(assets / name)], check=True)
    (account / 'auth.json').symlink_to('/Users/ovm/.codex/auth.json')
    roots = [Path('/opt/homebrew'), Path('/Library/Developer/CommandLineTools'),
             Path('/Users/ovm/.nodebrew')]
    config = configuration(LLVM, roots).replace('plugins = false', 'plugins = true').replace('hooks = false', 'hooks = true')
    # Source investigation is read-only. Hook writers are host processes and
    # write only to the experiment's independently configured memory DB.
    config = config.replace('extends = ":workspace"', 'extends = ":read-only"')
    config = config.replace('[permissions.pilot.network]', json.dumps(str(LLVM)) + ' = "read"\n[permissions.pilot.network]')
    model = json.loads((BASE / 'protocol.json').read_text())['model']
    config = 'model = ' + json.dumps(model) + '\nmodel_reasoning_effort = "xhigh"\n' + config
    (account / 'config.toml').write_text(config)
    egg_config = case / 'eggshell.toml'
    database = active_database()
    egg_config.write_text('default = "work"\n[eggs]\nwork = ' + json.dumps(str(database)) +
        '\n[profiles.work]\nread = ["work"]\nwrite = "work"\nhandoff_chars = 120000\n')
    env = {k:v for k,v in os.environ.items() if k in {'PATH','HOME','USER','LOGNAME','LANG','LC_ALL'}}
    env.update(CODEX_HOME=str(account), TMPDIR=str(temporary), EGGSHELL_PREFIX=str(prefix),
        EGGSHELL_DATA_ROOT=str(case / 'data'), EGGSHELL_CONFIG=str(egg_config),
        HF_HUB_OFFLINE='1', LEAN_NUM_THREADS='1')
    save(case / 'environment.json', env)
    execute([source / '.lake/build/bin/eggshell', 'install', 'codex'], env, case / 'install.json', 180)
    if sha(prefix / 'libexec/eggshell') != sha(source / '.lake/build/bin/eggshell'):
        raise ValueError('Installed binary differs from selected runtime')
    with Server([shutil.which('codex'), '--strict-config', 'app-server'], LLVM, env, case / 'discovery') as server:
        server.initialize('0.145.0')
        discovered = server.request('hooks/list', dict(cwds=[str(LLVM)]))
    hooks, _ = vetted_hooks(discovered, account, prefix, source)
    save(case / 'hooks-before-trust.json', discovered)
    with (account / 'config.toml').open('a') as out:
        for hook in hooks:
            out.write('\n[hooks.state.' + json.dumps(hook['key']) + ']\nenabled = true\ntrusted_hash = ' +
                      json.dumps(hook['currentHash']) + '\n')
    save(case / 'prepared.json', dict(arm=arm, runtimeSha256=sha(prefix / 'libexec/eggshell'),
        configurationSha256=sha(account / 'config.toml'), database=str(database), agentsEnabled=False))
    return env


def prepare_fresh():
    require_guard(json.loads((BASE / 'protocol.json').read_text()))
    case = BASE / 'environments/fresh'
    case.mkdir(parents=True, exist_ok=False, mode=0o700)
    account = case / 'account'; account.mkdir(mode=0o700)
    temporary = case / 'tmp'; temporary.mkdir()
    (account / 'auth.json').symlink_to('/Users/ovm/.codex/auth.json')
    roots = [Path('/opt/homebrew'), Path('/Library/Developer/CommandLineTools'), Path('/Users/ovm/.nodebrew')]
    model = json.loads((BASE / 'protocol.json').read_text())['model']
    config = configuration(LLVM, roots).replace('extends = ":workspace"', 'extends = ":read-only"')
    config = config.replace('[permissions.pilot.network]', json.dumps(str(LLVM)) + ' = "read"\n[permissions.pilot.network]')
    (account / 'config.toml').write_text('model = ' + json.dumps(model) + '\nmodel_reasoning_effort = "xhigh"\n' + config)
    env = {k:v for k,v in os.environ.items() if k in {'PATH','HOME','USER','LOGNAME','LANG','LC_ALL'}}
    env.update(CODEX_HOME=str(account), TMPDIR=str(temporary))
    save(case / 'environment.json', env)
    return env


def generation_protocol(arm, label=None):
    protocol = json.loads((BASE / 'protocol.json').read_text())
    if arm not in {'fresh', 'candidate'}:
        raise ValueError('Token comparison is fresh versus candidate only')
    if protocol.get('generationAllowed') is not True and label not in protocol.get('scheduledLabels', []):
        raise ValueError('Model trials stopped for regression diagnosis; retain existing attempts')
    return protocol


def model_turn(arm, label, topic):
    protocol = generation_protocol(arm, label)
    if protocol['sourceWorkspace'] != str(LLVM):
        raise ValueError('Model workspace differs from the frozen investigation')
    transport = Path(__file__).with_name('pilot_server.py')
    if protocol.get('transportSha256') != sha(transport):
        raise ValueError('Freeze the exact benchmark transport before starting model turns')
    if protocol.get('runnerSha256') != sha(Path(__file__)):
        raise ValueError('Freeze the same benchmark runner for all conditions')
    case = BASE / 'environments' / arm
    record = json.loads((ROOT / 'docs/benchmarks/llvm-three-topics.json').read_text())
    prompt = record['prompts'][topic].replace('<LLVM_SOURCE>', str(LLVM))
    prepared = validate_prepared_trial(BASE, protocol, arm, label, topic, prompt, case / 'environment.json')
    require_guard(protocol)
    env = prepared['environment']
    if shutil.disk_usage(BASE).free < 4 * 1024**3:
        raise OSError('Need 4 GiB free before a model trial; retain existing attempts')
    executable = shutil.which('codex')
    if not executable or stream_sha(executable) != protocol['codexExecutableSha256']:
        raise ValueError('The native CLI differs from the frozen harness')
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=LLVM, text=True).strip() != protocol['sourceCommit']:
        raise ValueError('LLVM source differs from the frozen checkout')
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=LLVM, text=True).strip():
        raise ValueError('LLVM source has changed before generation')
    attempt = BASE / 'attempts' / label
    attempt.mkdir(parents=True, exist_ok=False, mode=0o700)
    model = protocol['model']
    (attempt / 'prompt.txt').write_text(prompt)
    shutil.copy2(Path(__file__), attempt / 'runner.py')
    shutil.copy2(transport, attempt / 'transport.py')
    shutil.copy2(Path(__file__).with_name('readme_trial.py'), attempt / 'trial-gate.py')
    shutil.copy2(Path(__file__).with_name('memory_guard.py'), attempt / 'memory-guard.py')
    shutil.copy2(BASE / 'prepared' / label / 'ready.json', attempt / 'prepared-trial.json')
    save(attempt / 'admission.json', dict(expectedBodySha256=prepared['expectedBodySha256'],
        facts=prepared.get('facts'), finalUsageRequired=True, automaticResubmission=False))
    shutil.copy2(BASE / 'protocol.json', attempt / 'protocol.json')
    if arm != 'fresh':
        database = active_database()
        save(attempt / 'input-snapshot.json', dict(files=graph_files(database) if database.exists() else {},
            head=json.loads((database / 'head').read_text()) if (database / 'head').exists() else None))
    save(attempt / 'invocation.json', dict(arm=arm, label=label, topic=topic, model=model,
        effort='xhigh', promptSha256=sha(attempt / 'prompt.txt'),
        runtimeSha256=sha(Path(env['EGGSHELL_PREFIX']) / 'libexec/eggshell') if arm != 'fresh' else None,
        study=str(BASE), runtimeSource=protocol['candidateSource'] if arm != 'fresh' else None,
        activeDatabase=str(active_database()) if arm != 'fresh' else None,
        configurationSha256=sha(case / 'account/config.toml'),
        protocolSha256=sha(BASE / 'protocol.json'), transportSha256=sha(transport),
        captureLimits=dict(responseBytes=BenchmarkServer.max_response_bytes,
            transcriptBytes=BenchmarkServer.max_transcript_bytes),
        startedUtc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())))
    started = time.monotonic()
    identity = None
    successful = None
    manager = None
    manager_log = None
    generation_completed = False
    try:
        with BenchmarkServer([executable, '--strict-config', 'app-server'], LLVM, env,
                             attempt / 'rpc', timeout=900) as server:
            hello = server.initialize('0.145.0')
            listed = server.request('hooks/list', dict(cwds=[str(LLVM)]))
            if arm == 'fresh' and any(row['hooks'] or row['errors'] or row['warnings'] for row in listed['data']):
                raise ValueError('Fresh condition has hooks')
            unless_trusted = [hook for row in listed['data'] for hook in row['hooks'] if hook['trustStatus'] != 'trusted']
            if unless_trusted:
                raise ValueError('A reviewed hook is not trusted')
            thread = server.request('thread/start', dict(cwd=str(LLVM), model=model,
                permissions='pilot', approvalPolicy='never', ephemeral=True, allowProviderModelFallback=False))
            save(attempt / 'thread.json', thread)
            if thread['model'] != model or thread['reasoningEffort'] != 'xhigh' or thread['instructionSources']:
                raise ValueError('Model, reasoning effort or instructions differ from protocol')
            identity = thread['thread']['id']
            if arm != 'fresh':
                binary = Path(env['EGGSHELL_PREFIX']) / 'libexec/eggshell'
                manager_log = (attempt / 'manager.log').open('wb')
                manager = subprocess.Popen([str(binary), 'codex-daemon', identity],
                    cwd=LLVM, env=env, stdout=manager_log, stderr=subprocess.STDOUT)
                endpoint = Path(env['EGGSHELL_DATA_ROOT']) / 'sessions' / identity / 'daemon.json'
                expires = time.monotonic() + 10
                while not endpoint.exists():
                    if manager.poll() is not None or time.monotonic() >= expires:
                        raise RuntimeError('Owned native manager did not publish its endpoint')
                    time.sleep(.005)
            turn = server.request('turn/start', dict(threadId=identity, model=model, effort='xhigh',
                input=[dict(type='text', text=prompt)]))
            save(attempt / 'turn-start.json', turn)
            completed = server.wait_notification('turn/completed', lambda p:
                p['threadId'] == identity and p['turn']['id'] == turn['turn']['id'])
            save(attempt / 'completed.json', completed)
            generation_completed = completed['turn']['status'] == 'completed'
            answers = [message['params']['item']['text'] for message in server.notifications
                if message.get('method') == 'item/completed' and message['params'].get('threadId') == identity
                and message['params'].get('turnId') == turn['turn']['id']
                and message['params']['item']['type'] == 'agentMessage'
                and message['params']['item'].get('phase') == 'final_answer']
            (attempt / 'answer.txt').write_text('\n'.join(answers))
            with server.lock:
                usage, packets = capture_attempt(attempt, identity, generation_completed)
            validate_observed_trial(prepared, usage, packets, arm)
            if not generation_completed or not answers:
                raise ValueError('Generation did not complete; retain this attempt and its usage')
            if arm != 'fresh':
                execute([Path(env['EGGSHELL_PREFIX']) / 'libexec/eggshell', 'egg', 'keep'],
                    dict(env, CODEX_THREAD_ID=identity), attempt / 'keep.json', 180)
            server.request('thread/unsubscribe', dict(threadId=identity))
        successful = dict(completed=True, elapsedSeconds=time.monotonic()-started,
            threadId=identity, answerSha256=sha(attempt / 'answer.txt'), usage=usage['total'])
    except BaseException as error:
        if (attempt / 'rpc/exchange.jsonl').exists():
            try:
                capture_attempt(attempt, identity, generation_completed)
            except BaseException as capture_error:
                save(attempt / 'capture-failure.json', dict(error=f'{type(capture_error).__name__}: {capture_error}',
                    rawRpcRetained=True, unknownFinalUsage=True))
        save(attempt / 'failure.json', dict(error=f'{type(error).__name__}: {error}', elapsedSeconds=time.monotonic()-started))
        raise
    finally:
        if manager is not None:
            try:
                shutdown_owned(manager, Path(env['EGGSHELL_PREFIX']) / 'libexec/eggshell',
                    env, LLVM, attempt / 'shutdown.json')
            except BaseException as cleanup_error:
                save(attempt / 'cleanup-failure.json', dict(error=f'{type(cleanup_error).__name__}: {cleanup_error}',
                    rawRpcRetained=True, trialAccepted=False))
                raise
            finally:
                if manager.poll() is None:
                    manager.terminate()
                    manager.wait(timeout=5)
                manager_log.close()
    if arm != 'fresh':
        subprocess.run(['/bin/cp', '-cR', str(active_database()), str(attempt / 'output.egg')], check=True)
        successful['outputGraphFiles'] = graph_files(attempt / 'output.egg')
    save(attempt / 'result.json', successful)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'turn'])
    parser.add_argument('--arm', choices=['candidate','fresh'], required=True)
    parser.add_argument('--label')
    parser.add_argument('--topic', type=int, choices=[0,1,2,3])
    args = parser.parse_args()
    if args.action == 'prepare': prepare_fresh() if args.arm == 'fresh' else prepare(args.arm)
    else: model_turn(args.arm, args.label, args.topic)
