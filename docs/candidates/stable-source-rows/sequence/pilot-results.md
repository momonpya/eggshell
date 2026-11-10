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

Three remaining paired stages are incomplete. No aggregate or second-round
claim is available. This table includes cached input within input, and includes
reasoning within output exactly once. Topic one has no failed model attempt.

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
