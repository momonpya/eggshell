#!/usr/bin/env python3
"""Build and regress the uninstrumented, isolated discovery candidate."""
import argparse
import importlib
import json
from pathlib import Path
import shutil
import subprocess
import time

from context_native_probe import environment, sha
from owned_daemon import shutdown_owned
from semantic_latency import execute, save


MODULES = {
    'exact-depth-relation-membership': 'discovery_depth_candidate',
    'publication-ordinal-owner-tree': 'discovery_owner_candidate',
    'exact-work-and-child-projections': 'discovery_work_candidate',
    'exact-latest-match-override': 'discovery_match_candidate',
}


def sources(checkout):
    return {str(path.relative_to(checkout)): sha(path) for path in checkout.rglob('*')
            if path.is_file() and not any(part in {'.lake', '.git', '__pycache__'}
                                         for part in path.relative_to(checkout).parts)}


def drain(binary, data, env, output, cwd):
    registered = [json.loads(path.read_text()) for path in (data / 'index-targets').glob('*.json')]
    live = {}
    for target in registered:
        owner = target['owner']; directory = Path(owner['directory']); head = directory / 'head'
        if not head.exists() or json.loads(head.read_text())['identity'] != owner['database']:
            continue
        indexes = (directory / 'derived' / owner['database'] / 'indexes'
                   if target['storage'] == 'database' else data / 'read-cache' / owner['database'] / 'indexes')
        live[str(indexes)] = dict(head=head, headSha256=sha(head))
    def tickets():
        return sorted(str(path) for directory in live for path in Path(directory).glob('**/*.json'))
    before = tickets()
    save(output / 'index-before.json', dict(tickets=before,
        heads={str(row['head']): row['headSha256'] for row in live.values()}))
    stopped = None
    if before:
        with (output / 'index-drain.log').open('wb') as log:
            process = subprocess.Popen([str(binary), 'codex-daemon', 'discovery-regression-recovery'],
                                       env=env, cwd=cwd, stdout=log, stderr=subprocess.STDOUT)
            try:
                expires = time.monotonic() + 30
                while tickets():
                    if process.poll() is not None or time.monotonic() > expires:
                        raise RuntimeError('The owned recovery daemon exited or did not drain pending work')
                    time.sleep(.02)
                stopped = shutdown_owned(process, binary, env, cwd, output / 'index-shutdown.json')
            finally:
                if process.poll() is None:
                    process.terminate(); process.wait(timeout=3)
    if tickets() or any(sha(row['head']) != row['headSha256'] for row in live.values()):
        raise ValueError('Background index maintenance changed a graph publication or left work pending')
    return dict(pendingBefore=len(before), pendingAfter=0, headsUnchanged=True, shutdown=stopped)


