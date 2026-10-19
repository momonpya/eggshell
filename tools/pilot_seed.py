"""Freeze and verify a shared scripted seed bundle for runner qualification."""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess

from pilot_tasks import digest, write_json


def freeze_fixture(memory, destination):
    result = json.loads((memory / "result.json").read_text())
    saved = json.loads((memory / "saved-snapshot.json").read_text())
    qualification = json.loads((memory / "manifest.json").read_text())
    thread = json.loads((memory / "writer/thread.json").read_text())["thread"]
    completed = json.loads((memory / "writer/completed.json").read_text())
    history = Path(thread["path"])
    if (qualification.get("scripted") is not True or result["pilot_model_runs"] != 0
            or result["seed_acquisitions"] != 0 or thread["modelProvider"] != "scripted"):
        raise ValueError("This freezer accepts only a declared scripted qualification fixture")
    if not result["passed"] or not history.is_relative_to(memory / "writer/codex/sessions") or history.is_symlink():
        raise ValueError("Unqualified or external scripted seed history")
    if completed["turn"]["status"] != "completed" or completed["threadId"] != thread["id"]:
        raise ValueError("Seed writer did not finish")
    before_history = digest(history)
    answers = []
    with history.open() as stream:
        for line in stream:
            row = json.loads(line)
            item = row.get("payload", {})
            if row["type"] == "response_item" and item.get("type") == "message" and item.get("role") == "assistant" and item.get("phase") == "final_answer":
                if item["internal_chat_message_metadata_passthrough"]["turn_id"] != completed["turn"]["id"]:
                    raise ValueError("Seed final answer belongs to another turn")
                answers.append("".join(part["text"] for part in item["content"] if part["type"] == "output_text"))
    if len(answers) != 1 or not answers[0]:
        raise ValueError("A unique native recorded seed answer is required")
    workspace = Path(thread["cwd"])
    if any(digest(workspace / name) != expected for name, expected in qualification["source_hashes"].items()):
        raise ValueError("Seed source workspace changed")
    database = memory / "observations.egg"
    if any(path.is_symlink() for path in [database, *database.rglob("*")]):
        raise ValueError("Seed DB contains a symlink")
    if list(database.glob("derived/*/indexes/**/*.json")):
        raise ValueError("Seed has unfinished indexing")
    if any(digest(database / name) != expected for name, expected in saved["graph_files"].items()):
        raise ValueError("Seed graph changed")
    warm = saved["warm"]["after"]
    if warm["valid"] != warm["windows"] or warm["windows"] <= 0 or warm["missing"] or warm["invalid"]:
        raise ValueError("Seed warm coverage is incomplete")
    destination.mkdir()
    subprocess.run(["/bin/cp", "-cpR", str(database), str(destination / "observations.egg")], check=True, timeout=60)
    shutil.copy2(history, destination / "native.jsonl")
    (destination / "answer.txt").write_text(answers[0])
    hashes = {str(path.relative_to(destination)): digest(path) for path in destination.rglob("*") if path.is_file()}
    checkpoint = dict(kind="scripted-runner-fixture", study_seed=False, thread_id=thread["id"],
        last_turn_id=completed["turn"]["id"], workspace=str(workspace), database_identity=saved["identity"],
        source_hashes=qualification["source_hashes"], warm=saved["warm"], files=hashes,
        history_sha256=before_history, answer_sha256=digest(destination / "answer.txt"), seed_acquisitions=0)
    write_json(destination / "seed.json", checkpoint)
    if digest(history) != before_history:
        raise ValueError("Source history changed while freezing the checkpoint")
    return verify(destination, digest(destination / "seed.json"))


def verify(directory, expected_sha256):
    if directory.is_symlink() or (directory / "seed.json").is_symlink():
        raise ValueError("Seed root or manifest is a symlink")
    if digest(directory / "seed.json") != expected_sha256:
        raise ValueError("Seed checkpoint differs from the caller's frozen manifest")
    checkpoint = json.loads((directory / "seed.json").read_text())
    if checkpoint["kind"] != "scripted-runner-fixture" or checkpoint["study_seed"] is not False:
        raise ValueError("Scripted seed cannot be relabeled as a study acquisition")
    actual = set()
    for path in directory.rglob("*"):
        if path.is_symlink():
            raise ValueError("Seed contains a symlink")
        if path.is_file() and path != directory / "seed.json":
            actual.add(str(path.relative_to(directory)))
    if actual != set(checkpoint["files"]) or any(digest(directory / name) != expected
            for name, expected in checkpoint["files"].items()):
        raise ValueError("Frozen seed files changed")
    if digest(directory / "native.jsonl") != checkpoint["history_sha256"] or digest(directory / "answer.txt") != checkpoint["answer_sha256"]:
        raise ValueError("Seed history/answer does not match its checkpoint")
    identity = json.loads((directory / "observations.egg/head").read_text())["identity"]
    if identity != checkpoint["database_identity"]:
        raise ValueError("Seed DB identity changed")
    return checkpoint
