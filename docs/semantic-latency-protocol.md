# Warm DB semantic completion measurement

Fixed before collecting results. This is a latency diagnostic of the isolated
development candidate, not a token/quality benchmark or an adoption comparison.
No generation-model calls are needed. The MiniLM model, ranking settings,
semantic-first policy and 1,500 ms semantic budget remain unchanged for the
original run archived as `baseline-1`; its protocol is immutable there.
Subsequent runs declare their compiled semantic cap with `--semantic-budget-ms`
and record it in the manifest. This argument records the implementation setting;
it does not configure the native binary.

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

## Follow-up fixed before its 48 measured hooks

Use `--fixtures` with the original dataset, fresh cell data roots and the same
48 conditions. The next candidate uses a 3,500 ms semantic cap, still limited
to half the remaining native deadline. The complete numerical request for the
1,024-source cached question took 1,221 ms outside the original cap; fresh
questions and derived focus additionally initialize an encoder. Merely giving
these nested stages 1,500 ms cannot accommodate their observed costs plus the
matching kernel. The candidate also replaces repeated page-list scans with
bounded generational hash lookup and retains verified owner metadata within
one pinned request. Full-reference identity and existing admission/selection
rules remain in place. An additional node-lookup shortcut showed no diagnostic
improvement and was removed before this run.

The completion/body/five-second gate and three repetitions per cell do not
change. This is a combined candidate diagnostic, not isolation of the budget's
causal contribution. The cached condition also reuses derived focus windows
when the fresh request produced them; interpret each purpose's telemetry.

The `allocation-1` run is retained in full: 256 sources completed, while every
1,024-source cell still failed the gate. Before another full repeat, a diagnostic
changed only the page-cache update's ownership behavior: check capacity/membership
before inserting, so the rotation branch does not retain the old table across
every insert. Preserve both candidates' generated C and all results. Its one-hook
diagnostic still failed the gate; it is not a 48-hook result. Investigate repeated
Work-posting validation before fixing the next full candidate. The same saved
fixtures, questions, 48 conditions and five-second gate remain required.

The next full repeat keeps the 3,500 ms cap. It additionally validates each
distinct Work-posting owner pair once per pinned nomination and sends numerical
windows in batches of at most 32 across document boundaries. All original
document/window positions and complete nomination/ranking remain required.
Synthetic complete-reference checks include more than 32 documents, a document
with more than 32 windows, stable tied window positions, and a late missing
window after earlier batches have scored. This next run is fixed at the same
48 hooks and uses the original saved fixtures through `--fixtures`.

The `bounded-scoring-1` repeat still failed every 1,024-source cell. A CPU
profile then found that even an unused source reader captured by the provider
response task marks the controller's page cache as shared. The next candidate
drops forbidden readers before creating that task and gives permitted pulls
their own cache on the same pinned image, including mixed/federated sources.
Standalone configured inspection (outside the measured hook set) then took
4,049 ms with a fresh question and 3,378 ms with a reused question/focus cache.
The next 48 hooks therefore use a 4,500 ms semantic cap, still limited to half
the remaining deadline. The same original fixtures, 48 conditions and strict
five-second complete-semantic/body gate remain unchanged. Failure-injection
regression allows the semantic allocation plus the original 800 ms transport
and lexical fallback allowance; that is separate from the scientific gate.
