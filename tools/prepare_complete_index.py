#!/usr/bin/env python3
"""Build an isolated producer using the common complete-window warm path."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BASE = Path('/Users/ovm/.codex/experiments/eggshell/window-centroid-20261020/construction-3/checkout')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(output):
    if output.exists():
        raise ValueError('Keep prior construction attempts immutable')
    if sha(BASE / '.lake/build/bin/eggshell') != '415bcc2cd64412dad79d089da89f20533048901e5536f3d7206bdaa372b6f6f4':
        raise ValueError('Frozen base runtime changed')
    output.mkdir(parents=True)
    rows = []
    for name in ['baseline', 'candidate']:
        case = output / name
        checkout = case / 'checkout'
        case.mkdir()
        subprocess.run(['/bin/cp', '-cR', str(BASE), str(checkout)], check=True)
        shutil.copy2(ROOT / 'tools/IndexCompletionAudit.lean', checkout / 'tools/IndexCompletionAudit.lean')
        if name == 'candidate':
            shutil.copy2(ROOT / 'tools/IndexCompletion.lean', checkout / 'tools/IndexCompletion.lean')
            worker = checkout / 'Eggshell/Worker.lean'
            original = worker.read_text()
            first = original.index('/-- Batch compatible metadata tickets')
            last = original.index('\ndef run (role : String)', first)
            changed = original[:first] + original[last:]
            changed = changed.replace('public import Eggshell.Warm\n',
                                      'public import Eggshell.Warm\npublic import tools.IndexCompletion\n', 1)
            before = '''        let count ← indexQueued target (paths.map System.FilePath.mk)
        if (json.getObjValAs? Bool "warm").toOption.getD false then
          let _ ← Warm.runTarget (← target.owner.pin) target
          pure ()
'''
            after = '''        let count ← IndexCompletion.run target (paths.map System.FilePath.mk)
          ((json.getObjValAs? Bool "warm").toOption.getD false)
'''
            if changed.count(before) != 1:
                raise ValueError('Expected one index dispatcher')
            worker.write_text(changed.replace(before, after))
            (case / 'Worker-before.lean').write_text(original)
            (case / 'Worker-after.lean').write_text(worker.read_text())
        with (checkout / 'lakefile.lean').open('a') as stream:
            if name == 'candidate':
                stream.write('\nlean_lib IndexCompletionResearch where\n  roots := #[`tools.IndexCompletion]\n')
            stream.write('\nlean_exe index_completion_audit where\n  root := `tools.IndexCompletionAudit\n')
        env = dict(os.environ, LEAN_NUM_THREADS='1', HF_HUB_OFFLINE='1')
        command = ['lake', '--no-cache', 'build', 'index_completion_audit']
        if name == 'candidate':
            command += ['eggshell', 'Eggshell.ContractAudit']
        started = time.monotonic()
        with (case / 'build.log').open('wb') as log:
            result = subprocess.run(command, cwd=checkout, env=env, stdout=log, stderr=subprocess.STDOUT)
        record = dict(command=command, exitCode=result.returncode, elapsedSeconds=time.monotonic()-started)
        (case / 'build.json').write_text(json.dumps(record, indent=2) + '\n')
        if result.returncode:
            raise RuntimeError('Retain the failed build: ' + str(case))
        rows.append(dict(implementation=name, checkout=str(checkout),
            runtimeSha256=sha(checkout / '.lake/build/bin/eggshell'),
            helperSha256=sha(checkout / '.lake/build/bin/index_completion_audit'),
            workerSha256=sha(checkout / 'Eggshell/Worker.lean')))
        print(json.dumps(rows[-1]), flush=True)
    manifest = dict(base=str(BASE), rows=rows, templates={name: sha(ROOT / 'tools' / name) for name in
        ['IndexCompletion.lean', 'IndexCompletionAudit.lean', 'prepare_complete_index.py']},
        scope='Isolated index producer only; retrieval and equality rules unchanged',
        generationModelCalls=0, productionAdoption=False)
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    main(parser.parse_args().output)
