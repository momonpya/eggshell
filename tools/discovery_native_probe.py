#!/usr/bin/env python3
"""Retain four representative 10k-window native hooks after discovery qualification."""
import argparse
import fcntl
import json
from pathlib import Path
import shutil
import subprocess

from context_native_probe import environment, sha, tree
from pilot_memory_probe import protected_databases
from prepare_context_candidate import input_manifest
from semantic_latency import execute, graph_files, save
from semantic_scale import config, measure


def run(args):
    build = args.build.resolve(); scale = args.scale.resolve(); output = args.output.resolve()
    source = Path(__file__).resolve().parents[1]
    if any(output.is_relative_to(path) or path.is_relative_to(output) for path in [source, build, scale]):
        raise ValueError('Use a separate native inspection directory')
    qualified = json.loads((build / 'result.json').read_text())
    runtime = build / 'checkout/.lake/build/bin/eggshell'
    if not qualified['passed'] or sha(runtime) != qualified['candidateSha256']:
        raise ValueError('Use a completed uninstrumented qualification')
    sealed = json.loads((scale / 'manifest.json').read_text())
    fixture = next(row for row in sealed['fixtures'] if row['label'] == '10000')
    question = fixture['questions'][0]
    prepared = scale / 'prepared/10000/source.egg'
    prepared_files = json.loads((prepared.parent / 'prepared.json').read_text())['files']
    prefix = args.prefix.resolve(); support = prefix / 'share/eggshell/minilm'
    if tree(prepared) != prepared_files or input_manifest(support) != sealed['encoderInputs']:
        raise ValueError('The common warm publication or numerical inputs changed')
    with (scale / 'run.guard').open('a') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        output.mkdir(parents=True, exist_ok=False, mode=0o700); args.created_output = output
        checkout = output / 'checkout'
        subprocess.run(['/bin/cp', '-cpR', str(build / 'checkout'), str(checkout)], check=True, timeout=300)
        binary = checkout / '.lake/build/bin/eggshell'
        if sha(binary) != qualified['candidateSha256']:
            raise ValueError('The native inspection copy changed the qualified executable')
        config_file = output / 'empty.toml'
        config_file.write_text('default = "empty"\nsemantic_matcher = false\n[profiles.empty]\nread = []\n')
        env = environment(output / 'build-data', config_file, prefix)
        # Compile cache inspection against the candidate's actual encoder
        # contract. This is unmeasured setup and does not relink the runtime.
        execute(['lake', '--no-cache', 'build', 'retrieval_scale'], output / 'helper-build', env, checkout)
        helper = checkout / '.lake/build/bin/retrieval_scale'
        helpers = ['semantic_scale.py', 'semantic_latency.py', 'context_native_probe.py', 'pilot_memory_probe.py', 'owned_daemon.py']
        save(output / 'manifest.json', dict(candidateSha256=sha(binary), inspectorSha256=sha(helper),
            qualifiedResultSha256=sha(build / 'result.json'), sealedScaleManifestSha256=sha(scale / 'manifest.json'),
            runnerSha256=sha(Path(__file__)), helpers={name: sha(source / 'tools' / name) for name in helpers},
            fixture=fixture, question=question, layouts=['database', 'private-overlay'],
            conditions=['fresh', 'cached'], repetitions=1, plannedNativeHooks=4,
            purpose='representative body/publication/ACK check; not the complete fixed scale gate or token comparison',
            generationModelCalls=0, productionAdoption=False))
        rows = []
        for layout in ['database', 'private-overlay']:
            cell = output / layout; cell.mkdir(); database = cell / 'source.egg'
            subprocess.run(['/bin/cp', '-cpR', str(prepared), str(database)], check=True, timeout=300)
            if layout == 'private-overlay':
                destination = cell / 'data/read-cache' / fixture['head']['identity']
                destination.parent.mkdir(parents=True)
                subprocess.run(['/bin/cp', '-cpR', str(database / 'derived' / fixture['head']['identity']),
                                str(destination)], check=True, timeout=300)
                shutil.rmtree(database / 'derived')
            config(cell / 'config.toml', binary, database)
            env = environment(cell / 'data', cell / 'config.toml', prefix)
            before = tree(database)
            if graph_files(database) != fixture['graphFilesSha256']:
                raise ValueError('The native check has a different original source publication')
            with protected_databases([database]):
                raw, timing = execute([binary, 'egg', 'warm', 'source'], cell / 'ready', env, cell, timeout=120)
                warm = json.loads(raw)['databases'][0]
                after = warm['after']
                if (warm['requested'] or warm['batches'] or warm['lexical']['added'] or warm['lexical']['hydrated']
                        or warm['lexical']['removed'] or after['windows'] != fixture['uniqueWindows']
                        or after['valid'] != fixture['uniqueWindows'] or after['missing'] or after['invalid']):
                    raise ValueError('The copied warm publication unexpectedly needed repair')
                raw, doctor_timing = execute([binary, 'egg', 'doctor'], cell / 'doctor', env, cell, timeout=120)
                doctor = json.loads(raw)['databases'][0]
                if doctor['state'] != 'warm' or not doctor['lexical']['ready']:
                    raise ValueError('Doctor did not certify the prepared original-window inputs')
                save(cell / 'setup.json', dict(warm=warm, timing=timing, doctor=doctor,
                    doctorTiming=doctor_timing, sourceFiles=before, expectedSourceWindows=10000))
                for condition, expected in [('fresh', False), ('cached', True)]:
                    raw, _ = execute([helper, 'query', database, question], cell / (condition + '-query'), env, cell)
                    ready = json.loads(raw)['ready']
                    if condition == 'cached' and not ready:
                        payload = (json.dumps(dict(query=dict(text=question), candidates=[])) + '\n').encode()
                        raw, _ = execute([binary, 'search-provider'], cell / 'query-only-setup', env, cell, payload)
                        reply = json.loads(raw)
                        if reply.get('related') != [] or reply.get('ranked') != []:
                            raise ValueError('Empty-candidate query setup nominated source data')
                        raw, _ = execute([helper, 'query', database, question], cell / 'query-after-setup', env, cell)
                        ready = json.loads(raw)['ready']
                    if ready != expected:
                        raise ValueError('The actual fresh/cached query condition is wrong')
                    row = measure(binary, cell, env, fixture, question, condition, 'discovery-check-' + layout)
                    response = json.loads((cell / (condition + '-prompt/stdout')).read_text())
                    trace = (row.get('search') or {}).get('trace', {})
                    notice = {'pending': 'is pending', 'timedOut': 'timed out'}.get(trace.get('semantic'))
                    row = dict(row, layout=layout, unfinishedStatusVisible=(notice is None or
                        'semantic search ' + notice in response.get('systemMessage', '')))
                    rows.append(row); save(output / 'results.json', rows)
                    print(json.dumps(dict(layout=layout, condition=condition, body=row['sourceBodyDelivered'],
                        ack=row['acknowledgementConfirmed'], elapsedMs=row['elapsedMs'],
                        gatePassed=row['gatePassed'], trace=trace)), flush=True)
            if tree(database) != before or graph_files(database) != fixture['graphFilesSha256']:
                raise ValueError('The read-only check changed source/cache data')
        if (sha(binary) != qualified['candidateSha256'] or sha(runtime) != qualified['candidateSha256']
                or tree(prepared) != prepared_files or input_manifest(support) != sealed['encoderInputs']):
            raise ValueError('The candidate, original inputs or prepared publication changed')
        save(output / 'result.json', dict(inspectionComplete=len(rows) == 4, nativeHooks=len(rows), rows=rows,
            observedBodyDeliveryPassCount=sum(bool(row['sourceBodyDelivered'] and row['publicationConfirmed']
                and row['acknowledgementConfirmed'] and row['unfinishedStatusVisible']) for row in rows),
            observedFiveSecondSemanticPassCount=sum(row['gatePassed'] for row in rows),
            generationModelCalls=0, productionAdoption=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['build', 'scale', 'prefix', 'output']:
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        if getattr(args, 'created_output', None) is not None:
            save(args.created_output / 'failure.json', dict(error=f'{type(error).__name__}: {error}', productionAdoption=False))
        raise


if __name__ == '__main__':
    main()
