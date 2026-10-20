#!/usr/bin/env python3
"""Preserve the real historical LLVM observation corpus for latency only."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

from context_native_probe import environment, sha
from semantic_latency import execute, graph_files, save


SEED_SHA256 = '4c6b1f9b5549c23603ae324b0926ba9049430f8b2f8c4cc541cc611ea2441c21'
SUBJECT_COMMIT = '6dfe1677ab8dffbc6ec13d53a1e0215d75147689'
MARKER = 'llvm::PrettyStackTraceString CrashInfo'
QUESTIONS = [
    'Find the saved Clang Driver::BuildCompilation observations about the construction of a Compilation.',
    'Show saved evidence for how Clang builds a Compilation in Driver::BuildCompilation.',
    'Retrieve the recorded implementation of Driver::BuildCompilation in the Clang driver.',
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['legacy', 'source-protocol', 'workspace', 'import-build', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args(); legacy = args.legacy.resolve(); build = args.import_build.resolve()
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=False, mode=0o700)
    qualified = json.loads((build / 'result.json').read_text())
    helper = build / 'checkout/.lake/build/bin/import_scale_graph'
    if not qualified['passed'] or sha(helper) != qualified['importHelperSha256']:
        raise ValueError('Actual-corpus import requires the qualified original-policy helper')
    if sha(legacy) != SEED_SHA256:
        raise ValueError('The real LLVM saved observation corpus differs from the historical frozen seed')
    workspace = args.workspace.resolve()
    commit = subprocess.check_output(['git', '-C', str(workspace), 'rev-parse', 'HEAD'], text=True).strip()
    status = subprocess.check_output(['git', '-C', str(workspace), 'status', '--porcelain'], text=True)
    if commit != SUBJECT_COMMIT or status:
        raise ValueError('The LLVM source workspace differs from the recorded clean snapshot')
    saved = json.loads(legacy.read_text()); nodes = saved[2]; gold = []; works = []
    for ordinal, root in enumerate(saved[4]):
        node = nodes[root]
        if node[:2] != ['apply', 'outcome']:
            continue
        work, body = [nodes[ref[1]] for ref in node[2][:2]]
        if work[0] == 'atom' and isinstance(work[1], str):
            works.append(work[1])
        if body[0] == 'atom' and isinstance(body[1], str) and MARKER in body[1]:
            gold.append(ordinal)
    if not gold or any(MARKER in text for text in works + QUESTIONS):
        raise ValueError('The fixed evidence marker is absent from bodies or leaks through Work/the question')
    source_protocol = args.source_protocol.resolve()
    declaration = dict(source=str(legacy), sourceSha256=SEED_SHA256,
        sourceProtocol=str(source_protocol), sourceProtocolSha256=sha(source_protocol),
        historicalUse='LLVM Clang driver follow-up experiment, 2026-09-12; latency provenance only',
        workspace=str(workspace), subjectCommit=commit,
        sourceRoots=len(saved[4]), sourceDistinctRoots=len(set(saved[4])), sourceUnions=len(saved[5]),
        bodyMarker=MARKER, goldRootOrdinals=gold, questions=QUESTIONS,
        importHelperSha256=sha(helper), importSourceSha256=sha(build / 'checkout/tools/ImportScaleGraph.lean'),
        generationModelCalls=0, historicalTokenResultsReused=False, productionAdoption=False)
    save(output / 'declaration.json', declaration)
    shutil.copy2(legacy, output / 'legacy-work.egg'); shutil.copy2(source_protocol, output / 'historical-protocol.md')
    config = output / 'empty.toml'; config.write_text('default = "empty"\nsemantic_matcher = false\n[profiles.empty]\nread = []\n')
    prefix = output / 'empty-prefix'; prefix.mkdir()
    env = environment(output / 'import-data', config, prefix)
    raw, timing = execute([helper, output / 'legacy-work.egg', output / 'source.egg'], output / 'import', env, output, timeout=600)
    imported = json.loads(raw)
    if (imported['sourceSha256'] != SEED_SHA256 or not imported['allValuesAndReferencesPreserved']
            or imported['roots'] != len(saved[4]) or imported['unions'] != len(saved[5])):
        raise ValueError('The actual saved corpus was changed or filtered during import')
    bindings = imported['rootBindings']
    if len(bindings) != len(saved[4]) or [row[0] for row in bindings] != list(range(len(saved[4]))):
        raise ValueError('The imported root catalogue cannot bind the recorded gold sources')
    if sha(legacy) != SEED_SHA256 or sha(output / 'legacy-work.egg') != SEED_SHA256:
        raise ValueError('The original frozen seed changed')
    fixture = dict(label='actual-llvm', database=str(output / 'source.egg'), documents=imported['documents'],
        windowReferences=imported['windowReferences'], uniqueWindows=imported['uniqueWindows'],
        maxOwnerWindows=imported['maxOwnerWindows'], head=imported['head'],
        graphFilesSha256=graph_files(output / 'source.egg'), bodyMarker=MARKER, questions=QUESTIONS,
        workspace=str(workspace), subjectCommit=commit,
        goldOwners=[bindings[index][1] for index in gold], provenance=declaration, importTiming=timing,
        sourceSaved=True, warmComplete=False, allValuesAndReferencesPreserved=True)
    save(output / 'fixture.json', fixture)
    save(output / 'result.json', dict(passed=True, fixture=fixture, generationModelCalls=0,
        historicalTokenResultsReused=False, productionAdoption=False))
    print(json.dumps(dict(passed=True, roots=imported['roots'], owners=imported['documents'],
                          windowReferences=imported['windowReferences'], uniqueWindows=imported['uniqueWindows'])))


if __name__ == '__main__':
    main()
