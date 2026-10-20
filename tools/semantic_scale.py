#!/usr/bin/env python3
"""Run the fixed 48 synthetic plus 12 actual-corpus native latency hooks."""
import argparse
import fcntl
import hashlib
import json
from pathlib import Path
import shutil
import statistics
import subprocess

from context_native_probe import environment, sha, tree
from pilot_memory_probe import protected_databases
from prepare_context_candidate import input_manifest
from semantic_latency import execute, graph_files, receipt_for, save, shutdown


COUNTS = [2, 1024, 10000, 50000]
REPETITIONS = list(range(3))


def complete_discovery(row, fixture):
    if row.get('status') != 'completed' or row.get('corpus', {}).get('purpose') != 'discovery':
        return False
    counts = row.get('counters', {}); source = counts.get('source', {})
    inputs = counts.get('sourceInput', {}); encoder = counts.get('encoder') or {}
    references = fixture['windowReferences']; unique = fixture['uniqueWindows']
    return (row['corpus'].get('windowReferences') == references and counts.get('scoredWindows') == references
            and row['corpus'].get('documents') == fixture['documents']
            and row['corpus'].get('durableDocuments') == fixture['documents']
            and inputs.get('windows') == references and inputs.get('vectors', 0) >= references
            and inputs.get('embeddedCharacters') == inputs.get('tokenizerMappedCharacters')
            and inputs.get('embeddedCharacters') is not None
            and unique <= source.get('hit', -1) <= references
            and source.get('absent') == 0 and source.get('unusable') == 0 and encoder.get('sourceEncodeUs') == 0)


def classify(stdout, record, published, ack, search, numerical, fixture):
    try:
        context = json.loads(stdout)['hookSpecificOutput']['additionalContext']
    except (ValueError, KeyError, TypeError):
        context = ''
    trace = (search or {}).get('trace', {})
    publication = bool(published and published.get('output', '').encode() == stdout
        and published.get('sha256') == hashlib.sha256(stdout).hexdigest() and published.get('bytes') == len(stdout)
        and published.get('replyComplete') is True and published.get('flushedMs', 1) <= published.get('deadlineMs', 0))
    accepted = bool(ack and ack.get('offerAccepted') is True and ack.get('rpcCompleted') is True)
    discoveries = [row for row in numerical if row.get('corpus', {}).get('purpose') == 'discovery']
    complete = any(complete_discovery(row, fixture) for row in discoveries)
    semantic = complete and trace.get('semantic') == 'completed' and trace.get('route') == 'configured'
    body = fixture['bodyMarker'] in context
    elapsed = record.get('elapsedMs')
    success = (semantic and body and publication and accepted and record.get('exitCode') == 0
               and elapsed is not None and elapsed < 5000)
    return dict(gatePassed=success, semanticComplete=semantic, discoveryScoringComplete=complete,
        sourceBodyDelivered=body, publicationConfirmed=publication, acknowledgementConfirmed=accepted,
        elapsedMs=elapsed, search=search, numerical=numerical,
        observedSegments=[dict(status=row.get('status'), source=row.get('counters', {}).get('sourceInput'),
            query=row.get('counters', {}).get('queryInput')) for row in discoveries])


def config(path, binary, database, writable=False, lexical=False):
    provider = [str(binary), 'search-provider'] + (['--mode', 'lexical'] if lexical else [])
    path.write_text('default = "probe"\nsemantic_matcher = ' + json.dumps(provider) +
        '\n[eggs]\nsource = ' + json.dumps(str(database)) + '\n[profiles.probe]\nread = ["source"]\n' +
        ('write = "source"\n' if writable else '') + 'handoff_chars = 120000\n')


def clone(source, target):
    if target.exists():
        raise ValueError('Refusing to overwrite an existing fixture copy')
    subprocess.run(['/bin/cp', '-cpR', str(source), str(target)], check=True, timeout=300)


def setup_destination(path):
    if not path.exists():
        return path
    serial = 1
    while path.with_name(path.name + f'-resume-{serial}').exists():
        serial += 1
    return path.with_name(path.name + f'-resume-{serial}')


def inspect_query(helper, database, question, destination, env, cwd):
    raw, _ = execute([helper, 'query', database, question], setup_destination(destination), env, cwd)
    return json.loads(raw)['ready']


def native_hook(binary, cell, env, fixture, event, session, destination, question=None):
    value = dict(hook_event_name=event, session_id=session, turn_id='first-turn',
                 cwd=fixture.get('workspace', str(cell)), _eggshell_config=str(cell / 'config.toml'))
    if question is not None:
        value['prompt'] = question
    return execute([binary, 'codex-hook'], destination, env, cell,
                   (json.dumps(value, ensure_ascii=False) + '\n').encode(), timeout=35)


