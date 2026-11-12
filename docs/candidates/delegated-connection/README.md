# Ordinary project hooks without a per-request relay

This isolated candidate connects the [request-owned socket](../request-socket/README.md)
to the existing project service and ordinary registered hooks. Backend SHA-256:
`6ece69c62bb845d7c955a681450fe873f58b75c6e208bc28ede708b47d6e70ed`.
The fixed comparison parent remains `ea5b3861…`. Neither the main implementation
nor the global installation is changed; adoption and paid token comparisons remain zero.

## Prepare authority once, execute requests independently

The service loads its private `publisher/project-access.json` at startup. It
registers each project once and compiles the configured read/write selections
into immutable private scopes. It publishes separate connection files containing
only protocol identity, the two loopback ports, and a token for one fixed scope.
Administration secrets, physical paths and original registration capabilities
remain on the host. Restart registers the projects again and atomically refreshes
the exported connection files; an old captured complete cut can still be replayed.
Catalog changes currently require a controlled service restart.
Current admission bounds are 64 catalog projects and 256 delegated scopes;
these limits and long-running catalog management still need scale validation.

The user-owned configuration selects an explicit connection file, for example:

```toml
[profiles.work]
project_service = "/absolute/path/project.connection.json"
read = ["ALPHA", "BETA"]
write = "ALPHA"
```

The host's token must permit that exact selection. Other selected projects are
read inputs. A pending turn retains its original writer and full read boundary
when the current project changes. The existing operator-authenticated process
transport remains an explicit alternative. There is no automatic transport fallback.

One direct RPC owns one socket and cancellable task. Independent queries run
independently; no gateway subprocess, new application mutex, or shared gateway
queue is introduced. The existing service retains source ACKs, admission limits,
reply reservations, stream checks, query readers, and background preparation.
The server watches a direct caller's connection and cancels and joins its work
when that caller leaves. Recommendation, certification, matching, extraction,
ranking, three advisory edge types, and the original database formats are unchanged.

## Authority, cancellation and build checks

[Native authority checks](checks.json) publish eleven complete observations and
eleven answers into their selected projects. Ten simultaneous writers finish
their source ACKs in **365 ms**. The checks also cover exact retry, an actual
publisher restart with the old cut and identical ACK, eight raw forbidden
requests, immutable selection, and a denied project that is never opened.
The eight raw cases include another write target, an omitted project, another
scope, another host policy, the wrong listener, a read-only publication, an
unknown delegated token, and attempted administration with a delegated token.

A real cold project pin is interrupted: the client joins in **12 ms**, and the
service's established connection census returns to zero in **25 ms**. Both
publisher exits are normal. The [guard](checks.guard.json) finishes with no owned
PIDs and a sampled related peak of 1,757,280 KiB. One broken-pipe service warning
was observed during these intentional rejection/disconnect cases; this is not
claimed as an all-stderr-empty hook workload.

The [kernel audit](proofs.json) checks six laws with standard axioms only. Its
copied original pin/execute bodies are bound to the fixed parent's actual source.
The old operation and the shared executor agree for every operation, including
the existing target, read-only and complete-boundary checks. The direct client's
1,308-declaration effect closure reaches no process spawn, application mutex,
project ownership or source DB IO; immutable DB key types are permitted.
This is not a proof of arbitrary IO aliases, C, POSIX or scheduling.

The [347-object product](native.json) has exactly the declared seven changed
modules plus the socket module, including all embedded source inputs.
[Source comparison](sources-checked.json) approves the actual OS source as well.
The [328-object mixed observer](mixed-native.json) contains all product core and
[324 unchanged common sources](mixed-sources.json). The unchanged small supervisor
shares [all ten product module sources](small-client-sources.json) it imports.
The [304-object authority observer](checks-native.json) has a separate component
comparison, not a claim to include the full product closure.

Initial fixture and meta-audit errors were corrected before their successful
executions. Failed guards and refusals remain recorded; they are not successful
runs. No answering model was invoked.

## The previously failing fourteen-client growth workload

The [predeclared workload](growth-plan.json) keeps the previous lifecycle,
storage and delivery oracle. Its [fixture patch](mixed-transport.patch) changes
transport configuration and the observer entrypoint. It starts with two empty
logical project DBs, four physical owners per DB, and four writer sessions whose
writes concentrate on the same owner. It mixes fresh, existing, resumed, cleared
and compacted contexts, two interrupted writers, a real three-service restart,
late and duplicate Post/Stop events, a project switch, and four growth waves.
No manual `keep` or `warm` command runs.

| Completed gated phase | Clients | Time |
| --- | ---: | ---: |
| Initial readers | 4 | 1.001 s |
| Concurrent writers/readers | 4 + 8 | 1.580 s |
| Restarted lifecycle mixture | 10 | 1.514 s |
| Growth wave 1 | 4 + 10 | 2.049 s |
| Growth wave 2 | 4 + 10 | 2.311 s |
| Growth wave 3 | 4 + 10 | 2.431 s |
| Growth wave 4 | 4 + 10 | 2.715 s |
| Final readers | 10 | 2.201 s |

Reader gates include the prompt and Stop; their preceding SessionStart is
outside the gate. All actual hooks, including starts, are audited separately.
The [independent reconstruction](summary.json) checks actual callback bodies and
lifecycle resets: **72/72** semantic queries and **1,476/1,476** required original
appearances. Of these, 390 are in new bodies and 1,086 in previously delivered
visible context; 110 appearances are in fresh contexts. The final frozen inventory
contains **50 distinct required source/fingerprint/text items**, all present in
the independently checked final queries. Maximum actual body is 26,324 UTF-8 bytes.
This remains the existing 500,000-character small fixture, not the public default.

All **504 commands / 429 hooks** return zero with empty stderr and no incomplete
notice. Maximum hook time is **2.292 seconds**. The [original guard](growth.guard.json)
finishes normally with no owned PIDs and a sampled related peak of
**3,490,224 KiB (~3.33 GiB)**. The 4,358,524 KiB protective stop and the user's
5,000,000,000-byte ceiling are unchanged. All services stop normally.
This run succeeds as a whole; the parent's fourth-wave failure remains a failure.

The [read-only native inventory](storage-summary.json) verifies **75 observations,
25 answers and 50 stored fields**, with original publication files unchanged.
Four interrupted observations retain unknown timing; 71 have verified intervals.
The reused raw postmortem's `originalRunPassed=false` is a legacy constant, not
a run-status measurement. Actual run status comes from the original guard and
independent summary. [Raw callbacks and stages](growth-records.json) retain the evidence.

## Cleanup and remaining work

Ended DBs, session caches, helper builds, unused copied compiler objects and
generated C files were deleted: [13,397 entries / 839,811,413 logical bytes](retired.json),
without an archive. The candidate source/backend/prefix, shared model, fixed
parent/supervisor and protected LLVM original remain. All protected native input
hashes still match. After deletion, the [candidate's 347 objects](candidate-after-cleanup.json),
[parent's 346](parent-after-cleanup.json), and [client's eleven](client-after-cleanup.json)
remain consistent.

This demonstrates the declared local mixed workload. Sustained 80-person use,
large growing databases, general 98% necessary-evidence delivery, production p99,
Linux/remote/NAS deployment and MCP policy are not established. These checks do
not drive actual Codex UI chats or answering models. Accepted LLVM seed and both
topic passes remain 0/6; repeated matched total-token/quality comparisons remain
0/18. The candidate is not adopted. Continue with real LLVM evidence on this
connected route under the existing seed and model-admission contracts.
