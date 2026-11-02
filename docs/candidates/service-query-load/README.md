# Actual LLVM selection requests under concurrent service load

Isolated model-free diagnosis on runtime
`d33a5d3c2ad7bb4c96aac61d111c26260f47835d4233b2a0795697fd561207e3`.
The [plan](plan.json) was written before execution. No answering model was
called. This is one shared project and one local data-side service, not eighty
complete hooks, multiple hosts, a publication workload or an eight-hour test.

[RealDeliveryProbe](../../../tools/research/RealDeliveryProbe.lean) runs the
ordinary topic 1/2/3 initial hooks, twice each, using the unchanged product
executable, original LLVM snapshot and frozen requirements. The optional
[native TCP relay](../../../tools/research/ServiceQueryLoad.lean) forwards the
unmodified framed requests and replies and captures each actual selector input
and its returned choice in memory. Capabilities never enter saved artifacts.
Only source identities, owner domains, sizes and hashes are retained in
[captured queries](captured-queries.json).

Both chats of each topic return identical selector inputs and exact choices.
The three distinct captured queries are assigned round-robin to 1/4/16/40/80
simultaneous native clients. Each client uses the ordinary palette, selection
and release RPCs, with one shared 29-second deadline. Every successful choice
must equal the choice returned to the ordinary hook, including all selected
source keys and receipt fields. Failed requests are retained and not retried.

## Results

The [six ordinary hooks](hooks.json) delivered 4/4, 7/7 and 5/5 known available
requirements in both chats: 32/32 occurrences, 14,817–16,582 ms. All three
bodies equal the retained record-boundary bodies byte for byte. This is not
two answering-model cycles. Three other proposed requirements remain
unconfirmed in the original DB and are preserved in the frozen record.

The [service load](result.json) did not pass at eighty clients:

| Simultaneous selector clients | Completed with exact choice | Sample maximum |
| --- | --- | --- |
| 1 | 1/1 | 1,381 ms |
| 4 | 4/4 | 2,560 ms |
| 16 | 16/16 | 7,809 ms |
| 40 | 40/40 | 18,693 ms |
| 80 | 61/80 | 28,611 ms |

All nineteen failed requests were still in the palette phase. They received
deadline/expired-view errors, not an empty-memory result. Prepared source loads
remained one, owner loads remained thirty, and page misses remained 888 through
all 141 requests. The immutable originals were being shared; they were not
rebuilt for every client. The captured query JSON is 1.00/1.97/1.29 MB and the
choice JSON is about 1 MB. Each palette describes 606,953 wire bytes and is
charged 19,488,032 bytes; the peak view charge admits six such views under the
unchanged 128 MiB limit. Large outputs share a 48 MiB reservation budget.

The subsequent [reply-admission candidate](../reply-admission/README.md)
separates selection computation from reserving output bytes. Its partial
improvement does not establish the full goal.

Eleven background `state.guard` warnings were observed in the native stderr
stream. The earlier ACK microbenchmark's zero warnings cannot be generalized
to this full hook path. These are retained-queue retries, and remain unresolved.
No live-head index-abort recurrence was observed in this read-only workload;
it does not test preparation under continuing original publications.

[Resource receipts](resources.json) include the initial test-harness compile
failure, a one-chat freeze rejected before fixture creation, and the corrected
two-chat run. The final guard exited normally, with no trigger or surviving
owned process; aggregate sampled peak was 2,814,848 KiB. These are sample
maxima and one burst per load level, not population p99 or token results.
Ended fixture DBs/caches are [deleted](cleanup.json), without archives.
