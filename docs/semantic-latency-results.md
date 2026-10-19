# Warm DB latency diagnostic, 2026-10-19

The original measured development candidate failed the [preregistered practical
gate](semantic-latency-protocol.md). All 48 hooks delivered original DB body,
with exact stdout/SHA-256/publication and accepted acknowledgement verified.
Only the 2- and 32-source cells completed semantic search. Each source has one
original window, fully warmed before measurement. This is not an LLM-token or
quality adoption comparison; no generation-model calls were made.

Three repetitions per cell, all retained. Times below are individual native
UserPromptSubmit latencies in milliseconds, rounded only for display.

| Sources | Source vectors | Question cache | Semantic complete | Body | Latencies, ms |
| --- | --- | --- | --- | --- | --- |
| 2 | DB | fresh | 3/3 | 3/3 | 1170, 1151, 1151 |
| 2 | DB | cached | 3/3 | 3/3 | 239, 235, 243 |
| 2 | private overlay | fresh | 3/3 | 3/3 | 1142, 1149, 1153 |
| 2 | private overlay | cached | 3/3 | 3/3 | 237, 239, 235 |
| 32 | DB | fresh | 3/3 | 3/3 | 1326, 1320, 1341 |
| 32 | DB | cached | 3/3 | 3/3 | 368, 370, 364 |
| 32 | private overlay | fresh | 3/3 | 3/3 | 1319, 1330, 1336 |
| 32 | private overlay | cached | 3/3 | 3/3 | 375, 379, 370 |
| 256 | DB | fresh | 0/3 | 3/3 | 3839, 3854, 3896 |
| 256 | DB | cached | 0/3 | 3/3 | 3831, 3846, 3855 |
| 256 | private overlay | fresh | 0/3 | 3/3 | 3980, 3990, 3958 |
| 256 | private overlay | cached | 0/3 | 3/3 | 3941, 4085, 3923 |
| 1024 | DB | fresh | 0/3 | 3/3 | 18179, 18277, 18448 |
| 1024 | DB | cached | 0/3 | 3/3 | 18322, 18074, 18098 |
| 1024 | private overlay | fresh | 0/3 | 3/3 | 18188, 18007, 18162 |
| 1024 | private overlay | cached | 0/3 | 3/3 | 17701, 17808, 17742 |

Both layouts use a read-only profile. The private-overlay layout additionally
protects the graph directory against writes. Graph-file hashes are checked
against the same saved seed before and after each pair. OS page caches were not
cleared. Counts out of three are observations, not population probabilities.

## Where the time goes

Representative DB-layout repetition 0 (the raw records contain every attempt):

| Sources / question | Full discovery numerical request | Import/constructor | Question embedding | NumPy scoring | Semantic search / lexical fallback |
| --- | --- | --- | --- | --- | --- |
| 2 / fresh | 498 ms, complete | 441.289 ms | 6.272 ms | 0.034 ms | 1090 / 0 ms |
| 2 / cached | 44 ms, complete | 0 ms, model unused | 0 ms | 0.029 ms | 168 / 0 ms |
| 32 / fresh | 514 ms, complete | 430.949 ms | 6.519 ms | 0.400 ms | 1249 / 0 ms |
| 32 / cached | 79 ms, complete | 0 ms, model unused | 0 ms | 0.359 ms | 294 / 0 ms |
| 256 / fresh | 773 ms, complete | 443.782 ms | 6.044 ms | 2.923 ms | 1506 timeout / 2255 ms |
| 256 / cached | 311 ms, complete | 0 ms, model unused | 0 ms | 2.816 ms | 1506 timeout / 2249 ms |
| 1024 / fresh | interrupted; last checkpoint at 3 ms | unobserved | unobserved | unobserved | 1511 timeout / 16585 ms |
| 1024 / cached | interrupted; 575/1024 scored at last checkpoint | 0 ms, model unused in observed prefix | 0 ms in observed prefix | 7.059 ms in observed prefix | 1508 timeout / 16728 ms |

These columns are nested measurements and must not be summed. Startup imports
are separately recorded (about 26–31 ms in these representatives), excluding
interpreter boot. Constructor time includes FastEmbed import and initialization;
lazy work inside embedding remains embedding time. Unobserved initialization in
an interrupted request is not a zero-cost initialization.

The 2-source fresh hook also starts a second encoder for derived source focus:
434.672 ms import/constructor and 11.898 ms source embedding. Its cached hook
reuses those derived windows and does not initialize that encoder. Thus the
fresh/cached contrast includes derived focus-cache reuse, not only query reuse.
Original persistent windows were warm in both conditions.

At 256 sources the entire numerical nomination finishes in 311 ms with a cached
question, yet semantic search still expires and lexical matching takes another
2249 ms. At 1024 sources numerical work is itself interrupted and lexical
matching takes over 16 seconds. Encoder residency or a larger semantic budget
alone cannot establish the required latency. Profile the matching/extraction
path before choosing an optimization, then repeat with these exact saved seeds.
The pilot remains pending.

## Evidence and execution boundary

