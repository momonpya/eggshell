#!/usr/bin/env python3
"""Locate current warm first/history costs; require exact complete Handoffs."""
import argparse
import fcntl
import json
from pathlib import Path
import shutil
import subprocess

from context_candidate import once
from context_native_probe import environment, sha, tree
from pilot_memory_probe import protected_databases
from prepare_context_candidate import input_manifest
from prepare_discovery_candidate import sources
from profile_discovery_scale import instrument as instrument_work
from semantic_latency import execute, save
from semantic_scale import config


PREPARATION = '''/-- Diagnostic only. Each thunk is forced between the clock samples. -/
@[noinline] def preparationProfileIO (label : String) (action : Unit → IO α) : IO α := do
  let started ← IO.monoNanosNow
  let result ← action ()
  let elapsed := (← IO.monoNanosNow) - started
  if let some path ← IO.getEnv "EGGSHELL_PREPARATION_TRACE" then
    IO.FS.withFile path .append fun handle =>
      handle.putStrLn (Json.mkObj [("label", toJson label),
        ("startedNs", toJson started), ("elapsedNs", toJson elapsed)]).compress
  pure result

'''


def instrument(source):
    # Preserve the existing measured Work/admission stages and add only the
    # preparation boundaries absent from the former discovery trace.
    source = instrument_work(source)
    declaration = source.index('def indexedSemanticNominationsUsing (snapshot')
    comment = source.rfind('/--', 0, declaration)
    comment_end = source.index('-/', comment) + 2
    if source[comment_end:declaration].strip():
        raise ValueError('The preparation diagnostic declaration boundary changed')
    source = source[:comment] + PREPARATION + source[comment:]
    start = source.index('def headerSemanticNominations (')
    end = source.index('\ndef indexedSemanticOwners (', start)
    body = source[start:end]
    body = once(body, '  let documents ← Persistence.Store.searchDocuments snapshot',
        '  let documents ← preparationProfileIO "prepare.searchDocuments" fun _ => Persistence.Store.searchDocuments snapshot')
    body = once(body, '  let childIds ← savedSemanticChildren snapshot workIds',
        '  let childIds ← preparationProfileIO "prepare.savedChildren" fun _ => savedSemanticChildren snapshot workIds')
    source = source[:start] + body + source[end:]
    start = source.index('def indexedSemanticNominationsUsing (snapshot')
    end = source.index('\ndef semanticChildIds (', start)
    body = source[start:end]
    body = once(body, '  let lexicalPosting ← RetrievalResearch.Index.strictLookup snapshot',
        '  let lexicalPosting ← preparationProfileIO "prepare.lexicalIndex" fun _ => RetrievalResearch.Index.strictLookup snapshot')
    body = once(body, '  let some indices ← SemanticMatcher.nominateIndexed command current requestDocuments lexical anchors readWindow false receipt |',
        '  let some indices ← preparationProfileIO "prepare.nominateIndexed" (fun _ => SemanticMatcher.nominateIndexed command current requestDocuments lexical anchors readWindow false receipt) |')
    projection = body.index('  let mut found : IndexedSemanticNominations := {}') \
        if '  let mut found : IndexedSemanticNominations := {}' in body else body.index('  let owner :')
    body = body[:projection] + '  preparationProfileIO "prepare.projectOwners" fun _ => do\n' + \
        '\n'.join('  ' + line for line in body[projection:].rstrip().splitlines()) + '\n'
    source = source[:start] + body.rstrip() + '\n' + source[end:]
    return source


