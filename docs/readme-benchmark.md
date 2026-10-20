# README LLVM benchmark rerun

The 2026-10-20 user instruction puts this real-model benchmark before further
50,000-window diagnosis. The full paper goal remains open. Cache lifetime and
deadline repairs are not claimed to improve token reduction when the delivered
warm-DB body is unchanged.

The task is the README's Clang Driver sequence: topics 1, 2 and 3, first from a
new seed and then with accumulated memory, in independent native chats. Prompts
come verbatim from `docs/benchmarks/llvm-three-topics.json`; only `<LLVM_SOURCE>`
is replaced with the fixed source path. LLVM is commit
`6dfe1677ab8dffbc6ec13d53a1e0215d75147689`.

## Frozen comparison

- Native Codex CLI 0.145.0, Luna with `xhigh`, read-only source workspace.
- Latest public main at freeze: `51873167c11c447a0af67e73430b5ab6635b2a65`, built
  from a clean Git archive; executable SHA-256
  `959809379df896e464da5419398187b714d26fc90d87004f434a36be681bd2f3`.
- Qualified isolated candidate: SHA-256
  `a5fdc5d5446b92f7f90d3473ce781d204a0d81fd500abf3f3e0ab2900ed91193`.
- Three predetermined repetitions of every topic/initial-history cell for
  both memory implementations, plus one fresh reference per topic/repetition.
  Fresh references are reused for the first/history columns, as in the README.
- One new common seed. Every compared memory cell starts from identical graph
  bytes at the same active DB pathname. Candidate repetition 0 is the
  predeclared next common checkpoint, shared by both implementations; other
  trial outputs do not enter history. This avoids independently generated
  histories becoming an implementation confound.
- First lap order per topic: repetition 0 fresh/public/candidate, repetition 1
  fresh/candidate/public, repetition 2 fresh/public/candidate. Retained lap
  uses the same arm ordering and corresponding fresh references.
- New ephemeral native chat and independent private state per attempt;
  native memory, other plugins, web and agent tools are disabled. The only
  enabled plugin in memory arms is the vetted native Eggshell command plugin.
  Hook trust is recorded from verified installed hashes, without bypass.
- Model-call timeout 900 seconds. Failed or interrupted attempts remain;
  an existing attempt is never silently resubmitted. Unknown failure usage
  remains unknown rather than becoming zero.

The native CLI account rejected `gpt-6-luna` with HTTP 400. No usage was
reported for that rejected request. The available native CLI Luna,
`gpt-5.6-luna`, is explicitly selected for **all** compared conditions. This is
also the model in the README's CLI demo. It differs from the GPT-6 Luna label
in the three-topic historical table; historical counts are not matched controls.

Protocol and raw private artifacts:
`/Users/ovm/.codex/experiments/eggshell/readme-luna-20261020/`.
Every attempt archives its actual prompt, runner, protocol, thread metadata,
native RPC events, delivered context packets, final answer and cumulative usage.
The implementation arms also archive their original input graph hashes and
their own output DB after saving and shutting down. A completed model response
is recovered from its actual `final_answer` event; ephemeral chats do not support
`thread/read(includeTurns=true)`.

## Preparation and accounting

Source access is checked without a model: actual Driver source hashes must
match, source writes must be denied, and fresh must have no hooks. The first
read-only configuration omitted the explicit LLVM read grant. Its model run
could not investigate the source and is **not** an accepted seed. Its complete
answer, failed source DB and **400,978 tokens** remain archived. The corrected
source-access checks pass before subsequent generation.

The accepted seed uses **4,082,469 input + output tokens**. Known acquisition
cost including the denied-source attempt is **4,483,447 tokens**, plus unreported
usage for the unsupported-model rejection. Seed cost is separate from follow-up
reductions. The accepted seed's graph has a distinct identity from the rejected
source-access acquisition.

The checkpoint's 1,956 discovery/focus cache windows are completely warm.
An initial explicit path warm selected a private overlay because that path was
not the configured writable DB. Its validated semantic/lexical hint bytes were
copied into the DB-owned sidecar, excluding private ownership records, tickets
and query data. A configured writable warm and repeat, using a fresh private
state root, both validate all 1,956 windows with zero source encodes/batches.
Graph bytes remain unchanged. This establishes a DB-contained prepared input;
copying a private directory alone would not establish cross-chat readiness.

Each new common checkpoint is prepared outside measured model turns. The
candidate's native chats reuse copied DB-owned hints, with source/query probes
retained. Public main runs its actual session-owned cache behavior; the harness
does not invent DB-owned caching for that executable. Native cold/incomplete
or empty delivery is retained as observed, rather than labeled a warm delivery.

Use cumulative thread `inputTokens + outputTokens` once per new thread. Cached
input is already included; reasoning is already in output. No character or
packet-byte saving substitutes for token saving. Failed acquisition/trial
usage remains in accounting, with missing usage stated explicitly.

The first fresh topic-1 reference completes at **3,050,963 tokens**. That is one
reference observation, not a reduction rate or a completed three-topic result.
Implementation trials, all three repetitions, source-grounded answer review
and the corresponding final summaries remain in progress. No README savings
claim, production adoption or full-goal completion follows from preparation.

## Execution

`tools/readme_benchmark.py` prepares private native environments and captures
one real turn. `tools/readme_sequence.py --stage N` runs one of the six frozen
stages and prepares its common next checkpoint. It validates matching input
graphs and reuses only completed recorded calls; a running, failed or missing
record stops the controller for inspection rather than replaying the request.
The process guard includes experiment-owned detached inference processes and
enforces the existing aggregate 3,500,000 KiB limit. Raw authentication stays
outside published artifacts. No subagent is used.
