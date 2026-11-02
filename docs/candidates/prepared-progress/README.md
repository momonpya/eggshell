# Preparation progress across source publications

2026-11-03. Isolated candidate; not adopted. Inclusive-token improvement,
98% hook-body delivery and 80-person sustained performance remain unverified.
No answering model was called in these checks. The interrupted acquisition
remains rejected; its token limit and sealed cohort were not changed.

The previous [native reproduction](../native-study/preparation-conflict/result.json)
rejected a readable revision 42 solely because revision 43 was current.
This candidate completes preparation of the selected immutable source instead.

## Implementation

- [PreparedRoot](../../../tools/research/prepared-progress/Eggshell/PreparedRoot.lean)
  binds a source head to a complete component head. The component tree is
  mutable preparation workspace; foreground reads restore the named immutable
  root through a checked `HistoryReader`.
- A fixed ring holds at most 64 exact views, plus `latest`. Full source-head
  equality checks a ring hit. A collision is a miss, never identity. Slots are
  overwritten without creating a new index key or tombstone per publication.
  Active readers retain their opened handle independently of the ring.
- A new `latest` must extend the previous source through checked publication
  ancestry. `Promotion.never_backward` and `same_database` reuse the existing
  Lean lineage proof. An older completion remains independently usable and
  cannot demote `latest`. Neutral memo publications may share a component only
  when the checked delta has no changed owners.
- [Product diff](candidate.patch) connects lexical, window-owner and partition
  preparation/read paths. Complete roots are registered after atomic component
  publication. Incarnation/authority, original membership, component-header,
  row-count, extent and checksum checks remain. Later source/matrix heads do
  not invalidate a still-readable input pin.
- A missing window-owner completion directory is recoverable from its complete
  workspace publication. This covers the gap between component commit and
  registration; it must not return `warm` forever without registering a view.
- The embedding model, encoder contract, ranking, selection budget, WorkGraph,
  Union/Exact and certification rules are unchanged. This is preparation and
  read-root selection, not a new ranking heuristic.

Apply `candidate.patch` with `git apply --unidiff-zero` to the unchanged
`empty-routing-core`, copy the new
`Eggshell/PreparedRoot.lean` from its research source, and compile with the
existing `StudyBuildMain.lean` native builder. Baseline and candidate cores,
executables and private data roots are separate. The fixed study runtime
`e39c5aa3…` is not overwritten. The candidate runtime is
`1ba7fa0632cc97c0c3cadb0d8fa275149d8eb32a0b629d845ab92dd26c9cafc7`.

## Native evidence

[Synthetic checks](native-result.json), [resource guard](native.guard.json):

- Preparation overlapped three source publications, completed its selected
  source, and left the newer source explicitly unprepared until catch-up.
- Lexical results matched a full scan; numeric memberships/counts matched a
  full original-window census; window-owner postings matched the full source
  directory. Synthetic two-dimensional vectors were used, not MiniLM.
- Old source/matrix preparation, incremental preparation after further source
  and matrix advancement, old active readers, reverse completion order,
  foreign authority rejection, corrupt-root rejection, a missing completion
  directory, and reopening from a fresh process all passed.
- New repair events survived acknowledgment of the captured older events.
  This tests the existing debt-ID contract; it is not an end-to-end proof of
  every scheduler acknowledgment path.
- The ring test covered more than 64 source publications and checked at most
  64 live named views and at most 65 reachable catalogue rows.
- The complete synthetic scenario took 1,012 ms. This is neither hook latency
  nor a scale/load benchmark. An earlier test failed because the test itself
  registered mutable old workspace as a completed newer root; the corrected
  test uses the retained completed root. That failure is retained separately.

[Real source](real-source.json), [resource guard](real-source.guard.json): the
same protected interrupted acquisition from the previous failure now permits
revision 42 preparation and revision 43 catch-up. Both lexical and window-owner
roots remain readable afterward, and revision 43 was not prematurely certified.
Twelve lexical probes per source matched an independent full original scan;
all window-owner occurrences matched the source directory. The protected data
file SHA-256 and source head were unchanged. The diagnostic took 15,241 ms,
including independent original-body scans. It did not run numerical warm or a
delivery benchmark, and does not make the interrupted seed acceptable.

[Native lifecycle](native-gate/result.json), [recovery](native-gate/recovery.json),
[actual body audit](native-gate/recall-audit.json): the compiled candidate passed
the ordinary eight-operation Pre/Post/Stop sequence, final explicit warm,
source-only recovery and new-chat delivery. Five actual shell calls and three
MCP-shaped calls produced eight portable origins and 17 journal events, with
consumption 1 / supports 16 / coquoted 4. This did not use a real MCP server.
Both required fixture items were delivered in 4,570 ms. The synaptic receipt
completed with 15 requests / 25 facts. The guard peak was 1,722,640 KiB and all
services exited. This used the actual MiniLM boundary; it is still a small
fixture, not the LLVM topics or an 80-user load test. The reviewed App Server
bundle exposed exactly eight enabled trusted hooks.

The full [ContractAudit](contract-audit.txt) compiled against the changed core.
The first direct check could not resolve its test-only imports; the native
builder compiled `tests.CorpusCache`, `SearchMemo` and `FullSearchOracle` against
the selected interfaces before the successful audit. This was a check setup
failure, not evidence of a product contract failure.

Runtime construction passed at 2,664,464 KiB aggregate peak. The controller,
built against the same candidate source, is
`0ba6cb637360bb020fb1c976760d36f8aa18ca8e8b686e4f42a2d191a654cf8f`.
The aggregate 3.5 GiB stop, absolute 4 GiB ceiling and 2 GiB disk floor were
unchanged. Completed synthetic DBs/read-caches were [deleted](cleanup.json);
code and compact results remain, without compressed archives.
The ended lifecycle DB/cache/stage-log directories and standalone audit
executable were also removed. Required compact gate records were fingerprinted
before and after removal and are unchanged. DB replay requires rebuilding a
new fixture; the current runtime, controller and source core remain protected.

## Remaining work

The native runtime/lifecycle checks passed. Next, verify numerical/synaptic
preparation through the ordinary worker under sustained publication. This
component-level fix is not yet
a single atomically selected view across canonical source, shared/private
synapses, lexical, matrix and partition roots. Continuous-write throughput,
bounded backlog, project-service sharing, crash recovery of the whole worker,
and 80-user load must be measured rather than inferred from these fixtures.
Lexical warm still enumerates the complete source candidate directory. A
valid completed workspace basis must drive source-delta updates instead; full
enumeration belongs to bootstrap/recovery/oracle work. Removing head-change
rejection alone does not establish that preparation keeps up with publication.
In particular, a newer DB-present record must not disappear from the delivery
denominator because an older prepared view is available.

The ring bounds reachable lookup metadata, not append-only disk growth. Physical
compaction must preserve registered/active roots or explicitly make them cold;
arbitrary truncation/compaction is not proved by append-only reader tests.
The existing bounded ancestry walk can refuse promotion across a gap beyond its
budget; it must not be interpreted as an empty source delta.

Only after the remaining ordinary preparation checks pass, freeze a new
runtime/cohort for paid comparisons. Product adoption still requires repeated,
matched first/history topic 1/2/3 comparisons with inclusive total tokens,
quality and deadline checks. No production or README performance claim follows
from these proofs and tests alone.