def read_sample(cell, session, condition, fixture):
    directory = cell / (condition + '-prompt')
    stdout = (directory / 'stdout').read_bytes() if (directory / 'stdout').exists() else b''
    record = json.loads((directory / 'record.json').read_text()) if (directory / 'record.json').exists() else {}
    try:
        receipt = receipt_for(cell / 'data', session)
    except (FileNotFoundError, RuntimeError):
        receipt = None
    def stage(name):
        path = receipt / (name + '.json') if receipt else None
        return json.loads(path.read_text())['data'] if path and path.exists() else None
    numerical = [json.loads(path.read_text())['data'] for path in sorted(receipt.glob('numerical-*.json'))] if receipt else []
    result = classify(stdout, record, stage('published'), stage('ack'), stage('search'), numerical, fixture)
    return dict(result, receipt=receipt.name if receipt else None, stdoutSha256=hashlib.sha256(stdout).hexdigest(),
                actualStdoutRetained=(directory / 'stdout').exists())


def measure(binary, cell, env, fixture, question, condition, label):
    session = 'scale-' + label + '-' + condition
    result_path = cell / (condition + '-result.json')
    if result_path.exists():
        return json.loads(result_path.read_text())
    prompt = cell / (condition + '-prompt')
    # A retained prompt directory may have run before an interrupted observer.
    # Recover its actual stdout/receipt, never submit that measured hook again.
    if not prompt.exists():
        if not (cell / (condition + '-start')).exists():
            native_hook(binary, cell, env, fixture, 'SessionStart', session, cell / (condition + '-start'))
        failure = None
        try:
            native_hook(binary, cell, env, fixture, 'UserPromptSubmit', session, prompt, question)
        except Exception as error:
            failure = f'{type(error).__name__}: {error}'
        finally:
            shutdown(binary, cell, env, condition + '-shutdown')
    else:
        failure = 'recovered existing measured attempt; no resubmission'
        if list((cell / 'data/sessions').glob('*/daemon.json')):
            shutdown(binary, cell, env, condition + '-recovery-shutdown')
    row = dict(read_sample(cell, session, condition, fixture), condition=condition, question=question,
               observerError=failure, fixture=fixture['label'], originalWindows=fixture['windowReferences'],
               uniqueWindows=fixture['uniqueWindows'], owners=fixture['documents'])
    save(result_path, row)
    return row


def load_fixtures(root, actual):
    completed = json.loads((root / 'result.json').read_text())
    if not completed['passed'] or len(completed['fixtures']) != len(COUNTS):
        raise ValueError('All four source preparations must finish before serial warming and measurement')
    fixtures = []
    for count in COUNTS:
        saved = json.loads((root / 'seeds' / str(count) / 'saved-snapshot.json').read_text())
        value = saved['fixture']; database = Path(value['database'])
        if value['requestedWindows'] != count or graph_files(database) != saved['graphFilesSha256']:
            raise ValueError('A common source publication changed')
        fixtures.append(dict(value, label=str(count), graphFilesSha256=saved['graphFilesSha256'],
            bodyMarker='ORIGINAL_CLOCK_BODY_', questions=[
                f'Find kernel realtime clock observations for monotonic scheduling and elapsed timers, question {n}.'
                for n in [1, 2, 3]]))
    observed = json.loads((actual / 'result.json').read_text())
    if not observed['passed'] or not observed['fixture']['allValuesAndReferencesPreserved']:
        raise ValueError('The actual corpus must be imported without filtering or changing references')
    value = observed['fixture']
    if graph_files(Path(value['database'])) != value['graphFilesSha256']:
        raise ValueError('The actual observation corpus changed')
    fixtures.append(value)
    return fixtures


def check_subject(fixture):
    if 'workspace' not in fixture:
        return
    workspace = fixture['workspace']
    commit = subprocess.check_output(['git', '-C', workspace, 'rev-parse', 'HEAD'], text=True).strip()
    status = subprocess.check_output(['git', '-C', workspace, 'status', '--porcelain'], text=True)
    if commit != fixture['subjectCommit'] or status:
        raise ValueError('The real source workspace changed from its frozen clean commit')


