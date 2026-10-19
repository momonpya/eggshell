#!/usr/bin/env python3
"""Qualify an isolated 2-gram index against one saved legacy native DB."""
import argparse
from contextlib import nullcontext
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from context_native_probe import environment, sha, tree
from owned_daemon import shutdown_owned
from pilot_memory_probe import protected_databases
from semantic_latency import execute, graph_files, hook, receipt_for, save, shutdown


QUERIES = [
    ('korean', 'Find 한국어 검색 evidence', 'ORIGINAL_KOREAN_BODY'),
    ('cyrillic', 'Find Поиск evidence', 'ORIGINAL_CYRILLIC_BODY'),
    ('kana', 'Find ガイド evidence', 'ORIGINAL_WIDTH_BODY'),
    ('width', 'Find abc123 evidence', 'ORIGINAL_WIDTH_BODY'),
    ('single', 'Find 木 evidence', 'ORIGINAL_JAPANESE_BODY'),
    ('accent', 'Find résumé evidence', 'ORIGINAL_ACCENT_BODY'),
]


def config(path, binary, databases, writable=False, provider=None):
    command = 'false' if provider is None else json.dumps([str(x) for x in provider])
    names = ['source' + str(i) for i in range(len(databases))]
    path.write_text('default = "probe"\nsemantic_matcher = ' + command + '\n[eggs]\n' +
                    ''.join(name + ' = ' + json.dumps(str(db)) + '\n' for name, db in zip(names, databases)) +
                    '[profiles.probe]\nread = ' + json.dumps(names) + '\n' +
                    ('write = "source0"\n' if writable else '') + 'handoff_chars = 120000\n')


def lexical_doctor(binary, cell, env, label, expected):
    raw, _ = execute([binary, 'egg', 'doctor'], cell / label, env, cell)
    rows = json.loads(raw)['databases']
    if not rows or any(row['state'] != expected or row['lexical']['ready'] != (expected == 'warm')
                       or row['numerical'] != 'disabled' for row in rows):
        raise ValueError('Doctor did not report the actual lexical-only state')
    return rows


def deliver(binary, cell, env, label, question, marker, semantic='notRequested'):
    session = 'lexical-' + label
    hook(binary, cell, env, 'SessionStart', session, cell / (label + '-start'))
    try:
        stdout, timing = hook(binary, cell, env, 'UserPromptSubmit', session, cell / (label + '-hook'), question)
        response = json.loads(stdout)
        context = response['hookSpecificOutput']['additionalContext']
        if marker not in context:
            raise ValueError('The original saved body was not delivered: ' + label)
        receipt = receipt_for(cell / 'data', session)
        published = json.loads((receipt / 'published.json').read_text())['data']
        ack = json.loads((receipt / 'ack.json').read_text())['data']
        search = json.loads((receipt / 'search.json').read_text())['data']
        if (published['output'].encode() != stdout or published['sha256'] != hashlib.sha256(stdout).hexdigest()
                or published['bytes'] != len(stdout) or not published['replyComplete']
                or published['flushedMs'] > published['deadlineMs'] or not ack['offerAccepted']):
            raise ValueError('Original stdout/publication/ACK do not agree')
        if search['trace']['semantic'] != semantic:
            raise ValueError('Unexpected semantic status: ' + repr(search['trace']))
        numerical = [json.loads(p.read_text())['data'] for p in receipt.glob('numerical-*.json')]
        if semantic == 'notRequested' and numerical:
            raise ValueError('Lexical-only delivery invoked a numerical provider')
        notice = {'pending': 'is pending', 'timedOut': 'timed out'}.get(semantic)
        if notice is not None and 'semantic search ' + notice not in response.get('systemMessage', ''):
            raise ValueError('Fallback concealed the incomplete semantic search')
        if timing['elapsedMs'] >= 5000:
            raise ValueError('The native fallback exceeded the five-second diagnostic limit')
        row = dict(label=label, elapsedMs=timing['elapsedMs'], receipt=receipt.name,
                   trace=search['trace'], numerical=numerical, originalBody=True,
                   stdoutSha256=published['sha256'], accepted=True,
                   markerOccurrences=context.count(marker))
        save(cell / (label + '-result.json'), row)
        return row
    finally:
        shutdown(binary, cell, env, label + '-shutdown')


