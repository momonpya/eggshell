# Fixed-lane BLAKE3 compression

Isolated candidate; not adopted. Models, prompts, WorkGraph/Exact, advisory
synapses, candidate selection, source bodies and ACK rules are unchanged.
There is no new pool, lock, queue or cache in this candidate. Its purpose is
to measure a recurring validation calculation before changing scheduling.

## Evidence and proof boundary

The [early](early-stack.json) and [late](late-stack.json) native stack records
include BLAKE3/PageMap validation. [StackWeights](../../../tools/research/StackWeights.lean)
checks its exclusive weights against all 76 and 80 published native-summary
entries, respectively. Waiting threads are included. These weights are neither
CPU percentages nor durations and do not establish the fraction of hook time
that this candidate can remove.

[RegisterRounds](../../../tools/research/RegisterRounds.lean) keeps sixteen
`UInt32` lanes in a record, performs each round using eight direct four-lane
mixes, and retains seven calls to that round. Its mathematical indexed
get/set specification is noncomputable. A proved compiler equality selects the
direct implementation before its consumers are compiled.

The proof connects the complete seven-round array result, including the
non-sixteen-lane fallback, to the existing total array definition. It composes
the already checked `RegisterMix` equality; it does not replace it with a new
axiom. The [axiom output](runtime/axioms.txt) lists only `propext`,
`Classical.choice` and `Quot.sound`. This is pure functional equality, not a
theorem about native code, IO, latency or memory.

## Rejected implementation

The first record implementation expanded its generic setters into an
882,732-byte round symbol span. Its [valid native measurement](step/component.json)
was slower: about 28.2–28.4 ms versus 15.3–15.8 ms for 128 hashes of 4 KiB,
and 114.5–115.1 ms versus 60.9–62.0 ms for eight hashes of 256 KiB. It is
rejected, not hidden as an invalid experiment. [The source change](packed-change.patch)
records the correction to direct lane arithmetic. The corrected native round
symbol span is 17,180 bytes; symbol span is not an instruction count.

## Native component result

The [source/native audit](native-packed.json) checks five actual objects and
the [source records](sources-packed.json). The candidate digest is generated
from the exact source witness of the product's linked BLAKE3 object, changing
only its namespace, helper import and proved compiler binding. It is not an
independent handwritten implementation of the surrounding hash algorithm.
The [binding audit](runtime-packed.json) verifies those bytes and confirms the
actual compressor calls the new seven-round function. The generic indexed
round and setter have no executable native symbols.

[Native checks](component-packed.json) cover 18 input lengths from zero to
256 KiB, known empty/abc vectors, four segmentation boundaries, framed-field
hashes and 148 safe lane controls. Every output byte matches. Timed inputs are
read from an owned reference after starting the clock; ordering is AB/BA/AB.

| Work per arm | Parent | Direct fixed lanes |
| --- | ---: | ---: |
| 128 hashes × 4 KiB | 15.545–15.829 ms | 5.150–5.166 ms |
| 8 hashes × 256 KiB | 63.190–63.914 ms | 20.731–21.037 ms |

This is approximately three times the throughput of this component. Its
allocation-heartbeat count remains substantially higher, so it is not reported
as an allocation or memory improvement. Heartbeats are not allocated bytes.
The combined guard peak is 103,408 KiB, not a per-arm memory comparison.
The component executable is `a27b67c1…`; no answering model was called.

## Actual-hook comparison

[The runtime plan](runtime/plan.json) changes only `Eggshell.Blake3` and adds
the proved helper. It keeps the namespace and original types in the product.
The full [native audit](runtime/native.json) checks 324 linked inputs; the
[source audit](runtime/sources.json) retains all 322 parent modules, changes
exactly one module and adds exactly one helper. The entry and embedded literals
are unchanged. Actual-object inspection confirms the compressor's new call.
The runtime is `1153215e…`. This full audit is distinct from the component's
five-object audit.

