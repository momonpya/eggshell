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
- Qualified isolated candidate: SHA-256
  `a5fdc5d5446b92f7f90d3473ce781d204a0d81fd500abf3f3e0ab2900ed91193`.
- Three predetermined repetitions of every topic/initial-history cell for
  the candidate, plus one fresh reference per topic/repetition.
  Fresh references are reused for the first/history columns, as in the README.
- One new common seed. Every compared memory cell starts from identical graph
  bytes at the same active DB pathname. Candidate repetition 0 is the
  predeclared next common checkpoint; other
  trial outputs do not enter history. This avoids independently generated
  histories becoming an implementation confound.
- Per topic, repetitions 0, 1 and 2 use fresh then candidate. The retained lap
  uses the corresponding already recorded fresh references. Public-version
  token trials were removed at the user's direction; their consumed usage and
  interrupted observation remain in the original artifacts. The prior protocol
  and every per-attempt protocol remain archived.
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
retained. A public run that delivered no initial body is not a healthy token
control. Public code is used for delivery diagnosis with explicitly prepared
session caches, without a generation-model token arm.

Use cumulative thread `inputTokens + outputTokens` once per new thread. Cached
input is already included; reasoning is already in output. No character or
packet-byte saving substitutes for token saving. Failed acquisition/trial
usage remains in accounting, with missing usage stated explicitly.

The completed topic-1 first-use comparisons are:

| Repetition | Fresh total tokens | Candidate total tokens | Reduction vs fresh |
| --- | ---: | ---: | ---: |
| 0 | 3,050,963 | 789,335 | 74.1% |
| 1 | 2,932,984 | 1,604,261 | 45.3% |
| 2 | 3,181,936 | 978,336 | 69.3% |

These are the three predetermined topic-1 first-use repetitions, not a completed
three-topic result. The
historical README study records 76.0% first-lap and 96.4% retained-lap reduction.
Its answering model and seed differ, so the present observations alone cannot
attribute that gap to an implementation change. The MiniLM model is unchanged;
the isolated candidate changes its input segmentation and scoring, and changes
lexical terms to 2-grams. Those changes can change delivery.

The candidate's repetition 0 delivers 120,302 UTF-8 bytes of initial context in
7,227 ms. Its discovery and focus receipts both complete with no source-cache
miss, unusable record or source encoding; no foreground warm is requested.
Repetitions 0 and 1 have the identical initial packet SHA-256
`a6c99a918aac4a2149305bd1547aae96a908a423b216e36612eff22ee14017e7`,
but execute 16 and 40 tool commands. Their difference cannot be attributed to
a difference in that initial packet. Later packets and newly investigated facts
also need review. Source review finds a material target-condition error in the
candidate answers' generic `spirv` examples: the cited branch's
language-dependent alternative specifically requires `spirv32` or `spirv64`.
The original answers and history remain unchanged, and neither explanation is
accepted as source-verified correct. Fewer tokens alone do not pass adoption.
Generation is stopped in the protocol and the runner rejects new model calls
until the delivery and quality diagnosis is resolved. Existing attempts are
never replayed. The full goal remains active; the candidate is unadopted.
The fixed-input body comparisons and their limits are recorded in
[delivery-regression-diagnosis.md](delivery-regression-diagnosis.md).

Prepared public-main delivery now differs from the full candidate on all three
initial questions. A first-segment scoring control, isolated from production,
retains modern cache/warm/performance code and reproduces all three public
initial bodies. This is a causal diagnostic, not an adopted old implementation
or a recovered token result. Its separate native topic-1 preflight completes in
11,041 ms with no source encoding. Physical publication bytes change through a
derived memo and neutral journal; authoritative graph equality is audited
explicitly. The failed physical-immutability assertion remains recorded.

The original after-topic-1 checkpoint mixes public plain primary lexical terms with the
candidate's newly saved `P`-prefixed terms. Public lookup cannot find those new
postings, so its original history delivery comparisons are excluded as healthy
public controls. The first-use seed was produced by public main and has no such
mixed index.

## Matched scoring diagnosis

