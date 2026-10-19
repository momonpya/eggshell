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

## Complete-window batching and reader isolation

`bounded-scoring-1` kept the 3,500 ms allocation and repeated all 48 hooks
against the original snapshots. It validates a repeated Work-posting owner
once per pinned nomination (and rejects conflicting bindings), and batches
up to 32 numerical windows across document boundaries. Every original source
and position remains in scoring. All 48 stdout bodies and accepted
acknowledgements were independently rechecked against their published SHA-256.
Semantic completion remained 36/48; every 1,024-source cell still failed.

| Sources | Source vectors | Question cache | Semantic complete | Body | Latencies, ms |
| --- | --- | --- | --- | --- | --- |
| 2 | database | fresh | 3/3 | 3/3 | 1150, 1150, 1147 |
| 2 | database | cached | 3/3 | 3/3 | 242, 242, 240 |
| 2 | private-overlay | fresh | 3/3 | 3/3 | 1157, 1165, 1149 |
| 2 | private-overlay | cached | 3/3 | 3/3 | 243, 248, 247 |
| 32 | database | fresh | 3/3 | 3/3 | 1276, 1271, 1272 |
| 32 | database | cached | 3/3 | 3/3 | 312, 303, 302 |
| 32 | private-overlay | fresh | 3/3 | 3/3 | 1261, 1279, 1277 |
| 32 | private-overlay | cached | 3/3 | 3/3 | 304, 306, 310 |
| 256 | database | fresh | 3/3 | 3/3 | 1987, 1986, 1989 |
| 256 | database | cached | 3/3 | 3/3 | 1005, 998, 999 |
| 256 | private-overlay | fresh | 3/3 | 3/3 | 1962, 1958, 2053 |
| 256 | private-overlay | cached | 3/3 | 3/3 | 1011, 1030, 1020 |
| 1024 | database | fresh | 0/3 | 3/3 | 6076, 6072, 6067 |
| 1024 | database | cached | 0/3 | 3/3 | 6084, 6092, 6053 |
| 1024 | private-overlay | fresh | 0/3 | 3/3 | 6081, 6189, 6178 |
| 1024 | private-overlay | cached | 0/3 | 3/3 | 6274, 6179, 6136 |

The size run took 123.20 seconds with peak descendant RSS 1,119,744 KiB.
Full regression before it passed in 88.40 seconds, peak 2,973,760 KiB;
a separate daemon drained remaining tickets without changing graph heads.
Its synthetic numerical comparison covers more than 32 owners, more than
32 windows within one owner, exact original tied positions and a late cache
miss after previous batches scored. Complete Work-surface comparisons also
reject conflicting gram/ordinal bindings in either order.

A standalone cached-question inspection then completed the full numerical
request in 1,005 ms, yet spent 4,627 ms in kernel discovery. A CPU sample
found persistent table copying and multi-thread marking during checked
Work reads. The provider response task captured a source reader even when
durable foreground repair was forbidden. Dropping that unused capability
before task creation avoids sharing the controller's page cache. Permitted
source pulls instead get an empty private page cache on the same pinned
image; read accounting/observations remain shared. This also covers staged
and federated readers. Original body checks and selection rules remain.

After that correction, separate unbounded configured diagnostics took
4,049 ms with fresh query/focus vectors and 3,378 ms with reused query/focus
vectors. Kernel discovery was 1,449 and 1,476 ms, respectively. These are
phase inspections, not native delivery samples; sampling overhead and source
focus cache state are retained in their records. A native diagnostic with
the old 3,500 ms cap still timed out and delivered lexical body in about
6 seconds. The next fixed 48-hook run therefore uses the preregistered
4,500 ms cap and the original half-remaining-deadline reservation. The
five-second practical gate is unchanged. Failure-injection regression keeps
its prior 800 ms allowance above the semantic cap (now 5,300 ms); that test
allowance is separate from the practical gate.

Raw records and frozen implementations are in `bounded-scoring-1/`,
`scoring-standalone-1/`, `scoring-profile-1/`,
`reader-ownership-profile-1/`, `reader-ownership-fresh-1/` and
`profile-native-9/`/`profile-native-10/` beside the original dataset.
No LLM-token saving or quality adoption is established by this diagnostic.

## Reader-isolation fixed repeat

`reader-isolation-1` repeated the same 48 conditions with the frozen reader
isolation candidate and 4,500 ms semantic cap. Semantic completion was 47/48,
body publication and accepted acknowledgement 48/48. The strict practical
gate **still fails**: fresh private-overlay repetition 1 at 1,024 sources
timed out and needed 7,373.50 ms including lexical body delivery. That attempt
is retained and has not been replaced by a rerun.

