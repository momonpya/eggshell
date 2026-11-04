# Subset lexical rank: exact, locally faster, not promoted

Isolated investigation after `b9eac443`. The candidate is rejected as the next
runtime: no useful eighty-reader capacity improvement was established and the
matched total-token/quality gates remain unrun. The active isolated source is
restored to `prepared-lexical-build/StudyMain`. Multiple append owners within
the project, complete certification, MiniLM, synapses, ranking policy, budgets
and worker limits are preserved throughout.

## What was actually repeated

`refocusObservedNeighborhood` parses the admitted original text again to compute
local lexical ranks. The same text already has published lexical membership.
Global IDF is not an equivalent replacement: frequencies and population must be
computed over the exact selected row sequence, including duplicate rows.

The first read-only native audit uses the retained sixteen-owner source with
163 candidates and 415,948 original search-text characters. Eight questions
across seven sequences (empty, singleton, eight, half, full, reverse, duplicates)
produce 56 identical complete rankings and 6,216 point comparisons. Five
alternating repetitions take 179–199 ms parsing versus 5–13 ms in the initial
prototype. That prototype first unions term bitmaps, so its small-fixture speed
is not a large-DB algorithmic guarantee.

The product candidate points into each captured source's term roots directly.
It neither enumerates all common-term owners nor builds a full term union.
The final component repeats the 56 full rankings and 6,216 checks, tests a sparse
height-eight bitmap through id 10^12 and out-of-range addresses, and declines an
owner outside the captured candidate set. Parsing takes 182.2–199.9 ms versus
9.4–20.8 ms through the actual prepared reader, including eligibility checks.
Both original and dictionary heads remain unchanged.

The [patch](candidate.patch) adds `SubsetLexical.lean` and changes the common
project refocus adapter in `Handoff.lean`. Unsupported/staged rows retain the
original parser. The [Lean laws](laws.txt) prove rank equality under the explicit
term-membership invariant, preserving Float operations and tie-breaks, and
equivalence of the refocus adapter when supplied the original lexical rank.
They do not prove all persistence IO or the entire writer invariant. Declaration
checks connect these functions to discovery and forbid full enumeration/union
calls in the new term projection. Ordinary [ContractAudit](contract-audit.txt)
passes. The native comparison supplies additional finite representation evidence.

## Three fixed actual-hook pairs

Each arm performs explicit warm, then a cold-frontend and running-frontend hook.
The same original cut, question, MiniLM, settings and controller are used; order
is parent/candidate, candidate/parent, parent/candidate. All twelve actual bodies
are the same 88,578 UTF-8 bytes. All original heads remain frozen.

| Pair | Parent cold | Candidate cold | Parent running | Candidate running |
| --- | ---: | ---: | ---: | ---: |
| 1 | 9,151 ms | 8,603 ms | 5,748 ms | 5,644 ms |
| 2 | 8,563 ms | 8,635 ms | 6,038 ms | 5,826 ms |
| 3 | 8,631 ms | 8,654 ms | 5,693 ms | 5,648 ms |

Running hooks improve by only 45–212 ms; two cold pairs become slightly slower.
Actual prepared subset lookup in pair three takes 46/59 ms for 160 rows. Do not
replace whole-hook results with the much larger component percentage.

## Contemporaneous eighty-reader control

The parent is slower this turn than its prior 57/80 record, so one paired native
load check is fixed before either arm runs. Both arms use the existing cold
frontend protocol, frozen sixteen-owner inventory, 82 exact original input/output
records and two frozen required fields. No bound is widened.

| Observation | Parent | Candidate |
| --- | ---: | ---: |
| Both fields in actual body, within 30 s | 21/80 | 22/80 |
| Complete ordinary client protocol, including body ACK | 21/80 | 21/80 |
| Operation admission observed | 73/80 | 75/80 |
| Meaning / lexical actual bodies | 3 / 18 | 3 / 19 |
| All eighty turn captures complete | Yes | Yes |
| Measurement range, including failures | 20,468–29,804 ms | 19,487–29,816 ms |

One candidate body includes both required fields at 29,815 ms but its ACK is
refused. Preserve it as actual body delivery and a failed protocol; do not hide
either result. Both arms have 59 client failures and nonzero exit status.
The final 24/25 operation observations have queue median 21,420/20,741 ms and
work median 1,549/1,552 ms. These are incomplete observation populations, not p99.
The new rank calculation has not resolved the admitted query bottleneck.

The older 57/80 record is not a contemporaneous control. No thermal/performance
warning was reported by the Mac's `pmset` query, which does not establish the
cause of timing variation. Do not attribute that variation to this candidate.

## Decision and next work

Restore the parent; keep the [evidence](evidence.json), patch, checker and failed
checks, then delete ended trial DBs/caches/raw logs and the rejected executable.
No archive is created. Source hashes verify unchanged graph, vector, synapse,
owner, storage, authority and admission implementations. All guards finish with
no owned survivors or memory trigger; maximum sampled aggregate RSS across the
checks/builds is 2,855,200 KiB under the unchanged 3.5 GiB stop/4 GiB ceiling.

Next inspect repeated prepared-view restoration and input/output metadata
transport across the actual search worker/service boundary, including the
fallback path. A meaning-only local improvement cannot establish capacity when
most loaded replies are fallback. Source-owner count is not the demonstrated
bottleneck. The common-project route still restores its aggregate bitmap view;
the distinct-project reference route and complete cross-project dependency
handling remain separate unfinished work. The new local projection did not fix
those structures and must not be described as an 80-user design completion.

Answering-model calls remain zero; paid comparisons remain **0/18**. No real
98% evidence, eight-hour capacity, large-growing-DB, NAS, quality or total-token
improvement is established. Product, public README benchmark and release
adoption remain unchanged. Reproduce only after applying the isolated patch
with `git apply --unidiff-zero`, restoring the two diagnostic imports/command in
`FrontTrafficChecks` and using the guarded [setup](setup.lean). Initial parser,
controller and launch failures are retained in the evidence/recording guards;
they are not counted as successful checks.
