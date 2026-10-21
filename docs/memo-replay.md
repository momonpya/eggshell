# Captured memo publication and replay

The development source now carries the completed-authorization certificate
through discovery and binds persistent memo replay to the current request
and external nominations. The installed application binary and release have
not been replaced. Evidence and exact source hashes are in
`docs/memo-replay-review.json`.

## Implemented binding

`DemandMemo.readChecked` retains the complete request equality established
by the existing request gate. `readObserved` carries that proof together with
the current nomination equality. A hash nominates one of eight slots; the
complete request still decides whether its record belongs to the caller.
There is no second request comparison in the observed-read path.

The actual automatic-handoff publisher constructs a `CapturedRecord` from
the computed response, pinned source heads, captured read program and current
nominations. `publishCaptured` consumes that object. Its proof fields erase,
and the stored Record codec is byte-identical to the previous codec.
`captured_decode_keeps_origin` proves that canonical record decoding retains
the captured request, payload, nominations, source heads and read program
together.

Replay decodes the Handoff and accepts it only if re-encoding gives the exact
captured payload bytes. Decoded fields cannot silently drop or normalize
parts of that payload; noncanonical optional responses are rejected. A completed cache hit
with no context remains distinct from a cache miss. Search-incomplete
responses remain ineligible for reuse. Source-head/neutral-chain and exact
read-program validation keep their existing behavior, and external source
files are rechecked by the ordinary delivery path after replay.

The kernel theorem and producer integration described in
`docs/completed-authority.md` are included in this source change. The packet
renderer and the matching implementation preceding Discovery are unchanged.
MiniLM, providers, source-evidence checks, worker, hooks and graph store are
byte-identical to the previous working implementation.

## Current receipt and original locator

A successful memo lookup writes `memo-replay.json` under the current hook
receipt. It records request/payload SHA-256, the current nomination and graph
dependency checks, and the original equality-selection locator already
carried by the Handoff. It stores no plaintext request or response.

| Origin value | Meaning at the memo stage |
| --- | --- |
| `no-completed-work` | The cached result carries no completed/control work. |
| `locator-carried` | Completed/control work retains an equality snapshot locator. Its complete ancestry has not been independently replayed. |
| `untracked` | Completed/control work lacks that locator. It cannot count as tracked direct-only or congruence-free delivery. |

`externalSourceCheck: delivery-stage` states where freshness is checked;
the memo-stage receipt does not claim that the check has already succeeded.
Its payload checksum identifies the cached computation before source and
transport reconciliation, rather than the final stdout bytes.

## Verification

A native fixture created a small isolated DB and exercised the actual
publisher and `demandResponse?`. It passed:

- exact replay of the original code text and complete serialized response;
- different requests sharing the same slot, and changed nomination order;
- a captured no-context result, noncanonical payload and incomplete notice;
- changed observed source input, including a previously absent key;
- current receipt checksums, deferred freshness labeling and honest
  `untracked`/`locator-carried` classification.

ContractAudit checks the actual captured publisher, request-bound reader,
canonical replay and receipt caller. The final native fixture, test support
and complete `TestMain.lean` elaboration passed. The full IO suite and six
LLVM delivery stages were not executed for this change. Setup/interpreter
failures and their partial directories remain alongside the successful run.
The memo work's sampled aggregate RSS peaked at 2,833,856 KiB; no resource
guard fired. Answering-model calls and new seeds were zero.

The standard test runner includes the new fixture. It can also be run alone
with an isolated data root and a fresh DB path:

```sh
LEAN_NUM_THREADS=1 lake build memo_replay_tests
EGGSHELL_DATA_ROOT="$PWD/.lake/memo-replay-data" \
  .lake/build/bin/memo_replay_tests "$PWD/.lake/fresh-memo-replay.egg"
```

## Remaining boundary

Captured publication and exact replay do not prove the filesystem writer's
exclusivity, complete dependency capture, JSON codec refinement or the source
reader's complete Value-to-owner binding. The original equality locator
still describes selected components; generator scheduling, original-child
roles and final-fragment ancestry remain incomplete. These IO/model
boundaries prevent a complete Phase 0/2 claim or a Phase 3 congruence fraction.

Required original-code coverage across both LLVM laps remains a separate
unfinished delivery check. The source-context tuning candidate has not been
integrated. This change does not claim token savings or answer-quality
improvement, and neither metric alone rejects appropriate delivery.
