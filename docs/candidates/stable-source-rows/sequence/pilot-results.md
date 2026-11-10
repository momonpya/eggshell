# Fixed-runtime pilot

This is one repetition, not an adoption comparison. Product runtime is
`dd53c89bc450b66b58dd57d104ccbc82f32ca6345fa9666125e7feb03017000e`;
native controller is
`670aaf8ec8b79cf71ca97daf9ae41bd33a9070196be36ce45a9dd0f8d26cf6c5`.
All arms use gpt-5.6-luna/xhigh, the same fixed prompt and LLVM source commit
`6dfe1677ab8dffbc6ec13d53a1e0215d75147689`. The accepted seed costs
2,073,642 inclusive tokens separately. Earlier failed acquisitions retain
their own cost records; they are not rolled into a per-question saving.

| Round / topic | Fresh input + output | Memory input + output | Saving | Delivered fully stored units | Including partially stored evidence |
| --- | ---: | ---: | ---: | ---: | ---: |
| First / 1 | 4,888,585 | 1,306,474 | 73.275% | 3/3 | 4/4 |
| First / 2 | 3,419,749 | 174,754 | 94.890% | 5/5 | 7/7 |
| First / 3 | 4,382,725 | 904,479 | 79.363% | 5/5 | 5/5 |
| Second / 1, reused fresh reference | 4,888,585 | 697,687 | 85.728% reference only | 5/5 | 5/5 |
| Second / 2, reused fresh reference | 3,419,749 | 175,591 | 94.865% reference only | 6/6 | 7/7 |
| Second / 3, reused fresh reference | 4,382,725 | 174,860 | 96.010% reference only | 7/7 | 7/7 |

All six memory stages and their source-history audits completed. The
independent six-pair comparison is
incomplete; second-round reductions refer to reused first-round controls and
are not an exact campaign-wide saving. This table includes cached input within input, and includes
reasoning within output exactly once. First-round topic one has no failed model attempt.

The new second-round topic-one fresh control was interrupted by the presealed
5,000,000-token limit. It observed **5,078,087 inclusive tokens** before
interruption; final usage is unknown. This cost is retained as a lower bound,
not discarded or counted as a completed fresh answer. No memory trial had
started at that point. The complete independent six-pair pilot is therefore
not achieved, and an exact campaign-wide token saving is unavailable.

The [explicit continuation](reference-round.json) uses the completed first-round
fresh control for each second-round topic, as previously permitted by the user.
Every fresh plan field must match except its label and output/guard paths;
source, prompt, model, account, environment and harness must be identical.
These references are not three new independent repetitions. No model trial
is retried, no token/time/resource limit is raised, and the answering controller
and product stay fixed. Strict native source closure checks the selected
completed reference and candidate. A separate history receipt marks reference
reuse, the failed charged attempt, and comparison incompleteness explicitly.
Any later reference-based reduction will be labelled as such, alongside this
additional failed cost; it cannot authorize adoption.

Second-round topic one completed with input/output 688,226 / 9,461 and cached
input 510,848. All 5/5 fully stored originals are in the actual initial packet,
matching the preflight body hash. Its initial hook took 9,026 ms with no hook
failure. Native source audit, read coverage and standalone next-history closure
passed. The answer reports `UNRESOLVED` because the workspace lacks the built
Clang/lit configuration; quality non-inferiority is not established. The new
failed fresh control and its unknown final usage remain charged separately.

Second-round topic two completed with input/output 167,166 / 8,425, cached
input zero, and no tool calls. The actual initial packet matches the preflight
body: 6/6 fully stored units and 7/7 when including the partially stored
`dumpmachine` evidence. The initial hook took 9,204 ms; all three hooks passed.
Native source audit and history closure completed. Its answer describes the
driver/config/target/toolchain chain and downstream caller assumptions, but
this unblinded observation does not establish quality non-inferiority.

Second-round topic three completed with input/output 166,977 / 7,883 and cached
input 13,568. No tools were called. All 7/7 fully stored originals are in the
actual initial packet, matching the audited preflight body. Its first hook took
9,106 ms; all three hooks passed, as did native source audit and history closure.
The answer describes target, input-language, final-phase and no-output
boundaries, while noting that the matching built compiler is unavailable.

Across the six stages, **31/31 fully stored requirement instances** and
**35/35 instances including partial stored evidence** occur in the actual
initial model packets. All 44 memory hooks passed. Initial prompt hooks range
from 7,880 to 9,204 ms. These are six single-request observations, not a p99,
a sixteen-client result, evidence about all possible required history, or
eighty-person readiness. The [structured result](six-stage-results.json)
checks the actual packet hashes, final token arithmetic, completed guards,
frozen delivery audits and source-closure receipts. Product and answering
controller hashes stayed fixed; no model trial was retried.

The six memory runs consumed 3,433,845 inclusive tokens. The three completed
fresh controls consumed 12,691,059; reusing them does not bill those tokens a
second time. Completed study runs therefore cost 16,124,904 tokens. Including
the interrupted fresh attempt gives an observed lower bound of **21,202,991**,
with final failed usage unknown. Accepted seed acquisition adds 2,073,642
separately (at least 23,276,633 including that seed). Earlier failed seed
acquisitions retain their separate receipts. No exact net campaign reduction,
quality non-inferiority, adoption comparison or production adoption is claimed.

