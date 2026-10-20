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

| Repetition | Fresh total | Full candidate total / reduction | First-segment control total / reduction | Full-window centroid total / reduction |
| --- | ---: | ---: | ---: | ---: |
| 0 | 3,050,963 | 789,335 / 74.1% | 269,654 / 91.2% | 458,554 / 85.0% |
| 1 | 2,932,984 | 1,604,261 / 45.3% | 562,109 / 80.8% | 529,236 / 82.0% |
| 2 | 3,181,936 | 978,336 / 69.3% | 443,128 / 86.1% | 207,446 / 93.5% |

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

An isolated full-window candidate retains every encoded segment and projects each
original window to one normalized centroid, weighted by newly covered source
tokens. Its encoder runtime and stored bundles are unchanged. Numerical boundary
checks, native build and ContractAudit pass. Three zero-generation native hooks
finish semantic delivery in 13,127 / 7,842 / 8,185 ms, with zero source encoding,
explicit centroid-policy receipts, unchanged authoritative source graphs, and
clean daemon shutdowns. The maximum aggregate RSS is 1,405,824 KiB. The source
publication may gain derived memos, so only the original common snapshot is used
for subsequent measured turns. Native preflight artifacts:
`/Users/ovm/.codex/experiments/eggshell/window-centroid-20261020/construction-3/`.

Its three fixed topic-1 first-use model trials are now complete, as shown in the
last table column. They reuse the exact same original seed graph bytes, active
DB pathname, source, question, Luna/xhigh settings, native harness and original
fresh references. All three initial packets match the predeclared centroid body
hash `932b170a0c22d8590f3a664f9e48060036892215fc2c5bacb616c58e81ae52b8`.
The candidate uses fewer inclusive tokens than the full maximum-over-pairs
candidate in every repetition. It uses more than the first-segment diagnostic
in repetition 0; that result is retained rather than hidden by the other two.

The three new calls consume 1,195,236 total tokens, with no recorded model errors
or reroutes, repeated call or reacquired seed. Cached input remains included.
All measured hooks finish within 30 seconds, with maxima 11,807 / 8,150 / 8,062 ms.
Initial semantic searches complete with zero source encoding. The guard observes
2,513,808 KiB peak aggregate RSS and does not fire. All owned daemon shutdowns
exit 0. Generation is stopped again after this fixed sequence. Raw results:
`/Users/ovm/.codex/experiments/eggshell/readme-window-centroid-20261020/`.

Source review confirms the cited target/arch test expectations, HLSL argument
translations and clang-cl language expectations. It retains a precision concern
about repetition 0's abbreviated SPIR-V condition. Driver tests still lack a
built Clang/lit configuration, and no independent quality acceptance is claimed.
The original answers remain unchanged. This is an encouraging token result for
one first-use cell, not complete quality recovery or a three-topic/history
acceptance result. The candidate remains isolated and unadopted.

The candidate's model turn and `egg keep` completed, but the harness's detached
daemon shutdown client returned a wait-for-exit failure after acknowledgement.
The endpoint disappeared and the saved result/usage were recovered without
another model request. Its exact model duration is retained; the lost outer
wall timer is left unavailable. Subsequent cells use a foreground manager
owned by the runner and reap it together with the shutdown client. Zero-model
checks for both executables confirm both exit 0. The original shutdown failure
and recovery are retained; the cell is not rerun or selected for token count.

## Continuing the fixed sequence

Stage 2 uses the already fixed after-topic-1 canonical values from the original
study, with complete public primary postings. One exact copy becomes the
centroid study's `checkpoints/stage-1`. All three repetitions use that same
publication. There is no new seed. Subsequent checkpoints use predeclared
centroid repetition 0; the other repetitions never enter history. Any later
implementation comparison must receive the same chosen checkpoint, rather than
generating an independent history for each implementation.

The sequence controller selects the study's configured active DB pathname and
reuses completed external fresh references. An incomplete attempt stops instead
of being submitted again. It checks matching question/model/effort, source
snapshot hashes and the measured initial body against native preflight. Each
attempt retains the exact executed sequence runner and its protocol hash.

Checkpoint warm uses the configured writable DB name, and the repeat uses an
independent private data root. Stage 2 validates all 2,437 windows with zero
requested encodes or batches in either pass. Its zero-generation native preflight
delivers semantic context in 8,127 ms with zero source encoding and unchanged
authoritative source data. The first preflight's header-only detection failure
is retained; the corrected check records the entire additional context,
including the preceding source-status text. It does not strip that prefix to
manufacture body equality.

Quality follows the original README study's question-level correctness and
source-support scope. Different unrequested examples are not failures, and the
original study also had no verified configured Clang build. Missing execution
evidence is reported honestly; source checks and justified qualifications remain
necessary. The broader paper experiments still require their own executable
tests or independent blind evaluations.

## Topic 2 first-lap results

All three fixed pairs complete from the same prepared after-topic-1 snapshot.

| Repetition | Fresh total tokens | Centroid total tokens | Reduction vs fresh |
| --- | ---: | ---: | ---: |
| 0 | 3,654,187 | 51,242 | 98.6% |
| 1 | 4,439,023 | 53,433 | 98.8% |
| 2 | 2,767,030 | 51,451 | 98.1% |

All measured initial packets equal the full native preflight context, including
source-status text. Initial hooks take 8,461 / 8,519 / 8,582 ms; every measured
hook remains within 30 seconds and initial semantic searches encode no source
windows. Candidate answers make no additional source-tool calls. The six new
model calls consume 11,016,366 inclusive tokens, with no errors, reroutes or
retries. The maximum aggregate RSS is 1,582,752 KiB; the guard does not fire.
The common source remains unchanged, and all owned daemon shutdowns exit 0.

Manual review supports the main mode/config/ToolChain API trace and records
qualifications. HLSL descriptions need the target-architecture condition; the
filtered original `rg` data in both the public and centroid packets lacks that
guard, so this is not a newly lost delivered guard. Repetition 1's proposed
multi-line RUN snippet also needs continuation syntax. Proposed tests are not
reported as executed or passing. No independent or overall quality acceptance
is claimed; original answers remain intact. Raw checks are in
`results/stage-2-native-audit.json` and `results/stage-2-source-review.json` under
the centroid study.

The predeclared repetition-0 output forms the next checkpoint. Explicit warm
fills its 19 new windows, and a repeat from an independent private root requests
zero work; all 2,456 windows are ready. A separate public-producer copy preserves
its 151 authoritative values, stable root/owner/window IDs and unions while
preparing complete primary postings for later public comparison. The stage-3
native preflight delivers the next question in 8,716 ms with no source encoding.
No new seed is acquired. Topic 3, the retained lap and quality gates remain open.

## Topic 3 regression and interrupted third pair

The same prepared after-topic-2 snapshot is used for every candidate repetition.
Two fixed pairs complete with poor token reductions; the positive topic-1 and
topic-2 cells do not offset this failure.

