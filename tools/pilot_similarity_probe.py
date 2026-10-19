#!/usr/bin/env python3
"""Exercise the isolated similarity control on one existing protected warm DB."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from pilot_hook_probe import execute, tree_hashes
from pilot_memory_probe import QUESTION, delivery, native_turn, prepare_case, protected_databases, snapshot, warm
from pilot_scripted_provider import ScriptedProvider
from pilot_tasks import digest, load_suite, write_json
from prepare_pilot_similarity import overlay


def promoted_generators(nominations, selection):
    pairs = {}
    for row in nominations:
        if row["kind"] != "experimental-similarity-identity-nomination":
            raise ValueError("Unknown experimental nomination record")
        for matched in row["matches"]:
            if not matched["incomingFragmentIdentity"]:
                pair = matched["currentFragment"], matched["pastFragment"]
                pairs[json.dumps(pair, sort_keys=True)] = pair
    if not pairs:
        raise ValueError("No new experimental identity nomination was recorded")
    for left, right in pairs.values():
        if not any(edge["scope"] == "run" and (
                (edge["left"] == left and edge["right"] == right) or
                (edge["left"] == right and edge["right"] == left)) for edge in selection["runLocal"]):
            raise ValueError("Experimental nomination has no actual run-local generator")
    return len(pairs)


def qualified_inputs(ordinary, memory, control, source, suite):
    baseline = json.loads((ordinary / "result.json").read_text())
    saved = json.loads((memory / "result.json").read_text())
    experimental = json.loads((control / "result.json").read_text())
    sealed = json.loads((control / "manifest.json").read_text())
    prefix = ordinary / "prefix"
    binary = control / "checkout/.lake/build/bin/eggshell"
    if not baseline["passed"] or not saved["passed"] or not experimental["passed"]:
        raise ValueError("A required qualification failed")
    expected = experimental["production_binary_sha256"]
    if digest(prefix / "libexec/eggshell") != expected or digest(source / ".lake/build/bin/eggshell") != expected:
        raise ValueError("Ordinary runtime differs from the control's original candidate")
    if digest(binary) != experimental["candidate_sha256"]:
        raise ValueError("Experimental executable changed")
    if (control / "checkout/Eggshell/Handoff.lean").read_text() != overlay((source / "Eggshell/Handoff.lean").read_text()):
        raise ValueError("Control is not the declared intervention on the current candidate")
    for name, expected in sealed["helpers"].items():
        if digest(control / name) != expected or digest(Path(__file__).with_name(name)) != expected:
            raise ValueError("Experimental build helper changed")
    for name, expected in sealed["overlay_hashes"].items():
        if digest(control / "checkout" / name) != expected:
            raise ValueError("Experimental overlay changed")
    for name, expected in sealed["source_hashes"].items():
        if name not in sealed["overlay_hashes"] and digest(control / "checkout" / name) != expected:
            raise ValueError("Experimental source snapshot changed")
    manifest = load_suite(suite)
    memory_manifest = json.loads((memory / "manifest.json").read_text())
    if memory_manifest["suite_sha256"] != digest(suite / "suite.json"):
        raise ValueError("Saved observations use another task suite")
    workspace = memory / "workspace"
    if any(digest(workspace / name) != expected for name, expected in manifest["tasks"][0]["start_hashes"].items()):
        raise ValueError("Original source workspace changed")
    saved_snapshot = json.loads((memory / "saved-snapshot.json").read_text())
    database = memory / "observations.egg"
    if list(database.glob("derived/*/indexes/**/*.json")):
        raise ValueError("Saved observations still have active index tickets")
    if any(digest(database / name) != expected for name, expected in saved_snapshot["graph_files"].items()):
        raise ValueError("Saved graph snapshot changed")
    return prefix, binary, workspace, database, saved_snapshot, manifest


def control_prefix(binary, ordinary_prefix, output, workspace):
    prefix, bootstrap = output / "control-prefix", output / "bootstrap"
    (prefix / "share/eggshell").mkdir(parents=True)
    (bootstrap / "codex").mkdir(parents=True)
    (bootstrap / "tmp").mkdir()
    subprocess.run(["/bin/cp", "-cR", str(ordinary_prefix / "share/eggshell/minilm"),
                    str(prefix / "share/eggshell/minilm")], check=True, timeout=60)
    env = {key: value for key, value in os.environ.items()
           if key in {"PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL"}}
    env.update(CODEX_HOME=str(bootstrap / "codex"), TMPDIR=str(bootstrap / "tmp"),
               EGGSHELL_PREFIX=str(prefix), EGGSHELL_DATA_ROOT=str(bootstrap / "data"),
               HF_HUB_OFFLINE="1", LEAN_NUM_THREADS="1", EGGSHELL_PILOT_SIMILARITY_CONTROL="1")
    execute([binary, "install", "codex"], env, workspace, output / "control-install.json")
    if digest(prefix / "libexec/eggshell") != digest(binary):
        raise ValueError("Installed control differs from its qualified executable")
    return prefix


def run(ordinary, memory, control, source, suite, output, runtime_roots, installed_control=None):
    prefix, binary, workspace, original_db, saved, manifest = qualified_inputs(ordinary, memory, control, source, suite)
    if any(not path.is_dir() or memory.is_relative_to(path) or output.is_relative_to(path)
           or suite.is_relative_to(path) for path in runtime_roots):
        raise ValueError("Invalid runtime read root")
    original_prefix = tree_hashes(prefix)
    original_database = snapshot(original_db)
    experimental_prefix = installed_control or control_prefix(binary, prefix, output, workspace)
    if digest(experimental_prefix / "libexec/eggshell") != digest(binary) or tree_hashes(
            experimental_prefix / "share/eggshell/minilm") != tree_hashes(prefix / "share/eggshell/minilm"):
        raise ValueError("Installed control executable or embedding assets differ")
    installed_before = tree_hashes(experimental_prefix)
    database = output / "common.egg"
    subprocess.run(["/bin/cp", "-cpR", str(original_db), str(database)], check=True, timeout=60)
    if snapshot(database) != original_database:
        raise ValueError("Copied DB differs from its saved snapshot")
    python = Path(manifest["python"])
    base = Path(subprocess.check_output([str(python), "-c", "import sys;print(sys.base_prefix)"],
                                      text=True, timeout=10).strip()).resolve()
    roots = [python.parent.parent, base, *runtime_roots]
    for name in ["pilot_similarity_probe.py", "prepare_pilot_similarity.py", "pilot_memory_probe.py",
                 "pilot_hook_probe.py", "pilot_preflight.py", "pilot_scripted_provider.py", "pilot_server.py", "pilot_tasks.py"]:
        shutil.copy2(Path(__file__).with_name(name), output / name)
    write_json(output / "manifest.json", dict(ordinary_binary_sha256=digest(prefix / "libexec/eggshell"),
        control_binary_sha256=digest(binary), saved_snapshot=saved, suite_sha256=digest(suite / "suite.json"),
        source_hashes=manifest["tasks"][0]["start_hashes"], workspace=str(workspace),
        installed_control=str(experimental_prefix), installed_control_reused=installed_control is not None,
        helpers={path.name: digest(path) for path in output.glob("*.py")},
        production_adoption=False, pilot_model_runs=0))
    reports, catalogs = {}, []
    with protected_databases([database]), ScriptedProvider(output / "provider", "") as provider:
        protected_before = snapshot(database)
        write_json(output / "protected-before.json", protected_before)
        for label, runtime, numerical in [("ordinary", prefix, True), ("similarity", experimental_prefix, True),
                                          ("control-lexical", experimental_prefix, False)]:
            info = prepare_case(output, label, workspace, database, runtime, source, roots, provider, "private", numerical)
            if runtime == experimental_prefix:
                info["env"]["EGGSHELL_PILOT_SIMILARITY_CONTROL"] = "1"
            version = execute([shutil.which("codex"), "--version"], info["env"], workspace,
                              info["case"] / "cli-version.json", timeout=10).stdout.strip()
            if version != "codex-cli 0.145.0":
                raise ValueError("Similarity probe requires CLI requalification")
            warm_row = warm(runtime / "libexec/eggshell", info, workspace, database, "warm.json") if numerical else None
            if warm_row is not None and warm_row["requested"] != 0:
                raise ValueError("Common DB lost its saved warm coverage")
            identity, body, catalog = native_turn(info, workspace, provider, label, QUESTION)
            catalogs.append(catalog)
            evidence = delivery(info, identity, body, saved["warm"]["after"]["windows"], numerical)
            receipt = info["case"] / "data/receipts" / evidence["receipt"]
            ack = json.loads((receipt / "ack.json").read_text())["data"]
            if not ack["rpcCompleted"] or not ack["offerAccepted"]:
                raise ValueError("Native stdout was not acknowledged")
            journal = info["case"] / "data/pilot-similarity-control.jsonl"
            nominations = [json.loads(line) for line in journal.read_text().splitlines()] if journal.exists() else []
            if bool(nominations) != (label == "similarity"):
                raise ValueError("Experimental nomination records crossed a condition boundary")
            if label == "similarity" and (not any(row["matches"] for row in nominations)
                    or evidence["search"]["completed"] <= 0 or evidence["search"]["equalityOrigin"] is None):
                raise ValueError("Warm semantic control did not reach a recorded completed selection")
            if label != "similarity" and evidence["search"]["completed"] != 0:
                raise ValueError("The control fixture did not distinguish ordinary advice from experimental completion")
            analysis = None
            generators = 0
            if evidence["search"]["equalityOrigin"] is not None:
                observed = execute([runtime / "libexec/eggshell", "inspect-equality", evidence["receipt"]],
                    info["env"], workspace, info["case"] / "equality-analysis.json")
                analysis = json.loads(observed.stdout)
                reference = evidence["search"]["equalityOrigin"]["selection"]
                captured = json.loads((info["case"] / "data/receipts" / reference["receipt"] /
                                       (reference["stage"] + ".json")).read_text())["data"]
                generators = promoted_generators(nominations, captured)
            if snapshot(database) != protected_before:
                raise ValueError("A consumer changed the protected common DB")
            reports[label] = dict(**evidence, thread_id=identity, warm=warm_row,
                                  original_nominations=nominations, equality_analysis=analysis,
                                  experimental_pairs_in_actual_generators=generators,
                                  acknowledged=True, protected_database_unchanged=True)
        if len(set(catalogs)) != 1 or provider.error:
            raise ValueError("Native catalogs differ or the fixed provider rejected a request")
        write_json(output / "protected-after.json", snapshot(database))
    if snapshot(original_db) != original_database or tree_hashes(prefix) != original_prefix:
        raise ValueError("Original qualified DB or runtime changed")
    if tree_hashes(experimental_prefix) != installed_before:
        raise ValueError("Installed control runtime changed during consumption")
    if any(digest(workspace / name) != expected for name, expected in manifest["tasks"][0]["start_hashes"].items()):
        raise ValueError("Source workspace changed")
    result = dict(passed=True, cases=reports, database_identity=saved["identity"],
        common_saved_snapshot=True, scripted_turns=3, local_http_requests=3, generation_model_calls=0,
        pilot_model_runs=0, seed_acquisitions=0, source_files_unchanged=50, production_adoption=False,
        scope="paired warm semantic-control transport; not a model outcome or adoption comparison")
    write_json(output / "result.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["ordinary", "memory", "control", "source", "suite", "output"]:
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--runtime-read-root", type=Path, action="append", default=[])
    parser.add_argument("--installed-control", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if sys.platform != "darwin":
        parser.error("This probe requires the qualified macOS filesystem boundary")
    try:
        output.mkdir(parents=True, exist_ok=False, mode=0o700)
    except FileExistsError:
        print("Similarity probe output exists; previous evidence retained", file=sys.stderr)
        return 2
    try:
        result = run(*[getattr(args, name).resolve() for name in ["ordinary", "memory", "control", "source", "suite"]],
                     output, [path.resolve() for path in args.runtime_read_root],
                     args.installed_control.resolve() if args.installed_control else None)
    except Exception as error:
        write_json(output / "failure.json", dict(error=f"{type(error).__name__}: {error}", production_adoption=False))
        print(f"Similarity probe failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(dict(passed=True, cases=list(result["cases"]), pilot_model_runs=0)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