def prepare(binary, phase_helper, output, fixture, prefix):
    cell = output / 'prepared' / fixture['label']; database = cell / 'source.egg'
    result_path = cell / 'prepared.json'
    if result_path.exists():
        value = json.loads(result_path.read_text())
        if tree(database) != value['files']:
            raise ValueError('Prepared source or numerical records changed')
        return database, value
    cell.mkdir(parents=True, exist_ok=True)
    if not database.exists():
        clone(Path(fixture['database']), database)
    if graph_files(database) != fixture['graphFilesSha256']:
        raise ValueError('Preparation copy changed a source publication')
    env = environment(cell / 'data', cell / 'config.toml', prefix)
    records = {}
    for label, lexical in [('lexical', True), ('numerical', False), ('repeated', False)]:
        config(cell / 'config.toml', binary, database, writable=True, lexical=lexical)
        destination = cell / (label + '-warm')
        if destination.exists():
            # Warming is unmeasured maintenance; preserve interrupted attempts
            # and resume the missing-window difference in a new recorded call.
            serial = len(list(cell.glob(label + '-warm*')))
            destination = cell / (label + f'-warm-resume-{serial}')
        raw, timing = execute([binary, 'egg', 'warm', 'source'], destination, env, cell, timeout=7200)
        records[label] = dict(result=json.loads(raw)['databases'][0], timing=timing)
    repeated = records['repeated']['result']; after = repeated['after']
    if (repeated['requested'] or repeated['batches'] or repeated['lexical']['added'] or repeated['lexical']['hydrated']
            or after['valid'] != fixture['uniqueWindows'] or after['missing'] or after['invalid']):
        raise ValueError('Complete lexical/numerical warm or its no-work repetition failed')
    raw, doctor_timing = execute([binary, 'egg', 'doctor'], setup_destination(cell / 'doctor'), env, cell)
    doctor = json.loads(raw)['databases'][0]
    if doctor['state'] != 'warm' or not doctor['lexical']['ready']:
        raise ValueError('Doctor did not certify both prepared indexes')
    try:
        cost, timing = execute([phase_helper, 'cache-cost', database], setup_destination(cell / 'cache-cost'), env, cell, timeout=600)
        cost = dict(result=json.loads(cost), timing=timing)
    except Exception as error:
        cost = dict(unavailable=f'{type(error).__name__}: {error}')
    if graph_files(database) != fixture['graphFilesSha256']:
        raise ValueError('Explicit warming changed the authoritative graph')
    result = dict(warm=records, doctor=doctor, doctorTiming=doctor_timing, cacheCost=cost, files=tree(database))
    save(result_path, result)
    return database, result


def collect(binary, helper, phase_helper, output, fixture, prepared, prefix):
    rows = []
    identity = fixture['head']['identity']
    for layout in ['database', 'private-overlay']:
        for repetition in REPETITIONS:
            label = fixture['label'] + '-' + layout + '-' + str(repetition)
            cell = output / 'cells' / label; database = cell / 'source.egg'
            cell.mkdir(parents=True, exist_ok=True)
            env = environment(cell / 'data', cell / 'config.toml', prefix)
            if not (cell / 'setup.json').exists():
                if database.exists():
                    raise ValueError('Interrupted copy/setup requires inspection before collecting a cell')
                clone(prepared, database)
                if layout == 'private-overlay':
                    destination = cell / 'data/read-cache' / identity; destination.parent.mkdir(parents=True)
                    clone(database / 'derived' / identity, destination)
                    shutil.rmtree(database / 'derived')
                config(cell / 'config.toml', binary, database)
                before = tree(database)
                with protected_databases([database]):
                    raw, timing = execute([binary, 'egg', 'warm', 'source'], cell / 'private-ready', env, cell, timeout=7200)
                    warmed = json.loads(raw)['databases'][0]
                    if warmed['requested'] or warmed['lexical']['hydrated'] or warmed['lexical']['added']:
                        raise ValueError('Copied complete indexes unexpectedly needed repair')
                if tree(database) != before or graph_files(database) != fixture['graphFilesSha256']:
                    raise ValueError('Read-only private setup changed a DB byte')
                save(cell / 'setup.json', dict(files=before, warm=warmed, timing=timing))
            setup = json.loads((cell / 'setup.json').read_text())
            if tree(database) != setup['files']:
                raise ValueError('The source/cache tree changed between native cells')
            question = fixture['questions'][repetition]
            with protected_databases([database]):
                for condition, expected in [('fresh', False), ('cached', True)]:
                    if (cell / (condition + '-result.json')).exists():
                        row = json.loads((cell / (condition + '-result.json')).read_text())
                    else:
                        if not (cell / (condition + '-prompt')).exists():
                            destination = cell / (condition + '-query-precondition')
                            ready = inspect_query(helper, database, question, destination, env, cell)
                            if condition == 'cached' and not ready:
                                execute([phase_helper, 'prime', database, question], setup_destination(cell / 'unmeasured-prime'), env, cell, timeout=600)
                                ready = inspect_query(helper, database, question, cell / 'after-prime', env, cell)
                            if ready != expected:
                                raise ValueError('The actual query-cache precondition is not satisfied')
                        row = measure(binary, cell, env, fixture, question, condition, label)
                    row = dict(row, layout=layout, repetition=repetition)
                    rows.append(row)
            if tree(database) != setup['files'] or graph_files(database) != fixture['graphFilesSha256']:
                raise ValueError('Native read-only delivery changed a DB/cache byte')
            print(json.dumps(dict(fixture=fixture['label'], layout=layout, repetition=repetition,
                attempts=[dict(condition=row['condition'], gate=row['gatePassed'], elapsedMs=row['elapsedMs'])
                          for row in rows[-2:]])), flush=True)
    return rows


