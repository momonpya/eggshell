# Ordered owner ranges in actual selectors

Isolated experiment, not adopted. The parent is the fixed-lane hashing
candidate `1153215e…`, not a public-release token benchmark. The numerical
model, prompts, ranking, synapses, Exact, deadlines, pools and resource limits
are unchanged. There are no answering-model calls.

[BucketView](../../../../tools/research/BucketView.lean) lifts complete ordered
optional-bucket equality through the original `RangeReach.prepare` function.
[The product connection](../../../../tools/research/OwnerReachConnection.lean)
relates the actual nested `ownerReach` collector and its member queries. It
preserves missing keys, order, duplicates and all prepared-index lookups,
without claiming equality of raw hash-map layouts.

The connection is inserted after the original definitions and before the
three consumers. A separate check copies the three original consumer bodies
from the parent's recorded source: `plan`, `selectPrepared` and `selectView`
are definitionally equal to their refactored versions. The [axioms](refactor-axioms.txt)
and [connection axioms](axioms.txt) contain only the standard axioms. The
initial proof-copy check omitted `open Lean`; its [rejection](refactor-rejection.txt)
is retained. The product code was not changed to accommodate that error.

The first connection returned functions. Native inspection found the chooser
taking a member argument and passing an unevaluated key callback, allowing
index construction to move into individual lookups. This [candidate](function-rejection.json)
was rejected before any real hook or answering-model call. Its source patch,
native fragment and audits remain recorded; its executable was overwritten by
the rebuilt data-returning candidate, without an archive.

The replacement returns an explicit `Index` value containing a lookup over
the already prepared table. The [native audit](native-binding.json) checks
that each of the three selector entries directly invokes the collector and
preparation mapper once. Those calls are absent from member traversal
helpers. Compiler inlining at the entry is allowed and recorded. Reference
constructor calls survive only in the reference helpers and their own boxed
wrappers. Earlier inspector attempts failed to account for that self-wrapper
and private text symbols; the complete checks were corrected, not skipped.

[Source comparison](sources-data.json) permits exactly one direct product
change, `Eggshell.Handoff`, and the two declared helper additions. Three
`include_str` containers change only by those exact source bytes. All parent
modules and the entry are retained; the native closure is independently
inspected. [Runtime identity](runtime.json) binds these checks to the actual
executable.

This is a query-local range index over query-dependent unit ordinals. It is
not a new project snapshot cache, a publication-delta implementation or proof
of eighty-user scalability. Prepared base ranges should still be shared in
the project image where applicable. No whole-query mutex or worker queue was
added. A future pool remains an option only if a matched full-hook comparison
supports it; the old selector-only pool is not repeated here.

The [plan](plan.json) fixes ABBA order and four/sixteen clients before measured
waves. All arms use the same final snapshot, source bytes, three questions,
canonical bodies, harness, environment and 500,000-character envelope. Warm
and initialization precede the measured waves. The three canonical primes
and additional four-client [preflight](preflight.json) must pass first.
This does not rerun the earlier paid seed and six-stage sequence with the new
runtime. General evidence recall, token savings, answer quality and p99 are
separate unpassed adoption conditions.

The first comparison completed two pilot arms, then the next arm hit the disk
floor with four clients in flight and no outputs. It is an [aborted comparison](aborted-comparison.json),
not a success or a measured-wave completion. The earlier commentary saying
it stopped before measurement was too strong; the empty client directories
showed that it could have started. Forced termination left dead endpoints;
one startup then refused them. [Recovery](endpoint-recovery.json) checks that
their PIDs belonged to the stopped guard and no longer exist before removing
only those endpoints. Source files still match their frozen hashes.

After retiring completed duplicate states, a [fresh complete ABBA](recovery-plan.json)
was declared. The two completed pilots are kept separately and **not pooled**
with it. Each successful arm is collected and retired before the next arm,
keeping disk use bounded. Resource limits, product and native harness are
unchanged.

| Arm | Four clients | Sixteen clients | Sampled combined peak KiB |
| --- | ---: | ---: | ---: |
| Parent A1 | 5.189 s | 13.673 s | 4,032,384 |
| Candidate B1 | 4.948 s | 12.943 s | 3,884,000 |
| Candidate B2 | 5.658 s | 14.208 s | 3,808,096 |
| Parent A2 | 5.944 s | 15.324 s | 3,777,488 |

[The comparison](comparison.json) checks equal snapshot, source, questions,
canonical bodies, harness settings and non-treatment environment. Every
measured wave completes meaning and synaptic search with byte-equal bodies
and ACK; all four guards exit normally and leave no owned processes. There
are 92 successful prompt deliveries including the primes in this fresh
comparison, plus seven in preflight. The aborted sequence's completed pilots,
three additional successful primes and four clients without outputs are
separate attempts, not silently discarded successes.

Mean sixteen-client wall time is 14.4985 versus 13.5755 seconds: a descriptive
6.366% reduction with two repetitions per arm. Variation remains substantial.
This fixes one copying pattern; it does not explain or remove all remaining
delay. The few-second target, p99, a memory improvement, broad 98% evidence
recall, eighty-user operation, token savings and quality are not established.
The candidate remains unadopted; no paid model evaluation was run.

Ended source copies are [deleted](retired-sources.json), as are the previous
winner-width experiment's [duplicate wave outputs](retired-obsolete-waves.json).
Current source DBs, canonical bodies, model assets and required native inputs
are protected. No compressed archive is created.

After collection the [isolated build, source, proof cache and transient trial states](retired-generated.json)
are retired too. The current parent, selected six-stage runtime, controllers,
source head, project read-cache and model assets are retained. Full raw symbol
dumps are replaced by their digests and the checked compact native branch
record. The retired executable is not available for replay; source helpers,
the exact patch and audits remain available to regenerate it.
