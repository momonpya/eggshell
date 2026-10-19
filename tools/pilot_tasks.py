#!/usr/bin/env python3
"""Prepare and grade the fixed ItsDangerous task sequence; never invoke a model."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import xml.etree.ElementTree as ET


DATA = Path(__file__).resolve().parents[1] / "benchmarks/itsdangerous"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def files(root):
    result = {}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if any(part in {".git", ".pytest_cache", "__pycache__"} for part in relative.parts):
            continue
        if path.is_symlink():
            raise ValueError(f"Symbolic link is not a task source file: {relative}")
        if path.is_file():
            result[str(relative)] = digest(path)
    return result


def copy_files(source, target, names):
    target.mkdir(parents=True, exist_ok=False)
    for name in names:
        path = target / name
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, path)


def protected(names, prefix):
    return {name: sha for name, sha in names.items() if not name.startswith(prefix)}


def run_checks(python, checkout, checks, output):
    output.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    env.pop("PYTHONHOME", None)
    env.pop("PYTHONOPTIMIZE", None)
    env.update(PYTHONPATH=os.pathsep.join([str(checkout / "src"), str(checkout / "tests")]),
               PYTHONDONTWRITEBYTECODE="1", PYTEST_DISABLE_PLUGIN_AUTOLOAD="1",
               PYTHONHASHSEED="0", EGGSHELL_PILOT_SOURCE=str(checkout))
    command = [str(python), "-m", "pytest", "-q", "-ra", "--rootdir", str(checkout),
               f"--junitxml={output / 'results.xml'}", str(checkout / "tests"), *map(str, checks)]
    timed_out = False
    with (output / "stdout.log").open("w") as log:
        process = subprocess.Popen(command, cwd=checkout, env=env, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            process.wait(timeout=90)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    counts = {key: 0 for key in ("tests", "failures", "errors", "skipped")}
    cases = []
    xml = output / "results.xml"
    if xml.exists():
        tree = ET.parse(xml).getroot()
        for suite in tree.iter("testsuite"):
            for key in counts:
                counts[key] += int(suite.get(key, 0))
        for case in tree.iter("testcase"):
            parts = case.get("classname", "").split(".")
            start = next((i for i, part in enumerate(parts) if part.startswith("test_")), 0)
            identity = ".".join(parts[start:]) + "::" + case.get("name", "")
            failed = case.find("failure") is not None or case.find("error") is not None
            cases.append(dict(id=identity, failed=failed))
    result = dict(command=command, exit_code=process.returncode, timed_out=timed_out,
                  counts=counts, cases=cases,
                  passed=process.returncode == 0 and not timed_out and counts["tests"] > 0
                  and not any(counts[key] for key in ("failures", "errors", "skipped")))
    write_json(output / "run.json", result)
    return result


def load_suite(root):
    manifest = json.loads((root / "suite.json").read_text())
    if files(root / "material") != manifest["material_hashes"]:
        raise ValueError("Frozen task material changed")
    if digest(Path(__file__)) != manifest["grader_sha256"]:
        raise ValueError("Use the frozen grader for this suite")
    return manifest


def grade(root, task_id, candidate, output):
    if output.is_relative_to(candidate) or output.is_relative_to(root):
        raise ValueError("Grading output must be outside candidate and frozen suite")
    manifest = load_suite(root)
    task = next(task for task in manifest["tasks"] if task["id"] == task_id)
    prefix = manifest["allowed_source_prefix"]
    observed = files(candidate)
    baseline = task["start_hashes"]
    invalid = sorted(name for name in baseline.keys() | observed.keys()
                     if baseline.get(name) != observed.get(name) and
                     not (name.startswith(prefix) and name.endswith(".py")))
    output.mkdir(parents=True, exist_ok=False)
    if invalid:
        result = dict(passed=False, status="invalid-edit", invalid_paths=invalid,
                      grader_model_calls=0)
        write_json(output / "grade.json", result)
        return result
    checkout = output / "checkout"
    start = root / "cases" / task_id / "start"
    if files(start) != baseline:
        raise ValueError("Frozen starting snapshot changed")
    copy_files(start, checkout, baseline)
    for name in baseline.keys() | observed.keys():
        if name.startswith(prefix):
            path = checkout / name
            if name in observed:
                path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(candidate / name, path)
            elif path.exists():
                path.unlink()
    checks = [root / "material/checks" / name
              for name in ["test_import_boundary.py", *task["checks"]]]
    before = protected(files(checkout), prefix)
    result = run_checks(Path(manifest["python"]), checkout, checks, output / "evaluation")
    result["protected_files_unchanged"] = protected(files(checkout), prefix) == before
    result["test_set_matches"] = sorted(row["id"] for row in result["cases"]) == task["expected_test_ids"]
    result["frozen_material_unchanged"] = files(root / "material") == manifest["material_hashes"]
    result["starting_snapshot_unchanged"] = files(start) == baseline
    result["passed"] = result["passed"] and all(result[key] for key in (
        "protected_files_unchanged", "test_set_matches", "frozen_material_unchanged", "starting_snapshot_unchanged"))
    result["status"] = "evaluated"
    result["grader_model_calls"] = 0
    write_json(output / "grade.json", result)
    return result


def prepare(prepared, output):
    source = prepared / "subject"
    readiness = json.loads((prepared / "subject-manifest.json").read_text())
    specification = json.loads((DATA / "tasks.json").read_text())
    if not readiness["passed"] or readiness["commit"] != specification["subject_commit"]:
        raise ValueError("The required subject has not passed readiness")
    if any(digest(source / name) != sha for name, sha in readiness["source_hashes"].items()):
        raise ValueError("Pinned subject source changed")
    python = Path(readiness["runtime"]["executable"])
    output.mkdir(parents=True, exist_ok=False)
    shutil.copytree(DATA, output / "material")
    shutil.copy2(Path(__file__), output / "grader.py")
    base = output / "base"
    copy_files(source, base, readiness["source_hashes"])
    manifest = dict(subject_commit=readiness["commit"], python=str(python),
                    subject_runtime=readiness["runtime"],
                    environment_freeze_sha256=digest(prepared / "environment-requirements.txt"),
                    material_hashes=files(output / "material"), grader_sha256=digest(Path(__file__)),
                    allowed_source_prefix=specification["allowed_source_prefix"], tasks=[],
                    generation_model_calls=0, pilot_model_runs=0, status="preparing")
    previous = base
    for spec in specification["tasks"]:
        case = output / "cases" / spec["id"]
        start, reference = case / "start", case / "reference"
        copy_files(previous, start, files(previous))
        copy_files(start, reference, files(start))
        patch = output / "material" / spec["patch"]
        for flags in (["--check"], []):
            subprocess.run(["git", "apply", *flags, str(patch)], cwd=reference, check=True)
        checks = [output / "material/checks" / name for name in ["test_import_boundary.py", *spec["checks"]]]
        missing = run_checks(python, start, checks, case / "before")
        gold = run_checks(python, reference, checks, case / "after")
        failures = [row["id"] for row in missing["cases"] if row["failed"]]
        informative = (not missing["passed"] and missing["counts"]["failures"] > 0
                       and missing["counts"]["errors"] == 0
                       and not any("test_itsdangerous" in identity for identity in failures))
        task = dict(**spec, start_hashes=files(start), reference_hashes=files(reference),
                    expected_test_ids=sorted(row["id"] for row in gold["cases"]),
                    before=missing["counts"], after=gold["counts"],
                    counterfactual_informative=informative)
        manifest["tasks"].append(task)
        write_json(output / "suite.json", manifest)
        if not informative or not gold["passed"]:
            raise RuntimeError(f"Task oracle validation failed: {spec['id']}; logs preserved")
        previous = reference
    manifest["status"] = "reference-checked"
    write_json(output / "suite.json", manifest)
    print(json.dumps(dict(status=manifest["status"], tasks=[dict(id=t["id"], before=t["before"],
          after=t["after"]) for t in manifest["tasks"]], generation_model_calls=0, pilot_model_runs=0)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    precheck = modes.add_parser("prepare")
    precheck.add_argument("--subject-root", required=True, type=Path)
    precheck.add_argument("--output", required=True, type=Path)
    grading = modes.add_parser("grade")
    for name in ("suite", "candidate", "output"):
        grading.add_argument("--" + name, required=True, type=Path)
    grading.add_argument("--task", required=True)
    args = parser.parse_args()
    if args.mode == "prepare":
        prepare(args.subject_root.resolve(), args.output.resolve())
        return 0
    result = grade(args.suite.resolve(), args.task, args.candidate.resolve(), args.output.resolve())
    print(json.dumps({key: result[key] for key in ("passed", "status", "grader_model_calls")}))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
