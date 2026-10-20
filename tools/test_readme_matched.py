"""Small fixtures for fixed pairing, original-evidence recovery and no retry."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from readme_matched import completed, normalized, reconstruct, require_stage_complete, slots


class MatchedStudyTests(unittest.TestCase):
    def test_equal_repetitions_for_every_lap_topic_and_condition(self):
        order = [s for stage in range(1, 7) for s in slots(stage)]
        self.assertEqual(len(order), 54)
        self.assertEqual(len({s['label'] for s in order}), 54)
        for stage in range(1, 7):
            stage_slots = list(slots(stage))
            self.assertEqual(len(stage_slots), 9)
            self.assertEqual({s['topic'] for s in stage_slots}, {(stage - 1) % 3 + 1})
            for condition in ['fresh', 'public', 'candidate']:
                self.assertEqual([s['repetition'] for s in stage_slots if s['condition'] == condition], [0, 1, 2])
            self.assertEqual([s['condition'] for s in stage_slots[:3]], ['fresh', 'public', 'candidate'])

    def windows(self, text):
        inputs, rows = [], []
        for position, start in enumerate(range(0, len(text), 384)):
            window = text[start:start + 512]
            key = hashlib.sha256(window.encode()).hexdigest()
            inputs.append(dict(id=key, text=window))
            rows.append(dict(relation='owner', position=position, discovery=key, focus=key))
        return inputs, rows

    def test_reconstruction_keeps_work_separate_from_outcome(self):
        evidence = '保存された本文\n' + ''.join(chr(0x4e00 + i) for i in range(800))
        inputs, rows = self.windows('command contains ANCHOR\n' + json.dumps(evidence, ensure_ascii=False))
        document = reconstruct(inputs, rows, [])[0]
        self.assertEqual(document['evidence'], evidence)
        self.assertNotIn('ANCHOR', document['evidence'])
        self.assertIn('ANCHOR', document['work'])

    def test_historical_answer_is_not_interpreted_as_json(self):
        inputs, rows = self.windows('fixed question\nA historical answer\nwith two lines')
        doc = reconstruct(inputs, rows, ['fixed question'])[0]
        self.assertEqual(doc['kind'], 'answer')
        self.assertEqual(doc['evidence'], 'A historical answer\nwith two lines')

    def test_bad_hash_gap_or_foreign_focus_cannot_silently_drop_evidence(self):
        inputs, rows = self.windows('command\n' + json.dumps('A' * 800))
        inputs[0]['text'] += 'tampered'
        with self.assertRaises(ValueError):
            reconstruct(inputs, rows, [])
        inputs, rows = self.windows('command\n' + json.dumps('A' * 800))
        with self.assertRaises(ValueError):
            reconstruct(inputs, rows[1:], [])
        inputs, rows = self.windows('command\n' + json.dumps('A' * 800))
        rows[0]['focus'] = 'foreign'
        with self.assertRaises(ValueError):
            reconstruct(inputs, rows, [])

    def test_numbered_blank_lines_do_not_make_source_excerpt_falsely_absent(self):
        self.assertEqual(normalized('  10\tcode\n  11\t\n 12\tmore'), normalized('code\n\nmore'))

    def test_attempt_without_final_usage_stops_instead_of_retrying(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            slot = next(slots(1))
            self.assertFalse(completed(base, slot))
            attempt = base / slot['condition'] / 'attempts' / slot['label']
            attempt.mkdir(parents=True)
            with self.assertRaisesRegex(ValueError, 'do not resubmit'):
                completed(base, slot)
            (attempt / 'result.json').write_text(json.dumps(dict(completed=True, usage={})))
            (attempt / 'usage.json').write_text(json.dumps(dict(finalUsageKnown=False, total={})))
            with self.assertRaisesRegex(ValueError, 'unknown'):
                completed(base, slot)

    def test_stage_barrier_requires_all_nine_completed_calls(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            with self.assertRaisesRegex(ValueError, 'every condition'):
                require_stage_complete(base, 1)
            for slot in slots(1):
                attempt = base / slot['condition'] / 'attempts' / slot['label']
                attempt.mkdir(parents=True)
                usage = dict(inputTokens=10, outputTokens=2, totalTokens=12)
                (attempt / 'result.json').write_text(json.dumps(dict(completed=True, usage=usage)))
                (attempt / 'usage.json').write_text(json.dumps(dict(finalUsageKnown=True, total=usage)))
            require_stage_complete(base, 1)


if __name__ == '__main__':
    unittest.main()
