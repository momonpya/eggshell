# Shared hook frontend, parallel original owners

Isolated continuation of [publication-names](../publication-names/README.md),
parent `cb4fabdd`. Not adopted. One logical project keeps sixteen independent
original append owners. Sharing the hook frontend does not serialize those
original writers, merge project caches or narrow certification's source domain.

The earlier 80-query/80-save tests exercised ordinary search and save functions
but bypassed normal per-chat daemon ownership. The normal frontend still made
one resident manager per chat. The [predeclared idle test](plan.json) reached
40 managers at 2,394,896 KiB manager RSS, then triggered the unchanged 3.5 GiB
aggregate stop before reaching 80 (58 managers observed at the peak). That is
counterevidence to treating the earlier tests as full ordinary-entry capacity.
The failure is retained in [parent-guard.json](parent-guard.json), with partial
[samples](parent-samples.json) and the exact [checker](parent-checker.lean).

The candidate has one private local hook frontend for a data root, independent
of the project publication service. It routes authenticated session IDs, keeps
session-private state separate, and derives synapse clock domains per chat.
One loop owns registration, request-byte accounting, pending maintenance and
active task ownership. It admits at most 128 requests, 16 MiB of admitted input,
four framed readers and two session-maintenance tasks. A session cannot have
two maintenance tasks at once. These are resource bounds, not measured capacity.
Underlying Lean/OS synchronization still exists; no whole-program lock-free
progress guarantee is claimed.

The first two shared runs registered all 80 chats with one manager and roughly
69,296 KiB manager RSS, but failed shutdown. They are **failed trials**. After
replacing cooperative notification alone with cancellation of actual receives,
the failure remained. A separate one-process native diagnostic disproved the
zombie-process hypothesis: the process was live, with the main thread inside
Lean task-manager finalization and a session-maintenance thread waiting in
`Publication.Client.resolve` → `Daemon.connect`. The endpoint file was already
removed. [Diagnosis](retirement-diagnosis.json), [stack](retirement-stack.txt).

The continuation joins owned work before returning from the frontend, checks
cancellation before subsequent maintenance/startup steps and while acquiring
existing filesystem guards, and makes connect/send waits spend their original
absolute deadline. Receive cancellation unregisters and joins the actual async
read. It does not extend shutdown or hook deadlines. Native validation of this
continuation initially still failed: a second one-process diagnostic showed
an actual exit code of zero and a zero-RSS zombie, rather than running work.
The spawning parent now retains and reaps its child handle under the existing
startup guard. Foreign callers distinguish exited processes from running ones.
[Exited-child diagnosis](retirement-exited-unreaped.json).

The final [80-chat trial](shared-report.json) passed, including a peer stalled
after one header byte, wrong-chat hook/ACK rejection, unauthenticated registration
rejection, eighty distinct clock domains, unchanged original heads and actual
exit of the frontend. Shutdown took 1,014 ms; the three-second cutoff was kept.
All sixteen original heads also match the pre-candidate baseline.

| Registered chats | Native managers | Manager RSS, KiB |
| ---: | ---: | ---: |
| 10 | 1 | 62,032–68,176 |
| 40 | 1 | 68,480–68,816 |
| 80 | 1 | 68,896–69,264 |

Peak aggregate RSS was 288,416 KiB, including the test/guard and shared service.
The separate [early-shutdown check](retirement-final.json), with maintenance
still active and a partial-header peer, returned in 42 ms and independently
reaped the actual child with exit code zero. Both final guards report no owned
survivors. Earlier failed trials and build/probe errors remain in the compact
[resource](resources.json) and [negative](negative-checks.json) records; they are
not counted as passes. These are not latency percentiles.

The four Lean budget laws cover admission counts/bytes and same-session task
exclusion; they are not proofs of heap usage, native IO, liveness or throughput.
The separate declaration audit checks that the actual loop, maintenance,
per-chat clock attachment and ordinary daemon entry use those implementations.
Normal ContractAudit also passed on the final source. Product adoption still requires the
prespecified matched total-token, quality and deadline comparisons.

Apply [candidate.patch](candidate.patch) after the parent's patch. It changes
Daemon/Wire, adds HookBudget/HookFrontend, and makes existing lock waits and
publication-service startup observe cancellation. The sixteen preserved
[source hashes](identity.json) include the original store, project ownership,
captured boundaries, search/selection, e-graph and authority code. The
[setup](setup.lean), [proof setup](check-setup.lean),
[retirement setup](retirement-setup.lean) and [records](records.lean) use Lean;
the numerical runtime remains the existing local MiniLM implementation.

This component does not establish real 98% evidence delivery, 5–50 KB ingestion,
eight-hour load, large-DB p99, multiple-PC/NAS behavior or token improvement.
The next full-system test must include normal hook routing, Pre/Post, parallel
original saves, shared preparation and growing data, with queue age and
preparation debt and chat turnover. No answering model was called for this component.
Finished fixture DBs/caches, raw logs and the diagnostic executable/build were
deleted without archives: 136,748,209 apparent bytes. The current runtime and
necessary build inputs remain; protected originals were rehashed unchanged.
[Cleanup](cleanup.json).