Before measurement, all three canonical topic bodies must match. Then the
predeclared order is parent/candidate/candidate/parent, with four and sixteen
clients in each arm, on the same final snapshot. Guards retain the 5 GB user
ceiling, 4,358,524 KiB protective stop and 2,097,152 KiB disk floor. Actual-hook
results are separate from component timings. Generic 98%, few-second/p99
latency, 80-person sustained use and token/quality adoption are not established
by the component result.

The three canonical preflight bodies match, and the additional four-client
diagnostic wave passes in 5.257 s. The [fixed ABBA comparison](runtime/comparison.json)
then returns:

| Arm | Four-client wave | Sixteen-client wave | Aggregate peak RSS, KiB |
| --- | ---: | ---: | ---: |
| Parent A | 6.061 s | 15.677 s | 3,493,888 |
| Candidate B | 5.216 s | 14.026 s | 3,838,944 |
| Candidate B | 5.198 s | 13.950 s | 3,865,584 |
| Parent A | 6.103 s | 15.824 s | 3,828,304 |

All four arms report sixteen peak search actors, maximum **admission** queue
waits of 2–10 ms, and one prepared-reader image build with 22 hits. See the
[candidate's saved operation statistics](runtime/b-second-metadata.json).
This is not a measurement of every CPU, IO or reply-budget wait, nor proof
that all locks are unnecessary. The existing dispatch is already request-owned;
simply pooling the same work is not established as a way to remove seconds.
A broader pool candidate must begin from borrowed prepared project data and
measure the remaining execution, rather than repeat the rejected selector-only
pool experiment.

The descriptive mean sixteen-client reduction is about 11.2%, with only two
arms per runtime. It does not establish statistical significance or the
few-second target. Memory reduction is not confirmed. All 99 actual native
initial-hook calls, including primes, return the canonical bodies and ACK;
all measured waves complete semantic search and synapses. Original DB bytes
remain unchanged, all guards exit normally, and no answering model is called.
The comparison also checks identical saved questions, snapshot, canonical
bodies, envelope, client counts and non-treatment environment across arms.

The final-head canonical bodies retain 18/18 fully stored necessary originals,
19/19 including the partial original. This is the fixed final snapshot, not a
new six-stage answering-model run or a general 98% guarantee. The component's
threefold throughput gain translates into a much smaller whole-hook gain;
further round/selector micro-optimizations are not assumed to deliver the
remaining target. The candidate remains isolated and unadopted: inclusive
token and quality comparisons have not been performed for this runtime.

## Ended-artifact cleanup

The [retirement record](retired-unused.json) removes 1,543 unreferenced generated
files, 413,679,504 logical bytes, without an archive. Targets are recomputed from
actual retained link responses and resolved source/library inputs. Source and
transitive stamps remain; no DB, source, model, executable, symlink or active
library input is removed. Protected executable, head and canonical-body hashes
match before and after. Rebuilding a retired helper requires regenerating its
compiler inputs; old link responses are not evidence that those inputs remain.
The earlier comparator already had missing native inputs; this cleanup does
not claim to restore its source rebuildability.

After full integration, [the standalone component](runtime/retired-component.json)
is also removed: 1,933 files and 123,210,758 logical bytes, with all 3,120
resolved active compiler inputs checked. Its actual results and proof source
remain in the repository; no archive is created. Acknowledged native session,
ledger and receipt duplicates are retired separately per arm. Comparison
scalars, canonical bodies and cache/shutdown metadata are retained while
duplicate native hook payloads are removed after verification.
The [final duplicate-output retirement](runtime/retired-outputs.json) removes
298 files and 52,761,141 logical bytes. Across the five acknowledged arms,
99 sessions and their ledgers/receipts account for another 7,542 entries and
240,543,420 bytes. None is archived. The integrated runtime and its compiler
inputs remain active; removed native payload copies cannot be replayed.