| Repetition | Fresh total tokens | Centroid total tokens | Reduction vs fresh |
| --- | ---: | ---: | ---: |
| 0 | 4,309,908 | 2,025,867 | 53.0% |
| 1 | 2,306,333 | 1,500,516 | 34.9% |
| 2 | 5,945,537 | Incomplete; at least 1,213,841 | Unknown |

The third candidate attempt has no recorded turn completion or final answer.
Its last cumulative usage report includes 1,207,467 input tokens (1,065,856
cached) and 6,374 output tokens. The final usage is unknown; the lower bound is
not a completed result or a zero-cost failure. No request is resubmitted.
Raw RPC, the exact executed runners and an explicitly interrupted DB copy are
retained. This copy is not a completed output or the next canonical checkpoint.

The disk filled during this batch, preventing both normal result capture and
the final resource-guard report. The model child's exit cause and maximum RSS
cannot be recovered from that missing report. Cleaning 28 obsolete or failed
private build directories with `lake clean` restores about 4 GiB; source files,
DBs, installed runtime prefixes and experiment logs are retained. The sequence
controller now refuses new model or warm work below 2 GiB free. This is a start
check, not a disk reservation or continuous monitor. Existing incomplete
attempts still stop without automatic retry. All generation labels are cleared.

The retained records are `results/stage-3.json`,
`results/stage-3-interrupted-summary.json`,
`attempts/stage3-candidate-r2/usage-observed.json`,
`attempts/stage3-candidate-r2/failure-recovered.json`, and
`disk-incident-recovery.json` under the centroid study. The candidate remains
isolated and unadopted. Topic 3, retained use and overall quality are unresolved.

## Diagnosing topic 3 against the public implementation

The public `main` remains `51873167c11c447a0af67e73430b5ab6635b2a65` at this
check. The warmed public implementation and first-segment diagnostic control
receive copies of the same prepared after-topic-2 snapshot and the same question.
Their Handoff text is byte-identical, with SHA-256
`8c38292d58d776a23d9763a20c96cecb95ecb7d913126852404f1da33f94ac74`.
This is an uncensored helper comparison, not a native hook latency measurement
or another generation-model token arm. A subsequent centroid run through the
same helper reproduces its actual native initial packet byte-for-byte
(`b400ef432319f610a29cb0595469968ac67741b0c4e2761ab95d5d7aaf391033`).
Both helpers and the native packet include the source-status prefix. The
public/centroid difference is therefore present at the same Handoff boundary;
it is not explained by an extra outer prefix on one side. The source graph is
unchanged. That diagnostic uses 1,240,864 KiB maximum aggregate RSS and no
generation-model calls; it is not a native deadline result.

The public text includes the beginning of `Driver::getFinalPhase`, but neither
that public packet nor the centroid native packet includes the
`OPT_fsyntax_only` condition. The stored windows contain this condition. Thus
missing delivered evidence is established, but its attribution to a new scoring
change is not. The investigation must distinguish evidence absent from the DB,
evidence stored but not delivered, and evidence already delivered but reread.
The saved comparison is `stage3-delivery-diagnosis/summary.json` and its raw
per-implementation bodies under the centroid study.

A pure lexical diagnostic also shows that `-fsyntax-only` and
`OPT_fsyntax_only` have disjoint terms, as do `final phase` and `getFinalPhase`.
That is a retrieval limitation, not proof of this token regression's cause or
authorization to adopt identifier aliases. No additional retrieval change is
implemented on the strength of these membership checks.

## Topic 3 continuation audit

`tools/readme_delivery_audit.py` reads the existing native RPC, hook output and
per-request receipts. It neither invokes a model nor modifies a DB, and it
refuses to replace an existing diagnostic. The two completed attempts show:

| Repetition | Executed commands | Pre-tool incomplete notices | Numerical failures with missing durable windows |
| --- | ---: | ---: | ---: |
| 0 | 17 | 0 | 3 |
| 1 | 36 | 19 | 15 |

All observed numerical failures have missing vectors in durable documents,
with zero source encoding in the hook. The initial 58-document publication is
warm; later failure receipts name larger publications, including 63, 70, 83 and
91 documents. One 63-document receipt has 32 absent cache probes and fails well
before the semantic deadline. This establishes a readiness gap during ongoing
publication, not a need to enlarge an expired search deadline. Background index
work has not completed for every publication visible to every concurrent search.

In repetition 1, 19 incomplete notices are published before the semantic finish
deadline. Their lexical fallback search returns an empty result that the hook
turns into a pending notice. This alone does not establish omitted new evidence:
previously delivered ranges and empty matches must still be distinguished from
undelivered material. Repetition 0 has poor savings despite no such notices, so
the continuation gap cannot explain the whole regression.

Repetition 1 executes three identical command strings twice. The file-list and
numbered-range groups have identical captured outputs; the unsorted `rg` group
does not. These are observed duplicate requests, not proof that arbitrary
search outputs are interchangeable or that skipping them would preserve quality.
The legacy shared matcher trace also has two malformed lines under concurrent
use. The audit retains those line numbers and relies on per-request numerical
receipts rather than treating the damaged trace as complete evidence.

The full result and executed auditor are saved as
`stage3-delivery-diagnosis/native-execution-audit.json` and
`native-execution-audit-runner.py` under the centroid study. Initial selection,
ongoing readiness and repeated reads remain separate hypotheses. No retrieval
change or model retry is adopted from this audit.

An additional source-line presence audit separates an initial delivery omission
from material not found in the exported stored windows. The exact line of the
`OPT_fsyntax_only` condition at `Driver.cpp:360` occurs in two stored windows,
neither initial packet, and four executed command outputs across the two runs.
The lines constructing the `TY_Nothing` action at `Driver.cpp:5328`, invoking
`ConstructJob` at `Driver.cpp:6382`, and forwarding to `getFinalPhase` at
`Types.cpp:431` are absent from the exported stored-window texts but occur in
executed outputs. These are text-presence checks, not full-range coverage or
semantic-equivalence certificates; signature absence alone does not prove a
read is necessary. Details are in `stage3-delivery-diagnosis/read-evidence-map.json`.

## Complete window order before fusion: isolated candidate

A cached-vector diagnostic separates question and source projection. It uses
the same 2,456 unique cached windows and owner domain, without encoding or
generation-model calls. With the 694-character focus suffix, the condition at
`Driver.cpp:360` in owner `v16748591830955464422` has within-owner numerical rank
11 with both first-segment projections, 26 with source-centroid projection only,
10 with query-centroid projection only, and 25 with both centroids. These are
window-order diagnostics, not complete graph rankings, deliveries or token
results. Inputs, domain, cached scores and exact auditor source are retained in
`readme-window-centroid-20261020/stage3-window-projections`.

An identifier-component prototype improves that window's lexical rank from
69 to 10, but cannot bring it back into the focused 16-window result. The
provider has already discarded its numerical position before rank fusion.
Another method-header window even leaves the focused result when the expanded
lexical terms give more support to the already retained numerical windows.
Component hints alone are not adopted; their source files, checks and failed
ranking outcome are archived privately with source hashes.

