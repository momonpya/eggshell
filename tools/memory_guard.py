#!/usr/bin/env python3
"""Run one serial experiment with a three-GiB aggregate RSS stop threshold.

The one-GiB margin below the user's four-GiB ceiling allows for sampling delay.
Count the monitor, descendants and explicitly owned detached executables. Keep
large child output in files rather than loading it into the chat or monitor.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import time

MAX_MIB = 3072


def code_sha():
    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def processes():
    rows = {}
    output = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,rss=,stat=,lstart=,args='],
                                     text=True, env=dict(os.environ, LC_ALL='C'))
    for line in output.splitlines():
        fields = line.split(maxsplit=9)
        if len(fields) == 10:
            pid, parent, rss = map(int, fields[:3])
            rows[pid] = dict(parent=parent, rss=rss, state=fields[3],
                             identity=' '.join(fields[4:9]), command=fields[9])
    return rows


def require_guard(protocol):
    """Model dispatch must be a direct child of the frozen, live monitor."""
    pid = int(os.environ.get('EGGSHELL_EXPERIMENT_GUARD_PID', '0'))
    path = os.environ.get('EGGSHELL_EXPERIMENT_GUARD_RECORD')
    if not pid or pid != os.getppid() or not path:
        raise ValueError('Run the experiment under tools/memory_guard.py before heavy work')
    record = json.loads(Path(path).read_text())
    if not (record['guardPid'] == pid and record['state'] == 'running' and
            record['limitRssKiB'] <= MAX_MIB * 1024 and
            record['guardSha256'] == protocol['memoryGuardSha256'] == code_sha()):
        raise ValueError('Memory monitor does not match the frozen experiment')


def run(command, record_path, cwd, limit_mib=MAX_MIB, disk_mib=2048, prefixes=()):
    if not command or not 1 <= limit_mib <= MAX_MIB:
        raise ValueError('RSS threshold must be at most 3072 MiB')
    record_path = record_path.resolve()
    record_path.parent.mkdir(parents=True, exist_ok=True)
    if record_path.exists():
        raise ValueError('Keep the existing monitor record; choose a new execution label')
    if shutil.disk_usage(record_path.parent).free < disk_mib * 1024**2:
        raise OSError('Not enough disk space to start a guarded experiment')
    record = dict(guardPid=os.getpid(), guardSha256=code_sha(), state='running',
        limitRssKiB=limit_mib * 1024, userCeilingRssKiB=4096 * 1024,
        sampledPeakRssKiB=0, samples=0, guardTriggered=False, reason=None,
        ownedPrefixes=list(prefixes), childCommand=command)

    def save():
        pending = record_path.with_suffix(record_path.suffix + '.pending')
        pending.write_text(json.dumps(record, indent=2) + '\n')
        pending.replace(record_path)

    interrupted = []
    previous_handlers = {}
    for kind in [signal.SIGINT, signal.SIGTERM]:
        previous_handlers[kind] = signal.signal(kind, lambda signum, frame: interrupted.append(signum))
    environment = dict(os.environ, LEAN_NUM_THREADS='1', HF_HUB_OFFLINE='1',
        OMP_NUM_THREADS='1', OPENBLAS_NUM_THREADS='1', MKL_NUM_THREADS='1',
        TOKENIZERS_PARALLELISM='false', EGGSHELL_EXPERIMENT_GUARD_PID=str(os.getpid()),
        EGGSHELL_EXPERIMENT_GUARD_RECORD=str(record_path))
    save()
    known = {}
    active = set()
    child = None
    started = time.monotonic()

    def observe():
        nonlocal active
        rows = processes()
        active = {pid for pid, identity in known.items() if pid in rows and
                  rows[pid]['identity'] == identity and not rows[pid]['state'].startswith('Z')}
        if child.pid in rows and not rows[child.pid]['state'].startswith('Z'):
            active.add(child.pid)
        for pid, row in rows.items():
            if pid == os.getpid() or row['state'].startswith('Z'):
                continue
            try:
                arguments = shlex.split(row['command'])
            except ValueError:
                arguments = []
            if any(arg == prefix or arg.startswith(prefix + '/') for arg in arguments for prefix in prefixes):
                active.add(pid)
        changed = True
        while changed:
            found = {pid for pid, row in rows.items() if row['parent'] in active and not row['state'].startswith('Z')}
            changed = not found.issubset(active)
            active.update(found)
        for pid in active:
            known[pid] = rows[pid]['identity']
        rss = sum(rows[pid]['rss'] for pid in active) + rows.get(os.getpid(), {}).get('rss', 0)
        record['sampledPeakRssKiB'] = max(record['sampledPeakRssKiB'], rss)
        record['samples'] += 1
        return rows, rss

    def terminate():
        if child is None:
            return
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        for kind, delay in [(signal.SIGTERM, .3), (signal.SIGKILL, .1)]:
            rows, _ = observe()
            for pid in active:
                if pid in rows and known[pid] == rows[pid]['identity']:
                    try:
                        os.kill(pid, kind)
                    except ProcessLookupError:
                        pass
            time.sleep(delay)
        child.wait(timeout=5)

    try:
        with record_path.with_suffix('.stdout').open('xb') as output, record_path.with_suffix('.stderr').open('xb') as errors:
            child = subprocess.Popen(command, cwd=cwd, env=environment, stdout=output,
                                     stderr=errors, start_new_session=True)
            record['childPid'] = child.pid
            save()
            while True:
                _, rss = observe()
                if interrupted:
                    record['reason'] = 'interrupted'
                elif rss >= record['limitRssKiB']:
                    record['reason'] = 'aggregate-rss'
                elif shutil.disk_usage(record_path.parent).free < disk_mib * 1024**2:
                    record['reason'] = 'disk-space'
                elif child.poll() is not None:
                    time.sleep(.1)
                    observe()
                    if active:
                        record['reason'] = 'leftover-processes'
                    break
                if record['reason']:
                    break
                if record['samples'] % 20 == 0:
                    save()
                time.sleep(.1)
    except BaseException as error:
        record['reason'] = 'monitor-error'
        record['error'] = f'{type(error).__name__}: {error}'
        raise
    finally:
        try:
            if child is not None:
                if record['reason'] or child.poll() is None or active:
                    terminate()
                record['exitCode'] = child.wait(timeout=5)
        finally:
            for kind, handler in previous_handlers.items():
                signal.signal(kind, handler)
            record.update(state='finished', elapsedSeconds=time.monotonic() - started,
                          guardTriggered=record['reason'] is not None)
            save()
    return record


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--record', type=Path, required=True)
    parser.add_argument('--cwd', type=Path, default=Path.cwd())
    parser.add_argument('--rss-mib', type=int, default=MAX_MIB)
    parser.add_argument('--disk-mib', type=int, default=2048)
    parser.add_argument('--owned-prefix', action='append', default=[])
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    result = run(command, args.record, args.cwd, args.rss_mib, args.disk_mib, args.owned_prefix)
    print(json.dumps({k:result[k] for k in ['exitCode', 'sampledPeakRssKiB', 'limitRssKiB', 'guardTriggered', 'reason']}))
    code = result['exitCode']
    sys.exit(2 if result['guardTriggered'] else (128 - code if code < 0 else min(125, code)))
