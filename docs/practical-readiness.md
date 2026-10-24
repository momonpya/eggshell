# Practical readiness gates

The development candidate is not ready for ordinary MCP use or a paper pilot.
Unit tests and original-byte delivery receipts do not establish these gates, and
performance work remains isolated under the adoption conditions in AGENTS.md.

## Priority and current evidence

1. Remove repeated catalogue construction from hooks. The isolated single-source
   path now shares a prepared domain for catalogue, Work/native views and numeric
   topology; original owner validation remains on admission. Cold fallback still
   invokes `Store.searchDocuments`. Multi-source preparation still builds the
   complete cross-DB identity table over semantic membership. The small/real-DB
   stage checks in [the candidate record](prepared-candidate-domain.md) do not
   qualify full 10,000/50,000-window hooks or that multi-source path.
2. Close storage privacy before live MCP trials. `captureTerminal` persists the
   raw result before manager dispatch. `postToolUse` and operation graph
   compilation subsequently use the pending turn's single write target. No
   trusted MCP/server descriptor, per-server admission policy or credential
   exclusion currently precedes every durable path. Private usage-index tests
   do not establish private capture of MCP observations.
3. Measure the complete latest hook at scale, including candidate loading,
   numeric setup/scoring, postings, admission, source checks, packing, commit and
   stdout. Earlier implementations did run 50,000-window hooks and timed out;
   the latest native-observation candidate has no qualified 50,000-window result.
4. Only after these pass: live-server lifecycle, daily growth, then one week of
   ordinary use and receipts. Paper comparisons follow practical qualification.

## Prepared candidate domain

Build the complete ordered owner/Work/window/topology domain during publication
maintenance or explicit/background warm. Keep one bounded packed payload plus
an atomic readiness record tied to source changes and the actual implementation
bytes. A derived-only memo publication must not force a complete rebuild.
Retraction, replacement and a different DB incarnation must invalidate it.
Read-only shared DBs use the private DB-identity overlay.

A hook opens and verifies the domain once and shares it between discovery,
focus and fallback. It does not repair it, reopen a current head, enumerate all
owners or decode all Work/Outcome payloads. Lexical nominations come from
postings and retain original stable order. Numerical ranking keeps the complete
ordered window population. Only admitted owners and delivered original ranges
are hydrated from the pinned source. Cached nomination metadata cannot replace
an original owner or confer Exact/Union authority.

Before model calls, compare ordered candidates, Work/native views, topology,
rankings and delivered bytes against the fixed-snapshot reference path. Record
corrupt/partial/stale/read-only cases and actual DB read observations. A fast
open microbenchmark is not a full-hook latency result.

## Latency protocol

The initial practical target is p95 <= 3 seconds for both first and subsequent
hooks on a warmed 50,000-window DB. Thirty seconds remains a hard ceiling, not
the target. Measure 50 hooks per category at 2, 1,024, 10,000 and 50,000 windows,
and a fixed real DB. Freeze runtime SHA, source snapshot, questions, provider,
cache state and harness before measurement. Define p95 by nearest rank
`ceil(0.95 * n)`; retain every attempt, including timeout, incomplete stdout and
fallback. Report semantic completion separately from usable fallback delivery.

Separate explicit cold-import/warm duration from warmed new-chat hooks. Record
stage timings, read counts, payload bytes, peak aggregate RSS and free disk.
Keep all experimental processes together under 4 GiB; the existing guard stops
at 3.5 GiB. Generate scale fixtures in bounded publication batches and avoid
retaining obsolete complete DB copies.

## MCP capture policy

The target default is private storage for external observations. Unknown origin
is private as well. Identify server/account/tenant from trusted adapter metadata;
do not infer storage authority from a tool-name prefix, shell spelling, a file
certificate or response text. Allow/deny configuration is per trusted server
identity. Explicit sharing is separate from recording permission.

Apply the policy before terminal capture, live journals, recovery snapshots,
checkpoints and answer publication. A final answer can quote a private result,
so routing only the raw MCP result is insufficient. Preserve that dependency or
conservatively keep the entire affected turn private.

Credential-bearing arguments are excluded before any durable write. If the
actual operation cannot be retained without credentials, omit that observation
and record a content-free reason; never substitute redacted arguments as if
they were the executed Exact Work. Tests must scan all durable artifacts for
secret sentinels and prove that private results and derived answers are absent
from the shared DB, not merely absent from a derived usage index.

## Changing locations and storage growth

Index a stable resource locator separately from exact observed content. Scope
it by server, principal/tenant and resource identity. A new observation at the
same location retains history and links versions for recommendation; it does
not unify old/new bytes or certify old state as current. Preserve acquisition
time and invalidation metadata. The 30-day age hint alone grants no completion.

Before live use, set and record explicit storage budgets for queued capture,
individual observations and retained private history. On budget exhaustion,
record an omission without corrupting an already captured original or claiming
an incomplete result was complete. Measure bytes and windows added, duplicates,
compaction amplification and cleanup after a representative day, including
large JSON results. Choose defaults from that measurement; no daily growth
limit has yet been validated.

## Live acceptance and later token adoption

Use an actual read-only MCP server with a real Codex session only after capture
privacy passes. Exercise Pre/Post/Stop, interruption/retry, new-chat warm reuse,
resource mutation and principal changes. Record one day first, then one week.
No such live trial has passed yet. Zero observed false completed reuse requires
changed-state and changed-invocation controls with an explicit denominator.

Practical gates do not replace token adoption: compare the same saved snapshot,
source, questions, model, reasoning and harness for topics 1/2/3, first and
history-bearing use, using predefined equal repetitions. Count input plus
output, cached input and failed attempts; separate seed cost. Preserve quality,
delivery receipts and deadlines. Do not adopt a candidate on latency, tests,
proofs, delivery size or the best single token result alone.
