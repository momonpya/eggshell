# Bounded immutable-object census

Diagnostic only; no capacity repair or adoption. Parent `c1de4407…`, observer
`af71fe76…`. Ranking, authority, model, budgets and worker policy are unchanged.
The linked source and native-input audits are in `native.json` and `sources.json`.

The small C adapter uses the installed Lean runtime's object-layout interface;
Lean controls and records every observation. It borrows a live immutable root,
follows constructors and ordinary arrays, and counts strings/scalar arrays as
leaves. It skips mutable references, closures, tasks, external objects and unknown
layouts. There are no exported pointers, mutations, allocator changes or Python
or Ruby components. Each observation is bounded to 262,144 objects and 6,291,456
bytes of temporary diagnostic storage.

Controls verified shared versus independent 1 MiB payloads, a mutable reference
that is not followed, and explicit capacity saturation. The actual hook trial
used three topic primes and four concurrent clients: all seven canonical bodies,
semantic routes, synaptic routes and ACKs passed. The measured wave took
4,004 ms; related sampled RSS peaked at 2,385,824 KiB. This was not an 80-client
retry or a model-token experiment.

Seven roots were observed in each of seven hooks. Input/admitted immutable roots
were about 1.16/1.93 MB; routed and bound roots varied by topic. Metadata and final
roots hit the census cap in every sample. Their roughly 8.36 MB counts are partial
and cannot establish a whole-heap size or the cause of the earlier RSS stop.

A separate native component examined eight fields of the 40 published owners.
The sum of independently measured complete owner roots was 43,394,861 bytes;
identifier rows and JSON were the largest field sums. Fields overlap and roots
may be shared. These numbers must not be added or multiplied by 80 to infer
per-request memory. Mutable cache contents and transient allocation remain outside
this census.

Actual cache counters show 40 source views loaded, zero evictions, and no further
view loads after priming through the measured 4/16/40-client phases. They do not
support adding another metadata cache or blaming cache thrashing.

The first initialization encountered a dead publisher endpoint left by the prior
forced 80-client stop, before warm or any hook/model call. Recovery checked that
its PID no longer existed and removed only dead endpoint records; the frozen
runtime was unchanged. See `initialization-recovery.json`.

After evidence collection, 3,311 files / 404,147,171 logical bytes of ended helper
builds, raw results, receipts and logs were deleted without archives. Current
native inputs, original DB bytes and the project cache were retained and
hash-checked (`cleanup.json`). After the diagnostic was complete, its source,
native build and installed executable were also removed: another 2,558 files /
549,614,755 logical bytes, without archives (`runtime-cleanup.json`). Native inputs
of the retained parent and new candidate were checked before deletion. The small
diagnostic implementation and validation records remain in Git. Paid
answering-model trials: 0; adoption: 0.
