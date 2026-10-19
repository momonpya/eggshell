#!/usr/bin/env python3
"""Qualify fresh, pasted-answer and native-continuation context with fixed responses."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from pilot_context import audit_context, observed_output, previous_answer_prompt, recorded_answer
from pilot_hook_probe import ScriptedServer, execute
from pilot_preflight import configuration
from pilot_scripted_provider import ScriptedProvider
from pilot_tasks import copy_files, digest, load_suite, write_json


PRIOR_QUESTION = "Inspect the original payload loader and summarize its failure handling."
QUESTION = "Which behavior must be preserved when adding a serialized-byte limit to the payload loader?"
ANSWER = "PILOT_RECORDED_ANSWER: Preserve deserialization through the selected serializer and BadPayload wrapping."
SOURCE_LINE = "return use_serializer.loads(payload)"


def prepare(output, name, workspace, roots, provider):
    case = output / name
    case.mkdir()
    home, temporary = case / "codex", case / "tmp"
    home.mkdir()
    temporary.mkdir()
    config = ('model = "gpt-5.6-sol"\nmodel_provider = "scripted"\n' + configuration(workspace, roots) +
              '\n[model_providers.scripted]\nname = "Local history fixture"\nbase_url = ' +
              json.dumps(provider.url) + '\nwire_api = "responses"\nrequires_openai_auth = false\n' +
              'supports_websockets = false\nrequest_max_retries = 0\nstream_max_retries = 0\nstream_idle_timeout_ms = 5000\n')
    (home / "config.toml").write_text(config)
    env = {key: value for key, value in os.environ.items()
           if key in {"PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL"}}
    env.update(CODEX_HOME=str(home), TMPDIR=str(temporary), LEAN_NUM_THREADS="1", HF_HUB_OFFLINE="1")
    return case, home, env


def initialize(server, home, workspace):
    hello = server.initialize("0.145.0")
    if Path(hello["codexHome"]) != home:
        raise ValueError("Unexpected Codex root")
    hooks = server.request("hooks/list", dict(cwds=[str(workspace)]))
    if any(row["hooks"] or row["errors"] or row["warnings"] for row in hooks["data"]):
        raise ValueError("Non-Eggshell condition has hooks")
    thread = server.request("thread/start", dict(cwd=str(workspace), permissions="pilot", approvalPolicy="never",
                            ephemeral=False, allowProviderModelFallback=False))
    if (thread["modelProvider"] != "scripted" or thread["instructionSources"] != []
            or thread["activePermissionProfile"]["id"] != "pilot" or thread["thread"].get("parentThreadId")):
        raise ValueError("Unexpected thread configuration or subagent")
    return thread


def turn(server, identity, prompt, output):
    started = server.request("turn/start", dict(threadId=identity, input=[dict(type="text", text=prompt)]))
    completed = server.wait_notification("turn/completed", lambda params:
        params["threadId"] == identity and params["turn"]["id"] == started["turn"]["id"])
    if completed["turn"]["status"] != "completed":
        raise ValueError("Scripted turn failed")
    loaded = server.request("thread/read", dict(threadId=identity, includeTurns=True))["thread"]
    write_json(output, loaded)
    if any(item["method"] == "hook/completed" for item in server.notifications):
        raise ValueError("Non-Eggshell condition ran a hook")
    return loaded, started["turn"]["id"]


def run(suite, output, runtime_roots):
    manifest = load_suite(suite)
    task = manifest["tasks"][0]
    workspace = output / "workspace"
    if any(not path.is_dir() or output.is_relative_to(path) or suite.is_relative_to(path) for path in runtime_roots):
        raise ValueError("Invalid runtime read root")
    copy_files(suite / "cases" / task["id"] / "start", workspace, task["start_hashes"])
    for name in [".tmp", ".bin"]:
        (workspace / name).mkdir()
    subprocess.run(["git", "init", "--quiet", str(workspace)], check=True, timeout=10)
    python = Path(manifest["python"])
    base = Path(subprocess.check_output([str(python), "-c", "import sys;print(sys.base_prefix)"],
                                      text=True, timeout=10).strip()).resolve()
    roots = [python.parent.parent, base, *runtime_roots]
    for name in ["pilot_history_probe.py", "pilot_context.py", "pilot_hook_probe.py", "pilot_preflight.py",
                 "pilot_scripted_provider.py", "pilot_server.py", "pilot_tasks.py"]:
        shutil.copy2(Path(__file__).with_name(name), output / name)
    command = "sed -n '240,272p' src/itsdangerous/serializer.py"
    program = "text(await tools.exec_command(" + json.dumps(dict(cmd=command, login=False, max_output_tokens=2500)) + "));"
    reports, catalogs = {}, []
    codex = shutil.which("codex")
    with ScriptedProvider(output / "provider", program) as provider:
        case, home, env = prepare(output, "same-chat", workspace, roots, provider)
        version = execute([codex, "--version"], env, workspace, output / "cli-version.json", timeout=10).stdout.strip()
        if version != "codex-cli 0.145.0":
            raise ValueError("History probe requires CLI requalification")
        write_json(output / "manifest.json", dict(cli=version, cli_launcher_sha256=digest(Path(codex).resolve()),
            suite_sha256=digest(suite / "suite.json"),
            helpers={path.name: digest(path) for path in output.glob("*.py")}, source_hashes=task["start_hashes"],
            scripted=True, pilot_model_runs=0))
        provider.begin("prior", final_text=ANSWER)
        with ScriptedServer([codex, "--strict-config", "app-server"], workspace, env, case / "rpc") as server:
            initial = initialize(server, home, workspace)
            identity = initial["thread"]["id"]
            prior, prior_turn = turn(server, identity, PRIOR_QUESTION, output / "prior-thread.json")
            answer = recorded_answer(prior, prior_turn)
            if answer != ANSWER:
                raise ValueError("Recorded answer differs from the fixed response")
            rows = [row["body"] for row in provider.requests if row["condition"] == "prior"]
            if len(rows) != 2:
                raise ValueError("Unexpected prior request count")
            prior_request = rows[-1]
            expected_output = "".join((workspace / "src/itsdangerous/serializer.py").read_text().splitlines(keepends=True)[239:272])
            observed_output(prior_request, expected_output)
            provider.begin("same-chat", final_only=True)
            continued, _ = turn(server, identity, QUESTION, case / "thread.json")
            if len(continued["turns"]) != 2:
                raise ValueError("Continuation did not retain the prior turn")
            reports["same-chat"] = dict(thread_id=identity, prior_thread_id=identity, turns=2)
            server.request("thread/unsubscribe", dict(threadId=identity))
        for condition in ["fresh", "previous-answer"]:
            case, home, env = prepare(output, condition, workspace, roots, provider)
            provider.begin(condition, final_only=True)
            with ScriptedServer([codex, "--strict-config", "app-server"], workspace, env, case / "rpc") as server:
                initial = initialize(server, home, workspace)
                current_id = initial["thread"]["id"]
                if current_id == identity:
                    raise ValueError("New-thread condition reused prior history")
                prompt = previous_answer_prompt(QUESTION, answer) if condition == "previous-answer" else QUESTION
                loaded, _ = turn(server, current_id, prompt, case / "thread.json")
                if len(loaded["turns"]) != 1:
                    raise ValueError("New-thread condition has prior native turns")
                reports[condition] = dict(thread_id=current_id, prior_thread_id=identity, turns=1)
                server.request("thread/unsubscribe", dict(threadId=current_id))
        for condition in reports:
            rows = [row["body"] for row in provider.requests if row["condition"] == condition]
            if len(rows) != 1:
                raise ValueError("Unexpected consumer request count")
            body = rows[0]
            reports[condition].update(audit_context(body, condition, QUESTION, answer, prior_request))
            catalogs.append([item for item in body["input"] if item.get("type") == "additional_tools"])
            present = SOURCE_LINE in json.dumps(body["input"])
            if present != (condition == "same-chat"):
                raise ValueError("Native source observation crossed a condition boundary")
            reports[condition]["original_observation_present"] = present
        if provider.error:
            raise ValueError(provider.error)
        if any(catalog != catalogs[0] for catalog in catalogs) or any(
                tool.get("name") == "collaboration" for item in catalogs[0] for tool in item["tools"]):
            raise ValueError("Native tool catalogs differ or expose agent tools")
        if len(provider.requests) != 5:
            raise ValueError("Unexpected total request count")
    if any(digest(workspace / name) != expected for name, expected in task["start_hashes"].items()):
        raise ValueError("Source changed")
    load_suite(suite)
    result = dict(passed=True, cases=reports, scripted_turns=4, local_http_requests=5,
                  generation_model_calls=0, pilot_model_runs=0, seed_acquisitions=0,
                  source_files_unchanged=len(task["start_hashes"]), catalogs_identical=True,
                  scope="non-Eggshell context transport; not a model outcome or study seed")
    write_json(output / "result.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["suite", "output"]:
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--runtime-read-root", type=Path, action="append", default=[])
    args = parser.parse_args()
    output = args.output.resolve()
    try:
        output.mkdir(parents=True, exist_ok=False, mode=0o700)
    except FileExistsError:
        print("History probe output exists; previous evidence retained", file=sys.stderr)
        return 2
    try:
        result = run(args.suite.resolve(), output, [path.resolve() for path in args.runtime_read_root])
    except Exception as error:
        write_json(output / "failure.json", dict(error=f"{type(error).__name__}: {error}", scripted=True, pilot_model_runs=0))
        print(f"History probe failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(dict(passed=True, cases=list(result["cases"]), pilot_model_runs=0)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
