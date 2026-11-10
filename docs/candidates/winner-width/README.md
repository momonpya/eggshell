# Carry the winner tree's width through point updates

Isolated candidate, not adopted. The real late product CPU sample in
[routing-leaf-image](../routing-leaf-image/README.md) showed repeated
`lean_nat_pow` below `StableWinnerIndex.Tree.updated`. The existing sparse
reverse-incidence index and cached winner tree are retained. The earlier
batch-winner proposal was reviewed and is not retried: this candidate retains
the same sequential point updates and computes the root width once, halving it
at each descent.

[WinnerWidth](../../../tools/research/WinnerWidth.lean) proves equality of the
complete returned cache for every preference, tree, depth, index and replacement,
and for an arbitrary update list including duplicate positions. The proofs use
only `propext` and `Quot.sound`; no `sorry`, native decision procedure, new axiom
or solver is used. No new cache, lock, queue, weighting or candidate selection is
introduced. This is a pure equality proof, not an IO, memory or latency theorem.

The [actual scalar context](scalar-context.json) is frozen from four final-head
product receipts before their deletion. It has 46 families, 10,637 candidate units
and a 396-bit scale. Benchmark update positions are synthetic, not a replay of
the complete selector.

## Native component measurement

The first timing attempt reused the original expression's precomputed oracle
through common-subexpression elimination. Its implausible nanosecond reference
times are explicitly [invalid](invalid-timing-result.json); they neither reject
nor adopt the candidate. Its semantic checks remain separate from performance.
The [corrected plan](barrier-plan.json) loads both cache and updates from an owned
reference **after** starting the clock. An output barrier alone was insufficient.
Inputs, pattern order and repetitions were unchanged.

[Corrected native results](barrier-result.json), 16,384 leaves and three
AB/BA/AB pairs per pattern:

| Updates | Original | Width carried |
| --- | ---: | ---: |
| Sparse 16 | 0.088–0.093 ms | 0.071–0.074 ms |
| Contiguous 1,024 | 4.84–5.41 ms | 3.81–4.13 ms |
| All 16,384 | 80.21–81.87 ms | 62.25–64.24 ms |
| Duplicate 1,024 | 4.94–4.95 ms | 3.88–3.91 ms |
| Erase 1,024 | 4.65–4.70 ms | 3.59–3.65 ms |

All leaves and stable winners match, including 296 additional small-depth
controls. This is about 20–24% less time in this component, not a measured
whole-hook or total-token improvement. Combined guard RSS is 99,776 KiB and
cannot be assigned as a per-arm memory reduction. The native audit verifies five
objects, both required unchanged common modules, reviewed helper sources and
empty embedded-literal changes. The runtime is `4e664481…`.

## Isolated actual-hook candidate

[WinnerWidthReplacement](../../../tools/research/WinnerWidthReplacement.lean)
keeps the original replacement callback and sequential fold, without building an
intermediate mapped list. The isolated runtime adds one compiler-simplification
equality theorem in `WinnerUpdates`; affected consumers are rebuilt normally.
There is no object/symbol substitution around the compiler or source auditor.
The entry, models, ranking, ties, WorkGraph/Exact, three advisory edges, bodies,
deadlines and ACK contracts remain comparison invariants.

The initial full build put this compiler theorem after its same-module
consumers. Generated-object inspection found no call to `updateManyWidth`, so
that build was not benchmarked. The successful compilation is not reported as a
successful optimization. [Its record](runtime/unapplied-binding.json) retains
the object/runtime hashes, symbols and original patch. The theorem was moved
before the consumers, which were rebuilt normally; the corrected object has
the new call. The source/native audit requires this binding before a hook run.
The connected runtime is `b8f1fe68…`: 325 actual linked objects, all 322 parent
modules present, exactly one changed module and two added helpers. The entry's
source and embedded literals are unchanged. This complete audit is distinct
from the five-object component audit.
The actual binding was also typechecked independently; its standard axiom
dependencies are recorded in [axioms.txt](runtime/axioms.txt).

[The runtime plan](runtime/plan.json) freezes three canonical bodies and the
parent/candidate/candidate/parent order, with four and sixteen clients in each
arm. The memory ceiling is 5,000,000,000 bytes, protective RSS stop 4,358,524 KiB
and disk floor 2,097,152 KiB. No 40/80-client trial or answering-model call is
authorized by this component result. Actual-hook results are recorded separately;
generic 98%, p99, token/quality adoption and the few-second target are not inferred
from the table above.

## Actual-hook result and decision

The three canonical preflight bodies and the additional four-client diagnostic
wave pass. The [fixed ABBA comparison](runtime/comparison.json) then returns:

| Arm | Four-client wave | Sixteen-client wave | Aggregate peak RSS, KiB |
| --- | ---: | ---: | ---: |
| Parent A | 6.817 s | 16.919 s | 3,617,056 |
| Candidate B | 6.666 s | 16.518 s | 4,113,488 |
| Candidate B | 6.697 s | 16.826 s | 3,741,776 |
| Parent A | 6.773 s | 17.088 s | 3,573,552 |

All 99 actual native initial-hook calls, including each arm's three primes,
preserve canonical body bytes and ACK; every measured wave completes semantic
search and synaptic traversal. The fixed three canonical bodies contain all
18 fully stored and 19 including partially stored originals previously audited
on this head. Initialization/priming is outside each measured wave. Each guard
exits zero, leaves no owned process and does not trigger the resource limit;
original project files remain byte-identical.

The descriptive sixteen-client mean reduction is only **1.950%**. The few-second
target remains unmet, RSS improvement is not demonstrated, and two repetitions
per arm do not establish p99 or a stable whole-hook gain. No inclusive-token or
answer-quality benefit is measured. The candidate is **unadopted**; this small
point-update optimization is not the main solution to the remaining latency.
The selected product and published performance claims remain unchanged.

The parent arms printed
[session-maintenance/queued-work warnings](runtime/maintenance-observations.json)
during shutdown. These are retained separately from successful delivery checks.
All owned processes drained, but maintenance completion and its causal timing
impact are not established. A clean guard does not turn these warnings into
completed durable work. These clients are disposable performance fixtures, not
the paid seed/model sequence.

After collection, all 99 ended clients' session/ledger/receipt trees were removed:
7,542 entries and 240,542,589 logical bytes, without an archive. The per-arm
`*-retired.json` receipts retain ownership, counts and protected hashes. Actual
stdout, comparison records and canonical bodies remain. The ended unadopted
[runtime/source/installation](runtime/retired-runtime.json) was then removed:
2,683 entries and 293,007,445 logical bytes, with 1,560 active compiler references
checked outside that tree. The selected product, controllers, comparator and
all original project-file hashes remain unchanged. The retired executable is
not an available input for another experiment.

Ended controller compiler interfaces were
[deleted](retired-controller-interfaces.json), without an archive, after checking
that 3,125 active compiler references resolve outside the retired directories.
The selected product, native controllers, active compiler inputs, original DBs
and models were preserved. Rebuilding those retired controllers requires
regenerating interfaces; their native executables remain usable. After sealing
the full runtime, the ended width-component build/source was also
[deleted](runtime/retired-component.json): 1,924 files and 111,080,516 logical
bytes, with all 3,125 active compiler references checked outside the retired
tree and protected hashes unchanged. Its result/audits remain; its executable
path is retired.
