# Working-set diagnosis

The earlier80-client run stopped at3,673,600KiB aggregateRSS. Its publication
host used1,597,968KiB; the frontend used394,752KiB. That record did not identify
the retained objects or implicate thread stacks.

The new observer runs the unchanged readonly-pages33c408 runtime and sealed
a80cad client under the successful16-client/two-wave condition. It takes three
bounded `vmmap -summary -wide` samples. All32 hooks deliver their required
original fields and complete semantic handoffs. The observer adds sampling
cost; its timings are not a clean performance comparison.

At the larger publication-host sample, physical footprint is682.2MiB and
resident stacks total2,304KiB despite218 reported stack regions. The dominant
region is labeled IOAccelerator:672.1MiB resident/dirty. At the earlier host
sample the footprint is422.9MiB and resident stacks2,096KiB. The frontend
sample has91.9MiB footprint and656KiB resident stacks. These distinguish
virtual stack reservations from resident memory; they do not identify live
Lean objects or distinguish live allocations from allocator-retained pages.

After prime/wave-a/wave-b,hostRSS is174,496/661,744/919,184KiB. Every snapshot
reports zero active search actors and request bytes. The prepared-source
catalogue stays at16 entries/8MiB charged,and its page count stays86;palette
queries are also fully released. Those named counters do not explain the
growth and do not cover every cache or retained task. Trace retained heap and
allocator ownership before changing concurrency or memory limits.

The installed Lean toolchain ships mimalloc2.2.3 (`MI_MALLOC_VERSION223`),
and the linked executable contains its allocator options. That release uses
macOS VM tag100 for its anonymous mappings by default; the vmmap label is not
evidence that Eggshell uses a GPU. This attribution is inferred from the
installed allocator and its primary source:
[tag default](https://github.com/microsoft/mimalloc/blob/v2.2.3/src/options.c#L133),
[anonymous mapping tag](https://github.com/microsoft/mimalloc/blob/v2.2.3/src/prim/unix/prim.c#L249-L254).

The native hook client exits0 and writes its complete report. After saving all
memory samples, the observer's finalizer incorrectly reaps that child again:
the guard records exit1/ECHILD,with no surviving processes. Keep that failure;
do not rerun the workload to relabel it successful. The observer source now
reads its actual reaping state from a local reference in the finalizer. That
corrected controller has not repeated this model-backed workload.

Next: distinguish live per-query graph/JSON state from allocator retention.
Reducing thread count or raising the memory guard is not supported by these
samples. A separate ownership correction removes the operation client's
unnecessary deadline mutex; it is not claimed to fix this memory failure.
Answering-model calls0;paid comparisons0/18;product core unchanged/unadopted.
