# A request owns and retires its connection

This is an isolated transport foundation, **not integrated into ordinary
hooks or the project gateway**. The current parent remains `ea5b3861…`.
The current fourteen-client growth failure is not fixed by this component test.
Answering-model calls, project queries, token comparisons and adoption are zero.

The existing gateway subprocess is also a cancellation boundary. Simply
replacing it with a task would not establish native resource retirement:
the standard TCP writer retains its socket and buffers until its native write
callback completes. See the pinned [Lean 4.33 TCP implementation](https://raw.githubusercontent.com/leanprover/lean4/v4.33.0/src/runtime/uv/tcp.cpp).

The candidate keeps protocol, frame bounds, deadlines, cancellation checks and
scope cleanup in [Lean](../../../tools/research/request-socket/OwnedSocket.lean).
A [small C adapter](../../../tools/research/request-socket/socket.c) provides
nonblocking POSIX connect, poll, send, receive and close. There are no native
asynchronous callbacks holding requests. The sequential request task owns its
descriptor and closes it in `finally`; a canceller signals and joins that task.
The native handle is invalidated before close, so later use of an escaped
closed connection is refused. The adapter has a static callback table rather
than mutable global initialization, a once lock or per-connection class
registration. It uses the pinned public `lean.h` external-object ABI; it does
not patch Lean's private TCP structures. This adapter targets POSIX. Only
macOS has been compiled and tested here. It dials loopback only; authenticated
remote tunnels and actual multi-host deployment remain untested.

`withConnection` rejects a callback result if cancellation or its absolute
deadline occurred before return. No application mutex, CAS, shared request
queue, connection cache or gateway subprocess is added. This is a
single-owner caller contract, not a general linear type system: arbitrary
concurrent misuse of an aliased connection is not proved safe.

## Checked boundaries

The [kernel audit](proofs.json) checks five properties: the frame header,
decoder and frame limit equal the existing daemon definitions, valid ports
cannot truncate into another destination, and accepted native send counts
cannot advance beyond the owned buffer. Theorems use standard axioms only;
there is no `sorry`, `native_decide` or Z3. The 475-declaration action closure
reaches no process spawn, application mutex, shared reference, graph or DB.
This does not prove POSIX syscalls, the C adapter, OS scheduling, or all IO
interleavings correct.

The [native audit](native.json) checks 75 Lean objects; all [73 common
module sources](common-sources.json) match the fixed parent. The additional
module and fixture sources are checked against their native source witnesses.
The separately compiled [OS object](ffi.json) is hashed and linked exactly
once. The [run plan](run-plan.json) binds the executed native test binary and
OS object. This is a component closure, not a full product build.

## Native lifecycle results

The [actual results](checks.json) are from one guarded native execution.
With the fixture listener already running, sixteen independent connections
transfer 60,224 UTF-8 bytes in **13 ms**;
every returned byte matches its own original payload. The fixture splits
headers and payloads to exercise partial reads.

| Condition | Observed result |
| --- | --- |
| Mid-header EOF | Refused in 2 ms |
| Oversized header | Refused before payload allocation in 1 ms |
| Cancel while waiting for input | Task joined and peer observed close in 27 ms |
| Input deadline | Task joined and peer observed close in 85 ms after the observation point |
| Cancel while sending to a non-reading peer | Joined in 24 ms; peer received a partial 1,767,132 bytes and then terminated |
| Callback returns after deadline | Success refused; peer observed close |
| Escaped closed scope | Old handle refused; another live connection retained exact bytes |
| Invalid port | Refused before truncation |
| TCP descriptor census | 0 before and 0 after all joined operations |

The declared sixteen-client transport limit was ten seconds. These are
component timings, **not vector search, work-graph extraction, hook p99 or
98% evidence-delivery results**. The [guard](checks.guard.json) finishes
normally with no owned PIDs and a sampled related peak of 306,096 KiB, below
the unchanged 4,358,524 KiB stop and 5,000,000,000-byte user ceiling.

The initial C compiler could not locate the macOS SDK headers; the system SDK
compiler was then used without changing the source for that correction.
Fixture elaboration and an incomplete mapping for a custom link response also
failed before execution and were corrected. The mapped response uses the
parent's actual native manifest rather than filename guesses or duplicate
objects. [Terminal guards](guard-records.json) and separate refusals retain
these failures; no failed build is counted as a transport run.

## Remaining integration

The next step is a project-service route using this owner instead of a
per-query relay. The service must retain private grants and project policy;
clients receive only a delegated handle. Use the existing independent query,
source ACK, reply-reservation and cancellation machinery. A connection may
not alter its captured complete read cut or its configured write project.
Do not expose local administration secrets, raw private project capabilities,
or serialize independent queries through one gateway queue.

After that route is bound to ordinary scripts, repeat the same two-DB mixed
new/resumed/interrupted/restarted/growing workload, inspect actual delivered
bodies, and validate the LLVM seed and both topic passes under the existing
experiment contract. Cross-host authentication, NAS, MCP policy, sustained
80-user use, general 98% delivery, inclusive token reduction and quality remain
unfinished. The current source, native prototype and their required inputs
are retained for that integration; unused copied compiler cache is pruned
without an archive: [695 entries / 71,029,364 logical bytes](retired.json), with
[active input hashes](protected-native-inputs.json) checked before and after
deletion. The [remaining 75 native objects](socket-after-cleanup.json) and
[346-object parent](product-after-cleanup.json) remain consistent.
