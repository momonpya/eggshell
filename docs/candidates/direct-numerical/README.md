# Direct numerical ownership inside providers

Isolated continuation of `c96b875e`, not adopted. Answering-model calls are zero;
paid matched comparisons remain **0/18**. Public product/README results and
releases are unchanged.

`SearchProvider` previously launched another full native executable merely to
bridge a provider's requests to the shared numerical daemon. The candidate
factors that bridge into `Numerical.Client` and owns it directly in Lean. The
pipe CLI calls the same client. It retains a numerical keeper, an optional
endpoint, an optional local score process and a closed flag; it retains no
query/corpus/response and adds no global client pool or new mutex. Each client
has one sequential provider owner.

Encode and projected-block requests still use the existing bounded shared
service. Large cache-only score frames still use the existing local NumPy
boundary. Close retires that local process before releasing the keeper, rejects
later requests and is idempotent. This is not a proof of arbitrary concurrent
IO or a lock-free runtime. MiniLM, block scoring, graph/Exact/Union authority,
ranking, Handoff, original publication and provider protocol sources are
unchanged; [identities](identity.json) and the [patch](candidate.patch) record the
two changed product modules.

The first native component attempt exposed a framing defect: direct callers
omitted the newline that the old pipe's line reader supplied. That attempt
timed out and is retained as a failure. Both routes now call `requestBody`,
which preserves already-terminated input. Four pure Lean laws and actual
declaration-dependency checks cover the channel selection, exclusion of local
scores/close from shared requests, unchanged terminated frames and use of the
direct client in the provider. They use only standard Lean axioms. The standard
ContractAudit passes. [Laws](laws.txt), [audit](contract-audit.txt),
[failed attempts](failed-attempts.json), [terminal guards](guards.json).

## Numerical and fixed-source checks

The [predeclared protocol](plan.json) alternates arm order across three matched
pairs. All vectors, token coverage and scores agree. Every pair also scores a
9,229,675-byte local frame, larger than the 8 MiB RPC bound, with all 1,500 unit
products equal to one. Cache-only scoring starts no embedding service; a second
live owner keeps the same service and values after the first closes; closing
the last owner leaves no service. [Components](components.json),
[actual numerical values](numerical-values.json).

| Pair | Parent pipe: six operations and close | Direct client |
| --- | ---: | ---: |
| 0 | 2,075 ms | 1,240 ms |
| 1 | 1,569 ms | 1,247 ms |
| 2 | 1,544 ms | 1,252 ms |

Steady encode/block calls are not consistently faster; the removed process
primarily reduces initial setup and transport. These are component timings,
not hook latency or token savings.

One retained original boundary, all sixteen source owners, the same prepared
roots and the same question produce identical complete keyed JSON responses
in all six provider calls. Every rank, window and coverage field is compared;
the original heads remain unchanged. Parent provider times are
1,699/1,681/1,671 ms; candidate times are 1,427/1,439/1,420 ms.
[Frozen request](frozen-request.json), [actual response](actual-response.json),
[repetitions](replay.json). This small domain is not large-domain recall.

## Ordinary traffic still fails at eighty

The corrected eight-reader ordinary protocol delivers all four frozen fields
in every initial body, with complete prepared turn inputs and completed meaning
search. Hooks take 1,395–3,432 ms. This fresh fixture is not a matched production
speedup against the previous cold/warm fixtures.

The next ordinary 80-writer trial, using 5 KB outputs and sixteen source owners,
fails: **44/80 initial deliveries and full writer loops complete, 36 initial
hooks time out**. Maximum initial latency is 29,860 ms. The 50 KB and fresh-reader
waves are not run after this failure. Peak aggregate RSS is 2,831,152 KiB,
below the unchanged 3.5 GiB stop and 4 GiB hard ceiling; shutdown leaves no owned
process. This is not eighty-person sustained capacity, p99, 98% real-evidence
delivery, a token/quality result or adoption.

All eighty turn-input probes report complete. The cause is not a missing owner
reference in this trial. Successful calls have service queue p50 8,337 ms,
maximum 12,816 ms and processing/transport p50 1,174 ms, maximum 2,076 ms.
Of 44 successful bodies, 33 finish meaning search and eleven use lexical
fallback. Only eight of 36 failed calls have a final service observation, with
queue times 12,817–13,086 ms; the other 28 are unobserved at that stage.
[Actual outputs and errors](native-trials.json), [stages](native-stages.json),
[summary](stage-summary.json).

`deliverForWork` submits meaning search to the three search workers, then
submits lexical fallback through the same service when the first response is
incomplete. It also requests background warm on timeout despite these complete
captured inputs. This can add more admission/preparation work under saturation.
The current per-receipt service observation can overwrite the earlier attempt,
so the observations do not measure the complete cost of both attempts or prove
that this is the sole cause. Do not blame a 30-second lock holder, cold input or
the numerical kernel from these data.

Next retain per-attempt route/id/timing, then make fallback part of one admitted
search lifecycle with the original absolute hook deadline and exact input
boundary. Cache-miss repair must follow actual typed debt; queue expiry must
not masquerade as missing cache. Preserve the complete certification domain and
do not enlarge worker counts, admission bounds or timeouts to hide this failure.
The full 80-client protocol must pass before the broader multi-project,
large-domain, sustained-load and matched token gates.

Ended component/replay/reader fixtures and raw logs are [deleted](cleanup.json),
without archives. Only the failed small1 fixture remains an active input for
the admission/fallback investigation, along with current build/control inputs
and protected originals.

Subsequent status: the [single-search continuation](../single-search/README.md)
sealed this failure, then replaced the active diagnostic with its post-write
readback fixture. The old small1 DB/cache and remaining raw log were
[deleted](../single-search/cleanup.json), without an archive. Current comparison
runtimes and required build inputs remain; this document's 44/80 result is the
historical parent result, not the latest candidate's complete gate.