The next isolated candidate retains every already computed numerical window
position until focused evidence fusion. It sorts the accumulated positions
once, and still retains at most 16 final focused cues. Discovery's 16-window
hint limit is unchanged. Ranked hints are checked against the original
document's finite window domain; focused replies must contain the complete
window permutation. Source repair remains a separate capability bounded to
32 windows. Neither the encoder, stored vectors, lexical grammar nor equality
rules change.

The constructor is `tools/window_order_candidate.py`. Build artifacts are in
`/Users/ovm/.codex/experiments/eggshell/window-order-20261021/construction-2`.
The runtime SHA-256 is
`d6a653aca67a51ddce327558dce812fa9b8c972aa562467203e773fb0c46495d`.
Build, `ContractAudit` and rank-directory tests pass. Boundary checks reject
foreign, repeated and omitted orders, retain the 32-window repair restriction,
and validate a 100,000-position hint with hash-based distinctness. That last
check is not a DB-size latency gate. A 65-window regression fixture demonstrates
that a strong lexical match beyond the early numerical cutoff can return while
the final cue count remains 16. An initial compilation proof failure and a test
fixture syntax repair remain recorded. Maximum build aggregate RSS is
2,840,336 KiB; the guard does not fire. Effective source hashes are retained
after the fixture repairs.

On the same prepared after-topic-2 DB and question, the uncensored helper and
actual native initial hook produce identical text with SHA-256
`b3c9e6499ce045a98a4bd6e1f2a0c47c0bece60cd67ffa310c613388b9a0a357`.
The `getFinalPhase` opening is present again, as in the warmed public packet;
the decisive `OPT_fsyntax_only` condition remains absent. This partial recovery
does not establish restored answer quality or token savings.

The native hook completes semantic delivery in 14,977 ms with zero source
encoding, unchanged authoritative graph values and clean client/daemon shutdown.
Its guard observes 1,426,768 KiB maximum aggregate RSS. This is one topic-3
readiness check, not the complete deadline gate for all topics or retained use.
The result is
`/Users/ovm/.codex/experiments/eggshell/readme-window-order-20261021/native-preflight-topic3/result.json`.
At this preflight boundary no generation-model call was made or scheduled.
The subsequent fixed cohort below does not qualify the candidate for adoption.

## Complete-window-order cohort: no confirmed improvement

The predeclared three topic-3 repetitions restore the same prepared
after-topic-2 publication, question, source and Luna/xhigh settings. They reuse
the three completed fresh references; no seed is acquired again.

| Repetition | Fresh total | Candidate total | Reduction vs fresh | Maximum completed hook |
| --- | ---: | ---: | ---: | ---: |
| 0 | 4,309,908 | 1,867,149 | 56.7% | 9,238 ms |
| 1 | 2,306,333 | 1,997,323 | 13.4% | 10,995 ms |
| 2 | 5,945,537 | unknown; interrupted | unknown | only partial records |

The previous centroid reductions for repetitions 0 and 1 were 53.0% and 34.9%.
The new candidate has no confirmed improvement and remains **unadopted**.
These topic cells are reported separately; the historical first-lap target is
not redefined as a new per-topic threshold. This incomplete cohort cannot prove
that an entire lap, retained use or answer quality has recovered.

The third turn stops at the old capture reader's 1 MiB response limit after
23.3 seconds. It has no final answer or reported token usage and is not
resubmitted. The completed calls report 3,864,472 inclusive tokens. The exact
new cohort total is unknown and at least that large; the failed turn is not
charged as zero. The earlier centroid interruption and its known 1,213,841-token
lower bound remain separate. The guard's maximum aggregate RSS is
2,958,848 KiB, without a guard trigger. All three actual initial packets equal
the preflight body, including the interrupted turn. That equality does not
make the third model turn complete.

Static source review preserves qualifications rather than approving quality.
In particular repetition 1's statement about `-x` after an input needs the
**last input** restriction. The HLSL discussion also needs the full OS and
architecture guard. No LLVM build or executed Driver-test result is available.
The native audit observes 37/29 executed commands, 14/7 pre-tool incomplete
notices and 18/3 numerical failures with missing durable windows in the two
completed trials. These continuation gaps and initial selection remain distinct
diagnostic questions.

`results/topic3-window-order.json`, `topic3-cohort-accounting.json`,
`topic3-initial-packet-audit.json`, `source-review.json` and
`topic3-native-audit.json` retain these observations under the window-order
study. `results/public-delivery-diff/` retains complete diffs against the
warmed public implementation. Its graph files and question are identical
across all four inspected implementations: public equals the first-segment
control, and differs from both centroid and complete-window-order candidates.
All include the source-status prefix. This comparison concerns the Handoff
boundary, not public native latency or token savings. The next diagnostic is
the still-unmeasured topic-3 public-equivalent control, before another retrieval
policy is added.

## Capture failure and storage recovery

The unbounded test search observed immediately before the capture failure
produces 1,813,239 bytes when reproduced without a model. The old reader did
not retain the oversized RPC frame, so its exact method and contents cannot be
claimed from that reproduction. The benchmark reader now admits responses up
to 32 MiB and transcripts up to 256 MiB, using incremental byte buffering. The
metadata-only preflight retains its 1 MiB/32 MiB limits. Configuration response
redaction, bounded admission and the no-generation fence remain enforced.
Twenty controls pass. Five completed actual RPC traces and the reproduced large
output replay without lost or changed decoded messages. This replay invokes no
answering model. A future generation protocol must freeze the exact transport
hash before creating an attempt. The failed historical turn remains failed.

`transport-diagnosis/` retains the old executed transport, replay records,
controls and failure reproduction. No generation is performed with the repaired
transport at this recording boundary; historical and future harness hashes must
remain distinguishable.

Before this cohort, the stopped synthetic 50,000-window fixture's 5,562,013,928-byte
page file was archived with reversible compression. The expanded archive and
all 13 identical copies were checked against the original SHA-256 before the
raw files were removed; heads, derived data, source and logs remain. The archive
is 218,969,652 bytes. The restore helper is
`readme-window-order-20261021/obsolete-build-cleanup/restore-pages.py` under the
experiment root. Restore it before resuming those fixtures. This is offline
storage recovery, not a production compaction change or a 50,000-window gate.
README model inputs are unaffected.

## Public-equivalent initial-delivery control on topic 3

The first-segment diagnostic uses the existing modern DB cache, warm, deadlines
and native harness. It is isolated and never proposed as a production repair.
Warm and repeat from independent private roots confirm all 2,456 windows valid,
with zero requested encodes and unchanged authoritative publication. Its native
initial preflight reproduces the warmed public text in 11,155 ms. The fixed
three-call cohort restores the same prepared after-topic-2 graph before each
call, with the same question, source and Luna/xhigh settings. The three fresh
references are reused. No candidate output enters the common history.

