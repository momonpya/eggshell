# Metadata-only identity projections

Isolated candidate, not adopted. Original append owners, source certification,
vector ranking, evidence selection and private/public scope are unchanged.
Answering-model calls0; paid matched comparisons0/18.

The private importer already stores one-hop references rather than duplicated
tool outputs. It nevertheless decoded, hashed, projected and serialized each
original body to construct those references for every destination source.
This candidate indexes the native event's small description in the same
private append transaction as its body and exact sequence receipt.

`start` and `answer` have source-specific knowledge and retain the complete
projection path. `finish` is an identity projection for every source: its
original clock, occurrence, byte count and two body digests can construct the
reference and append receipt without reading its output. The importer still
checks the captured original prefix and source eligibility. This is based on
the event's projection semantics; no tool name or command grammar selects it.

Descriptions do not contain tool arguments, output, queries or answer text.
They stay in the same private journal as before. On actual materialization the
original canonical body must match its description and both scoped reference
digests. A `DescribedEntry` carries the equality witness through identity
projection, avoiding another full-body hash. The receiving journal also
checks its description before returning the event. Duplicate identities keep
the original exact-body conflict check and first-observation rules.

Six Lean laws cover content/name/turn description fields, the identity
projection, exact described projection and the original frontier step.
ContractAudit connects append/import/materialization to the new operations,
forbids original-body loaders from the new-reference writer, and retains the
source boundary's sequence requirement through `stepDescription`. This is
not a proof of arbitrary on-disk metadata or all distributed IO.

`decodedBytes` remains the declared event extent charged to the existing
slice budget. It must not be called physical bytes decoded by the candidate.
`bodyBytes` measures non-identity inputs decoded while planning new imports;
duplicate conflict guards can separately materialize their originals.
`metadataBytes` records described-event metadata decoded while planning.

The controls reuse the same frozen original file,5 KB and50 KB MCP events
and sixteen frozen destination sources. They reconstruct and compare every
projected event, full append frontier, clock, order and canonical body, then
verify unchanged import is idempotent and aliases never become original feeds.
The timed observation function is identical across arms; candidate-only laws
and corruption checks run separately. No answering model creates the fixture.

Three alternating matched comparisons measure the full native process,
including private appends, imports and both complete materialization checks:

| Pair | Parent, ms | Candidate, ms |
| --- | ---: | ---: |
|0 |3102 |2681 |
|1 |2896 |2631 |
|2 |2948 |2633 |

For the50 KB output, all sixteen imports take546/526/586 ms in the parent
and207/211/212 ms in the candidate. The six private event appends for that
case take40/37/38 and59/38/38 ms respectively; the slower first candidate
append is retained. These are not end-to-end Post-hook or source-save times.
The candidate plans371,008 original-body bytes and160,960 metadata bytes
for that case, versus1,991,472 declared original-event bytes in the old
planner. The candidate retains that same declared charge in `decodedBytes`;
it does not claim the charge itself shrank or report these counts as all IO.

Native checks pass36 literal old-algorithm receipt steps and324 projection
domains. Damaged receipt metadata is rejected before the prepared prefix can
publish. Content-digest damage is rejected before materialization returns an
event; it is not incorrectly called pre-ingress body verification. Changed
alias clocks are rejected, and old pinned original/alias views remain exact.
The integration checks real omitted-then-consumed usage, exact source
projection, scope/indirection/digest rejection, and fresh-process recovery.
Full and prefix replay tests cover dependency changes, retraction, restoration,
cache recreation and continuation reuse. Initial compiler/proof/checker errors
and an integration entry-point omission remain in evidence. The inspection
entry correction changes the harness only; the two product files are checked
byte-identical before and after it. A failed process-sampling attach is not
CPU-profile evidence. Earlier component observations are recorded separately.

The same retained sixteen-owner project, MiniLM, question and settings also
run three alternating pairs of real hooks. All twelve actual bodies are
byte-identical and contain both frozen original fields; original heads stay
unchanged.

| Pair | Parent first / next hook, ms | Candidate first / next hook, ms |
| --- | ---: | ---: |
|0 |5982 /2932 |5678 /2931 |
|1 |5662 /2923 |5737 /2976 |
|2 |5445 /2868 |5495 /2908 |

Hook timings are mixed. This is not consistent query acceleration, p99,
OS-cold performance, or Luna first/history-round token evidence.

The ordinary mixed workload retains16 original owners,80 clients,5000-byte
outputs, three preparation workers and all existing resource/deadline bounds.
All80 writers succeed. Public readiness takes80,222 ms:16/16 sources and
owner references are ready and save queues empty, but preparation still has
17 pending/3 active jobs. The entire background system has not drained.

All80 fresh readers are measured:60 deliver both original fields and finish
within30 seconds,20 fail at deadlines. Semantic completion is9 and lexical
completion51. Failure-inclusive hook times are8,202–29,765 ms, median25,237 ms.
The67 reader-scoped final service observations show queue median19,711/max26,328
ms and work median755/max6,075 ms. These observations are not full p99.
The eighty-client capacity gate fails. The previous62/80 run used a separately
generated DB; do not attribute the difference of two readers to this change.
There is no demonstrated capacity improvement from the faster import alone.

A separate process verifies all82 saved original input/output observations,
all80 posted cases published, no pending save sessions, and unchanged source
heads. All25 guards are terminal with no owned survivors or resource stops.
Peak related RSS is3,073,760 KiB; the3,670,016 KiB stop remains unchanged.

This removes one repeated preparation path. Foreign feed relationships and
per-source private classification still exist, so it is not a project-wide
single replay or an eighty-person capacity claim. The full98%/30-second goal,
growing multiple projects, eight-hour use, NAS operation, inclusive-token
improvement and answer quality require their own evidence.

Next measure and remove the remaining repeated source/graph preparation in
the actual query worker. Private foreign-feed and classification duplication
also remain. Avoid repeating an unchanged burst or treating this import
optimization as a solution to the query queue.

[Patch](candidate.patch), [laws](laws.txt), [evidence](evidence.json),
[actual fixed body](actual-body.txt), [mixed summary](mixed-summary.json).
Ended test DBs, caches and raw logs are removed after recording, without
archives. Active controls, compared runtimes, sources and build inputs remain.
[Cleanup](cleanup.json).
