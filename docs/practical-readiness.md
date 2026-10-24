# Practical readiness gates

The development candidate is not ready for ordinary MCP use or a paper pilot.
Unit tests and original-byte delivery receipts do not establish these gates, and
performance work remains isolated under the adoption conditions in AGENTS.md.

The latest user authorization permits a breaking redesign, with multiple DBs
and concurrent shared-DB use part of the core. See [the architecture decision](breaking-architecture.md).
Complete ranking equality remains a reference diagnostic for equivalent reader
changes; it is no longer an obligatory product invariant for intentional
recommendation changes. Original authority, scope, freshness, measured recall
differences and matched token/quality/deadline adoption remain required.
The [DB research decisions](db-research-decisions.md) fix the next candidate's
base/delta publication boundary, clustered routing and deferred original reads.
Routed query compensation remains unimplemented. The later deferred discovery
candidate suppresses inert owner reads, but complete Work reconstruction remains;
the paged component alone does not satisfy this target.
The [incremental projection component](incremental-projections.md) now retains
old numerical rows and writes only new/damaged projections with one atomic head.
Full-key validation still takes 9.3 seconds in that component's 10k audit.
The subsequent [source-delta preparation candidate](source-delta-warm.md) now
supplies only verified changed-owner keys during background numerical preparation;
deadline-only registration preserves readiness, and actual unavailable inputs
create private repair debt. Explicit warm still verifies the full source. Other
derived refreshes, owner loading and routed query coverage remain unfinished.
These are not native-hook or token qualification.

The [Work-only inference component](work-only-inference.md) proves the complete
fixed-pass Work/Union boundary. The [discovery integration](deferred-work-discovery.md)
now preserves quotient roots, later demands and original witnesses while
deferring inert Outcomes. In actual 10k hooks, owner reads fall to nine and the
body/ACK behavior agrees, but first/continued elapsed times are 18.9/17.2 seconds
versus reference 17.7/16.6 seconds. No speed gain or p99 is established. All Work
views and numerical rows are still acquired. This is not a token cohort or 50k
qualification; the candidate remains unadopted.

The later [admission-policy index](admission-policy-index.md) replaces repeated
classification-list scans with an extensionally equal exact lookup. It does not
remove original Work loading. Controlled retrieval-only time falls from about
35.3 to 30.3 seconds; the normal native hook remains about 18.6/17.3 seconds with
identical stdout/ACK behavior. One pair per arm establishes no p99 or token gain.
A separate processing-thread sample identifies quadratic `projectMatches`
membership/append work as the next target. Persistent canonical recognition,
routing, privacy and full scale qualification remain unfinished.

The [stable projection fold](projection-fold.md) now replaces that repeated
membership/append work with an exact set and one append, preserving the full
graph list. All 36 controlled cases and native stdout/ACK behavior agree.
Local-Union-disabled discovery falls from about 28.3 to 23.0 seconds in its
current cohort; ordinary discovery remains about 9.2 seconds. Native first/
continued are 17.8/16.5 seconds in one pair, not a p99 or token adoption result.
Complete original Work restoration and numerical acquisition remain the next
architecture targets; do not enlarge the fixture instead of changing them.

## Priority and current evidence

The subsequent [Work-class query](work-class-lookup.md) composes rootless
generated equality with original Work-owner buckets. Lean proves its ordered
selection agrees with the full corpus-rooted equality filter. All 120 original
source probes agree at 10k/50k; positive medians are about 25/29 ms for one owner.
Thirteen small checks cover mixed congruence and two pinned DBs. This is not
normal discovery, p99, token or 50k hook qualification. The remaining controller
mixes structural recognition with partial-text inference; that producer boundary
must change before this query can replace all-Work admission. Do not disguise
equality as textual Coverage.

1. Remove repeated catalogue construction from hooks. The isolated single-source
   path now shares a prepared domain for catalogue, Work/native views and numeric
   topology; original owner validation remains on admission. Cold fallback still
   invokes `Store.searchDocuments`. Multi-source preparation still builds the
   complete cross-DB identity table over semantic membership. The small/real-DB
   stage checks in [the candidate record](prepared-candidate-domain.md) do not
   qualify that multi-source path. Actual native 10,000-window hooks now take
   18–20 seconds: all 9,969 owners still pass Work admission and are hydrated.
   See [the measured breakdown](native-hook-scale.md). The 30-second practical
   gate remains unqualified at 50,000 windows: the measured reference returns
   only an incomplete notice there.
2. Close storage privacy before live MCP trials. `captureTerminal` persists the
   raw result before manager dispatch. `postToolUse` and operation graph
   compilation subsequently use the pending turn's single write target. No
   trusted MCP/server descriptor, per-server admission policy or credential
   exclusion currently precedes every durable path. Private usage-index tests
   do not establish private capture of MCP observations.
