# Hook ingress supervisor candidate

Status: isolated, unadopted candidate based on public main
`51873167c11c447a0af67e73430b5ab6635b2a65`. No release or token-saving claim.

The public client's RPC timer starts after reading stdin and recording the
native tool result. A blocked read in either step can consume the entire host
timeout without producing a hook response. Separately, a malformed session
state aborts capture before the original tool result becomes durable.

## Execution boundary

The registered handler selects its budget before stdin is read. Ordinary hooks
use `codex-hook` with a 29-second window. Terminal hooks and compact SessionStart
use `codex-hook fast` with a 2-second window. The manifest retains its existing
30/3-second host limits, leaving time for cancellation and output forwarding.

The parent starts a process group that inherits stdin. That child owns parsing,
native capture, manager startup and the direct RPC. It cannot create a blocked
stdin-copy task in the parent. The parent kills and reaps the child group on
expiration, validates the response as a JSON object, and emits an explicit
unconfirmed-processing notice if no completed response arrived. A delivery
acknowledgement is attempted only after the parent writes and flushes the body.
This acknowledges that pipe write; it does not prove model receipt.

Malformed session state causes the child to preserve the immutable native
observation and then report incomplete processing. A valid disabled state still
prevents capture. If the storage operation itself blocks until cancellation,
journal durability remains unknown and the warning does not claim otherwise.

`ContractAudit` checks that the parent uses the deadline/group supervisor,
performs no stdin read or native capture, and reaches the response decoder. It
also checks the child-to-request-to-capture/direct-transport route. These source
checks are separate from an OS-level liveness or semantic correctness proof.

## Repeated fault experiment

`tests/hook_ingress.py` runs the actual command selected from each manifest.
There are three repetitions of nine event/condition pairs per arm: 27 public
and 27 candidate trials. Both arms used the same harness and identical input
hashes. Conditions include ordinary input, valid disabled state, malformed
state, a FIFO that blocks state reads, and complete JSON with EOF withheld.
Each run retains input, stdout, stderr and an execution receipt. No source DB,
embedding model or language model is used.

| Condition | Public main, 3 trials | Candidate, 3 trials |
|---|---|---|
| Blocked state, PostToolUse | Host kills at 30 seconds; empty stdout | Explicit warning at 28.88–28.91 seconds |
| Held stdin, Interrupt | Host kills at 3 seconds; empty stdout | Explicit warning at 1.88–1.92 seconds |
| Malformed state, PostToolUse | No original observation saved | Original observation body saved unchanged |
| Valid disabled state, PostToolUse | No observation or context | No observation or context |

All 27 candidate trials produced valid JSON without a host kill. Public main
had six missing-output trials. The malformed-state body comparison checks tool
identity, command input and original response, not just receipt count. This is a
deterministic fault comparison; concurrent validation and sequential arm runs
do not support a general latency or throughput claim.

The FIFO and withheld EOF are injected faults. They reproduce missing native
stdout, but do not identify the original reported incident or reproduce its
literal Codex UI error. Slow or uninterruptible OS operations and blocked host
stdout remain IO-boundary assumptions; these tests are not a hard realtime
proof. A 28.9-second warning also does not satisfy Phase 1's cold-hook target.

## Remaining gates

The full regression suite, lifecycle checks and package checks pass. Full regressions retain
two `retained uncommitted work: No such file or directory` warnings; successful
exit is not evidence that every background queue drained. The final inventory
still has three indexing tickets in the `daemon-parallel` session. Draining
those independently of session lifetime remains Phase 1 work.

Phase 0 still needs semantic success/pending/timeout receipts, vector cache
statistics, stage durations, and full equality-dependency attribution including
inherited local unions and structural selection dependencies. This candidate
does not restore or claim those features.

No initial/history × topics 1/2/3 language-model token comparison has been run.
The repository adoption gate therefore remains unsatisfied, even though the
fault and regression checks pass. The candidate must remain separate from the
main implementation, public README results and release until that gate passes.
