# Ordinary hooks writing to a shared project service

This candidate extends the [ordinary shared-read adapter](../project-hook-read/README.md)
with native capture and publication to the project's host. It is isolated from
the global installation and is **unadopted**. No answering-model run or matched
token comparison has been made.

`project_service` is a user-owned executable/argument array. The profile's
`read` names select readable projects and its optional `write` selects exactly
one writable project. Repository configuration cannot execute the command.
The captured descriptor and complete project/owner cut bind queued publication
to its original destination. A project destination has no local filesystem
path; only an explicit directory destination can reach the existing local
publication path.

Native Pre/Post records use an empty private per-turn journal anchor. It is
not a client copy of the shared work graph, and its private knowledge records
are not published. The publication capsule carries captured original tool
records and native provenance to the owning service. Shared source durability
and derived-index readiness remain separate: the client accepts a verified
source ACK; service-owned background preparation is notified separately.

The transport owns each connection's process group. Query execution is not
wrapped in a new shared mutex or search queue. Remote advice still cannot
certify or block a current native operation. Unsupported enforced native
searches are explicitly skipped rather than interpreted as an incomplete
network reply.

## Failures retained

The first native workload failed before its first source operation: the
adapter returned no reply for an unsupported enforced tool search, and the
caller rendered that as an incomplete notice. The correction makes the
no-search decision before entering the remote-delivery protocol.

The second workload durably stored all six native observations with their
provenance but omitted both final answers. The remote compiler used the queue
directory's checkpoint flag without the local path's final-message check.
Final answers can be queued in that directory. The correction makes a final
message select complete-turn compilation regardless of queue; the Lean law
`ProjectIngress.final_compiles_turn` states that invariant.

Both failures remain failures, with their exact runtime/observer bindings,
guard results, callback input/output and error records. Bounded fixture waits
distinguish asynchronous source publication from hook acceptance.

The corrected final-message path stored six original observations and two
answers, and all three advisory edge kinds were present. Its first read wave
still failed. A native read-only postmortem found ready query inputs in all
four owner slots, but missing owner-identity inputs in the two empty slots.
The two populated slots had both inputs. Waiting only for `PreparedInputs`
was therefore an insufficient readiness oracle; the actual query correctly
refused the incomplete inventory.

Writable project registration now durably registers preparation targets for
every physical owner, including empty owners, once per service registration.
The background service builds them; search neither creates them nor removes
empty owners from its captured cut. Registration IO runs outside the existing
owner-registry metadata section. The completed-registration marker is set only
after every target is registered; partial failure remains retryable. Restart
re-registers idempotently from durable targets. The fixture waits for both
query and owner-identity inputs before its delivery phase.

## Native validation

Product `d3496cae522875b41910e393492be4eef4bb55cfbc9c2498abe57a24366d2f56`
passes the fresh native workload with two project DBs and two physical owners
per project. Two simultaneous writers use the ordinary native hook entry to
capture six real shell observations and two final answers. Publication and
complete query/owner preparation take 4.835 seconds in this small fixture.
There are no manual `keep` or `warm` calls. Both populated owners retain all
three advisory edge kinds.

Four necessary original fields are frozen from the DB before delivery. Source
files are then deleted. Each ten-client wave mixes single-project and combined
readers; the restart itself is outside its following client gate.

| Native ten-client wave, including start/prompt/stop | Whole wave |
| --- | ---: |
| New sessions | 2.355 s |
| Resumed sessions | 2.270 s |
| After all three services restart: resume, clear, compact | 3.223 s |
| Three new, three resumed, two cleared, two compacted sessions | 2.281 s |

All forty searches complete semantically. Actual visible context contains
**104/104 required appearances of four unique fields**. Sixty appearances are
in new callback bodies; forty-four remain in previously confirmed context.
Reset contexts must receive the originals again. Required text is checked
inside its own SOURCE path/fingerprint's CODE block. Single-project readers
receive none of the other project's required fields. The original project
heads and files remain unchanged by the query phase.

All 144 native commands, including 138 hooks, exit successfully with empty
individual stderr and no incomplete notice. Sampled related RSS peaks at
3,561,152 KiB under the unchanged aggregate guard. All services stop normally,
the guard is terminal and untriggered, and no owned process remains. The
existing MiniLM pooling warning in the service log is retained; the model and
numerical leaf are unchanged. This fixture uses a 500,000-character allowance;
its largest actual callback body is 8,738 UTF-8 bytes. These are not token
reduction measurements.

The [per-hook receipt](hook-timing.json) has six Pre and six Post observations,
with maxima of 376 and 381 ms. The maximum of 42 UserPromptSubmit callbacks is
2.129 seconds. These small samples are not production percentile estimates.

Eight kernel-checked laws use standard axioms only. The actual publication
and registration callers are audited, and the read adapter's 1,376-declaration
dependency closure has no local project-file reads. The 343-object product and
320-object observer are audited against 318 identical common sources and the
complete product core. The interrupted build is preserved as interrupted;
its guard and every named descendant are confirmed absent before resuming
the checked compiler cache. Compiler rejections remain separate failures.

Ended DBs, private journals, caches, observer copies and unused installation
helpers are deleted without archive: 17,607 entries / 3,203,995,751 logical
bytes. Protected originals, current runtime, model and native inputs retain
their hashes. The 343-object product passes again after cleanup.

See the [summary](summary.json), [actual callback records](native-calls.json),
[visible delivery records](replies.json), [prepared owner inventory](preparation-postmortem.json),
[guards](guards.json), [proof/caller audit](proofs.json) and [patch](candidate.patch).

## Validation boundary

These are scripted native hook events on one Mac/OS user, not actual Codex UI
chats or authenticated clients on other machines. Existing
[local mixed-lifecycle evidence](../../practical-runtime/mixed-chat-lifecycle/README.md)
and shared-read evidence belong to their recorded runtimes and are not counted
as validation of this new publication adapter. This run restarts idle services
between turns; interruption during an active shared query/publication, late
tool results and project switching across that interruption are not covered.

Authenticated remote hosts, SMB/NFS, continuous publication during search,
crash recovery at every source/index boundary, bounded large-turn delta
publication, certified remote reuse, growing production DBs and sustained
80-user operation remain unverified. The accepted LLVM seed and both passes
of topics 1/2/3, repeated inclusive-token comparisons and quality evaluation
remain outstanding. These functional checks do not establish general 98%
delivery or token improvement.
