# Background admission is not index invalidation

The observed message is `Eggshell retained queued work: timed out waiting for
session state.guard`. Calling this "background indexing interrupted by a
publication" was inaccurate. It comes from `flushDeferred`, the background
save lane, rather than `flushIndexes` or the index worker's source validation.

In the fixed `bd609e52` runtime, `reconcileToolReceipts` and the enabled-state
check in `flushDeferred` call `withSession`, whose lock admission is 100 ms.
The enclosing catch returns without consuming the retained save queue. The
daemon schedules independent save and index tasks, each at most once per
second after its previous task has ended. This failure does not cancel the
independent index task or itself discard a prepared root. It also does not
prove bounded progress: repeated failure can delay publication and therefore
the indexing of newly observed work indefinitely.

The historical source-advancement rejection is a separate defect. The
[ordinary index worker overlap check](../lexical-delta/worker-progress/result.json)
completed pinned revisions while later publications arrived, retained old
readers and finally caught up. That small fixture is not evidence that the
full native hook path is free of lock contention under 80-user traffic.

The ACK candidate moved ledger confirmation outside the common session lock,
but the real hook still performs `handoff.reconcileDelivery`, constructs
`acknowledgmentProjection`, and writes the offered body/projection while
holding that lock in `deliverForWork`. These are remaining possible long
critical sections. No full-path holder timing was collected, so this note
does not assign each warning to one of them. The ACK-only zero-failure test
cannot close this issue: the later native run observed 13 warnings.

Any fix must preserve queued native observations, completed roots, delivery
deduplication, turn/epoch checks and the existing absolute deadline. It must
measure lock hold/admission and backlog progress in the actual hook path.
Increasing the wait or suppressing the warning does not establish a fix.
No product change or adoption claim accompanies this diagnosis.
