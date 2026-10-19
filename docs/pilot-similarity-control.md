# Isolated similarity-equality control

The sixth [pilot condition](pilot-protocol.md) deliberately allows semantic
recommendations to nominate equality. `tools/prepare_pilot_similarity.py` builds
that executable in a separate experiment directory. Production source, the
default Lake targets, installed user runtime and production binary remain unchanged.
This is an experimental control, not a candidate for production adoption.

## Exact intervention

The ordinary indexed discovery computes and grounds its matches first, using
the same semantic provider, nominations and ranking. The isolated overlay then
passes those matches through `tools/PilotSimilarityControl.lean` before discovery
accumulates them and records admission observations. When the configured search
is semantic, the adapter changes only `retrieved = true` to `retrieved = false`.
Intrinsic matches and lexical-only/fallback matches remain unchanged.

This admits broad retrieval alignments to the ordinary run-local union lane.
It does not directly set fragment identity or completed status. Saturation must
create a real union before ordinary applicability/extraction can omit Work.
The numerical search threshold, warm policy, native-nomination policy, deadlines,
Exact-footprint check, child-membership check, source freshness checks, observed
result bytes and output publication path are retained. The assumed equality can
itself affect later equivalence/membership decisions; those effects belong to
the intervention and must be retained in the trajectory.

The transform is applied **after** the ordinary matcher's preparation certificate.
That certificate does not prove the experimental assumption semantically sound.
The control is intentionally fallible and cannot supply a production correctness
claim or be pooled into the ordinary Phase 3 congruence denominator.

The IO adapter requires `EGGSHELL_PILOT_SIMILARITY_CONTROL=1`. Before promotion it
records the original semantic nominations, owners, demands, compared fragments,
child status and incoming identity status under the private `EGGSHELL_DATA_ROOT`
in `pilot-similarity-control.jsonl`. These are identity *nominations*, not evidence
that a union or completed delivery happened. Actual unions/extraction still need
the native receipts. The marker and private data root must be explicit in the
eventual runner; no production configuration option enables this intervention.

## Reproduce the build and checks

On the observed macOS host with Lean 4.33.0 and an existing candidate build:

```sh
python3 -B tools/prepare_pilot_similarity.py \
  --source /absolute/eggshell-checkout \
  --output /absolute/pilot/new-similarity-control
```

Use the aggregate 3,500,000 KiB process guard for this build. Output must be new;
old runs, including failed construction attempts, remain intact. The tool copies
the tracked source snapshot and seals its hashes. It adds the research module,
its test executable and a private Lake target, then applies an exact-anchor
overlay to indexed discovery. An upstream boundary change requires re-auditing
the patch rather than silently applying it elsewhere.

The compiler cache is copied with APFS clones into the experiment, with separate
writable inodes. It is never symlinked back to production. The tool builds and
runs the isolated tests, builds the actual control runtime, checks its private
nomination journal, and verifies that all original tracked files and the
production executable remained unchanged during preparation. No model or
embedding-provider trial is launched by this builder.

## Observed qualification and limits

Evidence is under
`/Users/ovm/.codex/experiments/eggshell/pilot-similarity-20261020/qualified-1/`:
source/helper/overlay manifest, private checkout, full build logs, executable
fingerprints, control-test output and the private nomination journal.

The disjoint-text fixture has a fixed semantic nomination. Ordinary retrieval
stays advisory with no union/completed use; enabling the intervention creates
an actual run-local union and admits completed child Work. Additional checks
retain the parent-with-no-child guard, absent-nomination behavior, all other
Match fields, intrinsic/lexical behavior and the Exact-footprint boundary.
IO checks reject a missing experiment marker and retain the original nominated
Match before changing its admission lane.

The isolated test executable and runtime both built successfully. All 220
original tracked files and the production executable were unchanged during the
build. The complete qualification took 31.42 s, aggregate sampled peak
2,712,144 KiB under the 3,500,000 KiB guard. This is build/fixture evidence,
not a model outcome, token result or latency distribution.

Five context paths have [scripted native transport evidence](pilot-history-probe.md).
This sixth path now has an isolated implementation and a built executable, but
its installed plugin, real warm-DB semantic nominations, native receipt ancestry
and body/omission behavior still need qualification. A synthetic nomination
cannot substitute for that check. The complete task runner, common study seed
and repeatable native history, model/settings/order/limits, incorrect-reuse
adjudication and billed-attempt reconciliation remain open. No actual model
trial or study-seed acquisition has started. The original deferred
`hook output missing` investigation remains deferred.
