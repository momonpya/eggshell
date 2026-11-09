# Actual selector preparation boundaries

Isolated diagnostic, not an adopted optimization. Parent is the owned-selector
runtime `36612afe…`. No model, weight, candidate domain, authority, budget,
worker limit, mutex or allocator policy changes.

The previous native run reached 4,152,272 KiB with sixteen clients. Its peak
included both publisher 1,850,144 KiB and frontend 631,664 KiB, so publisher RSS
cannot be assigned entirely to a particular selector object.

`HookFrontend.Session` stores cursors and maintenance markers, not a handoff or
ThreadState. `ThreadState.lastHandoff` is read by CLI status/graph display and
written on accepted delivery. Search requests also carry ThreadState, although
current native search checks use the request's epoch and reread current state.
The old body is empty in the fresh-chat capacity workload; removing its request
copy would therefore not explain that workload's observed memory peak. This
does not establish that state decoding or history requests are cheap.

The actual `selectView` includes problem construction, member alternatives,
bundle recipes, coverage compilation, cost binding, prepared scopes, the owned
kernel and final projection. The existing 335–1,532 ms interval combines them.
This diagnostic adds strict native barriers at those boundaries. The logical
barrier is identity; a copied pre-observer function supplies the whole-function
definitional equality check. The diagnostic native implementation records time,
PID, per-thread allocation-event counter and a per-call tag, then returns the
same input even if observation fails. It does not retain the inspected root.

Allocation events are not allocation bytes or process RSS. Intervals include
the preceding marker's observation overhead, and concurrent wall intervals
overlap. Native stage order/tag validity and actual returned body bytes must be
checked before interpreting the readings. These observations do not establish
capacity improvement, a population p99 or total-token savings.

The predeclared native workload is three warm primes plus four concurrent
clients on the existing interrupted-seed performance fixture. It is not a new
accepted seed, a paid first/history comparison or an unchanged 80-client retry.
The 5,000,000,000-byte ceiling, 4,358,524 KiB protective stop and 2 GiB disk
floor stay unchanged.

The isolated native runtime was `cd836bae…`. Its 324-object native closure and
one-existing-module/one-added-module source change passed; literal source
identities matched. The auxiliary whole-function equality check compiled using
`rfl`. Native return bytes were checked independently.

All three primes and all four concurrent clients returned their canonical body
bytes and ACKs. Four semantic searches and four synaptic projections completed;
the measured wave was 4,455 ms. Related aggregate RSS peaked at 2,030,208 KiB.
The original DB files did not change; both services exited with no owned process
remaining. This four-client diagnosis is not a capacity improvement comparison
with the earlier sixteen-client peak.

**Concurrent attribution is rejected.** All 63 events had one shared tag,
instead of seven independent IDs. No per-request concurrent stage duration is
inferred from it. The three sequential primes were recovered independently from
their published hook windows, which do not overlap; each window contains exactly
one complete, ordered nine-stage sequence with monotonic allocation counters.
See [validation](sequential-phases.json) and [events](events.json).

| Sequential interval | Topic 1 | Topic 2 | Topic 3 |
| --- | ---: | ---: | ---: |
| Problem construction | 133.903 ms | 180.191 ms | 182.389 ms |
| Member bindings | 2.703 ms | 2.697 ms | 2.704 ms |
| Bundle recipes | 2.504 ms | 9.651 ms | 10.127 ms |
| Coverage compile | 1.510 ms | 2.345 ms | 2.351 ms |
| Cost binding | 0.365 ms | 0.397 ms | 0.372 ms |
| Prepared scopes | 4.832 ms | 5.448 ms | 5.614 ms |
| Owned selector | 178.649 ms | 259.526 ms | 264.236 ms |
| Final projection | 21.194 ms | 23.272 ms | 22.915 ms |

The selector intervals count about 3.20 / 4.84 / 4.83 million small allocation
events. This does not identify their live byte count, retention or contribution
to publisher RSS. These three samples exclude neither other query stages nor
frontend encoding/ACK work. They narrow the preparation investigation away from
scope construction; they do not justify another scope cache or certify the
80-client workload. The remaining family-only base-cue lookup motivates the
[unconnected range-index prototype](../base-cue-buckets/README.md).

Scaffolding compilation and proof/record-preservation failures occurred before
any native hook; [guards](guards.json) retain them. Successful native services
reported zero owned processes after shutdown. No answering model ran. The
diagnostic native/source/prefix, ended results, session/receipt data and raw logs
were then removed without archives: 3,899 files / 548,725,550 logical bytes.
Protected original/current runtime and canonical-body hashes were checked before
and after; [cleanup](cleanup.json) records the boundary. Logical deleted bytes are
not the same as physical disk space reclaimed. The owned-selector parent and
project cache remain available; the ended observer executable does not.
