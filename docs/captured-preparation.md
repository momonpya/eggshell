# Prepare the original cut a request actually captured

The 80-person goal needs independently publishing source owners and complete
original cuts. It cannot substitute the latest or a ready subset for a turn's
accepted original inputs. The [native counterexample](candidates/captured-preparation/counterexample.json)
demonstrated a missing contract: A1 is captured, the background worker prepares
A2, and A1 remains unavailable. The parent rejects historical warm through its
forward-only shared synapse index; the original records are intact.

The [component integration](candidates/prepared-cuts/README.md) now prepares
skipped A1/B1 after A2/B2 without replacing either later completed input.
Explicit warm plus ordinary worker/extraction delivered both original responses.
The [service-interest continuation](candidates/source-interests/README.md) now
captures originals/private usage while unready and fulfils exact A1/B1 through
normal shared workers and the complete hook delivery path. Write/read-only
fixtures and fresh-process restore pass. Cancellation/expiry, numerical and
sustained-capacity gates remain unfinished.

This replaces the idea that another notification of the ordinary latest-head
job would be enough. Increasing waits or the number of ready-name slots does
not prepare a skipped cut. The implementation below is unfinished; it is not
an 80-user or 98% delivery claim.

## Input and preparation contract

1. Always capture the complete original inventory before readiness checks,
   including raw DBs and empty sources. A private request frame represents
   pending preparation explicitly; absence of ready roots cannot erase the
   original heads. Capture requester-private usage at that same boundary and
   keep it out of shared preparation metadata.
2. Register source-specific preparation interests by project/scope, original
   identity/full head, model/encoder and implementation. Their payload is
   query-independent root metadata, never the prompt or original tool output.
   Identical interests share work. Different cuts cannot coalesce into a job
   that only pins the current source. Full admission retains existing durable
   interests and reports rejection; it does not discard acknowledged work.
3. A worker batches source differences but materializes roots at interested
   boundaries. Keep a source-bound catalogue of completed component roots and
   locate a verified prepared ancestor without scanning the corpus. Validate
   actual source lineage, not only revision ordering. A preparation may start
   from an earlier immutable tree even if a later cut finished first.
   Use the original publication parent chain to find that ancestor, checking
   exact source-head catalogue keys along the unprepared difference. This
   work is bounded by the source difference, not the corpus population. A
   pending frame retains the ancestor references separately from ready inputs;
   an earlier basis is never passed off as the requested completed cut.
4. Logical tree basis and physical append extent are separate. Derive from the
   ancestor's root, append beyond the current published file extent, and keep
   all existing completed roots readable. Recovery discards only uncommitted
   bytes after the current physical publication. The isolated
   `PageMap.withWriterFrom` primitive is a foundation for this step; it does not
   itself prepare a source or prove original-source lineage.
5. Connect that operation to lexical, owner, shared synapse, canonical,
   window-owner and numerical assignment roots. Readiness names/catalogues
   cannot roll back unrelated completed cuts. Reuse content-addressed vectors;
   do not re-embed or reconstruct the corpus for an old interest. Original
   append owners never wait for this derived writer region.
6. Fulfil a request only with the roots for its complete captured cut.
   Certification reads the complete original graph and remains independent
   of advisory nomination/pruning. Numerical incompleteness may use the
   existing lexical advisory path when its exact-cut inputs are ready; it
   cannot redefine the original evidence denominator.
7. Retain component extents required by queued/live requests through name
   retirement and physical compaction. Cancellation removes interests after
   their last reader; it never rolls back original ACKs or restarts a closed
   worker. An older or missing extent is explicit, never a latest alias.

The service still has bounded shared scheduling/cache accounting. Sources can
prepare independently across owners, while a single mutable physical writer
region has one writer. A reader does not build an index or hold a project-wide
writer lock. Cross-project dictionaries and all-source certification remain
complete; this plan does not introduce a project-sized mutable head.

## Verification before adoption

Reproduce A1 captured/A2 prepared, then fulfil A1 through the normal worker
without changing its original heads. Verify new/old readers together, missing
or divergent deltas, duplicate interests, cancellation, full admission,
restart and source-only recovery. Exercise raw/project/read-only inputs and
private usage capture. Neither a storage primitive nor a warm call alone is
the fulfilment test.

Run combined publication/preparation/search at declared 10/40/80-client rates,
then the eight-hour workload. Record queue age, stable preparation debt,
bounded RSS, hook p99 below 30 seconds and actual necessary-original delivery
of at least 98% by condition. Multi-host authentication and NAS durability
remain separate checks. The fixed matched token/quality adoption gate still
applies; no result here adopts a product change.
