# Keep valid empty delivery separate from failure

The preceding [lexical-witness candidate](lexical-witness.md) exposed a status
bug: the 50k continuation returned a valid empty worker result before the
deadline, but the controller changed every empty lexical result into an incomplete
notice. Making reads faster could not remove that unconditional conversion.

This isolated Lean change uses the existing `SearchDelivery.empty` boundary.
It requires a current accepted request stamp and a successfully decoded worker
reply containing no new Handoff. The controller now retains empty status
metadata instead of manufacturing `pendingSearch`. Missing, malformed, expired
and obsolete replies still pass through their existing distinct constructors.
Actual pending results remain pending. No new transport, format version or
compatibility branch is introduced.

The metadata has empty text and no delivered graphs, completion, Union,
covered fragment, source checkpoint or operation-blocking authority. It is
not registered as a memory offer. The original semantic trace is retained.
If semantic search timed out, the existing system notice still says so and
states that no new memory body was delivered. No incomplete context body is
injected for this accepted empty lexical result. Configured empty results retain
the same empty stdout body as before.

Ordinary Lean proves the accepted-empty parser case, authority-free metadata
and unchanged trace. ContractAudit requires the real controller to use the
accepted-reply classifier, neutral empty result and separate pending result.
The standalone audit covers all ten route/status combinations, transport
absence, malformed JSON shape, expired/stale replies, oversized UTF-8 output and
an actual pending Handoff. A preliminary helper failed on an unavailable
`Except.isError` convenience method; the corrected audit uses the existing
`toOption` API. The failure remains recorded.

## Actual native checks

One guarded actual-native pair per original read-only source uses the unchanged
MiniLM boundary, source-only prepared cache copies and new private question/chat
state. Preparation releases its process before foreground timing. Actual stdout
matches its publication SHA and both owned managers acknowledge shutdown and exit.

| Source | First | ACK-history continuation |
| --- | --- | --- |
| 10k windows | 9,600 ms; original body 17,803 bytes | 7,901 ms; no new body, configured semantic search complete |
| 50k windows | 22,735 ms; lexical original body 21,346 bytes after semantic timeout | 22,047 ms; valid empty lexical result, no incomplete context body |

Both first bodies and the 10k empty body match their stored lexical-witness
references. The 50k continued body intentionally changes from the 356-byte
incomplete notice to zero bytes. Its stdout contains only the existing system
notice: semantic search timed out and no new saved-memory body was delivered.
The receipt says `disposition=empty`, `reason=no-new-memory`, `completed=0`;
memory-offer acceptance is false and acknowledged history remains 12. The first
50k offer is accepted. Semantic timeouts of about 14.3 s remain visible on both
50k requests; this is not successful complete numerical ranking.

These are one-pair lifecycle diagnostics, not a fresh paired speedup trial,
p99 or token benchmark. The previous stored times were 9,812/7,944 ms and
22,897/22,584 ms. No timing improvement is attributed to this classification fix.
Explicit warm/repeat take 21,967/20,585 ms at 10k and 145,459/140,050 ms at 50k,
outside the hook table. All four reuse existing coverage with zero source
embeddings, produced projections or matrix bytes written.

Maximum aggregate RSS is 2,114,880 KiB, below the 3.5 GiB guard and 4 GiB ceiling.
All final guards/owned processes finish; original DB and lexical-index file
hashes remain unchanged. Terminal helpers are hashed and deleted without archives;
their source, generated code, objects, link inputs and raw evidence remain.
The [review](candidates/empty-search-review.json) pins these records and the
patch, runtime and consistency check.

## Scope

This changes status classification, not retrieval scores, selected originals,
packing, the MiniLM contract, three synaptic relations, class recognition,
freshness or deadline policy. No answering model or seed is called. It does not
establish token savings, quality, p99 or million-window capacity. Full numerical
scoring and large lexical postings still require corpus-proportional work, and
normal federation still builds its catalogue. Shared concurrent use, private
MCP capture, Phase 4 tool-semantics rules and matched model comparisons remain
unfinished. Product adoption continues to require the topic/lap/repetition,
inclusive-token, quality and deadline gates in AGENTS.md. Phases 0–6 stay active.
