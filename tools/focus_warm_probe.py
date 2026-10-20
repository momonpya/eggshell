#!/usr/bin/env python3
"""Check focus warm closure, exact ranking and 12 fixed LLVM native hooks."""
import argparse
import fcntl
import json
from pathlib import Path
import shutil
import subprocess

from context_native_probe import environment, sha, tree
from pilot_memory_probe import protected_databases
from prepare_context_candidate import input_manifest
from prepare_discovery_candidate import sources
from semantic_latency import execute, graph_files, save
from semantic_scale import config, measure, check_subject, inspect_query


def clone(source, target):
    subprocess.run(['/bin/cp', '-cpR', str(source), str(target)], check=True, timeout=300)


def run(args):
    source = Path(__file__).resolve().parents[1]
    build = args.build.resolve(); reference = args.reference.resolve()
    scale = args.scale.resolve(); output = args.output.resolve(); prefix = args.prefix.resolve()
    if any(output.is_relative_to(p) or p.is_relative_to(output) for p in [source, build, reference, scale]):
        raise ValueError('Use a separate native inspection directory')
    qualified = json.loads((build / 'result.json').read_text())
    baseline = json.loads((reference / 'result.json').read_text())
    frozen_build = sources(build / 'checkout'); frozen_reference = sources(reference / 'checkout')
    for root, result in [(build, qualified), (reference, baseline)]:
        if (not result['passed'] or sha(root / 'checkout/.lake/build/bin/eggshell') != result['candidateSha256']
                or sources(root / 'checkout') != json.loads((root / 'manifest.json').read_text())['sources']):
            raise ValueError('An uninstrumented qualified input changed')
    sealed = json.loads((scale / 'manifest.json').read_text())
    fixture = next(row for row in sealed['fixtures'] if row['label'] == 'actual-llvm')
    prepared = scale / 'prepared/actual-llvm/source.egg'
    prepared_files = json.loads((prepared.parent / 'prepared.json').read_text())['files']
    support = prefix / 'share/eggshell/minilm'
    if tree(prepared) != prepared_files or input_manifest(support) != sealed['encoderInputs']:
        raise ValueError('The common warm publication or numerical assets changed')
    check_subject(fixture)
    with (scale / 'run.guard').open('a') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        output.mkdir(parents=True, exist_ok=False, mode=0o700); args.created_output = output
        checkouts = output / 'checkouts'; checkouts.mkdir()
        tools = {}
        empty = output / 'empty.toml'
        empty.write_text('default = "empty"\nsemantic_matcher = false\n[profiles.empty]\nread = []\n')
        for label, root in [('candidate', build), ('reference', reference)]:
            checkout = checkouts / label; clone(root / 'checkout', checkout)
            shutil.copy2(source / 'tools/FocusSnapshot.lean', checkout / 'tools/FocusSnapshot.lean')
            lakefile = checkout / 'lakefile.lean'
            lakefile.write_text(lakefile.read_text() +
                '\nlean_exe focus_snapshot where\n  root := `tools.FocusSnapshot\n')
            env = environment(output / ('build-data-' + label), empty, prefix)
            execute(['lake', '--no-cache', 'build', 'focus_snapshot', 'retrieval_scale'],
                    output / ('build-' + label), env, checkout, timeout=600)
            binary = checkout / '.lake/build/bin/eggshell'
            if sha(binary) != (qualified if label == 'candidate' else baseline)['candidateSha256']:
                raise ValueError('Helper compilation changed a qualified runtime')
            tools[label] = dict(binary=binary, rank=checkout / '.lake/build/bin/focus_snapshot',
                                query=checkout / '.lake/build/bin/retrieval_scale')
        save(output / 'manifest.json', dict(candidateSha256=qualified['candidateSha256'],
            referenceSha256=baseline['candidateSha256'], runnerSha256=sha(Path(__file__)),
            snapshotHelperSha256=sha(source / 'tools/FocusSnapshot.lean'),
            helpers={name: sha(source / 'tools' / name) for name in [
                'semantic_scale.py', 'semantic_latency.py', 'context_native_probe.py',
                'pilot_memory_probe.py', 'owned_daemon.py']}, fixture=fixture,
            sealedScaleManifestSha256=sha(scale / 'manifest.json'),
            qualifiedResultSha256=sha(build / 'result.json'), referenceResultSha256=sha(reference / 'result.json'),
            layouts=['database', 'private-overlay'], questions=fixture['questions'],
            conditions=['fresh', 'cached'], plannedNativeHooks=12, exactFullFocusComparisons=2,
            generationModelCalls=0, productionAdoption=False))
        binary = tools['candidate']['binary']; rows = []; comparisons = []
        identity = fixture['head']['identity']
        for layout in ['database', 'private-overlay']:
            cell = output / layout; cell.mkdir(); database = cell / 'source.egg'; clone(prepared, database)
            if layout == 'private-overlay':
                destination = cell / 'data/read-cache' / identity
                destination.parent.mkdir(parents=True)
                clone(database / 'derived' / identity, destination); shutil.rmtree(database / 'derived')
            cache = (database / 'derived' / identity if layout == 'database'
                     else cell / 'data/read-cache' / identity)
            # Obtain the actual cache path from the existing layout. Avoid a
            # guessed count or any migration of valid original vector bytes.
            matches = list(cache.glob('**/vectors'))
            if len(matches) != 1:
                raise ValueError('Expected exactly one source vector cache')
            vectors = matches[0]; original_vectors = tree(vectors)
            config(cell / 'config.toml', binary, database, writable=layout == 'database')
            env = environment(cell / 'data', cell / 'config.toml', prefix)
            graph_before = graph_files(database)
            def warm():
                raw, timing = execute([binary, 'egg', 'warm', 'source'], cell / 'warm', env, cell, timeout=180)
                return json.loads(raw)['databases'][0], timing
            if layout == 'private-overlay':
                source_before = tree(database)
                with protected_databases([database]):
                    warmed, timing = warm()
                if tree(database) != source_before:
                    raise ValueError('Private warm changed a shared DB byte')
            else:
                warmed, timing = warm()
            before, after = warmed['before'], warmed['after']
            warmed_vectors = tree(vectors)
            if (before['discovery']['valid'] != fixture['uniqueWindows'] or before['focus']['missing'] == 0
                    or before['invalid'] or warmed['requested'] != before['missing']
                    or warmed['batches'] != (warmed['requested'] + 31) // 32
                    or after['valid'] != after['windows'] or after['focus']['valid'] != after['focus']['windows']
                    or after['missing'] or after['invalid']
                    or any(warmed_vectors.get(name) != digest for name, digest in original_vectors.items())):
                raise ValueError('Focus difference did not preserve all valid original input bytes')
            config(cell / 'config.toml', binary, database)
            fixed_tree = tree(database); fixed_vectors = warmed_vectors
            if graph_before != fixture['graphFilesSha256'] or graph_files(database) != graph_before:
                raise ValueError('Warm changed the frozen authoritative graph')
            with protected_databases([database]):
                raw, repeat_timing = execute([binary, 'egg', 'warm', 'source'], cell / 'repeat', env, cell, timeout=180)
                repeat = json.loads(raw)['databases'][0]
                if repeat['requested'] or repeat['batches'] or repeat['lexical']['hydrated'] or repeat['lexical']['added']:
                    raise ValueError('Complete warm repetition did work')
                raw, doctor_timing = execute([binary, 'egg', 'doctor'], cell / 'doctor', env, cell, timeout=180)
                doctor = json.loads(raw)['databases'][0]
                if doctor['state'] != 'warm' or not doctor['lexical']['ready']:
                    raise ValueError('Doctor did not report complete discovery and focus inputs')
                save(cell / 'setup.json', dict(warm=warmed, timing=timing, repeated=repeat,
                    repeatTiming=repeat_timing, doctor=doctor, doctorTiming=doctor_timing,
                    originalVectors=original_vectors, completeVectors=fixed_vectors, sourceTree=fixed_tree))
                for repetition, question in enumerate(fixture['questions']):
                    for condition, expected in [('fresh', False), ('cached', True)]:
                        label = f'q{repetition}-{condition}'
                        ready = inspect_query(tools['candidate']['query'], database, question,
                            cell / (label + '-query'), env, cell)
                        if condition == 'cached' and not ready:
                            execute([binary, 'search-provider'], cell / (label + '-prime'), env, cell,
                                (json.dumps(dict(query=dict(text=question), candidates=[])) + '\n').encode())
                            ready = inspect_query(tools['candidate']['query'], database, question,
                                cell / (label + '-after-prime'), env, cell)
                        if ready != expected:
                            raise ValueError('The actual query-cache precondition is wrong')
                        row = measure(binary, cell, env, fixture, question, label, 'focus-warm-' + layout)
                        focuses = [r for r in row['numerical'] if r.get('corpus', {}).get('purpose') == 'focus']
                        discovery = [r for r in row['numerical'] if r.get('corpus', {}).get('purpose') == 'discovery']
                        closure = bool(focuses and discovery and all(r['status'] == 'completed'
                            and r['counters']['source']['absent'] == 0 and r['counters']['source']['unusable'] == 0
                            and r['counters']['encoder']['sourceEncodeUs'] == 0 for r in focuses + discovery))
                        row = dict(row, layout=layout, repetition=repetition, condition=condition,
                                   completeCacheOnlyFocus=closure)
                        rows.append(row); save(output / 'results.json', rows)
                        print(json.dumps(dict(layout=layout, repetition=repetition, condition=condition,
                            elapsedMs=row['elapsedMs'], gatePassed=row['gatePassed'],
                            body=row['sourceBodyDelivered'], cacheOnlyFocus=closure)), flush=True)
                # Same DB, assets, question and complete warmed inputs. The old
                # repair-enabled and new cache-only functions must return every
                # owner and original window position in precisely the same order.
                signatures = {}
                for label in ['reference', 'candidate']:
                    raw, timing = execute([tools[label]['rank'], database, fixture['questions'][0]],
                        cell / ('full-rank-' + label), env, cell, timeout=60)
                    signatures[label] = json.loads(raw)
                if signatures['reference'] != signatures['candidate']:
                    raise ValueError('Warm closure changed full focus owner/window ordering')
                comparisons.append(dict(layout=layout, fullSignature=signatures['candidate'], exact=True))
                save(output / 'full-rank.json', comparisons)
            if tree(database) != fixed_tree or tree(vectors) != fixed_vectors or graph_files(database) != graph_before:
                raise ValueError('Read-only hooks or rank comparisons changed source/cache bytes')
        check_subject(fixture)
        if (tree(prepared) != prepared_files or sources(build / 'checkout') != frozen_build
                or sources(reference / 'checkout') != frozen_reference
                or input_manifest(support) != sealed['encoderInputs']):
            raise ValueError('A frozen fixture, qualified source or numerical asset changed')
        save(output / 'result.json', dict(inspectionComplete=True, nativeHooks=len(rows),
            observedFiveSecondSemanticPassCount=sum(r['gatePassed'] for r in rows),
            observedCacheOnlyFocusPassCount=sum(r['completeCacheOnlyFocus'] for r in rows),
            observedOriginalBodyPassCount=sum(r['sourceBodyDelivered'] for r in rows),
            exactFullFocusComparisons=comparisons, sourceAndVectorBytesUnchanged=True,
            generationModelCalls=0, productionAdoption=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['build', 'reference', 'scale', 'output', 'prefix']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        if getattr(args, 'created_output', None):
            save(args.created_output / 'failure.json', dict(error=f'{type(error).__name__}: {error}', productionAdoption=False))
        raise


if __name__ == '__main__':
    main()
