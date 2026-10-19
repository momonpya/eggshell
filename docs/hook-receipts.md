# Native hook receipts

Unadopted diagnostics in the development candidate. Normal use assumes a warmed
DB. Cache ownership and warming do not supply an LLM-token reduction claim when
the same body is delivered. These records do not change the public handoff format.

Each native invocation gets a random identity before stdin is read. Its private
records live at `EGGSHELL_DATA_ROOT/receipts/<identity>/`, independently of the
chat directory and DB graph. Each process atomically replaces its own stage file;
there is no shared log lock. Files use mode 0600 and directories use 0700.

| Stage | Observation |
| --- | --- |
| `ingress.json` | The supervised child started, with the absolute deadline. |
| `request.json` | Parsed event/session/turn, input byte count and input-read time. |
| `failure.json` | A caught ingress/request error, when available. |
| `search.json` | Semantic state, selected route, stage durations, returned completion counts and explicitly untracked equality origin. |
| `numerical-*.json` | Actual cache-availability probes, scoring counts/times and the observation's completion state. |
| `dispatch.json` | Manager handler duration and success/error. |
| `transport.json` | Terminal-capture, manager-start and RPC durations. |
| `published.json` | Exact stdout bytes, byte count, SHA-256, reply validity and monotonic start/flush/deadline times. |
| `ack.json` | Whether the acknowledgement RPC completed and whether the live offer was accepted. |

Empty responses also receive publication records. An incomplete child reply or
held stdin records the actual incomplete response emitted by the supervisor.
Missing stages show which boundary was not observed; they are not zero durations
or evidence of a completed search. `replyComplete` means that the transport reply
was a valid hook object. The semantic search status is a separate observation.

The stdout receipt is written only after stdout flush, through a supervised RPC
subprocess that shares the original deadline. This process can record a failed
or empty request without starting a chat manager. A receipt write failure is
reported on stderr and cannot replace the already emitted output. A stdout flush
is not confirmation that the host app or language model ingested the body.

## Numerical observations

The built-in provider receives the same receipt identity inside its request;
provider commands and index-lane identities remain stable. `source` and `query`
counters distinguish valid hits, files observed absent after a failed probe,
and existing/unusable records. They count initial availability probes, including
repeated source-window references, rather than unique DB keys or repair rereads.
Query probes describe availability before query preparation; source repair is
still prohibited for ordinary cold durable windows.

`corpus` records requested documents/window references, cache-owned document
count, and whether the purpose is discovery or source focus. Focus views may
need derived windows even when all original DB windows are warm. A running checkpoint is published on the first source probe, every 32
source probes and query probes. The provider replaces it with `completed` or
`failed` when that request returns. If killed, its last checkpoint is an observed
prefix, with up to 31 subsequent source probes unrecorded. Never extrapolate its
hit rate to the requested corpus or treat a missing/custom-provider record as
zero misses. `cacheMs`, `queryMs` and `scoreMs` are nested measurements and must
not be added as disjoint durations. Query time includes preparation and cache IO.

## Remaining requirements

This is a per-invocation audit trail, not a complete Phase 0 result. Runtime
equality ancestry and selected-role dependencies remain untracked. The existing
selection diagnostic has not been promoted into a delivery-wide classifier.
The original `hook output missing` incident is deferred at the user's request
on 2026-10-19 and excluded from current investigation. It may concern the Claude
environment, but neither that environment nor the cause is confirmed. It is not
resolved and does not block the remaining measurement work. Ingress fault
fixtures establish only their own mechanisms. DB-size-independent latency,
host ingestion, the pilot, proofs/rules, full experiments and paper are still
required by `GOAL.md`.
