# Group incoming feeds without serializing original owners

Isolated candidate, not adopted. Independent append owners remain independent;
each owns its original source head. This change does not replace them with one
project writer or make the project authority an arbitrary physical owner.
Eighty clients need not imply eighty source heads: the existing fixture routes
them over sixteen owners. Owner count and worker/resource limits are unchanged.

The previous registry has sixteen private destination journals, not256 journals.
It schedules256 owner/ingress pairs. Each pair imports a feed and can replay the
same destination again. The candidate keys replay jobs by destination owner and
storage scope, while storing the complete incoming relationships in that
destination's private journal. Sixteen destinations retain240 foreign feed
relationships. Read-only and writable storage scopes remain separate.

Each import round captures original journal heads, shares the existing event and
16 MiB encoded-byte budgets across inputs, and persists its round-robin cursor.
Later appends and newly registered inputs wait for the next round rather than
invalidating the current finite prefix. Imported events remain authenticated
references to their original bodies. Replay runs after that captured round is
imported. Original source heads are never advanced by private preparation.

The scheduler distinguishes committed partial progress from unchanged failure.
Progress resumes without the failure backoff; genuine failure retains it. New
wakes, active claims, closure and resource limits retain their existing rules.
This changes scheduling only; progress is not completion or reuse authority.

The native checks compare the complete imported projection, original identities,
reference-only storage, restart recovery and facts/status against existing replay
oracles. They include late inputs, expired and zero-byte budgets, a large feed
beside a small feed, scope/corruption rejection and a50,047-byte structured result.
The ordinary context and preparation integration reports are recorded separately
in `evidence.json`; a component pass is not an eighty-client capacity pass.

| Functional check | Result |
| --- | --- |
| Original append owners / replay targets |16 /16 |
| Foreign feed relationships retained |240 |
| Complete imported original projection | Equal |
| Late event / newly registered input / small feed beside large feed | Preserved |
| Ordinary prompt / Pre / Post / Stop, six-source context |952 /139 /97 /32 ms |
| Eighty preparation wakes, three existing workers, concurrent original ACK | Passed |
| Stop during active preparation / recovered pending debt |23 ms /0 |

The integration's eighty wakes coalesce over six source targets. They are not
eighty writer lifecycles or a sustained capacity measurement. Its first
preparation phase takes2,102 ms. The first integration attempt reuses a captured
input boundary while constructing a new test turn and is rejected; the harness
now clears that boundary and captures a fresh one. Product capture validation
is unchanged. Earlier compilation and CLI-dispatch failures remain in evidence.

This is an intermediate correction, not a complete project-wide shared replay
implementation. There are still sixteen destination projections and240 incoming
relationships in this fixture. Registering all relationships or preparing the
same immutable structures per destination can still amplify work. The next
capacity check must measure that remaining cost, foreground queueing and actual
delivery, without the old heavy readiness observer or higher limits.

The ordinary mixed workload has now been run with the actual service executable:

| Mixed workload, sixteen owners and eighty concurrent clients | Result |
| --- | ---: |
| Successful query/Pre/Post/Stop writer lifecycles |80/80 |
| Exact saved original inputs/outputs after fresh-process reopen |82/82 |
| Posted but unpublished / pending saved sessions |0 /0 |
| Source/owner readiness gate after writers |126,231 ms |
| Preparation pending / active / retries at that gate |0 /0 /2 |
| Committed partial-progress requeues |156 |
| Fresh readers delivering both original fields within30 seconds |58/80 |
| Semantic / lexical deliveries |9 /49 |
| Failure-inclusive hook minimum / median / maximum |8,866 /26,239 /29,756 ms |
| Observed operation queue median / maximum |20,237 /26,275 ms |
| Observed operation work median / maximum |686 /6,599 ms |

Only63 operations have final service timing observations; these are not
all-request quantiles or p99. Twenty-two clients fail. All80 captured source
inventories and admissions complete. The three workers' first work takes
5,809–6,599 ms, including2,323–2,688 ms of readiness. Subsequent observed work
medians are668/688/697 ms per lane. Existing reader-image/page caches are already
hitting; adding another generic cache is not a demonstrated remedy.

This independently generated functional fixture is not a matched performance
comparison with the previous60/80 run. The heavy replay observer was removed
from this capacity harness; readiness still checks the same complete source
inventory and owner image. Do not attribute126 seconds versus155 seconds, or
58 versus60 readers, solely to this implementation change. Worker, owner,
request, memory and hook-deadline bounds are unchanged. The original source heads
remain unchanged during readback and the separate fresh-process original audit.

The capacity gate fails. The candidate has not demonstrated real98% necessary
evidence or sustained eighty-person/multi-project/NAS operation. Preparation
grouping is insufficient: remaining destination-wide preparation and foreground
queueing must be handled separately. See[next-capacity.md](next-capacity.md).
Answering calls0; paid matched comparisons0/18. Total-token and quality adoption
gates remain open; no product source or README performance claim changes.

All native guards finish without owned survivors or resource stops. Maximum
related RSS is3,470,416 KiB, below the unchanged3,670,016 KiB stop and4 GiB ceiling.
The sealed evidence includes failed attempts, actual distinct delivered bodies,
receiver hashes, phase receipts and exact runtime/source identities. Ended
fixtures, private caches and raw logs are removed after sealing, without archives;
active original inputs, source trees and compilation dependencies are retained.
Cleanup releases432,041,738 apparent bytes. Protected original and control-file
SHA-256 checks pass before and after deletion. `candidate.patch` applies cleanly
to the captured parent source tree. It also contains the native helper deltas;
`evidence.json` binds their actual compiled sources separately from workspace
entry-point adapters. A portable patch-header repair is recorded without
changing the native results.
The ended component executable is later retired with its recorded hash in
[local-selection/retirement.json](../local-selection/retirement.json). Service
executables and compilation inputs remain; the deleted checker needs a rebuild.
