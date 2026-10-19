#!/usr/bin/env python3
"""Exercise the registered native hook command, without a model or source DB."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import tempfile
import time


def process_table():
    result = {}
    for line in subprocess.check_output(["ps", "-axo", "pid=,ppid=,lstart=,command="], text=True).splitlines():
        fields = line.split(maxsplit=7)
        if len(fields) == 8:
            result[int(fields[0])] = (int(fields[1]), " ".join(fields[2:7]), fields[7])
    return result


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def probe(options, event, mode, repeat):
    root = options.output / f"{mode}-{event}-{repeat}"
    root.mkdir(parents=True, exist_ok=False)
    data = root / "data"
    session = data / "sessions/probe"
    session.mkdir(parents=True)
    state = session / "state.json"
    if mode == "blocked-state":
        os.mkfifo(state, 0o600)
    elif mode == "bad-state":
        state.write_text("invalid JSON\n")
    elif mode == "disabled":
        state.write_text(json.dumps(dict(profile="work", enabled=False, nextProfile=None, nextProjection=None,
                                        deliveredGraphs=[], afterCompaction=False, lastHandoff="",
                                        lastReason="", epoch=0, offers=[])))
    value = dict(hook_event_name=event, session_id="probe", turn_id="turn",
                 cwd=str(options.input_cwd), tool_name="shell", tool_use_id="native-result",
                 tool_input=dict(command="printf probe"),
                 tool_response=dict(output="NATIVE_RESULT_PROBE"))
    payload = (json.dumps(value, separators=(",", ":")) + "\n").encode()
    (root / "input.json").write_bytes(payload)
    manifest = json.loads(options.manifest.read_text())
    handler = manifest["hooks"][event][0]["hooks"][0]
    args = shlex.split(handler["command"])[1:]
    limit = handler["timeout"]
    env = os.environ.copy()
    for key in ("PLUGIN_ROOT", "PLUGIN_DATA", "CODEX_THREAD_ID"):
        env.pop(key, None)
    env.update(EGGSHELL_DATA_ROOT=str(data), EGGSHELL_CONFIG=str(root / "absent.toml"),
               EGGSHELL_PREFIX=str(root / "runtime"), LEAN_NUM_THREADS="1", HF_HUB_OFFLINE="1")
    known = {}
    started = time.monotonic()
    child = subprocess.Popen([str(options.binary), *args], cwd=root, env=env,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             start_new_session=True)
    child.stdin.write(payload)
    child.stdin.flush()
    if mode != "held-stdin":
        child.stdin.close()
        child.stdin = None
    next_sample = 0
    while child.poll() is None and time.monotonic() - started < limit:
        if time.monotonic() >= next_sample:
            rows = process_table()
            if child.pid in rows:
                known.setdefault(child.pid, rows[child.pid][1])
            active = {pid for pid, identity in known.items() if pid in rows and rows[pid][1] == identity}
            changed = True
            while changed:
                changed = False
                for pid, (parent, identity, _) in rows.items():
                    if parent in active and pid not in active:
                        active.add(pid)
                        known[pid] = identity
                        changed = True
            next_sample = time.monotonic() + .2
        time.sleep(.01)
    host_killed = child.poll() is None
    if host_killed:
        os.killpg(child.pid, signal.SIGKILL)
    if child.stdin is not None:
        child.stdin.close()
        child.stdin = None
    stdout, stderr = child.communicate(timeout=2)
    elapsed = time.monotonic() - started
    (root / "stdout.txt").write_bytes(stdout)
    (root / "stderr.txt").write_bytes(stderr)
    try:
        output = json.loads(stdout)
        valid = isinstance(output, dict)
    except (UnicodeDecodeError, json.JSONDecodeError):
        output, valid = None, False
    # Managers deliberately detach. Discover any too fast for ancestry sampling
    # through this fixture's endpoint and verify the executable before cleanup.
    rows = process_table()
    for endpoint in data.glob("sessions/*/daemon.json"):
        pid = json.loads(endpoint.read_text())["pid"]
        if pid in rows and rows[pid][2].startswith(str(options.binary) + " codex-daemon "):
            known[pid] = rows[pid][1]
    cleaned = []
    for pid, identity in known.items():
        row = process_table().get(pid)
        if row is not None and row[1] == identity:
            try:
                os.kill(pid, signal.SIGKILL)
                cleaned.append(pid)
            except ProcessLookupError:
                pass
    native = list(session.glob("tools/*/*.json"))
    expected_missing = options.expect_public_failures and (mode == "held-stdin" or (mode == "blocked-state" and event == "PostToolUse"))
    expected_receipts = int(event == "PostToolUse" and (mode == "normal" or (mode == "bad-state" and not options.expect_public_failures)))
    errors = []
    if host_killed != expected_missing or valid == expected_missing:
        errors.append("unexpected timeout or hook output validity")
    if not expected_missing and child.returncode != 0:
        errors.append("hook did not exit successfully")
    if len(native) != expected_receipts:
        errors.append("native observation count differs from the declared expectation")
    for receipt in native:
        saved = json.loads(receipt.read_text())
        if (saved.get("name") != value["tool_name"] or saved.get("useId") != value["tool_use_id"]
                or json.loads(saved["input"]) != value["tool_input"]
                or json.loads(saved["response"]) != value["tool_response"]):
            errors.append("native observation body changed")
    if not expected_missing and mode in ("normal", "disabled") and output != {}:
        errors.append("ordinary or disabled hook unexpectedly injected context")
    needs_notice = mode in ("blocked-state", "held-stdin") or (mode == "bad-state" and event == "PostToolUse")
    if not expected_missing and needs_notice:
        if valid and not any(word in stdout.decode().lower() for word in ("incomplete", "unconfirmed", "not complete")):
            errors.append("failed work was not explicitly reported as unconfirmed")
    result = dict(event=event, mode=mode, repeat=repeat, input_sha256=sha(root / "input.json"),
                  registered_args=args, host_limit_seconds=limit, elapsed_seconds=elapsed,
                  host_killed=host_killed, exit_code=child.returncode, stdout_bytes=len(stdout),
                  valid_json_object=valid, native_receipts=len(native), cleanup_pids=cleaned, errors=errors)
    (root / "receipt.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)
    return result


def main():
    project = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=project / ".lake/build/bin/eggshell")
    parser.add_argument("--manifest", type=Path, default=project / "plugins/eggshell/hooks/hooks.json")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--input-cwd", type=Path, default=project)
    parser.add_argument("--repetitions", type=int, default=1)
    parser.add_argument("--expect-public-failures", action="store_true")
    options = parser.parse_args()
    options.binary = options.binary.resolve()
    options.manifest = options.manifest.resolve()
    options.output = options.output.resolve() if options.output else Path(tempfile.mkdtemp(prefix="eggshell-ingress-"))
    options.output.mkdir(parents=True, exist_ok=True)
    schedule = []
    for repeat in range(1, options.repetitions + 1):
        events = ("Interrupt", "PostToolUse") if repeat % 2 else ("PostToolUse", "Interrupt")
        for mode in ("normal", "disabled", "bad-state", "blocked-state"):
            schedule.extend((event, mode, repeat) for event in events)
        schedule.append(("Interrupt", "held-stdin", repeat))
    (options.output / "manifest.json").write_text(json.dumps(dict(
        binary_sha256=sha(options.binary), hooks_sha256=sha(options.manifest), harness_sha256=sha(Path(__file__)),
        schedule=schedule, model_calls=0, input_cwd=str(options.input_cwd),
        expect_public_failures=options.expect_public_failures), indent=2) + "\n")
    results = [probe(options, *item) for item in schedule]
    (options.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    raise SystemExit(int(any(row["errors"] for row in results)))


if __name__ == "__main__":
    main()
