# Retiring quiescent frontend cursor entries

Isolated continuation of `16f3576a`, not adopted. The complete ordinary
eighty-client lifecycle still **fails**. Answering-model calls are zero and
matched total-token/quality comparisons remain 0/18.

Only [HookFrontend changes](candidate.patch). The existing single loop owns
registration, cursor-entry revisions and retirement. No lock or CAS is added.
The registry stays at 128 entries; original publication still uses independently
owned regions within each project. Search/save/preparation counts, deadlines,
bytes and complete read/certification domains stay unchanged.

Successful maintenance may mark an entry quiescent only after its turn is closed
or absent, durable deferred/checkpoint queues are empty, preparation requests have
been accepted and the preparation wake has not changed. Malformed or quarantined
pending state is not absence. Inspection does not quarantine or consume data.
Arrival and completion of a hook/ACK advance a loop-owned revision and clear
quiescence; a stale maintenance result cannot restore it. A pending refresh,
active request or active maintenance protects the entry. Under registry pressure,
the loop retires the oldest eligible entry, discarding only reconstructable cursor
state. Private journals, project originals and shared vectors are not deleted.
Confirmed quiescent history is no longer refreshed every second.

## What passed

Five Lean laws protect changed revisions and active/pending entries. A declaration
audit connects those helpers to the actual loop, and connects maintenance to the
existing durable ACK and preparation paths. The unchanged standard ContractAudit
passes. These laws do not prove distributed ownership or the whole IO system.

The native policy test registers 240 closed-history sessions through the actual
authenticated frontend. The unchanged 128-entry bound retires 112 old entries;
re-registering the oldest session retires one more. Private state is unchanged,
unauthorized input cannot evict a session, and idle maintenance does not repeat.
Native file checks reject open, queued, malformed and quarantined turns without
consuming their work. The stale-result and active/pending selection checks use
the actual pure policy; they are not a full concurrent shutdown stress test.
[Policy receipt](policy.json), [laws](laws.txt), [contract](contract-audit.txt).

Eight ordinary prepared readers deliver all four frozen fields in
1,392–3,690 ms. In the next 5 KB eighty-writer protocol, all eighty initial bodies
contain all four seed fields, in 3,378–20,233 ms, with one operation admission each.
All eighty Pre/Post/Stop loops finish. Ordinary background preparation drains,
and the independent audit verifies all **82** exact input/output originals across
sixteen owners. No administrative warm is used. The post-readback head files
also equal all sixteen frozen original heads.

## What still failed

The subsequent eighty fresh readers deliver both required case-79 fields in
only **6/80** cases. There are no `frontend session admission is full` messages.
Seventy-one requests have one operation admission and nine have none. All eighty
captured turn-input frames are complete: missing index readiness is not the
explanation for those nine unadmitted requests.

The final delivery groups are:

| Route/result | Clients | Required original fields |
| --- | --- | --- |
| Configured meaning search completed | 6 | Both fields delivered |
| Lexical fallback offered a valid body | 15 | Neither field delivered |
| Incomplete/deadline failure | 59 | No successful delivery |

All fifteen lexical bodies are 8,374 bytes and cite the same eight *other* cases
(4, 10, 11, 40, 47, 58, 63, 67). None contains a case's frozen raw head value.
This is a nomination/delivery defect, distinct from the queue's timeout defect;
successful JSON output must not count as evidence delivery.

Only 25 calls retain a final service observation. Within that observed subset,
queue median/max are 20,809/26,512 ms and service-work median/max are
1,710/10,503 ms. The fifteen completed lexical phases take 1,320–2,134 ms.
All eighty input captures report complete, with boundary/reference/owner/attach
substeps summing to 596–1,840 ms. These figures do not establish an all-request
p99, nor identify the entire cost before admission. See
[readback analysis](readback-analysis.json) and [actual stages](native-stages.json).

Shutdown also fails: the frontend acknowledges shutdown but does not exit within
its existing three-second retirement budget. The outer guard detects leftover
processes and cleans them up; its terminal owned set is empty. This is **not** a
normal native shutdown pass. Aggregate sampled peak RSS is 3,231,888 KiB, below
the unchanged 3,670,016 KiB stop; the guard trigger is `leftover-processes`, not
memory. The 50 KB protocol is not started. The whole eighty-client gate, sustained
eight-hour load, multi-host/NAS, real-evidence 98%, quality and token improvement
remain unproved. Do not compare fresh synthetic seeds as a causal speedup.

## New diagnosis and next action

The unchanged lexical grammar retains a sentence-final period inside a word.
The actual question produces `Pcase-79.`, while the audited tool Work's case field
produces `Pcase-79`. The URI remains one whole token. Pure Lean evaluation finds
**zero shared tokens** between that question and the recorded tool invocation;
dropping the final period produces `Pcase-79`. A standalone `P:` is also present
in the stored JSON's terms. [Token-boundary diagnosis](token-boundary.json).
This is not a grammar change, a ranking experiment or proof that punctuation
alone fixes all delivery. SearchRank/tokenizer, graph, numerical values and
selection are unchanged by this candidate.

Next address literal/resource-token boundaries generically, without task-specific
keys or weight tuning, and replay against the complete frozen originals. Separately
reduce the measured query work and queueing using publication-prepared shared
WorkGraph metadata, and trace cancellation/join of active frontend requests.
Do not enlarge the registry, workers or deadlines, repeat this unchanged burst,
or call the policy-only success eighty-user support.

[Identity](identity.json), [guards](guards.json), [failed attempts](failed-attempts.json),
[native reports](native-reports.json), [actual outputs](native-trials.json),
[summary](summary.json) and [original heads](original-heads.json) retain scope and
all failures. Initial compile/test-controller mistakes are not passing trials.
Ended fixtures and raw logs are deleted after sealing, without an archive; the
current failed small1 fixture remains the next diagnostic input.
