# Bounded source-pin transport groups

Isolated continuation of `4cc95e15`, **not adopted**. Candidate executable
SHA-256: `a7b2314bfd9152c2597ef6b05f4a08584b2e80019df4c09a5962ec82dba6dd6f`.
The parent executable is `input-frame-build/StudyMain`. Both retain sixteen
independent append owners in one logical project, three search workers, original
queue/memory/deadline limits, MiniLM, full certification and extraction behavior.

## Evidence before the change

Two ordinary lexical hooks take 2,439/1,514 ms. In the running case, the operation
takes 519 ms and the indexed lexical pass reaches render completion at 206 ms.
These are distinct nested scopes, not a claim that all remaining time is one
function. A separate one-second native sample, verified against the query worker's
exact executable and parent PID, shows repeated prepared-source opening and
`resolve`/`ready` RPCs. The worker process already persists between requests;
introducing a persistent worker is therefore not the missing fix. The
[stack excerpt](parent-stack.txt) records observed call paths; recursive stack
counts are not CPU percentages. Sampled times are not performance comparisons.

## Change and contract

The [patch](candidate.patch) groups up to sixteen source retain requests into one
authenticated exchange. Sixteen is a transport group bound, not a project-owner
limit: larger inventories are processed completely in multiple groups. The server
still calls the existing scalar source/head/manifest path for each entry. The
client checks every returned entry with the same scalar scope/manifest/retention
checker and rejects a changed reply inventory. An invalid entry has an explicit
failure at its own position. No source is silently omitted.

Captured shared and requester-private usage readers are still opened separately
with their existing checks. Successful canonical attachment preserves their source
and private usage. Uncaptured preparation retains its existing scalar path. Release
requests are grouped for the exact local service owner; each item must present
its own read capability. Foreign endpoints keep their own scalar release path.
Original hard expiries, lease accounting and source/canonical payloads are not
changed. A lost response can leave unknown leases until their existing expiry;
this does not prove immediate cleanup after every transport failure.

The [Lean laws and declaration audit](proofs.lean) connect actual batching to the
existing scalar checks, source-local shared/private restoration, and the ordinary
hook. The two field-preservation laws use only standard axioms. Ordinary
ContractAudit passes. This is not a proof of complete concurrent/distributed IO,
arbitrary wire decoding or all-failure cleanup.

## Native component check

Three alternating scalar/batched pairs return all sixteen identical source
identities in the same order. The first scalar open, 413 ms, includes cold
service preparation and is not a warmed speedup control. Warm scalar opens take
97/98 ms versus 52–53 ms batched; scalar releases take 24–25 ms versus 1–2 ms.
The checks also cover a short reply, a server-side oversized request, one wrong
captured manifest with all other fifteen sources retained, an unauthorized release,
and thirty-two inputs across two transport groups. Ordinary `prepareMany` retains
all sixteen canonical inputs and the captured private usage roots. All 159 acquired
leases are released: active handles, readers and charged bytes are zero, with zero
expirations and exact accounting.

The initial audit correctly fails without a prepared frame; the final audit first
performs ordinary warm. An initial test also passed equal acquisition and holding
deadlines, which violates the existing lifetime contract after transport; the
final test uses a strictly earlier acquisition deadline. Neither production limits
nor the original expiry contract were widened. Build/check/controller failures
are retained in the compact evidence rather than counted as successful checks.

## Actual hooks and contemporaneous eighty-reader pair

Same retained 82 originals/16 heads, question, MiniLM, 120,000-character budget
and harness. Three meaning pairs alternate order; one additional lexical pair
checks the fallback path. All sixteen actual bodies are byte-identical within
their route: meaning 88,578 bytes and lexical 13,566 bytes, both frozen fields present.

| Meaning pair | Cold parent / candidate | Running parent / candidate |
| --- | ---: | ---: |
| 1 | 7,195 / 8,232 ms | 4,689 / 5,474 ms |
| 2 | 8,435 / 8,529 ms | 5,644 / 5,491 ms |
| 3 | 8,337 / 8,364 ms | 5,683 / 5,376 ms |

The lexical pair is 2,672/2,709 ms cold and 1,666/1,472 ms running. Whole-hook
improvement is not consistent across these pairs; the first meaning pair worsens.
Do not substitute component time or the best pair for a practical speedup claim.

| Cold native eighty-reader burst | Parent | Candidate |
| --- | ---: | ---: |
| Both required original fields delivered / client success | 25/80 | 64/80 |
| Admitted operations / complete captured inputs | 80/80 | 80/80 |
| Measurement range, failures included | 17,709–29,795 ms | 11,388–29,760 ms |
| Final operation observations | 28 | 68 |
| Observed queue median / maximum | 19,915 / 25,444 ms | 19,418 / 25,450 ms |
| Observed work median / maximum | 1,479 / 15,006 ms | 644 / 8,197 ms |

This is one predeclared parent-then-candidate pair, not a repeated capacity or p99
result. Historical 49/80 is not its matched control. The candidate has six completed
meaning phases, sixty-one skipped expired meaning windows and twelve retirements
before execution. Its sixteen client failures report nine daemon receive deadlines
and seven owned-task deadlines. Final operation observations are not all-request
latency statistics. **The capacity gate still fails.**

All 82 saved input/output originals remain exact; all sixteen original heads stay
unchanged. Peak aggregate RSS over builds and trials is 2,820,496 KiB, with no guard
trigger or owned survivor. [Evidence](evidence.json) preserves actual deduplicated
bodies, runtimes, all client failures and native receipts. Ended trial DBs/caches/raw
logs are deleted without archives; active candidate/control builds and the original
cut remain necessary.

Keep the candidate isolated while addressing remaining query work and queue drain.
Parallel original owners are already connected and are not increased here. Combined
save/preparation/query load, larger/mixed-project cuts, real 98% evidence delivery,
eight-hour eighty-person use, NAS/multiple hosts, p99, quality and total-token gains
remain unverified. Answering-model calls are zero and paid comparisons **0/18**;
there is no product, README benchmark or release adoption.
