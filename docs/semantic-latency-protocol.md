# Warm DB semantic completion measurement

Fixed before collecting results. This is a latency diagnostic of the isolated
development candidate, not a token/quality benchmark or an adoption comparison.
No generation-model calls are needed. The MiniLM model, ranking settings,
semantic-first policy and 1,500 ms semantic budget remain unchanged for this run.

Prepare one saved fixture for each source count: **2, 32, 256, 1,024**. Record its
actual document/window counts, graph files, head digest, source text construction
and completed warm coverage. Copy that same saved DB and the same numerical
records into every repetition and layout for that size; never generate separate
seeds to compare layouts. Model weights and the numerical runtime stay installed
and offline. OS page caches are not cleared, so this is not a cold-disk test.

For every size, use these two source-cache layouts:

- The DB contains its warm source vectors and remains filesystem-writable.
- The graph DB is protected against writes and source vectors live in the user's
  DB-identity-scoped private overlay.

Both use a read-only profile with no write DB, preventing a response memo or
question save from changing the compared graph. Each of **three repetitions**
gets a separate data root and uses the identical question for that repetition
across sizes/layouts. Its two measured conditions are:

1. A new chat with that question absent from the private question-vector cache.
2. Another new chat with the identical question cached, with all prior provider
   processes shut down. If the first attempt did not create the cache, prime it
   through a standalone complete numerical request and record that setup
   separately. A failed/timed-out attempt is retained.

This gives **48 measured delivery hooks**, all retained. SessionStart and daemon
shutdown are recorded separately. The measured delivery event is the new chat's
first UserPromptSubmit, whose search retains the original native deadline.
Record exact stdin/stdout, SHA-256, acknowledgement, semantic state, route,
elapsed time and every provider receipt. A semantic success must have completed
the full discovery corpus; a killed provider's observed prefix is not full
coverage. Focus requests and discovery requests remain separate.

Python reports observed startup imports, model-lease wait, FastEmbed import and
constructor time, embedding-iteration/normalization time, and NumPy preparation
and scoring time in microseconds. Lazy work inside the first embedding remains
in embedding time; this does not claim an internal weights-loading breakdown.
Lean's cache/query/IPC timings are nested observations, not additive independent
phases. No encoder reply means timing unavailable, never zero initialization.

Report every size/layout/question-cache cell as a count out of three, with all
individual latencies and censored phases. Do not hide a bad cell in an overall
average. These small repeated diagnostics do not establish a general completion
probability. Before the pilot, require all three observed attempts in every
cell to complete semantic discovery and retain body delivery within five
seconds. Otherwise inspect the measured bottleneck, change the implementation
or allocation, and repeat against these same saved fixtures. This gate does not
replace the pilot's quality, safety or inclusive-token requirements.