| Repetition | Fresh total | Diagnostic total | Reduction vs fresh | Maximum hook |
| --- | ---: | ---: | ---: | ---: |
| 0 | 4,309,908 | 1,368,379 | 68.3% | 7,149 ms |
| 1 | 2,306,333 | 2,255,083 | 2.2% | 6,786 ms |
| 2 | 5,945,537 | 2,324,915 | 60.9% | 7,096 ms |

All three actual initial bodies equal warmed public SHA-256
`8c38292d58d776a23d9763a20c96cecb95ecb7d913126852404f1da33f94ac74`.
This does not prove that subsequent hook bodies match public. It also does not
establish recovered savings: matching the initial public packet is insufficient
in this cohort, and returning to first-segment scoring is not an adopted repair.
The other initial public/candidate differences remain real. Do not pool this
diagnostic with centroid results to describe a single implementation's lap.

The cohort reports exactly 5,948,377 new inclusive tokens, with cached input
included, no errors, reroutes, failures or resubmissions and no new seed cost.
All hooks finish within 30 seconds; maximum aggregate RSS is 2,335,328 KiB,
without a guard trigger. The repaired capture transport and runner hashes are
frozen for all three calls. Earlier fresh/treatment records have different
capture hashes; this is a qualified diagnosis, not an adoption comparison under
an identical harness. These real traces have maximum response size 123,565
bytes and do not themselves exercise the new large-response limit.

The same static source criteria were frozen before these three calls. The
third answer incorrectly says later `-S` or `-c` overrides `-fsyntax-only`;
`getFinalPhase` selects Compile before Backend/Assemble independently of their
relative argument order. The second answer also puts config processing before
ordinary argument parsing, contrary to `BuildCompilation`. Other positional
`-x` and HLSL-scope qualifications remain. No independent or executable LLVM
quality acceptance is recorded. The control remains unadopted.

Continuation audit observes 11/19/19 executed commands, 2/7/5 pre-tool incomplete
notices and 5/9/7 numerical failures with missing durable windows. Thus a warm
58-document initial publication does not establish readiness for every later
publication. The next diagnostic uses retained publication parent heads and
receipts to compare continuation selection/readiness with public behavior,
without adding another retrieval policy or more model calls first. Exact
continuation parity is still unverified.

A separate no-model packet audit classifies explicit stored Work prefixes.
Public and centroid each deliver one investigation answer and 22 Bash
observations. The answer occupies 8.6% versus 6.7% of rendered result-part bytes;
these include captions and provenance and are **not token savings** or a
content-only ratio. This topic does not support the hypothesis that historical
answers crowded out observations. Owners and original excerpts change instead.
The complete-window-order packet also contains a stored `update_plan` operation.
Full graphs without excerpt contexts are counted separately from fragment
characters. Both initial parser assumptions that failed are retained with the
corrected diagnostic.

Records are under
`/Users/ovm/.codex/experiments/eggshell/readme-public-equivalent-20261021/`:
`results/topic3-diagnostic.json`, `topic3-cohort-accounting.json`,
`source-review.json`, `all-three-native-audit.json`, `summary.json`, and
`packet-composition/result.json`. The protocol has generation disabled and an
empty schedule. Topic 3 diagnosis, retained use, overall quality and the full
practicality/paper goal remain open.

## Retained publication and index-completion diagnosis

The poor public-equivalent repetition 1 retains 22 publication heads, revisions
1–22, spanning 58–78 documents. Read-only domain exports pin those actual roots
against the retained append-only page file. Each failed search is linked to its
recorded proposed command through native hook IDs, identical output, and nearby
monotonic receipt times. Document and window-reference counts must resolve to
one exported domain digest; physically different neutral revisions may share a
domain. Original graph files remain unchanged. These are recovered source
domains, not reconstructed historical cache states or complete native replay.

In the first failure, 107 required discovery-window cache files have mtimes
after the end of the hook's integer completion second. The native receipt
reports 32 absent probes before failure, not an exhaustive count of every
missing window. Earlier mtimes alone do not certify historical availability.
Both the source-domain linkage and conservative timestamp limits are retained
in `readme-continuation-audit-20261021/receipt-domains-and-cache-times.json`.

The first failed 59-document publication is republished on a private copy by
the public producer, preserving authoritative values, root order, owners, Work
IDs, windows and unions. Both implementations receive that same prepared graph,
original question, recorded proposed Work and the identical 207 initial-Handoff
claims. Fully warmed public and first-segment-control bodies are byte-identical:
19,516 bytes, SHA-256
`9b2841c78d60391c70447b157a1bdd48caf7a345d616a7417fcb5b7ef59117d1`.
The 22,699/5,955 ms helper times are uncensored diagnostics, not native deadline
measurements. The later native delivery ledger and staged state are not
reconstructed, so this does not prove that this exact body would have been
delivered historically. The saved case is `first-failure-comparison/` under that
study. `tools/DeliveryAudit.lean` now accepts an explicit proposed Work and claims
for this controlled comparison; its original prompt-inspection mode remains.

The drain can compute its warm hint from an older head before the worker pins a
newer publication. The old worker indexes original windows and removes valid
tickets before separately applying that hint to full warm. A false stale hint
can therefore acknowledge a new owner's ticket while its focus view is cold.
The isolated producer uses one existing `Warm.runTarget` path for both views and
removes validated tickets only after that path succeeds. Its single index claim
and encoder belong to warm, avoiding a nested claim or a second encoding path.
Invalid tickets remain quarantined and provider failure retains valid tickets.

`tools/prepare_complete_index.py` constructs the candidate from the frozen
centroid baseline. The only changed pre-existing source file is `Worker.lean`;
the new `tools/IndexCompletion.lean` supplies the producer. Handoff, numerical
ranking, encoder, lexical grammar and equality source bytes are unchanged.
The runtime is
`57cceba86ee4b1e00bb35f0289ee0766b270c636fe47379e53ae1fde3e2d03cb`.
It remains isolated and unadopted.

The real worker is exercised on the same retained 59-document input, initially
with only the preceding publication's vectors:

| Worker condition | Ticket acknowledged | Missing focus windows after acknowledgment |
| --- | ---: | ---: |
| Existing producer, `warm=false` | 1 | 1 |
| Complete-window producer, `warm=false` | 1 | 0 |

Explicit warm repairs the old producer's remaining window. At that complete
boundary all 2,564 cached files match the candidate byte-for-byte. Provider
failure leaves the ticket in place; a foreign authority is quarantined with
the injected bytes retained, without encoding. All source graph files remain
unchanged. The old partial index takes 27,392 ms plus a later 2,767 ms warm;
the candidate's complete index takes 29,382 ms. These single background-worker
measurements do not establish a speed gain or satisfy a native-hook gate.

Build and ContractAudit pass. Construction 1's diagnostic IO-type error and
construction 2's missing library registration remain recorded. Construction 3
is the successful effective source. Its initial native topic-3 hook completes
in 12,122 ms with zero source encoding, reproducing the centroid packet
`b400ef432319f610a29cb0595469968ac67741b0c4e2761ab95d5d7aaf391033`.
This is preservation against centroid, **not public parity**.

