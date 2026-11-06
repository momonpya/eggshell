# Share immutable read views

Isolated implementation; not adopted. This change removes repeated image
construction and metadata-cache updates from already prepared original reads.
It does not establish eighty-person capacity, real98% delivery, answer quality
or inclusive-token improvement.

The parent charged and captured the same source metadata and record geometry
separately for each query, with at most eight active views. The candidate
retains a bounded immutable image and gives each request a separate charged
lease. Images use complete source/head/manifest/scope identities and canonical
owner membership. The private batch binding preserves the caller's order;
question, deadline, capability and retained token are not public image keys.
Every request still authenticates all sources and its retained token before a
cache hit can create a lease. No recommendation becomes certification.

The existing128MiB bound remains. At most eight resident/building images and
the existing160-operation ceiling are checked on every registry update. Active
borrowers remain charged through release, expiry and close until their finalizer.
Idle images can be evicted; each private lease has its own deadline and scope.
This is bounded sharing, not an increased worker, memory or timeout allowance.

`View.project` returns metadata, original ranges and question-specific focus
through a pure`Except` function. The running service calls this function; it
cannot acquire a mutex, mutate cache state, start a task or wait for a fill.
Content serialization and geometry accounting run outside the registry mutex.
A resident hit also returns its already checked byte count directly, removing
an extra registry acquisition. The registry still synchronizes admission,
pinning, release and retirement of mutable lifetime state. Authentication,
source-cache loading, payload fetch, transport and publication retain their
separate synchronization. This is not a claim that all retrieval is lock-free.

Lean laws establish original-boundary binding, membership preservation, shared
source identity, private scope/deadline separation, projection independence
from lifetime bookkeeping and the byte/image/lease bounds. Ordinary ContractAudit
passes. An actual declaration audit connects actor/context/client/service to
the pure projection and examines1,953 dependencies for shared synchronization.
The native255-object closure is consistent; direct changes are exactly
SourceViewBatch, SharedReadViews and PublicationService, with precisely those
source bytes embedded by PublicationWire. These checks do not formalize OS/FFI
behavior or prove application capacity.

Native controls hold the view-registry and prepared-source mutexes while eighty
readers execute the actual pure batch projection. They complete in1ms with
identical metadata, record geometry and focus. A separate eighty-request test
holds all eighty leases concurrently, alternates questions and owner order,
and checks focus against the independent original-window implementation.
Image count/build count stay at two; residency866,656 bytes is unchanged and
eighty private leases cost5,102,720 bytes. Typed/wire parity, original scope,
full head/root/capability, invalid retained token on a cache hit, foreign focus,
expiry, cancellation and active release controls pass. Existing file-read
controls also hold a preparation lock during eighty readers×128 reads.
These are component controls, not eighty full searches.

The ordinary fixed16-source cohort runs sixteen parallel queries in two waves.
All32 complete semantic search, both required original fields and ACK within
30s. All32 complete stdout bodies equal the parent. Prime included,35 actual
outputs are independently retained and verified. Latency min/median/max is
5,661/7,032/7,882ms. This single cohort is not a p99 or token-adoption comparison.

The real service builds one image and reuses it34 times. Metadata-cache hit/join
counts remain543/97 after prime instead of growing with each query. The query
view accounting peak is28,317,600 bytes; the prior retained cohort reported
110,419,200. Those are accounting charges, not whole-process live heap bytes.
Frontend shutdown is319ms/exit0, publisher exit0, with no guard intervention or
owned survivors. Related peak RSS is2,790,560KiB. Host RSS still grows
175,120→654,112→895,520KiB; this does not improve the prior memory result.
Consequently no unchanged eighty-full-search trial is attempted and the host
memory problem remains open. Background preparation is still active/pending
at the last observation; it is not labeled drained there.

The subsequent [host-memory diagnosis](../heap-ownership/README.md) runs the same
sealed runtime with optional tracing disabled. All35 outputs remain exact,
and host RSS still grows179,920→667,824→891,312KiB. It rules out detailed tracing
as the main explanation; it does not establish a memory repair.

Ranking, selection, certification completeness, source payloads, source heads,
deadlines and resource limits are unchanged. Answering-model calls remain0;
paid matched comparisons remain0/18. The product, README results and releases
are unchanged pending the prescribed token and quality comparisons.

Ended DBs, caches, sessions, raw logs and compiler logs are deleted after compact
evidence verification. Required originals and native inputs remain; the baseline
alias is restored. Before this study, unused old derived caches were also deleted
after verifying sixteen complete project heads and five other protected files.
No archive is made. Failed preflights/builds are recorded, not counted as passes.

[Plan](plan.json), [patch: read views](SharedReadViews.patch),
[patch: image membership](SourceViewBatch.patch),
[patch: real service](PublicationService.patch), [build/laws](build.json),
[native closure](native-closure.json), [exact source comparison](native-sources.json),
[native controls](native-checks.json), [held-lock reads](held-lock-reads.json),
[eighty leases](eighty-leases.json), [actual output evidence](evidence.json),
[bodies](bodies.json), [verification](verification.json), [parity](parity.json),
[measurements](measurements.json), [cache snapshots](shared-cache.json),
[summary](summary.json), [all guards](controls.json),
[development failures](development.json), [cleanup](cleanup.json),
[old derived-cache cleanup](retired-derived.json).
