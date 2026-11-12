# Match the historical complete-delivery envelope

**The retained current runtime delivers all frozen evidence under the earlier
500,000-character envelope.** Comparing that earlier result with later
120,000-character audits had confounded a configuration change with a code
regression. No product code, ranking, graph, model or authority is changed here.

## Historical evidence

The [record-boundary plan](../record-boundary/hook-plan.json) explicitly uses
500,000 characters. Its [actual result](../record-boundary/native-result.json)
has 32/32 delivered occurrences across six fresh chats, with bodies of
498,246 / 498,246 / 497,995 characters. The later
[stable-storage LLVM input](../../practical-runtime/stable-storage-read-llvm/input.json)
also specifies 500,000. The recent
[source-snapshot trial](../source-snapshot/llvm/plan.json) specifies 120,000.

The record producer is byte-identical in the earlier and current products;
that check alone does not establish equivalence of the complete pipelines.
The older source is also different. Instead of attributing the change to
either code or seed without control, this study changes only the envelope on
one fixed current runtime and physical project.

## Controlled registered-hook comparison

[Predeclared plan](plan.json), [fixed inputs](fixed-inputs.json),
[complete results](comparison.json).

Runtime SHA-256 is
`720e64d9daf08a8c8f5e716b8cb877bc378253ba51fb43738dc33e05c1b6c534`.
Both arms use the same physical source-only project, original revision 41,
source bytes, questions, MiniLM implementation, ranking, authority, registered
hook commands and observer. The 4/7/5 DB-present obligations are independently
frozen for both arms **before any warm or query** and match exactly.
The order is predeclared: 500,000, then 120,000; each has six independent fresh
clients. Cache readiness is established outside hook timing. The two passes
are repeat retrieval audits, not answering-model history rounds.

| Topic | 500,000: first / repeat | Hook ms | 120,000: first / repeat | Hook ms |
| --- | --- | --- | --- | --- |
| 1 | 4/4 / 4/4 | 6,226 / 3,981 | 1/4 / 1/4 | 4,930 / 2,955 |
| 2 | 7/7 / 7/7 | 4,112 / 3,979 | 4/7 / 4/7 | 3,114 / 2,958 |
| 3 | 5/5 / 5/5 | 4,097 / 3,967 | 3/5 / 3/5 | 3,066 / 2,920 |

The totals are **32/32 (100%)** and **16/32 (50%)**. All twelve semantic
searches complete; all 36 registered callbacks exit normally with empty
stderr. Within each arm/topic the two bodies have the same SHA-256. The larger
bodies are 498,511–498,514 characters; the smaller are 115,373–115,650.
The audited bodies match actual hook stdout exactly. The original four files
and captured three files still match their pre-delivery hashes afterward.

The first cold preparation fails with `explicit warm lost its preparation
claim` before any query or callback. [Failure](initial-warm-refusal.json).
Its cause is not established by this message. All processes drain; the same
captured project, code and settings resume explicit warm successfully, and
both arms require successful warm before querying. The failure, stop records
and original command output remain separate from successful results.

## What this establishes

The current implementation retains the ability to produce complete evidence
on this fixed corpus when given the earlier envelope. The observed recent
50% result is reproduced solely by selecting 120,000 on that same product.
This does not prove that every historical code change is output-equivalent,
that 500,000 is the best production setting, or that all future evidence fits.

No answering model is called, so total tokens and answer quality are
**unmeasured**. A larger delivery body is not a token-reduction result.
This incomplete interrupted original is not an accepted seed; the study is
not the requested seed → topics 1/2/3 → history topics 1/2/3 experiment.
No product/default change is adopted from this audit. The full 80-person,
multi-project, 98%/30-second goal remains open.

## Evidence and retirement

[Native closure](native.json): 325 consistent observer objects.
[Source comparison](sources.json): all product core present and 322 common
sources unchanged. The actual hook runtime is the unchanged product, not this
observer. [Guard records](guards.json) retain successful and failed stages.
The successful query guard takes 136.250 seconds including both warm/service
lifecycles and independent audits, peaks at 2,174,064 KiB related RSS, and has
no surviving owned process. It is not a hook latency sample or a p99 claim.

[Lossless callback evidence](callbacks.json) stores every original text file
under `calls/` and `commands/` by SHA-256 with a path table; equal contents are
stored once, without compression or an archive. [Body references](bodies.json)
locate each exact body in its actual callback stdout; the twelve redundant
plaintext body copies are removed after byte/hash equality checks. Per-cell
source assessments remain beside this document.
[Retirement](retired.json) removes the ended DB, cache, observer/source/build
and scratch files: 5,591 entries, 871,409,463 logical bytes. No archive is
created. All 355 protected inputs remain unchanged, and the
[retained product](parent-after-retirement.json) still has 347 consistent objects.
