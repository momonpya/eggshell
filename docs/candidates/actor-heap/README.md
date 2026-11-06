# Observe allocations at actor stage boundaries

Unadopted diagnostic. The existing final query observation covers the inner
phase heap;the outer actor also restores requests and reader frames. Under an
explicit diagnostic flag,the existing stage callback now records the installed
owner-only allocator area summary. Numerical callbacks can call that callback
from the inner phase,so labels identify the observed execution point,not a
claim that all observations belong to one physical heap.

Across the same frozen16sources and35actual outputs including prime,the outer
execution-start observation is about1.2MB used,and completion is tens of KiB.
Numerical callback observations peak near4MB used and9MB committed. These
values do not explain roughly900MB service RSS. Area.used can include pending
remote frees,and owner observations cannot prove whole-process reachability.

All32measured outputs are byte-identical to the sealed allocator-service parent,
with required originals,ACKs and semantic handoffs. This is neither an80-user
capacity success nor a real98% delivery or token/quality adoption result.
The later transport diagnostic exposed the risk of manually replacing a few
native objects;that build path has been removed from the controller. Subsequent
diagnostics use complete transitive source/dependency/interface selection.

The ended DB/cache,raw data and unused executable were deleted without archives.
[Plan](plan.json),[observer source](observer.patch),[build](build.json),
[actual bodies](bodies.json),[hook evidence](evidence.json),[verification](verification.json),
[stage summaries](heap-stages.json),[controls](controls.json),[cleanup](cleanup.json).
