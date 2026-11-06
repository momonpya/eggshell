# Heap ownership and service retention observations

Status: diagnostic-only isolated candidate,unadopted. Product code and README
performance claims are unchanged. Answering-model calls0;paid comparisons0/18.
The80-hook memory failure remains unresolved;no unchanged80 retry was run.

The preceding working-set observation identified resident heap mappings,but
did not separate live results,caches,pending frees and allocator-held pages.
This study adds measurement without changing ranking,certification,delivery
selection,deadlines,model processes or actor concurrency.

## Model-free measurement validation

Four fresh processes run8 dedicated actors over4 waves with identical input
and work. They cross retention of one tiny parsed string with owner-thread
collection. Reports are written and dropped on the producer;worker task and
result handles do not escape the wave. Fourth-wave post-join RSS is about77MiB
in all four conditions. This simple same-owner parse/free fixture does not
reproduce the real service growth. It does not test freeing a large result
after ownership transfer and producer exit.

The installed allocator reports version223. Its global committed counters
produce impossible unsigned totals in collection conditions,and some printed
page counters are negative. Those metrics fail validation and are rejected
for service attribution. Keep that negative result instead of interpreting
global committed bytes as resident or live memory. The fixture is short enough
that the external guard can miss transient peaks;its sampled peak is not a
continuous RSS bound.

The service uses a separate owner-only entry point:it visits only the calling
thread's heap and does not merge/print global counters or force collection.
The adapter calls the allocator already linked into Lean;it does not link an
additional allocator. Native C is limited to the allocator diagnostic API,
which Lean's public API does not expose. Workload generation,control and
analysis remain Lean. Generated prototypes and native checks validate the ABI.

## Actual service observation

The same sealed client and frozen16-source development fixture complete two
16-client waves. All32 required originals plus ACKs and all32 semantic handoffs
complete;all32 full stdout values match the owner-metadata-image parent byte
for byte. Min/median/max latency is7,000/7,994/9,116ms. Related sampled peak RSS
is2,691,712KiB. This single control does not establish a performance improvement
or80-person capacity. These synthetic MCP records are not LLVM topics1/2/3 or
a real98% evidence-delivery validation.

Host RSS after prime/wave-a/wave-b is172,608/647,088/874,864KiB,while:

- Active actors,request bytes and owner-cache borrowers are0 at each snapshot.
- Prepared sources stay16 entries/8MiB and86 canonical pages.
- Owner metadata stays160 empty entries,charged12,703,024bytes;no new loads or
  evictions occur after prime. One finished loader task is retained.
- The file-header cache and original-owner arena stay empty.
- The public reader image stays one image,charged382,242bytes,with278 pages.

Cache cardinality does not explain the observed increase. This does not prove
that cache heap footprint is constant or that the allocator is the sole cause.
The32 search-phase owner samples report roughly5.0–5.2MB of used blocks and
8.9–10.0MB of committed areas per sample. These are owner-local observations,
not total process live bytes. The non-block visitor reads area accounting
without draining pending remote frees;it cannot establish Lean reachability.
This limitation follows from the installed version's
[area/visit implementation](https://github.com/microsoft/mimalloc/blob/v2.2.3/src/heap.c).

The next causal test must vary result ownership:allocate/free on the producer
versus transfer a graph and free it after producer exit. Audit the typed
SearchReply and Json lifetimes at async boundaries before changing allocator
knobs,worker counts or clocks. Do not infer a completed-task closure leak from
these measurements.

Native-source audit binds253 candidate modules to252 parent modules. Only the
five declared existing source files and one diagnostic API module differ;the
foreign object has a separate source/object digest. Seven failed builds and
the recorder's dropped-metric-field failure are retained as failures. The
recorder was corrected against original stdout hashes and original receipts;
the model-backed workload was not repeated to hide that failure.

[Plan](plan.json),[fixture results](fixtures.json),[actual attribution](attribution.json),
[actual outputs](evidence.json),[body verification](verification.json),
[controls/failures](controls.json),[source audit](native-service-sources.json),
[adapter](../../../tools/research/native/allocator_probe.c).
