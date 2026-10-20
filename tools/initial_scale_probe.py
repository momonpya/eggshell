#!/usr/bin/env python3
"""Run the fixed synthetic first/continuation strata on common saved graphs."""
import argparse
import fcntl
import json
from pathlib import Path
import shutil
import subprocess
import time

from context_native_probe import environment, sha, tree
from focus_warm_probe import clone
from initial_budget_probe import sample
from owned_daemon import shutdown_owned
from pilot_memory_probe import protected_databases
from prepare_context_candidate import input_manifest
from prepare_discovery_candidate import sources
from semantic_latency import execute, graph_files, save
from semantic_scale import config


def warm(binary, cell, env, name):
    raw, timing = execute([binary, 'egg', 'warm', 'source'], cell / name, env, cell, timeout=3600)
    return json.loads(raw)['databases'][0], timing


def require_warm(result):
    after = result['after']
    if (after['missing'] or after['invalid'] or after['valid'] != after['windows']
            or after['discovery']['valid'] != after['discovery']['windows']
            or after['focus']['valid'] != after['focus']['windows']):
        raise ValueError('Discovery/focus numerical inputs are not completely warm')


def prepare(binary, output, fixture, original, original_files, prefix, prepared_from=None):
    cell = output / 'prepared' / fixture['label']; cell.mkdir(parents=True)
    database = cell / 'source.egg'
    donor = original
    reused = None
    if prepared_from:
        candidate = prepared_from / 'prepared' / fixture['label']
        if (candidate / 'warm/record.json').exists() and (candidate / 'repeat/record.json').exists():
            declaration = json.loads((prepared_from / 'manifest.json').read_text())
            if declaration['candidateSha256'] != sha(binary):
                raise ValueError('Prepared donor used another runtime')
            attempts = {}
            for phase in ['warm', 'repeat']:
                record = json.loads((candidate / phase / 'record.json').read_text())
                if record['exitCode'] or sha(candidate / phase / 'stdout') != record['stdoutSha256']:
                    raise ValueError('Prepared donor has an incomplete or changed warm result')
                attempts[phase] = dict(result=json.loads((candidate / phase / 'stdout').read_text()), timing=record)
            donor = candidate / 'source.egg'
            reused = dict(directory=str(candidate), attempts=attempts,
                manifestSha256=sha(prepared_from / 'manifest.json'), runnerSha256=sha(prepared_from / 'runner.py'))
    donor_files = tree(donor)
    clone(donor, database)
    if graph_files(database) != fixture['graphFilesSha256']:
        raise ValueError('Source graph changed during preparation copy')
    roots = list(original.glob('derived/**/vectors'))
    original_vectors = {str(path.relative_to(original)): tree(path) for path in roots}
    config(cell / 'config.toml', binary, database, writable=True)
    env = environment(cell / 'data', cell / 'config.toml', prefix)
    initial, initial_timing = warm(binary, cell, env, 'warm')
    require_warm(initial)
    if reused and (initial['requested'] or initial['batches']):
        raise ValueError('Completed donor lost warmed numerical inputs')
    repeated, repeat_timing = warm(binary, cell, env, 'repeat')
    require_warm(repeated)
    if (repeated['requested'] or repeated['batches'] or repeated['lexical']['added']
            or repeated['lexical']['hydrated'] or repeated['lexical']['removed']):
        raise ValueError('Complete preparation repetition performed work')
    preserved = True
    for path, entries in original_vectors.items():
        current = tree(database / path)
        preserved = preserved and all(current.get(key) == digest for key, digest in entries.items())
    if (graph_files(database) != fixture['graphFilesSha256'] or tree(original) != original_files
            or tree(donor) != donor_files or not preserved):
        raise ValueError('Preparation changed an original graph or vector byte')
    prepared = dict(warm=initial, warmTiming=initial_timing, repeated=repeated,
        repeatTiming=repeat_timing, sourceTree=tree(database), originalVectors=original_vectors,
        graphFilesSha256=fixture['graphFilesSha256'], reusedPreparation=reused)
    save(cell / 'prepared.json', prepared)
    return database, prepared


