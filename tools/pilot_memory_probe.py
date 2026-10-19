#!/usr/bin/env python3
"""Record, warm and deliver a scripted observation through independent native chats."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import errno
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import time

from pilot_hook_probe import ScriptedServer, execute, tree_hashes, vetted_hooks
from pilot_preflight import configuration
from pilot_scripted_provider import ScriptedProvider
from pilot_server import Server
from pilot_tasks import copy_files, digest, load_suite, write_json
from owned_daemon import shutdown_owned


QUESTION = "Explain how Serializer.load_payload decodes payload bytes and wraps deserialization failures as BadPayload."
MARKER = "return use_serializer.loads(payload)"


def message_texts(body):
    return [part["text"] for item in body["input"] if item.get("type") == "message"
            for part in item.get("content", []) if part.get("type") == "input_text"]


def check_delivery(body, context, expected):
    if any(item.get("type") in {"custom_tool_call", "custom_tool_call_output", "function_call",
                               "function_call_output"} for item in body["input"]):
        raise ValueError("Consumer inherited native tool history or performed a tool call")
    texts = message_texts(body)
    present = any(MARKER in text for text in texts)
    if present != expected:
        raise ValueError("Unexpected saved-body presence in the first consumer request")
    if expected and (not context or MARKER not in context or "EGGSHELL PRIOR WORK" not in context
                     or not any(context in text for text in texts)):
        raise ValueError("Published hook context did not reach the first consumer request")


def snapshot(directory):
    result = {}
    for path in [directory, *sorted(directory.rglob("*"))]:
        if path.is_symlink():
            raise ValueError("Unexpected DB symlink")
        meta = path.stat()
        row = dict(mode=stat.S_IMODE(meta.st_mode), mtime_ns=meta.st_mtime_ns, flags=meta.st_flags)
        if path.is_file():
            row.update(size=meta.st_size, sha256=digest(path))
        result[str(path.relative_to(directory))] = row
    return result


@contextmanager
def protected_databases(databases):
    if sys.platform != "darwin":
        raise ValueError("This qualification requires macOS immutable-file protection")
    paths = [path for database in databases for path in [database, *sorted(database.rglob("*"))]]
    if any(path.is_symlink() for path in paths):
        raise ValueError("Refusing to protect a DB symlink")
    original = {path: path.stat().st_flags for path in paths}
    try:
        for path in reversed(paths):
            os.chflags(path, original[path] | stat.UF_IMMUTABLE)
        for database in databases:
            try:
                with (database / "must-not-write").open("w") as stream:
                    stream.write("invalid")
            except OSError as error:
                if error.errno not in {errno.EPERM, errno.EACCES, errno.EROFS}:
                    raise
            else:
                raise ValueError("DB write protection did not reject a write")
        yield
    finally:
        for path in paths:
            os.chflags(path, original[path])


def prepare_case(output, label, workspace, database, prefix, source, roots, provider, profile, numerical=True):
    case = output / label
    case.mkdir()
    config_root, temporary = case / "codex", case / "tmp"
    config_root.mkdir()
    temporary.mkdir()
    egg_config = case / "eggshell.toml"
    text = 'default = ' + json.dumps(profile) + "\n"
    if not numerical:
        text += "semantic_matcher = false\n"
    text += '[eggs]\nprior = ' + json.dumps(str(database)) + '\n[profiles.work]\nread = ["prior"]\nwrite = "prior"\n[profiles.private]\nread = ["prior"]\n'
    egg_config.write_text(text)
    config = configuration(workspace, roots)
    if label != "fresh":
        config = config.replace("plugins = false", "plugins = true").replace("hooks = false", "hooks = true")
    config_file = config_root / "config.toml"
    config_file.write_text(config)
    env = {key: value for key, value in os.environ.items()
           if key in {"PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL"}}
    env.update(CODEX_HOME=str(config_root), TMPDIR=str(temporary), EGGSHELL_PREFIX=str(prefix),
               EGGSHELL_DATA_ROOT=str(case / "data"), EGGSHELL_CONFIG=str(egg_config),
               HF_HUB_OFFLINE="1", LEAN_NUM_THREADS="1")
    codex = shutil.which("codex")
    if label != "fresh":
        execute([codex, "plugin", "marketplace", "add", prefix, "--json"], env, workspace, case / "marketplace.json")
        execute([codex, "plugin", "add", "eggshell@eggshell", "--json"], env, workspace, case / "plugin.json")
        with Server([codex, "--strict-config", "app-server"], workspace, env, case / "discovery") as server:
            server.initialize("0.145.0")
            discovery = server.request("hooks/list", dict(cwds=[str(workspace)]))
        hooks, _ = vetted_hooks(discovery, config_root, prefix, source)
        write_json(case / "hooks-before-trust.json", discovery)
        trust = "\n".join("[hooks.state." + json.dumps(hook["key"]) +
                          "]\nenabled = true\ntrusted_hash = " + json.dumps(hook["currentHash"]) for hook in hooks)
        config = config_file.read_text() + "\n" + trust + "\n"
    config = 'model = "gpt-5.6-sol"\nmodel_provider = "scripted"\n' + config
    config += ('\n[model_providers.scripted]\nname = "Local scripted fixture"\nbase_url = ' +
               json.dumps(provider.url) + '\nwire_api = "responses"\nrequires_openai_auth = false\n' +
               'supports_websockets = false\nrequest_max_retries = 0\nstream_max_retries = 0\nstream_idle_timeout_ms = 5000\n')
    config_file.write_text(config)
    return dict(case=case, env=env, config_root=config_root)


def native_turn(info, workspace, provider, label, prompt, keep=False):
    provider.begin(label, final_only=not keep)
    env, case = info["env"], info["case"]
    binary = Path(env["EGGSHELL_PREFIX"]) / "libexec/eggshell"
    try:
        with ScriptedServer([shutil.which("codex"), "--strict-config", "app-server"], workspace, env, case / "rpc") as server:
            hello = server.initialize("0.145.0")
            if Path(hello["codexHome"]) != info["config_root"]:
                raise ValueError("Unexpected Codex home")
            listed = server.request("hooks/list", dict(cwds=[str(workspace)]))
            if label == "fresh":
                if any(row["hooks"] or row["errors"] or row["warnings"] for row in listed["data"]):
                    raise ValueError("Fresh condition has hooks")
            elif any(hook["trustStatus"] != "trusted" for row in listed["data"] for hook in row["hooks"]):
                raise ValueError("Reviewed hook is not trusted")
            thread = server.request("thread/start", dict(cwd=str(workspace), permissions="pilot",
                approvalPolicy="never", ephemeral=False, allowProviderModelFallback=False))
            if (thread["modelProvider"] != "scripted" or thread["instructionSources"] != []
                    or thread["activePermissionProfile"]["id"] != "pilot"):
                raise ValueError("Unexpected provider, instructions or command profile")
            identity = thread["thread"]["id"]
            turn = server.request("turn/start", dict(threadId=identity, input=[dict(type="text", text=prompt)]))
            completed = server.wait_notification("turn/completed", lambda params:
                params["threadId"] == identity and params["turn"]["id"] == turn["turn"]["id"])
            if completed["turn"]["status"] != "completed":
                raise ValueError("Scripted turn failed")
            write_json(case / "completed.json", completed)
            write_json(case / "thread.json", thread)
            if keep:
                execute([binary, "egg", "keep"], dict(env, CODEX_THREAD_ID=identity),
                        workspace, case / "keep.json")
            server.request("thread/unsubscribe", dict(threadId=identity))
    finally:
        if label != "fresh":
            execute([binary, "codex-daemon", "shutdown"], env, workspace, case / "shutdown.json", timeout=15)
    rows = [row["body"] for row in provider.requests if row["condition"] == label]
    if len(rows) != (2 if keep else 1):
        raise ValueError("Unexpected scripted request count")
    catalog = [item for item in rows[0]["input"] if item.get("type") == "additional_tools"]
    if any(tool.get("name") == "collaboration" for item in catalog for tool in item["tools"]):
        raise ValueError("Agent tool namespace is exposed")
    return identity, rows[0], hashlib.sha256(json.dumps(catalog, sort_keys=True).encode()).hexdigest()


def warm(binary, info, workspace, database, filename):
    result = execute([binary, "egg", "warm", database], info["env"], workspace, info["case"] / filename)
    row = json.loads(result.stdout)["databases"][0]
    after = row["after"]
    if after["windows"] <= 0 or after["valid"] != after["windows"] or after["missing"] or after["invalid"]:
        raise ValueError("Warm coverage is incomplete")
    return row


def delivery(info, identity, body, windows, semantic):
    receipts = []
    for directory in (info["case"] / "data/receipts").iterdir():
        request = json.loads((directory / "request.json").read_text())["data"]
        if request.get("session") == identity and request.get("event") == "UserPromptSubmit":
            receipts.append(directory)
    if len(receipts) != 1:
        raise ValueError("Missing or duplicate prompt receipt")
    directory = receipts[0]
    published = json.loads((directory / "published.json").read_text())["data"]
    raw = published["output"].encode()
    if (published["sha256"] != hashlib.sha256(raw).hexdigest() or published["bytes"] != len(raw)
            or not published["replyComplete"] or published["flushedMs"] > published["deadlineMs"]):
        raise ValueError("Unconfirmed, inconsistent or late stdout")
    context = json.loads(published["output"])["hookSpecificOutput"]["additionalContext"]
    check_delivery(body, context, True)
    search = json.loads((directory / "search.json").read_text())["data"]
    numerical = [json.loads(path.read_text())["data"] for path in sorted(directory.glob("numerical-*.json"))]
    discovery = [row for row in numerical if row["corpus"]["purpose"] == "discovery"]
    complete = any(row["status"] == "completed" and row["corpus"]["windowReferences"] == windows
                   and row["counters"]["scoredWindows"] == windows
                   and row["counters"]["source"] == dict(absent=0, hit=windows, unusable=0)
                   and row["counters"]["encoder"]["sourceEncodeUs"] == 0 for row in discovery)
    if semantic:
        if search["trace"]["semantic"] != "completed" or not complete:
            raise ValueError("Semantic discovery did not score all warm windows")
    elif numerical or search["trace"]["semantic"] != "notRequested":
        raise ValueError("Lexical-only condition invoked numerical search")
    return dict(receipt=directory.name, stdout_sha256=published["sha256"], stdout_bytes=len(raw),
                search=search, numerical=numerical, all_warm_windows_scored=complete if semantic else None,
                body_in_first_request=True)


def drain_indexes(binary, info, workspace, database):
    def tickets():
        return list(database.glob("derived/*/indexes/**/*.json"))
    if not tickets():
        return 0
    before = len(tickets())
    head = digest(database / "head")
    write_json(info["case"] / "before-index-drain.json", dict(head_sha256=head, tickets=before))
    with (info["case"] / "index-drain.log").open("w") as log:
        process = subprocess.Popen([str(binary), "codex-daemon", "pilot-index-recovery"],
                                   env=info["env"], cwd=workspace, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 30
            while tickets():
                if process.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError("Index recovery exited or timed out")
                time.sleep(0.05)
        finally:
            shutdown_owned(process, binary, info["env"], workspace,
                           info["case"] / "index-drain-shutdown.json")
    if process.returncode or digest(database / "head") != head:
        raise ValueError("Index recovery failed or changed the graph head")
    return before


def run(qualification, suite, source, output, runtime_roots):
    if sys.platform != "darwin":
        raise ValueError("This fixture qualifies macOS immutable DB protection")
    sealed = json.loads((qualification / "manifest.json").read_text())
    qualified = json.loads((qualification / "result.json").read_text())
    prefix = qualification / "prefix"
    binary = prefix / "libexec/eggshell"
    if not qualified["passed"] or digest(binary) != qualified["candidate_sha256"] or digest(binary) != digest(source / ".lake/build/bin/eggshell"):
        raise ValueError("Qualified runtime differs from the current candidate")
    for name, expected in sealed["helpers"].items():
        if digest(qualification / name) != expected:
            raise ValueError("Original qualification helper changed")
    prefix_before = tree_hashes(prefix)
    manifest = load_suite(suite)
    task = manifest["tasks"][0]
    workspace = output / "workspace"
    copy_files(suite / "cases" / task["id"] / "start", workspace, task["start_hashes"])
    for name in [".tmp", ".bin"]:
        (workspace / name).mkdir()
    subprocess.run(["git", "init", "--quiet", str(workspace)], check=True, timeout=10)
    python = Path(manifest["python"])
    base = Path(subprocess.check_output([str(python), "-c", "import sys;print(sys.base_prefix)"], text=True).strip()).resolve()
    roots = [python.parent.parent, base, *runtime_roots]
    if any(output.is_relative_to(path) or suite.is_relative_to(path) or not path.is_dir() for path in runtime_roots):
        raise ValueError("Invalid runtime read root")
    for name in ["pilot_memory_probe.py", "pilot_hook_probe.py", "pilot_preflight.py",
                 "pilot_scripted_provider.py", "pilot_server.py", "pilot_tasks.py", "owned_daemon.py"]:
        shutil.copy2(Path(__file__).with_name(name), output / name)
    write_json(output / "manifest.json", dict(candidate_sha256=digest(binary), suite_sha256=digest(suite / "suite.json"),
        source_hashes=task["start_hashes"], runtime_prefix=str(prefix),
        helpers={path.name: digest(path) for path in output.glob("*.py")}, scripted=True, pilot_model_runs=0))
    database, graph_copy = output / "observations.egg", output / "graph-only.egg"
    program = 'text(await tools.exec_command({cmd:"sed -n \\\'240,272p\\\' src/itsdangerous/serializer.py",login:false,max_output_tokens:2500}));'
    reports = {}
    with ScriptedProvider(output / "provider", program) as provider:
        writer = prepare_case(output, "writer", workspace, database, prefix, source, roots, provider, "work")
        version = execute([shutil.which("codex"), "--version"], writer["env"], workspace, output / "cli-version.json", timeout=10).stdout.strip()
        if version != "codex-cli 0.145.0":
            raise ValueError("This fixture requires CLI requalification")
        writer_id, _, catalog = native_turn(writer, workspace, provider, "writer",
            "Inspect Serializer.load_payload and record its original decoding and BadPayload behavior.", keep=True)
        graph = execute([binary, "inspect-graph", database], writer["env"], workspace, writer["case"] / "graph.json")
        if MARKER not in graph.stdout:
            raise ValueError("The original native tool body was not committed")
        warmed = warm(binary, writer, workspace, database, "warm.json")
        drained = drain_indexes(binary, writer, workspace, database)
        identity = json.loads((database / "head").read_text())["identity"]
        windows = warmed["after"]["windows"]
        base_files = {}
        for path in database.iterdir():
            if path.name == "derived" and path.is_dir():
                continue
            if not path.is_file() or path.is_symlink():
                raise ValueError("Unexpected source DB layout")
            base_files[path.name] = digest(path)
        copy_files(database, graph_copy, base_files)
        if json.loads((graph_copy / "head").read_text())["identity"] != identity:
            raise ValueError("Graph-only copy changed DB identity")
        write_json(output / "saved-snapshot.json", dict(identity=identity, graph_files=base_files, warm=warmed,
                   index_tickets_remaining=0, drained=drained, writer_thread=writer_id))
        with protected_databases([database, graph_copy]):
            protected_before = {path.name: snapshot(path) for path in [database, graph_copy]}
            write_json(output / "protected-before.json", protected_before)
            for label, db, numerical in [("fresh", database, False), ("semantic-primary", database, True),
                                         ("semantic-private", graph_copy, True), ("lexical", database, False)]:
                info = prepare_case(output, label, workspace, db, prefix, source, roots, provider, "private", numerical)
                warm_row = None
                if numerical:
                    warm_row = warm(binary, info, workspace, db, "warm.json")
                    if (label == "semantic-primary" and warm_row["requested"] != 0 or
                            label == "semantic-private" and warm_row["requested"] != windows):
                        raise ValueError("Unexpected primary versus private-overlay warming")
                    doctor = execute([binary, "egg", "doctor"], info["env"], workspace, info["case"] / "doctor.json")
                    status = json.loads(doctor.stdout)
                    if status["memory"] != "read-only" or status["databases"][0]["state"] != "warm":
                        raise ValueError("Read-only DB is not reported warm")
                reader_id, body, reader_catalog = native_turn(info, workspace, provider, label, QUESTION)
                if reader_id == writer_id or reader_catalog != catalog:
                    raise ValueError("Native history or tool catalog differs unexpectedly")
                if label == "fresh":
                    check_delivery(body, None, False)
                    evidence = dict(body_in_first_request=False)
                else:
                    evidence = delivery(info, reader_id, body, windows, numerical)
                if {path.name: snapshot(path) for path in [database, graph_copy]} != protected_before:
                    raise ValueError("Reading or warming changed a protected shared DB")
                queries = list((info["case"] / "data/queries/vectors").glob("*.json"))
                if any("text" in json.loads(path.read_text()) for path in queries):
                    raise ValueError("Query vectors retained plaintext")
                reports[label] = dict(**evidence, warm=warm_row, reader_thread=reader_id, query_vectors=len(queries),
                                      native_tool_history=False, protected_databases_unchanged=True)
            write_json(output / "protected-after.json", {path.name: snapshot(path) for path in [database, graph_copy]})
        if provider.error:
            raise ValueError(provider.error)
    if tree_hashes(prefix) != prefix_before:
        raise ValueError("The qualified runtime prefix changed")
    if any(digest(workspace / name) != expected for name, expected in task["start_hashes"].items()):
        raise ValueError("Subject source changed")
    load_suite(suite)
    result = dict(passed=True, database_identity=identity, windows=windows, cases=reports,
                  scripted_turns=5, local_http_requests=6, generation_model_calls=0, pilot_model_runs=0,
                  seed_acquisitions=0, restored_db_flags=True, source_files_unchanged=len(task["start_hashes"]),
                  qualified_runtime_unchanged=True, scope="scripted saved-observation transport; not a study seed or model outcome")
    write_json(output / "result.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["qualification", "suite", "source", "output"]:
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--runtime-read-root", type=Path, action="append", default=[])
    args = parser.parse_args()
    output = args.output.resolve()
    try:
        output.mkdir(parents=True, exist_ok=False, mode=0o700)
    except FileExistsError:
        print("Memory probe output exists; previous evidence retained", file=sys.stderr)
        return 2
    try:
        result = run(args.qualification.resolve(), args.suite.resolve(), args.source.resolve(), output,
                     [path.resolve() for path in args.runtime_read_root])
    except Exception as error:
        write_json(output / "failure.json", dict(error=f"{type(error).__name__}: {error}", scripted=True, pilot_model_runs=0))
        print(f"Memory probe failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(dict(passed=True, windows=result["windows"], cases=list(result["cases"]), pilot_model_runs=0)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
