# Warm discovery stages and owner projection

The 2026-10-20 user instruction sets the whole-hook limit to **30 seconds for
both initial and subsequent prompts**. Lower latency remains desirable in both
strata. The former five-second and initial-only scheduling observations in
[discovery-native.md](discovery-native.md) retain their original classifications.
New measurements must use a separate cohort, rather than relabel those runs.

## Fixed-input diagnosis

`tools/profile_discovery_stages.py` measures preparation and Work evaluation
on the qualified `ready-delivery-qualified-20261020/construction-7` runtime.
The saved 10,000-window publication, complete source-vector bytes, numerical
provider, question, receipt and workspace are held fixed. Initial history is
empty; subsequent history contains the actual 26 ACKed delivery keys. There
are three complete calls: semantic initial, semantic history and lexical
history. The helper does not invoke a native hook or a generation model.

Every instrumented result must equal the **entire reference Handoff**, including
an absent Handoff. The helper uses a generous diagnostic deadline, so its
timings are not native-hook deadline passes. Instrumentation overhead is not
subtracted. Nested timings below must not be added together.

Artifact root: `/Users/ovm/.codex/experiments/eggshell/discovery-stages-20261020/`.
Inspection 1 retains three successful reference calls and the failed first
instrumented build. Inspection 2 reuses those verified reference bytes and
passes all three complete-Handoff comparisons. Its guard takes 139.824 seconds,
with aggregate descendant RSS peak 3,074,608 KiB under the 3,500,000 KiB limit.
Source/cache bytes, model assets, qualified runtime and ordinary runtime remain
unchanged.

| Instrumented stage (ms) | Semantic initial | Semantic history |
| --- | ---: | ---: |
| Complete helper call, internal clock | 17,146 | 17,018 |
| Source documents | 1,602.817 | 1,409.466 |
| Complete checked nominations | 1,680.713 | 1,164.860 |
| Owner projection | 1,554.649 | 1,571.581 |
| Work evaluation, two rounds | 9,948.572 | 10,535.595 |
| Work loading, 19,938 calls | 5,483.633 | 5,599.230 |
| Admission, 9,969 calls | 2,988.922 | 2,997.478 |
| Source surfaces, two calls | 1,855.652 | 2,023.304 |
| Child membership, two calls | 1,811.780 | 2,066.804 |

Two evaluation rounds do not imply two physical DB reads: each semantic
controller reads 9,969 Works and 9,969 Outcomes. Lexical history runs two
controllers, taking 20,274 ms internally. Their Work evaluations take
9,999.188 and 7,665.064 ms. In the second controller, cached Work/Outcome reads
take only 6.457/7.235 ms, while admission and other work repeat. The existing
NodeReader cache already helps; replacing it with another cache is not the
first remedy. Surface membership and demand deduplication already use hash
indexes. No quadratic cost is inferred merely from their names.

The old continuation policy cancels semantic work after 4.5 seconds and then
starts this lexical work. Its approximately 25-second total is consistent with
the observed cancellation plus repeated evaluation. A uniform ready-search
policy can avoid that redo, while independent data-structure work reduces the
time of either policy.

## Exact owner projection candidate

The old projection appends to immutable lists and scans accumulated window
keys while walking the full ranking. `tools/OwnerProjection.lean` replaces
that accumulation with arrays and hash membership, preserving list order,
duplicates and the precise treatment of empty windows. Sparse owner IDs do
not allocate arrays up to the largest ID; full key equality handles collisions.

Universal theorems equate the reference and builder results, including all
eight output fields. Monadic theorems preserve left-to-right resolver effects
and the first failure. The concrete IO compiler equality uses a local,
kernel-proved lawful IO instance for the pinned Lean toolchain; it introduces
no axiom, `sorry` or `native_decide`. ContractAudit retains the existing axiom
whitelist and checks both single-DB and federated callers.

`tools/owner_projection_candidate.py` keeps the original nomination structure
and converts all fields through proved round trips. Checked nominations still
resolve through the same closed source arrays, with the same foreign-source
errors. No source/window verification, ranking or certification rule is removed.
The candidate is isolated from ordinary runtime sources.

Primitive construction 12 passes 224 independent result comparisons and twelve
resolver/effect/failure cases. Its independent original 10,000-row loop takes
513.243 ms; the builder takes 0.485 ms and completes 50,000 rows in 2.677 ms.
Those are accumulator measurements, not hook latency or token savings.

