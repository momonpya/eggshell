# Isolated project service gateway

This candidate adds a client/server process boundary for project publication
and complete read-cut pinning. The native product is
`e7f3c8b69da8429b69514a43dbc9ee3607743a01fa596502270cbde0e8b71fe7`;
its parent is `5d37ec14…`. It remains isolated and unadopted. The normal product,
global installation, encoder, recommendation, certification and delivery prompt
are unchanged.

The host owns a catalog of project names, directories and read/write grants.
Each connection selects its readable projects and at most one writable project.
The public descriptor contains complete immutable owner inventories, without
host directories, administration secrets or private capabilities. The client
uses a bounded framed process channel; deployment must authenticate that channel.
The candidate does not expose the existing local administrator socket remotely.

Read pinning uses read registration and never acquires a source writer. A
publication includes the captured write-project identity and the complete cuts
of all selected read projects. The host rejects a changed destination, missing
project, foreign inventory or changed scope. The existing source ACK and exact
replay check are reused. The peer owns only its channel; closing or timing out
that channel does not start, stop or kill the shared publisher. Each concurrent
caller has an independent connection and request task. Arbitrary concurrent use
of one peer is not claimed to be linear or verified.

## Native validation

The [Lean fixture](../../../tools/research/GatewayChecks.lean) launches a separate
publisher and gateway processes. Both DBs have two storage owners. Original
tool input/output comes from actual `printf` calls, with over 5,000 UTF-8 bytes
per observation and actual monotonic intervals. The client workspace is deleted
before publication; publishing does not require that path to exist on the host.

| Check | Result |
| --- | --- |
| Ten concurrent clients publishing to two DBs | 0.416 seconds for the whole gate |
| Complete original input/output in its captured project | 12/12 observations |
| Original final answers | 12/12, correct project |
| Exact retry, then publisher restart and retry | Original heads unchanged |
| Disconnect after durable source ACK, before reply | Durable once; reconnect/retry adds nothing |
| Read-only client and raw read-only request | Publication rejected |
| SDK destination/cut/scope changes and denied catalog entry | Rejected; original heads unchanged |
| Wrong reply identity/protocol, invalid UTF-8, truncated/oversized reply | Rejected, 105–108 ms including child cleanup |
| Peer stops responding | Deadline cancels and joins child/tasks, 305 ms |
| Oversized, truncated and invalid-UTF-8 native requests | No accepted reply or source changes |

The complete native fixture takes 9.699 seconds, including setup, source checks,
restart, adverse cases and shutdown. This is not a search or hook latency.
Sampled related RSS peaks at 784,224 KiB; no resource guard triggers. Both
publisher instances exit normally, and all owned processes are drained. Fixture
stdout/stderr are empty. The [result](result.json), [original inventory](concurrent-originals.json),
[adverse-peer timings](adversarial.json) and [guards](guards.json) retain the evidence.

The 338-object product closure is consistent. The 299-object native observer
contains the complete product core and 298 byte-identical imported sources.
The only four changed existing product sources are ProjectPublication,
PublicationClient, PublicationService and Main; the two added modules are
ProjectGateway and ProjectGatewayPeer. PublicationWire's embedded literals match
the actual changed source bytes.

Five [Lean laws and a dependency audit](../../../tools/research/GatewayAudit.lean)
pass using only standard axioms. The host execution path is checked to use the
scope/destination/ACK guards. The client-only transitive closure of 1,462
declarations reaches neither project file reads nor mutex `atomically`.
These are scoped checks, not a proof of arbitrary IO scheduling or deployments.

## Remaining work

This is a local native process-channel test, not SSH, another OS user, a remote
machine, SMB/NFS or sustained 80-user operation. Only publication and complete
read pinning are connected here. Remote original retrieval, vector/work-graph
search and normal hook configuration still need this boundary. Per-project
cuts do not establish a new atomic cross-project global snapshot guarantee.

The LLVM seed → topics 1/2/3 → second pass, quality, and repeated matched inclusive
token comparisons remain outstanding for this candidate. No answering-model call
runs; adoption remains zero. The process-channel result does not prove general
98% evidence delivery or the 30-second requirement at production scale.

The first uncertain build was deleted and rebuilt from the known parent.
Compiler rejections retain their diagnostics and source digests, without keeping
obsolete source copies. Ended fixture DBs, caches and duplicate native observer
artifacts were deleted without archive: 2,357 entries, 568,381,141 logical bytes.
The current isolated product, protected originals and native/model inputs remain
unchanged; the 338-object product closure passes again after cleanup.