Raw dataset:
`/Users/ovm/.codex/experiments/eggshell/semantic-latency-20261019-isolated/baseline-1/`
contains protocol and binary hashes, all seeds, graph-file hashes, exact native
inputs/outputs, per-stage receipts, results/summary and `publication-audit.json`.
The native executable remained unchanged across all 48 hooks.

The first setup attempt hit a 180-second fixture-preparation timeout after
850/1024 saved sources. The first 36 hook measurements were preserved. A helper
verified the exact existing source prefix and resumed the remaining 174 saves
on the same DB identity; the remaining 12 hooks were then measured. The initial
failure, source versions, preparation checkpoint and resume manifest are kept.
No measured hook was discarded or rerun. Peak descendant RSS was 1,180,288 KiB
in the initial run and 1,035,328 KiB in the resumed run, below the 3,500,000 KiB
guard. Preparation cost is separate from delivery latency.

The instrumented library, native executable, helper and test executable built.
Full regression passed in 85.23 seconds with peak descendant RSS 2,812,176 KiB.
Remaining regression index tickets were drained by a separate daemon without
changing graph heads. The two Python sources also passed syntax compilation.
Reusing the saved 2-source fixture through `--fixtures` passed a separate
four-hook smoke run in 3.71 seconds; it is outside the 48-hook dataset.

Run a revised candidate with `tools/semantic_latency.py --fixtures` pointing to
this dataset, a fresh output directory and the guarded runner. Do not regenerate
independent seeds and attribute their differences to the implementation.

## Follow-up on 2026-10-20

`allocation-1` repeats all 48 hooks against the original saved fixtures. The
semantic cap is 3,500 ms with half the remaining deadline reserved for lexical
delivery. It also uses pinned owner metadata and bounded generational page
lookup. All 48 published bodies and acknowledgements are retained; 36 searches
completed semantics. The practical gate still fails at 1,024 sources.

| Sources | Source vectors | Question cache | Semantic complete | Body | Latencies, ms |
| --- | --- | --- | --- | --- | --- |
| 2 | database | fresh | 3/3 | 3/3 | 1232, 1250, 1261 |
| 2 | database | cached | 3/3 | 3/3 | 264, 261, 249 |
| 2 | private-overlay | fresh | 3/3 | 3/3 | 1179, 1194, 1189 |
| 2 | private-overlay | cached | 3/3 | 3/3 | 247, 250, 253 |
| 32 | database | fresh | 3/3 | 3/3 | 1351, 1354, 1374 |
| 32 | database | cached | 3/3 | 3/3 | 366, 356, 365 |
| 32 | private-overlay | fresh | 3/3 | 3/3 | 1338, 1347, 1347 |
| 32 | private-overlay | cached | 3/3 | 3/3 | 362, 369, 363 |
| 256 | database | fresh | 3/3 | 3/3 | 2415, 2375, 2366 |
| 256 | database | cached | 3/3 | 3/3 | 1398, 1436, 1383 |
| 256 | private-overlay | fresh | 3/3 | 3/3 | 2368, 2369, 2505 |
| 256 | private-overlay | cached | 3/3 | 3/3 | 1401, 1430, 1444 |
| 1024 | database | fresh | 0/3 | 3/3 | 11985, 11938, 12018 |
| 1024 | database | cached | 0/3 | 3/3 | 11915, 11914, 11991 |
| 1024 | private-overlay | fresh | 0/3 | 3/3 | 11958, 12204, 11857 |
| 1024 | private-overlay | cached | 0/3 | 3/3 | 12012, 11751, 11862 |

Raw evidence is beside the original dataset at `allocation-1/`, including the
manifest, exact native output, receipts, frozen implementation/binaries, generated
C and full regression logs. Its size run took 199.07 seconds with observed peak
RSS 1,123,680 KiB. The same snapshot was copied, not regenerated.

An additional node-lookup shortcut did not establish a diagnostic benefit
and was removed. No empty-topology shortcut was taken: the 1,024-source fixture
actually contains 1,024 All relations and 8,195 nodes.

The first regression after changing the semantic cap failed an old requirement
that total delivery stay below 3,500 ms. Its real timeout delivery took 3,638 ms,
with DB body, explicit unfinished status and accepted acknowledgement. The
assertion now uses the suite's existing common 4,300 ms delivery bound. The
preregistered size gate remains five seconds. The corrected full regression
passed in 90.32 seconds, peak 2,816,400 KiB. The failed run and raw receipt remain
available; it is not counted as a success.

Inspection of generated C then showed that inserting before checking capacity
retained the old hash table across every update, forcing copy-on-write. The
update now checks room/membership first. Its generated C no longer adds that
extra reference on the insert path. Page-reference equality, original payload
checks, admission/ranking and the 4,096-page bound remain in place.

This ownership correction passed full regression in 87.07 seconds, observed
peak 2,796,480 KiB, and separate daemon draining preserved graph heads. A single
1,024-source native diagnostic took 6,964 ms and still timed out semantically.
That diagnostic is not a replacement for 48 measurements or evidence of a
general rate. A full repeat of this last correction has not started.

Next investigate repeated validation of one owner's Work postings across grams,
then fix and preregister the next candidate before repeating the same 48 cells.
No token/quality adoption, pilot or release is established by these diagnostics.
