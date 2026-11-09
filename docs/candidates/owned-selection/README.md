# Consume old selection state before updating

Isolated candidate, **unadopted**. The parent remains `c1de4407…`. The generic
Lean equality proof and generated-code inspection are recorded in
[request-validation-cost](../request-validation-cost/README.md). This study first
measures the proved implementation natively, then connects it to actual hooks.
It changes no weights, candidate domain, budget, model, tie order, authority or
source scope. No worker limit, cache, mutex, queue or allocator policy is added.

## Native comparison

The native component includes the unchanged parent core and one added Lean
module. Closure/source audits are in `component-native.json` and
`component-sources.json`. It runs seven predeclared synthetic problems, each in
AB/BA/AB order. Every one of 21 comparisons has the same complete selected
sequence, cost and benefit (`component.json`).

| Offers | Original | Candidate |
| --- | ---: | ---: |
| 0 | 0–34 µs | 0–1 µs |
| 1 | 1–6 µs | 1–2 µs |
| 32 | 126–151 µs | 122–147 µs |
| 128 | 696–722 µs | 663–671 µs |
| 512 | 7.189–7.333 ms | 6.600–6.767 ms |
| 2,048 | 36.565–37.002 ms | 26.140–27.940 ms |
| 4,096 | 126.722–130.211 ms | 74.443–78.349 ms |

Zero/singleton measurements include timer/startup effects and are not meaningful
speed ratios. Larger cases include 384-bit weights and shared/ring features.
They are not captured LLVM selector inputs or an 80-client workload.

Separate controls deliberately retain all prior values for cases up to 128
offers, keeping 16 and 64 nonempty snapshots per implementation. Their UInt64
fingerprints remain equal after subsequent updates, and both implementations
return exactly the same final sequence/cost/benefit. Fingerprints are auxiliary
mutation detection; the generic Lean theorems establish the stronger semantic
equalities. Retained-control timing is not reported as production performance.

Small-allocation heartbeats decrease only modestly; they count allocation events,
not allocation bytes, array size or RSS. Combined component RSS peaks at
101,392 KiB and cannot be attributed to one arm. Component speed does not prove
whole-hook latency, memory capacity or total-token improvement.

The first native build rejected a test namespace collision, a modulo bound and
an unnecessary proof tactic. The corrected failed snapshot compiled; no native
benchmark was started until the build and source audits passed. See
`build-error.json`.

## Actual-hook connection

The isolated runtime changes `Eggshell.Handoff` only to import the proved kernel
and call it at the three selection entry points. A declaration audit requires
all three actual consumers to use the new implementation. The complete selected
result is proved equal for every problem, including tie and singleton handling.
Actual-hook and capacity results are recorded separately; product adoption still
requires the matched inclusive-token and quality comparisons in AGENTS.md.

The integrated native runtime is `36612afe…`; `runtime-native.json` and
`runtime-sources.json` verify its closure and the declared one-existing-module /
one-added-module change. The six independent actual chats preserve all canonical
body bytes and ACKs. Frozen DB-present originals are 4/4, 7/7 and 5/5 in each
repetition, 32/32 total, with explicit exclusions for three absent items.

| Topic | Chat 0 | Chat 1 |
| --- | ---: | ---: |
| 1 | 5,994 ms | 3,231 ms |
| 2 | 4,278 ms | 3,631 ms |
| 3 | 3,698 ms | 3,545 ms |

Related single-hook-study RSS peaks at 1,917,472 KiB. This interrupted-seed
performance fixture is not an accepted new seed or a first/history answering
model benchmark. No answering model was called.

The single changed-candidate normal capacity study passes all four and all
sixteen semantic/synaptic canonical bodies plus ACKs, in 3,813 and 9,679 ms.
Related RSS peaks at **4,152,272 KiB**, about 4.25 decimal GB, near the unchanged
4,358,524 KiB protective stop below the 5 GB ceiling. This is not a matched
performance comparison with the older parent runs. Capacity improvement is not
established, and no 40/80-client escalation is performed.

At the peak, the publisher uses 1,850,144 KiB, the frontend daemon 631,664 KiB,
the numerical Lean process 164,528 KiB and the model process 1,099,568 KiB.
Other controllers/save/index workers also contribute. `peak-roles.json` retains
sanitized PID/role/RSS attribution; these values are process RSS, not live heap
or proof of which object owns the memory. The remaining problem is not assigned
solely to the selector or the shared metadata cache.

Existing service profiles show 7,238–8,285 units and 16,790 pieces, 9,936 incoming
rows and 7,787 canonical rows. In the 23 prime/concurrent samples, row-domain
construction takes 8–36 ms and unit preparation 22–167 ms; selection including
problem/scoping preparation takes 335–1,532 ms. These nested wall intervals are
not additive CPU costs. Do not rebuild a canonical-row cache on the assumption
that the measured 8–36 ms dominates the hook, or rerun the already-tested
batch-winner/cue-sharing proposals.

The current isolated runtime is retained for the next investigation of actual
request-state/IR and frontend retention. It remains unadopted; total-token,
quality, accepted-seed rounds, 80-user sustained growth/multiple DB/NAS and p99
are unverified. Native component speed is not substituted for those gates.

Ended benchmark executable/source, raw hook results, receipts and logs were
deleted without archives: 3,828 files / 234,322,619 logical bytes (`cleanup.json`).
Current runtime and original DB hashes remain unchanged. The benchmark compiler
interfaces are retained because the frozen runtime source's `.lake` path still
depends on them; deleting them would leave a dangling current dependency.
