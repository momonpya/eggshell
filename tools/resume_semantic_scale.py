#!/usr/bin/env python3
"""Resume a sealed scale run after full-corpus query priming failed."""
import argparse
import ast
import fcntl
import json
from pathlib import Path

from context_native_probe import environment, sha, tree
from pilot_memory_probe import protected_databases
from semantic_latency import execute, save


def retained_samples(scale):
    paths = set((scale / 'cells').glob('*/*-result.json'))
    paths.update((scale / 'cells').glob('*/*-prompt/*'))
    paths.update((scale / 'cells').glob('*/data/receipts/*/*.json'))
    return {str(path): sha(path) for path in paths if path.is_file()}


def run(args):
    scale = args.scale.resolve(); output = args.output.resolve()
    source = Path(__file__).resolve().parents[1]
    if any(output.is_relative_to(path) or path.is_relative_to(output) for path in [source, scale]):
        raise ValueError('Use a separate recovery record directory')
    manifest = json.loads((scale / 'manifest.json').read_text())
    executable = next(Path(path) for path in manifest['executables'] if Path(path).name == 'eggshell')
    helper = executable.with_name('retrieval_scale'); phase_helper = executable.with_name('semantic_latency')
    build = executable.parents[4]
    saved_fixtures = Path(manifest['fixtures'][0]['database']).parents[2]
    actual = Path(manifest['fixtures'][-1]['database']).parent
    cells = {fixture['label'] + '-' + layout + '-' + str(repetition): (fixture, fixture['questions'][repetition])
        for fixture in manifest['fixtures'] for layout in ['database', 'private-overlay'] for repetition in range(3)}
    command = ['python3', '-B', str(source / 'tools/semantic_scale.py'), '--build', str(build),
        '--fixtures', str(saved_fixtures), '--actual', str(actual), '--prefix', str(args.prefix.resolve()),
        '--output', str(scale), '--resume']
    output.mkdir(parents=True, exist_ok=False, mode=0o700); args.created_output = output
    save(output / 'manifest.json', dict(scaleManifestSha256=sha(scale / 'manifest.json'),
        recoverySha256=sha(Path(__file__)), resumedCommand=command,
        repeatsExistingMeasuredAttempts=False, resumesRemainingMeasuredAttempts=True,
        generationModelCalls=0, productionAdoption=False))
    recovered = []
    for step in range(len(cells)):
        step_root = output / str(step); step_root.mkdir()
        # The lock, rather than a failure file, proves no original runner is live.
        with (scale / 'run.guard').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if any(sha(Path(path)) != digest for path, digest in manifest['executables'].items()) or any(
                    sha(source / 'tools' / name) != digest for name, digest in manifest['helpers'].items()):
                raise ValueError('Recovery must use the identical sealed executables and measurement helpers')
            failure = json.loads((scale / 'failure.json').read_text())
            save(step_root / 'retained-failure.json', failure)
            prefix = 'RuntimeError: '
            if not failure['error'].startswith(prefix):
                raise ValueError('This recovery handles only failed unmeasured full-corpus query priming')
            details = ast.literal_eval(failure['error'][len(prefix):])
            invocation = details.get('args', [])
            if (len(invocation) != 4 or invocation[:2] != [str(phase_helper), 'prime']
                    or details.get('exitCode') != 1
                    or 'standalone query priming did not complete' not in details.get('stderr', '')):
                raise ValueError('The retained failure is outside the query-setup boundary')
            database = Path(invocation[2]); cell = database.parent
            if cell.parent != scale / 'cells' or database.name != 'source.egg' or cell.name not in cells:
                raise ValueError('The failed priming call names a foreign cell')
            fixture, question = cells[cell.name]
            if question != invocation[3] or cell.name in recovered or (cell / 'cached-prompt').exists():
                raise ValueError('Refusing to revisit a recovered or already-measured cached attempt')
            fresh = json.loads((cell / 'fresh-result.json').read_text())
            if fresh['question'] != question or fresh['fixture'] != fixture['label']:
                raise ValueError('The original fresh attempt is not retained for this cell')
            before_samples = retained_samples(scale); before = tree(database)
            env = environment(cell / 'data', cell / 'config.toml', args.prefix.resolve())
            with protected_databases([database]):
                raw, _ = execute([helper, 'query', database, question], step_root / 'query-before', env, cell)
                readiness = json.loads(raw)
                if not readiness['ready']:
                    # The ordinary native provider's empty-candidate lane embeds
                    # exactly the question in its existing private query cache.
                    # It receives no DB owner, source windows or corpus to search.
                    payload = (json.dumps(dict(query=dict(text=question), candidates=[])) + '\n').encode()
                    raw, _ = execute([executable, 'search-provider'], step_root / 'query-only-prime', env,
                                     cell, payload, timeout=120)
                    reply = json.loads(raw)
                    if reply.get('related') != [] or reply.get('ranked') != []:
                        raise ValueError('An empty-candidate setup unexpectedly returned a nomination')
                raw, _ = execute([helper, 'query', database, question], step_root / 'query-after', env, cell)
                if not json.loads(raw)['ready'] or tree(database) != before:
                    raise ValueError('Query-only setup failed or wrote to the protected source/cache tree')
            save(step_root / 'setup.json', dict(cell=cell.name, question=question,
                originalFreshResultSha256=sha(cell / 'fresh-result.json'),
                retainedSampleHashes=before_samples, databaseUnchanged=True,
                generationModelCalls=0, measuredHookSubmitted=False))
        # Keep the frozen runner and its resume contract untouched. Existing
        # measured prompt/result files are recovered, never submitted again.
        terminal = True
        try:
            execute(command, step_root / 'resume', env, source, timeout=7200)
        except RuntimeError:
            terminal = False
        if any(not Path(path).is_file() or sha(Path(path)) != digest for path, digest in before_samples.items()):
            raise ValueError('Resuming altered an existing measured stream, result or receipt')
        recovered.append(cell.name)
        save(output / 'recoveries.json', recovered)
        print(json.dumps(dict(recoveredCell=cell.name, originalSamplesUnchanged=True, runnerExitZero=terminal)), flush=True)
        if terminal:
            final = json.loads((scale / 'summary.json').read_text())
            if final['recordedAttempts'] != 60:
                raise ValueError('The resumed collection did not retain all fixed attempts')
            save(output / 'result.json', dict(passed=True, recoveredCells=recovered,
                summarySha256=sha(scale / 'summary.json'), summary=final,
                originalSamplesUnchanged=True, generationModelCalls=0, productionAdoption=False))
            return
    raise ValueError('Recovery exceeded the predetermined cached-cell count')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['scale', 'prefix', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        if getattr(args, 'created_output', None) is not None:
            save(args.created_output / 'failure.json', dict(error=f'{type(error).__name__}: {error}', productionAdoption=False))
        raise


if __name__ == '__main__':
    main()
