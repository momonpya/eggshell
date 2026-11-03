# Durable read boundaries in concurrent project publication

Isolated continuation of [owned-lexical](../owned-lexical/README.md), not adopted.
One logical project has independent source owners; configured reference projects
remain read-only. The [patch](candidate.patch) applies to `owned-lexical-core`
with `git apply --unidiff-zero`. Copy the tracked
[native check](/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/tools/research/ProjectInputsChecks.lean)
into its corresponding candidate module path. It replaces the old standalone
ProjectAccess check. The source-load harness is updated for the explicit new wire
contract; its previous throughput results do not validate this implementation.

## Read scope and durable publication

The configured publication bridge now requires a checked complete `ReadSet`.
It uses those retained views, including their old heads, rather than obtaining
new current read boundaries during save. Lean proves that the serialized read
image count equals the configured project count and that its total source-head
count equals the actual retained source inventory.

Read registration grants a separate capability and acquires no writer lease.
The service checks each read capability, original incarnation, complete owner
inventory and that project's internal dependency closure before admission.
The write project retains its own cut separately. All source views share the
existing bounded service catalogue and page pool; they are not rebuilt per
observation or copied into per-user databases.

The same original transaction stores a descriptor of its write cut and complete
configured read cuts, plus the receipt-to-descriptor binding. A descriptor has
project/inventory identities and original heads, with no capabilities, locations,
private journal entries, query vectors or foreign original bodies. Identical
descriptors share a content-addressed record within each source rather than
being repeated per observation. No canonical vector copy is added per owner.

The request identity is stable across credential changes. A retry must recover
the exact durable descriptor: dropping/reordering its read projects or replacing
them with later heads is rejected. Successful ACKs carry the checked input
digest. This metadata does not create Union, Match or completed authority.

An ordinary single-source publisher now rejects a project directory before it
can create an unrelated shadow `head` inside it. Normal hooks still need their
actual read boundary carried to the project publisher; the guard is not that
integration and is not an alternate successful save path.

## Native checks

Runtime: `85108cc6e567e5952b0c88c831cd19d416da39898fb2e0ae3adc71845f97c546`.
The [plan](plan.json) was recorded before implementation. Both source builds and
the final native helper include ordinary ContractAudit. The
[axiom audit](proof-audit.txt) uses only standard Lean axioms; it does not prove
concurrent IO, durability of the OS/filesystem or timing bounds.

The [final check](checks.json) passes the following real loopback service cases:

- 80 sessions route across all 16 write owners, with peak 13 active publications.
  Two configured read projects retain 20 original sources. All 80 observations,
  time receipts, reconstructed promotions and the full graph recover in a fresh
  process; all 80 receipt-to-input bindings match the frozen expected boundary.
- A foreign project contains original data before capture and is updated again
  after read registration. All recorded input boundaries retain the older
  nonempty cut. Decoded old graph values contain the first original and exclude
  the later one. The writer project contains no foreign original body.
- Every foreign source's writer lease remains available while its read scope is
  registered. Foreign and same-project read credentials cannot publish.
- Missing owners, wrong read credentials, omitted configured reads, changed
  retry order and replacement with latest heads are rejected without advancing
  original heads. Missing-owner checks also bypass the client and exercise the
  server boundary directly.
- Identical descriptors are stored once per source. Separate metadata checks
  reject corrupt input bindings and descriptor bytes; old pinned readers remain
  unchanged after later corruption.
- A restarted service issues new credentials and replays the old request
  without advancing a source. After that ACK the service is forcibly stopped;
  a fresh process still recovers the exact original graph and input bindings.
- Queue bytes, active publications and borrowers drain to zero. The single
  source API is rejected before creating a shadow DB in a logical project.

The whole check took **9,303 ms**, with peak owned RSS **361,456 KiB**, no guard
limit and no surviving process. The 891 ms publication interval excludes the
preceding controlled journal ingress and uses small repetitive 5 KB outputs.
It is not a matched speed comparison, a complete hook time, p99 or sustained
capacity. The earlier pre-guard check is retained separately; it is not pooled
with the final result.

Initial negative records are retained: two compile errors from reserved Lean
identifiers, a fixture syntax/unused-variable error, an incorrect hex-only
descriptor key and a fixture check that searched numeric JSON rather than
decoded original Values. The key failure occurred before the 80 publications;
neither failed run is counted as a successful full check. An auxiliary source
check initially exceeded its 1 GiB Lean heap setting; aggregate RSS protection
remained unchanged at 3.5 GiB with a 4 GiB user ceiling.

## Remaining integration and capacity obligations

This records actual complete configured read boundaries. It does **not** yet
close transitively referenced dependencies across different projects at query
time; the existing project view closure is internal to each project. The normal
Pre/Post/Stop journal and saved PendingTurn do not yet carry these read views.
They must preserve the actual accepted query boundary, including later accepted
deliveries, rather than inventing it at publication time.

Shared project/scope lexical, synapse and vector preparation and complete
cross-owner certification still need normal-path integration. Existing bounded
registry and image limits remain; increasing user/project counts, owner
handover, sustained backlog, multi-host/NAS and growing storage are not validated
by this short check. No 80-user/eight-hour or 98% delivery claim follows.

Answering-model calls remain zero and matched paid comparisons remain 0/18.
There is no token-adoption evidence, and no product/README-results/release
adoption. Ended DBs, private caches, raw logs and unused helpers are deleted
after compact records are sealed, without archives; current necessary source,
object, interface and link inputs remain. Protected originals are rehashed.
