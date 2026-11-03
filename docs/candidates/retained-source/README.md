# Retained original readers during active query processing

Isolated continuation of [original-feed](../original-feed/README.md), not
adopted. The [plan](plan.json) fixes the contracts and unchanged aggregate
resource limits. There are no answering-model calls or matched paid comparisons.

`CanonicalSourceLease` keeps a charged borrow of the existing shared original
cache until the active query releases its token. It retains the exact canonical
recipe reader and its bound shared-synapse reader. It does not duplicate original
payloads in a per-session cache. Metadata admission is bounded to 8 MiB and
512 handles; existing cache budgets and the 4 GiB hard ceiling are unchanged.

Source rows, palettes, record geometry, binding lookup and multi-source palette
preparation consume a retained reader when a token is supplied. A bad, expired,
released or foreign token is an error and cannot trigger stateless reconstruction.
Stateless administrative access remains explicit. Tokens are transient, scoped
to the authenticated local service and excluded from memo/receipt identities.
Normal recommendation preparation requests retention; `automaticHandoff` releases
every acquired original reference in its finalizer, including memo returns.
Preparation failures release any acquired reference. Lost callers have a bounded
lifetime and the service reaps abandoned handles.

Release/expiry denies new readers. An active reader retains the original cache
borrow and its metadata charge until its own finalizer finishes. Eviction may
remove other idle cache entries but cannot remove that charged borrowed entry.
The pool's metadata lock protects only ownership bookkeeping, not graph lookup,
payload reads or model work. This is not a formal lock-free implementation.

The Lean source-identity, byte-budget and token-independent memo properties use
only standard axioms (`propext`, `Classical.choice`, `Quot.sound`), with no new
axiom, `sorry` or `native_decide`. Standard ContractAudit compiles. These pure
properties do not prove concurrent IO, actual heap bounds or sustained throughput.

The first focused test incorrectly assumed that the current physical write lane
already contained an original. The captured fixture actually has four empty
write lanes and original observations in its read project. Later probes exposed
a second fixture mismatch: its generic MCP observations have no file-row aliases
in the canonical file-row projection. Zero file rows do not assert that those
generic observations are absent from the DB or ordinary handoff. The retained
file-row test therefore creates a verified three-line file observation through
native journal, original publication and normal shared/canonical preparation.
The normal mixed workload continues to test the original MCP-shaped fixture.
These failed probes and compile failures are retained as negative evidence.

The [focused native check](retention.json) passes in 7,564 ms with sampled peak
RSS 248,416 KiB. All three published file rows match the actual RPC body while
the mutable source head is hidden; explicit stateless reconstruction fails.
Eighty logical clients deliver those same rows, with service original loads
remaining one before/after. All 82 service handles finish released or expired,
with zero active handles, readers and charged metadata bytes. Synthetic idle
cache pressure creates 140 entries and 45 real LRU evictions while preserving
the retained entry. Release/expiry during an active read, duplicate release,
foreign scope/root, closed admission and abandoned-service-handle expiry pass.
The fixture head is restored. These are not sustained-capacity measurements.

The normal native lifecycle also passes: prompt/Pre/Post/Stop take
375/145/121/26 ms. It retains six captured source views, ordinary MCP-shaped
observations, original publication and background imports. That context check
uses an earlier harness revision with identical product sources; no controlled
binary comparison is inferred. The [MiniLM burst](workload.json) uses the final
helper for all 80 queries and 80 numerical-configured saves. Every query delivers
both original fixture evidence items. Median/p95/maximum delivery is
15,745/17,912/18,104 ms, with 24 semantic replies and 56 lexical fallbacks.
At foreground completion all 400 retained original handles are released,
with zero active/readers/charged bytes. All 80 original response atoms and
327 numerical windows remain valid. Normal preparation drains in 2,330 ms;
fresh semantic delivery is 2,025 ms and, after verified service restart,
2,449 ms with identical body hashes. The guarded scenario is 31,458 ms,
not one hook's latency, with sampled aggregate RSS 2,655,552 KiB.

During paused preparation, all 24 new originals receive durable ACKs in
1,608 ms. Verified shutdown and normal manager recovery preserve those originals
and all 423 numerical windows; recovery is 17,121 ms with 73 retries and fresh
semantic delivery 2,627 ms. Identical reissue leaves original heads unchanged,
ACKs in 1,345 ms and recovers in 3,768 ms with one retry; semantic delivery takes
2,813 ms. Both actual interrupted-query bodies are recorded; their hashes differ
because private derived state was not frozen. These are durability checks, not
controlled selection, latency or token comparisons. The remaining preparation
retries are not resolved by original reader retention.

Resource observations are independent of the accounting theorem. All guards
finish with no surviving owned process. Early compile errors and the four
unsuitable fixture probes remain in [negative records](negative-checks.json).
An edit-only controller initially exceeded its 512 MiB Lean import budget;
narrowing its import fixed that without running product IO or raising resource
limits. After sealing compact evidence and actual bodies, [cleanup](cleanup.json)
deletes the ended fixture, 388 closed/generated files and the superseded helper:
230,271,477 apparent bytes. It claims no equivalent physical-space reclamation.
Protected original/fixture hashes remain unchanged; no archive is created.

Retention begins inside active `automaticHandoff` processing, after worker
admission. It does not yet retain all derived roots while a request waits in the
worker queue. Lexical/numeric readers remain captured by the existing keyed
provider; private usage remains separately pinned. This is not atomic publication
or one held service view spanning every component. Many-source admission, complete
cross-owner certification, transitive read dependencies, multi-host/NAS behavior,
80 people for eight hours, 98% required-evidence delivery and matched total-token
improvement remain unfinished. No candidate is adopted by this component test.

Apply [candidate.patch](candidate.patch) with `git apply --unidiff-zero` to
`original-feed-core`. Build `tools.research.RetainedSourceChecks` with the existing
native study builder, renaming the imported original-feed entry point to
`originalFeedMain`. Run `context-prepared-numeric FRESH_ROOT`,
`retained-source ROOT`, `drain ROOT`, `interrupt-preparation ROOT` and
`interrupt-retry ROOT` with the same private data root. The retention command
requires its file-fixture subdirectory to be fresh. Use one aggregate guard at
a time for this experiment prefix. [Identity](result.json), [resources](resources.json),
[Lean audit](audit.txt), [original delivery](prompt-output.json) and
[interrupted bodies](deliveries.json) separate scope and evidence.
