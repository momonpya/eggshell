# Publication replay and ordinary hook attribution

Isolated continuation of [front-traffic](../front-traffic/README.md), parent
`ec1ce788`. Product sources, public README results and releases are unchanged.
No answering model was called; paid matched comparisons remain **0/18**.

## Reproduced publication failure

The [eight-reader diagnostic](plan.json) initially never reached its reader
wave. A seed checkpoint remained queued for the unchanged 180-second drain
window. The service reported 189 completed operations, but the original graph had
already stored that observation. The [read-only audit](original-audit-before.json)
found its valid stored origin, both native start/finish events and exact input/
output agreement. Original and private-journal heads were unchanged by the audit.

One ordinary retry returned
`authoritative writes cannot publish an empty graph delta` after 622 ms,
leaving the checkpoint queued. [Actual response](retry-before.json).
The source graph already contained the Outcome; the new durable request/input
binding still needed a publication. Its callback reported a metadata change
without naming the existing Outcomes affected by that binding. The source
publisher correctly rejected a neutral change containing authoritative writes.

The candidate binds publication metadata to the compiled Promotions' actual
Outcome ids. Each id must be a live source member before it is reported.
It neither invents an affected owner nor changes the graph-delta guard.
Pure Lean laws characterize the exact affected set and show that a changed
binding with a known owner has a non-neutral delta. The standard ContractAudit
and actual executable-declaration dependency checks pass. The two new laws use
only `propext`, `Classical.choice` and `Quot.sound`.

On the **same retained DB and checkpoint**, the ordinary worker completed in
637 ms, returned a durable source ACK with `timed=1 / awaiting=0 / unavailable=0`,
and removed the queue entry. No replacement seed or new tool observation was
created. [Actual response](retry-after.json). These two timings demonstrate
completion behavior, not a speed improvement or a token comparison.

[Native recovery checks](recovery-checks.json) additionally confirm:

- Replaying the same request and input boundary succeeds without changing the
  original source head.
- Replaying its receipt with another actual read boundary is rejected, also
  without changing that source head.
- An authoritative write with no graph delta is still rejected and rolled back.
- Publication metadata naming an unpublished owner is rejected and rolled back.

The [core patch](candidate.patch) changes NativePublication and adds receipt
timings in four existing modules. GraphStore, PageMap, SearchProvider, MiniLM and
BlockScore match the parent exactly; [source identities](identity.json) record
this. An early interpreted audit exceeded its internal 1 GiB limit; it was
replaced by the native audit, without raising the aggregate memory limits.

## Measured ordinary-entry stages

With the repair, the fresh two-observation fixture drained and all eight fresh
chats received all four frozen fields in their actual initial hook bodies.
All configured semantic searches completed, and all original heads remained
unchanged. [Inputs](frozen-inputs.json), [actual receiver outputs](deliveries.json),
[stage records](stage-report.json), [service counters](input-report.json).

| Observed stage | Eight readers |
| --- | ---: |
| Whole initial hook | 5,082–7,826 ms |
| Turn reference/owner probe, returning missing owners | 9–45 ms |
| Final operation reference read | 2–6 ms |
| Final operation owner-reference read | 37–46 ms |
| Service queue | 0–3,006 ms |
| Service processing, including worker transport/reservation | 1,248–1,736 ms |

The old test's readiness condition was incomplete: it reported sixteen source
references as ready while the complete owner reference was still missing.
All eight turn probes reported `missing-owners`. Roughly 3.5 seconds elapsed
before operation admission while the shared preparation completed. This is a
**cold owner-input** result, not evidence of fully warmed throughput. Product
`Warm.required` already checks owner readiness; the test must use that complete
condition before claiming a warmed DB. Do not attribute these seconds to the
final 37–46 ms owner reads or to a terminal state-lock error.

The corrected [test protocol](ready-plan.json) now requires every exact source
reference, numerical input for populated sources, and the complete exact owner
reference in addition to drained original queues. With ordinary background
preparation, these references became ready after 5,839 ms. All eight initial
turns then captured complete inputs, requested no hook-time warm, completed
semantic search and delivered all four frozen fields in 2,230–5,366 ms. Service
queue time was 1–3,832 ms and processing including worker transport/reservation
was 1,276–2,283 ms. Original heads stayed unchanged; actual process exit left no
owned process. The [final native guard](ready-resources.json) recorded peak
aggregate RSS 2,224,016 KiB, below the unchanged stop limit.
[Ready inputs](ready-frozen-inputs.json), [preparation samples](ready-drain.json),
[stages](ready-stage-report.json), [service counters](ready-input-report.json).

This is a readiness-test correction, not a production speedup or matched timing
comparison with the earlier cold fixture. The first attempted run still used
the isolated tree's old checker because setup had not copied the changed
workspace checker. It is explicitly [rejected](readiness-source-mismatch.json).
Build setup now copies and verifies only the two owned research modules before
building. The subsequent build compiled the corrected checker and its actual
receipts all report complete turn inputs.

## Rejected fixed-cost hypothesis

The [predeclared native key diagnostic](key-plan.json) measured sixteen stable
configuration keys at 1,721–1,775 microseconds each. That is too small to explain
the hundreds of milliseconds outside inner numeric scoring; no key-generation
optimization was made. The complete lightweight native process took 0.29 seconds
([timer](startup-time.txt)). Short-lived adapters are a remaining investigation
target. The attempted startup sample captured no usable call graph, so it does
not identify which initialization work consumes that time.

## Remaining scope

These are small native fixtures, not an 80-user, eight-hour capacity result,
large-DB p99, real evidence 98% result, real MCP-server trial, remote/NAS test,
answer-quality result or token-improvement result. The earlier 65/80 ordinary
traffic failure remains a failure; it has not been rerun as a claimed success.

Next reduce repeated short-lived provider/encoder setup without changing
responses, ranking, private boundaries
or certification's complete original domain. Reuse the retained active fixture
for fixed-source diagnostics. Preserve the original 30-second deadline, 3.5 GiB
aggregate stop, 4 GiB ceiling and 2 GiB disk floor. Only after the native protocol
passes should the full fixed-runtime 1/80-writer and 80-fresh-reader series
resume, followed by the broader project/scale/sustained and matched token gates.
The current service has sixteen independently owned original append regions,
not a separate DB for each person. Source publication admits sixteen concurrent
groups, while the normal operation service has three search and two save
workers and preparation has three workers. These separate bounds require joint
capacity measurement; a source-only burst does not establish that the normal
save path uses sixteen publications concurrently.

Ended diagnostic fixtures and raw logs are [deleted](cleanup.json) after the
compact records are sealed. The small retained diagnostic2 fixture remains an
active fixed-source control for the next provider investigation; no archive is
created.