Recorded observations are then supplied to real native hooks without rerunning
the LLVM commands or invoking an answering model. After an explicit 8,665 ms
wait for background warm, the new 59-document publication has all 2,565 required
window records. The second pre-tool search completes semantic discovery on 59
documents and focus on 58, with zero source encoding; every hook is below 30
seconds. This is a different captured observation fixture from the 2,564-window
worker test and does not prove readiness without that external wait.

The initial report accidentally used an initial-prompt-only receipt selector
for continuation assertions. Original reports and executed scripts are kept;
the corrected report matches the second sequential PreToolUse's captured input,
output and receipt, without repeating any request. The no-wait case actually
searches 58 durable documents plus one staged observation, encodes staged source
for 1,097,198 microseconds, and fails semantic discovery before lexical fallback.
The waited reply is empty; the no-wait reply is also empty after reconciliation.
Neither publishes an incomplete notice in this fixture. This is not evidence
that necessary material was omitted. It exposes publication/staging and duplicate
encoding as unresolved concerns beyond the repaired ticket-completion invariant.

One ticket survives no-wait shutdown. A separate daemon with no pending turn
recovers it, validates all 2,565 window records and removes it without changing
the source graph. The partial DB and state before recovery are archived. All
these steps use zero answering-model calls; maximum guarded aggregate RSS is
1,832,752 KiB. Token savings, answer quality, immediate continuation readiness,
remaining adoption cells and the full goal are unproven. The candidate stays
unadopted, with generation disabled and no scheduled model calls.

Records are under `complete-index-20261021/construction-3/results/` and
`checks/`, plus `readme-complete-index-20261021/native-preflight-topic3/`,
`native-continuation/`, `native-no-wait/`, `receipt-selection-correction.json`,
and `standalone-recovery/` in the experiment root. The next investigation is the
staged-observation/save/index boundary, before another retrieval policy or more
answering-model trials.

## Execution tools

### Shared native continuation demand versus public main

**Validity correction:** this retained continuation comparison does not establish
native delivery parity. Rebuilding the private graph generated another DB ID,
but the initial advisory frontier still referred to the original
`68898cd9…` source. The prepared source was `93fef5d6…`. Advisory closure checks
both the literal question and DB identity, so old owners were reopened in every
condition. The same issue affects the preceding `first-failure-comparison`.
The raw numbers below remain observations of that foreign-source demand;
they must not be used to attribute extra native context or token regression to
the candidate. Each artifact now has a separate `validity-correction.json`.
The initial no-ledger comparisons and the matched native token cohort retain
their separate validity.

The public main ref was rechecked as `51873167c11c447a0af67e73430b5ab6635b2a65`.
`tools/DeliveryDemandAudit.lean` and `tools/compare_continuation_demand.py`
extend the first-failure comparison to include the observed native Outcome,
staged values, native target extraction and the publisher's delivery
reconciliation. Every implementation receives identical explicit demand data
and the same path and authoritative bytes of the fully warmed 59-document DB.
No answering model or LLVM command is executed.

The retained attempt has an acknowledged initial offer, an empty first pre-tool
reply and an empty first post-tool reply. The latter records one native Outcome
in history. This yields 208 claims, rather than the preceding diagnostic's 207.
The first captured tool has no source certificate, so it produces two staged
roots; both are checked as already published. Target extraction returns `none`
for this command in every implementation. All these inputs are compared
structurally, including the serialized staged values, rather than by counts
alone. Later history and historical asynchronous scheduling are not reconstructed.

| Implementation | Final body bytes | Exact body SHA-256 |
| --- | ---: | --- |
| Warm public main | 19,516 | `9b2841c78d60391c70447b157a1bdd48caf7a345d616a7417fcb5b7ef59117d1` |
| First-segment diagnostic | 19,516 | `9b2841c78d60391c70447b157a1bdd48caf7a345d616a7417fcb5b7ef59117d1` |
| Complete-index centroid candidate | 32,361 | `fecca1f465b18421b47723c32ff23beb9c0d35f3eb2b4ba37425d820cea383a5` |

Raw Handoff text and reconciled text match within each implementation in this
case. Public main and the first-segment control have four observation parts.
The centroid candidate retains those four owners with different excerpts and
adds four owners: a prior answer, a stored plan and two Bash observations. Its
common owners also omit ranges present in public main; this is not simply the
same public body with extra text appended. Neither packet's presented fragments
contain `OPT_fsyntax_only`. Content differences and byte counts are not token
savings, and do not by themselves establish which answer would be correct.

The inference that this continuation discrepancy persists under healthy native
delivery is withdrawn because of the foreign-source frontier above.
The first-segment control's equality
on this single boundary does not establish full continuation parity or make
that control an adopted repair. The fixed-history comparison also does not
simulate the different future histories generated by the two initial packets.
All candidates remain unadopted; the fresh-relative inclusive token and quality
gates remain open.

Helper times are 22,403/7,561/8,986 ms and are uncensored diagnostic times, not
native-hook deadline measurements. Guarded aggregate RSS peaks at 1,763,632 KiB.
Retained setup failures cover an assumed ack file on an empty reply, an incorrect
assertion about the public publisher's qualified reconciliation method, a missing
`ToJson Value` instance in the helper, and an incorrect three-root assumption
for a tool without a source certificate. After correcting the last assertion,
the completed public inspection was reused without repeating its command;
both original and resumed runners and all raw outputs remain available.

Evidence is in `readme-native-demand-parity-20261021/inspection-4/`: the protocol,
shared demand, three raw/final packets, summary, packet owner differences and
full text diffs. Postprocessing source and the unchanged original summary hash
are retained separately. Source DBs, LLVM, frozen runtimes and production code
remain unchanged. This result does not narrow the native regression's cause or
establish restored savings.

### Preparing saved observations before semantic continuation

The next isolated candidate waits for the existing save/index producer before
starting semantic lookup on observed current-turn work. This applies only to
the built-in numerical provider and a writable DB in the captured read set.
It reads warm metadata and checks exact **live root** membership; an interned
but retracted node is insufficient. Read-only profiles, custom providers and
lexical lookup keep their existing path. The wait never saves, encodes or drops
a staged value. Search rechecks the live turn, epoch, enabled state and delivery
claims after waiting. Every actual cache row and source certificate still goes
through the existing search checks.

At most one third of the remaining overall hook window is assigned to this
preparation. The manager still enforces its semantic cutoff and hard deadline.
If preparation remains incomplete, semantic lookup returns pending before
starting a numerical provider, and the existing lexical fallback receives the
unchanged staged and saved candidates. A `source-readiness` receipt records the
observation count, outcome, wait duration and original deadline without source
or question text. The pure wait-deadline bound is proved in Lean.

