#!/usr/bin/env python3
"""Synthetic usage-accounting controls. No server, model, or network is used."""
from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest

from pilot_usage import audit


def packet(direction, message, **extra):
    return dict(direction=direction, message=message, **extra)


def start(thread="t", request=0):
    return [packet("client", dict(id=request, method="thread/start", params={})),
            packet("server", dict(id=request, result=dict(thread=dict(id=thread, turns=[]))))]


def counts(inputs=100, outputs=20, cached=60, reasoning=8, writes=30):
    return dict(inputTokens=inputs, outputTokens=outputs, totalTokens=inputs + outputs,
                cachedInputTokens=cached, reasoningOutputTokens=reasoning, cacheWriteInputTokens=writes)


def usage(total=None, thread="t", turn="u"):
    value = total or counts()
    return packet("server", dict(method="thread/tokenUsage/updated", params=dict(
        threadId=thread, turnId=turn, tokenUsage=dict(total=value, last=value))))


def trial(request=1, thread="t", turn="u", role="trial", total=None, status="completed"):
    return [packet("client", dict(id=request, method="turn/start", params=dict(threadId=thread)),
                   attempt=dict(id=str(request), role=role)),
            packet("server", dict(id=request, result=dict(turn=dict(id=turn, status="inProgress")))),
            usage(total, thread, turn),
            packet("server", dict(method="turn/completed", params=dict(
                threadId=thread, turn=dict(id=turn, status=status))))]


