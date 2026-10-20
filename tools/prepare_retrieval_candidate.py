#!/usr/bin/env python3
"""Compose complete-context embeddings and indexed 2-grams in one isolated build."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

import context_candidate as context
import lexical_candidate as lexical
from prepare_context_candidate import input_manifest, sha, write, TARGETS as CONTEXT_TARGETS
from prepare_lexical_candidate import TARGETS as LEXICAL_TARGETS, execute


HELPERS = [
    'RetrievalCategories.lean', 'RetrievalGrams.lean', 'RetrievalGramsTests.lean',
    'RetrievalIndex.lean', 'RetrievalIndexTests.lean', 'LexicalProbe.lean', 'ContextWindowTests.lean',
    'RetrievalScale.lean', 'RetrievalTerms.lean',
    'context_candidate.py', 'context_encoding.py', 'lexical_candidate.py',
    'prepare_retrieval_candidate.py',
]


def overlays(source, inputs):
    result = {name: transform((source / name).read_text())
              for name, transform in lexical.TRANSFORMS.items() if name != 'Eggshell/Warm.lean'}
    result['Eggshell/SearchProvider.lean'] = context.provider((source / 'Eggshell/SearchProvider.lean').read_text())
    warm = lexical.warm(context.warm((source / 'Eggshell/Warm.lean').read_text()))
    result['Eggshell/Warm.lean'] = context.once(warm,
        '      valid := 0, missing := 0, invalid := 0}',
        '      valid := 0, missing := 0, invalid := 0\n' +
        '      encoderContract := SearchProvider.encoderContract, input := {}}')
    result['runtime/embedding.py'] = context.numerical((source / 'runtime/embedding.py').read_text(),
        (source / 'tools/context_encoding.py').read_text(), inputs)
    result['TestMain.lean'] = lexical.main_fixture(context.main_test_fixture((source / 'TestMain.lean').read_text()))
    result['tests/ReadOnlyCacheTests.lean'] = context.readonly_test_fixture(
        (source / 'tests/ReadOnlyCacheTests.lean').read_text())
    for name in ['tests/PageDBTests.lean', 'tests/SemanticDeadlineTests.lean']:
        result[name] = lexical.FIXTURES[name]((source / name).read_text())
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['source', 'support', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args(); source = args.source.resolve(); output = args.output.resolve()
    if output.is_relative_to(source) or source.is_relative_to(output):
        parser.error('Use a separate experiment directory')
    output.mkdir(parents=True, exist_ok=False, mode=0o700); checkout = output / 'checkout'; checkout.mkdir()
    names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=source).decode().strip('\0').split('\0')
    names = sorted(set(names + ['tools/' + name for name in HELPERS]))
    frozen = {name: sha(source / name) for name in names}
    for name in names:
        path = source / name
        if path.is_symlink() or not path.is_file():
            raise ValueError('Candidate sources must be regular files')
        (checkout / name).parent.mkdir(parents=True, exist_ok=True); shutil.copy2(path, checkout / name)
    (checkout / 'lakefile.lean').write_text((source / 'lakefile.lean').read_text() + LEXICAL_TARGETS +
        CONTEXT_TARGETS + '\nlean_exe retrieval_scale where\n  root := `tools.RetrievalScale\n' +
        '\nlean_exe retrieval_terms where\n  root := `tools.RetrievalTerms\n')
    (checkout / '.lake').mkdir()
    subprocess.run(['/bin/cp', '-cpR', str(source / '.lake/build'), str(checkout / '.lake/build')], check=True, timeout=60)
    ordinary = source / '.lake/build/bin/eggshell'; original = sha(ordinary)
    if ordinary.stat().st_ino == (checkout / '.lake/build/bin/eggshell').stat().st_ino:
        raise ValueError('Candidate outputs alias production')
    inputs = input_manifest(args.support)
    write(output / 'encoder-inputs.json', inputs)
    write(output / 'manifest.json', dict(sourceHashes=frozen, productionBinarySha256=original,
        productionAdoption=False, generationModelCalls=0))
    # Retain the actual original save-time retrieval policy for common fixtures.
    execute(checkout, output, 'legacy-seed-build', ['lake', '--no-cache', 'build', 'lexical_probe', 'retrieval_scale'])
    shutil.copy2(checkout / '.lake/build/bin/lexical_probe', output / 'legacy-seed')
    shutil.copy2(checkout / '.lake/build/bin/retrieval_scale', output / 'legacy-scale-producer')
    rendered = overlays(source, inputs)
    for name, value in rendered.items():
        (checkout / name).write_text(value)
    compile(rendered['runtime/embedding.py'], 'embedding.py', 'exec')
    write(output / 'overlays.json', {name: sha(checkout / name) for name in rendered})
    execute(checkout, output, 'build', ['lake', '--no-cache', 'build', 'eggshell', 'eggshell_tests',
        'lexical_probe', 'context_window_tests', 'retrieval_grams_tests', 'retrieval_index_tests',
        'semantic_latency', 'retrieval_scale', 'retrieval_terms', 'Eggshell.ContractAudit'])
    for label in ['context_window', 'retrieval_grams', 'retrieval_index']:
        execute(checkout, output, label + '-tests', [str(checkout / '.lake/build/bin' / (label + '_tests'))])
    if sha(ordinary) != original or any(sha(source / name) != expected for name, expected in frozen.items()):
        raise ValueError('The combined candidate changed its production inputs')
    if input_manifest(args.support) != inputs:
        raise ValueError('Encoder assets changed during qualification')
    write(output / 'result.json', dict(passed=True, candidateSha256=sha(checkout / '.lake/build/bin/eggshell'),
        legacySeedSha256=sha(output / 'legacy-seed'),
        legacyScaleProducerSha256=sha(output / 'legacy-scale-producer'),
        scaleHelperSha256=sha(checkout / '.lake/build/bin/retrieval_scale'), modelAssetsUnchanged=True,
        productionFilesUnchanged=True, generationModelCalls=0, productionAdoption=False))
    print(json.dumps(dict(passed=True, checkout=str(checkout))))


if __name__ == '__main__':
    main()
