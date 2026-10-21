"""Reject incomplete, substituted or unsaved common-history checkpoints."""
import json
from pathlib import Path
import tempfile
import unittest

from prepare_token_stage import checkpoint
from readme_token_dispatch import order
from semantic_latency import graph_files


class CommonHistoryTests(unittest.TestCase):
    def fixture(self, root):
        slots = [dict(**slot, label=f"r{slot['repetition']}", study=str(root / slot['condition']))
                 for slot in order() if slot['stage'] == 1]
        return dict(slots=slots), slots

    def complete(self, slot):
        attempt = Path(slot['study']) / 'attempts' / slot['label']
        attempt.mkdir(parents=True)
        output = attempt / 'output.egg'
        output.mkdir()
        (output / 'head').write_text('saved common graph')
        usage = dict(inputTokens=2, outputTokens=3, totalTokens=5)
        (attempt / 'usage.json').write_text(json.dumps(dict(finalUsageKnown=True, total=usage)))
        (attempt / 'result.json').write_text(json.dumps(dict(completed=True, usage=usage,
                                                           outputGraphFiles=graph_files(output))))
        (attempt / 'keep.json').write_text(json.dumps(dict(exitCode=0)))
        (attempt / 'shutdown.json').write_text(json.dumps(dict(exit_code=0, daemon_exit_code=0)))
        return attempt

    def test_r0_alone_cannot_advance_history(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            plan, slots = self.fixture(root)
            self.complete(next(s for s in slots if s['condition'] == 'candidate' and s['repetition'] == 0))
            with self.assertRaisesRegex(ValueError, 'every fixed preceding'):
                checkpoint(root / 'study', plan, 2)
            self.assertFalse((root / 'study').exists())

    def test_substituted_r0_output_is_rejected_before_indexing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            plan, slots = self.fixture(root)
            for slot in slots:
                attempt = self.complete(slot)
                if slot['condition'] == 'candidate' and slot['repetition'] == 0:
                    (attempt / 'output.egg/head').write_text('another history')
            with self.assertRaisesRegex(ValueError, 'output changed'):
                checkpoint(root / 'study', plan, 2)
            self.assertFalse((root / 'study').exists())

    def test_unsaved_r0_is_rejected_before_indexing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            plan, slots = self.fixture(root)
            for slot in slots:
                attempt = self.complete(slot)
                if slot['condition'] == 'candidate' and slot['repetition'] == 0:
                    (attempt / 'keep.json').write_text(json.dumps(dict(exitCode=1)))
            with self.assertRaisesRegex(ValueError, 'save or owned shutdown'):
                checkpoint(root / 'study', plan, 2)
            self.assertFalse((root / 'study').exists())


if __name__ == '__main__':
    unittest.main()
