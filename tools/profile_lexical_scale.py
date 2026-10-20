#!/usr/bin/env python3
"""Inspect exact lexical nominations after the fixed native scale run ends."""
import argparse
import fcntl
import json
from pathlib import Path
import shutil
import subprocess

from context_native_probe import environment, sha, tree
from pilot_memory_probe import protected_databases
from semantic_latency import execute, save
from semantic_scale import check_subject


def run(args):
    build = args.build.resolve(); scale = args.scale.resolve(); output = args.output.resolve()
    source = Path(__file__).resolve().parents[1]
    if any(output.is_relative_to(path) or path.is_relative_to(output) for path in [source, build, scale]):
        raise ValueError('Phase inspection must use a separate experiment directory')
    # An existing summary alone does not prove the original runner has stopped.
    # Hold the same live-process lock throughout this separately timed inspection.
    with (scale / 'run.guard').open('a') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        summary = json.loads((scale / 'summary.json').read_text())
        results = json.loads((scale / 'results.json').read_text())
        if summary['recordedAttempts'] != 60 or len(results) != 60:
            raise ValueError('Retain and finish all 60 original attempts before phase inspection')
        manifest = json.loads((scale / 'manifest.json').read_text())
        order = ['10000', '1024', '2', 'actual-llvm', '50000']
        fixtures = sorted(manifest['fixtures'], key=lambda row: order.index(row['label']))
        original = build / 'checkout'; binary = original / '.lake/build/bin/eggshell'
        qualified = json.loads((build / 'result.json').read_text())
        if not qualified['passed'] or sha(binary) != qualified['candidateSha256']:
            raise ValueError('The qualified runtime changed')
        overlays = json.loads((build / 'overlays.json').read_text())
        if any(sha(original / name) != digest for name, digest in overlays.items()):
            raise ValueError('The compiled candidate sources differ from their qualified overlays')
        output.mkdir(parents=True, exist_ok=False, mode=0o700)
        args.created_output = output
        checkout = output / 'checkout'
        subprocess.run(['/bin/cp', '-cpR', str(original), str(checkout)], check=True, timeout=300)
        helper_source = Path(__file__).with_name('LexicalScaleProfile.lean')
        shutil.copy2(helper_source, checkout / 'tools' / helper_source.name)
        lakefile = checkout / 'lakefile.lean'
        lakefile.write_text(lakefile.read_text() +
            '\nlean_exe lexical_scale_profile where\n  root := `tools.LexicalScaleProfile\n')
        save(output / 'manifest.json', dict(qualifiedRuntime=qualified['candidateSha256'], overlays=overlays,
            helperSourceSha256=sha(helper_source), runnerSha256=sha(Path(__file__)),
            scaleManifestSha256=sha(scale / 'manifest.json'), scaleSummarySha256=sha(scale / 'summary.json'),
            fixtures=manifest['fixtures'], purpose='standalone-lexical-nomination-profile',
            profileOrder=order, fullFallbackFixtures=['10000'], fullFallbackTimeoutSeconds=120,
            retainedCollectionError=json.loads((scale / 'failure.json').read_text())
                if (scale / 'failure.json').exists() else None,
            newNativeHooks=0, generationModelCalls=0, productionAdoption=False))
        config = output / 'empty.toml'
        config.write_text('default = "empty"\nsemantic_matcher = false\n[profiles.empty]\nread = []\n')
        env = environment(output / 'data', config, args.prefix.resolve())
        execute(['lake', '--no-cache', 'build', 'lexical_scale_profile'], output / 'build', env, checkout, timeout=600)
        helper = checkout / '.lake/build/bin/lexical_scale_profile'
        if sha(checkout / '.lake/build/bin/eggshell') != qualified['candidateSha256']:
            raise ValueError('Building an inspection helper changed the cloned runtime')
        profiles = []
        for fixture in fixtures:
            check_subject(fixture)
            label = fixture['label']; prepared = scale / 'prepared' / label
            expected = json.loads((prepared / 'prepared.json').read_text())['files']
            database = prepared / 'source.egg'
            if tree(database) != expected:
                raise ValueError('The already-warm source/cache publication changed')
            with protected_databases([database]):
                raw, timing = execute([helper, database, fixture['questions'][0]], output / label,
                                      env, checkout, timeout=900)
                domain_raw, domain_timing = execute([helper, '--domain', database], output / label / 'domain',
                                                   env, checkout, timeout=900)
                lexical = None; lexical_timing = None
                if label == '10000':
                    lexical_env = dict(env, EGGSHELL_HANDOFF_TRACE=str(output / label / 'lexical-trace.log'))
                    try:
                        lexical_raw, lexical_timing = execute([helper, '--lexical', database, fixture['questions'][0]],
                            output / label / 'lexical', lexical_env, fixture.get('workspace', str(checkout)), timeout=120)
                        lexical = dict(json.loads(lexical_raw), inspectionStatus='returned')
                    except subprocess.TimeoutExpired:
                        lexical_timing = json.loads((output / label / 'lexical/record.json').read_text())
                        lexical = dict(inspectionStatus='timedOut', elapsedMs=None, timeoutSeconds=120)
            profile = json.loads(raw)
            domain = json.loads(domain_raw)
            if (profile['head'] != fixture['head'] or profile['population'] != fixture['documents']
                    or profile['selected'] != profile['ranking'][:8]
                    or len(profile['ranking']) != len(set(profile['ranking']))
                    or domain['head'] != fixture['head'] or domain['documents'] != fixture['documents']
                    or domain['windowReferences'] != fixture['windowReferences']
                    or domain['uniqueWindows'] != fixture['uniqueWindows']
                    or (lexical is not None and lexical['inspectionStatus'] == 'returned'
                        and lexical['semanticProviderConfigured'] is not False)
                    or tree(database) != expected):
                raise ValueError('Phase inspection changed its source or lost the full nomination order')
            check_subject(fixture)
            profiles.append(dict(fixture=label, profile=profile, timing=timing,
                domain=domain, domainTiming=domain_timing, lexical=lexical, lexicalTiming=lexical_timing))
            save(output / 'profiles.json', profiles)
            print(json.dumps(dict(fixture=label, ranked=len(profile['ranking']),
                postingUs=profile['postingUs'], ordinalUs=profile['ordinalUs'],
                otherNominationUs=profile['otherNominationUs'], totalUs=profile['totalUs'],
                searchDocumentsUs=domain['searchDocumentsUs'],
                lexicalFallbackMs=lexical['elapsedMs'] if lexical is not None else None)), flush=True)
        if sha(binary) != qualified['candidateSha256'] or any(
                sha(original / name) != digest for name, digest in overlays.items()):
            raise ValueError('Inspection changed the qualified candidate')
        save(output / 'result.json', dict(passed=True, helperSha256=sha(helper), profiles=profiles,
            newNativeHooks=0, generationModelCalls=0, productionAdoption=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['build', 'scale', 'prefix', 'output']:
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