def recover(binary, helper, cell, env, database):
    raw, _ = execute([helper, 'save', database], cell / 'native-save', env, cell)
    saved = json.loads(raw)
    if saved['lexical']['ready'] or not saved['savingChatRemoved']:
        raise ValueError('A native save did not leave explicit lexical indexing debt')
    tickets = lambda: list(database.glob('derived/*/indexes/**/*.json'))
    pending = tickets()
    if not pending:
        raise ValueError('An encoder-disabled save did not persist a DB-owned lexical ticket')
    head = sha(database / 'head')
    save(cell / 'before-drain.json', dict(headSha256=head, tickets=[str(p) for p in pending]))
    with (cell / 'index-drain.log').open('wb') as log:
        process = subprocess.Popen([str(binary), 'codex-daemon', 'lexical-independent-recovery'],
                                   env=env, cwd=cell, stdout=log, stderr=subprocess.STDOUT)
        try:
            expires = time.monotonic() + 20
            while tickets():
                if process.poll() is not None or time.monotonic() > expires:
                    raise RuntimeError('Independent lexical index recovery exited or timed out')
                time.sleep(0.01)
            stopped = shutdown_owned(process, binary, env, cell, cell / 'index-shutdown.json')
        finally:
            if process.poll() is None:
                process.terminate(); process.wait(timeout=3)
    raw, _ = execute([helper, 'status', database], cell / 'status-after-drain', env, cell)
    if (not json.loads(raw)['ready'] or sha(database / 'head') != head or tickets()
            or (cell / 'data/sessions/lexical-native-writer').exists()):
        raise ValueError('Independent recovery changed the graph or needed the deleted saving chat')
    delivered = deliver(binary, cell, env, 'recovered', 'Find 추가 저장 evidence', 'NEW_LEXICAL_BODY')
    return dict(ticketsDrained=len(pending), graphHeadUnchanged=True, savingChatAbsent=True,
                shutdown=stopped, delivery=delivered)


