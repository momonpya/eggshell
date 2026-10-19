# Pilot usage accounting

`tools/pilot_usage.py` audits a saved Codex App Server JSONL exchange offline.
It does not launch a server, start a model turn, acquire a seed, or establish
that a comparison is ready to run. It is a component of the still-unfinished
[pilot protocol](pilot-protocol.md).

The [official App Server documentation](https://learn.chatgpt.com/docs/app-server)
defines the JSONL transport, request/response IDs, turn lifecycle and
`thread/tokenUsage/updated` notifications. On 2026-10-20 the installed
`codex-cli 0.145.0` generated the schemas with:

```sh
codex app-server generate-json-schema --experimental --out /absolute/pilot/schema
```

Its `ThreadTokenUsageUpdatedNotification` contains `total` and `last`
breakdowns. Each has input, output, cached input, reasoning output,
and total counters; cache-write input is optional. The local schema bundle and
its hashes are retained in the evidence directory below. Generate and check
the schemas again if the runner's CLI changes.

## Capture and audit

Capture stdin and stdout in one ordered file per server process, wrapping each
unmodified wire message with its direction. Label every client `turn/start`
with a unique attempt ID and either `seed` or `trial` role. For example, this is
an envelope, not an additional App Server wire field:

```json
{"direction":"client","attempt":{"id":"topic-1-fresh-r1","role":"trial"},"message":{"id":7,"method":"turn/start","params":{"threadId":"actual-thread-id","input":[{"type":"text","text":"fixed task prompt"}]}}}
```

Include the successful `thread/start` response and every seed/history turn
from that new thread's origin. A continuing native chat can be audited when
its entire captured history is present. Importing or resuming history whose
usage baseline is absent is unsupported. Keep collection order, including
notifications that arrive before a turn's start response or after completion.

```sh
python3 tools/pilot_usage.py \
  --capture /absolute/pilot/capture.jsonl \
  --output /absolute/pilot/new-usage-audit
```

The output directory must be new. It retains the input bytes, auditor source,
their SHA-256 values and `audit.json`. Exit zero means the reported usage
boundaries can be allocated; it does **not** certify complete billing.

For each thread the auditor interprets `total` as a cumulative counter and takes
differences between consecutive turns' final counters. Repeated or partial notifications and `last`
snapshots are never added together. Reported total must equal inclusive input
plus output. Cached input, reasoning output and cache-write details are
retained but never added a second time. Invalid counts, inconsistent
differences and decreased counters invalidate the allocation.
This interpretation and its boundaries still need validation on live provider
traces before trial collection; the schema's field names alone do not prove
their accounting semantics. Only synthetic exchanges have been audited here.

Every attempt remains in the report, including failed, interrupted,
unacknowledged and request-error attempts. A missing usage boundary is `null`,
not zero. If a seed boundary is absent, the next trial cannot absorb that
seed's cost. The eventual thread total may still be known while its allocation
between seed and trial remains unknown. A genuinely zero measurement requires
an explicit usage update with zero counters.

Unassigned turn events, overlapping captures, missing/duplicate completions,
unsupported history operations and unreviewed client methods prevent a
complete-capture result. Hook execution, rerouting, additional agents and
server-initiated requests require a separate execution audit. This auditor
does not establish instruction, hook, tool or filesystem isolation.

## Billing boundary

The public protocol and generated schemas do not establish that every billed
failed upstream request appears in the thread's counters. The report therefore
always says `billing_coverage: not-established` and `adoption_eligible: false`.
An error's retry flag and failed-attempt reported usage are preserved; missing
consumption is never estimated from text length or silently discarded.

Before reporting the AGENTS.md inclusive metric, the runner must reconcile
the reported counters with provider usage evidence that covers failed and
retried requests, including any independently invoked models. This can
require additional provider instrumentation. Account-wide daily totals
cannot assign cost to an individual matched trial. Pricing, amortization,
matched-cell summaries and adoption decisions are outside this auditor.

## Validation evidence

Run the synthetic controls without a server or network:

```sh
python3 -B tools/check_pilot_usage.py
```

They cover duplicate/partial cumulative updates, seed/continuation boundaries,
independent threads, zero versus unknown, counter reset and inconsistent
subsets, out-of-order responses, late updates, failed/interrupted/retried
attempts, omitted events, malformed input, immutable CLI outputs, and required
execution-audit cases. These are accounting controls, **not model outcomes**.

Local evidence is under
`/Users/ovm/.codex/experiments/eggshell/pilot-transport-20261020/`:
the installed CLI schema bundle, schema provenance, frozen audit/control
sources, full control logs, and an end-to-end **synthetic** capture/report.
Model trials and seed acquisition remain at zero. Production Eggshell source
and executables are unchanged, so the existing warm latency and generation
benchmarks are not repeated for this offline tool.
