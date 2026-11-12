# Shared-project reads through ordinary hooks

Isolated product `7bc72da7ca0be0507aabe6401f3a50b52b1fecb5a6515c179294a6b0bed163d1`
connects the [shared-query service](../project-read-service/README.md) to the
registered ordinary hooks. It is **unadopted**; the global installation and
README benchmark claims are unchanged. No answering-model run is made.

## Behavior

A user-owned profile can specify `read_service` as an executable/argument array.
Its existing `read` list then names projects in the host catalog, rather than
client filesystem paths. This read-only entry rejects a simultaneous `write`;
remote publication through the gateway exists separately and is not yet wired
to ordinary saving hooks. Repository configuration cannot execute this command.
Host policy must fit the client profile's character allowance. `egg doctor`
reports the remote names and read-only mode. An unqualified `egg warm` points
to the data host instead of pretending to warm an empty local read list.

UserPromptSubmit captures the immutable descriptor and complete project/owner
cut before searching. Network capture runs outside the session-state critical
section; its result is committed only if the turn and epoch are still current.
Search validates the same descriptor and cut. It uses the existing data-side
vector, e-class/work graph, synaptic traversal and original rendering.

The actual subtractable delivery packet accompanies the body. The adapter
rejects a packet whose rendering differs from that body, and passes it through
the existing bounded reconciliation, offer and client-ACK flow. It does not
invent an acknowledged projection from plain text. Replies carry actual search
status even when no new body is needed.

Remote advice has no current-Work completion authority: completion, blocking
and local unions are always zero/false. Client-native freshness and certified
operation reuse remain separate. Enforced tool searches do not stop a native
operation using remote advice.

Capture and query reuse the existing request-local cancellation registry.
Only short registration/removal sections hold its metadata mutex; the network
request runs outside it. Each connection owns its process group and pipe tasks.
There is no new shared search queue or mutex around query execution.

## Native evidence

The [Lean fixture](../../../tools/research/ProjectHookReadChecks.lean) first
acquires six native observations and two final answers through ordinary hooks,
in two project DBs with two owners each. Four original code fields are frozen
from the DB before delivery. One explicit warm completes; source files are
then deleted. Thirteen direct service queries pass on this exact product,
including ten simultaneous connections completing in 0.506 seconds.

After those services stop, the normal-hook phase starts a new publisher with
an initially empty host data root and a separate initially empty client data
root. It performs no additional manual warm or source acquisition.

| Ten-client ordinary-hook workload | Whole start/prompt/stop gate |
| --- | ---: |
| Fresh sessions | 4.068 s |
| Existing sessions with resume events | 2.412 s |
| Four resumed, three cleared and three compacted sessions | 2.440 s |

All thirty queries contain the required originals in their actual visible
context: **78/78 repeated appearances of four unique fields**. Forty-four
appearances are in new callback bodies; the rest are already confirmed text
retained by continuing contexts. Clear/compact cases must receive the originals
again. Checks require each field inside its own SOURCE path/fingerprint's CODE
block, exclude other projects' fields from single-project readers, and verify
that original DB heads and files do not change.

Every successful normal-hook prompt has a captured remote frame, no local
project/input boundary, an empty pending-offer list after native ACK, and a
confirmed delivery projection. Actual callback stdout is retained and checked
against the recorded body. The largest hook body is 9,361 UTF-8 bytes. The
fixture allowance is 500,000 characters; this is not the public default and is
not a token-reduction measurement.

An actual connected process that withholds its reply is cancelled and joined
in 5 ms in the initial phase and 7 ms in the final phase; no captured scope is
returned. This checks cancellation during pinning, not interruption at every
point in a long query. All 114 successful acquisition/source/hook commands
have exit zero and empty stderr. The normal-hook service retains the existing
MiniLM pooling warning; model and numerical runtime files are unchanged.

Related sampled RSS peaks at 2,937,584 KiB in the normal-hook phase. Successful
guards are terminal, untriggered and have no owned process remaining. Services
stop normally. Five laws use standard axioms only, and the real adapter's
1,358-declaration dependency closure contains no local project-file reads.
The 341-object product and 319-object observer are audited separately against
the exact common product sources. These are scoped checks, not proofs of
arbitrary IO scheduling or production p99.

The actual native `egg doctor` reports ALPHA as a remote read-only project,
with no local DB list. The actual unqualified `egg warm` rejects this client
profile with the data-host preparation instruction. A metadata-launcher import
failure is retained separately. The refactored legacy test entry also passes
the established native build under the unchanged aggregate resource guard;
its smaller interpreted typecheck had exceeded that compiler's 768 MiB heap.

The first combined fixture fails before normal-hook callbacks because the
test recorder omits its parent directory. Its already completed direct-query
and cancellation checks remain component results; the whole fixture remains
a failure. The corrected observer resumes the same unchanged DBs in new
service/client roots. Earlier compiler and proof-name failures are retained.
The shared read fixture is extracted into a library so importing its CLI
`main` cannot collide with another native test entry. No product behavior is
changed by that test refactoring.

Ended fixture DBs, caches, native-observer copies and unused installation
helpers are deleted without archive: **6,420 entries / 924,844,131 logical
bytes**. Protected originals and current source/runtime/model/native inputs
remain unchanged. The 341-object product passes again after deletion.

See [summary](summary.json), [actual normal-hook bodies/state](hooks-checked-results.json),
[native calls](native-calls.json), [required originals](required-before-delivery.json),
[guards](guards.json), [proof audit](proofs.json) and [patch](candidate.patch).

## Outstanding

These are scripted native hook events on one Mac/OS user, not actual Codex UI
chats or authenticated connections from another machine. Resume events are
tested, but pausing a real chat during a running query and resuming across a
publisher restart is not covered. Concurrent remote saving plus these hooks,
remote certified matching, NAS semantics, larger/growing DBs, sustained
80-user workloads and general 98% evidence delivery remain unverified.
The LLVM accepted seed, both passes of topics 1/2/3, repeated inclusive-token
and quality comparisons remain outstanding; adoption is zero.