def run(args):
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=False, mode=0o700)
    build = args.build.resolve(); checkout = build / 'checkout'
    binary = checkout / '.lake/build/bin/eggshell'
    helper = checkout / '.lake/build/bin/lexical_probe'
    built = json.loads((build / 'result.json').read_text())
    if sha(binary) != built['candidateSha256'] or sha(build / 'legacy-seed') != built['legacySeedSha256']:
        raise ValueError('The isolated candidate or legacy seed producer changed')
    ordinary = args.source.resolve() / '.lake/build/bin/eggshell'
    frozen = {str(p): sha(p) for p in [binary, helper, ordinary, build / 'legacy-seed']}
    empty_prefix = output / 'empty-prefix'; empty_prefix.mkdir()
    seed_env = environment(output / 'seed-data', output / 'seed.toml', empty_prefix)
    raw, _ = execute([build / 'legacy-seed', 'prepare', output / 'seed'], output / 'prepare', seed_env, output)
    seed = json.loads(raw); database = Path(seed['database'])
    if seed['documents'] != 5 or seed['legacyKoreanPosting']:
        raise ValueError('The common seed was not saved under the actual old lexical policy')
    graph = graph_files(database); saved_tree = tree(database)
    save(output / 'saved-snapshot.json', dict(seed=seed, graph=graph, files=saved_tree,
                                            generationModelCalls=0, productionAdoption=False))
    results = {}
    for layout in ['database', 'private-overlay']:
        cell = output / layout; cell.mkdir(); copied = cell / 'source.egg'
        subprocess.run(['/bin/cp', '-cpR', str(database), str(copied)], check=True, timeout=30)
        if tree(copied) != saved_tree:
            raise ValueError('Native trial did not use the identical saved source snapshot')
        config_file = cell / 'config.toml'; config(config_file, binary, [copied], layout == 'database')
        env = environment(cell / 'data', config_file, empty_prefix)
        cold = lexical_doctor(binary, cell, env, 'doctor-cold', 'cold')
        with protected_databases([copied]) if layout == 'private-overlay' else nullcontext():
            before = tree(copied)
            raw, _ = execute([binary, 'egg', 'warm', 'source0'], cell / 'warm', env, cell)
            warmed = json.loads(raw)['databases'][0]
            if warmed['lexical']['added'] != 5 or warmed['lexical']['hydrated'] != 5 or warmed['requested']:
                raise ValueError('Lexical-only warm did not index exactly the five original saved owners')
            raw, _ = execute([binary, 'egg', 'warm', 'source0'], cell / 'warm-again', env, cell)
            repeated = json.loads(raw)['databases'][0]
            if repeated['lexical']['added'] or repeated['lexical']['hydrated'] or repeated['lexical']['batches']:
                raise ValueError('An already warm lexical index hydrated or rebuilt the corpus')
            warm = lexical_doctor(binary, cell, env, 'doctor-warm', 'warm')
            config(config_file, binary, [copied])
            healthy_before = tree(copied)
            with protected_databases([copied]) if layout == 'database' else nullcontext():
                rows = [deliver(binary, cell, env, layout + '-' + label, question, marker)
                        for label, question, marker in QUERIES]
            if tree(copied) != healthy_before or graph_files(copied) != graph:
                raise ValueError('Read-only lexical delivery changed source DB bytes')
            if layout == 'private-overlay' and tree(copied) != before:
                raise ValueError('Private lexical warming wrote into the shared protected DB')
            results[layout] = dict(cold=cold, warm=warm, indexed=warmed, repeated=repeated, deliveries=rows)
    # A copied DB must be canonicalized as one logical corpus, not get a second vote.
    cell = output / 'federated-copy'; cell.mkdir()
    original = output / 'database/source.egg'; alias = cell / 'alias.egg'
    subprocess.run(['/bin/cp', '-cpR', str(original), str(alias)], check=True, timeout=30)
    config_file = cell / 'config.toml'; config(config_file, binary, [original, alias])
    env = environment(cell / 'data', config_file, empty_prefix)
    with protected_databases([original, alias]):
        row = deliver(binary, cell, env, 'federated-copy', QUERIES[0][1], QUERIES[0][2])
        if row['markerOccurrences'] != results['database']['deliveries'][0]['markerOccurrences']:
            raise ValueError('A copied DB duplicated the original body')
    results['federated-copy'] = row
    # A model-enabled but numerically cold corpus must still deliver the warm lexical body.
    cell = output / 'private-overlay'; copied = cell / 'source.egg'; config_file = cell / 'config.toml'
    config(config_file, binary, [copied], provider=[binary, 'search-provider'])
    env = environment(cell / 'data', config_file, args.prefix.resolve())
    before = tree(copied)
    with protected_databases([copied]):
        results['numerically-cold'] = deliver(binary, cell, env, 'numerically-cold', QUERIES[0][1],
                                                QUERIES[0][2], semantic='pending')
    if tree(copied) != before:
        raise ValueError('Cold numerical fallback repaired the protected source corpus')
    # The stalled provider is a controlled test process; no model inference is run.
    stall = output / 'stall.py'; pid_file = output / 'stall.pid'
    stall.write_text('import os,pathlib,sys,time\npathlib.Path(sys.argv[1]).write_text(str(os.getpid()))\n'
                     'sys.stdin.readline()\ntime.sleep(60)\n')
    config(config_file, binary, [copied], provider=[sys.executable, stall, pid_file])
    env = environment(cell / 'data', config_file, empty_prefix)
    with protected_databases([copied]):
        results['timeout'] = deliver(binary, cell, env, 'timeout', QUERIES[0][1], QUERIES[0][2], semantic='timedOut')
    if not pid_file.exists():
        raise ValueError('The controlled semantic provider did not start')
    pid = int(pid_file.read_text())
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        pass
    else:
        raise ValueError('The timed-out semantic provider remained alive')
    if tree(copied) != before:
        raise ValueError('A timeout wrote into the source DB')
    cell = output / 'recovery'; cell.mkdir(); copied = cell / 'source.egg'
    subprocess.run(['/bin/cp', '-cpR', str(original), str(copied)], check=True, timeout=30)
    config_file = cell / 'config.toml'; config(config_file, binary, [copied], writable=True)
    env = environment(cell / 'data', config_file, empty_prefix)
    results['independent-recovery'] = recover(binary, helper, cell, env, copied)
    if tree(database) != saved_tree or any(sha(Path(p)) != expected for p, expected in frozen.items()):
        raise ValueError('Native trials changed their common seed or executable')
    save(output / 'result.json', dict(passed=True, results=results, sourceSnapshotUnchanged=True,
                                    generationModelCalls=0, productionAdoption=False))
    print(json.dumps(dict(passed=True, conditions=list(results))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['source', 'build', 'prefix', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        if args.output.is_dir():
            save(args.output / 'failure.json', dict(error=f'{type(error).__name__}: {error}', productionAdoption=False))
        raise


if __name__ == '__main__':
    main()
