# Independently owned originals inside one project

Isolated storage/publication candidate, not adopted and not an ordinary-hook
integration. The [plan](plan.json) preserves the 80-user, 30-second, 98% actual
delivery objective and the separate matched token/quality/deadline adoption gate.

One project has an immutable, complete inventory of source-owner regions.
Regions are internal service work partitions, not personal DBs or projects.
Each owns a separate original PageMap incarnation. Their physical identities
are unique and differ from the logical project identity; their graph authority
and logical publication destination remain the project. Copying the logical
identity into multiple PageMaps is explicitly rejected.

The owner publishes its originals, native source receipts, dependency frontier
and previous-head binding in the same PageMap transaction. Different owners do
not replace a common original head. Exact previous-head bindings have immutable
revision keys, including the root digest. Lookup is a point operation rather
than a walk of every previous publication. `PublicationHistory.Trace.index_exact`
proves the append rule's point table contains exactly the earlier trace heads;
`lookup_canonical` connects a returned head to `SourceDelta.Lineage`. The native
tests compare every actual indexed history entry with the existing publication
chain walk. This is not a complete proof of the IO-to-index refinement.

`openView` accepts the entire independently requested original cut or rejects it.
Missing owners, foreign scopes, same-revision forks and omitted dependencies
are errors. `pin` collects originals and closes their recorded dependencies
before declaring the query cut. Closure lifts only to a required historical
head, not an index's ready root. An old explicit cut remains old. No warm-state
or top-K filter can reduce the source inventory.

The owner lease spans its loop. An owner-local lifecycle gate rejects concurrent
use or use after release; scope exit drains an already admitted operation before
unlocking. This uses a short local `Std.Mutex` and an OS lease. Existing per-source
PageMap/persistence guards also remain. It is not a lock-free IO or linear-type
claim; remote failover, arbitrary external file replacement and writable forks
are not established by this local protocol. Shared use still requires the
data-side service and scoped admission.

The updated [design model](../../../tools/research/OwnedPublicationModel.lean)
now distinguishes a registered physical original from its logical project.
Its previous placeholder equality between those identities did not describe
physical partitioning. Existing closed-view join and completeness laws remain
kernel checked, without changing the goal or treating this as runtime certification.

Native [results](report.json), with one concurrent source-view reader:

| Logical producer clients | Native owner threads | Original ACKs | Publication elapsed | Complete concurrent views |
| --- | --- | --- | --- | --- |
| 10 | 16 | 40/40 | 698 ms | 11 |
| 40 | 16 | 160/160 | 1,659 ms | 18 |
| 80 | 16 | 320/320 | 2,802 ms | 27 |

Clients here are controlled producer labels dispatched to owner threads, not
80 network connections or full Pre/Post/Stop sessions. The producer writes
synthetic native start/finish journal records; the normal native compiler and
publisher create the stored original graphs and complete source receipts.
No real MCP server, answering model, vector search, synaptic preparation or
delivery selector ran. Elapsed times include owner startup, journal production,
preparation and grouped publication; the full original census is outside that
timing. There is no p99, sustained-load, token or delivery-recall claim here.

All ACKed original observations were present, and complete federated graph roots
equaled an independently materialized union: 160/640/1,280 unique roots in the
three loads. A stronger census also reconstructs every expected client/round
input and output, rejects duplicate or foreign occurrences, checks exact saved
bytes and verifies that receipt destinations remain the logical project path.
Boundary tests reject an omitted cross-owner dependency, close a
collected cut to that exact dependency, retain historical cuts, reject forks and
foreign/missing owners, reject escaped owner capabilities, and retain the lease
until an in-flight operation drains. The original process then exited. A
[separate process](reopen.json), using a fresh private data root, reopened all
four projects and repeated the original census, ancestry comparison and graph
union checks. This does not test persistent cross-owner Union edges or prove
the complete certification-index refinement.

