#!/usr/bin/env python3
"""Time the unchanged Work admission stages in an isolated native diagnostic."""
import argparse
import fcntl
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from context_candidate import once
from context_native_probe import environment, sha, tree
from pilot_memory_probe import protected_databases
from semantic_latency import execute, save


COUNTERS = '''structure DiscoveryProfileCost where
  calls : Nat := 0
  nanoseconds : Nat := 0
  deriving ToJson

/-- A thunk keeps the measured work after the clock observation. This wrapper
changes no decision or cache and is compiled only in the diagnostic checkout. -/
@[noinline] def discoveryProfileIO (costs : IO.Ref (Std.HashMap String DiscoveryProfileCost))
    (label : String) (action : Unit → IO α) : IO α := do
  let started ← IO.monoNanosNow
  let result ← action ()
  let elapsed := (← IO.monoNanosNow) - started
  costs.modify fun table =>
    let previous := table.getD label {}
    table.insert label {calls := previous.calls + 1, nanoseconds := previous.nanoseconds + elapsed}
  pure result

'''


def instrument(source):
    start = source.index('def indexedDiscoveryUsing (source : IndexedContext)')
    stop = source.index('/-- An empty body can still carry source-refresh metadata.', start)
    body = source[start:stop]
    body = once(body, '  trace "start"', '  trace "start"\n  let costs ← IO.mkRef ({} : Std.HashMap String DiscoveryProfileCost)')
    body = once(body, '  let prepare := fun (state : IndexedOwners) (runLocal : List UnionEdge) (runAll : List AllEdge) => do',
        '  let prepare := fun (state : IndexedOwners) (runLocal : List UnionEdge) (runAll : List AllEdge) => discoveryProfileIO costs "topology.prepare" fun _ => do')
    body = once(body, '  let evaluate := fun (state : IndexedOwners) (view : RunView) (tasks : List Value) => do',
        '  let evaluate := fun (state : IndexedOwners) (view : RunView) (tasks : List Value) => discoveryProfileIO costs "evaluate.total" fun _ => do')
    body = once(body, '      let ids ← source.surfaces query.pattern.surfaces.toList',
        '      let ids ← discoveryProfileIO costs "surfaces" fun _ => source.surfaces query.pattern.surfaces.toList')
    body = once(body, '      let admit := fun (ordinal : Nat) (work : Matcher.WorkView) => do',
        '      let admit := fun (ordinal : Nat) (work : Matcher.WorkView) => discoveryProfileIO costs "admit.total" fun _ => do')
    body = once(body, '        let units := Matcher.Corpus.workScoringTerms work query',
        '        let units ← discoveryProfileIO costs "workScoringTerms" fun _ => pure (Matcher.Corpus.workScoringTerms work query)')
    body = once(body, '        let read ← readDemandFrequencies source.frequencies known units',
        '        let read ← discoveryProfileIO costs "frequencies" fun _ => readDemandFrequencies source.frequencies known units')
    body = once(body, '        let requested := Matcher.GeometryMemo.inputsWork corpus work text taskNative query',
        '        let requested ← discoveryProfileIO costs "geometry.inputsWork" fun _ => pure (Matcher.GeometryMemo.inputsWork corpus work text taskNative query)')
    body = once(body, '        let ranks ← Matcher.GeometryMemo.prepareRanksFromM rankReader (← knownRanks.get)\n          previousCoverage savedRanks requested',
        '        let ranks ← discoveryProfileIO costs "geometry.prepareRanks" fun _ => do\n          Matcher.GeometryMemo.prepareRanksFromM rankReader (← knownRanks.get) previousCoverage savedRanks requested')
    body = once(body, '        let selection ← Matcher.GeometryMemo.prepareUsingM previousCoverage ranks.cache\n          selectionReader (← retainedSelections.get) requested',
        '        let selection ← discoveryProfileIO costs "geometry.prepare" fun _ => do\n          Matcher.GeometryMemo.prepareUsingM previousCoverage ranks.cache selectionReader (← retainedSelections.get) requested')
    body = once(body, '        pure (!(work.alignments (Matcher.GeometryMemo.provider coverage)\n          view.quotient corpus task query.pattern query.workPatterns false taskNative).isEmpty)',
        '        discoveryProfileIO costs "alignments" fun _ =>\n          pure (!(work.alignments (Matcher.GeometryMemo.provider coverage)\n            view.quotient corpus task query.pattern query.workPatterns false taskNative).isEmpty)')
    body = once(body, '        state ← IndexedOwners.loadWork source.ordinal source.readWork source.readOwner state id admit',
        '''        state ← discoveryProfileIO costs "loadWork.total" fun _ =>
          IndexedOwners.loadWork
            (fun id => discoveryProfileIO costs "ordinal" fun _ => source.ordinal id)
            (fun id => discoveryProfileIO costs "readWork" fun _ => source.readWork id)
            (fun id => discoveryProfileIO costs "readOwner" fun _ => source.readOwner id)
            state id admit''')
    body = once(body, '''        let mut subworks := state.subworks
        let requested := membershipDemand state.candidates stagedCandidates
        for work in requested.works do
          -- A new alias may grant membership after an earlier negative read.
          if ← membership work then
            unless subworks.contains work do
              subworks := work :: subworks
        state := {state with subworks}''', '''        state ← discoveryProfileIO costs "childMembership" fun _ => do
          let mut subworks := state.subworks
          let requested := membershipDemand state.candidates stagedCandidates
          for work in requested.works do
            -- A new alias may grant membership after an earlier negative read.
            if ← membership work then
              unless subworks.contains work do
                subworks := work :: subworks
          pure {state with subworks}''')
    body = once(body, '      let requested := Matcher.GeometryMemo.inputsPrepared corpus text semantic taskNative query',
        '      let requested ← discoveryProfileIO costs "batch.inputsPrepared" fun _ => pure (Matcher.GeometryMemo.inputsPrepared corpus text semantic taskNative query)')
    body = once(body, '      let (grounded, context) ← Matcher.GeometryMemo.Context.groundM prepared groundedCorpus\n        taskNative effectiveEvidence contextReader (← retainedContext.get)',
        '      let (grounded, context) ← discoveryProfileIO costs "batch.ground" fun _ => do\n        Matcher.GeometryMemo.Context.groundM prepared groundedCorpus taskNative effectiveEvidence contextReader (← retainedContext.get)')
    body = once(body, '  trace "discovery"', '''  trace "discovery"
  let profile := (← costs.get).toList.mergeSort (fun a b => a.1 ≤ b.1)
  trace ("profile " ++ (Json.mkObj (profile.map fun (label, cost) => (label, toJson cost))).compress)''')
    return source[:start] + COUNTERS + body + source[stop:]


