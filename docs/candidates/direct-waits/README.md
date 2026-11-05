# Direct native event registration: negative result

This isolated candidate registers socket/timer readiness with the request owner
using `Async.toIO`, rather than enqueueing another default-pool action with
`Async.block`. It retains request-owned actors, complete original/certification
domains, MiniLM, ranking, original cutoffs and all resource allowances.

The native component checks pass128 immediate returns,80 concurrent timer
payloads, exception and valid-empty preservation, absolute expiry rejection, and
the existing request cancellation/join checks. The combined event test takes83ms.
The first build's checker syntax failure is retained separately from the sealed
successful runtime.

The actual16-client waves deliver the required original fields plus ACK for
only1/16 and2/16 requests. Across32 requests the median is29,407ms and maximum
29,688ms. This does not improve the preceding request-owned candidate's3/32.
The first wave consumes93.95 service CPU seconds, including44.79 system seconds,
and still performs422,288 shared-page hit updates. The registered event path
alone does not solve the capacity problem. No80-client burst or model trial was
started after this failed gate.

The [plan](plan.json), [sealed identities](identity-before.json),
[raw-body observations](evidence.json), [deduplicated actual bodies](bodies.json),
and [independent verification](verification.json) remain reviewable. Actual
stdout/body digests and both required original fields are checked independently;
an empty semantic result is not successful delivery for these known-positive
synthetic cases. This fixture is already observed development data.

Candidate runtime SHA256:
`d1771f7e5765c95cd597779357b734eebdfcc1b4e4af2073bf9eb5f9ed89bb01`.
This candidate is not adopted. Answering-model calls0; paid matched total-token
and quality comparisons0/18. Component checks do not establish80 people,
eight-hour operation, growing projects, multi-host sharing or98% delivery.
