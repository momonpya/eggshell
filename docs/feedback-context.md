# Read eligibility before presentation

Status: quarantined, not adopted. Parent product `cfbbf023…`; candidate
`05e28ed8f1bb6606b02d5ef7b2fa2ca1e2e34d9cb9168e347a51691609e6b46f`.
The only product delta is [feedback-context.patch](candidates/feedback-context.patch).
The model and the original sources are unchanged.

## Fault and change

The first real-seed warm of the literal-support candidate failed with
`synaptic replay deadline`: 61,806 ms inside the replay and 72,149 ms for the
guarded command. A CPU sample of the private replay spent all 1,346 active
samples in `Journal.presentation`, reconstructing acknowledged originals.
Some reads could never earn a usage label because their pre-read knowledge
was unavailable or incomplete; presentation was nevertheless computed first.

The candidate makes the same eligibility decision before presentation. It
does not add a label, remove private history, increase a deadline, or change
recommendation weights. Successful indexed reads and answer citations retain
their existing handling.

One paired read-only replay of the same 59 private events took 16,807 ms in
the parent and 8,232 ms in the candidate. Both produced exactly the same
4,877 consumption facts, 18 usage facts, 29 origins, 0 pending, and 18 unknown.
All three evidence digests match. This single pair is a diagnostic, not a
statistical performance or token-improvement result.

## Actual hooks remain unsuccessful

The fixed C7 seed and frozen DB-present evidence were reused for model-free
diagnosis. This is not a new-seed answering-model study. Counts include the
failed topic; missing coordinates do not change the frozen denominator.

| Topic | Frozen eligible | Actual delivered | Hook ms | Result |
| --- | ---: | ---: | --- | --- |
| 1 | 4 | 2 | 25,989 / 25,203 | Same body in two private chats |
| 2 | 6 | 0 | 28,976 | Incomplete notice; daemon receive deadline |
| 3 | 5 | 3 | 28,884 / 26,346 | Same body in two private chats |

Topic 1 and 3 still omit the ToolChain key and complete HLSL branch. Topic 1's
body is byte-identical to the earlier record-focus candidate, not a delivery
improvement. Warm succeeded for all three forks, in 106,064 / 164,999 /
159,619 ms. Source facts and the published source prefix remained unchanged.
The actual hook still reads only a fraction of the first synaptic lookup
before the 500 ms budget expires and admits no graph offers.

The actual Pre/Post/Stop fixture passed: six tool observations, 13 journal
events, four private usage facts, ten supports, sixteen coquotation facts,
DB-only restoration, and 2/2 tiny required originals. A fresh full-search
oracle and ContractAudit passed. A concurrent preparation warning remains:
`original basis changed during incremental assignment`.

Aggregate actual delivery is **5/15**, with **0 answering-model calls and 0/6
answering stages**. No token improvement, 95% delivery, shared NAS, or
10–80-user acceptance is claimed. See the
[raw report and bodies](candidates/feedback-context/records/required-report.json).
The graph-access investigation continues in [synaptic-routing.md](synaptic-routing.md).

Ended topic-2/3 DBs and caches, the earlier executable/prefix, native fixture,
research helper builds, contract interfaces and finished probes were deleted:
13 targets, 1,250,199,652 logical bytes. No archive was created. The original
seed, build dependencies and the topic-1 graph actively used for persistence
integration remain. See [cleanup record](candidates/feedback-context/records/retirement.json).
