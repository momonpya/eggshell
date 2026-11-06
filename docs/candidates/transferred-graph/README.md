# Graph ownership and completed thread lifetimes

Diagnostic only, not a product change. No database or answering model is used.
The native adapter supplies OS thread identities, thread inventories and RSS;
Lean controls parsing, transfer, joining, checks and recording. An absent thread
is accepted only after a successful inventory. Inventory failures are retried,
not interpreted as thread exit.

Eight producers each construct two independent parses of the same446,121-byte
JSON, with8,192 records per result. Four waves compare producer-local release,
consumer release while the producer remains alive, release after OS-confirmed
producer exit, and transfer through a string whose exact bytes are checked.
The final RSS values are approximately78.1,78.6,78.9 and96.9MiB respectively.
None reproduces the real service's hundreds-of-MiB accumulated growth. The
encoded representation is not adopted as a repair.

A second diagnostic links the actual selected `OperationPool.ownedPhase`
object, retaining all parent objects except the entry and OS adapter. It
prewarms the helper identically and checks exit of both outer and inner
threads. After four waves, direct transfer ends at89.8MiB, the helper without
readiness at119.2MiB and the readiness condition at105.3MiB. The quiet condition
grows about10MiB per wave in this short sample; the readiness condition
plateaus after wave2. This is a lead about phase/result lifetimes, not proof of
a retained graph, a leak, or the real service's growth mechanism. No allocator,
wire, worker count, clock or cancellation policy is changed on this evidence.

[Plans](plan.json),[actual-helper plan](phase-plan.json),[seven reports and
ten drained guards](evidence.json),[standalone build](build.json),[selected
native helper provenance](phase-build.json),[deletion without archives](cleanup.json).
The unused diagnostic executables and generated artifacts were deleted after
recording208,804,008 logical bytes of cleanup. Parent objects, fixtures and
original inputs remain available. No80-client retry was run.
