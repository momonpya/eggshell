# Scheduling over one prepared snapshot

Isolated diagnosis, not adopted. No product algorithm or answering model is
changed. The selected product is `dd53c89b…`, which completed the six memory
stages in [the fixed-runtime study](../stable-source-rows/sequence/pilot-results.md).

Those six stages used different growing snapshots. Their retained output
packets cannot serve as byte references for a query against the final head.
This diagnosis therefore freezes DB-present originals before delivery, creates
three normal product packets from **one final source/private/ACK snapshot**,
and checks each in an independent chat before measuring four concurrent clients.
It does not rerun the rejected selector-only pool or call an answering model.

The native helper must pass complete dependency inspection and unchanged
product-core source checks before running. Its original build omitted two
research imports that the ordinary controller did not use; the missing
`MemoryCapacity` and `StudyWarm` sources were taken from the frozen product,
without taking product code from the working checkout. The failed build receipt
is retained in `build-input-repair.json`. No DB operation had run at that point.

The diagnostic unsets `LEAN_NUM_THREADS`, with numerical-library thread limits
remaining one. Query-stage times are recorded under their actual receipt IDs.
Existing service profiles are collected within the concurrent phase's clock
window, but are **not** attributed to individual concurrent requests. A bounded
three-second publisher stack sample complements those records. Sampling and
profile writes may perturb timing; they do not establish a speed improvement,
whole-hook CPU percentages, p99, or sixteen-client capacity.

The aggregate memory ceiling remains 5,000,000,000 bytes, with the existing
4,358,524 KiB RSS stop and 2 GiB disk floor. No eighty-client test is allowed
on this Mac. Source-only restoration and explicit warm are outside hook timing.
The same expected original bytes, semantic search, three advisory edges and
publication ACK must survive the measured phase.

## Normal measurements

All of these use the same final source/private/ACK snapshot, product SHA,
questions and normal product controller. The new final-snapshot availability
audit found 18 fully stored requirements and one partly stored requirement;
all 19 available instances occur in the independently confirmed reference
bodies. This is a different snapshot from the six growing memory stages.
Every measured body must be byte-identical to its topic's reference. No
answering model is called.

| Trial | Clients | Whole-wave completion | Semantic / synapse / body / ACK |
| --- | ---: | ---: | --- |
| Sampled diagnosis | 4 | 6.622 s | 4/4 for each |
| Observers disabled | 4 | 5.942 s | 4/4 for each |
| Observers disabled | 16 | 15.639 s | 16/16 for each |

The last two phases are predeclared in `capacity-16-plan.json`. Their supervisor
returned zero with `guardTriggered=false`, no reason, no owned processes, and
sampled peak RSS 3,887,728 KiB. The sampled diagnosis also exited normally,
with peak 2,532,048 KiB, including its ready-before-load observer. Measurements
include the actual hook body publication and ACK. Source restoration and warm
are outside the wave. The 16 clients individually took 13.552–15.636 s. This
passes the 30 s bound in these observations but **does not pass a few-second
target**, establish p99, or validate 80 sustained users. No 40/80 test ran.

Authoritative normal receipts are `owned-sampled-result.json` and
`capacity-16-result.json`; neither establishes a performance improvement.
The native controller's four-client diagnostic deliberately reports
`allPhasesPassed=false` because it is not a capacity gate. Its individual phase
passed. The non-diagnostic 4/16 report passed both declared phases.

## What the profile actually shows

The four sampled source-plan profiles have validation 2–3 ms, view access 0 ms,
unit construction 86–89 ms, domain construction 7–8 ms and selection
1,356–1,405 ms. They are service observations within the measured clock window,
not an invented mapping to individual requests. Moving the additional roughly
0.1 s of construction into the previously rejected selector-only pool is not
evidence of a material improvement.

The bounded early-window CPU sample contains routing traversal, PageMap load,
wire decode/re-encode and digest stacks. The existing PageMap cache already
stores **decoded, verified, typed pages**; adding another equivalent cache or
removing checks is not justified. Its request-local front has a 2 MiB / 512-slot
bound and resets the entire front when insertion no longer fits. Public reader
images seed new private fronts, but request misses do not enrich those fixed
images. In both the 4- and 16-client waves, the same topic independently repeats
1,627–1,905 misses and about 180,000 hits per request. The sample and counters
locate repeated work; they do not prove its full causal share of latency.

`PreparedReaders.CheckedFrame.fork` creates local mutable counters/trace/fronts.
`PagePool.reader` lookup has no shared cache owner, mutex or CAS. The existing
shared source-view callback also runs outside its catalogue mutex. Frame
capture/borrow and validation were cheap in this diagnosis. Do not relabel this
as a proven global read lock or an absent cache.

## Next isolation boundary

Pool adoption remains conditional on a clean ownership boundary and measured
benefit. The next candidate must reuse the existing verified-page machinery
and publication-prepared routing relation: one bounded, immutable project
image, small request-local overlays, and compilation/validation of changed
pages outside retrieval. Scope, file incarnation, complete page descriptor,
read observations, corruption rejection, and exact certification stay intact.
Pinned old images and private overlays must be included in the byte bound;
retaining an unbounded cache generation per request is not acceptable.

Only then is a CPU pool useful as an execution boundary starting with a small
request borrowing that image, with I/O waits outside. It must not merely move
an already expanded large IR into another queue. First compare native 4/16
waves on this same snapshot and require exact bodies, semantic completion,
three-edge traversal and ACK. Do not repeat the selector-only pool or the
rejected plain base-cue bucket index. Product algorithm, paid-model runtime,
README performance claims and adoption remain unchanged.

## Failed observations and retired helper

The first capture helper started its publisher before replay and cold warm.
The publisher's existing five-minute idle retirement elapsed during those
off-hook operations. Four requests still delivered correct bodies, but a
replacement publisher invalidated the original PID's sampler and shutdown
ownership. This was a harness lifecycle error, not a normal measurement. The
Lean helper now closes the replay publisher before starting the warm publisher;
the source is typechecked, but that fix has not been rerun natively.

The second diagnosis used the product's own controller and shut its services
down, but its external observer was not ready. The resource supervisor cleaned
that leftover observer and returned nonzero. Its JSON child exit code alone
does not make the trial successful. `cleanGuard` checks the supervisor-trigger
and reason fields as well. The third diagnosis used an explicit observer-ready
handshake and its actual live direct-child publisher, then exited normally.

The capture helper's ended native build/source tree is retired rather than
archived after collection; see `retired-helper.json`. Its historical native
closure and common-source audit records remain. The selected product, two
current controllers, accepted common seed, final standalone history and active
prepared performance fixture remain protected. Reopening a retired helper build
is not a supported continuation command.
