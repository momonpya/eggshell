# Ordinary hook traffic with parallel original owners

Isolated continuation of [front-managers](../front-managers/README.md), parent
`726f6747`. Not adopted. Production sources and README results are unchanged.

One logical project keeps sixteen independent original append owners. These
are physical write regions, not people or separate user databases. Sessions
route to one region; each region serializes its own commits, while different
regions publish concurrently. Readers and derived caches remain project scoped.
The shared hook frontend owns bounded admission metadata, not all original
writes. Sixteen owners is a test configuration, not evidence of 80-user capacity.

The [predeclared series](plan.json) uses actual ordinary Prompt/Pre/Post/Stop,
background publication/preparation, the installed MiniLM boundary, 5 KB tool
outputs, and fresh reader chats. No administrative warm or answering model is
called. Four fields from two exact seed originals are frozen before delivery.
The intended later wave checks two fields from the newly saved original.

## Negative ordinary-entry evidence

[Native records](native-trials.json) retain every failure. Actual receiver
outputs are deduplicated by checked SHA-256 in [deliveries.json](deliveries.json),
with per-hook timing and ACK records. [Original audits](originals.json) and
[validation receipts](validation.json) are consolidated separately. Each fresh fixture has a different project
identity; these are not matched-snapshot performance or token comparisons.

| Trial | Initial bodies containing all four fields | Completed writer loops | Initial hook observed range |
| --- | ---: | ---: | ---: |
| Parent `small1` | 53/80 | 34/80 | 6,488–29,798 ms |
| Task/pipe candidate `small2` | 9/80 | 9/80 | 321–9,615 ms |
| Registration correction `small3` | 65/80 | 65/80 | 9,713–29,772 ms |
| Sampled diagnostic `profile1` | 59/80 | 58/80 | 8,234–29,774 ms |

The parent checker incorrectly required a delivery ACK for nineteen Pre status
messages that offered no memory body. That checker is retained as
[failed-checker.lean](failed-checker.lean). Its 34 completed writer loops must
not be confused with its 53 successful initial deliveries. Later checkers
separate valid JSON, an incomplete-search notice, an actual memory body and ACK.

The event-driven waits exposed a separate short cutoff: `readyEndpoint` sent a
registration RPC with a 250 ms budget before the real hook. In `small2`, 71
initial requests failed before a search dispatch was recorded, mostly after
roughly 0.3–0.6 seconds. The authenticated hook/ACK frame already admits its
session in the frontend. The candidate removes that extra registration RPC;
endpoint identity and actual process liveness are still checked. The original
hook deadline, admission bounds and certification domain are unchanged.

`small3` still failed fifteen initial deliveries and busy shutdown. Fourteen
dispatch errors mention `state.guard` at the deadline. This identifies the
terminal failing step, **not** the time spent holding or waiting for that lock.
The [predeclared native diagnostic](profile-plan.json) sampled the frontend
without changing product code. [Compact stack observations](profile-observations.json)
show operation transport waits and repeated `ProjectContext.captureInputs`,
`OwnerViews.load?`, project-scope and PageMap metadata reads across requests.
They do not identify the source-service queue's full processing cost or prove
that moving a lock boundary will solve it. Do not tune lock budgets from these
terminal error messages. The sampled trial is not a capacity result.

Read-only original audits of `small1` and `small3` found intact seed and stored
tool input/output, with unchanged source heads. At interruption, only one and
two writer originals, respectively, had reached the original DB; the remaining
posted observations were still queued privately. Neither failed trial proves
that background publication keeps up. The larger-output and fresh-reader waves
were not run after these failures.

## Isolated task and pipe changes

[candidate.patch](candidate.patch) contains six changed core files against the
exact parent source, including the new Lean `TaskDeadline` module. Native IO
completion wakes an owned waiter; cancellation is observed by a native timer
within 25 ms. Actual receives/readers are cancelled and joined. Provider stdin
has one optional owner, separate from the reader's process handle, so closing
input actually delivers EOF. Timeout abortion retires the real provider.

The two independent numeric processes have separate model/score gates. Existing
vector scoring can run while encoding owns the model lane. Embeddings, scores,
ranking and authority rules are not intentionally changed; broad rank equality
and total-token improvement have not been established by this component test.

The [component report](task-deadline-report.json) passes 128 already-completed
tasks, 64 provider responses, a 51 ms timeout, a 28 ms cancellation and exact
unit-vector scoring while the model gate is held. The 64 responses plus normal
provider retirement take 12 ms; the complete component scenario takes 181 ms.
These are component timings, not hook percentiles. The standard
[ContractAudit](contract-audit.txt) and actual executable-declaration dependency
checks pass. Two deadline laws use `propext`; the reader-handle ownership law
uses no axioms. They do not prove native scheduling progress.

## Remaining gate

The observed aggregate RSS stays below the unchanged 3.5 GiB stop and 4 GiB
ceiling. Failed shutdowns are retained; guards cleaned up all owned processes.
The 50 KB trial was not started. No 80-user sustained capacity, real-evidence
98% coverage, large-DB p99, multiple-PC/NAS behavior, answer quality or token
improvement is established. Paid matched comparisons remain **0/18**.

Next, measure source-service queue time separately from execution and count
repeated preparation-metadata reads. Reuse checked project/snapshot metadata
once per immutable input boundary, while attaching each private boundary
separately. Preserve all original owners for certification and independent
write lanes. Only then restart the full fixed-runtime protocol series; do not
repeat an unchanged 80-client run or increase its budgets. Adoption still
requires the AGENTS matched token, quality and deadline comparisons.
