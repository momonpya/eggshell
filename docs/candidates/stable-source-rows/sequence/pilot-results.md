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

Five remaining paired stages are incomplete. No aggregate or second-round
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
