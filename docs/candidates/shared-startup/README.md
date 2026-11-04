# Shared frontend startup without a waiter lock convoy

Isolated continuation of `9a512e8c`, not adopted. Answering-model calls are zero;
matched inclusive-token/quality comparisons remain **0/18**. The whole 80-client
gate still fails, although the identified startup failure is removed.

The [product patch](candidate.patch) changes Daemon and removes the unused
attempt-count constant from DaemonWire. Cold callers observe the shared endpoint
outside the existing startup guard. A caller that obtains that guard alone may
recheck, replace a stale endpoint and spawn the frontend. Waiters use nonblocking
acquisition and keep observing readiness against their original absolute
deadline, rather than waiting in a lock convoy and failing after 200 ms. Hook
and ACK/RPC callers pass their supplied deadline into startup; the RPC default
is calculated before startup instead of giving transport a new budget afterward.

The existing OS ownership guard, generation check, live-invalid-endpoint
rejection and child-reaping discipline remain. A cancelled or expired caller
cannot enter another startup step. No new mutex, CAS, worker or deadline is
added. This is not a whole-program lock-free or distributed ownership proof.
Parallel source publication, shared project preparation, search/ranking,
MiniLM values, recommendation authority and complete certification are unchanged.

## Native startup checks

The test holds the actual OS startup guard for 350 ms, exceeding the former
200 ms cutoff. Requests then use the real authenticated TCP frontend.

| Native check | Result | Observed client time |
| --- | --- | --- |
| Cold shared frontend, lightweight callers | 80/80, one frontend | 776–946 ms |
| Already-running frontend | 80/80, same frontend | 305–419 ms |
| Cold frontend, independent processes | 8/8, one frontend | 270–302 ms |

The external processes have a separate deliberate shutdown/restart wave; the
same PID is required within each wave, not across the intentional restart.
An expired waiter returns after 71 ms while the guard is still held. A cancelled
waiter also returns without publishing an endpoint. A malformed but live
compatible endpoint is rejected without replacing its owner. An already-expired
request cannot use an otherwise valid live endpoint. The component exits zero,
all services stop, and the guard records no survivors or trigger. Sampled peak
aggregate RSS is 608,192 KiB. These are single-run component checks, not p99.

Two Lean laws cover the actual deadline/cancellation predicate. A declaration
audit reaches ordinary hook/RPC startup, the observation loop and spawn path.
The unchanged standard ContractAudit passes. These do not prove OS lock
semantics, all IO races, heap bounds or sustained throughput.
[Laws](laws.txt), [contract](contract-audit.txt).

## Actual retained-snapshot eighty-reader burst

The native hook helper, source heads, sixteen original owners, 82 audited exact
input/output records, question, MiniLM configuration and 120,000-character bound
are the same as the parent's cold readback. Both explicitly warm once before the
burst; the candidate warm takes 2,083 ms. No answering model is called. This is
one diagnostic pair, not the repeated paid adoption comparison.

| Result | Parent | Candidate |
| --- | ---: | ---: |
| Operation admission reached | 4/80 | 80/80 |
| Both required original fields actually delivered | 4/80 | 35/80 |
| Startup-guard timeout | 76 | 0 |
| Later owned-task deadline failure | 0 | 45 |

All 35 successful bodies contain both fields: six configured meaning results
and 29 lexical fallback results. Thus this burst also checks the preceding
literal-first fallback change under load. The other 45 fail; valid JSON alone
is not evidence delivery. All eighty turn-input captures are complete, and the
sixteen original heads remain frozen. Hook measurements span 12,106–29,803 ms,
including failures. The whole test exits nonzero due to those 45 failures;
the guard does not trigger and records no remaining owned processes. Peak
sampled aggregate RSS is 2,758,384 KiB, below the unchanged 3,670,016 KiB stop.

The 38 requests with final operation observations have queue median/max
20,185/26,191 ms and work median/max 1,220/9,280 ms. These are not all-request
p99 statistics. All eighty captured boundary/reference/owner/attach substep
sums are 354–1,277 ms. The twelve completed numerical observations take
215–639 ms, with 1,365 projection-row misses in total. Numerical timing alone
does not explain the 6–9-second complete meaning phases. It is premature to
blame the original store, increase worker counts, or add another cache layer.

Next profile and remove repeated prepared WorkGraph/query work and test queue
recovery with the same complete captured inputs. Keep cold startup and running
traffic as separate checks, then return to the full 5–50 KB writer/readback
protocol. The 80-user eight-hour objective, large growing DBs, multi-host/NAS,
98% real evidence, answer quality and total-token improvement remain unverified.

[Evidence](evidence.json) retains actual stdout by SHA, all measurements, errors,
admission/phase observations, original audit, unchanged source identities and
every guarded build failure. [Additional existing timings](stage-details.json)
retain numerical, partition, freshness and selection diagnostics without copying
endpoint secrets or authorization tokens. Initial checker compilation failures
are not passing trials. Ended diagnostic DB/cache roots and raw logs are deleted
after sealing; no archive is created. The frozen sixteen-owner source project
and needed current/comparison build inputs remain. [Cleanup](cleanup.json).
