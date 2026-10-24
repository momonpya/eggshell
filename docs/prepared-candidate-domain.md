# Prepared candidate domain

This is an isolated, unadopted candidate following `7d2e8b3`. The installed
runtime, MiniLM configuration, README results and release are unchanged. The
runtime delta is in `candidates/prepared-domain-runtime.patch`; source copies
under `tools/research/prepared-domain/` are review inputs, not a second runtime.
Apply the delta to the recorded parent candidate before compiling those tests.

## Runtime change

Publication records a source-change marker only for a non-neutral graph delta.
Derived memo publications preserve it. Together with DB identity, authority,
root frontier, candidate population and the actual implementation bytes, it
binds prepared nomination metadata to the source. Every writer in a qualified
runtime must use this publication path; mixing an older writer is unsupported.
The initial absent marker is zero, so a DB-only import can be prepared without
rewriting its original page map. A marker is not equality or execution authority.

Explicit/background warm prepares ordered owner/Work/window rows, original
native orientation and numeric All parent/child links. Each Work/native view
comes from the original pinned reader. The packed payload and readiness record
are atomically replaced in two fixed files, so source changes do not accumulate
one file per owner or per publication. A reader verifies the bounded payload's
size, digest, decoding, row count, unique/stable order and complete window keys.
The payload limit is 64 MiB. Read-only profiles prepare it in the existing private
DB-identity overlay; reading a cold domain creates no directories or repairs.

The single-source discovery path opens it once and shares it between initial
numerical nomination, later discovery, focus and Work admission. Lexical
nominations still use postings. Numerical scoring receives the complete ordered
window population. Admitted owners are hydrated from the original snapshot and
their actual Work/native orientation must agree before the existing compiler
certificate is constructed. Cached topology is only numerical ordering advice;
Exact, membership, Union and source checks retain their original readers.

A missing/invalid domain uses the original reference path and can be slower;
it cannot certify a completed empty corpus. The lightweight readiness record
is a maintenance hint. Actual opens validate the payload, and explicit warm
repairs corruption. Automatic repair after corruption is not qualified here.

## Checked evidence

The core Lean test compares candidate order, original Work/native views, window
keys and topology. Opening the domain observes only the three source keys
`sourceChange`, `roots` and `candidates`. It checks 20 derived-only publications,
new source publication, retraction, corrupted payload rejection, explicit repair,
and DB-only reconstruction in a private overlay with the source files made
read-only. Original head/pages remain unchanged.

The fixed-snapshot discovery/packet regression has two nonempty responses
(3,500 and 4,232 UTF-8 bytes) and one empty response. Original and prepared paths
produce identical bodies, completed/advisory counts, local Union counts and
blocking decisions. This is a regression fixture, not the topics 1/2/3 trial,
semantic ranking calibration or a complete Codex hook lifecycle.

On the preserved real seed DB, all 73 ordered Work/native/window rows are equal.
There are 2,117 discovery windows; the earlier 2,192 warm figure includes focus
keys as well. Reference catalogue/Work preparation took 109 ms and 491 DB page
reads. Ten independently pinned prepared opens took 13–15 ms and 10 DB page
reads each, with exactly three source-key observations. The original head/page
SHA-256 values match the pre-existing frozen review. These are catalogue-stage
measurements, not full-hook speedups or a p95 qualification.

A separate synthetic metadata microbenchmark builds 10,000 rows and 50,000
window references (3,592,254 bytes). Fifty checksum/decode/prepare runs took
276–297 ms; nearest-rank p95 is 296 ms. It does not construct a 50,000-window
source DB, read vectors, perform discovery, verify freshness or emit hook stdout.
It does not pass the full-hook practical gate.

The packed roundtrip and source-marker properties are ordinary Lean proofs.
ContractAudit verifies the publication, warm, prepared-open and actual discovery
call paths. Build/test guards stayed below 4 GiB aggregate task RSS; the largest
observed peak was 2,851,456 KiB. Full artifacts and failures are retained in
`candidates/prepared-domain-review.json`.

## Remaining work

- Measure the complete latest hook at 10,000 and 50,000 windows, first and
  subsequent calls, with fixed cache/provider state and all failures retained.
  The target remains p95 <= 3 seconds per category, absolute ceiling 30 seconds.
- Profile residual admission/frequency, numerical cache, source-check and packing
  costs. The metadata microbenchmark does not justify skipping these stages.
- Extend preparation to the multi-source path. `Federated.prepare` still builds
  the complete cross-DB identity table and reads numeric root/member/Outcome
  directories. Caching just its document list would leave its main cost intact;
  cross-source equality must retain original structural/byte witnesses.
- Make source-change maintenance incremental. Current preparation can rebuild
  the complete domain after a graph change; moving that work out of a hook does
  not eliminate its background CPU/storage cost.
- Close MCP private capture and credential exclusion before live-server use,
  measure daily growth, then collect one day and one week of real receipts.
- Qualify the whole product runtime and perform the matched inclusive-token and
  quality comparisons required by AGENTS.md. No answering-model calls, new seeds,
  token improvement or production adoption are claimed by this candidate.