class UsageControls(unittest.TestCase):
    def fixture(self):
        return start() + trial()

    def test_inclusive_not_cached_or_reasoning_added_twice(self):
        result = audit(self.fixture())
        self.assertTrue(result["reported_usage_complete"])
        self.assertEqual(result["by_role"]["trial"]["reported_usage"]["totalTokens"], 120)
        self.assertFalse(result["adoption_eligible"])
        self.assertEqual(result["billing_coverage"], "not-established")

    def test_repeated_and_partial_updates_not_summed(self):
        rows = self.fixture()
        rows[4:4] = [usage(counts(80, 10, 40, 4, 20)), usage()]
        result = audit(rows)
        self.assertEqual(result["by_role"]["trial"]["reported_usage"]["totalTokens"], 120)

    def test_seed_and_continuation_use_cumulative_difference(self):
        rows = start() + trial(role="seed") + trial(2, turn="v", total=counts(150, 30, 90, 12, 40))
        rows[-2]["message"]["params"]["tokenUsage"]["last"] = counts(20, 10, 0, 0, 0)
        result = audit(rows)
        self.assertEqual(result["by_role"]["seed"]["reported_usage"]["totalTokens"], 120)
        self.assertEqual(result["by_role"]["trial"]["reported_usage"]["totalTokens"], 60)

    def test_separate_threads_do_not_share_baseline(self):
        result = audit(self.fixture() + start("s", 2) + trial(3, thread="s"))
        self.assertEqual(result["by_role"]["trial"]["reported_usage"]["totalTokens"], 240)

    def test_missing_usage_is_unknown(self):
        rows = self.fixture()
        del rows[-2]
        result = audit(rows)
        self.assertFalse(result["reported_usage_complete"])
        self.assertIsNone(result["by_role"]["trial"]["reported_usage"])
        self.assertIsNone(result["threads"]["t"]["reported_usage"])

    def test_missing_boundary_does_not_move_seed_cost_to_trial(self):
        rows = start() + trial(role="seed")
        del rows[-2]
        rows += trial(2, turn="v", total=counts(150, 30, 90, 12, 40))
        result = audit(rows)
        self.assertIsNone(result["by_role"]["seed"]["reported_usage"])
        self.assertIsNone(result["by_role"]["trial"]["reported_usage"])
        self.assertEqual(result["threads"]["t"]["reported_usage"]["totalTokens"], 180)

    def test_zero_requires_explicit_measurement(self):
        result = audit(start() + trial(total=counts(0, 0, 0, 0, 0)))
        self.assertTrue(result["reported_usage_complete"])
        self.assertEqual(result["by_role"]["trial"]["reported_usage"]["totalTokens"], 0)

    def test_counter_reset_invalidates_all_allocations(self):
        rows = self.fixture() + trial(2, turn="v", total=counts(80, 10, 40, 4, 20))
        result = audit(rows)
        self.assertFalse(result["reported_usage_complete"])
        self.assertIsNone(result["threads"]["t"]["reported_usage"])
        self.assertTrue(all(row["reported_usage"] is None for row in result["attempts"]))

    def test_inconsistent_subset_difference_cannot_cross_allocate(self):
        rows = self.fixture() + trial(2, turn="v", total=counts(150, 30, 130, 12, 40))
        result = audit(rows)
        self.assertFalse(result["reported_usage_complete"])
        self.assertIsNone(result["by_role"]["trial"]["reported_usage"])
        self.assertIn("inconsistent-usage-difference", result["attempts"][1]["problems"])

    def test_string_and_integer_request_ids_are_distinct(self):
        rows = start(request="1") + trial(request=1)
        self.assertTrue(audit(rows)["reported_usage_complete"])

    def test_notification_before_start_response_is_bound(self):
        rows = self.fixture()
        rows[3], rows[4] = rows[4], rows[3]
        self.assertTrue(audit(rows)["reported_usage_complete"])

    def test_late_update_before_next_request_is_retained(self):
        rows = self.fixture()
        rows[-2], rows[-1] = rows[-1], rows[-2]
        self.assertTrue(audit(rows)["reported_usage_complete"])

    def test_late_update_after_next_request_cannot_cross_allocate(self):
        rows = self.fixture() + trial(2, turn="v", total=counts(150, 30, 90, 12, 40))
        late = rows.pop(4)
        rows.insert(6, late)
        self.assertIsNone(audit(rows)["by_role"]["trial"]["reported_usage"])

    def test_failed_and_interrupted_costs_are_retained(self):
        for status in ("failed", "interrupted"):
            with self.subTest(status=status):
                result = audit(start() + trial(status=status))
                self.assertEqual(result["attempts"][0]["status"], status)
                self.assertEqual(result["by_role"]["trial"]["reported_usage"]["totalTokens"], 120)
                self.assertFalse(result["adoption_eligible"])

    def test_retried_error_is_preserved_without_inventing_billing(self):
        rows = self.fixture()
        rows.insert(4, packet("server", dict(method="error", params=dict(
            threadId="t", turnId="u", willRetry=True, error=dict(message="retry")))))
        result = audit(rows)
        self.assertTrue(result["attempts"][0]["errors"][0]["will_retry"])
        self.assertEqual(result["billing_coverage"], "not-established")

    def test_request_failure_is_not_a_zero_cost_trial(self):
        rows = self.fixture()[:4]
        rows[-1]["message"] = dict(id=1, error=dict(code=-1, message="failed"))
        result = audit(rows)
        self.assertEqual(result["attempts"][0]["status"], "request-error")
        self.assertIsNone(result["by_role"]["trial"]["reported_usage"])

    def test_missing_response_or_completion_is_incomplete(self):
        for index in (3, 5):
            rows = self.fixture()
            del rows[index]
            self.assertFalse(audit(rows)["reported_usage_complete"])

    def test_empty_capture_is_not_measured(self):
        self.assertFalse(audit([])["reported_usage_complete"])

    def test_unknown_turn_cannot_be_zero_cost(self):
        result = audit(start() + [usage()])
        self.assertFalse(result["reported_usage_complete"])
        self.assertIsNone(result["threads"]["t"]["reported_usage"])

    def test_unsupported_history_operation_is_flagged(self):
        for method in ("thread/resume", "thread/fork", "thread/compact/start", "turn/steer", "review/start"):
            rows = self.fixture() + [packet("client", dict(id=2, method=method, params={}))]
            self.assertFalse(audit(rows)["reported_usage_complete"])

    def test_hooks_rerouting_and_extra_agents_need_separate_audit(self):
        for message in (dict(method="hook/started"), dict(method="model/rerouted"),
                        dict(method="item/completed", params=dict(item=dict(type="collabToolCall")))):
            self.assertFalse(audit(self.fixture() + [packet("server", message)])["reported_usage_complete"])

    def test_server_request_is_flagged(self):
        rows = self.fixture() + [packet("server", dict(id=5, method="item/requestApproval", params={}))]
        self.assertFalse(audit(rows)["reported_usage_complete"])

    def test_duplicate_ids_or_responses_are_rejected(self):
        for index in (2, 3):
            rows = self.fixture()
            rows.append(copy.deepcopy(rows[index]))
            with self.assertRaises(ValueError):
                audit(rows)

    def test_response_without_request_is_rejected(self):
        with self.assertRaises(ValueError):
            audit([packet("server", dict(id=2, result={}))])

    def test_inconsistent_and_noninteger_counters_are_rejected(self):
        for key, value in (("inputTokens", True), ("outputTokens", -1), ("totalTokens", 121),
                           ("cachedInputTokens", 101), ("reasoningOutputTokens", 21)):
            rows = self.fixture()
            rows[-2]["message"]["params"]["tokenUsage"]["total"][key] = value
            with self.assertRaises(ValueError):
                audit(rows)

    def test_optional_cache_write_counter_defaults_to_zero(self):
        rows = self.fixture()
        for value in rows[-2]["message"]["params"]["tokenUsage"].values():
            value.pop("cacheWriteInputTokens", None)
        self.assertEqual(audit(rows)["attempts"][0]["reported_usage"]["cacheWriteInputTokens"], 0)

    def test_duplicate_completion_is_incomplete(self):
        rows = self.fixture()
        rows.append(copy.deepcopy(rows[-1]))
        self.assertFalse(audit(rows)["reported_usage_complete"])

    def test_malformed_protocol_objects_are_rejected(self):
        for value in (None, [], 12):
            rows = self.fixture()
            rows[-2]["message"]["params"]["tokenUsage"]["total"] = value
            with self.assertRaises(ValueError):
                audit(rows)
        with self.assertRaises(ValueError):
            audit([packet("server", dict(method="item/completed", params=[]))])

    def test_unlabelled_and_duplicate_attempts_are_rejected(self):
        rows = self.fixture()
        del rows[2]["attempt"]
        with self.assertRaises(ValueError):
            audit(rows)
        rows = self.fixture() + trial(2, turn="v")
        rows[6]["attempt"]["id"] = "1"
        with self.assertRaises(ValueError):
            audit(rows)

    def test_cli_preserves_invalid_capture_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            capture, output = root / "input.jsonl", root / "audit"
            capture.write_text('{"direction":')
            command = [sys.executable, str(Path(__file__).with_name("pilot_usage.py")),
                       "--capture", str(capture), "--output", str(output)]
            first = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(first.returncode, 1)
            saved = (output / "audit.json").read_bytes()
            self.assertEqual(json.loads(saved)["status"], "invalid-capture")
            self.assertEqual((output / "capture.jsonl").read_bytes(), capture.read_bytes())
            second = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(second.returncode, 0)
            self.assertEqual((output / "audit.json").read_bytes(), saved)

    def test_cli_allocates_seed_and_failed_trial_separately(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            rows = start() + trial(role="seed") + trial(2, turn="v", status="failed",
                                                       total=counts(150, 30, 90, 12, 40))
            capture, output = root / "input.jsonl", root / "audit"
            capture.write_text("".join(json.dumps(row) + "\n" for row in rows))
            command = [sys.executable, str(Path(__file__).with_name("pilot_usage.py")),
                       "--capture", str(capture), "--output", str(output)]
            process = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(process.returncode, 0, process.stderr)
            result = json.loads((output / "audit.json").read_text())
            self.assertEqual(result["by_role"]["seed"]["reported_usage"]["totalTokens"], 120)
            self.assertEqual(result["by_role"]["trial"]["reported_usage"]["totalTokens"], 60)
            self.assertEqual(result["attempts"][1]["status"], "failed")
            self.assertFalse(result["adoption_eligible"])
            self.assertEqual((output / "capture.jsonl").read_bytes(), capture.read_bytes())


if __name__ == "__main__":
    unittest.main(verbosity=2)
