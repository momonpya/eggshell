import json
from pathlib import Path
import tempfile
import unittest

from prepare_token_restart import new_slots, qualified_source
from readme_token_dispatch import dispatch


class RestartTests(unittest.TestCase):
    def test_retired_comparison_cannot_dispatch_another_call(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            (base / 'retired.json').write_text('{}')
            with self.assertRaisesRegex(ValueError, 'retired'):
                dispatch(base)

    def test_all_controls_and_candidates_belong_to_the_new_study(self):
        base = Path('/new-fixed-comparison')
        slots = new_slots(base)
        self.assertEqual(len(slots), 54)
        self.assertEqual(len({(s['study'], s['label']) for s in slots}), 54)
        self.assertTrue(all(Path(s['study']).parent == base for s in slots))
        for stage in range(1, 7):
            current = [s for s in slots if s['stage'] == stage]
            self.assertEqual(len(current), 9)
            self.assertEqual({s['topic'] for s in current}, {(stage - 1) % 3 + 1})
            for condition in ['fresh', 'current', 'candidate']:
                self.assertEqual([s['repetition'] for s in current if s['condition'] == condition], [0, 1, 2])

    def test_failed_native_delivery_cannot_freeze_a_model_comparison(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            build = base / 'build'; build.mkdir()
            qualification = base / 'qualification'; qualification.mkdir()
            (build / 'result.json').write_text(json.dumps(dict(complete=True, runtimeSha256='unqualified')))
            (qualification / 'protocol.json').write_text(json.dumps(dict(candidate='unqualified')))
            (qualification / 'result.json').write_text(json.dumps(dict(complete=True, allStoredFullProbesDelivered=False)))
            with self.assertRaisesRegex(ValueError, 'must qualify'):
                qualified_source(build, qualification)


if __name__ == '__main__':
    unittest.main()