| Sources | Source vectors | Question cache | Semantic complete | Body | Latencies, ms |
| --- | --- | --- | --- | --- | --- |
| 2 | database | fresh | 3/3 | 3/3 | 2003, 2051, 1523 |
| 2 | database | cached | 3/3 | 3/3 | 423, 346, 263 |
| 2 | private-overlay | fresh | 3/3 | 3/3 | 1296, 1308, 1331 |
| 2 | private-overlay | cached | 3/3 | 3/3 | 275, 260, 280 |
| 32 | database | fresh | 3/3 | 3/3 | 1419, 1428, 1417 |
| 32 | database | cached | 3/3 | 3/3 | 339, 341, 407 |
| 32 | private-overlay | fresh | 3/3 | 3/3 | 1636, 1622, 1466 |
| 32 | private-overlay | cached | 3/3 | 3/3 | 362, 339, 354 |
| 256 | database | fresh | 3/3 | 3/3 | 2020, 1897, 1897 |
| 256 | database | cached | 3/3 | 3/3 | 905, 872, 856 |
| 256 | private-overlay | fresh | 3/3 | 3/3 | 1873, 1867, 1884 |
| 256 | private-overlay | cached | 3/3 | 3/3 | 879, 880, 876 |
| 1024 | database | fresh | 3/3 | 3/3 | 4167, 4164, 4170 |
| 1024 | database | cached | 3/3 | 3/3 | 3136, 3121, 3126 |
| 1024 | private-overlay | fresh | 2/3 | 3/3 | 4339, 7374, 4550 |
| 1024 | private-overlay | cached | 3/3 | 3/3 | 3972, 4012, 3773 |

The failed attempt completed numerical discovery for all 1,024 original
windows in 2,511 ms: 1,119 ms cache processing, 825 ms query work and 358 ms
scoring/IPC (nested measurements). Encoder import/constructor was 757.589 ms,
query embedding 18.384 ms and NumPy scoring 11.975 ms. No focus receipt was
observed before cancellation; its cost is unknown. Semantic timeout was
4,508 ms, then lexical delivery took 2,766 ms. All source vectors hit; this
was not a cold-source repair. Larger allocation alone has insufficient
headroom in this observed cell. Do not widen it again without removing cost.

The full repeat took 104.08 seconds, peak descendant RSS 1,138,496 KiB.
Full regression passed in 92.11 seconds, peak 2,848,400 KiB, including isolated
async pull cache/accounting and old-publication checks. A separate daemon
drained 3 remaining tickets to 0 with all graph heads unchanged. The core,
native executable, helper, tests and ContractAudit built. The frozen sources,
binaries and generated C are at `reader-isolation-implementation-1/`; the
48 outputs/receipts, immutable fixture hashes and independent
`publication-audit.json` are at `reader-isolation-1/`.

The development branch remains an unadopted candidate. No token/quality
adoption, pilot, main merge or release is established. Continue with the
remaining checked topology/cache costs before another fixed full repeat.

A subsequent Atom-byte reuse prototype kept the canonical structural traversal
and passed focused collision, authority/position and noncanonical-child alias
checks. Its single fresh private-overlay diagnostic took 4,457.18 ms, with
1,422 ms in kernel discovery. This did not establish sufficient extra deadline
headroom. The prototype was removed; source and executables were restored to
the pushed candidate. Its source/diff, executable, failed initial builds,
corrected build, focused tests and native output remain at
`atom-reuse-prototype-1/` and `atom-reuse-native-1/`. It is not a replacement
for the failed fixed-run cell or a completed 48-hook comparison.

Next decompose the failed hook's 1,119 ms cache observation into secure file
reads, JSON parsing and finite-vector validation before choosing another
candidate. All 1,024 original windows were hits. The practical gate remains
unmet; the prototype's removal does not change the 47/48 result.

## Packed numerical cache: fixed gate passed

`packed-vector-1` completed all 48 semantic searches and delivered original
DB body within five seconds in every preregistered cell. Independent inspection
matched all 48 literal stdout bodies, SHA-256 values and accepted acknowledgements.
Every discovery receipt completed scoring every original window with a source
cache hit. The allocation remains 4,500 ms, limited to half the remaining hook
deadline. The candidate was frozen throughout the run.

