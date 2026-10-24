# Exact lookup of admitted judgments

This isolated Lean change indexes already admitted judgments. It does not yet
index all original Work or maintain canonical classes across publications.
See [the review](candidates/admission-policy-review.json) for exact source/link
inputs, guards, raw comparisons and the excluded pre-integration attempt.

`OutcomePolicy.admitted` previously searched the full admission list on every
classification. Repeated classifications can therefore require quadratic work.
The new table uses the complete structural `(demand, projected relation)` key
and stores the first admission's delivery, exactly as `List.find?` does. It keeps
completed, advisory, irrelevant, missing and duplicate-key behavior unchanged.
Hashing selects a bucket; full key equality decides identity.

Ordinary Lean proves table lookup and classification equality for every input
list and query. A proved `csimp` replacement preserves the logical policy and
existing Match/authority witnesses. The table is built once outside its lookup
closure. This creates no Match, Union, new authority or relevance cutoff.
ContractAudit includes all three refinement theorems.

The native caller must also be recompiled: Handoff specializes the generic
discovery loop. Recompiling only Matcher left the old linear closure inside
Handoff. That diagnostic run is excluded from final performance comparisons.
The final generated Handoff C calls the indexed factory and contains no old
linear policy closure; its object is the one linked into the tested runtime.

## Fixed inputs and native evidence

The reference is the retained deferred-discovery runtime, not public main.
All 32 small cases and four 10k cases agree in every Handoff field and body byte.
Small cases include seven completed results, five blocking results and a positive
local Union. Controlled numerical nominations/focus are fixed callbacks.

| Controlled 10k discovery | Reference ms | Candidate ms |
| --- | ---: | ---: |
| Local Union, first | 9,652 | 9,640 |
| Local Union, acknowledged history | 9,564 | 9,533 |
| Retrieval-only, first | 35,293 | 30,307 |
| Retrieval-only, acknowledged history | 35,475 | 30,306 |

The retrieval-only path is faster in this single comparison, but still exceeds
30 seconds without the real numerical provider. Normal-path improvement is not
established. These are not replicated token results or p99 measurements.

Both native arms use the same immutable 10k source, question, MiniLM/configuration
and stdout/receipt/ACK harness, with fresh private session/query state. Explicit
warm runs in a separate child before measurement; no source re-embedding occurs.

| Actual UserPromptSubmit | Reference ms | Candidate ms | Output |
| --- | ---: | ---: | --- |
| First, including manager startup | 18,793 | 18,558 | Identical stdout and 17,803-byte original body |
| Same query after confirmed ACK | 17,443 | 17,316 | Identical empty reply suppressing acknowledged evidence |

Search completes in the correct first/continued stratum; neither response is
an incomplete notice. Managers and all owned processes exit. This is one pair
per arm, not a demonstrated normal-hook speed gain or 50k qualification.
The maximum aggregate RSS across this work is 2,809,424 KiB; native arms peak
at 1,937,904/1,940,288 KiB. Original DB files remain unchanged.

## Remaining cost, sampled directly

A separate single retrieval-only diagnostic samples the processing thread for
two seconds, about twelve seconds after launch. `projectMatches` appears in
993 of 1,341 samples (about 74%); the other branch is demand topology lookup.
This fraction describes that window, not total runtime. The profiled Handoff
equals the unprofiled one; profiled timings are excluded from the comparisons.

`projectMatches` scans every existing relation before each addition and appends
one edge by copying the accumulated list. Next replace that with exact membership
and one final append, proving retention of base duplicates, insertion order,
first original payload and automatic-only admission. This is independent of
selector weights and model choice. Complete foreground Work reconstruction,
per-window numerical acquisition and topology work still need separate access
paths; fixing policy lookup does not solve them.

No answering-model calls or new seeds were made. Token savings and answer quality
are unmeasured. This candidate is unadopted under AGENTS.md; product files,
README results and releases remain unchanged. Full fixpoint/indexed recognition,
shared/federated lifecycle, storage policy and all-topic/both-lap qualification
remain unfinished.
