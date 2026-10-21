import json
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from prepare_token_restart import new_slots, qualified_source
from readme_token_dispatch import dispatch, admit, history_reference_slots, prior_answer, memory_delivery_report


class RestartTests(unittest.TestCase):
    def test_real_admission_advances_after_the_r0_triple(self):
        plan = dict(slots=new_slots(Path('/new-fixed-comparison')))
        def finished(slot):
            return {} if slot['stage'] == 1 and slot['repetition'] == 0 else None
        with patch('readme_token_dispatch.checked', return_value=plan), \
             patch('readme_token_dispatch.status', side_effect=finished), \
             patch('readme_token_dispatch.read', side_effect=RuntimeError('prepared input inspection reached')):
            with self.assertRaisesRegex(RuntimeError, 'prepared input inspection reached'):
                admit(Path('/new-fixed-comparison'), 2)

    def test_real_admission_rejects_an_incomplete_r0_triple(self):
        plan = dict(slots=new_slots(Path('/new-fixed-comparison')))
        def finished(slot):
            return {} if slot['stage'] == 1 and slot['repetition'] == 0 and slot['condition'] != 'current' else None
        with patch('readme_token_dispatch.checked', return_value=plan), \
             patch('readme_token_dispatch.status', side_effect=finished), \
             patch('readme_token_dispatch.read') as inspect:
            with self.assertRaisesRegex(ValueError, 'preceding r0 matched triple'):
                admit(Path('/new-fixed-comparison'), 2)
            inspect.assert_not_called()

    def test_related_source_does_not_require_the_whole_previous_answer(self):
        prior = prior_answer([dict(kind='answer', owner='saved', work='previous task', evidence='prior finding')])
        inventory = dict(priorAnswer=prior, facts=[dict(name='another valid example',
            fullExcerptOwners=['raw'], excerpt='incidental source from a broad read')])
        body = '\nWORK GRAPH saved\n  GROUNDED OUTCOME\nprior finding\n  TRACE\n'
        report = memory_delivery_report(inventory, body)
        self.assertEqual(report['priorAnswerFullOwners'], ['saved'])
        self.assertEqual(report['missingSourceProbes'], ['another valid example'])
        source_only = memory_delivery_report(inventory,
            '\nWORK GRAPH raw\n  GROUNDED OUTCOME\nincidental source from a broad read\n  TRACE\n')
        self.assertEqual(source_only['priorAnswerFullOwners'], [])
        self.assertEqual(source_only['missingSourceProbes'], [])
        self.assertEqual(source_only['deliveredOwners'], ['raw'])
        self.assertTrue(source_only['relevanceReviewRequired'])
        with self.assertRaisesRegex(ValueError, 'No captured DB evidence'):
            memory_delivery_report(inventory, 'EGGSHELL SEARCH INCOMPLETE')

    def test_retired_comparison_cannot_dispatch_another_call(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            (base / 'retired.json').write_text('{}')
            with self.assertRaisesRegex(ValueError, 'retired'):
                dispatch(base)

    def test_required_original_code_is_distinct_from_incidental_full_probes(self):
        prior = prior_answer([dict(kind='answer', owner='answer', work='past task', evidence='If the condition holds, return the result.')])
        code = 'if (condition) {\n  return result;\n}'
        required = dict(name='requested condition and result', fullExcerptOwners=['raw'], excerpt=code,
                        requiredOriginalForTopics=[3])
        incidental = dict(name='unrequested example', fullExcerptOwners=['extra'], excerpt='other source')
        inventory = dict(topic=3, priorAnswer=prior, facts=[required, incidental])
        summary = '\nWORK GRAPH answer\n  GROUNDED OUTCOME\n' + prior['text'] + '\n  TRACE\n'
        report = memory_delivery_report(inventory, summary)
        self.assertEqual(report['missingRequiredOriginalCode'], [required['name']])
        source = '\nWORK GRAPH raw\n  GROUNDED OUTCOME\n' + code + '\n  TRACE\n'
        report = memory_delivery_report(inventory, source)
        self.assertEqual(report['missingRequiredOriginalCode'], [])
        self.assertEqual(report['missingSourceProbes'], [incidental['name']])
        self.assertEqual(report['priorAnswerFullOwners'], [])
        inventory['topic'] = 2
        self.assertEqual(memory_delivery_report(inventory, summary)['storedRequiredOriginalCode'], [])

    def test_absent_or_wrong_owner_code_does_not_create_a_delivery_pass(self):
        prior = prior_answer([dict(kind='answer', owner='answer', work='past task', evidence='A conclusion')])
        feature = dict(name='required code', fullExcerptOwners=['original'], excerpt='specific_code();',
                       requiredOriginalForTopics=[3])
        inventory = dict(topic=3, priorAnswer=prior, facts=[feature])
        unrelated = '\nWORK GRAPH another\n  GROUNDED OUTCOME\nspecific_code();\n  TRACE\n'
        report = memory_delivery_report(inventory, unrelated)
        self.assertEqual(report['missingRequiredOriginalCode'], ['required code'])
        feature['fullExcerptOwners'] = []
        report = memory_delivery_report(inventory, unrelated)
        self.assertEqual(report['storedRequiredOriginalCode'], [])

    def test_actual_admission_requires_original_code_without_quality_or_token_gates(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            slots = new_slots(base)
            candidate = next(s for s in slots if s['stage'] == 3 and s['condition'] == 'candidate')
            earlier = [s for s in slots if s['stage'] == 2 and s['repetition'] == 0]
            plan = dict(slots=earlier + [candidate], model='gpt-5.6-luna', effort='xhigh',
                        runtimes=dict(candidate='fixed-runtime'))
            snapshot = dict(directory='/fixed-snapshot', files={'graph': 'fixed-digest'})
            prior = prior_answer([dict(kind='answer', owner='answer', work='past task', evidence='Summary')])
            inventory = dict(topic=3, sourceGraphFiles=snapshot['files'], priorAnswer=prior,
                facts=[dict(name='needed branch', fullExcerptOwners=['raw'], excerpt='if (x) return y;',
                            requiredOriginalForTopics=[3])])
            case = Path(candidate['study']) / 'prepared' / candidate['label']
            case.mkdir(parents=True)
            protocol = dict(model=plan['model'], effort=plan['effort'], candidate='fixed-runtime')
            prepared = dict(manifest=dict(sourceSnapshot=snapshot, memory=dict(body='body.txt')),
                            qualityAccepted=False, tokenReductionPercent=-15)
            def read_fixture(path):
                if path.name == 'llvm-three-topics.json':
                    return dict(prompts={3:'fixed question'})
                return protocol if path.name == 'protocol.json' else inventory
            for original in [False, True]:
                with self.subTest(original=original):
                    text = ('\nWORK GRAPH raw\n  GROUNDED OUTCOME\nif (x) return y;\n  TRACE\n'
                            if original else '\nWORK GRAPH answer\n  GROUNDED OUTCOME\nSummary\n  TRACE\n')
                    (case / 'body.txt').write_text(text)
                    with patch('readme_token_dispatch.checked', return_value=plan), \
                         patch('readme_token_dispatch.status', side_effect=lambda s: {} if s['stage'] == 2 else None), \
                         patch('readme_token_dispatch.read', side_effect=read_fixture), \
                         patch('readme_token_dispatch.restore_input'), \
                         patch('readme_token_dispatch.validate_prepared_trial', return_value=prepared), \
                         patch('readme_token_dispatch.graph_files', return_value=snapshot['files']), \
                         patch('readme_token_dispatch.sha', return_value='fixed-digest'):
                        if original:
                            admit(base, 3)
                            self.assertTrue((base / 'stages/stage3.json').exists())
                        else:
                            with self.assertRaisesRegex(ValueError, 'Required original DB code missing'):
                                admit(base, 3)
                            self.assertFalse((base / 'stages/stage3.json').exists())

    def test_all_controls_and_candidates_belong_to_the_new_study(self):
        base = Path('/new-fixed-comparison')
        slots = new_slots(base)
        self.assertEqual(len(slots), 54)
        self.assertEqual(len({(s['study'], s['label']) for s in slots}), 54)
        self.assertEqual([s['stage'] for s in slots[:18]],
                         [stage for stage in range(1, 7) for _ in range(3)])
        self.assertTrue(all(s['repetition'] == 0 for s in slots[:18]))
        self.assertTrue(all(Path(s['study']).parent == base for s in slots))
        for stage in range(1, 7):
            current = [s for s in slots if s['stage'] == stage]
            self.assertEqual(len(current), 9)
            self.assertEqual({s['topic'] for s in current}, {(stage - 1) % 3 + 1})
            for condition in ['fresh', 'current', 'candidate']:
                self.assertEqual([s['repetition'] for s in current if s['condition'] == condition], [0, 1, 2])

    def test_only_the_predeclared_matched_triple_supplies_the_next_history(self):
        plan = dict(slots=new_slots(Path('/new-fixed-comparison')))
        for stage in range(2, 7):
            reference = history_reference_slots(plan, stage)
            self.assertEqual(len(reference), 3)
            self.assertTrue(all(s['stage'] == stage - 1 and s['repetition'] == 0 for s in reference))
        plan['slots'] = [s for s in plan['slots'] if not (
            s['stage'] == 1 and s['repetition'] == 0 and s['condition'] == 'fresh')]
        with self.assertRaisesRegex(ValueError, 'complete fixed r0'):
            history_reference_slots(plan, 2)

    def test_failed_native_delivery_cannot_freeze_a_model_comparison(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            build = base / 'build'; build.mkdir()
            qualification = base / 'qualification'; qualification.mkdir()
            (build / 'result.json').write_text(json.dumps(dict(complete=True, runtimeSha256='unqualified')))
            (qualification / 'protocol.json').write_text(json.dumps(dict(candidate='unqualified')))
            (qualification / 'result.json').write_text(json.dumps(dict(
                complete=True, nativeIntegrityVerified=False, allStoredFullProbesDelivered=True)))
            with self.assertRaisesRegex(ValueError, 'must qualify'):
                qualified_source(build, qualification)

    def test_valid_native_delivery_does_not_require_every_example_in_full(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            build = base / 'build'; build.mkdir()
            qualification = base / 'qualification'; qualification.mkdir()
            binary = build / 'checkout/.lake/build/bin/eggshell'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'qualified-native-artifact')
            digest = hashlib.sha256(binary.read_bytes()).hexdigest()
            (build / 'result.json').write_text(json.dumps(dict(complete=True, runtimeSha256=digest)))
            (qualification / 'protocol.json').write_text(json.dumps(dict(candidate=digest)))
            (qualification / 'result.json').write_text(json.dumps(dict(
                complete=True, nativeIntegrityVerified=True, allStoredFullProbesDelivered=False,
                questionLevelDeliveryAccepted=True, missingRequiredCode=[],
                qualityAccepted=False, tokenReductionAccepted=False, tokenReductionPercent=-15)))
            source, runtime, _ = qualified_source(build, qualification)
            self.assertEqual(source, build / 'checkout')
            self.assertEqual(runtime, digest)

    def test_integrity_or_summaries_do_not_replace_required_original_code(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            build = base / 'build'; build.mkdir()
            qualification = base / 'qualification'; qualification.mkdir()
            binary = build / 'checkout/.lake/build/bin/eggshell'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'original-code-review-required')
            digest = hashlib.sha256(binary.read_bytes()).hexdigest()
            (build / 'result.json').write_text(json.dumps(dict(complete=True, runtimeSha256=digest)))
            (qualification / 'protocol.json').write_text(json.dumps(dict(candidate=digest)))
            native = dict(complete=True, nativeIntegrityVerified=True,
                          allStoredFullProbesDelivered=True, historicalSummaryDelivered=True)
            for review in [{}, dict(questionLevelDeliveryAccepted=False, missingRequiredCode=['branch']),
                           dict(questionLevelDeliveryAccepted=True, missingRequiredCode=['branch'])]:
                with self.subTest(review=review):
                    (qualification / 'result.json').write_text(json.dumps(dict(native, **review)))
                    with self.assertRaisesRegex(ValueError, 'Required original DB code'):
                        qualified_source(build, qualification)

    def test_withdrawn_candidate_cannot_freeze_even_with_valid_delivery(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            build = base / 'build'; build.mkdir()
            qualification = base / 'qualification'; qualification.mkdir()
            binary = build / 'checkout/.lake/build/bin/eggshell'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'qualified-but-withdrawn-artifact')
            digest = hashlib.sha256(binary.read_bytes()).hexdigest()
            (build / 'result.json').write_text(json.dumps(dict(complete=True, runtimeSha256=digest)))
            (qualification / 'protocol.json').write_text(json.dumps(dict(candidate=digest)))
            (qualification / 'result.json').write_text(json.dumps(dict(
                complete=True, nativeIntegrityVerified=True, allStoredFullProbesDelivered=True)))
            (build / 'withdrawn.json').write_text(json.dumps(dict(reason='Explicit candidate review')))
            with self.assertRaisesRegex(ValueError, 'Candidate withdrawn'):
                qualified_source(build, qualification)


if __name__ == '__main__':
    unittest.main()
