# Project-shared numerical preparation

Isolated continuation of [project-context](../project-context/README.md), not
adopted. Source parent `c30bcad8`; final native helper SHA-256
`530756edf49965d70086d1f6f575896e2f72b2f798e9bd3802ada253cf3c9f39`.
This connects normal source save to physical preparation targets and makes
canonical numerical data project-owned instead of copying it for each owner.

One logical project retains independent original append owners. A small immutable
cache descriptor binds its identity, authority and complete inventory checksum.
Opening the project checks it against the full manifest; cache placement checks
the source authority without rebuilding the owner inventory. Configuring a bare
physical project source is rejected, so it cannot truncate the certification
read scope. Standalone source layout is unchanged.

The shared derived root contains one raw-vector store and one projection matrix.
Source-specific lexical, synapse, canonical-layout, window and router metadata
retain separate namespaces. A source router consumes its own keys in canonical
order, rather than scanning the entire shared matrix and filtering other owners.
Its exact original/matrix pair survives another owner's matrix append. Warm
readiness uses that retained pair; an unrelated matrix suffix does not demand
another source rebuild. Empty owners do not train a router on foreign rows.

Read-only profiles use a project-scoped private overlay. No query vector or
query memo is added to shared originals. Shared-overlay retirement checks every
source writer region; any live original owner or active source preparer retains
the whole cache. This is cache placement and lifecycle logic, not equality or
completion authority. WorkGraph, Exact, Match and Extract still decide reuse.

## Checks

The [storage check](layout.json) verifies shared canonical placement, separate
source metadata and projects, numerical deduplication, original-head preservation,
read-only preparation outside a fresh project, corruption rejection, old matrix
and router retention, and safe shared retirement. Holding the semantic writer
region does not block an independently owned original publication. Source-only
traversal equals the independent complete-directory reference for the fixture.
These tiny deterministic vectors test storage, not MiniLM retrieval quality.

The [normal-path check](context.json) uses ordinary hook entry functions, real
child workers and TCP publication with four write owners and two read owners.
It retains the parent's raw JSON evidence, complete frozen query boundary,
single native ingress, source ACK/read binding, private project memo, restart,
retry and rejection checks. `derivedPreparationQueued` is now **true**. Single
fixture times are prompt 333 ms, Pre 102 ms, Post 70 ms and Stop 21 ms; these are
not p99 or a comparison with LLVM. The [returned body](prompt-output.json) is
recorded.

In a fresh process, the [ordinary background index worker](preparation.json)
consumes the actual save ticket and leaves `Warm.required=false` without changing
the original head. Logical-project `egg warm` processes all four owners and
`doctor` reports them warm. This check took 1,532 ms. It exposed and corrected a
doctor error: an empty lexical source intentionally has no index file, and must
use the existing `Index.ready` contract.

The [actual MiniLM check](minilm.json) uses the unchanged multilingual MiniLM
model/encoder. The nonempty source prepares seven distinct windows in one batch,
seven projections and a five-point source router in 2,584 ms. Three empty owners
complete without foreign-row routers. Unchanged re-warm requests zero embeddings
and produces zero projections for all four owners; their reported preparation
times sum to 95 ms. Peak owned RSS is 1,312,352 KiB on initial numerical warm.
This is a small preparation check, not delivery recall or an answering-model run.

The same helper reruns the [80-session/16-owner original test](owners-80.json).
All 80 originals, read-input bindings and the complete graph recover in a fresh
process; peak simultaneous publications are 14. The 849 ms publication interval
excludes ingress and uses repetitive 5 KB inputs. Whole-check time is 8,162 ms,
peak RSS 373,024 KiB. It does not combine 80 normal hook lifecycles with continuous
derived preparation.

Ordinary ContractAudit passes. The [audit record](audit.txt) now requires
`ProjectionCursor.foldKeys` and forbids full-directory traversal from source
router construction. These reachability checks and native references are not a
new proof of IO concurrency or performance. [Resource summaries](resources.json)
include all build attempts and checks; guard limits are unchanged, no guard
fired and no owned process remains. [Negative checks](negative-checks.json) retain
compile/fixture failures and the doctor bug rather than relabeling them successes.

## Reproduction and unfinished work

Apply [candidate.patch](candidate.patch) to `project-context-core` with
`git apply --unidiff-zero`. Copy the tracked `ProjectCacheChecks.lean` into its
module path and build `tools.research.ProjectCacheChecks`. The commands are
`ROOT` for the storage fixture, `context ROOT` for a fresh normal lifecycle,
`prepare-context ROOT` for its later background/CLI check, and `owners80 ROOT`
for the source-only concurrency test. The helper also dispatches the ordinary
provider and numerical-service commands. Use a fresh private root and the same
resource monitor; these commands do not call an answering model.

The current installation-wide `index-drain.guard` still serializes background
draining. The next implementation must schedule source/region-owned preparation
through the shared service with bounded resident work and worker count, retain
required old cuts, and measure the real publication/preparation backlog. Removing
the guard while starting an index process for every chat would not satisfy the
memory or ownership contracts.

Retaining a complete project's prepared lexical/synapse/matrix/router capabilities
across concurrent re-warm, complete cross-owner certification, cross-project
transitive dependencies, shared content storage, compaction, MCP policy and
multi-host/NAS remain open. Eight-hour 80-user load, p99 <= 30 seconds and >=98%
actual required-evidence delivery have not passed. Neither the fixtures nor
several separate successful checks establish those properties.

Matched paid comparisons remain **0/18**. No total-token improvement, answer
quality claim, product adoption, README benchmark or release follows. Ended
DBs/caches/raw logs and superseded executable/generated files are deleted after
sealing these compact records, without archives; necessary source/object/interface
inputs, current helper and protected originals remain. The [cleanup record](cleanup.json)
records 622 removed entries, including six ended fixture trees. Rehashed protected
inputs agree with the parent record; no archive was created.
