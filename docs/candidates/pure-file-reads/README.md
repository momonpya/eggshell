# Pure file presentation metadata

Isolated candidate; not adopted. Answering-model calls and paid token
comparisons remain zero. This is a bounded lock-removal change, not a claim
that all retrieval is lock-free or that the 80-person/98% goals are met.

The former `publishFile` wrote exactly `fileStored file`: the complete file
identity, its canonical JSON order, its content key, and empty extents. The
same complete identity is already validated in the immutable owner descriptor.
Real extents come from that owner's published scopes. A separate PageMap
lookup, payload verification/decoding, shared cache, promise, borrower count,
LRU update, and release added no independent information.

The candidate derives the same small presentation value purely from the
checked descriptor. It removes the separate publication and the entire
16MiB file-header cache rather than moving its mutex to another cache or
replacing it with CAS. The original source/head/prepared-root/scope checks,
owner metadata, extent union, selector, vector and synaptic ranking, and
complete Work/e-class certification remain. The deleted cache allowance is
not reassigned to another pool.

Lean laws establish the exact stored value, uniqueness of a checked result
of the former canonical publication, the same extent union, and file validity
in a scoped owner descriptor. A declaration audit must connect the actual
selector to the pure constructor, reject obsolete storage/cache declarations,
and reject synchronization dependencies in captured reads.

The four new laws, ordinary ContractAudit, and actual declaration connections
pass. All 1,123 dependencies traversed from captured reads and the pure file
constructor/extent operation contain no shared synchronization entry points.
The selected native closure keeps 253 modules and changes exactly the four
declared source bodies plus their exact embedded identity inputs.

Native controls capture and publish one file observation through the actual
source pipeline. The three original rows have one complete file identity.
There is no separate file-header publication. The actual service selector's
complete choice and receipt match an independent selection. While holding the
preparation-owner mutex, 80 independent readers perform 128 reads each in
28ms; all rows, costs and payload identities match, shared cache statistics
are unchanged, and the original head is unchanged. This small three-row
component test does not measure 80 full hooks, large DB latency or a p99.

Existing typed/wire, foreign authority/scope/head/root, expiry, cancellation,
active-borrow release and reservation controls also pass. The whole native
control exits normally with zero surviving processes and zero reservations;
sampled related peak RSS is 114,544KiB. The compiler/native closure audit and
all failed controls are retained. The first native control exposed a checker
finalizer omission; after fixing it, invalid fixture lifetime and zero-valued
integer weights were reported normally and corrected to the existing rules.
No production deadline, ranking weight, worker count or resource bound changed.

No new full-hook cohort or paid model experiment was run. The earlier full
cohort's frontend-shutdown failure, residual host RSS, large post-provider
interval and overall 80-person/98% goals are not repaired or claimed by this
file-header change. Read admission, source preparation/cache fill, lease
ownership and release still have separate synchronization. A pure read
constructor is not a proof that those mutable operations need no ordering.

[Plan](plan.json), [build and kernel audit](build.json),
[selected native sources](native-sources.json), [native controls](native-checks.json),
[all guards and failures](controls.json), [failed-checker sample](check-finalization-sample.json),
[cleanup](cleanup.json). The old TypedReadChecks entry is superseded by
FileReadChecks; its selected native source witness remains with the parent
build and its source is retained in Git history.