`tools/prepare_source_readiness.py` constructs the candidate from the frozen
complete-index parent. Construction 1 retains an unused-binding build failure;
construction 2 is a working draft; construction 3 strengthens node lookup to
the existing checked live-root lookup and is the final tested source. Build and
ContractAudit pass. Its runtime is
`19affc5411fbebb89f26373b00b9db77566b9c0a973dfdbd023b677a0e4c7745`.
Worker is the only changed pre-existing library source; build registration and
the new module are additional changes. Handoff, ranking, lexical grammar, Warm,
MiniLM and the embedding runtime bytes remain equal to the parent.

Native hooks receive the same saved snapshot, question, session/turn IDs and
captured observations. No LLVM command or answering model runs. Two captured
observation fixtures are used; their asynchronous historical schedule is not
recreated. For the final source:

| Observation fixture / condition | Internal preparation | Whole continuation hook | Semantic route | Source encoding during search |
| --- | ---: | ---: | --- | --- |
| r0, immediate | 7,596 ms | 13,005 ms | completed | 0 |
| r1, immediate | 9,248 ms | 13,765 ms | completed | 0 |
| r1, index claim held | 9,608 ms | 10,597 ms | pending, then lexical | numerical provider not started |

The immediate r1 parent encodes staged source for 1,334,785 microseconds before
semantic failure and supplies a 7,571-byte lexical body. The candidate completes
semantic search and sends no new body. The same parent, given an explicit
9,047 ms external warm barrier, also completes semantic search with the exact
same empty stdout as the candidate. Thus the empty result reproduces that
parent's healthy prepared behavior; it is not proof that the lexical additions
are unnecessary for answer quality. When the index claim is held, the final
candidate's complete stdout, including the 7,571-byte body, matches the
immediate parent's lexical reply exactly. Both branches preserve their actual
native outputs in the records.

The final r0 reply also matches its parent's reply. All initial bodies reproduce
the centroid packet `b400ef432319f610a29cb0595469968ac67741b0c4e2761ab95d5d7aaf391033`.
These are parent-candidate checks, **not public-main delivery parity**. The
previous public-main discrepancy remains open. The final candidate has 15 native
hook calls across these three cases. Including draft and parent controls there
are 50 native calls, all below 30 seconds, with maximum aggregate RSS
1,984,288 KiB. There is no claim of faster overall replies: successful semantic
completion waits longer than the parent's early lexical fallback.

Evidence is in `source-readiness-20261021/construction-3/` and
`readme-source-readiness-20261021/`, especially `final-r0/`, `final-r1/`,
`r1-baseline-ready/` and `combined-summary.json`. Original source DBs, LLVM,
production runtime and prior raw records remain intact. Token savings, quality,
other adoption cells and the full Phase 0–6 goal remain unproven; the candidate
is isolated and unadopted, with no scheduled answering-model trials.

### Fixed token diagnostic for source readiness

`tools/readiness_token_cohort.py` prepares a new matched topic-3 first-lap
diagnostic: fresh, the complete-index centroid parent, and the live-root
readiness candidate, each three times. Order is balanced before any model call:
fresh/parent/candidate, parent/candidate/fresh, candidate/fresh/parent. Both
memory conditions receive the exact same prepared after-topic-2 graph and
portable cache at the same active DB path. No output trial enters common history.
The answering model stays `gpt-5.6-luna` with `xhigh`; MiniLM is unchanged.
All nine new calls use the same current runner and transport. The public-main
token arm is absent, and older failed or differently captured calls are not
comparison arms in this cohort.

Preparation completes without answering-model calls. Both installed runtimes
pass native initial-hook preflight in 11,660/11,180 ms, with source encoding 0
and the same centroid packet `b400ef4…`. Both complete portable cache preparation
and repeat without encoding. LLVM reference-file hashes match the fixed source
review criteria. These checks do not establish token savings or answer quality.

The frozen runner records inclusive input plus output, including cached input;
every submitted attempt is accounted for, and missing final usage remains
unknown. A pre-existing incomplete attempt cannot be resubmitted. A nonblocking
cohort lock prevents concurrent drivers. Aggregate RSS is guarded at 3,500,000
KiB; new trials require 4 GiB free and the process guard stops at 2 GiB free.
Exact driver, transport, runner and guard hashes are fixed before generation.

Space preparation removes only regenerable build products from 11 failed
constructions and compiler intermediates from 31 older copies. Forty-five unique
generated test executables are stored once each in lossless gzip archives with
verified SHA-256 and their original path/mode inventory. A selective restore
script restores one exact executable without expanding all copied binaries.
Runtime binaries, source DBs, source files and raw trial records are retained.
The inventory is `benchmark-build-cache-cleanup-20261021/` in the experiment root.

The new study is `readme-readiness-tokens-20261021/`, with separate private
environments for all three conditions, the frozen nine-call order, source
criteria and the common input. This is causal diagnosis of readiness on the
problematic cell, not the complete adoption test. Topic 1/2, retained-lap cells,
answer quality and public delivery differences remain open; no candidate is
adopted on the basis of this preparation or this cell alone.

The first repetition completes normally in all three conditions:

| Condition | Inclusive tokens | Saving versus its fresh reference |
| --- | ---: | ---: |
| Fresh | 4,661,871 | — |
| Complete-index parent | 1,746,693 | 62.5% |
| Source-readiness candidate | 1,976,254 | 57.6% |

The candidate consumes 13.1% more tokens than the parent in this repetition.
Its semantic searches complete 18 times with no pending result, while the
parent has 10 completions and 34 pending results. The candidate also delivers
fewer context bytes: 121,748 versus 149,929. Neither semantic completion nor
less delivered text establishes a token improvement. This one repetition does
not identify a unique cause, and answer quality has not been accepted.

All reported usage includes cached input and output; no API errors or model
reroutes occur. Known consumption for these three new turns is 8,384,818 tokens,
with no unknown final usage. The first driver stops at the 4 GiB disk check
before dispatching repetition 1, after all three turns finish. It does not fail
or resubmit a model turn. Additional generated diagnostic helpers are archived
losslessly, with exact path, mode and SHA-256 inventories and a selective restore
script. Runtime binaries and raw records remain present. After reclaiming space,
the unchanged frozen driver resumes only the remaining six calls, in the
original order. `interim-r0.json` retains the provisional result; the full three
repetitions, other adoption cells and the public delivery discrepancy stay open.

All nine fixed calls have now completed, with no model turn resubmitted:

| Repetition | Fresh tokens | Parent tokens | Readiness tokens | Parent saving vs fresh | Readiness saving vs fresh | Readiness increase vs parent |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 4,661,871 | 1,746,693 | 1,976,254 | 62.5% | 57.6% | 13.1% |
| 1 | 3,345,848 | 1,679,536 | 2,189,581 | 49.8% | 34.6% | 30.4% |
| 2 | 3,566,951 | 1,056,259 | 1,377,704 | 70.4% | 61.4% | 30.4% |

The readiness wait candidate is rejected: inclusive tokens increase in all
three repetitions. All nine final usages are known, totalling 21,600,697 tokens;
there are no API errors or model reroutes, no new seed acquisition, and all hooks
finish within 30 seconds. The resumed six-call guard peaks at 2,486,256 KiB.
`analysis-current.json` retains every row and its raw-record hashes. Answer
quality remains unaccepted. This topic-3 first-lap diagnostic compares isolated
modern candidates; it does not compare public-main tokens or establish recovery.