The first-segment control retains current full-bundle storage, DB cache/warm,
lexical indexing and performance changes, and changes only the source/query
bundle projection into numerical scoring. All compared cells use the original
public-produced seed graph bytes, prompt, source, answering model, reasoning
effort and native harness at the same active DB pathname. Its initial body is
the healthy public body's hash in all three actual native chats.

| Repetition | Fresh total | Full candidate total / reduction | First-segment control total / reduction |
| --- | ---: | ---: | ---: |
| 0 | 3,050,963 | 789,335 / 74.1% | 269,654 / 91.2% |
| 1 | 2,932,984 | 1,604,261 / 45.3% | 562,109 / 80.8% |
| 2 | 3,181,936 | 978,336 / 69.3% | 443,128 / 86.1% |

All six initial bodies match their predeclared hashes and every recorded hook
finishes within 30 seconds. The four new calls complete without recorded model
errors or reroutes; existing calls are not repeated. Source code stays unchanged.
The guard observes a maximum aggregate RSS of 2,321,856 KiB and does not fire.
Seed acquisition is not repeated. Raw data is under
`/Users/ovm/.codex/experiments/eggshell/readme-scoring-control-20261020/`.

The control beats the full candidate in every matched repetition for this one
first-use question. This supports investigating the expanded maximum-over-pairs
scoring as a token-cost regression here. It does not prove the whole historical
README gap, quality recovery, or the other topic/history cells. Answers still
lack executable Driver-test evidence; the original outputs and source-review
limitations remain. The control scores only first segments and is not adopted
as a full-context repair. Generation is stopped again after the fixed sequence.

For healthy history delivery comparison, a public-built offline helper republishes
the original 148 values into one new private DB. Authority, root order, stable
root/owner/Work/window IDs and unions are checked equal; no new seed or model
answer is generated. Its ordinary public producer creates complete plain-term
postings. Both implementations then inspect exact copies of this one prepared
snapshot. Public versus full candidate differs on all three questions; the
first-segment control equals public on all three. This is the checkpoint after
topic 1, **not** a completed retained lap. Warm/repeat validates all 2,437 cached
windows, and physical source publication bytes stay unchanged during inspection.
Artifacts are under
`/Users/ovm/.codex/experiments/eggshell/readme-history-public-index-20261020/`.

Full initial/history × three-topic × three-repetition token/quality requirements
remain, as do practical and paper requirements. No scoring control, benchmark
claim or behavior-changing repair has been adopted into production or README.

The next isolated candidate retains every encoded segment and projects each
original window to one normalized centroid, weighted by newly covered source
tokens. Its encoder runtime and stored bundles are unchanged. Numerical boundary
checks, native build and ContractAudit pass. Three zero-generation native hooks
finish semantic delivery in 13,127 / 7,842 / 8,185 ms, with zero source encoding,
explicit centroid-policy receipts, unchanged authoritative source graphs, and
clean daemon shutdowns. The maximum aggregate RSS is 1,405,824 KiB. The source
publication may gain derived memos, so only the original common snapshot is used
for subsequent measured turns. This candidate is not adopted; its total-token
and answer-quality gates have not run at this checkpoint. Artifacts:
`/Users/ovm/.codex/experiments/eggshell/window-centroid-20261020/construction-3/`.

The candidate's model turn and `egg keep` completed, but the harness's detached
daemon shutdown client returned a wait-for-exit failure after acknowledgement.
The endpoint disappeared and the saved result/usage were recovered without
another model request. Its exact model duration is retained; the lost outer
wall timer is left unavailable. Subsequent cells use a foreground manager
owned by the runner and reap it together with the shutdown client. Zero-model
checks for both executables confirm both exit 0. The original shutdown failure
and recovery are retained; the cell is not rerun or selected for token count.

## Execution

`tools/readme_benchmark.py` prepares private native environments and captures
one real turn. `tools/readme_sequence.py --stage N` runs one of the six frozen
stages and prepares its common next checkpoint. It validates matching input
graphs and reuses only completed recorded calls; a running, failed or missing
record stops the controller for inspection rather than replaying the request.
The process guard includes experiment-owned detached inference processes and
enforces the existing aggregate 3,500,000 KiB limit. Raw authentication stays
outside published artifacts. No subagent is used.
