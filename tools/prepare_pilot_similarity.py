#!/usr/bin/env python3
"""Build an isolated semantic-equality control without changing production sources."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from pilot_tasks import digest, write_json


IMPORT = "public import Eggshell.SelectionAudit\n"
HITS = "      hits := hits ++ found.val\n"
AUDIT = "        audit.modify fun previous => found.val.foldl (fun previous matched =>\n"
SEMANTIC = "  let matchedNominations := discoveryNominations native semanticOwners\n"
TARGETS = '''
lean_lib PilotSimilarityResearch where
  roots := #[`tools.PilotSimilarityControl]

lean_exe pilot_similarity_tests where
  root := `tools.PilotSimilarityControlTests
'''


def overlay(source):
    for anchor in [IMPORT, HITS, AUDIT, SEMANTIC]:
        if source.count(anchor) != 1:
            raise ValueError("The production discovery boundary changed; re-audit the experiment patch")
    return source.replace(IMPORT, IMPORT + "public import tools.PilotSimilarityControl\n").replace(
        HITS, "      let experimentMatches ← PilotSimilarityControl.apply experimentSemantic found.val\n"
              "      hits := hits ++ experimentMatches\n").replace(
        AUDIT, "        audit.modify fun previous => experimentMatches.foldl (fun previous matched =>\n").replace(
        SEMANTIC, SEMANTIC + "  let experimentSemantic := selection.semanticMatcher.isSome\n")


def run(source, output):
    checkout = output / "checkout"
    checkout.mkdir()
    names = subprocess.check_output(["git", "ls-files", "-z"], cwd=source).decode().split("\0")
    names = [name for name in names if name]
    before = {}
    for name in names:
        path = source / name
        if path.is_symlink() or not path.is_file():
            raise ValueError("Source snapshot must contain regular tracked files")
        before[name] = digest(path)
        (checkout / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, checkout / name)
    binary = source / ".lake/build/bin/eggshell"
    original_binary = digest(binary)
    handoff = checkout / "Eggshell/Handoff.lean"
    handoff.write_text(overlay(handoff.read_text()))
    lakefile = checkout / "lakefile.lean"
    lakefile.write_text(lakefile.read_text() + TARGETS)
    helper_names = ["PilotSimilarityControl.lean", "PilotSimilarityControlTests.lean", "prepare_pilot_similarity.py"]
    helpers = {}
    for name in helper_names:
        path = Path(__file__).with_name(name)
        helpers[name] = digest(path)
        shutil.copy2(path, output / name)
        if name.endswith(".lean"):
            shutil.copy2(path, checkout / "tools" / name)
    # APFS clones give the experiment its own writable cache inodes. Never
    # symlink a compiler output directory back into the production checkout.
    (checkout / ".lake").mkdir()
    subprocess.run(["/bin/cp", "-cR", str(source / ".lake/build"), str(checkout / ".lake/build")],
                   check=True, timeout=60)
    if os.stat(binary).st_ino == os.stat(checkout / ".lake/build/bin/eggshell").st_ino:
        raise ValueError("Experimental compiler outputs alias the production cache")
    manifest = dict(source_head=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip(),
        source_hashes=before, helpers=helpers, production_binary_sha256=original_binary,
        overlay_hashes={name: digest(checkout / name) for name in ["Eggshell/Handoff.lean", "lakefile.lean"]},
        production_adoption=False, experiment="similarity-equality", generation_model_calls=0)
    write_json(output / "manifest.json", manifest)
    env = dict(os.environ, LEAN_NUM_THREADS="1", HF_HUB_OFFLINE="1")
    env.pop("EGGSHELL_PILOT_SIMILARITY_CONTROL", None)
    env.pop("EGGSHELL_DATA_ROOT", None)
    for label, command in [("build-tests", ["lake", "--no-cache", "build", "pilot_similarity_tests"]),
                           ("tests", [str(checkout / ".lake/build/bin/pilot_similarity_tests")]),
                           ("build-runtime", ["lake", "--no-cache", "build", "eggshell"])]:
        with (output / (label + ".log")).open("w") as log:
            completed = subprocess.run(command, cwd=checkout, env=env, stdout=log, stderr=subprocess.STDOUT,
                                       timeout=600)
        write_json(output / (label + ".json"), dict(command=command, exit_code=completed.returncode))
        if completed.returncode:
            raise RuntimeError(f"Experimental build/check failed; see {label}.log")
    with (output / "recording.log").open("w") as log:
        completed = subprocess.run([str(checkout / ".lake/build/bin/pilot_similarity_tests"), "record"],
            cwd=checkout, env=dict(env, EGGSHELL_PILOT_SIMILARITY_CONTROL="1", EGGSHELL_DATA_ROOT=str(output / "private-data")),
            stdout=log, stderr=subprocess.STDOUT, timeout=30)
    if completed.returncode:
        raise RuntimeError("Experimental recording check failed; see recording.log")
    journal = [json.loads(line) for line in (output / "private-data/pilot-similarity-control.jsonl").read_text().splitlines()]
    if (len(journal) != 1 or journal[0]["kind"] != "experimental-similarity-identity-nomination"
            or len(journal[0]["matches"]) != 1 or journal[0]["matches"][0]["incomingFragmentIdentity"] is not False):
        raise ValueError("Original semantic nomination was not retained in the private experiment journal")
    if any(digest(source / name) != expected for name, expected in before.items()) or digest(binary) != original_binary:
        raise ValueError("Experimental build changed production sources or executable")
    expected_changes = {"Eggshell/Handoff.lean", "lakefile.lean", *["tools/" + n for n in helper_names if n.endswith(".lean")]}
    changed = {name for name, expected in before.items() if digest(checkout / name) != expected}
    if changed - expected_changes:
        raise ValueError("Experimental source changes exceeded the declared overlay")
    result = dict(passed=True, candidate_sha256=digest(checkout / ".lake/build/bin/eggshell"),
                  production_binary_sha256=original_binary, production_files_unchanged=len(before),
                  source_changes=sorted(expected_changes), production_adoption=False,
                  generation_model_calls=0, pilot_model_runs=0)
    write_json(output / "result.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if sys.platform != "darwin" or output.is_relative_to(source) or source.is_relative_to(output):
        parser.error("Use a separate macOS experiment directory")
    try:
        output.mkdir(parents=True, exist_ok=False, mode=0o700)
    except FileExistsError:
        print("Similarity output exists; previous evidence retained", file=sys.stderr)
        return 2
    try:
        result = run(source, output)
    except Exception as error:
        write_json(output / "failure.json", dict(error=f"{type(error).__name__}: {error}", production_adoption=False))
        print(f"Similarity preparation failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
