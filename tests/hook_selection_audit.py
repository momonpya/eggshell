#!/usr/bin/env python3
"""Check selection receipts through the real native hook, without a model."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    options = parser.parse_args()
    binary = options.binary.resolve()
    output = options.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    project = output / "project"
    project.mkdir()
    runtime = output / "runtime"
    database = project / "source.egg"
    config = project / "fixture.toml"
    # Deliberate failed nomination exercises the independently recorded lexical
    # route. This fixture makes no numerical-cache or embedding-model claim.
    config.write_text('default = "work"\nsemantic_matcher = ["/usr/bin/false"]\n'
                      f'[eggs]\nwork = {json.dumps(str(database))}\n'
                      '[profiles.work]\nread = ["work"]\nwrite = "work"\n')
    source = project / "probe.txt"
    body = "SELECTION_ORIGINAL_OBSERVATION_18431\n"
    source.write_text(body)
    env = os.environ.copy()
    env.update(EGGSHELL_DATA_ROOT=str(runtime), HF_HUB_OFFLINE="1")
    for name in ("PLUGIN_ROOT", "CODEX_THREAD_ID"):
        env.pop(name, None)
    runs = []

    def invoke(args, payload=None):
        start = time.monotonic()
        result = subprocess.run([str(binary), *args], input=payload, text=True,
                                capture_output=True, cwd=project, env=env, timeout=10)
        record = dict(args=args, input=payload, stdout=result.stdout,
                      stderr=result.stderr, exit_code=result.returncode,
                      elapsed_ms=round((time.monotonic() - start) * 1000))
        runs.append(record)
        (output / "runs.json").write_text(json.dumps(runs, indent=2))
        assert result.returncode == 0, record
        return result.stdout

    def hook(event, session, **fields):
        payload = dict(hook_event_name=event, session_id=session, turn_id="turn",
                       cwd=str(project), _eggshell_config=str(config), **fields)
        result = invoke(["codex-hook"], json.dumps(payload) + "\n")
        assert runs[-1]["elapsed_ms"] < 4300, runs[-1]
        return json.loads(result), result

    def begin(session):
        hook("SessionStart", session)
        return hook("UserPromptSubmit", session, prompt="Inspect probe.txt")

    tool = dict(tool_name="shell", tool_use_id="read-probe",
                tool_input=dict(command="cat probe.txt"))
    try:
        begin("seed")
        hook("PreToolUse", "seed", **tool)
        hook("PostToolUse", "seed", **tool, tool_response=dict(output=body))
        hook("Stop", "seed", last_assistant_message="The probe was inspected.")
        hook("SessionEnd", "seed")
        # Saving is asynchronous. Confirm the live seed daemon has consumed
        # every replayable job before interpreting reuse as saved-DB evidence.
        expires = time.monotonic() + 8
        while True:
            session = runtime / "sessions/seed"
            endpoint = json.loads((session / "daemon.json").read_text())
            os.kill(endpoint["pid"], 0)
            jobs = [path for name in ("deferred", "checkpoints")
                    for path in (session / name).glob("*.json")]
            if database.is_dir() and not jobs:
                break
            assert time.monotonic() < expires, dict(database=str(database), pending=jobs)
            time.sleep(0.1)
        begin("reuse")
        reused, raw = hook("PreToolUse", "reuse", **tool)
        assert '"deny"' in json.dumps(reused), reused
        receipts = []
        for path in (runtime / "receipts").iterdir():
            request = json.loads((path / "request.json").read_text())["data"]
            if request.get("session") == "reuse" and request.get("event") == "PreToolUse":
                receipts.append(path)
        assert len(receipts) == 1, receipts
        receipt = receipts[0]
        analysis = json.loads(invoke(["inspect-equality", receipt.name]))
        (output / "analysis.json").write_text(json.dumps(analysis, indent=2))
        assert analysis["published"]["output"] == raw, analysis
        assert analysis["published"]["sha256"] == hashlib.sha256(raw.encode()).hexdigest()
        assert analysis["acknowledgement"]["offerAccepted"] is True
        selected = analysis["selection"]
        assert selected["status"] == "partial" and selected["retained"]["controls"]
        assert selected["deliveryAncestry"] == "untracked"
        assert any(row["role"] == "completedOutcome" for row in selected["comparisons"])
        source.write_text("CHANGED_SOURCE_62481\n")
        begin("changed")
        changed, _ = hook("PreToolUse", "changed", **tool)
        assert '"deny"' not in json.dumps(changed), changed
        (output / "RESULT.json").write_text(json.dumps(dict(
            passed=True, receipt=receipt.name, llm_calls=0,
            scope="native lexical fallback, completed control, exact stdout, source invalidation"), indent=2))
    finally:
        invoke(["codex-daemon", "shutdown"])
    print(json.dumps(dict(passed=True, output=str(output), calls=len(runs))))


if __name__ == "__main__":
    main()
