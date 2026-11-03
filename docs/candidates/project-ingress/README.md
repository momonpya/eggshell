# One original private ingress event across project source views

Isolated continuation of [project-inputs](../project-inputs/README.md), not
adopted. A logical project retains multiple independently owned append streams.
The user selects one write project; configured reference projects stay read-only.
This change does not replace those owners with a single project-wide writer.

## Ingress representation

The old `SynapseLive.observe` loop writes a full event to every configured
source. Flattening the physical owner inventory into that loop would multiply
large Post bodies by the number of owners. This candidate adds the journal
representation needed to avoid that multiplication; **the ordinary hook loop
has not yet been connected to it**.

A native event has one original private journal record. Start/answer knowledge
can retain the other checked source heads and index hints. Source projections
preserve the native occurrence, Work, query, input, output, answer, clock,
archive and confirmed-delivery context. Only source-specific knowledge changes.
This is private ingress metadata, not another canonical vector or shared
foreign-body copy.

A background importer commits small one-hop references into source-specific
private journals. Each reference binds the original source authority, immutable
journal head, ordinal, original digest, target source and projected digest.
Indirect references and foreign scopes are rejected. Original append receipts
are checked before import. The per-source receipt chain is computed from the
decoded event rather than the reference encoding. Alias rows and their import
cursor use the same PageMap transaction.

Imports are bounded to at most 256 entries, 16 MiB of logical input and the
caller deadline per slice. Ordinary native capture retains its existing 8 MiB
event bound. Unrelated starts/answers are skipped; a Post without its Pre stays
explicitly unknown. Identical retries keep the first knowledge and time and do
not advance a journal head. No recommendation gains Union or completed authority.

## Checks

Native helper SHA-256:
`2b478872f5aa8b6912cf3c6d78dff472203f5f6d8df597e9d2ef488d0343875d`.

The [native check](checks.json) uses a 50,047-byte generic MCP-shaped JSON
response with quoted fields near its ends, plus a consuming call and an answer.
It captures five events once, imports them in slices of two without local body
chunks, and compares their projection with independently captured secondary
knowledge. Referenced and direct replay agree on every replay field. Normal
background replay produces two `omittedThenConsumed` private usage labels.

The original source publishes two shared consumption edges and two quotation
supports. Foreign private replay produces no shared consumption, preserving the
existing publication boundary. This MCP spelling fixture produces **zero
explicit coquoted facts**; it does not validate all three recommendation-edge
families. File-citation coquotation is unchanged. No extraction or scoring rule
was changed to make the fixture pass.

The check rejects wrong scopes, indirect references and changed original or
projected digests. An expired slice leaves the cursor/head unchanged. A corrupt
committed alias is rejected while a retained old reader still works. Later
original appends do not change old references; a fresh process recovers exactly
the same private view. Whole-check elapsed time is 6,931 ms, peak owned RSS
164,752 KiB, no guard trigger or surviving process. These are component-check
figures, not hook latency or throughput.

The same helper also reruns the parent
[80-session project check](owners-80.json): 16 routed write owners, two read
projects and 20 retained sources, with peak 13 simultaneous publications. All
80 originals, input bindings and the complete reconstructed graph recover in
a fresh process. Missing owners, wrong read grants, changed retry boundaries,
corrupt descriptors and accidental shadow databases are rejected. Whole-check
time is 7,700 ms and peak owned RSS 360,688 KiB. The 794 ms publication interval
excludes journal ingress and uses repetitive 5 KB outputs. It is not a matched
speed comparison or sustained capacity result. **This separate check does not
exercise the new reference importer with 80 concurrent event feeds.**

The source build includes ordinary ContractAudit. The
[Lean proof audit](proof-audit.txt) covers source identity/context, observation
clock, exact native payload preservation and bounded cursor movement using
standard axioms only. It does not prove concurrent IO, crash atomicity of the
filesystem or a timing bound. An auxiliary proof initially hit its 1 GiB Lean
heap setting; the successful run used 1.5 GiB while the aggregate 3.5 GiB stop
and 4 GiB user ceiling remained unchanged. Initial compile errors and the
incorrect demand for foreign shared consumption are retained as negative checks.

## Reproduce and remaining integration

Apply [candidate.patch](candidate.patch) to `project-inputs-core` using
`git apply --unidiff-zero`. Copy the tracked
`tools/research/ProjectIngressAudit.lean` into the same module path. Build the
existing `tools.research.ProjectInputsChecks` controller. Its added
`ingress ABSOLUTE_ROOT` and `inspect-ingress ABSOLUTE_ROOT` commands use a fresh
private data root; the existing single-root command runs the 80-session check.
The separate tracked `ProjectIngressProof.lean` checks the additional theorem.

The actual accepted query/read boundary must still be carried through normal
Pre/Post/Stop, PendingTurn and save worker. Capture must construct knowledge
from the checked project ReadSet and archive into the physical selected write
source, not a logical directory or new latest heads. Feed registration, worker
scheduling, retention of referenced private journal heads and the late-Pre /
interrupted-import cases need integration and further native checks. Referencing
one body does not by itself eliminate repeated replay work across sources.

Project/scope shared lexical, synapse and canonical vector preparation,
transitive cross-project dependencies, complete cross-owner certification,
growing-data backlog, maintenance, eight-hour 80-user load, multi-host/NAS,
p99 <= 30 seconds and 98% delivered evidence remain unvalidated. Short source
publication and journal component checks cannot be combined into those claims.

Answering-model calls are zero; matched paid comparisons remain 0/18. No total
token improvement, product adoption, README benchmark result or release follows.
Ended fixture DBs, private caches, raw logs and unused helpers are deleted after
compact evidence is sealed; no archive is created. Necessary source/object/
interface/link inputs and the current helper remain.

The [cleanup record](cleanup.json) lists 232 removed entries, including all
three ended fixture trees and the previous native helper. Protected original
snapshots, fixed diagnostic input and retained controls were rehashed unchanged.
