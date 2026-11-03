# Independent source views of a shared project matrix

Isolated continuation of [project-preparation](../project-preparation/README.md),
source parent `71687d94`. Not adopted. The [plan](plan.json) fixes the scope and
resource limits before native checks.

The physical vector store is shared per project/scope. Independently prepared
original sources can retain different matrix roots: source A's route may finish
before source B appends its vectors. The keyed provider previously keyed its
closed matrix table by directory alone and rejected the second source's valid
root. Single populated-owner fixtures did not cover this case. This is a
preparation/read-scope inconsistency, not evidence that a vector score, synaptic
edge or delivery budget needs tuning.

The candidate keys fixed matrix reads by canonical directory and original source
identity. Routing and scoring consume each source's exact captured matrix root;
the underlying file and vector rows remain shared. Conflicting duplicate views
of the same original source still fail. A missing source entry cannot fall
through to another source, the latest matrix or raw vector files. Dynamic reads
retain their existing behavior. No model, encoder, routing quota, ranking,
WorkGraph, Union/Exact, certification or delivery budget changes.

The [synthetic check](synthetic.json) creates distinct retained roots for two
sources in one physical canonical matrix. Both sources keep their vectors after
a later replacement; a missing source cannot use another source's entry or the
latest root, and duplicate conflicting views of one source are rejected.

The [actual MiniLM check](actual-fixed.json) runs the unchanged parent helper and
candidate on the same two-owner source snapshots and query. Parent discovery
returns unavailable with the specific recorded error `query scopes disagree
about the same matrix root`; candidate discovery succeeds and ranks both source
domains. Original heads are unchanged. Candidate discovery took 604 ms; the
parent's 724 ms is a failed lookup, not a speed baseline. The whole guarded check
including setup/warm/teardown took 22,969 ms with peak owned RSS 1,333,280 KiB.
This is a small discovery availability comparison, not a hook or token benchmark.

The existing [prepared-query regression](retained.json) also passes: after 66
later publications and genuine eviction of the old lookup name, captured
lexical ranks, routing, window rows and vectors remain unchanged. It rejects
latest/raw fallback, foreign authority and a newer unprepared source. Its
synthetic scenario took 2,511 ms. This does not yet transport all prepared roots
across the whole ordinary query lifetime.

The [normal lifecycle](context.json) keeps the six-source captured scope, source
ACK/read binding and single private ingress with five shared-worker imports.
Both original JSON evidence items reach the [returned body](prompt-output.json).
Small-fixture hook times are prompt 344 ms, Pre 98 ms, Post 69 ms and Stop 24 ms.
These are not 80-user p99 or a delivery comparison with the LLVM dataset.
Ordinary ContractAudit and the existing captured-query audit pass; the [audit](audit.txt),
[resources](resources.json), [failures](negative-checks.json) and
[source/runtime identities](result.json) retain the exact scope. Initial type/
fixture-controller errors remain recorded. Final checks have no guard trigger
or surviving owned process, and the aggregate stop/ceiling were not increased.

Apply [candidate.patch](candidate.patch) to `project-preparation-core` with
`git apply --unidiff-zero` and build `tools.research.ProjectMatrixScopes` using
the existing native study builder. Commands are `matrix-scopes FRESH_ROOT`,
`actual-matrix-scopes FRESH_ROOT PARENT_HELPER`, `retained-query FRESH_ROOT` and
`context FRESH_ROOT`. The actual check's private data root must be outside its
fresh fixture root because its numerical keeper starts before fixture setup.
Use the existing MiniLM runtime and recorded aggregate resource monitor.

Neither these small checks nor two successfully searched owners establish
80-user sustained capacity, 98% necessary-evidence delivery or answering-model
token savings. The complete cross-process query lifetime still needs all
prepared component roots, dependency scope and held read capabilities. Existing
search pipes are limited per session manager, not across all 80 users; aggregate
hook/worker memory and preparation throughput remain separate gates.

Matched paid comparisons remain **0/18**. Production, README benchmarks and
releases are unchanged. Ended DBs, caches and raw logs are deleted after compact
evidence is extracted; no archive is created.