def run(args):
    root = Path(__file__).resolve().parents[1]
    build = args.build.resolve(); native = args.native.resolve(); scale = args.scale.resolve()
    output = args.output.resolve(); prefix = args.prefix.resolve()
    if any(output.is_relative_to(p) or p.is_relative_to(output) for p in [root, build, native, scale]):
        raise ValueError('Use a separate diagnostic directory')
    qualified = json.loads((build / 'result.json').read_text())
    manifest = json.loads((build / 'manifest.json').read_text())
    measured = json.loads((native / 'result.json').read_text())
    cohort = json.loads((native / 'manifest.json').read_text())
    previous_manifest = json.loads((args.reference.resolve() / 'manifest.json').read_text()) if args.reference else None
    direct_candidate = bool(previous_manifest and
        manifest.get('baseResultSha256') == previous_manifest['qualificationResultSha256'] and
        previous_manifest['qualifiedRuntime'] == cohort['candidateSha256'])
    binary = build / 'checkout/.lake/build/bin/eggshell'
    if (not qualified['passed'] or sha(binary) != qualified['candidateSha256']
            or sources(build / 'checkout') != manifest['sources']
            or (cohort['candidateSha256'] != qualified['candidateSha256'] and not direct_candidate)
            or not measured['inspectionComplete'] or not measured['sourceAndOriginalVectorBytesUnchanged']):
        raise ValueError('Use the current completed qualified native cohort')
    fixture = next(x for x in cohort['fixtures'] if x['label'] == '10000')
    cell = native / 'cells/10000-database-0'; database = cell / 'source.egg'
    frozen_database = json.loads((cell / 'setup.json').read_text())['sourceTree']
    if tree(database) != frozen_database:
        raise ValueError('The fixed source/cache bytes changed')
    rows = json.loads((native / 'results/10000.json').read_text())
    first = next(x for x in rows if x['layout'] == 'database' and x['questionIndex'] == 0 and x['initial'])
    state = json.loads((cell / 'data/sessions' / first['session'] / 'state.json').read_text())
    if len(state['deliveredGraphs']) != first['retainedDeliveryKeysAfter'] or state['offers']:
        raise ValueError('Use the retained ACKed history without temporary offers')
    encoder = input_manifest(prefix / 'share/eggshell/minilm')
    if encoder != json.loads((scale / 'manifest.json').read_text())['encoderInputs']:
        raise ValueError('The original encoder inputs changed')
    ordinary = root / '.lake/build/bin/eggshell'; ordinary_hash = sha(ordinary)
    provider = Path(json.loads((args.reference.resolve() / 'semantic-first.json').read_text())['provider']) \
        if direct_candidate else binary
    if sha(provider) != cohort['candidateSha256']:
        raise ValueError('The fixed numerical provider executable changed')
    with (scale / 'run.guard').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        output.mkdir(parents=True, exist_ok=False, mode=0o700); args.created_output = output
        cases = []
        for name, lexical, delivered in [('semantic-first', False, []),
                ('semantic-history', False, state['deliveredGraphs']),
                ('lexical-history', True, state['deliveredGraphs'])]:
            request = dict(database=str(database), provider=str(provider), workspace=str(cell),
                question=first['question'], receipt=first['receipt'], delivered=delivered, lexical=lexical)
            path = output / (name + '.json'); save(path, request)
            cases.append((name, path))
        save(output / 'manifest.json', dict(qualifiedRuntime=qualified['candidateSha256'],
            qualificationResultSha256=sha(build / 'result.json'), nativeResultSha256=sha(native / 'result.json'),
            runnerSha256=sha(Path(__file__)), workInstrumentationSha256=sha(root / 'tools/profile_discovery_scale.py'),
            helperSourceSha256=sha(root / 'tools/DiscoveryStages.lean'), database=str(database),
            sourceTree=frozen_database, requests={name:sha(path) for name,path in cases}, encoderInputs=encoder,
            ordinaryRuntimeSha256=ordinary_hash, newNativeHooks=0, generationModelCalls=0,
            purpose='complete staged diagnosis; no native-hook or adoption comparison', productionAdoption=False))
        results = {}
        if args.reference:
            previous = args.reference.resolve()
            baseline = json.loads((previous / 'manifest.json').read_text())
            current = json.loads((output / 'manifest.json').read_text())
            if baseline['qualifiedRuntime'] != qualified['candidateSha256'] and not direct_candidate:
                raise ValueError('Only a direct qualified candidate may replace the reference implementation')
            for key in ['nativeResultSha256', 'helperSourceSha256',
                    'database', 'sourceTree', 'requests', 'encoderInputs']:
                if baseline[key] != current[key]:
                    raise ValueError('The frozen reference differs at ' + key)
            reference = json.loads((previous / 'partial-results.json').read_text())['reference']
            if set(reference) != {name for name, _ in cases} or sources(previous / 'reference/checkout') != json.loads((previous / 'reference/sources.json').read_text()):
                raise ValueError('Use three complete unchanged reference calls')
            for name, value in reference.items():
                record = json.loads((previous / 'reference' / name / 'record.json').read_text())
                stdout = previous / 'reference' / name / 'stdout'
                if record.get('exitCode') != 0 or sha(stdout) != record['stdoutSha256'] or json.loads(stdout.read_text())['handoff'] != value['handoff']:
                    raise ValueError('The original reference output changed')
            current['referencePartialSha256'] = sha(previous / 'partial-results.json')
            current['referenceManifestSha256'] = sha(previous / 'manifest.json')
            save(output / 'manifest.json', current)
            results['reference'] = reference
        for mode in (['instrumented'] if args.reference else ['reference', 'instrumented']):
            folder = output / mode; folder.mkdir()
            checkout = folder / 'checkout'
            subprocess.run(['/bin/cp', '-cpR', str(build / 'checkout'), str(checkout)], check=True, timeout=300)
            if mode == 'instrumented':
                path = checkout / 'Eggshell/Handoff.lean'; path.write_text(instrument(path.read_text()))
            shutil.copy2(root / 'tools/DiscoveryStages.lean', checkout / 'tools/DiscoveryStages.lean')
            lake = checkout / 'lakefile.lean'; lake.write_text(lake.read_text() +
                '\nlean_exe discovery_stages where\n  root := `tools.DiscoveryStages\n')
            frozen = sources(checkout); save(folder / 'sources.json', frozen)
            cfg = folder / 'config.toml'; config(cfg, binary, database)
            env = environment(folder / 'data', cfg, prefix)
            execute(['lake', '--no-cache', 'build', 'discovery_stages'], folder / 'build', env, checkout, timeout=600)
            if sha(checkout / '.lake/build/bin/eggshell') != qualified['candidateSha256']:
                raise ValueError('Helper compilation changed the frozen runtime')
            save(folder / 'helper.json', dict(sha256=sha(checkout / '.lake/build/bin/discovery_stages')))
            results[mode] = {}
            with protected_databases([database]):
                raw, _ = execute([binary, 'egg', 'warm', 'source'], folder / 'ready', env, cell, timeout=180)
                ready = json.loads(raw)['databases'][0]
                if ready['requested'] or ready['batches'] or ready['after']['missing'] or ready['after']['invalid']:
                    raise ValueError('Diagnostic inputs lost the complete warm precondition')
                execute([binary, 'search-provider'], folder / 'query-setup', env, cell,
                    (json.dumps(dict(query=dict(text=first['question']), candidates=[])) + '\n').encode())
                for name, request in cases:
                    trace = folder / (name + '-trace.log'); prep = folder / (name + '-preparation.jsonl')
                    raw, timing = execute([checkout / '.lake/build/bin/discovery_stages', request],
                        folder / name, dict(env, EGGSHELL_HANDOFF_TRACE=str(trace),
                            EGGSHELL_PREPARATION_TRACE=str(prep)), cell, timeout=180)
                    result = json.loads(raw)
                    handoff = result['handoff']
                    if handoff is not None and handoff['reason'] == 'search-incomplete':
                        raise ValueError('A staged diagnosis did not finish')
                    if name == 'semantic-first' and (not handoff or fixture['bodyMarker'] not in handoff['text']):
                        raise ValueError('The original required body is missing')
                    if mode == 'instrumented' and handoff != results['reference'][name]['handoff']:
                        raise ValueError('Instrumentation changed the entire Handoff')
                    stages = [json.loads(line.split('ms profile ', 1)[1]) for line in trace.read_text().splitlines()
                        if 'ms profile ' in line]
                    preparations = [json.loads(line) for line in prep.read_text().splitlines()] if prep.exists() else []
                    results[mode][name] = dict(internalMs=result['elapsedMs'], process=timing,
                        handoff=handoff, work=stages, preparation=preparations)
                    save(output / 'partial-results.json', results)
                    print(json.dumps(dict(mode=mode,case=name,internalMs=result['elapsedMs'])), flush=True)
            if sources(checkout) != frozen or tree(database) != frozen_database:
                raise ValueError('Diagnostic compilation or reads changed frozen inputs')
        if (sources(build / 'checkout') != manifest['sources'] or sha(binary) != qualified['candidateSha256']
                or sha(ordinary) != ordinary_hash or input_manifest(prefix / 'share/eggshell/minilm') != encoder):
            raise ValueError('A diagnostic changed a qualified runtime or encoder')
        save(output / 'result.json', dict(passed=True,exactCompleteHandoffs=True,results=results,
            sourceAndCacheBytesUnchanged=True,newNativeHooks=0,generationModelCalls=0,productionAdoption=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['build','native','scale','prefix','output']:
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--reference',type=Path,
        help='Reuse three unchanged complete reference calls, with all fixed inputs checked')
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        if getattr(args,'created_output',None):
            save(args.created_output/'failure.json',dict(error=f'{type(error).__name__}: {error}',productionAdoption=False))
        raise


if __name__ == '__main__':
    main()
