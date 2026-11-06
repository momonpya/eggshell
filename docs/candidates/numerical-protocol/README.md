# Numerical transport isolation

Status: isolated and unadopted. Answering-model calls: 0; paid matched
comparisons: 0/18. This component does not exercise WorkGraph selection or
original-evidence delivery.

The same 16 frozen source owners, 163 documents and 1,205 window references
feed one query encoding and two full scoring passes for each of 80 distinct
development questions. Exact score digests, source Heads, row order, ordinary
versus observed controls, model count and original deadlines are checked.

The original numerical service completed 77/80 requests: three TCP connections
expired. Its backlog and live-handler admission were 32, despite the existing
operation admission being 160. The isolated capacity correction binds both to
that existing admission constant. It completes 80/80, with all 77 prior score
digests identical. Wall time is 9,970 ms, versus 8,990 ms for the incomplete
parent. This establishes capacity correctness, not a speed improvement.

JSON decoding/parse medians were at most 1 ms. The evidence does not support a
codec rewrite as the cause of this failure. Client system CPU was 57.00 seconds
in the complete capacity control; these aggregate CPU seconds are not wall
time or attribution for the full hook.

The next candidate owns one pending native receive per connection fragment,
cancels and joins it on every exit, and avoids the stdlib readiness callback's
nested blocking read. Both exact-length readers now use terminating recursion
with a proved decrease for positive bounded chunks. Native fragmented-read,
callback-error, deadline, stop, EOF, unaffected-peer and raw-child lifetime
checks run before load. No kernel/model/scoring/deadline changes are made.

That candidate completes 80/80 in 8,026 ms, with all 80 score digests equal to
the capacity parent. Client system CPU is 35.71 seconds. Ordinary hooks then
complete two 16-client waves: 32/32 required originals, ACKs and semantic
handoffs, byte-identical to the retained parent. A full 80-hook run of this
intermediate runtime was not performed: the user directed the next change to
unnecessary read locks.

Evidence: [component records](evidence.json), [stage accounting](summary.json),
[capacity correction](../numerical-capacity/candidate.patch),
[receive ownership](../owned-receive/candidate.patch),
[native and ordinary-hook evidence](../owned-receive/evidence.json).
Failures are retained. These results do not establish total-token improvement,
answer quality, 80-person sustained use, growing DBs, NAS safety, or the 98%
real-evidence target.