3. Measure the complete latest hook at scale, including candidate loading,
   numeric setup/scoring, postings, admission, source checks, packing, commit and
   stdout. Earlier implementations did run 50,000-window hooks and timed out;
   the latest native-observation candidate has no qualified 50,000-window result.
4. Only after these pass: live-server lifecycle, daily growth, then one week of
   ordinary use and receipts. Paper comparisons follow practical qualification.

## Prepared candidate domain

Build the complete ordered owner/Work/window/topology domain during publication
maintenance or explicit/background warm. Target a paged, bounded-record directory
and an atomic readiness record tied to source changes and the actual implementation
bytes. A derived-only memo publication must not force a complete rebuild.
Retraction, replacement and a different DB incarnation must invalidate it.
Read-only shared DBs use the private DB-identity overlay.

A hook opens and verifies the domain once and shares it between discovery,
focus and fallback. It does not repair it, reopen a current head, enumerate all
owners or decode all Work/Outcome payloads. Lexical nominations come from
postings and retain original stable order. The full numerical scan remains a
reference. A routed candidate records differences and required-evidence misses,
with a separate branch for eligible prepared additions since its index boundary.
Only admitted owners and delivered original ranges
are hydrated from the pinned source. Cached nomination metadata cannot replace
an original owner or confer Exact/Union authority.

Before model calls, compare candidates, Work/native views, topology, rankings
and delivered bytes against the fixed-snapshot reference path. Equivalent reader
changes require equality; intentional routing changes report their differences.
Do not equate a stale routing index with a complete search of recent additions. Record
corrupt/partial/stale/read-only cases and actual DB read observations. A fast
open microbenchmark is not a full-hook latency result.

## Latency protocol

The user-confirmed practical gate is UserPromptSubmit p99 < 30 seconds on a
warmed 50,000-window DB, separately for new chats and chats with acknowledged
history. Faster remains preferable; the previous 3-second target was an
aspiration, not a user requirement. Time includes startup, stdin/stdout and
receipt confirmation at the caller boundary. An incomplete notice alone is
not useful delivery, even when it flushes in 29 seconds. A continuation can
correctly return no new body when the original is already acknowledged.

50k is the first regression point, not a maximum supported lifetime corpus.
Collaborative investigation across large repositories and revisions can exceed
one million windows. Follow the [growing shared-history plan](growing-shared-history.md)
for paged storage, multiple DBs and larger measurements. Neither unrestricted
30-second full scans nor million-window readiness has been established.

Before the next qualification cohort, freeze 100 attempts per category at 2,
1,024, 10,000 and 50,000 windows and a fixed real DB. Freeze runtime SHA, source
snapshot, questions, provider, cache state and harness before measurement.
Report nearest-rank sample p99, `ceil(0.99 * n)`, p50 and maximum, with every
attempt retained. This empirical percentile does not establish a population
p99 guarantee. Every timeout, incomplete search and missing useful delivery is
also a failure; a percentile cannot hide it. Report semantic completion
separately from usable lexical fallback. Existing diagnostic pairs do not
qualify this cohort.

Measure scaling rather than demand constant time on doubling. Full ordered
matrix scoring retains O(N*d); repeated catalogue construction and per-owner
IO are the avoidable costs. Do not extrapolate a timeout boundary from two DB
sizes as an established limit. Record actual deadline margin at each scale.

PreToolUse and PostToolUse are separate strata: record caller durations, p50,
sample p99, maximum, count and summed per-turn handler cost. Sum is not elapsed
turn wall time when calls overlap. Record semantic-enabled/projection/evidence
conditions; a test with search disabled cannot qualify search latency. The
existing seed's 144 Pre/Post handlers sum to 292,801 ms, despite each finishing
within 3,877 ms. This older, initially empty DB is evidence of cumulative cost,
not qualification of the latest runtime at 50,000 windows.

Separate explicit cold-import/warm duration from warmed new-chat hooks. Record
stage timings, read counts, payload bytes, peak aggregate RSS and free disk.
Keep all experimental processes together under 4 GiB; the existing guard stops
at 3.5 GiB. Generate scale fixtures in bounded publication batches and avoid
retaining obsolete complete DB copies.

## MCP capture policy

The implementation target is a private-constructor, policy-checked capture
value accepted by every Eggshell durable writer. Enumerate terminal capture,
Pre/Post journals, pending/recovery records, observations and answers, receipt
bodies, vector/lexical/synaptic sidecars and Eggshell stderr logs. Apply policy
before the first journal write. A ContractAudit-style dependency check must
verify that raw tool events cannot reach these sinks without that boundary;
secret-sentinel artifact scans separately test actual IO behavior. Neither
test alone substitutes for the other.

The target default is private storage for external observations. Unknown origin
is private as well. Identify server/account/tenant from trusted adapter metadata;
do not infer storage authority from a tool-name prefix, shell spelling, a file
certificate or response text. Allow/deny configuration is per trusted server
identity. Explicit sharing is separate from recording permission.

