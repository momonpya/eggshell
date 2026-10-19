#!/usr/bin/env python3
"""Pin and test the first paper-pilot subject, without generation-model calls."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import tomllib
import xml.etree.ElementTree as ET


REPOSITORY = "https://github.com/pallets/itsdangerous.git"
COMMIT = "672971d66a2ef9f85151e53283113f33d642dabd"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--python", default="python3.12")
    options = parser.parse_args()
    root = options.output.expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    manifest_path = root / "subject-manifest.json"
    if manifest_path.exists():
        raise SystemExit("Subject manifest already exists; preserve it and choose a new output.")
    interpreter = shutil.which(options.python)
    if interpreter is None:
        raise SystemExit(f"Python interpreter unavailable: {options.python}")
    subject = root / "subject"
    env = os.environ.copy()
    for key in ("PIP_EXTRA_INDEX_URL", "PIP_TRUSTED_HOST", "PYTHONPATH", "PYTHONHOME"):
        env.pop(key, None)
    env.update(PIP_INDEX_URL="https://pypi.org/simple", PIP_DISABLE_PIP_VERSION_CHECK="1",
               PYTHONDONTWRITEBYTECODE="1", PYTHONHASHSEED="0",
               PYTEST_DISABLE_PLUGIN_AUTOLOAD="1")
    steps = []

    def run(name, command, cwd=root, check=True):
        started = time.monotonic()
        result = subprocess.run(command, cwd=cwd, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
        (root / f"{name}.log").write_text(result.stdout)
        steps.append(dict(name=name, command=list(map(str, command)),
                          exit_code=result.returncode, elapsed_seconds=time.monotonic() - started))
        (root / "preparation-steps.json").write_text(json.dumps(steps, indent=2) + "\n")
        if check and result.returncode:
            raise RuntimeError(f"{name} failed; see {root / (name + '.log')}")
        return result

    def git(*args):
        return subprocess.check_output(["git", "-C", str(subject), *args], text=True).strip()

    if not subject.exists():
        run("clone", ["git", "clone", "--depth", "1", "--filter=blob:none", REPOSITORY, str(subject)])
        if git("rev-parse", "HEAD") != COMMIT:
            run("fetch", ["git", "fetch", "--depth", "1", "origin", COMMIT], subject)
            run("checkout", ["git", "checkout", "--detach", COMMIT], subject)
    if git("remote", "get-url", "origin") != REPOSITORY or git("rev-parse", "HEAD") != COMMIT:
        raise SystemExit("Existing subject has another origin or commit; it was left untouched.")
    if git("status", "--porcelain"):
        raise SystemExit("Existing subject has changes; it was left untouched.")
    tracked = git("ls-files").splitlines()
    source_hashes = {name: hashlib.sha256((subject / name).read_bytes()).hexdigest()
                     for name in tracked}
    lock = tomllib.loads((subject / "uv.lock").read_text())
    packaging = [p["version"] for p in lock["package"] if p["name"] == "packaging"]
    if len(packaging) != 1:
        raise SystemExit("The pinned subject has an ambiguous packaging dependency.")
    venv = root / "env"
    if not venv.exists():
        run("venv", [interpreter, "-m", "venv", str(venv)])
    python = str(venv / "bin/python")
    requested = subprocess.check_output([interpreter, "-c", "import sys;print(sys.version)"], text=True).strip()
    actual = subprocess.check_output([python, "-c", "import sys;print(sys.version)"], text=True).strip()
    if requested != actual:
        raise SystemExit("Existing environment uses another Python; it was left untouched.")
    run("bootstrap", [python, "-m", "pip", "install", f"packaging=={packaging[0]}", "flit_core<4"])
    # Resolve the lock's test dependency closure for this exact interpreter.
    # Install every selected version explicitly rather than asking pip to
    # select newer transitive dependencies.
    resolver = '''import json,sys,tomllib
from packaging.markers import Marker
lock=tomllib.load(open(sys.argv[1], "rb"))
wanted={"pytest", "freezegun"}
while True:
    before=wanted.copy()
    for package in lock["package"]:
        if package["name"] in wanted:
            wanted.update(d["name"] for d in package.get("dependencies", [])
                          if not d.get("marker") or Marker(d["marker"]).evaluate())
    if wanted == before: break
result={}
for name in sorted(wanted):
    versions={p["version"] for p in lock["package"] if p["name"] == name}
    if len(versions) != 1: raise RuntimeError("ambiguous locked dependency: "+name)
    result[name]=versions.pop()
print(json.dumps(result, sort_keys=True))
'''
    resolved = run("resolve-tests", [python, "-c", resolver, str(subject / "uv.lock")])
    dependencies = json.loads(resolved.stdout)
    requirements = root / "test-requirements.txt"
    requirements.write_text("".join(f"{name}=={version}\n" for name, version in dependencies.items()))
    run("install-tests", [python, "-m", "pip", "install", "--no-deps", "-r", str(requirements)])
    run("install-subject", [python, "-m", "pip", "install", "--no-deps", "--no-build-isolation",
                            "-e", str(subject)])
    freeze = run("freeze", [python, "-m", "pip", "freeze"])
    (root / "environment-requirements.txt").write_text(freeze.stdout)
    runtime = run("runtime", [python, "-c", "import json,platform,sys; print(json.dumps(dict("
                  "python=sys.version,executable=sys.executable,platform=platform.platform(),"
                  "machine=platform.machine())))"])
    result = run("baseline-tests", [python, "-m", "pytest", "-q", "-ra",
                 f"--junitxml={root / 'baseline.xml'}"], subject, check=False)
    suites = ET.parse(root / "baseline.xml").getroot().iter("testsuite")
    counts = {key: 0 for key in ("tests", "failures", "errors", "skipped")}
    for suite in suites:
        for key in counts:
            counts[key] += int(suite.get(key, 0))
    unchanged = (git("status", "--porcelain") == "" and all(
        hashlib.sha256((subject / name).read_bytes()).hexdigest() == digest
        for name, digest in source_hashes.items()))
    manifest = dict(repository=REPOSITORY, commit=COMMIT, runtime=json.loads(runtime.stdout),
                    locked_test_dependencies=dependencies, source_hashes=source_hashes,
                    source_unchanged=unchanged, baseline=counts, steps=steps,
                    passed=result.returncode == 0 and unchanged and not counts["failures"] and not counts["errors"],
                    generation_model_calls=0, pilot_model_runs=0,
                    scope="Subject readiness only; task protocol and model comparisons are not executed")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({key: manifest[key] for key in ("commit", "baseline", "passed", "source_unchanged",
                                                    "generation_model_calls", "pilot_model_runs")}))
    return 0 if manifest["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
