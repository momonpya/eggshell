#!/usr/bin/env python3
"""Build an isolated full-window-rank candidate without activating it."""
import os
from pathlib import Path
import shutil
import subprocess

from context_native_probe import sha
from semantic_latency import execute, save

ROOT = Path(__file__).resolve().parents[1]
BASE = Path('/Users/ovm/.codex/experiments/eggshell/window-centroid-20261020/construction-3/checkout')
OUTPUT = Path('/Users/ovm/.codex/experiments/eggshell/window-order-20261021/construction-2')
EXPECTED = '415bcc2cd64412dad79d089da89f20533048901e5536f3d7206bdaa372b6f6f4'


def replace(text, before, after):
    if text.count(before) != 1:
        raise ValueError('Reinspect the candidate transformation: ' + before[:100])
    return text.replace(before, after)


def main():
    if sha(BASE / '.lake/build/bin/eggshell') != EXPECTED:
        raise ValueError('The measured input runtime changed')
    if shutil.disk_usage(BASE).free < 2 * 1024**3:
        raise OSError('Need 2 GiB free before building another isolated candidate')
    OUTPUT.mkdir(parents=True, exist_ok=False, mode=0o700)
    checkout = OUTPUT / 'checkout'
    subprocess.run(['/bin/cp', '-cR', str(BASE), str(checkout)], check=True)
    for name in ['WindowRanks.lean', 'WindowRanksTests.lean']:
        shutil.copy2(ROOT / 'tools' / name, checkout / 'tools' / name)

    source = checkout / 'Eggshell/SearchProvider.lean'
    text = source.read_text()
    text = replace(text,
        '  positions := ((score, position) :: state.positions).mergeSort SearchRank.scoreOrder |>.take 16 }',
        '  positions := (score, position) :: state.positions }')
    text = replace(text,
        '      evidence := (index, result.positions.map Prod.snd) :: evidence',
        '''      let ordered := (result.positions.mergeSort SearchRank.scoreOrder).map Prod.snd
      let positions := if (request.getObjValAs? String "purpose").toOption == some "focus"
        then ordered else ordered.take 16
      evidence := (index, positions) :: evidence''')
    text = replace(text, 'structure IndexedMetrics where\n',
        'structure IndexedMetrics where\n  windowRankingPolicy : String := "complete focus order; cue limit follows lexical fusion"\n')
    source.write_text(text)

    source = checkout / 'Eggshell/SemanticMatcher.lean'
    text = source.read_text()
    first_import = text.index('public import ')
    text = text[:first_import] + 'public import tools.WindowRanks\n' + text[first_import:]
    text = replace(text, '  bounded : windows.length ≤ 32\n',
        '  bounded : windows.length ≤ document.windows.length\n')
    start = text.index('def indexedNominations (')
    stop = text.index('def indexedNominationsUsing (')
    nomination = text[start:stop]
    nomination = replace(nomination, 'WindowPull.check? document indices',
        'WindowRanks.Choices.check? document.windows.length indices')
    nomination = replace(nomination, 'WindowPull.check? document.val indices',
        'WindowRanks.Choices.check? document.val.windows.length indices')
    text = text[:start] + nomination + text[stop:]
    text = replace(text, 'cases checked : WindowPull.check? document.val\n',
        'cases checked : WindowRanks.Choices.check? document.val.windows.length\n')
    check = '''/-- A focused reply retains the complete original window domain. This is a
ranking check, never a grant for an unbounded source repair. -/
def completeWindowOrders (documents : List Persistence.Store.SearchDocument)
    (evidence : List WindowChoice) : Bool :=
  let directory := FirstIndex.make WindowChoice.document evidence
  evidence.length == documents.length && documents.zipIdx.all fun (document, index) =>
    (directory.read index).any fun choice =>
      choice.indices.mergeSort (· ≤ ·) == List.range document.windows.length

'''
    text = replace(text, 'def nominateIndexed (command : List String)',
        check + 'def nominateIndexed (command : List String)')
    text = replace(text,
        '      let some order := IndexedOrder.check? documents response.ranked |',
        '''      unless purpose != "focus" || completeWindowOrders documents response.evidence do
        throw (IO.userError "focused window order is not the complete original source")
      let some order := IndexedOrder.check? documents response.ranked |''')
    source.write_text(text)

    source = checkout / 'Eggshell/Handoff.lean'
    text = source.read_text()
    text = replace(text, '  SearchRank.select windows.length semantic.length []\n',
        '  SearchRank.select windows.length (min 16 semantic.length) []\n')
    text = replace(text,
        '''    (semantic : List Nat) : (focusedEvidenceWindows question windows semantic).length ≤ semantic.length :=
  SearchRank.selected_within_budget _ _ _ _''',
        '''    (semantic : List Nat) : (focusedEvidenceWindows question windows semantic).length ≤ semantic.length := by
  exact Nat.le_trans
    (SearchRank.selected_within_budget windows.length (min 16 semantic.length) [] _)
    (Nat.min_le_right _ _)''')
    source.write_text(text)

    # The independent reference oracle follows the new source-domain bound;
    # its malformed/duplicate/foreign cases remain intact.
    fixture = checkout / 'tools/RankDirectoryTests.lean'
    text = fixture.read_text()
    fixture.write_text(replace(text, 'SemanticMatcher.WindowPull.check? document indices',
        'Eggshell.WindowRanks.Choices.check? document.windows.length indices'))
    lakefile = checkout / 'lakefile.lean'
    text = lakefile.read_text()
    text += '\nlean_lib WindowRanksResearch where\n  roots := #[`tools.WindowRanks]\n'
    text += '\nlean_exe window_ranks_tests where\n  root := `tools.WindowRanksTests\n'
    lakefile.write_text(text)
    changed = ['Eggshell/SearchProvider.lean', 'Eggshell/SemanticMatcher.lean', 'Eggshell/Handoff.lean',
               'tools/RankDirectoryTests.lean', 'lakefile.lean', 'tools/WindowRanks.lean', 'tools/WindowRanksTests.lean']
    save(OUTPUT / 'manifest.json', dict(base=str(BASE), baseRuntimeSha256=EXPECTED,
        sources={name: sha(checkout / name) for name in changed},
        scope='Retain complete numerical window order for focus, fuse before retaining 16 cues; original source ownership and 32-window repair bound remain checked',
        sourceVectorsAndEncoderUnchanged=True, lexicalGrammarUnchanged=True,
        generationModelCalls=0, productionAdoption=False))
    shutil.copy2(__file__, OUTPUT / 'executed-constructor.py')
    env = dict(os.environ, LEAN_NUM_THREADS='1', HF_HUB_OFFLINE='1')
    env.pop('EGGSHELL_CONFIG', None)
    execute(['lake', '--no-cache', 'build', 'eggshell', 'delivery_audit', 'window_ranks_tests',
        'rank_directory_tests', 'Eggshell.ContractAudit'], OUTPUT / 'build', env, checkout, timeout=600)
    for target in ['window_ranks_tests', 'rank_directory_tests']:
        execute([checkout / '.lake/build/bin' / target], OUTPUT / target, env, checkout, timeout=60)
    if sha(BASE / '.lake/build/bin/eggshell') != EXPECTED:
        raise ValueError('The candidate changed its measured input runtime')
    save(OUTPUT / 'result.json', dict(passed=True, candidateSha256=sha(checkout / '.lake/build/bin/eggshell'),
        scope='Build and boundary checks only; native deadline, total tokens and quality are untested',
        generationModelCalls=0, productionAdoption=False))


if __name__ == '__main__':
    main()