def collect(binary, output, fixture, prepared, prepared_files, prefix):
    rows = []
    for layout in ['database', 'private-overlay']:
        for question_index, question in enumerate(fixture['questions']):
            cell = output / 'cells' / f"{fixture['label']}-{layout}-{question_index}"
            cell.mkdir(parents=True)
            database = cell / 'source.egg'; clone(prepared, database)
            data = cell / 'data'; data.mkdir()
            if tree(database) != prepared_files:
                raise ValueError('A native cell does not have the complete prepared snapshot')
            if layout == 'private-overlay':
                destination = data / 'read-cache' / fixture['head']['identity']
                destination.parent.mkdir(parents=True)
                clone(database / 'derived' / fixture['head']['identity'], destination)
                shutil.rmtree(database / 'derived')
            source_before = tree(database)
            vectors = list(database.glob('derived/**/vectors')) + list(data.glob('read-cache/**/vectors'))
            original_vectors = {str(path): tree(path) for path in vectors}
            config(cell / 'config.toml', binary, database)
            env = environment(data, cell / 'config.toml', prefix)
            with protected_databases([database]):
                destination_warm, timing = warm(binary, cell, env, 'warm')
                require_warm(destination_warm)
                if destination_warm['requested'] or destination_warm['batches']:
                    raise ValueError('A destination lost prepared numerical inputs')
                raw, doctor_timing = execute([binary, 'egg', 'doctor'], cell / 'doctor', env, cell, timeout=600)
                doctor = json.loads(raw)['databases'][0]
            if doctor['state'] != 'warm' or not doctor['lexical']['ready']:
                raise ValueError('Destination doctor did not confirm complete warm state')
            if (tree(database) != source_before
                    or any(tree(Path(path)) != entries for path, entries in original_vectors.items())):
                raise ValueError('Destination preparation changed original source/vector bytes')
            save(cell / 'setup.json', dict(warm=destination_warm, warmTiming=timing,
                doctor=doctor, doctorTiming=doctor_timing, sourceTree=source_before,
                originalVectors=original_vectors))
            protected = [database] + ([data / 'read-cache'] if (data / 'read-cache').exists() else [])
            before = [tree(path) for path in protected]
            session = f"scale-initial-{fixture['label']}-{layout}-{question_index}"
            # The synthetic fixtures have no external working repository.
            active = dict(fixture, workspace=str(cell))
            with protected_databases(protected), (cell / 'daemon.log').open('wb') as log:
                daemon = subprocess.Popen([str(binary), 'codex-daemon', session],
                    env=env, cwd=cell, stdout=log, stderr=subprocess.STDOUT)
                try:
                    expires = time.monotonic() + 5
                    while not (data / 'sessions' / session / 'daemon.json').exists():
                        if daemon.poll() is not None or time.monotonic() > expires:
                            raise RuntimeError('Owned manager failed to publish its endpoint')
                        time.sleep(.005)
                    payload = dict(hook_event_name='SessionStart', session_id=session, turn_id='start',
                        cwd=str(cell), _eggshell_config=str(cell / 'config.toml'))
                    execute([binary, 'codex-hook'], cell / 'start', env, cell,
                        (json.dumps(payload) + '\n').encode(), timeout=35)
                    for turn in ['first', 'continuation']:
                        row = sample(binary, cell, env, active, session, turn, question)
                        trace = (row.get('search') or {}).get('trace', {})
                        notice = {'pending': 'is pending', 'timedOut': 'timed out', 'failed': 'is unavailable'}.get(trace.get('semantic'))
                        stdout = json.loads((cell / turn / 'stdout').read_text())
                        unfinished_visible = bool(notice and 'semantic search ' + notice in stdout.get('systemMessage', ''))
                        fallback = (trace.get('route') == 'lexical' and unfinished_visible
                            and row['sourceBodyDelivered'] and row['publicationConfirmed']
                            and row['acknowledgementConfirmed']
                            and row['elapsedMs'] < (30000 if row['initial'] else 5000))
                        row = dict(row, label=fixture['label'], layout=layout, questionIndex=question_index,
                            unfinishedStatusVisible=unfinished_visible, timelyLexicalBodyDelivered=fallback)
                        rows.append(row)
                        save(output / 'results' / (fixture['label'] + '.json'), rows)
                        print(json.dumps({key: row[key] for key in ['label', 'layout', 'questionIndex', 'turn',
                            'elapsedMs', 'semanticComplete', 'sourceBodyDelivered', 'declaredBudgetPassed',
                            'timelyLexicalBodyDelivered']}), flush=True)
                finally:
                    shutdown_owned(daemon, binary, env, cell, cell / 'shutdown.json')
            if [tree(path) for path in protected] != before:
                raise ValueError('Measured hooks changed source or derived bytes')
    return rows