Generation is closed. The next priority is the existing warmed public-main
delivery comparison, using the same saved graph, question and delivery state.
Initial packets already differ on all three topics, and the controlled native
continuation demand above has been invalidated because its advisory receipts
refer to another source DB identity. A new question/native routing experiment
is held aside; neither its build nor native checks authorizes another token
cohort or production adoption before the public delivery discrepancy is resolved.

### Source identity and staged-state checks for continuation diagnostics

`tools/compare_delivery_sequence.py` now follows the 19 captured native
observations through 38 delivery points per condition. Each point uses the same
private publication in all conditions. Each condition keeps its own initial
packet and subsequent acknowledged claims. This is a controlled sequence through
the real delivery/reconciliation functions, without answering-model calls or
LLVM command execution; asynchronous scheduling and native deadlines are not
replayed.

The private publications are rebuilt with the public producer. Before reusing
an advisory frontier, unchanged authoritative values, root IDs/order and windows
are verified. `tools/advisory_claims.py` explicitly rebinds only that frontier's
source DB ID to the verified private publication and back to the logical source
for the next step. Observation and completion keys remain byte-identical. The
Lean helper rejects a frontier that does not belong to its pinned source.
The original 151-root frontier is dense, and all retained subsequent publications
have zero root removals; the verified retained insertion order therefore also
preserves the ordinal meaning of that frontier.

The first diagnostic also incorrectly required every staged value to be
published. Checkpoints save individual observations, while the active staged
graph includes a combined open All edge. It now retains that edge, including
before the first observation, and checks publication of observed native
Outcomes separately. Tool order follows native receipt filenames, matching
`loadToolReceipts`, rather than completion time.

`replay-1` retains the failed staged-prefix assertion; `replay-2` retains the
run stopped after confirming the foreign-DB receipt. All 20 private publications
and their completed warm checks are reused by `replay-3`; every warm check has
zero missing/invalid windows and zero encoding batches. After fixing the source
binding, the first pre-tool and post-tool responses are empty in all three
conditions, replacing the spurious re-delivery above. The resource guard stopped
`replay-3` after 32 complete points per condition; their bodies match across all
three conditions. The retained `partial-summary.json` records that original
incomplete run; it is not rewritten as a success.

`replay-3/resume-1` then verifies and reuses all 97 completed helper calls,
including the one extra completed public point. It dispatches only the 17
unfinished calls. Inputs, original partial results, helper/runtime hashes and
acknowledged claims are checked without rebuilding or warming again. The
unconfirmed prior control call and interrupted active DB remain preserved.
All 38 points per condition now complete, with byte-identical bodies across
public, first-segment control and the isolated complete-index centroid runtime.
There are nine nonempty replies per condition, all source-status metadata;
completed and blocking counts are zero. No old source excerpt is re-offered in
this fixed sequence. The selected `415bcc2…` benchmark candidate is unchanged;
this existing diagnostic's centroid condition is the Worker-only repair
`57cceba…`, not a new selected benchmark variant.

The resume makes zero answering-model calls. Its guard peaks at 382,224 KiB,
exits successfully and does not trigger. This controlled warmed sequence does
not establish historical asynchronous scheduling, native deadlines, token
recovery, full benchmark parity or adoption. Initial packet differences remain.

The separate identity audit of all six memory-enabled model trials in the
completed nine-call readiness cohort finds no foreign advisory source. Its
three-repetition negative token result remains valid. Exact evidence is in
`readme-readiness-tokens-20261021/results/source-identity-audit.json` and
`readme-delivery-sequence-20261021/` in the private experiment root.

The publication-boundary policy explains why initial omissions are not repaired
by simply reranking old advisory owners during the same request. Once the first
packet is acknowledged, older root positions for that exact question and source
DB are closed to further advisory offers, including original text omitted from
the packet. This is publication metadata, not an assertion that omitted text
was delivered or that its Work is complete. Independently grounded native
operations remain eligible. Public main and the selected centroid implementation
have byte-identical `AdvisoryFrontier.lean` policy source. The actual topic-3
trial's retained final state contains the original DB's frontier at root 151;
final state alone is not a record of every event's timing. Source references and
these scope limits are in `resume-1/boundary-policy.json`.

Before resuming, 18 stopped diagnostic executables are archived into nine
content-addressed gzip files. Every expanded SHA-256 is checked before deleting
the generated executable; the exact path/mode inventory and a one-path restore
helper are retained in
`benchmark-build-cache-cleanup-20261021/sequence-helper-archives/`. Actual free
space rises by 653,156,352 bytes at that boundary. Original DBs, source, raw logs
and runtime binaries remain present. This is storage recovery for diagnostics,
not production compaction or an experiment result.

### Trace relevant memory before another model experiment

Token variance alone does not establish a retrieval effect. Before another
cohort, trace the facts needed by the question through the original saved DB,
actual hook body, subsequent source reads and answer. Separate genuinely new
evidence from saved evidence that was omitted, and from delivered evidence that
was investigated again. Then evaluate inclusive tokens and answer quality under
the matched protocol; do not infer improvement from a smaller packet.

An offline audit reconstructs all 58 topic-3 input documents from their
overlapping, content-hashed windows, checks the recorded input graph hashes and
reads the actual packets and RPC command results of the completed trials. It
finds the following concrete cases:

| Relevant evidence | Present in saved DB | Actual candidate delivery | Subsequent source reads |
| --- | --- | --- | --- |
| `Driver.cpp:350–392`, including `-fsyntax-only` selecting the Compile phase | Complete source excerpt present | Required branch absent in both completed trials, including continuation packets | Present in both trials' command outputs |
| `Driver.cpp:3131–3135`, warning for `-x` after the last input | Complete source excerpt present | Required condition absent in both trials | Present in both trials' command outputs |
| Raw `getToolChain(*UArgs, ...)` selection | Saved source present | Call present in both initial packets | Included in one trial's further investigation; this alone does not prove the wider read was unnecessary |

Both completed trials' actual initial receipts report completed semantic search;
discovery and focus each hit all 2,400 source windows with zero absent or unusable
vectors. These initial omissions are not a cold-cache or search-timeout result.

The warmed public initial diagnostic also omits the first two conditions.
Those omissions are therefore not evidence of a candidate-specific regression.
Conversely, exact source signatures for the no-output Compile action, final
`ConstructJob` call and `x-args.c` expectation are not found in the exported
input evidence. This bounded absence does not prove all equivalent knowledge
was absent or all later reads were necessary.

Topic 2 has a useful contrasting observation: all three actual memory-enabled
answers complete without any additional tool execution, at
51,242 / 53,433 / 51,451 inclusive tokens. This is consistent with saved evidence
avoiding repeated investigation; formal answer-quality acceptance is still open.
The audit does not attribute an exact token amount to an individual memory fact.

