# Literal nomination over the complete retained WorkGraph

Isolated continuation of `6c0e40a4`, not adopted. Answering-model calls are zero;
matched token/quality comparisons remain **0/18**. The 80-client gate still fails.

The project already has sixteen independent original append owners. This change
does not serialize their publication, change ownership, add per-user project
DBs/caches, alter MiniLM, or grant recommendation any completion authority.

## Diagnosis and isolated change

The retained project contains all 82 exact tool inputs/outputs. A native audit
uses the actual complete postings and canonical owner identities. For the full
readback question, the requested original matches three question terms but is
ranked **81st**, outside the eight lexical nominations; eighty earlier answer
records share much of the question wording. Removing the sentence-final period
alone does not fix that ranking. [Full rank audit and rejected ablation](word-only.json).

The word-form-only ablation regresses the unpunctuated full question and is
rejected. The next [isolated product patch](candidate.patch) keeps the raw word
and optionally adds an alias without trailing `.`/`:`. Among the existing ranked
matches, it stably puts matches to structured literals (digits, identifier/path
punctuation) first, retaining score order within each lane and the eight-owner
nomination limit. This intentionally changes nomination order; it does not claim
byte-identical delivery or token improvement. Gold fields are used only in the
auditor, never in product routing. The product uses already-loaded postings,
without a new original-body parse or DB scan. Producer identity already depends
on grammar/ranking source bytes, so candidate indexes are explicitly prepared.

## Actual single-client delivery

The original sixteen source heads are fixed for all arms. Each cell counts the
two actual frozen fields, not merely valid hook JSON.

| Question | Parent | Word forms only, rejected | Literal-first candidate |
| --- | --- | --- | --- |
| Original full question, ending in `case-79.` | 0/2 | 0/2 | 2/2 |
| Same full question without final period | 2/2 | 0/2 | 2/2 |
| Bare identifier | 2/2 | 2/2 | 2/2 |
| Bare URI | 1/2 | 1/2 | 1/2 |

The last two arms change question intent and are diagnostic, not 98% evaluation
cells. The URI arm still delivers only the tail field. Candidate hook processes
take 1,351–2,292 ms; these four sequential observations do not establish a causal
speedup or p99. The candidate preflight warm takes 7,029 ms; the parent has no
explicit warm. All original heads remain unchanged and services exit normally.
[Probe receipts and actual stdout](probe.json).

Nine Lean laws establish word-boundary properties and stable partition membership
and order. A declaration audit reaches the actual nomination and grammar code.
The unchanged standard ContractAudit passes. Native grammar checks cover 24
examples, 11 literal classifications, stable routing, four multilingual probes,
224 streaming/oracle comparisons, 200,000 scalars and 4,364 category boundaries.
These are not retrieval-recall, distributed-ownership or whole-runtime proofs.
[Laws](laws.txt), [contract](contract-audit.txt), [native grammar](grammar.txt).

## Eighty readers still fail at cold frontend startup

The next native test prepares the retained project once (1,973 ms), audits all
82 exact originals, then starts eighty lightweight clients together with a new
private root and a **cold shared frontend**. Only **4/80** deliver both fields.
All four admitted searches use the configured meaning route. The other 76 fail
before operation admission: every failure receipt identifies the same
`daemon-start.guard` timeout. This path calls `withLockWithin ... 200` and does
not wait against the hook's absolute 30-second deadline. Releasing a startup
guard does not make waiters recheck a newly ready endpoint after their own
lock-acquisition timeout.

This is a distinct startup/admission defect. It does not show that the literal
fix regressed the parent's 6/80 result: that earlier protocol had a running
frontend, historical sessions and preceding writer loops. Do not compare the
two protocols as matched capacity results. The new burst is also not evidence
of lexical fallback correctness under sustained load: none of its four admitted
queries needed fallback.

All eighty measurement records and failure receipts are retained. Hook times
range from 258 to 9,976 ms, including early failures. The test exits nonzero;
the guard does not trigger and records no remaining owned processes. Peak
sampled aggregate RSS is 2,041,232 KiB. The sixteen original heads remain frozen.
[Summary](summary.json), [actual bodies](native-trials.json),
[stages including failures](native-stages.json), [originals](original-heads.json).

One initial readback controller rejected its own fresh directory because the
numerical keeper created that directory first. The harness check now precedes
keeper startup; the failed attempt is retained. The four-arm probe uses build6,
the readback uses a diagnostic-only build7 relink with identical product bytes.
The earlier word-only probe's exact executable hash was not captured before its
diagnostic relink; that provenance gap remains explicit in its rejected record.
[Identity](identity.json), [guards](guards.json), [failures](failed-attempts.json).

Next repair shared frontend startup without a per-client startup lock convoy or
arbitrary short admission cutoff; retain process-ownership and cancellation
checks. Then test cold startup and already-running operation separately before
the full 5–50 KB writer/readback protocol. Query queueing and repeated prepared
WorkGraph work remain independent unresolved costs. Keep parallel original
owners, complete certification inputs, shared project preparation and existing
resource/deadline limits. Eight-hour capacity, multi-host/NAS, 98% real evidence,
answer quality and inclusive-token improvement remain unproved.

Ended diagnostic DB/cache directories, the standalone grammar executable and raw
logs are deleted after sealing. No archive is created. The retained sixteen-owner
source project and current comparison/build inputs remain needed by the next
diagnostic. [Cleanup](cleanup.json).
