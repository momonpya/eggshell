# Next investigation: repeated captured input frames

Not implemented or validated. This follows the rejected local-rank candidate;
do not repeat that failed load test unchanged or retune ranking weights.

The sealed profiles contain twelve large worker-exchange envelopes of
311,126–311,134 bytes, alongside twelve small envelopes. They are two normal
hooks in each of six arms. `OperationPool.submit` charges the compressed
`OperationWire.Request`, and `OperationPlan.maxBytes` is 16 MiB, including active
and pending jobs. Eighty envelopes of this size would exceed that budget.
Envelope size is not exactly the charged request size; this is an admission
pressure hypothesis, not proof that the observed refusals came from this bound.

The source also exposes real duplication. `Worker.Search` carries `prepared`,
`originals` and `owners`. Its `pending.preparedInputs` can contain a serialized
`PreparedInputs.Frame` with the same roots. `capturePrepared` validates their
equality and can return both copies; `OperationPool.validate` decodes and
compares them again. The frozen private turn record and the transport request
need not necessarily use the same redundant representation.

First measure serialized field sizes immediately after normal capture, without
recording query text, capabilities or original payloads. Audit every consumer
of `pending.preparedInputs`. Then consider a transport-only projection that
retains the already-validated explicit frame once. The private durable pending
record must remain intact. Preserve every configured source, exact original
head, producer/model binding, requester-private usage boundary, cancellation,
deadline and retry identity. An inconsistent duplicate must fail before it can
be erased. Missing preparation must not turn into an empty successful search.

Prove the effective captured-input tuple is unchanged, check actual admission
and worker declarations, and test old captured roots after later publication,
mixed project/read-only sources, invalid duplicate frames and ordinary receipt
ACKs. Compare actual request charges and all delivered bodies before the next
paired eighty-reader/save/preparation test. Keep existing byte/count/worker and
deadline limits. Do not cache a shared answer to the fixture's identical question
or shrink certification to a recommendation subset to pass the load gate.
