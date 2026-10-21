#!/usr/bin/env python3
"""Isolate complete recorded scope headings; numerical retrieval stays fixed."""
import argparse
import os
from pathlib import Path
import shutil

from memory_guard import require_guard
from readme_preparation import clone
from readme_trial import sha
from semantic_latency import execute, save

ROOT = Path(__file__).resolve().parents[1]
BASE = Path('/Users/ovm/.codex/experiments/eggshell/window-centroid-20261020/construction-3/checkout')
RUNTIME = '415bcc2cd64412dad79d089da89f20533048901e5536f3d7206bdaa372b6f6f4'


def main(output):
    require_guard(dict(memoryGuardSha256=sha(ROOT / 'tools/memory_guard.py')))
    if output.exists() or sha(BASE / '.lake/build/bin/eggshell') != RUNTIME:
        raise ValueError('Preserve existing candidates and the fixed input runtime')
    output.mkdir(parents=True)
    checkout = output / 'checkout'
    clone(BASE, checkout)
    shutil.copy2(__file__, output / 'executed-constructor.py')
    shutil.copy2(ROOT / 'tools/ScopeContextTests.lean', checkout / 'tools/ScopeContextTests.lean')
    path = checkout / 'Eggshell/Handoff.lean'
    before = path.read_text()
    needle = '''    if paragraphStart || body.startsWith "# " || body.startsWith "##" ||
        (body.toList.head?.any Char.isAlpha && (body.contains '(' || body.endsWith ":")) then
'''
    replacement = '''    -- Indented scope labels belong to the original record too. Their
    -- conditions must precede a selected result, just as prose headings do.
    -- Numbered gaps above still reset this local hint; no relation or
    -- completion authority is inferred from indentation or punctuation.
    let label := String.ofList (body.toList.dropWhile (fun char => char == ' ' || char == '\\t'))
    let scopeLabel := scopeLabels && label.endsWith ":" && label.toList.head?.any Char.isAlpha
    let indentation := (body.toList.takeWhile (fun char => char == ' ' || char == '\\t')).length
    -- A monotone indentation stack prevents an earlier branch from lending
    -- its label to a following function or sibling record. Retain a still
    -- enclosing label when only an inner scope ends.
    if !blank && !scopeLabel then
      let enclosing := scopes.dropWhile (fun row => indentation <= row.1)
      if enclosing.length != scopes.length then
        heads := (offset, enclosing.head?.map Prod.snd) :: heads
      scopes := enclosing
    if scopeLabel && 0 < indentation then
      scopes := (indentation, offset) :: scopes.dropWhile (fun row => indentation <= row.1)
    if paragraphStart || body.startsWith "# " || body.startsWith "##" || scopeLabel ||
        (body.toList.head?.any Char.isAlpha && (body.contains '(' || body.endsWith ":")) then
'''
    if before.count(needle) != 1:
        raise ValueError('Reinspect the exact context heading scanner')
    changed = before.replace(needle, replacement)
    stack = '  let mut previousDelimiter : Option Char := none\n'
    reset = '      heads := (offset, none) :: heads\n      paragraph := true\n'
    if changed.count(stack) != 1 or changed.count(reset) != 1:
        raise ValueError('Reinspect the scope stack and numbered-gap reset')
    changed = changed.replace(stack, stack + '  let mut scopes : List (Nat × Nat) := []\n')
    changed = changed.replace(reset, '      scopes := []\n' + reset)
    signature = '''def contextStructureHeads (source : String) (layout : Option (DecodedLayout source)) :
'''
    if changed.count(signature) != 1:
        raise ValueError('Reinspect the original heading scanner signature')
    changed = changed.replace(signature, '''def contextStructureHeads (source : String) (layout : Option (DecodedLayout source))
    (scopeLabels : Bool := false) :
''')
    # Keep original cue ranking, context demand and minimum reservations.
    # Scope labels enrich rendered cues; they cannot change the planner's
    # earlier choice of which original observations need packet space.
    for name in ['prepareCueViews', 'prepareCueViewsFast']:
        start = changed.index('def ' + name + ' ')
        stop = changed.index('\n\n', changed.index('  let candidates :=', start))
        block = changed[start:stop]
        block = block.replace('  let candidates := ranges.map fun range =>',
            '  let scopedHeads := contextStructureHeads source decoded true\n  let candidates := ranges.map fun range =>')
        required = '    let required := if isEntry then complete else coherentRecordContext records heads complete 1024\n'
        if block.count(required) != 1:
            raise ValueError('Reinspect the rendered cue reservation')
        block = block.replace(required, required + '''    let scope := prerequisiteContextRange records scopedHeads range
    let required := if bounds : scope.start < required.start ∧ required.stop - scope.start ≤ 2048 then
      (⟨scope.start, required.stop, Nat.lt_trans bounds.1 required.ordered,
        required.within, bounds.2⟩ : EvidenceRange source)
      else required
''')
        changed = changed[:start] + block + changed[stop:]
    path.write_text(changed)
    (output / 'Handoff-before.lean').write_text(before)
    lakefile = checkout / 'lakefile.lean'
    with lakefile.open('a') as stream:
        stream.write('\nlean_exe scope_context_tests where\n  root := `tools.ScopeContextTests\n')
    save(output / 'manifest.json', dict(base=str(BASE), baseRuntimeSha256=RUNTIME,
        sourceBeforeSha256=sha(BASE / 'Eggshell/Handoff.lean'), sourceAfterSha256=sha(path),
        scope='Retain original indented colon headings with a nominated result; same window coordinates, byte/character budgets and authority checks',
        answeringModelCalls=0, productionAdoption=False))
    env = dict(os.environ, LEAN_NUM_THREADS='1', HF_HUB_OFFLINE='1')
    execute(['lake', '--no-cache', 'build', 'eggshell', 'scope_context_tests', 'Eggshell.ContractAudit'],
            output / 'build', env, checkout, timeout=900)
    execute([checkout / '.lake/build/bin/scope_context_tests'], output / 'checks', env, checkout)
    for relative in ['runtime/embedding.py', 'Eggshell/MiniLM.lean', 'Eggshell/SearchProvider.lean',
                     'Eggshell/PluginHooks.lean', 'Eggshell/Worker.lean']:
        if sha(BASE / relative) != sha(checkout / relative):
            raise ValueError('Candidate changed another search or authority boundary')
    if sha(BASE / '.lake/build/bin/eggshell') != RUNTIME:
        raise ValueError('Input runtime changed')
    save(output / 'result.json', dict(complete=True, runtimeSha256=sha(checkout / '.lake/build/bin/eggshell'),
        scope='Build and bounded context checks; native evidence, token and quality gates still required',
        answeringModelCalls=0, productionAdoption=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    main(parser.parse_args().output)
