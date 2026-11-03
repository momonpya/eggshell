# Frozen project views through normal hooks and publication

Isolated continuation of [project-ingress](../project-ingress/README.md), not
adopted. One configured project remains one logical DB with multiple independent
physical write owners. Reference projects remain read-only. WorkGraph, Exact,
Match and Extract still decide reuse; recommendation does not acquire authority.

## Normal-path connection

UserPromptSubmit now captures the complete configured project views before its
first lookup and serializes those original heads into PendingTurn. Subsequent
searches, private Pre/Post/Stop observations and publication reopen exactly that
turn boundary. Reopening requires the same project, inventory, configured order,
every owner and the exact retained source heads. A captured Context carries a
Lean equality between its actual read images and the serialized boundary, plus
proofs that no configured project or source was omitted.

Normal automatic and manual search accept those immutable snapshots rather than
opening current physical paths again. All physical owners are supplied to the
existing complete Work discovery; recommendation rank cannot remove certification
inputs. A turn keeps this boundary until it ends. Later publication becomes
visible to a newly captured turn; this candidate does not merge new cuts into an
existing turn.

Native ingress uses the selected physical write route from the start. The first
integration run exposed a logical directory passed as an archive DB before it
was corrected. Raw event bodies are now appended once, with other checked source
knowledge retained as metadata. Source maintenance targets retain the original
ingress owner. The ordinary index worker imports bounded one-hop references
before replay and leaves incomplete work explicit. Publication uses the captured
read views, carries their descriptor into the original transaction and validates
the ACK. It never creates a shadow head at the logical project directory.

## Query memo isolation

The next run exposed an independent ownership violation: a query memo updated
the writable original PageMap outside its project owner. That advanced an empty
owner from revision 0 to 1 without its publication-history entry, making the
captured revision impossible to reopen. This was not a retrieval-score problem.

Demand memo reads/writes now use a separate user-private PageMap under
`query-cache/<project-identity>/handoff`. The project scope is independent of its
selected write owner or chat. Complete source dependencies and request bytes
still decide replay. Its optional writer fails fast and cannot advance an
original project head. No canonical vector copy is added. Historical Work stored
by publication remains distinct from private retrieval-query memo data; this is
not a complete MCP persistence-policy implementation.

## Evidence

Final helper SHA-256:
`1c0cc81001b555f2cdc1531c47315c3d4ac6fc353049b60a97535b1b27859e7a`.

The [final normal-path check](checks.json) calls ordinary hook entry functions
with synthetic MCP-shaped notifications and uses real child workers and the
TCP publication service. It starts with four write owners and two reference
owners. Reference lexical/synapse/canonical indexes are prepared before lookup.
The [returned hook body](prompt-output.json) contains both required original JSON
values, including their quotes; finding the query text alone does not pass.

The reference project then publishes different original data. A fresh process
reopens the same captured views, retaining the first data and excluding the
later data. Pre/Post/Stop preserve that boundary. The normal save worker ACKs
the observation and binds the exact query images to its original publication.
Five other source journals import three event references each, without local
body chunks. Retry leaves the source head unchanged; missing/reordered captures
and shadow logical databases are rejected.

An additional small memo publication verifies one private project cache across
all four write owners, exact dependency replay and no leaked query in the work
graph. Original heads remain unchanged through query and native hook processing;
only original publication advances them.

| Entry | Single fixture, ms |
| --- | ---: |
| UserPromptSubmit | 331 |
| PreToolUse | 102 |
| PostToolUse | 69 |
| Stop | 19 |

The whole check took 8,336 ms, peak owned RSS 355,408 KiB, no guard limit or
surviving process. The [earlier complete check](preliminary-checks.json) is kept
separately; its helper predates the final proof/private-cache checks. These are
small component/integration figures, not p99, a speed comparison, a client ACK
from a live answering model, 98% evidence delivery or sustained capacity.

The same final helper reruns the existing
[80-session/16-owner source test](owners-80.json). All 80 original observations,
read-input bindings and the complete graph recover in a fresh process. It also
checks foreign read scope, complete owner inventory, descriptor corruption,
retries, new credentials and stop-after-ACK recovery. Peak simultaneous source
publications are 11. Whole-check time is 8,273 ms and RSS 368,800 KiB; its 897 ms
publication interval excludes ingress and uses repetitive 5 KB inputs. It does
not run 80 simultaneous normal hook lifecycles or derived preparation.

Ordinary ContractAudit is in the build. The
[additional Lean audit](proof-audit.txt) checks captured-image equality,
project/source completeness and owner-independent query-cache scope using only
standard axioms. It also rejects a DemandMemo publisher that directly bypasses
the private writer. It does not prove OS durability, arbitrary concurrent IO,
global writer ownership or a timing bound. Initial compile/fixture failures and
the two integration failures are retained as compact negative records.

## Reproduction and remaining gates

Apply [candidate.patch](candidate.patch) to `project-ingress-core` using
`git apply --unidiff-zero`. Copy the tracked `ProjectContextChecks.lean` into its
module path. Build `tools.research.ProjectContextChecks`; its root command runs
the normal-path check and `owners80 ROOT` reuses the parent source test. The patch
renames the parent's global entry point to avoid duplicate main definitions.
Run the separate tracked `ProjectContextProof.lean` against that build library.

The normal-path check explicitly reports **derivedPreparationQueued=false**:
the save worker still submits its index target using a logical project path.
Original publication is durable, but that preparation route is not connected.
This is the next integration task, together with project/scope shared canonical
vector preparation; creating one vector copy per physical owner is not a fix.

The later reference publication in this check is not re-warmed before the
remaining probes. Simultaneous replacement of prepared lexical/synapse/matrix/
router roots still needs a retained project read capability and its own test.
Cross-project transitive dependencies, complete cross-owner certification,
growing-data backlog, cache/page compaction, MCP policy, multi-host/NAS, 80-user
eight-hour load, p99 <= 30 seconds and 98% real required-evidence delivery remain
unvalidated. Keep these obligations; do not infer them by combining small tests.

Answering-model calls are zero and matched paid comparisons remain 0/18. No total
token improvement, answer-quality result, product adoption, README benchmark or
release follows. Ended DBs/caches/raw logs and the superseded helper are removed
after compact evidence is sealed, without archives. Current necessary source,
object, interface and link inputs remain; protected originals are rehashed.

The [cleanup record](cleanup.json) lists 322 removed entries, including six
ended fixture trees, their private caches, raw logs, generated C and the
superseded helper. No archive was created; protected inputs remain unchanged.
