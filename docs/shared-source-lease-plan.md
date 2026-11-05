# Shared source descriptors and request leases

The private-page candidate removes repeated shared-page hit updates, but remains
unadopted: actual32-query delivery is16/32. The source-readiness inputs are
missing in failed rows and their synaptic completeness is false. In addition,
the guard retires leftover processes after a nominal client exit; lifecycle is
also a failed gate.

The captured16-source cut requires1,364,136 bytes under the current retained-source
reservation formula. The actual Lean Budget implementation admits only98 source
tokens without releases, versus1,280 tokens for eighty complete cuts; its8 MiB
budget holds only six whole simultaneous cuts. This is an impossibility witness
for eager full-cut retention, not a replay of the measured scheduler and not yet
a per-request trace proving every observed failure has that exact error.

The source-payload service already shares one Loaded value per immutable
preparation and charges its pages, owner arenas and metadata caches globally.
Retained-source admission nevertheless charges65,536+8*serialized-identity bytes
again for every source of every request, and also has a512-token limit. Increasing
only those constants would conceal the representation problem.

Descriptor interning and thin request leases are now implemented only in an
[isolated candidate](candidates/shared-leases/README.md). The80×16 component
retains1,280 tokens with16 original pins in90ms and2,668,968 accounted bytes,
under the unchanged8 MiB budget. Scope/full Head/manifest and active-reader
release/expiry/close checks pass. The first actual32-query gate reaches32/32
original+ACK and32/32 semantic handoffs, maximum9,664ms. Actual80 is20/80 and
semantic16/80; it fails. A self-endpoint reuse follow-up regresses to0/80 and is
rejected. Neither variant is adopted or has paid token/quality comparisons.

Keep these contracts for the next implementation:

1. Intern the exact authorized source scope, full original Head and preparation
   manifest once. Share the immutable loaded preparation and descriptor. A neutral
   but different Head remains a distinct checked descriptor; do not erase it by
   assuming it equals the manifest's saved Head.
2. Each request owns a fresh unguessable token, its original deadline, active-reader
   count and release flag, referencing the interned descriptor. Charge resident
   descriptor bytes once and token metadata per borrower. Keep a global byte
   allowance and derive metadata count bounds from it, rather than a small fixed
   connection count. Payloads remain in the existing shared budgets.
3. Validate scope/root/manifest on every token use. Expiration forbids new reads;
   an active read keeps its reservation and descriptor pin until its actual
   finalizer runs. The last borrower releases the original preparation. Preserve
   rejection of foreign scopes and stale tokens, and prove the indexed lookup
   returns exactly the token's checked source.
4. Admit a complete read cut atomically, or release partial pins before waiting.
   A query must not retain unusable partial cuts while other queries need them.
   Do not narrow the certification domain to fit admission.
5. Reuse checked immutable descriptors in source preparation. Do not re-open and
   reconstruct the same roots per chat. Query text, usage roots and mutable
   inference overlays remain private.
6. Per-source acquisition failures are now recorded. Incomplete source readiness must not
   become a successful empty handoff: keep valid empty search results distinct
   from unavailable inputs. The last two variants shut down without survivors.
   A process labelled`codex-daemon` can be the shutdown CLI itself; its role label
   alone is not evidence that another frontend server was spawned. Keep the older
   leftover-process failure as a failed gate. Audit service-wide shutdown ordering
   separately: source-cache accounting must remain live until active reads join.

The [full80×16 protocol study](candidates/source-protocol/README.md) has now
completed six fixed waves:480/480 complete cuts received, maximum1,397ms, exact
scope/full Head/manifest and zero retained charge after release. Both external
and hosted service modes pass. This isolates actual received RPC replies from
the90ms direct component; it does not pass eighty whole queries. Overlapping
queries still fail0/80 with optional profiling on and off. Two completion-observer
candidates pass32/32 hooks but also fail0/80; neither is adopted. Polling alone
is not the established cause. Their402 real outputs and failures are retained.

The [subsequent stage attribution](candidates/query-stages/README.md) shows all80
ON and OFF requests reaching the typed provider. Reopening/frame/reader spans
are short; the provider entry-to-result interval is median9.99/9.95s, while the
ON numerical backend CPU is100ms. Delivery remains0/80 in both modes. All69/71
last source-error files were recorded after the semantic phase ended and belong to
lexical fallback. Earlier unavailable-cut counts have no preserved phase
attribution and must not be treated as initial acquisition failures.

Next separate typed runtime/encoder setup, scope pinning, prepared input
restoration, routing, scoring/wait and response validation using the existing
request-local callback. Preserve the same full cut, cancellation ownership,
original clock and complete certification. No weight, cutoff or resource
inflation substitutes for that evidence; the failed32-query control remains
a failed adoption gate.

The intended interface shares a complete checked immutable source cut in the
project service. Request actors receive small private leases and direct typed
access within that owner; the remote transport implements the same checked
interface. Metadata/Head/manifest validation, immutable lookup tables and
descriptor creation are coalesced once per cut or publication delta, rather than
reopening roots and serializing full manifests for every actor. Do not assume this
will fix the80-client failure until its protocol and actual-hook gates pass.
Current questions, usage, traces, e-class overlays and deadline remain private.
Certification still sees the complete original domain. Shutdown must close
admission, retain charges for active reads, join owners and only then dispose
the shared preparation. Avoid a second unbounded cache or a global lock around
long IO, and do not change ranking weights or cutoff policy as a substitute.

Then rerun actual hook32 and only proceed to the fixed eighty-client comparison
if semantic completion, real evidence+ACK and cleanup all pass.
Ordinary ContractAudit, complete certification,30-second upstream clock,
4 GiB aggregate ceiling/3.5 GiB stop and strict token/quality adoption gates remain.
This is still incomplete work toward the full80-person/eight-hour/growing-project/
multi-host objective; a synthetic read-only fixture cannot establish that goal.
