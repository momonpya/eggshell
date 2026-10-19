#!/usr/bin/env python3
"""Qualify native hooks with a local scripted provider; never run a real model."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

from pilot_preflight import configuration
from pilot_scripted_provider import ScriptedProvider
from pilot_server import Server
from pilot_tasks import copy_files, digest, load_suite, write_json


class ScriptedServer(Server):
    allowed_methods = Server.allowed_methods | {"thread/start", "thread/read", "thread/unsubscribe", "turn/start"}
    allow_turn_events = True


def tree_hashes(root):
    result = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            result[str(path.relative_to(root))] = dict(link=os.readlink(path))
        elif path.is_file():
            hasher = hashlib.sha256()
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    hasher.update(chunk)
            result[str(path.relative_to(root))] = dict(sha256=hasher.hexdigest())
    return result


def vetted_hooks(result, config_root, prefix, source):
    entries = result["data"]
    if len(entries) != 1 or entries[0]["errors"] or entries[0]["warnings"]:
        raise ValueError("Unexpected hook discovery result")
    hooks = entries[0]["hooks"]
    expected = ["postCompact", "postToolUse", "preToolUse", "sessionEnd", "sessionStart",
                "sessionStart", "stop", "userPromptSubmit"]
    if sorted(hook["eventName"] for hook in hooks) != expected:
        raise ValueError("Unexpected installed hook set")
    cached_roots = set()
    for hook in hooks:
        path = Path(hook["sourcePath"])
        cached = path.parents[1]
        if (not cached.is_relative_to(config_root / "plugins/cache") or
                path != cached / "hooks/hooks.json" or
                hook["pluginId"] != "eggshell@eggshell" or hook["handlerType"] != "command" or
                hook["source"] != "plugin" or not hook["enabled"]):
            raise ValueError("Hook is not from the isolated command plugin")
        if json.loads(path.read_text()) != json.loads((source / "plugins/eggshell/hooks/hooks.json").read_text()):
            raise ValueError("Cached hook configuration differs from reviewed source")
        for name in ["bin/egg", "bin/eggshelld", ".codex-plugin/plugin.json"]:
            if (cached / name).read_bytes() != (prefix / "plugins/eggshell" / name).read_bytes():
                raise ValueError("Cached plugin payload differs from the installed payload")
        command = hook["command"]
        launcher = json.dumps(str(cached / "bin/egg"))
        if command not in {launcher + " codex-start", launcher + " codex-hook", launcher + " codex-hook fast"}:
            raise ValueError("Unexpected hook command")
        cached_roots.add(str(cached))
    return hooks, sorted(cached_roots)


def execute(command, env, cwd, output, timeout=60):
    result = subprocess.run(list(map(str, command)), env=env, cwd=cwd, capture_output=True,
                            text=True, timeout=timeout)
    write_json(output, dict(command=list(map(str, command)), exit_code=result.returncode,
                            stdout=result.stdout, stderr=result.stderr))
    if result.returncode:
        raise RuntimeError(f"Command failed; see {output}")
    return result


def native_read_result(body, source_sha):
    results = []
    for item in body["input"]:
        if item.get("type") != "custom_tool_call_output":
            continue
        for part in item["output"]:
            if part.get("type") != "input_text":
                continue
            try:
                value = json.loads(part["text"])
            except (ValueError, TypeError):
                continue
            if isinstance(value, dict) and "exit_code" in value and "output" in value:
                results.append(value)
    expected = ["PILOT_NATIVE_READ:" + source_sha, "PILOT_OUTSIDE_READ_DENIED"]
    if len(results) != 1 or results[0]["exit_code"] != 0 or results[0]["output"].splitlines() != expected:
        raise ValueError("Native read/boundary output did not reach the next request")
    return results[0]["output"]


def run(suite, source, assets, output, runtime_roots):
    manifest = load_suite(suite)
    task = manifest["tasks"][0]
    start = suite / "cases" / task["id"] / "start"
    workspace, prefix = output / "workspace", output / "prefix"
    copy_files(start, workspace, task["start_hashes"])
    for name in [".tmp", ".bin"]:
        (workspace / name).mkdir()
    (workspace / ".eggshell.toml").write_text('default = "private"\n[eggs]\nprior = ".eggs/prior.egg"\n[profiles.private]\nread = ["prior"]\n')
    subprocess.run(["git", "init", "--quiet", str(workspace)], check=True, timeout=10)
    outside = output / "outside-canary"
    outside.write_text("outside-canary\n")
    (workspace / ".outside-link").symlink_to(outside)
    python = Path(manifest["python"])
    python_base = Path(subprocess.check_output([str(python), "-c", "import sys;print(sys.base_prefix)"],
                                              text=True, timeout=10).strip()).resolve()
    for path in runtime_roots:
        if not path.is_dir() or output.is_relative_to(path) or suite.is_relative_to(path):
            raise ValueError("Runtime read root overlaps experiment data")
    for name in ["pilot_hook_probe.py", "pilot_scripted_provider.py", "pilot_server.py",
                 "pilot_preflight.py", "pilot_tasks.py"]:
        shutil.copy2(Path(__file__).with_name(name), output / name)
    asset_names = ["fastembed-0.8.0", "models", "fastembed-0.8.0.model-ready"]
    asset_before = {name: tree_hashes(assets / name) if (assets / name).is_dir()
                    else digest(assets / name) for name in asset_names}
    minilm = prefix / "share/eggshell/minilm"
    minilm.mkdir(parents=True)
    for name in asset_names:
        if sys.platform == "darwin":
            subprocess.run(["/bin/cp", "-cR", str(assets / name), str(minilm / name)], check=True, timeout=60)
        elif (assets / name).is_dir():
            shutil.copytree(assets / name, minilm / name, symlinks=True)
        else:
            shutil.copy2(assets / name, minilm / name)
    binary = source / ".lake/build/bin/eggshell"
    codex = Path(shutil.which("codex")).absolute()
    environment = {key: value for key, value in os.environ.items()
                   if key in {"PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL"}}
    environment.update(EGGSHELL_PREFIX=str(prefix), HF_HUB_OFFLINE="1", LEAN_NUM_THREADS="1")
    roots = [python.parent.parent, python_base, *runtime_roots]
    conditions = {}
    for name in ["fresh", "eggshell"]:
        case = output / name
        case.mkdir()
        config_root, temp = case / "codex", case / "tmp"
        config_root.mkdir()
        temp.mkdir()
        config = configuration(workspace, roots)
        if name == "eggshell":
            config = config.replace("plugins = false", "plugins = true").replace("hooks = false", "hooks = true")
        (config_root / "config.toml").write_text(config)
        env = dict(environment, CODEX_HOME=str(config_root), TMPDIR=str(temp), EGGSHELL_DATA_ROOT=str(case / "data"))
        conditions[name] = dict(case=case, config_root=config_root, env=env)
    egg = conditions["eggshell"]
    version = execute([codex, "--version"], egg["env"], workspace, output / "cli-version.json", timeout=10).stdout.strip()
    if version != "codex-cli 0.145.0":
        raise ValueError("Scripted hook probe needs requalification for this CLI")
    write_json(output / "assets-before.json", asset_before)
    write_json(output / "manifest.json", dict(cli=version, cli_launcher_sha256=digest(codex.resolve()),
        candidate_sha256=digest(binary), source_hashes=task["start_hashes"], suite_sha256=digest(suite / "suite.json"),
        helpers={name: digest(output / name) for name in ["pilot_hook_probe.py", "pilot_scripted_provider.py",
                 "pilot_server.py", "pilot_preflight.py", "pilot_tasks.py"]},
        asset_manifest_sha256=digest(output / "assets-before.json"), scripted=True, pilot_model_runs=0))
    execute([binary, "install", "codex"], egg["env"], workspace, egg["case"] / "install.json")
    if digest(prefix / "libexec/eggshell") != digest(binary):
        raise ValueError("Installed runtime is not the selected candidate")
    with Server([str(codex), "--strict-config", "app-server"], workspace, egg["env"], egg["case"] / "discovery") as server:
        server.initialize("0.145.0")
        discovery = server.request("hooks/list", dict(cwds=[str(workspace)]))
    hooks, cached = vetted_hooks(discovery, egg["config_root"], prefix, source)
    write_json(egg["case"] / "hooks-before-trust.json", discovery)
    config_file = egg["config_root"] / "config.toml"
    shutil.copy2(config_file, egg["case"] / "config-before-trust.toml")
    trust = "\n".join("[hooks.state." + json.dumps(hook["key"]) + "]\nenabled = true\ntrusted_hash = " +
                      json.dumps(hook["currentHash"]) for hook in hooks)
    config_file.write_text(config_file.read_text() + "\n" + trust + "\n")
    source_sha = digest(workspace / "src/itsdangerous/serializer.py")
    python_code = f'''import errno,hashlib,json,pathlib
p=pathlib.Path('src/itsdangerous/serializer.py')
print('PILOT_NATIVE_READ:'+hashlib.sha256(p.read_bytes()).hexdigest())
try:
 pathlib.Path({str(outside)!r}).read_bytes()
 print('PILOT_OUTSIDE_READ_ALLOWED')
except OSError as error:
 print('PILOT_OUTSIDE_READ_DENIED' if error.errno in (errno.EPERM,errno.EACCES) else 'PILOT_UNEXPECTED_ERROR')
'''
    command = shlex.join([str(python), "-c", python_code])
    inside_patch = "*** Begin Patch\n*** Add File: .pilot-edit\n+inside-canary\n*** End Patch\n"
    outside_patch = f"*** Begin Patch\n*** Update File: {outside}\n@@\n-outside-canary\n+forbidden-write\n*** End Patch\n"
    program = ("text(await tools.exec_command(" + json.dumps(dict(cmd=command, login=False, max_output_tokens=1000)) + "));\n" +
               "text(await tools.apply_patch(" + json.dumps(inside_patch) + "));\n" +
               "try { text(await tools.apply_patch(" + json.dumps(outside_patch) + ")); } catch(e) { text(String(e)); }\n")
    reports = {}
    try:
        with ScriptedProvider(output / "provider", program) as provider:
            for name, info in conditions.items():
                (workspace / ".pilot-edit").unlink(missing_ok=True)
                config_file = info["config_root"] / "config.toml"
                original = config_file.read_text()
                config = 'model = "gpt-5.6-sol"\nmodel_provider = "scripted"\n' + original
                config += ('\n[model_providers.scripted]\nname = "Local scripted fixture"\nbase_url = ' +
                           json.dumps(provider.url) + '\nwire_api = "responses"\nrequires_openai_auth = false\n' +
                           'supports_websockets = false\nrequest_max_retries = 0\nstream_max_retries = 0\nstream_idle_timeout_ms = 5000\n')
                config_file.write_text(config)
                provider.begin(name)
                with ScriptedServer([str(codex), "--strict-config", "app-server"], workspace, info["env"],
                                    info["case"] / "rpc") as server:
                    hello = server.initialize("0.145.0")
                    if Path(hello["codexHome"]) != info["config_root"]:
                        raise ValueError("Unexpected Codex configuration root")
                    listed = server.request("hooks/list", dict(cwds=[str(workspace)]))
                    if name == "fresh":
                        if any(entry["hooks"] or entry["errors"] or entry["warnings"] for entry in listed["data"]):
                            raise ValueError("Fresh condition discovered hooks")
                    else:
                        trusted, _ = vetted_hooks(listed, info["config_root"], prefix, source)
                        if not all(hook["trustStatus"] == "trusted" for hook in trusted):
                            raise ValueError("Reviewed hooks did not become trusted")
                    thread = server.request("thread/start", dict(cwd=str(workspace), permissions="pilot",
                        approvalPolicy="never", ephemeral=False, allowProviderModelFallback=False))
                    if (thread["modelProvider"] != "scripted" or thread.get("instructionSources") != [] or
                            thread.get("activePermissionProfile", {}).get("id") != "pilot"):
                        raise ValueError("Unexpected thread provider, instructions or permissions")
                    turn = server.request("turn/start", dict(threadId=thread["thread"]["id"], input=[
                        dict(type="text", text="Scripted integration probe. Execute the fixed source read and boundary checks.")]))
                    completed = server.wait_notification("turn/completed", lambda params:
                        params["threadId"] == thread["thread"]["id"] and params["turn"]["id"] == turn["turn"]["id"])
                    if completed["turn"]["status"] != "completed":
                        raise ValueError("Scripted turn did not complete")
                    hook_runs = [item["params"]["run"] for item in server.notifications if item["method"] == "hook/completed"]
                    if name == "fresh" and hook_runs:
                        raise ValueError("Fresh condition ran hooks")
                    if name == "eggshell" and (not {"sessionStart", "userPromptSubmit", "preToolUse", "postToolUse", "stop"}
                            .issubset({row["eventName"] for row in hook_runs}) or any(row["status"] != "completed" for row in hook_runs)):
                        raise ValueError("Missing or failed native plugin callback")
                    write_json(info["case"] / "completed.json", completed)
                    write_json(info["case"] / "hooks-completed.json", hook_runs)
                    server.request("thread/unsubscribe", dict(threadId=thread["thread"]["id"]))
                if (workspace / ".pilot-edit").read_text() != "inside-canary\n" or outside.read_text() != "outside-canary\n":
                    raise ValueError("Native patch boundary failed")
                rows = [row["body"] for row in provider.requests if row["condition"] == name]
                if len(rows) != 2:
                    raise ValueError("Unexpected scripted request count")
                read_output = native_read_result(rows[1], source_sha)
                catalog = [item for item in rows[0]["input"] if item.get("type") == "additional_tools"]
                if any(tool.get("name") == "collaboration" for item in catalog for tool in item["tools"]):
                    raise ValueError("Agent tools remain exposed despite the disabled agent policy")
                reports[name] = dict(scripted_turns=1, requests=2, hook_events=[row["eventName"] for row in hook_runs],
                                     agent_tools_exposed=False,
                                     native_read_output=read_output,
                                     tool_catalog_sha256=hashlib.sha256(json.dumps(catalog, sort_keys=True).encode()).hexdigest())
        if provider.error or reports["fresh"]["tool_catalog_sha256"] != reports["eggshell"]["tool_catalog_sha256"]:
            raise ValueError("Fixture failed or condition tool catalogs differ")
    finally:
        execute([prefix / "libexec/eggshell", "codex-daemon", "shutdown"], egg["env"], workspace,
                egg["case"] / "shutdown.json", timeout=15)
    receipts = []
    for directory in (egg["case"] / "data/receipts").iterdir():
        request = json.loads((directory / "request.json").read_text())["data"]
        published = json.loads((directory / "published.json").read_text())["data"]
        raw = published["output"].encode()
        if (published["bytes"] != len(raw) or published["sha256"] != hashlib.sha256(raw).hexdigest()
                or published["flushedMs"] > published["deadlineMs"] or not published["replyComplete"]):
            raise ValueError("Invalid or late native stdout receipt")
        search = directory / "search.json"
        trace = json.loads(search.read_text())["data"]["trace"] if search.exists() else None
        receipts.append(dict(id=directory.name, event=request["event"], sha256=published["sha256"],
                             bytes=len(raw), search_trace=trace))
    if not {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"}.issubset({r["event"] for r in receipts}):
        raise ValueError("Missing native receipt events")
    if any(digest(workspace / name) != sha for name, sha in task["start_hashes"].items()):
        raise ValueError("Task source changed")
    if any((tree_hashes(assets / name) if (assets / name).is_dir() else digest(assets / name)) != asset_before[name]
           for name in asset_names):
        raise ValueError("Source MiniLM assets changed")
    load_suite(suite)
    result = dict(passed=True, conditions=reports, receipts=receipts, source_files_unchanged=50,
                  candidate_sha256=digest(binary), cached_plugin_roots=cached, scripted_turns=2,
                  semantic_timeouts=sum(bool(row["search_trace"]) and
                                        row["search_trace"].get("semantic") == "timedOut" for row in receipts),
                  generation_model_calls=0, pilot_model_runs=0, seed_acquisitions=0,
                  scope="scripted native-hook and tool-boundary integration; no saved DB body delivery")
    write_json(output / "result.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["suite", "source", "minilm-assets", "output"]:
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--runtime-read-root", action="append", type=Path, default=[])
    args = parser.parse_args()
    output = args.output.resolve()
    try:
        output.mkdir(parents=True, exist_ok=False, mode=0o700)
    except FileExistsError:
        print("Probe output exists; previous evidence retained", file=sys.stderr)
        return 2
    try:
        result = run(args.suite.resolve(), args.source.resolve(), args.minilm_assets.resolve(), output,
                     [path.resolve() for path in args.runtime_read_root])
    except Exception as error:
        write_json(output / "failure.json", dict(error=f"{type(error).__name__}: {error}", scripted=True, pilot_model_runs=0))
        print(f"Scripted hook probe failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