def run(args):
    profile = args.profile.resolve(); inspection = args.inspection.resolve(); output = args.output.resolve()
    source = Path(__file__).resolve().parents[1]
    if any(output.is_relative_to(path) or path.is_relative_to(output) for path in [source, profile, inspection]):
        raise ValueError('Use a separate qualification directory')
    completed = json.loads((profile / 'result.json').read_text())
    manifest = json.loads((profile / 'manifest.json').read_text())
    baseline = json.loads((inspection / 'manifest.json').read_text())
    original = inspection / 'checkout'; binary = original / '.lake/build/bin/eggshell'
    if (not completed['passed'] or not completed['exactHandoff']
            or sha(inspection / 'result.json') != manifest['originalInspectionSha256']
            or sha(binary) != manifest['qualifiedRuntime']
            or any(sha(original / name) != digest for name, digest in baseline['overlays'].items())):
        raise ValueError('The exact profile or qualified input changed')
    rendered = (original / 'Eggshell/Handoff.lean').read_text()
    matcher_rendered = None
    match_module = None
    components = manifest['candidate']['components']
    for component in components:
        module = importlib.import_module(MODULES[component['kind']])
        if sha(Path(module.__file__)) != component['sourceSha256']:
            raise ValueError('A candidate source changed after its profile')
        if component['kind'] == 'exact-latest-match-override':
            if sha(original / 'Eggshell/Matcher.lean') != component['baselineMatcherSha256']:
                raise ValueError('The reference semantic kernel changed')
            matcher_rendered = module.matcher((original / 'Eggshell/Matcher.lean').read_text())
            import hashlib
            if hashlib.sha256(matcher_rendered.encode()).hexdigest() != component['matcherSha256']:
                raise ValueError('The semantic kernel overlay cannot be reconstructed exactly')
            for name, digest in component['helpers'].items():
                if sha(source / name) != digest:
                    raise ValueError('A proof/check source changed after inspection')
            match_module = module
        else:
            rendered = module.handoff(rendered)
    import hashlib
    if hashlib.sha256(rendered.encode()).hexdigest() != manifest['candidate']['handoffSha256']:
        raise ValueError('The uninstrumented candidate cannot be reconstructed exactly')
    owner_checks = Path(__file__).with_name('DiscoveryOwnerTests.lean')
    if sha(owner_checks) != manifest['ownerTestsSourceSha256']:
        raise ValueError('The qualified owner boundary checks changed')
    original_sources = sources(original)
    ordinary = source / '.lake/build/bin/eggshell'; ordinary_hash = sha(ordinary)
    output.mkdir(parents=True, exist_ok=False, mode=0o700); args.created_output = output
    checkout = output / 'checkout'
    subprocess.run(['/bin/cp', '-cpR', str(original), str(checkout)], check=True, timeout=300)
    (checkout / 'Eggshell/Handoff.lean').write_text(rendered)
    shutil.copy2(owner_checks, checkout / 'tools/DiscoveryOwnerTests.lean')
    lakefile = checkout / 'lakefile.lean'
    lakefile.write_text(lakefile.read_text() +
        '\nlean_exe discovery_owner_tests where\n  root := `tools.DiscoveryOwnerTests\n')
    if matcher_rendered is not None:
        (checkout / 'Eggshell/Matcher.lean').write_text(matcher_rendered)
        for name in match_module.HELPERS:
            shutil.copy2(source / 'tools' / name, checkout / 'tools' / name)
        lakefile.write_text(lakefile.read_text() + match_module.TARGETS)
    frozen = sources(checkout)
    cache_record = None
    if args.build_cache is not None:
        cache = args.build_cache.resolve()
        cache_manifest = json.loads((cache / 'manifest.json').read_text())
        cache_build = json.loads((cache / 'build/record.json').read_text())
        if (cache_manifest['sources'] != frozen or sources(cache / 'checkout') != frozen
                or cache_build.get('exitCode') != 0):
            raise ValueError('The retained build cache has different sources or no completed build')
        cache_record = dict(manifestSha256=sha(cache / 'manifest.json'),
            buildRecordSha256=sha(cache / 'build/record.json'),
            retainedBinarySha256=sha(cache / 'checkout/.lake/build/bin/eggshell'))
        shutil.rmtree(checkout / '.lake/build')
        subprocess.run(['/bin/cp', '-cpR', str(cache / 'checkout/.lake/build'), str(checkout / '.lake/build')],
                       check=True, timeout=300)
    save(output / 'manifest.json', dict(profileManifestSha256=sha(profile / 'manifest.json'),
        profileResultSha256=sha(profile / 'result.json'), runnerSha256=sha(Path(__file__)),
        sources=frozen, components=components, qualifiedBaselineSha256=sha(binary),
        productionBinarySha256=ordinary_hash, originalSourceHashes=original_sources,
        instrumentation=False, productionAdoption=False, generationModelCalls=0,
        buildCache=cache_record, regressionConfigPolicy='fixture-owned; EGGSHELL_CONFIG unset'))
    config = output / 'empty.toml'
    config.write_text('default = "empty"\nsemantic_matcher = false\n[profiles.empty]\nread = []\n')
    data = output / 'data'; env = environment(data, config, args.prefix.resolve())
    targets = ['eggshell', 'eggshell_tests', 'discovery_owner_tests', 'Eggshell.ContractAudit']
    if match_module is not None:
        targets.append('keyed_override_tests')
    execute(['lake', '--no-cache', 'build'] + targets, output / 'build', env, checkout, timeout=600)
    owner_raw, owner_timing = execute([checkout / '.lake/build/bin/discovery_owner_tests'],
                                    output / 'owner-tests', env, checkout)
    match_checks = None
    if match_module is not None:
        raw, timing = execute([checkout / '.lake/build/bin/keyed_override_tests'],
                             output / 'match-tests', env, checkout)
        match_checks = dict(result=json.loads(raw), timing=timing)
    # The daemon deliberately attaches an explicit environment config over the
    # hook payload. Each native fixture supplies its own config in that payload.
    regression_env = dict(env)
    regression_env.pop('EGGSHELL_CONFIG', None)
    _, regression = execute([checkout / '.lake/build/bin/eggshell_tests'], output / 'regression',
                            regression_env, checkout, timeout=600)
    recovery = drain(checkout / '.lake/build/bin/eggshell', data, env, output, checkout)
    if (sources(checkout) != frozen or sources(original) != original_sources
            or sha(binary) != manifest['qualifiedRuntime'] or sha(ordinary) != ordinary_hash):
        raise ValueError('Qualification changed a frozen source or ordinary runtime')
    save(output / 'result.json', dict(passed=True, instrumentation=False,
        candidateSha256=sha(checkout / '.lake/build/bin/eggshell'),
        ownerChecks=json.loads(owner_raw), ownerTiming=owner_timing, regression=regression,
        matchChecks=match_checks,
        indexRecovery=recovery, sourcesUnchanged=True, ordinaryRuntimeUnchanged=True,
        generationModelCalls=0, productionAdoption=False))
    print(json.dumps(dict(passed=True, checkout=str(checkout), regressionMs=regression['elapsedMs'],
                          indexRecovery=recovery)), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['profile', 'inspection', 'prefix', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--build-cache', type=Path,
        help='Reuse a retained successful build only after checking every source; Lake still verifies all targets')
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        if getattr(args, 'created_output', None) is not None:
            save(args.created_output / 'failure.json', dict(error=f'{type(error).__name__}: {error}', productionAdoption=False))
        raise


if __name__ == '__main__':
    main()