def run(args):
    inspection = args.inspection.resolve(); scale = args.scale.resolve(); output = args.output.resolve()
    source = Path(__file__).resolve().parents[1]
    if any(output.is_relative_to(path) or path.is_relative_to(output) for path in [source, inspection, scale]):
        raise ValueError('Use a separate diagnostic directory')
    with (scale / 'run.guard').open('a') as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        prior = json.loads((inspection / 'result.json').read_text())
        manifest = json.loads((inspection / 'manifest.json').read_text())
        if not prior['passed'] or json.loads((scale / 'summary.json').read_text())['recordedAttempts'] != 60:
            raise ValueError('Complete the original collection and phase inspection first')
        original = inspection / 'checkout'
        binary = original / '.lake/build/bin/eggshell'
        if sha(binary) != manifest['qualifiedRuntime'] or any(
                sha(original / name) != digest for name, digest in manifest['overlays'].items()):
            raise ValueError('The qualified runtime or overlays changed')
        helper = original / 'tools/LexicalScaleProfile.lean'
        if sha(helper) != manifest['helperSourceSha256']:
            raise ValueError('The inspected helper changed')
        original_result = json.loads((inspection / '10000/lexical/stdout').read_text())
        receipt = original_result['receipt']
        if len(receipt) != 64 or any(c not in '0123456789abcdef' for c in receipt):
            raise ValueError('The reference receipt is invalid')
        output.mkdir(parents=True, exist_ok=False, mode=0o700); args.created_output = output
        checkout = output / 'checkout'
        subprocess.run(['/bin/cp', '-cpR', str(original), str(checkout)], check=True, timeout=300)
        handoff = checkout / 'Eggshell/Handoff.lean'
        candidate = None
        rendered = handoff.read_text()
        components = []
        if args.depth_candidate:
            import discovery_depth_candidate
            rendered = discovery_depth_candidate.handoff(rendered)
            components.append(dict(kind='exact-depth-relation-membership',
                sourceSha256=sha(Path(discovery_depth_candidate.__file__))))
        if args.owner_candidate:
            import discovery_owner_candidate
            rendered = discovery_owner_candidate.handoff(rendered)
            components.append(dict(kind='publication-ordinal-owner-tree',
                sourceSha256=sha(Path(discovery_owner_candidate.__file__))))
            owner_checks = Path(__file__).with_name('DiscoveryOwnerTests.lean')
            shutil.copy2(owner_checks, checkout / 'tools/DiscoveryOwnerTests.lean')
            lakefile = checkout / 'lakefile.lean'
            lakefile.write_text(lakefile.read_text() +
                '\nlean_exe discovery_owner_tests where\n  root := `tools.DiscoveryOwnerTests\n')
        if args.work_candidate:
            import discovery_work_candidate
            rendered = discovery_work_candidate.handoff(rendered)
            components.append(dict(kind='exact-work-and-child-projections',
                sourceSha256=sha(Path(discovery_work_candidate.__file__))))
        if args.match_candidate:
            import discovery_match_candidate
            matcher = checkout / 'Eggshell/Matcher.lean'
            matcher.write_text(discovery_match_candidate.matcher(matcher.read_text()))
            helpers = {}
            for name in discovery_match_candidate.HELPERS:
                helper_source = Path(__file__).with_name(name)
                shutil.copy2(helper_source, checkout / 'tools' / name)
                helpers['tools/' + name] = sha(helper_source)
            lakefile = checkout / 'lakefile.lean'
            lakefile.write_text(lakefile.read_text() + discovery_match_candidate.TARGETS)
            components.append(dict(kind='exact-latest-match-override',
                sourceSha256=sha(Path(discovery_match_candidate.__file__)),
                baselineMatcherSha256=sha(original / 'Eggshell/Matcher.lean'),
                matcherSha256=sha(matcher), helpers=helpers))
        if components:
            candidate = dict(components=components, handoffSha256=hashlib.sha256(rendered.encode()).hexdigest())
        handoff.write_text(instrument(rendered))
        compiled_helper = checkout / 'tools/LexicalScaleProfile.lean'
        compiled_helper.write_text(once(compiled_helper.read_text(), '  let receipt ← Receipt.fresh',
            '  let receipt := ' + json.dumps(receipt)))
        save(output / 'manifest.json', dict(originalInspectionSha256=sha(inspection / 'result.json'),
            runnerSha256=sha(Path(__file__)), originalHandoffSha256=sha(original / 'Eggshell/Handoff.lean'),
            instrumentedHandoffSha256=sha(handoff), helperSourceSha256=sha(helper),
            compiledHelperSha256=sha(compiled_helper), referenceReceipt=receipt,
            ownerTestsSourceSha256=sha(owner_checks) if args.owner_candidate else None,
            referenceWorkspace=str(original),
            qualifiedRuntime=manifest['qualifiedRuntime'], fullFallbackTimeoutSeconds=120,
            fixture='10000', questionIndex=0, productionAdoption=False, newNativeHooks=0,
            generationModelCalls=0, instrumentationOverheadIncluded=True, candidate=candidate))
        config = output / 'empty.toml'
        config.write_text('default = "empty"\nsemantic_matcher = false\n[profiles.empty]\nread = []\n')
        env = environment(output / 'data', config, args.prefix.resolve())
        targets = (['lexical_scale_profile'] + (['discovery_owner_tests'] if args.owner_candidate else [])
                   + (['keyed_override_tests'] if args.match_candidate else []))
        execute(['lake', '--no-cache', 'build'] + targets, output / 'build', env, checkout, timeout=600)
        if args.owner_candidate:
            execute([checkout / '.lake/build/bin/discovery_owner_tests'], output / 'owner-tests', env, checkout)
        if args.match_candidate:
            execute([checkout / '.lake/build/bin/keyed_override_tests'], output / 'match-tests', env, checkout)
        fixture = next(row for row in manifest['fixtures'] if row['label'] == '10000')
        database = scale / 'prepared/10000/source.egg'
        before = json.loads((database.parent / 'prepared.json').read_text())['files']
        if tree(database) != before:
            raise ValueError('The common warm publication changed')
        trace = output / 'trace.log'
        with protected_databases([database]):
            raw, timing = execute([checkout / '.lake/build/bin/lexical_scale_profile', '--lexical',
                database, fixture['questions'][0]], output / 'lexical',
                dict(env, EGGSHELL_HANDOFF_TRACE=str(trace)), original, timeout=120)
        result = json.loads(raw)
        # Bind the same receipt and workspace with a separate private output
        # root. Even workspace-bound status keys must match exactly.
        if (result['handoff'] != original_result['handoff'] or result['semanticProviderConfigured']
                or tree(database) != before or sha(binary) != manifest['qualifiedRuntime']):
            raise ValueError('Instrumentation changed delivery or the source/runtime')
        stages = [json.loads(line.split('ms profile ', 1)[1]) for line in trace.read_text().splitlines()
                  if 'ms profile ' in line]
        if len(stages) != 2 or any(not row.get('loadWork.total', {}).get('calls') for row in stages):
            raise ValueError('Both known-first and lexical discovery measurements are required')
        if any(sha(original / name) != digest for name, digest in manifest['overlays'].items()):
            raise ValueError('Instrumentation changed a qualified source overlay')
        if args.match_candidate and (sha(original / 'Eggshell/Matcher.lean') != components[-1]['baselineMatcherSha256']
                or sha(checkout / 'Eggshell/Matcher.lean') != components[-1]['matcherSha256']
                or any(sha(checkout / name) != digest for name, digest in components[-1]['helpers'].items())):
            raise ValueError('The exact Match implementation or baseline changed during inspection')
        save(output / 'result.json', dict(passed=True, exactHandoff=True, profile=stages,
            elapsedMs=result['elapsedMs'], timing=timing, productionAdoption=False,
            generationModelCalls=0, newNativeHooks=0, instrumentationOverheadIncluded=True,
            candidate=candidate, compiledHelperSha256=sha(checkout / '.lake/build/bin/lexical_scale_profile')))
        print(json.dumps(dict(passed=True, elapsedMs=result['elapsedMs'], profile=stages)), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['inspection', 'scale', 'prefix', 'output']:
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--depth-candidate', action='store_true',
        help='Inspect the isolated proof-equivalent relation membership change')
    parser.add_argument('--owner-candidate', action='store_true',
        help='Inspect the isolated ordinal-tree owner table and its native boundary checks')
    parser.add_argument('--work-candidate', action='store_true',
        help='Inspect exact child-demand deduplication and topology-only Work projection')
    parser.add_argument('--match-candidate', action='store_true',
        help='Inspect the proved latest-Match override compiler rewrite')
    args = parser.parse_args()
    try:
        run(args)
    except Exception as error:
        if getattr(args, 'created_output', None) is not None:
            save(args.created_output / 'failure.json', dict(error=f'{type(error).__name__}: {error}', productionAdoption=False))
        raise


if __name__ == '__main__':
    main()