def summarize(rows, fixtures):
    cells = []
    for fixture in fixtures:
        for layout in ['database', 'private-overlay']:
            for condition in ['fresh', 'cached']:
                values = [row for row in rows if row['fixture'] == fixture['label']
                          and row['layout'] == layout and row['condition'] == condition]
                elapsed = [row['elapsedMs'] for row in values]
                cells.append(dict(fixture=fixture['label'], originalWindows=fixture['windowReferences'],
                    owners=fixture['documents'], layout=layout, questionCache=condition, n=len(values),
                    passed=sum(row['gatePassed'] for row in values), elapsedMs=elapsed,
                    medianMs=statistics.median(elapsed) if elapsed and all(x is not None for x in elapsed) else None))
    return dict(plannedHooks=len(fixtures) * 12, recordedAttempts=len(rows), cells=cells,
        observedGatePassed=len(rows) == len(fixtures) * 12 and all(row['gatePassed'] for row in rows),
        generationModelCalls=0, productionAdoption=False)


def run(args):
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=args.resume, mode=0o700)
    build = args.build.resolve(); checkout = build / 'checkout'; prefix = args.prefix.resolve()
    binary = checkout / '.lake/build/bin/eggshell'; helper = binary.with_name('retrieval_scale')
    phase_helper = binary.with_name('semantic_latency')
    qualified = json.loads((build / 'result.json').read_text()); inputs = json.loads((build / 'encoder-inputs.json').read_text())
    if not qualified['passed'] or sha(binary) != qualified['candidateSha256']:
        raise ValueError('The combined runtime is not the qualified executable')
    support = prefix / 'share/eggshell/minilm'
    if input_manifest(support) != inputs:
        raise ValueError('The pinned numerical assets differ from the qualified runtime')
    fixtures = load_fixtures(args.fixtures.resolve(), args.actual.resolve())
    protocol = Path(__file__).resolve().parents[1] / 'docs/semantic-scale-protocol.md'
    declaration = dict(executables={str(path): sha(path) for path in [binary, helper, phase_helper]},
        helpers={name: sha(Path(__file__).with_name(name)) for name in
            ['semantic_scale.py', 'semantic_latency.py', 'context_native_probe.py', 'pilot_memory_probe.py', 'owned_daemon.py']},
        fixtures=fixtures, protocolSha256=sha(protocol), encoderInputs=inputs, semanticCapMs=4500,
        plannedHooks=60, repetitions=REPETITIONS, generationModelCalls=0, productionAdoption=False)
    if args.resume:
        if json.loads((output / 'manifest.json').read_text()) != declaration:
            raise ValueError('Resume requires identical sources, runtime, helpers, protocol and cells')
    else:
        save(output / 'manifest.json', declaration); shutil.copy2(protocol, output / 'protocol.md')
        shutil.copy2(Path(__file__), output / 'runner.py')
    with (output / 'run.guard').open('a') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        rows = []
        for fixture in fixtures:
            check_subject(fixture)
            database, _ = prepare(binary, phase_helper, output, fixture, prefix)
            rows.extend(collect(binary, helper, phase_helper, output, fixture, database, prefix))
            check_subject(fixture)
            save(output / 'results.json', rows); save(output / 'summary.json', summarize(rows, fixtures))
        if input_manifest(support) != inputs or any(sha(Path(path)) != value for path, value in declaration['executables'].items()):
            raise ValueError('The runtime or pinned numerical assets changed during measurement')
        result = summarize(rows, fixtures); save(output / 'summary.json', result)
        print(json.dumps(dict(recordedAttempts=result['recordedAttempts'], observedGatePassed=result['observedGatePassed'])), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['build', 'fixtures', 'actual', 'prefix', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        if args.output.is_dir():
            save(args.output / 'failure.json', dict(error=f'{type(error).__name__}: {error}', productionAdoption=False))
        raise


if __name__ == '__main__':
    main()
