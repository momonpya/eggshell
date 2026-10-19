#!/usr/bin/env python3
"""Counterfactual checks for a caller-pinned seed checkpoint."""
from pathlib import Path
import tempfile
import unittest

from pilot_seed import verify
from pilot_tasks import digest, write_json


class SeedIntegrityControls(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "seed"
        self.root.mkdir()
        (self.root / "observations.egg").mkdir()
        write_json(self.root / "observations.egg/head", dict(identity="fixed-db"))
        (self.root / "native.jsonl").write_text('recorded native history\n')
        (self.root / "answer.txt").write_text('recorded final answer')
        self.checkpoint = dict(kind="scripted-runner-fixture", study_seed=False,
            files={str(p.relative_to(self.root)):digest(p) for p in self.root.rglob("*") if p.is_file()},
            history_sha256=digest(self.root / "native.jsonl"), answer_sha256=digest(self.root / "answer.txt"),
            database_identity="fixed-db")
        self.seal()

    def tearDown(self):
        self.temporary.cleanup()

    def seal(self):
        write_json(self.root / "seed.json", self.checkpoint)
        self.expected = digest(self.root / "seed.json")

    def test_unchanged_checkpoint_and_changed_history(self):
        self.assertEqual(verify(self.root, self.expected)["database_identity"], "fixed-db")
        (self.root / "native.jsonl").write_text('another trial\n')
        with self.assertRaisesRegex(ValueError, "files"):
            verify(self.root, self.expected)

    def test_added_nested_manifest_is_not_hidden(self):
        (self.root / "observations.egg/seed.json").write_text('extra data')
        with self.assertRaisesRegex(ValueError, "files"):
            verify(self.root, self.expected)

    def test_resealed_payload_cannot_replace_the_callers_checkpoint(self):
        old = self.expected
        (self.root / "answer.txt").write_text('replacement answer')
        self.checkpoint["files"]["answer.txt"] = digest(self.root / "answer.txt")
        self.checkpoint["answer_sha256"] = digest(self.root / "answer.txt")
        self.seal()
        with self.assertRaisesRegex(ValueError, "caller"):
            verify(self.root, old)

    def test_wrong_db_identity_and_study_relabel_are_rejected(self):
        for update in [dict(database_identity="other-db"), dict(study_seed=True)]:
            with self.subTest(update=update):
                original = dict(self.checkpoint)
                self.checkpoint.update(update)
                self.seal()
                with self.assertRaises(ValueError):
                    verify(self.root, self.expected)
                self.checkpoint = original

    def test_symlink_payload_and_root_are_rejected(self):
        outside = Path(self.temporary.name) / "outside"
        outside.write_text('outside')
        (self.root / "answer.txt").unlink()
        (self.root / "answer.txt").symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "symlink"):
            verify(self.root, self.expected)
        alias = Path(self.temporary.name) / "alias"
        alias.symlink_to(self.root)
        with self.assertRaisesRegex(ValueError, "symlink"):
            verify(alias, self.expected)


if __name__ == "__main__":
    unittest.main(verbosity=2)