For topic one, fresh input/output is 4,867,798 / 20,787; memory is
1,295,205 / 11,269. Cached input is 4,654,208 and 1,092,224 respectively.
The answering model's initial memory packet matches the preflight body bytes.
Two preflight chats took 7,086 / 5,048 ms; the actual first prompt hook took
7,918 ms. All fifteen actual memory hooks completed without failure. Both
model guards exited zero with no owned processes. Source finalization, native
origin audit, read coverage and next-history freezing also passed. These are
single-request times, not sixteen-client throughput or p99 measurements.

Full-range eligibility and partial availability are distinct. The tracked
input-language range is only partially stored in this seed; its available
part is delivered. The trailing-language warning is absent from the seed and
is excluded from delivery success. The source-only audit was frozen before
the preflight; delivered output did not define its denominator.

Quality is **not established**. Fresh describes `-x` position/extension edge
cases. The memory answer concludes no fix is needed and cites ordinary
AMDGPU, clang-cl and Arm tests without addressing those counterexamples.
Independent inspection confirms `usesInput` examines `-x` and extensions
without tracking argument position, while `BuildInputs` diagnoses trailing
`-x`; toolchain selection precedes `BuildInputs`. HLSL and AMDGPU translation
contain the stated default-optimization paths. Neither answer has a runnable
Clang/lit build in the fixed workspace, so these are static observations,
not dynamically reproduced compiler failures. The differing conclusion must
remain visible; this one pair does not identify its causal source or establish
model variance. The runtime remains isolated and unadopted.

For topic two, fresh input/output is 3,398,207 / 21,542 and memory is
166,614 / 8,140. Cached input is 3,158,784 / zero. Memory made no tool calls;
all three hooks completed and the initial packet matches the audited body.
Its actual prompt hook took 7,978 ms; preflight chats took 7,494 / 5,351 ms.
Both partially stored requirements were included in the 7/7 available-evidence
assessment. Both model runs and source-history closure completed; neither
answering-model arm was retried. A preparation-controller identity check was
corrected before closure could start; it did not rerun or alter the answers.

The second memory answer covers driver mode, option visibility, configuration
head/tail ordering, triple normalization, ToolChain/tool selection, lifecycle
assumptions and an additional boundary-test proposal. Fresh additionally
discusses explicit option aliases, downstream callers and a duplicate legacy
spelling test. This is an unblinded content observation, not a non-inferiority
finding. No executable Clang/lit comparison has been performed.

For topic three, fresh input/output is 4,362,050 / 20,675 and memory is
893,334 / 11,145. Cached input is 4,173,312 / 700,928. The actual initial
packet matches the preflight body containing 5/5 DB-present units. Its first
prompt hook took 7,880 ms; all eleven hooks completed without failure. Both
answering arms and source-history closure passed, with no model retries. The
two unavailable requirements remain explicitly excluded. Both answers report
no source change and describe the parse, target, input-language and syntax-only
phase boundaries. Neither dynamically validates a compiler build; quality
non-inferiority remains unestablished.

The denominator concerns original bytes actually retained by the frozen DB.
`SourceEvidence.capture` retains file locators and streamed content fingerprints;
`ContentCapture.scanUsing` compares observed output with those files and
`ContentMetadata.stage` persists correspondence aliases. These functions do
not copy each complete input file into a historical content store. A file
fingerprint alone is therefore not evidence that an unobserved range is in
the DB. The audit reads the immutable workspace only to verify reference bytes
against a saved dependency, then requires those bytes in a native original
output. It never inserts live source bytes into the candidate packet.

Ended working DBs/caches for topics one through three were deleted without an
archive: 7,809 files / 1,670,646,626 logical bytes. The active next stage uses
the independent fourth-stage history; every source/private/ACK checkpoint file
and all three selected executable hashes were checked before and after removal.
Raw usage, RPC, answers, audited packets and compact source-audit receipts remain.
Deleted working DBs cannot be re-audited in place. Logical bytes are not physical
APFS savings. See [cleanup receipt](closed-stage-cache-cleanup.json).

The [next cleanup](finished-second-round-cache-cleanup.json) retired another
5,467 files / 1,193,786,370 logical bytes. After all six stages, the final
source/private/ACK snapshot passed a native standalone fork in 20,583 ms with
no model calls, copied session state or copied derived vectors. The
[final cleanup](final-intermediate-cleanup.json) then deleted the remaining
ended working DBs, intermediate checkpoints, ready caches and that verification
fork: 2,899 files / 1,641,311,416 logical bytes. The three cleanup batches total
16,175 files / 4,505,744,412 logical bytes, with no archive. Common seed inputs
for the required matched comparison and the final standalone snapshot for the
next performance investigation remain; all selected executable and retained
history hashes are unchanged. Older working snapshots cannot be reopened.
