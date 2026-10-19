#!/usr/bin/env python3
"""Restore independent native continuations from one frozen scripted seed."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

from pilot_context import recorded_answer, text_parts
from pilot_history_probe import prepare, turn
from pilot_hook_probe import ScriptedServer, execute
from pilot_memory_probe import protected_databases, snapshot
from pilot_scripted_provider import ScriptedProvider
from pilot_seed import freeze_fixture, verify
from pilot_tasks import digest, load_suite, write_json


class ForkServer(ScriptedServer):
    allowed_methods = ScriptedServer.allowed_methods | {"thread/fork"}


QUESTION = "Which behavior must be preserved when adding a serialized-byte limit to the payload loader?"


def run(memory, suite, output, runtime_roots):
    manifest = load_suite(suite)
    checkpoint = freeze_fixture(memory, output / "seed")
    bundle = output / "seed"
    expected_seed = digest(bundle / "seed.json")
    workspace = Path(checkpoint["workspace"])
    if checkpoint["source_hashes"] != manifest["tasks"][0]["start_hashes"]:
        raise ValueError("Seed source snapshot differs from the frozen task start")
    if any(not path.is_dir() or output.is_relative_to(path) or memory.is_relative_to(path)
           or suite.is_relative_to(path) for path in runtime_roots):
        raise ValueError("Invalid runtime read root")
    python = Path(manifest["python"])
    base = Path(subprocess.check_output([str(python), "-c", "import sys;print(sys.base_prefix)"],
                                      text=True, timeout=10).strip()).resolve()
    roots = [python.parent.parent, base, *runtime_roots]
    qualified_runtime = json.loads((memory / "manifest.json").read_text())
    runtime = Path(qualified_runtime["runtime_prefix"])
    if digest(runtime / "libexec/eggshell") != qualified_runtime["candidate_sha256"]:
        raise ValueError("Seed doctor runtime changed")
    for name in ["pilot_seed.py", "pilot_seed_probe.py", "pilot_context.py", "pilot_history_probe.py", "pilot_hook_probe.py",
                 "pilot_memory_probe.py", "pilot_preflight.py", "pilot_scripted_provider.py", "pilot_server.py", "pilot_tasks.py"]:
        shutil.copy2(Path(__file__).with_name(name), output / name)
    write_json(output / "manifest.json", dict(seed_manifest_sha256=digest(bundle / "seed.json"),
        suite_sha256=digest(suite / "suite.json"), helpers={p.name:digest(p) for p in output.glob("*.py")},
        study_seed=False, pilot_model_runs=0))
    source_request = json.loads((memory / "provider/request-2.json").read_text())["body"]
    answer = (bundle / "answer.txt").read_text()
    reports, catalogs = [], []
    with protected_databases([bundle]), ScriptedProvider(output / "provider", "") as provider:
        protected_before = snapshot(bundle)
        write_json(output / "protected-before.json", protected_before)
        for repetition in range(1, 3):
            verify(bundle, expected_seed)
            label = f"restore-{repetition}"
            case, home, env = prepare(output, label, workspace, roots, provider)
            seed_config = case / "seed-eggshell.toml"
            seed_config.write_text('default = "private"\n[eggs]\nprior = ' +
                json.dumps(str(bundle / "observations.egg")) + '\n[profiles.private]\nread = ["prior"]\n')
            diagnostic_env = dict(env, EGGSHELL_PREFIX=str(runtime), EGGSHELL_DATA_ROOT=str(case / "data"),
                                  EGGSHELL_CONFIG=str(seed_config))
            doctor = execute([runtime / "libexec/eggshell", "egg", "doctor"], diagnostic_env,
                             workspace, case / "doctor.json")
            status = json.loads(doctor.stdout)
            coverage = status["databases"][0]["coverage"]
            if (status["memory"] != "read-only" or status["databases"][0]["state"] != "warm"
                    or coverage["valid"] != coverage["windows"] or coverage["missing"] or coverage["invalid"]
                    or coverage["database"]["database"] != checkpoint["database_identity"]):
                raise ValueError("Restored seed DB is not fully warm and read-only")
            version = execute([shutil.which("codex"), "--version"], env, workspace, case / "cli-version.json", timeout=10).stdout.strip()
            if version != "codex-cli 0.145.0":
                raise ValueError("Frozen history fork requires CLI requalification")
            provider.begin(label, final_only=True, final_text=f"SCRIPTED RESTORE RESULT {repetition}")
            with ForkServer([shutil.which("codex"), "--strict-config", "app-server"], workspace, env, case / "rpc") as server:
                hello = server.initialize("0.145.0")
                if Path(hello["codexHome"]) != home:
                    raise ValueError("Unexpected private Codex root")
                hooks = server.request("hooks/list", dict(cwds=[str(workspace)]))
                if any(row["hooks"] or row["errors"] or row["warnings"] for row in hooks["data"]):
                    raise ValueError("Restored continuation has ambient hooks")
                forked = server.request("thread/fork", dict(threadId=checkpoint["thread_id"],
                    path=str(bundle / "native.jsonl"), lastTurnId=checkpoint["last_turn_id"],
                    cwd=str(workspace), permissions="pilot", approvalPolicy="never", model="gpt-5.6-sol",
                    modelProvider="scripted", ephemeral=False, deferGoalContinuation=True))
                thread = forked["thread"]
                identity = thread["id"]
                if (identity == checkpoint["thread_id"] or thread["forkedFromId"] != checkpoint["thread_id"]
                        or thread.get("parentThreadId") or not Path(thread["path"]).is_relative_to(home)
                        or forked["activePermissionProfile"]["id"] != "pilot"):
                    raise ValueError("Fork did not create an independent ordinary thread in its private root")
                if len(thread["turns"]) != 1 or recorded_answer(thread, checkpoint["last_turn_id"]) != answer:
                    raise ValueError("Fork did not restore the exact prior completed turn and answer")
                write_json(case / "fork.json", forked)
                loaded, trial_turn = turn(server, identity, QUESTION, case / "thread.json")
                if len(loaded["turns"]) != 2:
                    raise ValueError("Restored trial inherited another trial's history")
                server.request("thread/unsubscribe", dict(threadId=identity))
            rows = [r["body"] for r in provider.requests if r["condition"] == label]
            if len(rows) != 1:
                raise ValueError("Restored consumer made an unplanned request")
            body = rows[0]
            prefix = source_request["input"]
            if body["input"][:len(prefix)] != prefix:
                raise ValueError("Native source question/tool observations changed during restoration")
            tail = body["input"][len(prefix):]
            if (not tail or tail[0].get("role") != "assistant" or text_parts(tail[0]) != [answer]
                    or text_parts(tail[-1]) != [QUESTION] or tail[-1].get("role") != "user"):
                raise ValueError("Restored native answer/current question boundary changed")
            if any("SCRIPTED RESTORE RESULT" in json.dumps(item) for item in body["input"]):
                raise ValueError("A previous repetition leaked into the restored input")
            catalogs.append([item for item in body["input"] if item.get("type") == "additional_tools"])
            if snapshot(bundle) != protected_before:
                raise ValueError("A continuation modified the frozen seed")
            reports.append(dict(repetition=repetition, thread_id=identity, trial_turn_id=trial_turn,
                prior_turn_id=checkpoint["last_turn_id"], restored_native_prefix=True,
                loaded_turns=2, seed_unchanged=True, request_items=len(body["input"]), warm_coverage=coverage))
        if provider.error or catalogs[0] != catalogs[1] or any(
                t.get("name") == "collaboration" for c in catalogs for i in c for t in i["tools"]):
            raise ValueError("Provider error or changed/exposed agent catalog")
        write_json(output / "protected-after.json", snapshot(bundle))
    if len({row["thread_id"] for row in reports}) != 2:
        raise ValueError("Repetitions reused the same mutable native thread")
    verify(bundle, expected_seed)
    if any(digest(workspace / name) != h for name,h in checkpoint["source_hashes"].items()):
        raise ValueError("Source workspace changed")
    result = dict(passed=True, restores=reports, common_history_sha256=checkpoint["history_sha256"],
        common_answer_sha256=checkpoint["answer_sha256"], database_identity=checkpoint["database_identity"],
        scripted_turns=2, local_http_requests=2, pilot_model_runs=0, seed_acquisitions=0, study_seed=False,
        source_files_unchanged=50, scope="frozen scripted seed restoration; not a model outcome or usage comparison")
    write_json(output / "result.json", result)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ["memory", "suite", "output"]:
        parser.add_argument("--"+name, required=True, type=Path)
    parser.add_argument("--runtime-read-root", type=Path, action="append", default=[])
    args=parser.parse_args()
    output=args.output.resolve()
    try:
        output.mkdir(parents=True, exist_ok=False, mode=0o700)
    except FileExistsError:
        print("Seed probe output exists; previous evidence retained", file=sys.stderr)
        return 2
    try:
        result=run(args.memory.resolve(), args.suite.resolve(), output, [p.resolve() for p in args.runtime_read_root])
    except Exception as error:
        write_json(output/"failure.json", dict(error=f"{type(error).__name__}: {error}", study_seed=False))
        print(f"Seed probe failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(dict(passed=result["passed"], restores=len(result["restores"]), pilot_model_runs=0)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