Apply the policy before terminal capture, live journals, recovery snapshots,
checkpoints and answer publication. A final answer can quote a private result,
so routing only the raw MCP result is insufficient. Preserve that dependency or
conservatively keep the entire affected turn private.

Credential-bearing arguments are excluded before any durable write. If the
actual operation cannot be retained without credentials, omit that observation
and record a content-free reason; never substitute redacted arguments as if
they were the executed Exact Work. Tests must scan all durable artifacts for
secret sentinels and prove that private results and derived answers are absent
from the shared DB, not merely absent from a derived usage index.

## Changing locations and storage growth

Index a stable resource locator separately from exact observed content. Scope
it by server, principal/tenant and resource identity. A new observation at the
same location retains history and links versions for recommendation; it does
not unify old/new bytes or certify old state as current. Preserve acquisition
time and invalidation metadata. The 30-day age hint alone grants no completion.

Before live use, set and record explicit storage budgets for queued capture,
individual observations and retained private history. On budget exhaustion,
record an omission without corrupting an already captured original or claiming
an incomplete result was complete. Measure bytes and windows added, duplicates,
compaction amplification and cleanup after a representative day, including
large JSON results. Choose defaults from that measurement; no daily growth
limit has yet been validated.

Capacity policy separates hot recommendation indexes, cold retained originals,
and explicit deletion. Lack of delivery or rereading is not evidence that a
memory is dispensable. Cold records remain addressable by Exact identity and
provenance even when they leave semantic/lexical recommendation. A tombstone
can preserve an identity and explain unavailable evidence, but cannot count as
available original bytes or pass completion checks that need those bytes.
Compaction of historical copy-on-write pages is a separate bounded operation
which preserves pinned readers; fixture transaction batching does not implement
it. Do not silently create another unbounded archive.

## Recognition index and matrix follow-up

Keep full-population numerical scoring while removing per-window files and
transporting packed float32 model outputs. This remains O(N*d), plus work on
the nominated neighborhood; it is not O(K log N) overall. Preserve model,
segmentation, accumulation, thresholds, stable ties and complete owner/window
rankings. Float32 packing alone does not prove ranking or score equality.
Measure first mapping, resident reuse, invalidation and ownership within the
aggregate memory ceiling. No packed numerical matrix is qualified yet.

The isolated [binary64 row-matrix candidate](prepared-vector-matrix.md) now
checks all 19,969/99,969 discovery and focus keys at 10k/50k against the original
projected bits and coverage. Complete numerical provider outputs agree; the
single 50k provider pair is 28,844/19,127 ms. This is not float32/mmap scoring,
full-hook p99, matched token improvement or adoption. Original raw files remain
for maintenance/recovery, and full Work admission/owner hydration remains.

An authority index can separately store scoped canonical Work signatures and
class use lists at publication time. A congruence step requires equal operators,
ordered argument roles, identical Exact references and equivalent Semantic
references. Explicit persistent Unions can connect different signatures, so
signature matching alone is not the complete authority index. After local
Unions, revisit every affected parent through the complete use lists, including
parents outside recommendation top-K. Class identifiers and prepared readiness
belong to a pinned DB incarnation and Union state. Prove the indexed closure
and recognition results equal to the full reference closure, rather than only
showing returned matches are sound.

Broad intrinsic Work alignment is also used for advice in the current matcher;
a congruence index by itself does not eliminate that admission path. The actual
10k measurements must therefore remain the performance baseline until the
whole hook improves. Local changes can affect many parents; do not assume a
small number of local Unions implies a fixed small rebuild cost.

Freshness shortcuts retain fingerprint verification and reject ambiguous file
metadata; matching mtime/size alone is insufficient. External observations
without a supported current-state verifier remain historical advice. A later
sampled shadow check may run only a typed, explicitly permitted read operation,
not arbitrary stored shell text classified by a command-name prefix. Report
the sampled denominator and disagreement count; a sample with no disagreement
is not a proof that all completed reuse is correct.

## Live acceptance and later token adoption

Use an actual read-only MCP server with a real Codex session only after capture
privacy passes. Exercise Pre/Post/Stop, interruption/retry, new-chat warm reuse,
resource mutation and principal changes. Record one day first, then one week.
No such live trial has passed yet. Zero observed false completed reuse requires
changed-state and changed-invocation controls with an explicit denominator.

Practical gates do not replace token adoption: compare the same saved snapshot,
source, questions, model, reasoning and harness for topics 1/2/3, first and
history-bearing use, using predefined equal repetitions. Count input plus
output, cached input and failed attempts; separate seed cost. Preserve quality,
delivery receipts and deadlines. Do not adopt a candidate on latency, tests,
proofs, delivery size or the best single token result alone.