`owner-projection-qualified-20261020/construction-4` builds both callers and
ContractAudit, passes the same focused comparisons, and passes the full
regression in 115,112.201 ms. Three pending tickets drain to zero in a separate
owned daemon without changing graph heads; both shutdown processes exit 0.
Qualification takes 180.074 seconds, peak 3,213,200 KiB, no guard trigger.
Runtime SHA-256:
`aafee26146858867de65db1e57d96dc2c759e963d807e6cf02ab43ff46e46d18`.
Attempts 1–3 retain the missing-library and record-notation build failures.
Primitive attempts 1–11 likewise retain their individual outcomes.

## Uniform hook budget candidate

`tools/uniform_budget_candidate.py` removes the initial/subsequent distinction
from deadline allocation. Both wait for checked nominations for at most
15 seconds and at most half the actual remaining hook time. A matching ready
frame permits either search to finish matching/rendering under the **original
absolute hook deadline**. An absent or invalid ready frame does not extend the
cutoff. The hook's turn/epoch, expiry, publication-size and ACK checks still apply.

The first-search marker remains diagnostic and advances even for failed or
empty results. It no longer grants a different quota. Compaction does not reset
the marker. `tools/UniformBudgetTests.lean` exercises slow numerical responses
over 4.5 seconds on both prompts in one native session and checks the common
allocation, semantic completion and upstream bound.

`uniform-budget-qualified-20261020/construction-1` passes that native sequence:
initial 6,197 ms and subsequent 5,242 ms, both completed semantic responses with
the original overall deadline recorded after readiness. The empty-result fixture
does not establish body delivery. The full regression passes in 109,567.335 ms;
three tickets drain to zero in a separate owned daemon with unchanged graph
heads and both shutdown processes exiting 0. Qualification takes 174.469 seconds,
peak 3,222,896 KiB, no guard trigger. Runtime SHA-256:
`a5fdc5d5446b92f7f90d3473ce781d204a0d81fd500abf3f3e0ab2900ed91193`.

`tools/uniform_budget_probe.py` records a new native cohort using verified warm
inputs, both layouts and three fixed question pairs. It shares the original
source-byte, whole-publication, stdout/hash, ACK and owned-process checks, and
records 30-second limits plus the ready-search policy explicitly. Repeating an
ACKed question may yield no new body; retained evidence is recorded separately
and empty output is never counted as another body delivery.

The completed `uniform-budget-native-20261020/inspection-1` cohort uses the
qualified construction 1, the same saved 10,000-window publication, every
complete warm source-vector byte and the three predetermined questions in
both layouts. Reusing verified inputs adds zero source embeddings or lexical
hydration; warm and repeat take 9,073.075 and 7,393.031 ms separately from hooks.

| Same live session | Cases | Semantic / 30-second passes | Hook elapsed ms | New body / ACK |
| --- | ---: | ---: | ---: | ---: |
| Initial | 6 | 6 | 15,985.352–17,848.819 | 6 / 6 |
| Identical question after ACK | 6 | 6 | 14,984.449–16,236.464 | 0 / 0 |

All twelve discovery responses score the original 10,000 window references;
twelve focus responses also complete. All 24 numerical responses report zero
source-cache misses, unusable records and source encoding time. Every ready
marker arrives before its nomination cutoff; every recorded finish deadline
is the original whole-hook deadline. No case runs lexical fallback. Publication
stdout/hash checks pass for all twelve, and initial body delivery/ACK passes
for all six. Subsequent prompts preserve all previously ACKed keys and retain
the same key count; they do not newly deliver that body. Graph and original vector bytes remain
unchanged. All six owned managers and shutdown clients exit 0.

Collection takes 442.802 seconds, peak 1,527,456 KiB, no guard trigger. The
final audit reproduces both overlays and their helper bytes, verifies native
policy/receipt/publication data, and checks all eighteen frozen ordinary
artifact hashes. Other scales, different-question continuations and adoption
comparisons remain open. These results are scoped to the saved 10,000-window
fixture, rather than a claim that all DB sizes now satisfy the limit.

These are isolated diagnostics and candidates. Latest-public-main matched
inclusive input/output token and answer-quality comparisons remain required
for production adoption. Generation-model trials and production adoptions
remain zero. The rest of the goal, including other scales and different-question
continuations, remains open.
