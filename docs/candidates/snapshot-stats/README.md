# Immutable reads outside owner locks

Isolated candidate; product code is unchanged. Answering-model calls0, paid
matched comparisons0/18. This does not establish token savings, end-to-end
latency,80-user capacity or98% delivery.

Two read-only operations retained shared locks beyond the handoff of state:

* `stats` held the publication mutex while waiting on child cache mutexes,
  reply accounting, worker diagnostics and optional heap observation.
* `scopedSource` scanned and checked the registration array while holding its
  registry mutex, despite the array and each registration being immutable.

The candidate captures seven scalar status fields under the short publication
lock, then collects child reports and renders the response outside it. The
status snapshot contains no queue, handle, mutable reference, promise or
locking capability. Source authorization similarly captures the immutable
registration array, then resolves database, scope and capability with a pure
function. Registration, admission, cancellation and release still synchronize
their mutable state. The handoff itself is not claimed to be lock-free.

Lean proves the original status fields and counters are preserved, rejects
missing and foreign registrations, and checks the actual IO boundaries.
The declaration audit connects actual service calls to these functions and
checks338 pure dependencies for synchronization entry points. It is a
declaration audit plus kernel laws, not a theorem about all runtime IO or RSS.
Native checks hold the publication mutex throughout child collection and the
registry mutex throughout4,096 pure lookups. They also separate captured and
updated live states and reject foreign databases, scopes and secrets.

The selected native closure, not the restored experiment source, defines the
parent. The first native lock checks passed, but a later audit rejected the
runtime because `PublicationWire` still embedded the old service source.
That initial result is retained separately; it is not a coherent service
success. The identity producer is rebuilt with the exact new service bytes.

The coherent candidate passes the native checks and the unchanged sealed
client's two16-client waves. All32 complete stdout values are byte-identical
to the allocator-service parent;32/32 deliver required original fields and
ACKs and complete semantic handoffs. The independent recorder verifies35
actual outputs including prime. Latency min/median/max is6,666/7,464/8,173ms;
related sampled peak RSS is2,715,696KiB. This single control establishes no
latency or memory improvement. It is a frozen synthetic fixture, not a
real-workload98% result or a token/quality adoption comparison.
Startup failures from a stale runtime alias and the missing test-entry audit
delegation are retained;both occurred before actual queries. Only the test
entry was relinked to restore the original audit delegation.

The remaining read-path ownership work includes canonical source page pools,
file caches, view/lease admission and reader coordination. Replacing a shared
mutex with an unsynchronized reference would introduce a race, not discharge
an ownership obligation. Existing readonly-page, immutable-deadline and owner
metadata candidates remain separate, verified scopes.

[Plan](plan.json),[isolated implementation](candidate.patch),
[initial identity-audit rejection](initial-build-audit-rejection.json),
[native/kernel evidence](controls.json),[build provenance](build.json),
[hook evidence](evidence.json),[byte parity](hook-parity.json),
[independent body verification](verification.json),[deletion](cleanup.json).
