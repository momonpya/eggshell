# One admitted search and fallback lifetime

Isolated candidate over `72025d95`; not adopted. Answering-model calls are zero,
and the matched total-token/quality comparisons remain 0/18. The complete
80-client ordinary lifecycle gate still **fails**.

The previous frontend submitted configured search, waited for its phase cutoff,
then submitted lexical fallback to the same saturated queue as a second job.
Its final per-receipt observation could overwrite the first attempt. This
candidate admits one service operation with the original absolute deadline and
the unchanged captured original/prepared/private inputs. The service executes
configured search and any fallback sequentially in that slot. Requests whose
semantic window already expired in the queue go directly to lexical search.
Checked early-ready nominations may finish within the original hook deadline.

The owned phase runner retires and joins its worker process group before fallback.
The controller does not create an extra timer task or another queue. Cooperative
cancellation also reaches the raw worker. A valid empty response remains complete;
transport absence and incomplete search remain distinct. The frontend still uses
the existing SearchDelivery, turn/epoch/deadline and delivery-ACK checks. Queue
expiry no longer sends an unconditional warm notification; actual preparation
debt remains authoritative. Each operation's admission and terminal observations
and each completed phase are recorded separately.

Only Worker, PluginHooks and OperationPool change in [candidate.patch](candidate.patch).
MiniLM, numerical values, ranking, selection, Handoff, certification, original
publication and the frontend registry are unchanged. The complete source-tree
comparison confirms those are the only three changed product modules.

## Checks

Lean laws cover lexical fallback's frozen inputs, upstream deadlines, accepted
empty results and absent transport. The declaration/AST audit checks that the
normal frontend has exactly one exchange and that the service reaches the owned
phase runner. The unchanged standard ContractAudit passes.

The native policy cases cover body/empty/failure/pending results, queue expiry,
early-ready completion, upstream expiry and cancellation. An actual unresponsive
native worker and its `/bin/sleep` descendant retire before lexical fallback in
89 ms. Cancellation retires another worker group in 27 ms; cancellation of the
controller starts no fallback. These component checks do not establish capacity.

| Ordinary native protocol | Result | Hook time |
| --- | --- | --- |
| Eight fresh readers over the prepared seed | 8/8, all four frozen fields | 1,350–3,409 ms |
| Eighty writers' initial delivery | 80/80, all four frozen fields | 3,287–20,206 ms |
| Same eighty clients' Pre/Post/Stop | 80/80 writer loops finish | Individual receipts retained |
| New eighty readers after saving and preparing those observations | **7/80** deliver both new frozen fields | 311–29,760 ms, including refused requests |

The writer stage has exactly one operation admission per initial hook: 31
configured completions and 49 lexical fallbacks. Background preparation drains
through the ordinary workers, without administrative warm. An independent audit
finds all **82** exact original input/output observations across the complete
16-owner project view. The fresh-reader failure is not evidence of lost originals.

Of eighty readback receipts, **33 have zero operation admissions**. The frontend
keeps the seed plus eighty old writer sessions in its 128-entry registry and
rejects later sessions as full. The other 47 readers have one admission each;
seven finish configured search and forty fail under load. Registry retirement
alone therefore cannot be called the complete fix. The unchanged registry also
periodically schedules every retained session for maintenance; raising its limit
would hide lifecycle and work-amplification problems.

A new solo frontend over the **same retained original heads** delivers both
case-79 fields. Its service queue is 1 ms and service work is 5,592 ms. The recorded
elapsed-including-shutdown value is not hook latency. The original head hashes
remain unchanged, both services exit normally and the aggregate guard owns no
remaining processes. This checks storage and one unsaturated read; it does not
replace the failed eighty-reader gate.

The complete traffic guard peaks at **3,363,776 KiB**, below the unchanged
3,670,016 KiB stop and 4 GiB ceiling, and finishes with no owned processes.
The 50 KB protocol was not started after the readback failure. None of these
synthetic bursts demonstrates 80 users for eight hours, multi-host/NAS operation,
p99, real-LLVM 98% delivery, answer quality or total-token improvement.

## Ownership and next investigation

Parallel original owners remain mandatory: one configured project DB, multiple
independently owned physical append regions, and shared project-scoped vectors
and caches. Eighty users do not require eighty owners or private copies of the
project. This trial routes eighty writers across sixteen original owners; search,
save-operation and preparation slots are separate resource limits.

The next candidate must safely retire/reconstruct quiescent frontend cache entries
without losing durable work, active requests or maintenance ownership. Separately
measure the larger post-write query's service work and queue time. Preserve the
original deadline and complete read/certification domain; do not treat more slots,
larger registry bounds or another unchanged eighty-client run as a fix.

[summary.json](summary.json), [native-reports.json](native-reports.json),
[native-trials.json](native-trials.json) and [native-stages.json](native-stages.json)
retain every observed hook, deduplicated actual output and phase/admission data.
[guards.json](guards.json), [policy.json](policy.json), [identity.json](identity.json),
[laws.txt](laws.txt), [contract-audit.txt](contract-audit.txt) and
[failed-attempts.json](failed-attempts.json) retain limits, exact source/runtime
identity, proof scope and failed attempts. Initial builds and the solo diagnostic's
syntax/path mistakes remain failures. No paid seed was acquired or modified.

After sealing, ended policy/eight-reader fixtures and the superseded parent
failure DB/cache, together with raw logs and ended guard settings, are
[deleted](cleanup.json). No archive is created. Only the current failed small1
fixture is retained for the next lifecycle/query diagnosis, plus current control,
build inputs and protected originals. Do not rerun the destructive cleanup or
record extractor against already deleted inputs.