The full native run used 194,640 KiB sampled aggregate RSS; fresh-process reopen
used 114,288 KiB. Both guards exited normally with no owned survivors. The
[resource record](resources.json) also retains build failures. The ordinary
`ContractAudit` and revised ownership model were included in the native build.

Before product integration, the broker must grant project-scoped owner routes,
pass policy-approved observations to their physical journals, and use this
complete original cut for every query. Cache content stays project-owned:
one canonical vector/content store per permission scope, with owner-local
postings and dependency roots; it must not duplicate the model/vector payload
per session or owner. Index completion and preparation debt must cover the same
cut. Ordinary hooks/CLI, complete cross-region certification, shared preparation,
copy/failover/compaction, million-plus-window growth, actual LLVM six-stage
delivery, sustained 80-user mixed work and matched token/quality trials remain.
Matched token comparisons are 0/18; product and README results are unchanged.

## Output-byte workload and the remaining write cost

The user-specified 5–50 KB output range was measured rather than extrapolated
from short strings. The initial 80-client/320-observation runs took 4,738 ms
at 5,000 bytes and 30,271 ms at 50,000 bytes, with every original checked.
Those times included fixture output generation. Separating generation showed
181 ms for generation and 29,445 ms for the 50 KB journal/prepare/publication
path. [This result](ingress-50000.json) rules out fixture generation as the main
cause. The [profiled run](profile-50000.json) is diagnostic, not a timing arm.
Its [hot leaf excerpt](profile-hot-leaves.txt) shows repeated `PageMap.route`
and list allocation; [the raw sample digest](profile-sample-sha256.txt) remains
after deleting the raw sample.

`Writer.putManyAt` previously filtered the whole edit list once for each child,
rerunning the whole route scan for every child/edit pair. The isolated
[routing change](write-routing.patch) assigns every edit once to stable buckets.
`EditRouting.selected_exact` proves each bucket, including row order, equals
the former reference filter for every directory/edit list. No sorted-directory
assumption, top-K bound, body truncation, cache timeout or format change enters
this equality. Ordinary `ContractAudit` and the complete owner/boundary tests
passed with the change.

The [predeclared comparison](write-routing-plan.json) uses the same project
manifest, original head/page bytes, logical destination path and generated
inputs before each arm. One frozen boot copy is restored before every arm;
SHA-256 covers every initial file. Arm order alternates, three repetitions per
size. Fixture generation is forced outside the journal/prepare/publication
timer. Every arm performs the exact byte/provenance, ancestry and graph census.

| Bytes per observation | Parent, three runs (ms) | Routed candidate, three runs (ms) |
| --- | --- | --- |
| 5,000 | 4,934 / 4,877 / 4,940 | 3,913 / 3,931 / 3,942 |
| 50,000 | 30,637 / 30,594 / 35,227 | 15,970 / 15,301 / 18,796 |

All [twelve arms](write-routing-comparison.json) passed 320 original observations
and the independent 1,280-root graph census. No answering model ran. At 50 KB,
the candidate corresponds to about 17–21 observations/s in this synthetic
profile, including private journal production. The user's maximum assumed
640,000 calls over an eight-hour day is about 22.2/s before numerical/index
preparation. Therefore this is progress, not proof of sufficient sustained
ingestion capacity. The measured time is also not full-hook latency or p99.
The shared broker/cache integration and the unchanged token adoption gate remain.

Ended native fixtures, their DBs/private caches, the comparison's frozen boot
copy, old helper executable, raw sample and compiler logs were
[deleted](cleanup.json). No archive was created. The current routed prototype
helper, original/control inputs, source, native objects/interfaces and link
responses remain. Protected digests were unchanged. Deleted DBs can no longer
be inspected directly; their construction, measured results and source seals
are recorded. Apply `candidate.patch` to the owned-ready parent core and then
`write-routing.patch` for the routed variant, using `git apply --unidiff-zero`.
