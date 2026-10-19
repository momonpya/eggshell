#!/usr/bin/env python3
"""Qualify an isolated fresh-condition command environment without model turns."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import xml.etree.ElementTree as ET

from pilot_server import Server
from pilot_tasks import copy_files, digest, load_suite, write_json


DISABLED = ("apps", "plugins", "hooks", "plugin_hooks", "memories", "multi_agent",
            "multi_agent_mode", "multi_agent_v2", "browser_use", "computer_use", "in_app_browser",
            "code_mode", "code_mode_host", "shell_snapshot", "external_agent_memory_import", "skill_search")


def configuration(workspace, runtime_roots):
    tool_path = [str(workspace / ".bin"),
                 *[str(path / "bin") for path in runtime_roots if (path / "bin").is_dir()],
                 "/usr/bin", "/bin"]
    lines = ['approval_policy = "never"', 'default_permissions = "pilot"',
             'web_search = "disabled"', 'cli_auth_credentials_store = "file"',
             'project_doc_max_bytes = 0', 'notify = []', '[features]',
             *[f'{key} = false' for key in DISABLED],
             '[agents]', 'enabled = false',
             '[memories]', 'generate_memories = false', 'use_memories = false', 'dedicated_tools = false',
             '[skills]', 'include_instructions = false', '[skills.bundled]', 'enabled = false',
             '[plugins._default]', 'enabled = false',
             '[permissions.pilot]', 'extends = ":workspace"',
             '[permissions.pilot.workspace_roots]', f'{json.dumps(str(workspace))} = true',
             '[permissions.pilot.filesystem]', '":root" = "deny"', '":minimal" = "read"',
             '":tmpdir" = "deny"', '":slash_tmp" = "deny"',
             *[f'{json.dumps(str(path))} = "read"' for path in runtime_roots],
             '[permissions.pilot.network]', 'enabled = false',
             '[shell_environment_policy]', 'inherit = "none"', 'experimental_use_profile = false',
             '[shell_environment_policy.set]',
             f'PATH = {json.dumps(os.pathsep.join(tool_path))}',
             f'TMPDIR = {json.dumps(str(workspace / ".tmp"))}',
             'PYTHONDONTWRITEBYTECODE = "1"', 'PYTEST_DISABLE_PLUGIN_AUTOLOAD = "1"',
             'PYTHONHASHSEED = "0"']
    return "\n".join(lines) + "\n"


def check_policy(result, private_config):
    config = result["config"]
    expected = dict(approval_policy="never", default_permissions="pilot", web_search="disabled",
                    cli_auth_credentials_store="file", project_doc_max_bytes=0, notify=[])
    for key, value in expected.items():
        if config.get(key) != value:
            raise ValueError(f"Unexpected effective {key}")
    if any(config.get("features", {}).get(key) is not False for key in DISABLED):
        raise ValueError("An excluded feature is enabled or unreported")
    if config.get("agents", {}).get("enabled") is not False:
        raise ValueError("Agent tools are not disabled")
    if any(config.get(key) for key in ("sandbox_mode", "sandbox_workspace_write", "mcp_servers",
                                      "instructions", "developer_instructions", "model_instructions_file",
                                      "model_providers", "experimental_compact_prompt_file")):
        raise ValueError("Unexpected ambient configuration or legacy sandbox override")
    if config.get("memories", {}).get("use_memories") is not False or \
            config.get("memories", {}).get("generate_memories") is not False:
        raise ValueError("Native memory is not disabled")
    layers = []
    for layer in result.get("layers") or []:
        name = layer["name"]
        layers.append(dict(name=name, keys=sorted(layer["config"])))
        own_layer = (name.get("type") == "user" and name.get("file") == str(private_config)
                     and not name.get("profile"))
        if layer["config"] and not own_layer:
            raise ValueError(f"Unexpected configuration layer {name}; keys={sorted(layer['config'])}")
    return dict(expected=expected, disabled_features=list(DISABLED), layers=layers)


def probe_code(protected, readonly, port):
    return '''import errno,json,os,pathlib,shutil,socket,subprocess
import itsdangerous
result = {}
tools = {}
pathlib.Path('.pilot/write-check').write_text('workspace-write')
result['workspace_write'] = pathlib.Path('.pilot/write-check').read_text() == 'workspace-write'
result['source_read'] = pathlib.Path('src/itsdangerous/serializer.py').is_file()
result['candidate_import'] = pathlib.Path(itsdangerous.__file__).resolve() == pathlib.Path('src/itsdangerous/__init__.py').resolve()
for tool in ('git', 'rg', 'python'):
    path = shutil.which(tool)
    command = subprocess.run([path, '--version'], capture_output=True, text=True) if path else None
    tools[tool] = dict(path=path, exit_code=command.returncode, stdout=command.stdout, stderr=command.stderr) if command else dict(path=None)
    result[tool + '_available'] = command is not None and command.returncode == 0
result['ambient_environment_absent'] = 'EGGSHELL_PILOT_AMBIENT' not in os.environ
result['readonly_read'] = pathlib.Path(READONLY).read_text() == 'readonly-canary'
for name,path in PROTECTED.items():
    try:
        pathlib.Path(path).read_bytes()
        result[name] = False
    except OSError as error:
        result[name] = error.errno in (errno.EPERM, errno.EACCES)
try:
    pathlib.Path(READONLY).write_text('forbidden-overwrite')
    result['readonly_write_denied'] = False
except OSError as error:
    result['readonly_write_denied'] = error.errno in (errno.EPERM, errno.EACCES)
try:
    with socket.create_connection(('127.0.0.1', PORT), timeout=2):
        result['command_network_denied'] = False
except OSError as error:
    result['command_network_denied'] = error.errno in (errno.EPERM, errno.EACCES)
print(json.dumps(dict(checks=result, tools=tools)))
raise SystemExit(0 if all(result.values()) else 1)
'''.replace("READONLY", repr(str(readonly))).replace("PROTECTED", repr(protected)).replace("PORT", str(port))


def preflight(suite, output, codex, runtime_roots):
    if any(output.iterdir()):
        raise ValueError("Preflight output must be a new empty directory")
    manifest = load_suite(suite)
    if manifest["status"] != "reference-checked":
        raise ValueError("Task suite is not reference-checked")
    python = Path(manifest["python"])
    base = Path(subprocess.check_output([str(python), "-c", "import sys; print(sys.base_prefix)"],
                                       text=True, timeout=10).strip()).resolve()
    task = manifest["tasks"][0]
    start = suite / "cases" / task["id"] / "start"
    if any(digest(start / name) != sha for name, sha in task["start_hashes"].items()):
        raise ValueError("Fixed starting source changed")
    for path in runtime_roots:
        if not path.is_dir() or output.is_relative_to(path) or suite.is_relative_to(path):
            raise ValueError("Runtime read root includes experiment data or is not a directory")
    for name in ("pilot_preflight.py", "pilot_server.py", "pilot_tasks.py"):
        shutil.copy2(Path(__file__).with_name(name), output / name)
    workspace, pilot_config_root, pilot_temp_root = [output / name for name in ("workspace", "codex", "tmp")]
    copy_files(start, workspace, task["start_hashes"])
    subprocess.run(["git", "init", "--quiet", str(workspace)], check=True, timeout=10)
    for directory in (pilot_config_root, pilot_temp_root, workspace / ".tmp", workspace / ".pilot", workspace / ".bin"):
        directory.mkdir()
    readonly = output / "readonly-runtime"
    readonly.mkdir()
    (readonly / "marker").write_text("readonly-canary")
    outside = output / "outside-canary"
    outside.write_text("private-canary")
    private_marker = pilot_config_root / "credential-canary"
    private_marker.write_text("private-credential-canary")
    link = workspace / ".pilot/outside-link"
    link.symlink_to(outside)
    config_file = pilot_config_root / "config.toml"
    roots = [python.parent.parent, base, readonly, *runtime_roots]
    config_file.write_text(configuration(workspace, roots))
    env = {key: value for key, value in os.environ.items()
           if key in {"PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL"}}
    # CODEX_HOME selects this child's configuration root. The parent environment stays intact.
    env.update(CODEX_HOME=str(pilot_config_root), TMPDIR=str(pilot_temp_root),
               EGGSHELL_PILOT_AMBIENT="synthetic-environment-canary")
    version = subprocess.check_output([str(codex), "--version"], env=env, text=True, timeout=10).strip()
    if version != "codex-cli 0.145.0":
        raise ValueError("This preflight configuration must be requalified for the installed CLI")
    with (output / "schema-generation.log").open("w") as log:
        subprocess.run([str(codex), "app-server", "generate-json-schema", "--experimental",
                        "--out", str(output / "schema")], env=env, stdout=log,
                       stderr=subprocess.STDOUT, timeout=15, check=True)
    schemas = ("v2/CommandExecParams.json", "v2/ConfigReadResponse.json", "v2/HooksListResponse.json",
               "v2/SkillsListResponse.json", "v1/InitializeResponse.json")
    write_json(output / "manifest.json", dict(cli=version, cli_launcher_sha256=digest(codex.resolve()),
               suite_sha256=digest(suite / "suite.json"), task=task["id"], source_hashes=task["start_hashes"],
               protocol_schema_hashes={name: digest(output / "schema" / name) for name in schemas},
               runtime_read_roots=list(map(str, roots)), config_sha256=digest(config_file),
               sources={name: digest(output / name) for name in ("pilot_preflight.py", "pilot_server.py", "pilot_tasks.py")},
               environment_keys=sorted(env), pilot_model_runs=0))
    with Server([str(codex), "--strict-config", "app-server", "--listen", "stdio://"],
                workspace, env, output / "rpc") as server:
        hello = server.initialize(version.removeprefix("codex-cli "))
        if Path(hello["codexHome"]).resolve() != pilot_config_root:
            raise ValueError("Server used another configuration root")
        policy = check_policy(server.request("config/read", dict(cwd=str(workspace), includeLayers=True)), config_file)
        write_json(output / "effective-policy.json", policy)
        hooks = server.request("hooks/list", dict(cwds=[str(workspace)]))
        skills = server.request("skills/list", dict(cwds=[str(workspace)]))
        for result, entries in ((hooks, "hooks"), (skills, "skills")):
            if len(result["data"]) != 1 or result["data"][0]["cwd"] != str(workspace) or \
                    any(result["data"][0].get(key) for key in (entries, "errors", "warnings")):
                raise ValueError(f"Unexpected {entries} discovery")
        mcp = server.request("mcpServerStatus/list", {})
        if mcp["data"] or mcp.get("nextCursor"):
            raise ValueError("Unexpected MCP servers")
        protected = dict(outside_read_denied=str(outside), private_config_read_denied=str(private_marker),
                         oracle_read_denied=str(suite / "cases" / task["id"] / "reference/src/itsdangerous/serializer.py"),
                         symlink_read_denied=str(link), parent_read_denied=str(workspace / "../outside-canary"))
        if not all(Path(path).is_file() for path in protected.values()):
            raise ValueError("A protected probe target does not exist")
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen(8)
            port = listener.getsockname()[1]
            with socket.create_connection(("127.0.0.1", port), timeout=2):
                pass  # Positive network control outside the sandbox, before testing denial.
            probe = server.request("command/exec", dict(command=[str(python), "-c", probe_code(
                protected, readonly / "marker", port)], cwd=str(workspace),
                permissionProfile="pilot", timeoutMs=10000, outputBytesCap=16000,
                env=dict(PYTHONPATH=os.pathsep.join([str(workspace / "src"), str(workspace / "tests")]))))
        write_json(output / "probe.json", probe)
        if probe["exitCode"] != 0 or not all(json.loads(probe["stdout"])["checks"].values()):
            raise ValueError("Sandbox/environment probe failed")
        checks = json.loads(probe["stdout"])["checks"]
        if (readonly / "marker").read_text() != "readonly-canary":
            raise ValueError("Read-only marker changed")
        tests = server.request("command/exec", dict(command=[str(python), "-m", "pytest", "-q", "-ra",
              f"--junitxml={workspace / '.pilot/results.xml'}", str(workspace / "tests")],
              cwd=str(workspace), permissionProfile="pilot", timeoutMs=30000, outputBytesCap=32000,
              env=dict(PYTHONPATH=os.pathsep.join([str(workspace / "src"), str(workspace / "tests")]))))
        write_json(output / "tests.json", tests)
        if tests["exitCode"] != 0:
            raise ValueError("Subject tests failed under the command sandbox")
    process = json.loads((output / "rpc/process.json").read_text())
    if process["observed_generation_events"] or not process["reader_stopped"]:
        raise ValueError("Generation event observed or transport failed to stop")
    junit = ET.parse(workspace / ".pilot/results.xml")
    counts = {key: sum(int(row.get(key, 0)) for row in junit.iter("testsuite"))
              for key in ("tests", "failures", "errors", "skipped")}
    if counts != dict(tests=297, failures=0, errors=0, skipped=0):
        raise ValueError("Unexpected upstream test set or results")
    expected_ids = sorted(name for name in task["expected_test_ids"] if name.startswith("test_itsdangerous"))
    actual_ids = []
    for case in junit.iter("testcase"):
        parts = case.get("classname", "").split(".")
        start_index = parts.index("test_itsdangerous")
        actual_ids.append(".".join(parts[start_index:]) + "::" + case.get("name", ""))
    if len(expected_ids) != 297 or sorted(actual_ids) != expected_ids:
        raise ValueError("Upstream test identities differ from the frozen oracle")
    unchanged = all(digest(workspace / name) == digest(start / name) == sha
                    for name, sha in task["start_hashes"].items())
    if not unchanged:
        raise ValueError("Source changed during preflight")
    load_suite(suite)
    report = dict(passed=True, checks=checks, upstream_tests=counts, test_set_matches=True,
                  source_hashes_unchanged=len(task["start_hashes"]),
                  hooks=0, skills=0, mcp_servers=0, pilot_model_runs=0, generation_model_calls=0,
                  scope="fresh-condition configuration and command sandbox; not a qualified model runner")
    write_json(output / "result.json", report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--codex", type=Path, default=Path(shutil.which("codex") or "codex"))
    parser.add_argument("--runtime-read-root", type=Path, action="append", default=[])
    args = parser.parse_args()
    args.output = args.output.resolve()
    try:
        args.output.mkdir(parents=True, exist_ok=False, mode=0o700)
    except FileExistsError:
        print("Preflight output already exists; previous evidence retained", file=sys.stderr)
        return 2
    try:
        result = preflight(args.suite.resolve(), args.output.resolve(), args.codex.absolute(),
                           [path.resolve() for path in args.runtime_read_root])
    except Exception as error:
        write_json(args.output / "failure.json", dict(type=type(error).__name__, error=str(error), pilot_model_runs=0))
        print(f"Preflight failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