Evidence and the executed audit are in
`readme-memory-reuse-20261021/{audit.json,executed-audit.py}`. This analysis makes
zero answering-model calls and executes no LLVM command. The selected future
comparison candidate is the original `415bcc2…` runtime; changing variants
during comparison is not permitted. A future public/candidate comparison uses
the same saved input, questions, `gpt-5.6-luna/xhigh` and harness in both arms.
The first-use and second-lap topic-1/2/3 cells still require matched repeated
evaluation after this evidence tracing; the second lap has not run. Generation
remains closed while the interpretation and quality gaps are investigated.

### Delivered source facts in the topic-2 answers

The next offline audit uses the exact **before-topic-2** export. Its head/pages
hashes match all three trial input records. All content-addressed windows are
accounted for; the 57 original documents are reconstructed, and the one later
topic-2 answer is excluded. No later evidence is used to infer prior knowledge.

Two concrete source facts have matching original evidence, actual delivered raw
anchors and statements in all three answers: mode selection before ordinary
argument parsing, and `/clang:` pass-through reparsing in ordinary Clang mode.
The `-dumpmachine` source call is delivered too and appears in two answers.
Config-before-ToolChain is supported by the original source, but the full raw
anchor set is not delivered; do not count it as the same complete raw-code trace.
These matches establish textual support, not the model's internal attention.

| Repetition | Fresh commands | Memory commands | Fresh total tokens | Memory total tokens | Reduction | Input share of token difference |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 27 | 0 | 3,654,187 | 51,242 | 98.6% | 99.84% |
| 1 | 32 | 0 | 4,439,023 | 53,433 | 98.8% | 99.96% |
| 2 | 63 | 0 | 2,767,030 | 51,451 | 98.1% | 99.65% |

Each row has an identical task prompt and `gpt-5.6-luna/xhigh` across arms.
Totals include cached input and output; the already recorded seed acquisition
cost remains separate. The input share is a decomposition of observed usage,
not a causal token estimate for each memory fact. These results are consistent
with avoiding repeated source investigation; shorter answers alone do not
explain the observed reduction.

There is also an important quality qualification. The complete
`Driver.cpp:7244–7252` OS/architecture/input branch is present in **two original
observations**. All three actual packets omit the `spirv32`/`spirv64` guard and
instead include a filtered `rg` observation showing the HLSL test and constructor.
All three answers summarize HLSL selection without that architecture scope.
The earlier review's statement about the filtered observation did not establish
that this condition was absent from the DB. A sufficient-condition summary must
not be read as an exhaustive necessary-condition rule. High savings and zero
further tools do not resolve this qualification or accept overall quality.

The source/packet/answer mappings, per-anchor delivery and usage are retained in
`readme-memory-reuse-20261021/answer-trace-1/{audit.json,executed-audit.py}`.
This audit makes zero answering-model calls, executes no LLVM command and
adopts no implementation change.

### Retained-memory readiness before second-lap model calls

The completed `415bcc2…` topic-3 repetition-0 output is checked against its saved
head/pages hashes and successful keep/shutdown records. A private publication
rebuilt by the frozen public producer preserves all 204 roots, 76 documents,
owners, original windows and unions. Its copied 3,321 vectors lack the last
19 windows; one 32-capacity warm batch completes all 3,340 unique windows.
Repeating warm from another private data root requests no work. The original
DB is unchanged. No new seed or answering-model call is made.

This is the earlier study's **fixed common history**, not a newly measured
continuous lap from one variant. The topic-1 stored answer comes from the original
candidate repetition 0; topic-2 and topic-3 answers come from centroid repetition
0. The stored-memory audit identifies each exact answer hash and its origin.
All previously investigated source facts, including the syntax phase, no-output
Compile action, job-construction call, positional-language test and full HLSL
branch, are present in the retained DB.

Twelve actual native `UserPromptSubmit` calls inspect both runtimes, all three
topics and two session states. Each first session starts from an identical
prepared source; the next session retains private query state and verified
neutral DB memo publications. That exploratory second-session condition is
amended before any second-session call, in `native-1/resume-1/protocol.json`.
All authoritative values, root order and unions remain identical to the common
source. Legacy cache copies retain only original source-window records before
the first call; subsequent query hits are observed rather than presumed cold.

| Topic | Public, fresh private state | Public, next session | Selected centroid, fresh private state | Selected centroid, next session |
| --- | ---: | ---: | ---: | ---: |
| 1 | 28.821 s, incomplete | 27.699 s, body | 9.218 s, body | 7.223 s, body |
| 2 | 23.042 s, body | 22.276 s, body | 8.270 s, body | 6.384 s, body |
| 3 | 24.105 s, body | 23.080 s, body | 9.196 s, body | 7.224 s, body |

All six centroid calls complete semantic search, publish the exact captured
stdout and receive accepted acknowledgements. Original source windows all hit;
no source vector is encoded within the hook. Each topic's two centroid bodies
are byte-identical. Public main lacks the structured Receipt module: unavailable
numerical counters remain unknown, while its stdout and acknowledged session
state are retained. Its first topic-1 incomplete notice is not a healthy public
reference. The resume guard peaks at 1,469,920 KiB and exits without triggering.

Answer delivery must be checked after decoding the presentation. `CHARS`
captions separate valid original ranges, so a failed contiguous whole-answer
substring test does not establish missing text. Every span check succeeds;
merging the validated ranges shows complete topic-2 and topic-3 historical
answers in their centroid packets. On topic 1 the centroid instead delivers
the topic-3 answer in full and the original HLSL OS/architecture/input branch;
its same-question topic-1 answer is not offered. These are advisory context,
with zero completed counts at these prompt hooks. The observed contents do not
predict the answering model's tool use, correctness or token consumption.

The first public call had already finished when bookkeeping failed: the public
runtime has no structured receipts, and its neutral memo publication introduces
`change:` metadata. The corrected audit checks all authoritative values and
allows only derived rows plus metadata belonging to verified neutral revisions.
It reuses that completed call and submits only the remaining eleven. The
original failure, runner and protocol are retained; no completed hook is replayed.
`validity-correction.json` records these bookkeeping and substring-test limits.

Preparation, source/answer hashes, raw stdout, native state, timings and
validated packet ranges are retained under
`readme-retained-memory-20261021/{preparation-1,native-1/resume-1}`. These are
readiness and delivery checks, not second-lap model results, token savings,
independent quality acceptance or production adoption. The selected runtime
remains `415bcc2…`; the public pin was rechecked as `5187316…`.

`tools/readme_benchmark.py` prepares private native environments and captures
one real turn. `tools/readme_sequence.py --stage N` runs one of the six frozen
stages and prepares its common next checkpoint. It validates matching input
graphs and reuses only completed recorded calls; a running, failed or missing
record stops the controller for inspection rather than replaying the request.
The process guard includes experiment-owned detached inference processes and
enforces the existing aggregate 3,500,000 KiB limit. Raw authentication stays
outside published artifacts. No subagent is used.
