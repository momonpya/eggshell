#!/usr/bin/env python3
"""Construct an isolated read barrier before native staged semantic lookup."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BASE = Path('/Users/ovm/.codex/experiments/eggshell/complete-index-20261021/construction-3/candidate/checkout')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(output):
    assert not output.exists(), 'Keep previous construction attempts intact'
    assert sha(BASE / '.lake/build/bin/eggshell') == '57cceba86ee4b1e00bb35f0289ee0766b270c636fe47379e53ae1fde3e2d03cb'
    output.mkdir(parents=True)
    checkout = output / 'checkout'
    subprocess.run(['/bin/cp', '-cR', str(BASE), str(checkout)], check=True)
    shutil.copy2(__file__, output / 'executed-constructor.py')
    shutil.copy2(ROOT / 'tools/SourceReadiness.lean', checkout / 'tools/SourceReadiness.lean')
    path = checkout / 'Eggshell/Worker.lean'
    original = path.read_text()
    changed = original.replace('public import Eggshell.Warm\n',
        'public import Eggshell.Warm\npublic import tools.SourceReadiness\n', 1)
    changed = changed.replace('let some current := currentSearch? request state pending | return none',
        'let some _ := currentSearch? request state pending | return none', 1)
    changed = changed.replace('''  | .automatic =>
      let mut staged := []
''', '''  | .automatic =>
      let mut staged := []
      let mut sourceReady := true
''', 1)
    before = '''        staged := staged ++ (← IO.ofExcept (stagedGraphValues (snapshot.getD request.pending)))
      staged := staged.eraseDups
      automaticHandoff selection request.work
'''
    after = '''        let observed := snapshot.getD request.pending
        staged := staged ++ (← IO.ofExcept (stagedGraphValues observed))
        if request.route == .configured && request.evidence.isNone then
          sourceReady ← SourceReadiness.wait observed request.deadline request.receipt
      staged := staged.eraseDups
      -- Neither a completed index nor a captured pre-wait state grants delivery.
      let some state ← (readJson? files.state stateJsonDefaults : IO (Option ThreadState)) |
        throw (IO.userError "search context state disappeared after preparation")
      let some pending ← (readJson? files.pending pendingJsonDefaults : IO (Option PendingTurn)) |
        throw (IO.userError "search turn disappeared after preparation")
      let some current := currentSearch? request state pending | return none
      unless sourceReady do return some pendingSearch
      automaticHandoff selection request.work
'''
    assert changed.count(before) == 1
    path.write_text(changed.replace(before, after))
    (output / 'Worker-before.lean').write_text(original)
    (output / 'Worker-after.lean').write_text(path.read_text())
    with (checkout / 'lakefile.lean').open('a') as stream:
        stream.write('\nlean_lib SourceReadinessResearch where\n  roots := #[`tools.SourceReadiness]\n')
    command = ['lake', '--no-cache', 'build', 'eggshell', 'Eggshell.ContractAudit']
    started = time.monotonic()
    with (output / 'build.log').open('wb') as log:
        result = subprocess.run(command, cwd=checkout, env=dict(os.environ, LEAN_NUM_THREADS='1', HF_HUB_OFFLINE='1'),
            stdout=log, stderr=subprocess.STDOUT)
    record = dict(command=command, exitCode=result.returncode, elapsedSeconds=time.monotonic()-started)
    (output / 'build.json').write_text(json.dumps(record, indent=2)+'\n')
    if result.returncode:
        raise RuntimeError('Inspect retained build failure: ' + str(output))
    unchanged = ['Handoff.lean', 'SearchProvider.lean', 'SemanticMatcher.lean', 'Warm.lean', 'PluginHooks.lean']
    assert all(sha(BASE / 'Eggshell' / name) == sha(checkout / 'Eggshell' / name) for name in unchanged)
    manifest = dict(checkout=str(checkout), base=str(BASE), runtimeSha256=sha(checkout / '.lake/build/bin/eggshell'),
        unchangedSources={name:sha(checkout / 'Eggshell' / name) for name in unchanged},
        generationModelCalls=0, productionAdoption=False)
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(json.dumps(manifest), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    main(parser.parse_args().output)