| Sources | Source vectors | Question cache | Semantic complete | Body | Latencies, ms |
| --- | --- | --- | --- | --- | --- |
| 2 | database | fresh | 3/3 | 3/3 | 1133, 1100, 1107 |
| 2 | database | cached | 3/3 | 3/3 | 246, 243, 234 |
| 2 | private-overlay | fresh | 3/3 | 3/3 | 1114, 1103, 1114 |
| 2 | private-overlay | cached | 3/3 | 3/3 | 235, 239, 237 |
| 32 | database | fresh | 3/3 | 3/3 | 1220, 1218, 1231 |
| 32 | database | cached | 3/3 | 3/3 | 297, 298, 312 |
| 32 | private-overlay | fresh | 3/3 | 3/3 | 1223, 1229, 1226 |
| 32 | private-overlay | cached | 3/3 | 3/3 | 300, 293, 298 |
| 256 | database | fresh | 3/3 | 3/3 | 1637, 1642, 1635 |
| 256 | database | cached | 3/3 | 3/3 | 682, 683, 688 |
| 256 | private-overlay | fresh | 3/3 | 3/3 | 1638, 1629, 1624 |
| 256 | private-overlay | cached | 3/3 | 3/3 | 700, 705, 695 |
| 1024 | database | fresh | 3/3 | 3/3 | 3529, 3494, 3526 |
| 1024 | database | cached | 3/3 | 3/3 | 2392, 2384, 2397 |
| 1024 | private-overlay | fresh | 3/3 | 3/3 | 3431, 3421, 3478 |
| 1024 | private-overlay | cached | 3/3 | 3/3 | 2458, 2447, 2476 |

These are observations over the four fixed sizes and saved synthetic sources,
not a guarantee for arbitrary databases or a population completion rate.
The 47/48 predecessor and its 7,373.50 ms failed cell remain unchanged above.

Cache-only diagnostics split secure open, bounded read, JSON decoding and
finite-vector validation. Each row below preserves all three repetitions, in
milliseconds; cold OS reads were not excluded. These phases are sequential
within this helper and separate from native hook delivery.

| Layout / representation | Open | Read | JSON decode | Finite check | Original window hits |
| --- | --- | --- | --- | --- | --- |
| DB / decimal arrays | 95.5, 96.5, 95.8 | 43.3, 4.1, 4.1 | 223.6, 222.5, 220.9 | 272.2, 276.7, 273.4 | 1024/1024 each |
| private overlay / decimal arrays | 149.6, 148.7, 148.6 | 113.6, 3.9, 4.1 | 219.6, 221.6, 221.8 | 266.9, 277.8, 275.9 | 1024/1024 each |
| DB / packed words | 98.1, 93.2, 92.7 | 94.1, 3.1, 3.2 | 30.1, 29.3, 29.4 | 8.8, 8.0, 8.3 | 1024/1024 each |
| private overlay / packed words | 148.8, 144.4, 145.0 | 3.4, 3.2, 3.3 | 29.0, 29.1, 30.0 | 8.3, 7.9, 8.3 | 1024/1024 each |

The model/window JSON envelope is retained. Its vector is a lowercase hexadecimal
string of little-endian IEEE binary64 words. Finiteness is checked directly from
the exponent bits, with the same 1..4096 dimension and bounded-read constraints.
NumPy decodes those words into the original binary32 dot-product inputs. Source
selection, complete scoring, original window coordinates and the MiniLM
model are unchanged. This is not a character/transport saving claim about LLM
tokens. Old decimal-array records are invalid hints and explicit warm rebuilds
them; no compatibility reader or cache version branch was added to runtime.

The four original saved graphs were copied, then only their cache representation
was prepared by `tools/pack_latency_fixtures.py` using the native packer. All
1,314 windows (504,576 values) preserved binary32 bits; a separate audit also
confirmed every binary64 value matched the original decimal transport. The
50 decimal rounding/subnormal/sign edge cases preserved binary32 bits. An
exhaustive upper-16-bit check covered every sign/exponent/high-mantissa pattern
against Float.ofBits.isFinite, with malformed encodings and low NaN payloads
also rejected. These tests do not add a native_decide theorem.

Full regression passed in 89.06 seconds, observed peak descendant RSS 2,772,784
KiB. Remaining 3 tickets were drained to 0 by another daemon with graph heads
unchanged. The 48-hook run took 80.02 seconds, peak 1,111,696 KiB, under the
3,500,000 KiB guard. Reproducible fixture preparation took 2.62 seconds, peak
79,488 KiB; all four actual directories passed the candidate cache reader
before measurement. No generation-model call was made in these diagnostics.

Raw evidence is at `cache-cost-1/`, `cache-cost-packed-1/`, `packed-fixtures-2/`
and `packed-vector-1/` beside the original dataset. The last contains
`publication-audit.json` and `result-audit.json`; its implementation manifest
points to frozen sources, executables, generated C and all check logs at
`packed-vector-implementation-1/`. Initial failed build attempts are retained.
The helper and harness source hashes were checked unchanged after all 48 hooks.

The latency gate is now satisfied for the fixed protocol. Inclusive-token and
quality adoption against latest public main, the pilot, complete equality
ancestry, private-overlay orphan reclamation and the full paper remain unfinished.
