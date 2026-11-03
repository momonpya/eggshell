# Configured projects and independent publication owners

Isolated continuation of [owned-project-views](../owned-project-views/README.md),
not an adopted product change. Multiple concurrent source owners within one
logical project are mandatory. Each mutable source has one owner; the user still
selects one project write DB. The number of owners is independent of user count.

The [patch](candidate.patch) separates read-only project/source definitions from
the native publication compiler and adds a checked configuration binding. Apply
with `git apply --unidiff-zero` to `owned-view-cache-core`; the tracked
[Lean check](/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/tools/research/ProjectAccessChecks.lean)
is its native entry point. Routing is now defined once and shared by configuration
and the service. A write route carries its native session, registered project and
bounded physical slot. Only the configured write project grants one; read-only
bindings grant none. Conflicting paths for the same logical identity are rejected.

The configured read set retains every configured project and all its source
owners, independently of the write route, recommendation rank or index warmth.
Lean proves the configured destination, registered physical identity, absence of
a writer in a read-only selection, complete project count and complete source
count. The [axiom audit](proof-audit.txt) uses only standard Lean axioms; it is not
a proof of concurrent IO, storage durability or time bounds.

The explicit native client bridge prepares against the caller-retained write
project view and submits its cut through the existing owned service. The durable
receipt names a physical source, but reconstructing the submitted WorkGraph now
uses the logical project path. The native check compares all reconstructed
promotions with the complete committed graph, in addition to checking original
bytes and occurrence provenance. Ordinary single-source client behavior is
unchanged; ordinary Pre/Post/Stop is **not connected** to this bridge.

## Native result

Runtime: `cec84739cd956f155fa49726cbe2c58a2913a22c2d37223b446092e15cc94f8e`.
The [build](build.json) includes ordinary `ContractAudit`.
The [checks](checks.json) passed the predeclared [plan](plan.json):

- Normal TOML configuration selects one write project and two read projects,
  retaining all 20 sources (16 write-project owners plus four reference owners).
- 80 native sessions reach all 16 write owners; peak simultaneous source
  publication is 16. All 80 original observations have complete native timing
  receipts, and an identical retry returns its ACK without advancing a head.
- Every original byte and logical receipt is recovered in a fresh process;
  reconstructed promotions equal the full committed graph.
- Read-only and retained boot views remain unchanged. Wrong sessions, write
  destinations, project views, source receipts and conflicting aliases are
  rejected. All owner leases can be reacquired after normal service shutdown.
- Service queues, active operations and borrowers drain to zero.

The full check took 9,362 ms; the [guard](checks.guard.json) sampled peak owned RSS
338,720 KiB, fired no limit and found no surviving owned process. The 504 ms
publication interval excludes ingress recording and uses a small, highly
repetitive synthetic output; it is **not** a comparison with the previous 50 KB
load, a sustained rate, p99 or hook latency.

## Remaining obligations

The explicit publication bridge currently seals the write project's dependency
cut. The complete configured read set is represented separately; durable causal
dependencies across different projects are not yet carried by this bridge. It
must not be presented as a sealed multi-project transaction or connected to
ordinary hooks on that assumption.

Ordinary policy-approved journal routing, shared project/scope canonical vector
and content preparation, prepared-root alignment and complete cross-owner
certification still need integration. Real MCP/NAS/remote operation, 80 users for
eight hours, growing storage, actual 98% evidence delivery and matched total-token
improvement remain unvalidated. The prior 50 KB write-only rate was below the
maximum assumed input rate; this binding does not resolve that limit. Answering
model calls remain zero; matched paid comparisons remain 0/18. Nothing is adopted
into the product, README results or a release.

Ended native DBs, private caches and raw logs are deleted after sealing compact
records; no archive is made. Candidate sources, necessary build inputs and the
current native helper are retained. Protected originals and controls are checked
before and after cleanup.
