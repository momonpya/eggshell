#!/usr/bin/env python3
"""Counterfactual checks for saved-body evidence and reversible DB protection."""
from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import tempfile
import unittest

from pilot_memory_probe import MARKER, check_delivery, protected_databases


class MemoryEvidenceControls(unittest.TestCase):
    def body(self, text):
        return dict(input=[dict(type="message", role="user", content=[dict(type="input_text", text=text)])])

    def context(self):
        return "EGGSHELL PRIOR WORK\n" + MARKER + "\nEND EGGSHELL PRIOR WORK"

    def test_actual_published_context_must_reach_request(self):
        context = self.context()
        check_delivery(self.body(context), context, True)
        with self.assertRaises(ValueError):
            check_delivery(self.body("Just acknowledge this question."), context, True)

    def test_tool_argument_is_not_delivery_evidence(self):
        body = dict(input=[dict(type="custom_tool_call", input=self.context())])
        with self.assertRaises(ValueError):
            check_delivery(body, self.context(), True)

    def test_tool_history_cannot_replace_db_delivery(self):
        body = self.body(self.context())
        body["input"].append(dict(type="custom_tool_call_output", output=self.context()))
        with self.assertRaises(ValueError):
            check_delivery(body, self.context(), True)

    def test_incomplete_notice_is_not_saved_body(self):
        notice = "EGGSHELL SEARCH INCOMPLETE\nNo prior work is certified as complete."
        with self.assertRaises(ValueError):
            check_delivery(self.body(notice), notice, True)

    def test_marker_alone_is_not_the_published_context(self):
        with self.assertRaises(ValueError):
            check_delivery(self.body(MARKER), self.context(), True)

    def test_fresh_control_rejects_hidden_prior_body(self):
        check_delivery(self.body("Explain the payload loader."), None, False)
        with self.assertRaises(ValueError):
            check_delivery(self.body(self.context()), None, False)

    @unittest.skipUnless(hasattr(os, "chflags"), "Native macOS file flags required")
    def test_write_protection_is_restored_after_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            database = Path(folder) / "db"
            database.mkdir()
            head = database / "head"
            head.write_text("original")
            flags = {p: p.stat().st_flags for p in [database, head]}
            with self.assertRaisesRegex(RuntimeError, "injected failure"):
                with protected_databases([database]):
                    self.assertTrue(head.stat().st_flags & stat.UF_IMMUTABLE)
                    with self.assertRaises(PermissionError):
                        head.write_text("invalid")
                    raise RuntimeError("injected failure")
            self.assertEqual(head.read_text(), "original")
            self.assertEqual({p: p.stat().st_flags for p in flags}, flags)
            head.write_text("restored writable")

    @unittest.skipUnless(hasattr(os, "chflags"), "Native macOS file flags required")
    def test_symlink_is_rejected_before_any_flag_change(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            database = root / "db"
            database.mkdir()
            outside = root / "outside"
            outside.write_text("outside")
            (database / "alias").symlink_to(outside)
            before = (database.stat().st_flags, outside.stat().st_flags)
            with self.assertRaisesRegex(ValueError, "symlink"):
                with protected_databases([database]):
                    self.fail("Symlink protection unexpectedly admitted")
            self.assertEqual((database.stat().st_flags, outside.stat().st_flags), before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
