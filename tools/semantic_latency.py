#!/usr/bin/env python3
"""Run the preregistered warm-DB native-hook latency diagnostic, without an LLM."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import statistics
import struct
import subprocess
import sys
import time


def digest(data):
    return hashlib.sha256(data).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def graph_files(database):
    result = {}
    for path in database.iterdir():
        if path.is_file():
            hasher = hashlib.sha256()
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    hasher.update(chunk)
            result[path.name] = hasher.hexdigest()
    return result


def execute(args, directory, env, cwd, payload=None, timeout=120):
    directory.mkdir(parents=True, exist_ok=False)
    if payload is not None:
        (directory / "stdin").write_bytes(payload)
    started = time.monotonic_ns()
    try:
        result = subprocess.run([str(arg) for arg in args], input=payload, capture_output=True,
                                env=env, cwd=cwd, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        (directory / "stdout").write_bytes(error.stdout or b"")
        (directory / "stderr").write_bytes(error.stderr or b"")
        save(directory / "record.json", dict(args=[str(arg) for arg in args], timedOut=True,
             elapsedMs=(time.monotonic_ns()-started)/1_000_000, timeoutSeconds=timeout))
        raise
    elapsed = (time.monotonic_ns() - started) / 1_000_000
    (directory / "stdout").write_bytes(result.stdout)
    (directory / "stderr").write_bytes(result.stderr)
    record = dict(args=[str(arg) for arg in args], elapsedMs=elapsed,
                  exitCode=result.returncode, stdoutSha256=digest(result.stdout))
    save(directory / "record.json", record)
    if result.returncode:
        raise RuntimeError(dict(record, stderr=result.stderr.decode(errors="replace")))
    return result.stdout, record


def environment(data):
    env = os.environ.copy()
    env.update(EGGSHELL_DATA_ROOT=str(data), HF_HUB_OFFLINE="1", LEAN_NUM_THREADS="1")
    for key in ("PLUGIN_ROOT", "CODEX_THREAD_ID", "EGGSHELL_CONFIG"):
        env.pop(key, None)
    return env


def question_valid(path, model, window):
    if not path.exists():
        return False
    record = json.loads(path.read_text())
    if record.get("model") != model or record.get("window") != window or "text" in record:
        return False
    vector = record.get("vector")
    # The comparison harness can check either revision's precondition. The
    # candidate runtime accepts only packed vectors; it has no legacy reader.
    if isinstance(vector, list):
        return len(vector) == 384 and all(math.isfinite(x) for x in vector)
    if not isinstance(vector, str) or len(vector) != 384 * 16:
        return False
    try:
        return all(math.isfinite(x) for x in struct.unpack("<384d", bytes.fromhex(vector)))
    except (ValueError, struct.error):
        return False


def hook(binary, cell, env, event, session, directory, question=None):
    payload = dict(hook_event_name=event, session_id=session, turn_id="first-turn",
                   cwd=str(cell), _eggshell_config=str(cell / "config.toml"))
    if question is not None:
        payload["prompt"] = question
    return execute([binary, "codex-hook"], directory, env, cell,
                   (json.dumps(payload, ensure_ascii=False) + "\n").encode(), timeout=35)


def receipt_for(data, session):
    found = []
    for directory in (data / "receipts").iterdir():
        path = directory / "request.json"
        if not path.exists():
            continue
        request = json.loads(path.read_text())["data"]
        if request.get("session") == session and request.get("event") == "UserPromptSubmit":
            found.append(directory)
    if len(found) != 1:
        raise RuntimeError(dict(session=session, receipts=[str(p) for p in found]))
    return found[0]


def shutdown(binary, cell, env, name):
    execute([binary, "codex-daemon", "shutdown"], cell / name, env, cell, timeout=8)
    expires = time.monotonic() + 3
    while list((cell / "data/sessions").glob("*/daemon.json")):
        if time.monotonic() > expires:
            raise RuntimeError("native daemon did not retire its endpoint")
        time.sleep(0.01)


def measure(binary, cell, env, question, condition, count, layout, repetition, windows):
    session = f"{condition}-{count}-{layout}-{repetition}"
    hook(binary, cell, env, "SessionStart", session, cell / f"{condition}-session-start")
    try:
        output, timing = hook(binary, cell, env, "UserPromptSubmit", session,
                              cell / f"{condition}-delivery", question)
        json.loads(output)
        receipt = receipt_for(cell / "data", session)
        published_path = receipt / "published.json"
        published = json.loads(published_path.read_text())["data"] if published_path.exists() else None
        if published is not None and (published.get("output", "").encode() != output
                or published.get("sha256") != digest(output)
                or published.get("bytes") != len(output)):
            raise RuntimeError("native output did not agree with its publication receipt")
        search_path = receipt / "search.json"
        search = json.loads(search_path.read_text())["data"] if search_path.exists() else None
        numerical = [json.loads(p.read_text())["data"] for p in sorted(receipt.glob("numerical-*.json"))]
        discovery = [row for row in numerical if row["corpus"]["purpose"] == "discovery"]
        complete = any(row["status"] == "completed"
                       and row["corpus"]["windowReferences"] == windows
                       and row["counters"]["scoredWindows"] == windows
                       and row["counters"]["source"]["hit"] == windows for row in discovery)
        trace = search["trace"] if search is not None else {}
        semantic = trace.get("semantic") == "completed" and trace.get("route") == "configured" and complete
        row = dict(sources=count, layout=layout, repetition=repetition,
                   questionCache=condition, question=question, elapsedMs=timing["elapsedMs"],
                   semanticComplete=semantic, discoveryScoringComplete=complete,
                   sourceBodyDelivered=b"ORIGINAL_CLOCK_BODY_" in output,
                   publicationConfirmed=published is not None,
                   stdoutSha256=digest(output), receipt=receipt.name, search=search,
                   numerical=numerical)
        ack = receipt / "ack.json"
        row["acknowledgement"] = json.loads(ack.read_text())["data"] if ack.exists() else None
        save(cell / f"{condition}-result.json", row)
        return row
    finally:
        shutdown(binary, cell, env, f"{condition}-shutdown")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--smoke", action="store_true", help="Validate the harness; not part of the 48-run dataset")
    parser.add_argument("--resume", action="store_true", help="Continue unmeasured pairs from the same saved fixtures")
    parser.add_argument("--fixtures", type=Path, help="Reuse the exact saved seeds from an earlier diagnostic root")
    parser.add_argument("--semantic-budget-ms", type=int, default=1500,
                        help="Declare the compiled implementation's semantic cap for this fixed run")
    options = parser.parse_args()
    binary, helper, root = options.binary.resolve(), options.helper.resolve(), options.output.resolve()
    if options.resume:
        previous = json.loads((root / "manifest.json").read_text())
        if previous["binarySha256"] != digest(binary.read_bytes()) or previous["smoke"] != options.smoke:
            raise RuntimeError("resume requires the exact same native implementation and protocol")
        if options.fixtures and previous.get("fixtures") != str(options.fixtures.resolve()):
            raise RuntimeError("resume cannot change the saved fixture source")
        if previous.get("semanticBudgetMs", 1500) != options.semantic_budget_ms:
            raise RuntimeError("resume cannot change the declared semantic allocation")
        serial = len(list(root.glob("resume-*.json"))) + 1
        shutil.copy2(Path(__file__), root / f"runner-resume-{serial}.py")
        save(root / f"resume-{serial}.json", dict(binarySha256=previous["binarySha256"],
             helperSha256=digest(helper.read_bytes()), reason="continue saved fixtures after setup timeout"))
    else:
        root.mkdir(parents=True, exist_ok=False)
    counts, repetitions = ([2], [0]) if options.smoke else ([2, 32, 256, 1024], list(range(3)))
    protocol = Path(__file__).resolve().parents[1] / "docs/semantic-latency-protocol.md"
    if not options.resume:
        shutil.copy2(protocol, root / "protocol.md")
        shutil.copy2(Path(__file__), root / "runner-initial.py")
        save(root / "manifest.json", dict(smoke=options.smoke, sourceCounts=counts,
             repetitions=len(repetitions), plannedHooks=len(counts)*len(repetitions)*4,
             binarySha256=digest(binary.read_bytes()), helperSha256=digest(helper.read_bytes()),
             modelGenerationCalls=0, protocolSha256=digest(protocol.read_bytes()),
             semanticBudgetMs=options.semantic_budget_ms,
             fixtures=str(options.fixtures.resolve()) if options.fixtures else None))
    results = json.loads((root / "results.json").read_text()) if options.resume else []
    for count in counts:
        seed = root / "seeds" / str(count)
        seed_env = environment(root / "seed-data" / str(count))
        if options.fixtures and not seed.exists():
            saved = options.fixtures.resolve() / "seeds" / str(count)
            if not (saved / "fixture.json").is_file():
                raise RuntimeError("requested saved fixture is unavailable")
            seed.parent.mkdir(parents=True, exist_ok=True)
            if sys.platform == "darwin":
                subprocess.run(["/bin/cp", "-cR", str(saved), str(seed)], check=True)
            else:
                shutil.copytree(saved, seed)
        if (seed / "fixture.json").exists():
            fixture = json.loads((seed / "fixture.json").read_text())
            if fixture["headSha256"] != digest((seed / "source.egg/head").read_bytes()):
                raise RuntimeError("saved source fixture head changed")
        else:
            preparation = root / (f"prepare-{count}-resume-{serial}" if options.resume else f"prepare-{count}")
            raw, _ = execute([helper, "prepare", seed, str(count)], preparation, seed_env, root, timeout=600)
            fixture = json.loads(raw)
        model, identity = fixture["warm"]["after"]["model"], fixture["head"]["identity"]
        coverage = fixture["warm"]["after"]
        if (fixture["requestedSources"] != count or fixture["documents"] != count
                or coverage["valid"] != fixture["windows"] or coverage["missing"] or coverage["invalid"]):
            raise RuntimeError("saved fixture is not the requested fully warmed corpus")
        seed_database = seed / "source.egg"
        original = graph_files(seed_database)
        saved_graph = seed / "graph-files.json"
        if saved_graph.exists() and json.loads(saved_graph.read_text()) != original:
            raise RuntimeError("saved fixture graph files changed")
        save(seed / "graph-files.json", original)
        for layout in ("database", "private-overlay"):
            for repetition in repetitions:
                existing = [r for r in results if r["sources"] == count and r["layout"] == layout and r["repetition"] == repetition]
                if len(existing) == 2 and {r["questionCache"] for r in existing} == {"fresh", "cached"}:
                    continue
                if existing:
                    raise RuntimeError("refusing to repeat a partially measured pair")
                cell = root / "cells" / f"{count}-{layout}-{repetition}"
                cell.mkdir(parents=True)
                database, data = cell / "source.egg", cell / "data"
                if sys.platform == "darwin":
                    subprocess.run(["/bin/cp", "-cR", str(seed_database), str(database)], check=True)
                else:
                    shutil.copytree(seed_database, database)
                if graph_files(database) != original:
                    raise RuntimeError("fixture copy changed the saved publication")
                if layout == "private-overlay":
                    shutil.copytree(database / "derived" / identity, data / "read-cache" / identity)
                    shutil.rmtree(database / "derived")
                    subprocess.run(["/bin/chmod", "-R", "a-w", str(database)], check=True)
                env = environment(data)
                (cell / "config.toml").write_text('default = "readonly"\nsemantic_matcher = '
                    + json.dumps([str(binary), "search-provider"]) + '\n[eggs]\nsource = '
                    + json.dumps(str(database)) + '\n[profiles.readonly]\nread = ["source"]\n'
                    + 'handoff_chars = 120000\n')
                question = f"Find kernel realtime clock observations for monotonic scheduling and elapsed timers, question {repetition+1}."
                window = digest(question.encode())
                query_path = data / "queries/vectors" / f"{digest(model.encode())}-{window}.json"
                if question_valid(query_path, model, window):
                    raise RuntimeError("fresh-question condition was already cached")
                try:
                    results.append(measure(binary, cell, env, question, "fresh", count, layout,
                                           repetition, fixture["windows"]))
                    save(root / "results.json", results)
                    if not question_valid(query_path, model, window):
                        execute([helper, "prime", database, question], cell / "unmeasured-prime", env, cell)
                    if not question_valid(query_path, model, window):
                        raise RuntimeError("cached-question condition has no valid private vector")
                    results.append(measure(binary, cell, env, question, "cached", count, layout,
                                           repetition, fixture["windows"]))
                    save(root / "results.json", results)
                    if graph_files(database) != original:
                        raise RuntimeError("read-only delivery changed graph files")
                    print(json.dumps(dict(sources=count, layout=layout, repetition=repetition,
                          attempts=[dict(condition=r["questionCache"], completed=r["semanticComplete"],
                                         elapsedMs=r["elapsedMs"]) for r in results[-2:]])), flush=True)
                finally:
                    if layout == "private-overlay":
                        subprocess.run(["/bin/chmod", "-R", "u+w", str(database)], check=True)
    cells = []
    for count in counts:
        for layout in ("database", "private-overlay"):
            for condition in ("fresh", "cached"):
                rows = [r for r in results if r["sources"] == count and r["layout"] == layout and r["questionCache"] == condition]
                cells.append(dict(sources=count, layout=layout, questionCache=condition, n=len(rows),
                    semanticComplete=sum(r["semanticComplete"] for r in rows),
                    bodyDelivered=sum(r["sourceBodyDelivered"] for r in rows),
                    elapsedMs=[r["elapsedMs"] for r in rows],
                    medianMs=statistics.median(r["elapsedMs"] for r in rows)))
    summary = dict(smoke=options.smoke, attempts=len(results), cells=cells,
        observedGatePassed=len(results) == len(counts)*len(repetitions)*4 and all(
            r["semanticComplete"] and r["sourceBodyDelivered"] and r.get("publicationConfirmed", False)
            and r["elapsedMs"] < 5000 for r in results),
        modelGenerationCalls=0)
    save(root / "summary.json", summary)
    print(json.dumps(summary), flush=True)


if __name__ == "__main__":
    main()
