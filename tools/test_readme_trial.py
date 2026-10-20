"""Admission and cost-retention tests; no App Server or answering model runs."""
import json
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import readme_benchmark as bench
from readme_trial import (capture_attempt, publication_preserved, sha,
                          validate_observed_trial, validate_prepared_trial)
from semantic_latency import graph_files, save


class PreparedTrialTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.case = self.base / 'prepared/trial'
        self.case.mkdir(parents=True)
        self.source = self.base / 'source.egg'
        self.database = self.base / 'active.egg'
        for path, revision in [(self.source, 1), (self.database, 2)]:
            path.mkdir()
            save(path / 'head', dict(identity='same-db', revision=revision))
            (path / 'pages').write_text('canonical source')
        self.environment_file = self.base / 'environments/candidate/environment.json'
        account = self.base / 'account'
        account.mkdir()
        (account / 'config.toml').write_text('model = "gpt-5.6-luna"\n')
        self.binary = self.base / 'prefix/libexec/eggshell'
        self.binary.parent.mkdir(parents=True)
        self.binary.write_text('frozen runtime')
        save(self.environment_file, dict(CODEX_HOME=str(account), EGGSHELL_PREFIX=str(self.base / 'prefix')))
        data = self.case / 'data'
        data.mkdir()
        (data / 'query').write_text('prepared query')
        self.body = 'EGGSHELL PRIOR WORK\nWORK GRAPH v1\n  GROUNDED OUTCOME\nknown source fact\n'
        self.prompt = json.loads((bench.ROOT / 'docs/benchmarks/llvm-three-topics.json').read_text())['prompts'][1].replace('<LLVM_SOURCE>', str(bench.LLVM))
        files = {
            'body.txt': self.body,
            'config.toml': 'default = "work"\n[eggs]\nwork = ' + json.dumps(str(self.database)) +
                '\n[profiles.work]\nread = ["work"]\nwrite = "work"\nhandoff_chars = 120000\n',
            'stdout.json': dict(hookSpecificOutput=dict(additionalContext=self.body)),
            'timing.json': dict(exitCode=0, elapsedMs=123),
            'input.json': dict(hook_event_name='UserPromptSubmit', prompt=self.prompt,
                cwd=str(bench.LLVM), _eggshell_config=str(self.case / 'config.toml'), session_id='qualified-session'),
            'state.json': dict(lastHandoff=self.body, deliveredGraphs=['a:' + json.dumps([
                self.prompt, dict(identity='same-db', nextRoot=1)])]),
            'shutdown.json': dict(exit_code=0, daemon_exit_code=0),
            'search.json': dict(data=dict(trace=dict(semantic='completed'))),
            'numerical.json': dict(data=dict(status='completed', corpus=dict(purpose='discovery'), counters=dict(
                source=dict(hit=1, absent=0, unusable=0), encoder=dict(sourceEncodeUs=0)))),
            'focus.json': dict(data=dict(status='completed', corpus=dict(purpose='focus'), counters=dict(
                source=dict(hit=1, absent=0, unusable=0), encoder=dict(sourceEncodeUs=0)))),
            'publication.json': dict(before=str(self.source), after=str(self.database),
                beforeHead=json.loads((self.source / 'head').read_text()),
                afterHead=json.loads((self.database / 'head').read_text()),
                authoritativeGraphEqual=True, beforeRoots=2, afterRoots=2, beforeUnions=0, afterUnions=0,
                changedRows=[dict(key='change:2:0', derived=False)],
                publications=[dict(revision=2, neutral=True, added=[], removed=[], unionsChanged=False)]),
            'evidence.json': dict(sourceGraphFiles=graph_files(self.source),
                facts=[dict(name='known fact', anchors=['known source fact'], storedOwners=['v1'])]),
        }
        for name, value in files.items():
            if isinstance(value, str):
                (self.case / name).write_text(value)
            else:
                save(self.case / name, value)
        self.protocol = dict(model='gpt-5.6-luna', effort='xhigh', generationAllowed=False,
            sourceWorkspace=str(bench.LLVM),
            structuredReceiptsAvailable=True,
            scheduledLabels=['trial'], candidate=sha(self.binary), activeDatabase=str(self.database),
            runnerSha256=sha(Path(bench.__file__)), transportSha256=sha(Path(bench.__file__).with_name('pilot_server.py')),
            trialGateSha256=sha(Path(bench.__file__).with_name('readme_trial.py')),
            memoryGuardSha256=sha(Path(bench.__file__).with_name('memory_guard.py')),
            trials=dict(trial=dict(arm='candidate', topic=1, stage=1, repetition=0)),
            sourceSnapshots={'1':dict(directory=str(self.source), files=graph_files(self.source))})
        self.ready = dict(label='trial', arm='candidate', topic=1, stage=1, repetition=0,
            sourceWorkspace=str(bench.LLVM),
            model='gpt-5.6-luna', effort='xhigh', promptSha256=hashlib.sha256(self.prompt.encode()).hexdigest(),
            sourceSnapshot=self.protocol['sourceSnapshots']['1'], environmentSha256=sha(self.environment_file),
            configurationSha256=sha(account / 'config.toml'),
            **{k:self.protocol[k] for k in ['runnerSha256', 'transportSha256', 'trialGateSha256', 'memoryGuardSha256']},
            memory=dict(runtimeSha256=sha(self.binary), database=str(self.database),
                graphFiles=graph_files(self.database), configuration='config.toml', dataRoot='data',
                privateFiles={'query':sha(data / 'query')}, publication='publication.json',
                preflightTiming='timing.json', preflightStdout='stdout.json', preflightState='state.json',
                preflightInput='input.json', preflightSession='qualified-session',
                body='body.txt', shutdown='shutdown.json', evidenceAudit='evidence.json',
                searchReceipt='search.json', numericalReceipts=['numerical.json', 'focus.json']))
        self.files = list(files)
        self.seal()

    def seal(self):
        self.ready['files'] = {name:sha(self.case / name) for name in self.files}
        save(self.case / 'ready.json', self.ready)
        self.protocol['preparedTrialDigests'] = {'trial':sha(self.case / 'ready.json')}
        save(self.base / 'protocol.json', self.protocol)

    def change(self, name, update):
        value = json.loads((self.case / name).read_text())
        update(value)
        save(self.case / name, value)
        self.seal()

    def validate(self, arm='candidate'):
        return validate_prepared_trial(self.base, self.protocol, arm, 'trial', 1, self.prompt, self.environment_file)

    def test_qualified_memory_and_neutral_publication(self):
        result = self.validate()
        self.assertEqual(result['environment']['EGGSHELL_DATA_ROOT'], str(self.case / 'data'))
        self.assertEqual(result['facts'][0]['deliveredOwners'], ['v1'])

    def test_fresh_has_common_snapshot_but_no_memory(self):
        self.protocol['trials']['trial']['arm'] = self.ready['arm'] = 'fresh'
        self.ready['memory'] = None
        self.seal()
        self.assertIsNone(self.validate('fresh')['expectedBodySha256'])

    def test_private_public_provider_cache_is_sealed_and_missing_counters_stay_unknown(self):
        cache = self.case / 'provider-cache'
        cache.mkdir()
        (cache / 'vector.json').write_text('prepared source and query vectors')
        memory = self.ready['memory']
        memory.update(providerCache='provider-cache', providerFiles={'vector.json':sha(cache / 'vector.json')},
                      searchReceipt=None, numericalReceipts=None)
        self.protocol['structuredReceiptsAvailable'] = False
        config = self.case / 'config.toml'
        original = config.read_text()
        config.write_text('semantic_matcher = ' + json.dumps([str(self.binary), 'search-provider', '--cache', str(cache)]) + '\n' + original)
        self.seal()
        self.assertIsNotNone(self.validate()['expectedBodySha256'])
        (cache / 'vector.json').write_text('changed vector')
        with self.assertRaisesRegex(ValueError, 'provider cache'):
            self.validate()
        (cache / 'vector.json').write_text('prepared source and query vectors')
        memory['providerCache'] = str(self.base)
        self.seal()
        with self.assertRaisesRegex(ValueError, 'provider cache'):
            self.validate()

    def test_missing_or_changed_preparation_rejects_before_server(self):
        (self.case / 'ready.json').write_text('{}')
        with patch.object(bench, 'BASE', self.base), patch.object(bench, 'BenchmarkServer') as server:
            with self.assertRaisesRegex(ValueError, 'preparation manifest'):
                bench.model_turn('candidate', 'trial', 1)
            server.assert_not_called()
        self.assertFalse((self.base / 'attempts').exists())

    def test_unknown_label_is_not_admitted(self):
        with self.assertRaisesRegex(ValueError, 'preparation manifest'):
            validate_prepared_trial(self.base, self.protocol, 'candidate', 'unknown', 1, self.prompt, self.environment_file)

    def test_incomplete_body_rejects_before_server_even_with_a_sealed_manifest(self):
        self.change('stdout.json', lambda v:v['hookSpecificOutput'].update(additionalContext='EGGSHELL SEARCH INCOMPLETE'))
        with patch.object(bench, 'BASE', self.base), patch.object(bench, 'BenchmarkServer') as server:
            with self.assertRaisesRegex(ValueError, 'memory body'):
                bench.model_turn('candidate', 'trial', 1)
            server.assert_not_called()
        self.assertFalse((self.base / 'attempts').exists())

    def test_source_and_private_state_changes_are_rejected(self):
        for path in [self.source / 'pages', self.database / 'pages', self.case / 'data/query', self.binary]:
            with self.subTest(path=path):
                original = path.read_bytes()
                path.write_bytes(original + b'changed')
                with self.assertRaises(ValueError):
                    self.validate()
                path.write_bytes(original)

    def test_changed_question_model_and_harness_are_rejected(self):
        for key, value in [('model', 'other-model'), ('effort', 'high'), ('runnerSha256', 'wrong')]:
            with self.subTest(key=key):
                original = self.ready[key]
                self.ready[key] = value
                self.seal()
                with self.assertRaises(ValueError):
                    self.validate()
                self.ready[key] = original
        self.seal()
        with self.assertRaisesRegex(ValueError, 'question'):
            validate_prepared_trial(self.base, self.protocol, 'candidate', 'trial', 1, 'different', self.environment_file)

    def test_bad_native_preflight_and_foreign_frontier_are_rejected(self):
        cases = [
            ('timing.json', lambda v:v.update(elapsedMs=30000)),
            ('timing.json', lambda v:v.update(exitCode=1)),
            ('input.json', lambda v:v.update(prompt='another question')),
            ('input.json', lambda v:v.update(_eggshell_config='another config')),
            ('state.json', lambda v:v.update(deliveredGraphs=[])),
            ('state.json', lambda v:v.update(deliveredGraphs=['a:' + json.dumps([
                'recorded question', dict(identity='foreign-db', nextRoot=1)])])),
            ('stdout.json', lambda v:v['hookSpecificOutput'].update(additionalContext='EGGSHELL SEARCH INCOMPLETE')),
            ('shutdown.json', lambda v:v.update(daemon_exit_code=1)),
            ('search.json', lambda v:v['data']['trace'].update(semantic='pending')),
            ('numerical.json', lambda v:v['data']['counters']['source'].update(absent=1)),
            ('numerical.json', lambda v:v['data']['counters']['encoder'].update(sourceEncodeUs=1)),
            ('evidence.json', lambda v:v['facts'][0].update(anchors=['not delivered'])),
            ('evidence.json', lambda v:v['facts'][0].update(storedOwners=['another-owner'])),
        ]
        for name, update in cases:
            with self.subTest(name=name, update=update):
                original = (self.case / name).read_bytes()
                self.change(name, update)
                with self.assertRaises(ValueError):
                    self.validate()
                (self.case / name).write_bytes(original)
                self.seal()

    def test_change_metadata_must_belong_to_verified_neutral_revision(self):
        report = json.loads((self.case / 'publication.json').read_text())
        publication_preserved(report, self.source, self.database)
        for key in ['change:99:0', 'change:2:unrelated', 'value:1']:
            report['changedRows'][0]['key'] = key
            with self.subTest(key=key), self.assertRaises(ValueError):
                publication_preserved(report, self.source, self.database)


class AttemptCaptureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.attempt = Path(self.temporary.name)
        (self.attempt / 'rpc').mkdir()
        self.messages = [dict(method='thread/tokenUsage/updated', params=dict(threadId='ours',
            tokenUsage=dict(total=dict(totalTokens=120, inputTokens=100, outputTokens=20,
                                      cachedInputTokens=80, reasoningOutputTokens=10))))]

    def capture(self, completed=True, tail=''):
        (self.attempt / 'rpc/exchange.jsonl').write_text(''.join(json.dumps(dict(direction='server', message=m))+'\n'
            for m in self.messages) + tail)
        return capture_attempt(self.attempt, 'ours', completed)

    def test_inclusive_usage_without_double_counting_cached_or_reasoning(self):
        usage, _ = self.capture()
        self.assertTrue(usage['finalUsageKnown'])
        self.assertEqual(usage['total']['totalTokens'], 120)

    def test_interrupted_or_partial_log_retains_known_cost_with_unknown_final(self):
        for completed, tail in [(False, ''), (True, '{"direction":')]:
            with self.subTest(completed=completed, tail=tail):
                usage, _ = self.capture(completed, tail)
                self.assertEqual(usage['total']['totalTokens'], 120)
                self.assertTrue(usage['unknownFinalUsage'])

    def test_unknown_usage_is_not_zero(self):
        self.messages = []
        usage, _ = self.capture()
        self.assertIsNone(usage['total'])
        self.assertFalse(usage['finalUsageKnown'])

    def test_foreign_thread_usage_and_inconsistent_totals_are_not_accepted(self):
        self.messages.append(dict(method='thread/tokenUsage/updated', params=dict(threadId='foreign',
            tokenUsage=dict(total=dict(totalTokens=999, inputTokens=998, outputTokens=1)))))
        usage, _ = self.capture()
        self.assertEqual(usage['total']['totalTokens'], 120)
        self.messages[0]['params']['tokenUsage']['total']['totalTokens'] = 121
        usage, _ = self.capture()
        self.assertEqual(usage['total']['totalTokens'], 121)
        self.assertFalse(usage['finalUsageKnown'])

    def test_failed_hook_without_context_and_reroute_invalidate_completed_generation(self):
        for message in [dict(method='hook/completed', params=dict(run=dict(eventName='preToolUse',
                           entries=[], durationMs=10, status='failed'))),
                        dict(method='model/rerouted', params=dict(model='other-model'))]:
            with self.subTest(message=message):
                self.messages.append(message)
                usage, packets = self.capture()
                with self.assertRaises(ValueError):
                    validate_observed_trial({}, usage, packets, 'fresh')
                self.assertEqual(usage['total']['totalTokens'], 120)
                self.messages.pop()

    def test_wrong_initial_body_is_invalid_and_its_cost_is_kept(self):
        self.messages.append(dict(method='hook/completed', params=dict(run=dict(eventName='userPromptSubmit',
            entries=[dict(kind='context', text='actual body')], durationMs=10, status='completed'))))
        usage, packets = self.capture()
        with self.assertRaisesRegex(ValueError, 'differs'):
            validate_observed_trial(dict(expectedBodySha256='different'), usage, packets, 'candidate')
        self.assertEqual(json.loads((self.attempt / 'usage.json').read_text())['total']['totalTokens'], 120)
        self.assertEqual((self.attempt / packets[0]['file']).read_text(), 'actual body')
        validate_observed_trial(dict(expectedBodySha256=packets[0]['sha256']), usage, packets, 'candidate')


if __name__ == '__main__':
    unittest.main()
