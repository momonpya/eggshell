# Release exact preparation work with its waiters

Isolated continuation of [source-interests](../source-interests/README.md),
parent `2b5c7aee`. Not adopted. One logical project still has multiple
independent original append owners. The [identity record](result.json) checks
that original publication, project ownership/routing, captured inputs, operation
admission and Handoff sources are unchanged. This does not serialize a project
behind one original writer or create per-user project/vector copies.

The parent retained exact-cut preparation after the requesting hook stopped
waiting. This candidate gives each waiter a service-issued ticket with one fixed
expiry under its original cutoff. Source submissions require an already-live
ticket: a delayed request cannot recreate a released or expired registration.
Matching immutable jobs share their waiter references, including while running.
One release removes only its own reference. Last release or expiry removes
unneeded pending work. Durable publication wakes remain independent and are
never removed by query cancellation.

Active work retains its lane until the actual IO stops. The scheduler marks
retirement before closing the owned worker handle; a later valid waiter queues
behind that attempt. Attempt tokens reject stale retirement/completion.
Three reusable handles belong directly to the preparation pool, replacing the
global name lookup for those workers. Closing an old handle cannot kill its
replacement. Service closure is terminal before children are stopped. Remote
search cancellation is registered before cold input capture, so it also reaches
this preparation wait. Best-effort early release neither starts a service nor
extends the requesting cutoff; fixed expiry bounds a lost release.

The existing request bound remains 1,024 and charged metadata remains 8 MiB.
Waiter registrations also have a 1,024 bound; registrations and job-reference
edges are charged separately. These are scheduling-accounting invariants,
not proofs of native heap usage, timing, arbitrary IO or end-to-end liveness.
Short metadata mutexes and source/derived ownership leases still exist; this is
not a lock-free IO implementation. Original writes do not wait for this pool.

The [native model check](model-checks.txt) covers 80 waiters sharing one job,
individual and last release, late submission, retirement, stale tokens,
1,024-request/1,024-grant saturation and expiry recovery, durable newer wakes
and terminal closure. This is a model test, not 80 concurrent hook clients.

The [actual worker check](io.json) pauses a real product `codex-worker index`
before assigning work, without adding a production delay or fake backend.
Releasing one of two waiters leaves the blocked operation live; releasing the
last stops its real IPC/process, with zero remaining charge or retries. A fresh
owned handle then prepares the same actual source. Closing the old handle again
does not close that successor, and the acknowledged original head is unchanged.
Closed admission cannot grant a new ticket or recreate a worker.

The predeclared [hook checks](plan.json) use two original owners. They capture
unprepared A1/B1, prepare A2/B2 first, then call ordinary `deliverForWork` with
no harness historical warm. Every row delivers both captured original responses,
keeps later ready inputs and original physical heads, rejects future originals
and private-root substitution, and finishes with no grants, references, active
or pending jobs or charged metadata.

| Fresh fixture | Original bodies | Complete hook path |
| --- | ---: | ---: |
| [Write](write.json) | 2/2 | 1,237 ms |
| [Write repeat](write-repeat.json) | 2/2 | 1,228 ms |
| [Read-only](read-only.json) | 2/2 | 1,213 ms |
| [Read-only repeat](read-only-repeat.json) | 2/2 | 1,212 ms |

Read-only preparation uses user overlays. The first write check records one
`DB writer is busy` retry; the other three record zero. Two preparation workers
overlap. These synthetic fresh fixtures are not matched speed comparisons or
LLVM/80-person/p99 results. A [fresh process](restored.txt) restores the write
fixture's exact original/private boundary and byte-identical delivery.
[Write body](write-body.txt), [read-only body](read-body.txt).

Ordinary ContractAudit includes the actual waiter-registration/release and
owned-worker call connections. [Ten kernel laws](laws.txt) cover expiry
non-extension, admission bounds, rejection without registration, preservation
of other claims, stale retirement and terminal closure. Only standard Lean
axioms occur. These laws do not prove the entire native cancellation protocol.
The [negative records](negative-checks.json) retain the initial model syntax
failures and integrated type/API/test-source errors; no failed build is used as
a successful runtime. [Resources](resources.json) show sampled aggregate peak
2,839,120 KiB, no guard trigger and no owned survivors. The 3.5 GiB stop,
4 GiB ceiling and 2 GiB disk floor were not raised.

Apply [candidate.patch](candidate.patch) to `source-interest-core`, copy the
three tracked `InterestLifetime*Checks.lean` modules into their module paths,
and build `tools.research.InterestLifetimeChecks`. The [setup](setup.lean) and
[records controller](records.lean) retain exact commands and cleanup boundaries.
The separate [law setup](laws-setup.lean) uses the tiny scheduling dependency.

Sustained combined publication/preparation/query load, unstable transport and
service-restart ticket recovery, actual numerical execution, full Pre/Post/Stop,
large original domains, multi-host/NAS semantics and compaction leases remain
gates. Shared dictionary preparation still has an exclusive writer; this change
does not establish its throughput. Parallel original owners are necessary for
the chosen architecture, but not evidence that 80 people can work eight hours
without growing preparation debt. Practical 98% delivery, p99 below 30 seconds,
quality and matched total-token improvement are unestablished. Encoder and
answering-model calls are zero; paid comparisons remain 0/18. No product,
README benchmark or release adoption follows.

After compact evidence is extracted, finished fixture DBs, private caches and
raw logs are deleted, without archives. Current build inputs and protected
originals remain. [Deletion accounting](cleanup.json) and
[protected-original verification](protected-after.txt) are recorded separately.
