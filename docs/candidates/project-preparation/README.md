# Shared preparation across project owners

Isolated continuation of [project-cache](../project-cache/README.md), source
parent `1ecc4aff`. Not adopted. This changes preparation scheduling, not Work
equality, completion authority or the extraction objective.

One logical project has several independent original append owners. Original
publication remains independent of derived preparation. A local data-side
service owns three preparation workers, rather than a worker per chat or one
installation-wide drain. Source-specific lexical and synaptic work may overlap;
canonical numerical writers remain exclusive to their project/scope. Independent
projects may prepare numerical data concurrently. Three worker slots are a
resource bound for this candidate, not a demonstrated capacity for 80 users.

The Lean scheduler bounds running plus pending requests to 1,024 and their
encoded registry metadata to 8 MiB. No original output or question body is put in
this queue. Identical pending requests coalesce. A notification arriving during
an active attempt remains pending after that attempt finishes; completion needs
the active slot's token. Failure retains debt with backoff. Scheduling ACKs do
not acknowledge source durability or completed preparation. Durable source,
journal and ticket records remain the recovery authority.

Registry discovery follows source-specific references for the complete captured
read scope. The session daemon remembers the wake value observed before
scheduling. It does not rediscover or submit unchanged targets every second,
and a newer wake cannot be cleared by completing an older one. A bounded service
queue rejection leaves the daemon's cursor and wake pending for another attempt.

Long preparation IO runs in the worker processes, outside the scheduling gate.
Shutdown closes admission, cancels derived workers and drains durable source
commits. The client waits for the service's actual exit, rather than treating its
shutdown response as proof that no process remains. Recovery reuses durable
preparation intent; it does not republish acknowledged originals.

## Completion and freshness

The first native run exposed a real completion-classification bug: external
journal inputs deliberately make the conservative freshness probe return false,
even after a successful replay. Using that probe as the post-attempt drain
condition caused endless retries. The candidate retains the conservative probe
before work, requires the replay's actual `complete` result, then checks the
matching known-input checkpoint and remaining tickets/feed after work. This
post-attempt bookkeeping is not a freshness or Work certification rule. The
Lean audit checks that external inputs still require validation.

## Verification and remaining work

The [plan](plan.json) fixes the checks and unchanged resource limits. The
[normal lifecycle](context.json) retains the complete six-source captured read
scope, native source ACKs, single private ingress and five one-hop reference
imports performed by the actual shared workers. Ordinary hook times are prompt
342 ms, Pre 104 ms, Post 75 ms and Stop 24 ms. The two original JSON evidence
items reach the [returned body](prompt-output.json). These are small fixture
times, not p99 or an LLVM delivery result.

The [shared-service check](service.json) sends 80 concurrent scheduling notices
across six sources, publishes originals while preparation is active and observes
three concurrent preparation workers. The first phase drains in 1,418 ms with
zero retries and zero remaining requests/charged metadata bytes. Stopping with
three active jobs takes 23 ms; restart drains the persisted work without changing
any acknowledged original. The [actual daemon check](idle.json) observes no new
submissions during 2,200 ms without a wake, then processes a new wake. These are
80 notices, not 80 complete hook lifecycles or a sustained queue-age measurement.

The [actual MiniLM service check](minilm.json) prepares all six sources in
5,404 ms. The unchanged multilingual MiniLM produces two project/scope matrices
with 13 and 22 rows. Every unchanged source repeat requests zero embeddings and
produces zero projections. Original heads remain unchanged; source preparation
is not a query or answering-model experiment. Peak owned RSS is 1,687,552 KiB.

The [source-only 80-session check](owners-80.json) uses 16 append owners,
recovers all 80 originals/read-input bindings and the complete graph in a fresh
process, and observes 13 simultaneous original publications. Whole-check time is
8,268 ms and peak RSS 371,456 KiB. The 813 ms publication interval excludes native
ingress and preparation and uses repetitive 5 KB inputs. Its preparation counters
are zero: this check does not combine 80 clients with background preparation.

Ordinary ContractAudit and the [Lean boundary/axiom audit](audit.txt) pass.
The scheduling bounds, terminal closure, wake retention and unchanged external
validation depend only on standard Lean axioms. These are not proofs of all IO
concurrency, runtime memory or sustained throughput. [Resource summaries](resources.json)
retain every guarded build/check. [Failures](negative-checks.json) include the
original endless-retry classification, the obsolete fixture assumption that
background imports had not run yet, an early shutdown response leaving live
cleanup, compilation errors and an interpreted test controller exceeding its
1 GiB Lean limit. That controller was compiled into the native helper; neither
the aggregate stop limit nor the 4 GiB ceiling was increased. Final checks have
no guard trigger or remaining owned processes. Builds 12 and 13 have identical
production sources; build 13 adds only the numerical test command.

Apply [candidate.patch](candidate.patch) to `project-cache-core` with
`git apply --unidiff-zero`, then build `tools.research.ProjectPreparationChecks`.
Run `context ROOT` on a fresh private root, then `integration ROOT`, `idle ROOT`
and `numerical ROOT` on that root. `owners80 FRESH_ROOT` is the independent
source-only check. Preserve the recorded aggregate monitor limits. The numeric
command requires the existing MiniLM runtime; no new Python/Ruby control or
extraction implementation is introduced. [Result identity](result.json) records
the source and helper hashes.

Retaining all prepared roots across concurrent replacement, complete cross-owner
certification, transitive cross-project dependencies, external-change wakeups,
MCP storage policy, capacity reclamation and multi-host/NAS authorization remain
separate gates. Directory ticket enumeration and arbitrary worker IO are not
bounded by the scheduler's metadata proof. Do not infer total RSS bounds or a
lock-free runtime from the pure scheduling invariants. Queue age under sustained
ingress, saturation recovery and preparation throughput remain unmeasured.

Matched paid comparisons remain **0/18**. This candidate establishes no total
token improvement, answer-quality result, 98% delivery result, product adoption,
README benchmark or release. Ended experiment DBs, caches and raw logs are
deleted after compact evidence is sealed; no archive is created.
