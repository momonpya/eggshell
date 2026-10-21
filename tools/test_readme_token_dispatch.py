import json
from pathlib import Path
import tempfile
import unittest

from readme_token_dispatch import order, status


class TokenComparisonTests(unittest.TestCase):
    def test_all_topics_and_laps_have_equal_predeclared_repetitions(self):
        slots = list(order())
        self.assertEqual(len(slots), 54)
        self.assertNotIn('public', {s['condition'] for s in slots})
        for stage in range(1, 7):
            for condition in ['fresh', 'candidate', 'current']:
                selected = [s for s in slots if s['stage'] == stage and s['condition'] == condition]
                self.assertEqual([s['repetition'] for s in selected], [0, 1, 2])
                self.assertEqual({s['topic'] for s in selected}, {(stage - 1) % 3 + 1})
        self.assertEqual([s['condition'] for s in slots[:2]], ['fresh', 'candidate'])

    def test_attempted_unknown_cost_is_never_a_fresh_slot(self):
        with tempfile.TemporaryDirectory() as temporary:
            cell = Path(temporary)
            slot = dict(study=str(cell), label='trial')
            self.assertIsNone(status(slot))
            attempt = cell / 'attempts/trial'
            attempt.mkdir(parents=True)
            with self.assertRaisesRegex(ValueError, 'do not resubmit'):
                status(slot)
            (attempt / 'result.json').write_text(json.dumps(dict(completed=True, usage={})))
            (attempt / 'usage.json').write_text(json.dumps(dict(finalUsageKnown=False, total={})))
            with self.assertRaisesRegex(ValueError, 'Unknown'):
                status(slot)


if __name__ == '__main__':
    unittest.main()
