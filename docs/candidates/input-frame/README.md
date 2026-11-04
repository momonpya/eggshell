# One prepared-input representation on the worker wire

Isolated transport candidate, **not adopted**. The parent is `0071fae6`, whose
active control executable is `prepared-lexical-build/StudyMain`. The candidate
executable SHA-256 is `6c800c8ca323f24478abf16db9b990e33528b01b52ba34492cff4022fa2d1fbe`.
This does not change parallel original ownership, search workers, queue limits,
deadlines, MiniLM, nominations, certification, extraction or source contents.

## Measured duplication and the actual change

Ordinary capture puts prepared inputs, originals and owner roots both in explicit
`Worker.Search` fields and inside `pending.preparedInputs`. The read-only audit
measures 310,865 charged bytes, including a 145,001-byte duplicate envelope.
The initial unsent removal preview is only a size diagnostic; it is not safe to
use as a destructive drop because dependency checkpoints consume the pending turn.

The [patch](candidate.patch) validates capture first, replaces only the duplicate
wire envelope with its producer reference, and reconstructs the complete pending
turn before the existing search implementation or dependency callbacks run.
The private pending record is not rewritten. Invalid ambiguous references are
rejected. The actual serialized whole request is restored byte-for-byte in the
native codec check. Ordinary hooks exercise the real transport: six large parent
worker envelopes are 311,128–311,134 bytes, versus 166,220–166,226 bytes for the
candidate. Source/private-root checks and the complete read inventory remain.

The [Lean checks](proofs.lean) establish whole-request restoration for the stated
canonical-frame premises, identity and fallback preservation, and equality of
search IO actions when restoration yields the original request. They do not
prove arbitrary JSON round trips, concurrent IO correctness or distributed
authorization. Seven negative native cases reject inconsistent original/private
roots, missing inputs/boundaries/owners and ambiguous references. Actual
declaration connectivity and the ordinary ContractAudit pass.

## Three alternating normal-hook pairs

Same retained sixteen-owner snapshot, fixed question, MiniLM, 120,000-character
budget and harness. Each arm uses a fresh frontend and then a second fresh chat.
All twelve actual bodies are byte-identical, 88,578 UTF-8 bytes, with both frozen
original fields present. These are sequential traced hooks, not token comparisons.

| Pair | Cold parent / candidate | Running parent / candidate |
| --- | ---: | ---: |
| 1 | 7,232 / 6,938 ms | 4,459 / 4,420 ms |
| 2 | 6,946 / 7,013 ms | 4,439 / 4,406 ms |
| 3 | 6,804 / 6,825 ms | 4,418 / 4,410 ms |

The cold result is mixed and running differences are small. A smaller envelope
alone is not evidence of practical capacity or total-token improvement.

## Contemporaneous cold eighty-reader pair

One predeclared parent-then-candidate pair, with original worker and byte limits.
Both arms admit all eighty operations and retain eighty complete input captures.

| Actual outcome | Parent | Candidate |
| --- | ---: | ---: |
| Both frozen original fields in the delivered body | 42/80 | 49/80 |
| Whole client success, including ACK | 41/80 | 49/80 |
| Observed time range, failures included | 12,063–29,793 ms | 11,631–29,761 ms |

One parent client receives both fields but its ACK is refused. This is counted
as body delivery and client failure separately. Both arms still fail the capacity
gate. One burst does not establish a causal throughput improvement. The pure
16-MiB holding model (53 full requests versus 80 compact requests) must not be
confused with observed admission: the real parent also admits all eighty while
workers drain. Queue bytes are therefore not an established explanation for
these remaining deadline failures.

All 82 saved input/output observations remain exact, and all sixteen original
heads remain unchanged. Peak aggregate RSS over builds and trials is 2,832,000 KiB;
no guard fires and no owned process survives. All failures, initial build/check
errors, codec audits, runtimes, actual deduplicated bodies and per-request stage
records are preserved in [evidence.json](evidence.json).

Multiple append owners **within each logical project remain mandatory and are
already connected**. Sixteen owners serving eighty sessions is not evidence of
eighty-person, eight-hour capacity. Query work/queue drain and combined
publication/preparation remain unfinished; owner count must not be substituted
for that evidence. The candidate remains isolated for further work on sharing
immutable project inputs across requests. Cross-project/read-only cuts, ordinary
save/recovery with this codec, multi-host/NAS durability, sustained growth,
real-evidence 98%, p99, answer quality and total-token gains are not established.

Answering-model calls are zero and matched paid comparisons remain **0/18**.
No product, README benchmark or release adoption is made. Ended trial DBs,
caches and raw logs are deleted after compact recording, without archives;
the active candidate/control builds and retained original cut remain necessary.