def run(args):
    source = Path(__file__).resolve().parents[1]
    build = args.build.resolve(); scale = args.scale.resolve(); output = args.output.resolve(); prefix = args.prefix.resolve()
    if any(output.is_relative_to(path) or path.is_relative_to(output) for path in [source, build, scale]):
        raise ValueError('Use a separate observation directory')
    qualified = json.loads((build / 'result.json').read_text())
    frozen = json.loads((build / 'manifest.json').read_text())['sources']
    binary = build / 'checkout/.lake/build/bin/eggshell'
    if not qualified['passed'] or sha(binary) != qualified['candidateSha256'] or sources(build / 'checkout') != frozen:
        raise ValueError('Qualified candidate changed')
    sealed = json.loads((scale / 'manifest.json').read_text())
    fixtures = [next(row for row in sealed['fixtures'] if row['label'] == label) for label in args.labels]
    models = prefix / 'share/eggshell/minilm'
    if input_manifest(models) != sealed['encoderInputs']:
        raise ValueError('Pinned encoder assets changed')
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    shutil.copy2(Path(__file__), output / 'runner.py')
    save(output / 'manifest.json', dict(candidateSha256=qualified['candidateSha256'],
        qualificationManifestSha256=sha(build / 'manifest.json'), scaleManifestSha256=sha(scale / 'manifest.json'),
        runnerSha256=sha(Path(__file__)), helpers={name: sha(source / 'tools' / name) for name in [
            'initial_budget_probe.py', 'semantic_scale.py', 'semantic_latency.py', 'context_native_probe.py',
            'owned_daemon.py', 'pilot_memory_probe.py']}, fixtures=fixtures,
        layouts=['database', 'private-overlay'], questionPairsPerLayout=3, plannedNativeHooks=12 * len(fixtures),
        initialLimitMs=30000, continuationLimitMs=5000, semanticCapsMs=dict(initial=15000, continuation=4500),
        sameSessionContinuation=True, ownedDaemons=True, preparationCostSeparate=True,
        preparedFrom=str(args.prepared_from.resolve()) if args.prepared_from else None,
        generationModelCalls=0, productionAdoption=False))
    all_rows = []
    with (scale / 'run.guard').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for fixture in fixtures:
            original = scale / 'prepared' / fixture['label'] / 'source.egg'
            files = json.loads((original.parent / 'prepared.json').read_text())['files']
            if tree(original) != files or graph_files(original) != fixture['graphFilesSha256']:
                raise ValueError('Original saved warm publication changed')
            prepared, record = prepare(binary, output, fixture, original, files, prefix,
                args.prepared_from.resolve() if args.prepared_from else None)
            all_rows += collect(binary, output, fixture, prepared, record['sourceTree'], prefix)
            if tree(original) != files or tree(prepared) != record['sourceTree']:
                raise ValueError('A common publication changed during measurement')
            save(output / 'completed-strata.json', [label for label in args.labels
                if (output / 'results' / (label + '.json')).exists()
                and len(json.loads((output / 'results' / (label + '.json')).read_text())) == 12])
    if (sources(build / 'checkout') != frozen or sha(binary) != qualified['candidateSha256']
            or input_manifest(models) != sealed['encoderInputs']):
        raise ValueError('Qualified runtime or encoder assets changed')
    save(output / 'result.json', dict(inspectionComplete=True, nativeHooks=len(all_rows),
        observedSemanticPassCount=sum(row['declaredBudgetPassed'] for row in all_rows),
        observedTimelyLexicalBodyCount=sum(row['timelyLexicalBodyDelivered'] for row in all_rows),
        sourceAndOriginalVectorBytesUnchanged=True, generationModelCalls=0, productionAdoption=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['build', 'scale', 'prefix', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--labels', nargs='+', choices=['2', '1024', '10000', '50000'],
        default=['10000', '50000', '2', '1024'])
    parser.add_argument('--prepared-from', type=Path)
    run(parser.parse_args())
