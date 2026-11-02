# One prepared read set for keyed discovery

Isolated candidate based on `lexical-delta-core`, not adopted. The baseline
runtime remains `66c6cf14…`. No answering-model experiment or inclusive-token
improvement is claimed. The shared service's complete query lifetime and
80-user sustained load remain separate unfinished work.

The compiled candidate runtime is
`1b82d622598e76c8c9719076e7309b4fa707c253e327afd012ebebda10d7a6be`.

The previous code paired the caller's fixed source partition with the latest
matrix head, rejecting a valid completed source after an unrelated matrix
append. Routing and scoring also reopened components at different times;
`handleIndexedUsing` discarded its incoming matrix cache. Later preparation
could therefore remove availability or replace which numerical root was read.

## Implementation

[Product diff](candidate.patch), [predeclared check plan](plan.json).

- `PartitionBuild.read?` first selects the exact-source completed partition,
  then restores that partition's matrix through `HistoryReader`. Authority,
  retained extent, matrix statistics, width and source eligibility are checked.
  `ReadView.sameMatrix` and `matrix_is_routing_basis` bind the two heads in Lean.
- `KeyedSearchProvider.capture` opens lexical, window-owner and numerical
  readers before query encoding. Later nomination consumes these handles,
  including after the bounded completed-root directory evicts their names.
- `MatrixReads` distinguishes memoized dynamic lookup from a fixed read set.
  Keyed scoring preserves the captured matrices. A missing or invalid row in
  a fixed view cannot fall through to a newer matrix or a raw cache file.
  Conflicting matrix heads for the same physical cache scope are rejected.
- Query ranking, MiniLM, vector pooling, router quotas, selection budget,
  WorkGraph, e-class identity, Union/Exact and certification rules are unchanged.
  An unprepared newer source remains unavailable; no older source substitutes
  for the requested evidence denominator.

Apply the patch with `git apply --unidiff-zero` to the unchanged
`lexical-delta-core`. Use the existing native
`StudyBuildMain.lean`; baseline/candidate source, binaries and private roots
remain separate. This does not change the protected `66c6cf14…` runtime or its
sealed or rejected study records.

## Native checks

[Lean audit](../../../tools/research/PreparedQueryAudit.lean) reproduces the
old latest-matrix rejection on the same tiny source. It restores the exact
historical pair, captures the readers, then performs 66 later original
publications and preparation passes. The old lexical lookup name is genuinely
evicted. Captured route nominations, lexical ranks/anchors, window-owner rows
and projected bytes remain identical. A separately published valid replacement
row distinguishes fixed from latest numerical reads; an empty fixed read set
is explicitly rejected despite available latest rows. New queries see the
latest completed source; newer unprepared and foreign-authority inputs fail.

The audit uses synthetic two-dimensional vectors, not MiniLM. Its kernel-time
dependency walk also rejects reopening mutable roots from captured lexical or
routing reads. The full candidate `ContractAudit` compiled. The complete
synthetic scenario took 4,388 ms. The guarded process took 10,193 ms with a
102,560 KiB peak; neither is hook latency or an 80-user benchmark.

[Actual lifecycle](native-gate/result.json),
[source-only recovery](native-gate/recovery.json),
[actual hook audit](native-gate/recall-audit.json),
[resource receipt](native-gate/native.guard.json): five actual shell calls and
three MCP-shaped calls went through ordinary Pre/Post/Stop, publication and
indexing. Seventeen journal events yielded eight portable origins, consumption
1 / supports 16 / coquoted 4. This did not use a real MCP server or dispatch an
answering model. Explicit warm checked journal completion and valid original
and focus numerical windows. A source-only copy with a new private root was
warmed and delivered both predeclared required fixture items in 4,466 ms.
All session/publication services exited with code 0 and removed their endpoints;
the outer guard observed no surviving owned process and a 1,845,920 KiB peak.
The earlier shell-only smoke did not exercise MCP-shaped calls or new-chat
delivery; its compact result is retained separately.

This single small lifecycle is not a matched speed comparison with the parent
and does not establish large-DB recall, token savings or the 80-user target.

Original/canonical payload and shared/private synaptic service views are not
added to this keyed discovery record. Atomic preparation of every service
component, real publication/journal throughput, bounded 80-user queues,
98% evidence delivery and the repeated matched total-token/quality comparison
still need their own evidence. This patch alone is not product acceptance.
