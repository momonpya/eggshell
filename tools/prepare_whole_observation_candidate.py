#!/usr/bin/env python3
"""Isolate bounded complete file observations before optional excerpt padding."""
import argparse
import os
from pathlib import Path
import shutil

from memory_guard import require_guard
from readme_preparation import clone
from readme_trial import sha
from semantic_latency import execute, save

ROOT = Path(__file__).resolve().parents[1]
BASE = Path('/Users/ovm/.codex/experiments/eggshell/scope-context-20261021/construction-3/checkout')
RUNTIME = '63a457d12b4f635722a03cb2a798583a84ff19ba29112edb992127da5d709bff'

HELPERS = r'''
/-- Original numbered stdout is a coverage hint, never a file-read or
equivalence certificate. Unknown or multi-file provenance remains contextual. -/
structure CompleteFileObservation where
  owner : Value
  slice : TransportSlice
  source : String
  lines : List Nat

def observationLineHints (text : String) : List Nat :=
  ((text.splitOn "\n").filterMap fun row =>
    let body := row.toList.dropWhile (fun char => char == ' ' || char == '\t')
    let digits := body.takeWhile Char.isDigit
    if digits.isEmpty || !(body.drop digits.length).head?.any
        (fun char => char == '\t' || char == ':') then none
    else (String.ofList digits).toNat?).eraseDups

def completeFileObservation? (question : String) (owner : OutcomeEdge)
    (sources : List SourceEvidence.Record) (slice : TransportSlice) :
    Option CompleteFileObservation := do
  if !Matcher.nativeOutcome owner then none else do
  let [record] := sources | none
  let [file] := record.files | none
  let some content := file.content | none
  if !record.valid || (question.splitOn file.relative).length < 2 then none else do
  let lines := observationLineHints (readableEvidence owner owner.outcome)
  if lines.isEmpty then none else
    -- Fingerprints keep different observed source states in different hint
    -- domains. Neither line numbers nor overlapping text assert equality.
    pure {
      owner := owner.relation
      slice := slice
      lines := lines
      source := record.workspace ++ "\n" ++ file.relative ++ "\n" ++ content.root}

/-- Fit complete admitted originals against the actual framed packet cost.
An oversized original does not consume novelty or prevent a later fit. -/
def fitCompleteFileObservations (chars bytes : Nat)
    (cost : List TransportSlice → Nat × Nat) (seed : List TransportSlice)
    (domain : List CompleteFileObservation) :
    Option {items : List {item : CompleteFileObservation // item ∈ domain} //
      (cost (seed ++ items.map (·.val.slice))).1 ≤ chars ∧
      (cost (seed ++ items.map (·.val.slice))).2 ≤ bytes} :=
  if initialFits : (cost seed).1 ≤ chars ∧ (cost seed).2 ≤ bytes then
    let measure := fun (items : List {item : CompleteFileObservation // item ∈ domain}) =>
      cost (seed ++ items.map (·.val.slice))
    let rec fit (fuel : Nat)
        (pool : List {item : CompleteFileObservation // item ∈ domain})
        (seen : Std.HashSet (String × Nat))
        (accepted : {items : List {item : CompleteFileObservation // item ∈ domain} //
          (measure items).1 ≤ chars ∧ (measure items).2 ≤ bytes}) :=
      match fuel with
      | 0 => accepted
      | fuel + 1 =>
          let novelty := fun item => item.val.lines.countP fun line =>
            !seen.contains (item.val.source, line)
          match pool.mergeSort (fun left right => novelty right ≤ novelty left) with
          | [] => accepted
          | first :: rest =>
              if novelty first == 0 then accepted else
              let next := accepted.val ++ [first]
              if fits : (measure next).1 ≤ chars ∧ (measure next).2 ≤ bytes then
                let seen := first.val.lines.foldl
                  (fun seen line => seen.insert (first.val.source, line)) seen
                fit fuel rest seen ⟨next, fits⟩
              else fit fuel rest seen accepted
    some (fit domain.length domain.attach {} ⟨[], by simpa [measure] using initialFits⟩)
  else none

'''

