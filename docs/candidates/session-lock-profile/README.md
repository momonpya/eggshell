# Native session-lock observation

Isolated observer, not adopted and not a contention fix. The
[predeclared plan](plan.json) fixes the six native hooks and unchanged limits.
The observer runtime SHA is
`862df7070702f2473f10d3f29fd8e4c05d0ff07cb740a10be0ad7fffd583b3a0`;
the [patch](observer.patch) applies to parent `bd609e52…` with
`git apply --unidiff-zero`.

All six hooks preserved their parent's exact body hashes and the previously
frozen 4/4, 7/7 and 5/5 original requirements in both independent chats: 32/32.
Times were 14,760–16,343 ms. Three other proposed requirements remain
unconfirmed in the original DB. These are diagnostic initial chats from an
interrupted source, not paid first/history model trials or a new accepted seed.

The offer-publication guard held for 279 / 285 / 347 / 348 / 279 / 284 ms
when ordered by the recorded timestamps. Other measured hook sections held
for 0–1 ms. These are six observations, not a population p99. Twelve background
`state.guard` warnings occurred. The save lane has 100 ms admission, so the
observed offer holds can block it; the observation did not instrument every
ACK/background holder and cannot assign all warnings to that one phase.
No new tool observations were submitted, so it does not measure save backlog
drain or publication throughput under active tool traffic.

**The inner pure-step timings are invalid.** Passing `pure (compute input)`
evaluates its argument before the timing helper starts. The three zero-ms
decode/reconcile/projection readings therefore do not establish those steps
are cheap. The full acquired/released interval encloses their execution and is
still valid. State-write records were 4–6 ms. Raw step records remain in the
report, explicitly classified as unsuitable for pure-stage attribution.
Future pure-stage timing must defer execution into the measured action and
validate that measurement method first.

The ordinary ContractAudit compiled. The first observer compile attempt failed
on a helper's private visibility; the corrected build passed. All attempts and
the native run are retained in the [report](report.json). Native aggregate RSS
peaked at 3,007,248 KiB, with no guard trigger or owned process remaining. The
3.5 GiB stop, 4 GiB absolute ceiling and 2 GiB disk floor were unchanged.
Ended diagnostic DBs/caches/helper executables and raw logs are deleted, with
no archive. No answering-model calls or total-token improvement are claimed.

Following the ownership review, the next design is
[independent project streams and checked immutable views](../../owned-project-publication.md),
not an assumed CAS replacement. Its Lean model has passed, but the concurrent
storage/session runtime and index-completeness refinement remain unimplemented.
