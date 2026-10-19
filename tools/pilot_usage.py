#!/usr/bin/env python3
"""Audit reported App Server usage offline; never launch Codex or a model."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


FIELDS = ("inputTokens", "outputTokens", "totalTokens", "cachedInputTokens",
          "reasoningOutputTokens", "cacheWriteInputTokens")
READ_ONLY_METHODS = {"config/read", "configRequirements/read", "hooks/list", "model/list",
                     "experimentalFeature/list", "mcpServerStatus/list", "skills/list", "account/read"}


def breakdown(value):
    if not isinstance(value, dict):
        raise ValueError("Usage breakdown must be an object")
    counts = {key: value.get(key, 0) if key == "cacheWriteInputTokens" else value[key]
              for key in FIELDS}
    if any(type(number) is not int or number < 0 for number in counts.values()):
        raise ValueError("Usage counters must be nonnegative integers")
    if counts["totalTokens"] != counts["inputTokens"] + counts["outputTokens"]:
        raise ValueError("Reported total differs from input plus output")
    if counts["cachedInputTokens"] > counts["inputTokens"]:
        raise ValueError("Cached input exceeds inclusive input")
    if counts["reasoningOutputTokens"] > counts["outputTokens"]:
        raise ValueError("Reasoning output exceeds inclusive output")
    return counts


def request_key(value):
    if type(value) not in (str, int):
        raise ValueError("Request ID must be an integer or string")
    return type(value).__name__, value


def audit(records):
    requests, responses, notifications = {}, {}, []
    attempt_ids = set()
    issues = []
    for line, record in enumerate(records, 1):
        if not isinstance(record, dict):
            raise ValueError(f"Capture envelope must be an object at line {line}")
        direction, message = record["direction"], record["message"]
        if direction not in {"client", "server"} or not isinstance(message, dict):
            raise ValueError(f"Invalid capture envelope at line {line}")
        if "params" in message and not isinstance(message["params"], dict):
            raise ValueError(f"Protocol params must be an object at line {line}")
        if direction == "client":
            if "id" not in message:
                if "attempt" in record:
                    raise ValueError("Only turn/start requests can declare an attempt")
                if message.get("method") != "initialized":
                    issues.append(dict(line=line, reason="unreviewed-client-notification"))
                continue
            key = request_key(message["id"])
            if key in requests:
                raise ValueError("Duplicate client request ID")
            request = dict(message=message, line=line, attempt=record.get("attempt"))
            requests[key] = request
            if message["method"] == "turn/start":
                label = request["attempt"]
                if (not isinstance(label, dict) or label.get("role") not in {"seed", "trial"}
                        or not isinstance(label.get("id"), str) or not label["id"]
                        or label["id"] in attempt_ids):
                    raise ValueError("Every turn/start needs a unique seed/trial attempt label")
                attempt_ids.add(label["id"])
            elif request["attempt"] is not None:
                raise ValueError("Only turn/start requests can declare an attempt")
            if message["method"] not in READ_ONLY_METHODS | {
                    "initialize", "thread/start", "turn/start", "turn/interrupt"}:
                issues.append(dict(line=line, reason="unreviewed-client-method", method=message["method"]))
        elif "id" in message:
            key = request_key(message["id"])
            if "method" in message:
                issues.append(dict(line=line, reason="server-request-needs-separate-audit"))
            elif key in responses:
                raise ValueError("Duplicate server response ID")
            else:
                responses[key] = (line, message)
        else:
            notifications.append((line, message))
    if responses.keys() - requests.keys():
        raise ValueError("Server response without a captured client request")

    threads, attempts, turns = {}, [], {}
    for key, request in requests.items():
        message = request["message"]
        response_line, response = responses.get(key, (None, {}))
        if response_line is not None and response_line <= request["line"]:
            raise ValueError("Response precedes request")
        if message["method"] == "thread/start" and "result" in response:
            thread = response["result"]["thread"]
            identity = thread["id"]
            if identity in threads or thread.get("forkedFromId") or thread.get("turns"):
                raise ValueError("Expected a new empty thread")
            threads[identity] = dict(start_line=response_line, attempts=[], invalid=False)
        if message["method"] != "turn/start":
            continue
        attempt = dict(**request["attempt"], request_id=message["id"],
                       thread_id=message["params"]["threadId"], line=request["line"],
                       status="unacknowledged", turn_id=None, usage=[], terminal=[], errors=[])
        if "result" in response:
            turn = response["result"]["turn"]
            attempt["turn_id"] = turn["id"]
            attempt["status"] = "inProgress"
            identity = (attempt["thread_id"], turn["id"])
            if identity in turns:
                raise ValueError("Turn assigned to multiple attempts")
            turns[identity] = attempt
        elif "error" in response:
            attempt["status"] = "request-error"
        attempts.append(attempt)

    for line, message in notifications:
        method, params = message.get("method"), message.get("params", {})
        if method not in {"thread/tokenUsage/updated", "turn/started", "turn/completed", "error"}:
            extra_execution = (method in {"item/started", "item/completed"}
                               and params.get("item", {}).get("type") == "collabToolCall")
            if method in {"model/rerouted", "hook/started", "hook/completed"} or extra_execution:
                issues.append(dict(line=line, reason="execution-event-needs-separate-audit", method=method))
            continue
        turn_id = params["turn"]["id"] if method.startswith("turn/") else params["turnId"]
        attempt = turns.get((params["threadId"], turn_id))
        if attempt is None:
            issues.append(dict(line=line, reason="unassigned-turn-event", method=method))
            if params["threadId"] in threads:
                threads[params["threadId"]]["invalid"] = True
            continue
        if line <= attempt["line"]:
            raise ValueError("Turn event precedes its request")
        if method == "thread/tokenUsage/updated":
            usage = params["tokenUsage"]
            if not isinstance(usage, dict):
                raise ValueError("Thread usage must be an object")
            breakdown(usage["last"])  # Validate, but never sum request-level snapshots.
            attempt["usage"].append((line, breakdown(usage["total"])))
        elif method == "turn/completed":
            status = params["turn"]["status"]
            if status not in {"completed", "failed", "interrupted"}:
                raise ValueError("Nonterminal turn/completed status")
            attempt["terminal"].append((line, status))
        elif method == "error":
            attempt["errors"].append(dict(line=line, will_retry=params["willRetry"]))

    for attempt in attempts:
        thread = threads.get(attempt["thread_id"])
        if thread is None or thread["start_line"] >= attempt["line"]:
            issues.append(dict(attempt=attempt["id"], reason="missing-new-thread-origin"))
        else:
            thread["attempts"].append(attempt)

    for identity, thread in threads.items():
        baseline, observed = {key: 0 for key in FIELDS}, {key: 0 for key in FIELDS}
        previous_end = 0
        for attempt in thread["attempts"]:
            problems = []
            if attempt["line"] <= previous_end:
                problems.append("overlapping-turn-capture")
                thread["invalid"] = True
            terminal = attempt["terminal"]
            if len(terminal) != 1:
                problems.append("missing-or-duplicate-completion")
            else:
                attempt["status"] = terminal[0][1]
            for _, counts in attempt["usage"]:
                if any(counts[key] < observed[key] for key in FIELDS):
                    problems.append("cumulative-counter-decreased")
                    thread["invalid"] = True
                observed = counts
            final = attempt["usage"][-1][1] if attempt["usage"] else None
            if final is None:
                problems.append("missing-usage")
            if baseline is None:
                problems.append("missing-previous-usage-boundary")
            delta = None
            if final is not None and baseline is not None and not thread["invalid"]:
                try:
                    delta = breakdown({key: final[key] - baseline[key] for key in FIELDS})
                except ValueError:
                    problems.append("inconsistent-usage-difference")
                    thread["invalid"] = True
            attempt["reported_usage"] = delta
            attempt["last_observed_cumulative"] = final
            attempt["problems"] = problems
            previous_end = max([attempt["line"], *[row[0] for row in attempt["usage"]],
                                *[row[0] for row in terminal]])
            baseline = final
        missing_final = bool(thread["attempts"]) and not thread["attempts"][-1]["usage"]
        thread["reported_usage"] = None if thread["invalid"] or missing_final else observed
        if thread["invalid"]:
            for attempt in thread["attempts"]:
                attempt["reported_usage"] = None

    role_totals = {}
    for role in ("seed", "trial"):
        selected = [row for row in attempts if row["role"] == role]
        known = [row for row in selected if row.get("reported_usage") is not None]
        role_totals[role] = dict(attempts=len(selected), measured_attempts=len(known),
                               reported_usage=({key: sum(row["reported_usage"][key] for row in known)
                                                for key in FIELDS} if len(known) == len(selected) else None))
    complete = bool(attempts) and not issues and all(
        not row.get("problems", ["unassigned"]) and row.get("reported_usage") is not None
        for row in attempts)
    for row in attempts:
        row.pop("usage")
        row.pop("terminal")
    return dict(status="reported-usage-complete" if complete else "incomplete-capture",
                reported_usage_complete=complete, billing_coverage="not-established",
                adoption_eligible=False, issues=issues, by_role=role_totals, attempts=attempts,
                threads={key: dict(reported_usage=value["reported_usage"],
                                   invalid=value["invalid"]) for key, value in threads.items()})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    capture, output = args.capture.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    raw = capture.read_bytes()
    (output / "capture.jsonl").write_bytes(raw)
    (output / "auditor.py").write_bytes(Path(__file__).read_bytes())
    try:
        result = audit([json.loads(line) for line in raw.decode().splitlines()])
    except (ValueError, KeyError, TypeError) as error:
        result = dict(status="invalid-capture", reported_usage_complete=False,
                      billing_coverage="not-established", adoption_eligible=False, error=str(error))
    result.update(capture_sha256=hashlib.sha256(raw).hexdigest(),
                  auditor_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    (output / "audit.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("status", "billing_coverage", "adoption_eligible")}))
    return 0 if result["reported_usage_complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