INTEGRATION = r'''
      -- A literal file in the current request can justify complete original
      -- observations, without increasing the configured packet ceilings.
      -- Other requests retain the earlier plan exactly.
      let completeEntries := if enforce then [] else rawSlices.filterMap fun slice => do
        let first ← slice.members.head?
        if !entries.any (·.1 == first.matched.edge.relation) then none else do
        let members := slice.members.filter (·.matched.retrieved)
        if members.isEmpty then none else do
        let whole ← rawSlice (if stagedVisible then staged else []) true (ownerKey first, members)
        completeFileObservation? (requestQuestion.getD "") first.matched.edge first.sources whole
      let completeSupport := if enforce then [] else surrounding.filterMap fun source => do
        if !neighbors.any (·.1 == source.owner.relation) then none else
        completeFileObservation? (requestQuestion.getD "") source.owner source.provenance
          (renderSourceSupport source)
      let domain := choices.filterMap fun choice =>
        (completeEntries ++ completeSupport).find? (·.owner == choice.1)
      let seed := (interpretation.bind fun owner =>
        (choices.find? (·.1 == owner.val.relation)).map
          (fun choice => choice.2.2.getLast?.getD choice.2.1)).toList
      match fitCompleteFileObservations budget (byteBudget.getD (budget * 4)) packetCost seed domain with
      | none => ordinary
      | some accepted =>
          if accepted.val.isEmpty then ordinary else
          let whole := accepted.val.map (·.val.slice)
          let packetStart := seed ++ whole
          let startCost := packetCost packetStart
          let funded := (min budget (max available.1 startCost.1),
            min (byteBudget.getD (budget * 4)) (max available.2 startCost.2))
          let owners := accepted.val.map (·.val.owner) ++
            interpretation.toList.map (·.val.relation)
          let remaining := (choices.filter fun choice => !owners.contains choice.1).map (·.2)
          let costRemaining := fun suffix => packetCost (packetStart ++ suffix)
          match boundedFlexiblePacketSlices funded.1 funded.2 costRemaining remaining priority preference with
          | some fitted => packetStart ++ fitted.val
          | none => packetStart
'''


def main(output):
    require_guard(dict(memoryGuardSha256=sha(ROOT / 'tools/memory_guard.py')))
    if output.exists() or sha(BASE / '.lake/build/bin/eggshell') != RUNTIME:
        raise ValueError('Preserve prior candidates and the fixed input runtime')
    output.mkdir(parents=True)
    checkout = output / 'checkout'
    clone(BASE, checkout)
    shutil.copy2(__file__, output / 'executed-constructor.py')
    path = checkout / 'Eggshell/Handoff.lean'
    before = path.read_text()
    start = 'def renderAutomatic (staged : List Value) (budget : Nat) (current : String)'
    changed = before.replace(start, HELPERS + start)
    block_start = changed.index('      match boundedFlexiblePacketSlices available.1 available.2 packetCost slices priority preference with')
    block_end = changed.index('      else if reserved > budget', block_start)
    block = changed[block_start:block_end]
    changed = changed[:block_start] + '      let ordinary :=\n' + ''.join('  ' + line if line.strip() else line for line in block.splitlines(True)) + INTEGRATION + changed[block_end:]
    if changed == before or changed.count(HELPERS) != 1:
        raise ValueError('Reinspect the exact rendering boundary')
    path.write_text(changed)
    shutil.copy2(ROOT / 'tools/CompleteObservationTests.lean', checkout / 'tools/CompleteObservationTests.lean')
    with (checkout / 'lakefile.lean').open('a') as stream:
        stream.write('\nlean_exe complete_observation_tests where\n  root := `tools.CompleteObservationTests\n')
    save(output / 'manifest.json', dict(base=str(BASE), baseRuntimeSha256=RUNTIME,
        sourceBeforeSha256=sha(BASE / 'Eggshell/Handoff.lean'), sourceAfterSha256=sha(path),
        answeringModelCalls=0, productionAdoption=False))
    env = dict(os.environ, LEAN_NUM_THREADS='1', HF_HUB_OFFLINE='1')
    execute(['lake', '--no-cache', 'build', 'eggshell', 'complete_observation_tests',
             'scope_context_tests', 'Eggshell.ContractAudit'], output / 'build', env, checkout, timeout=900)
    for test in ['complete_observation_tests', 'scope_context_tests']:
        execute([checkout / '.lake/build/bin' / test], output / test, env, checkout)
    for relative in ['Eggshell/SearchProvider.lean', 'Eggshell/SemanticMatcher.lean',
                     'runtime/embedding.py', 'Eggshell/MiniLM.lean', 'Eggshell/PluginHooks.lean', 'Eggshell/Worker.lean']:
        if sha(BASE / relative) != sha(checkout / relative):
            raise ValueError('Changed another numerical or authority boundary')
    save(output / 'result.json', dict(complete=True, runtimeSha256=sha(checkout / '.lake/build/bin/eggshell'),
        answeringModelCalls=0, productionAdoption=False, qualityAccepted=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    main(parser.parse_args().output)
