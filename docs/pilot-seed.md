# Frozen scripted seed checkpoint

`tools/pilot_seed.py` freezes one existing [scripted observation fixture](pilot-memory-probe.md)
into a shared checkpoint: the saved DB and derived cache, native rollout through
the completed seed turn, recorded final answer, source hashes and warm receipt.
`tools/pilot_seed_probe.py` checks independent native continuations from that
same checkpoint. This prepares repeatable cells for the [pilot runner](pilot-protocol.md).
It does not acquire a model-generated study seed or measure model outcomes.

## Checkpoint and restoration contract

The source qualification must declare scripted responses, zero model trials and
zero study-seed acquisitions. Its native writer must have completed. The freezer
extracts the unique final answer from the native response item associated with
that turn, checks source/graph hashes and zero active index tickets, and copies
the DB and native history without rewriting either. The bundle stores DB
identity and SHA-256 for every payload file. It is explicitly marked
`scripted-runner-fixture` / `study_seed = false`.

Consumers pin the manifest's SHA-256 outside the bundle and verify it before
each repetition. Rewriting payload hashes inside the manifest cannot substitute
another checkpoint. Missing/extra files, nested undeclared manifests, changed
history/answer, wrong DB identity, symlinks and relabeling as a study acquisition
are rejected. Five counterfactual controls cover these boundaries.

The complete bundle is protected with macOS immutable flags during the probe.
`egg doctor` checks the relocated DB on each repetition: private/read-only
profile, all five source windows valid, no missing/invalid vectors, same DB ID.
It performs no numerical inference. The native consumer has hooks and native
memory disabled and cannot directly read the checkpoint through model tools.

The version-matched CLI 0.145.0 `ThreadForkParams` schema was inspected before
using `thread/fork` with an explicit rollout path and inclusive `lastTurnId`.
Each fork creates a new ordinary thread under that repetition's private Codex
root; it is not an AgentControl child. The provider/model, cwd and command
permission profile are explicit, and automatic goal continuation is deferred.
No agent namespace is exposed and no delegation call is made.

Before continuing, the fork must contain exactly the saved completed turn and
its recorded answer. The first local HTTP request must retain the complete
original native prefix, including its question, tool-call/result pair and
recorded hook context. Pasting old text into a user message cannot satisfy this
check. The new request appends the prior answer and current question; native
environment updates remain captured. Both consumers receive the same question.
Distinct fixed result markers demonstrate that the first repetition's response
never enters the second. Both resulting histories contain only seed + own trial.

## Reproduce and observed result

```sh
python3 -B tools/pilot_seed_probe.py \
  --memory /absolute/pilot/qualified-memory-probe \
  --suite /absolute/pilot/task-suite \
  --output /absolute/pilot/new-seed-probe \
  --runtime-read-root /opt/homebrew \
  --runtime-read-root /Library/Developer/CommandLineTools
python3 -B tools/check_pilot_seed.py
```

Output must be new; prior evidence is retained. Final evidence is under
`/Users/ovm/.codex/experiments/eggshell/pilot-seed-20261020/qualified-complete/`:
bundle/manifest, helper fingerprints, native fork/read exchanges, both local
requests, doctor records, protected snapshots and results. The two independent
restores passed. Both had full 5/5 warm coverage, identical source-history and
answer digests, distinct new thread/turn IDs, no new hooks and no cross-trial
response. The checkpoint and all 50 source files remained unchanged; original
file flags were restored. All five integrity controls passed.

The final probe took 1.33 s, aggregate sampled peak 174,032 KiB under the
3,500,000 KiB guard. These two scripted repetitions qualify restoration only;
they are not the study's required three-or-more repetitions or a latency result.

## Remaining runner work

This closes restoration of the shared scripted checkpoint. The full task
runner still needs to connect source reset, task execution and frozen grading
to all six conditions, with initial/history definitions and equal repetitions
for all three topics. The actual study seed must be acquired once under fixed
model/reasoning settings and matched source snapshots, then shared across cells.
The scripted freezer rejects that different provenance rather than assigning
synthetic observations to the study dataset.

Forked histories also require an audited usage baseline: imported seed usage
cannot be counted again as trial spending or assumed to be zero. The current
offline usage auditor does not qualify these fork captures; they lack trial
attempt labels and synthetic responses have no billable-model usage. Live usage
capture, failed-request billing reconciliation and incorrect-reuse adjudication
remain open. No model trial, seed cost, quality result, token-savings claim or
production adoption follows from this checkpoint. The original deferred
`hook output missing` investigation stays deferred.
