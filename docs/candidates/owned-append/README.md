# Proven hash refinement in the multi-owner service

Isolated composition on [project-access](../project-access/README.md), not adopted.
The source append profile found the old array-update BLAKE3 mix in the current
multi-owner candidate. The existing [register refinement](../../register-hash.md)
had already proved a total function equality and measured a roughly twofold
hash-only speedup. It was a separate candidate, not part of this source service.
This continuation reuses that proof and implementation rather than repeating the
research. No retrieval weights, source graph, recommendation/certification rule,
publication deadline or delivery budget changes.

The [patch](candidate.patch) applies to `owned-project-access-core` and imports
the existing tracked `RegisterMix.lean`. Its `csimp` theorem connects the old mix
to the proven implementation. The [axiom audit](proof-audit.txt) depends only on
`propext` and `Quot.sound`. Both native builds include ordinary `ContractAudit`.

## Diagnostic profile

The [Lean controller](/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/tools/research/OwnedAppendProfile.lean)
verified the actual service child's parent PID before five seconds of macOS
stack sampling at a 5 ms interval. The existing 50 KB native broker audit finished
all original/graph/reopen checks. Sampling perturbs latency; its duration is not
used as a baseline performance result. The [profile](profile.json) and
[guard](profile.guard.json) retain that distinction.

The [stack reduction](stacks.json) attributes exclusive sample weight to unique
ancestor symbols, counting recursive frames once per stack. Known waiting kernel
frames are separated. BLAKE3 appears in 2,629 of 8,464 awake-stack weights;
`Intern.root` in 3,219 and writer flush in 3,013. These overlap and are neither
wall-clock durations nor CPU-time measurements. In particular, the raw sampler's
14,899 recursively counted `encodeList` frames do not prove encoding dominates.
The raw sample is hashed then deleted after reduction, not archived.

## Fixed comparison

The [predeclared plan](plan.json) uses one immutable boot and the same logical
absolute path per size, 80 real loopback sessions across 16 source owners, four
waves, fixed 16 background pins per arm and three alternating-order repetitions
at each size. Parent and candidate receive the same controlled native output,
clock intervals and original Work inputs. Complete originals, occurrence
provenance, the independent 1,280-root graph and fresh-process recovery must match.
The existing comparison controller was not changed.

| Output bytes each | Repetition | Parent write waves, ms | Candidate write waves, ms | Parent max submit, ms | Candidate max submit, ms |
| --- | --- | ---: | ---: | ---: | ---: |
| 5,000 | 0 | 3,865 | 3,281 | 1,345 | 1,017 |
| 5,000 | 1 | 3,703 | 2,955 | 1,212 | 941 |
| 5,000 | 2 | 3,940 | 3,253 | 1,427 | 1,144 |
| 50,000 | 0 | 21,734 | 14,896 | 7,594 | 5,098 |
| 50,000 | 1 | 18,639 | 15,171 | 6,239 | 5,090 |
| 50,000 | 2 | 19,505 | 14,842 | 6,929 | 4,731 |

All 12 cells passed the same original/provenance/graph and recovery checks.
The [complete results](comparison.json) and [per-pair summary](summary.json) also
retain query offsets, actual starts, complete load windows and all submit samples.
For 5 KB, candidate full load windows were 3,400–3,582 ms, exceeding the displayed
write-wave sums because the final scheduled background pin also has to finish.
For 50 KB they equaled the displayed write-wave sums.

The whole comparison took 321,572 ms. The [guard](comparison.guard.json) sampled
aggregate owned RSS at most 1,871,824 KiB, fired no limit and found no surviving
owned process. Builds peaked at 2,808,448 KiB. An initial launcher failed its
128 MiB Lean elaboration limit before running a build; it was replaced with a
small native Lean launcher without raising the aggregate memory ceiling.

Parent helper: `831c019b72b6ef0602dca496cd4dda5183c16c4c7b3999bdc80a43c155863af2`.
Candidate helper: `901b595ffb976c55f2de1b98eaed12092c0fc56aee9ca87d158f194067182839`.
[Inputs](comparison-inputs.sha256) were checked unchanged after all cells.

## Limits and next action

The 50 KB candidate reaches only about **21.1–21.6 observations/s**, below the
maximum assumed 22.2/s before derived preparation. These are source-publication
RPC measurements, not hook latency, p99 or eight-hour capacity. There is no
evidence here about delivery recall or total-token savings. Ordinary project
Pre/Post/Stop, project-owned canonical preparation and cross-project read
dependencies remain unconnected. Answering-model calls and paid comparisons
remain zero / 0 of 18; this optimization is not adopted into the product, README
results or a release.

The remaining synchronous source path still builds root and search indexes.
Before removing or deferring any, trace each consumer and preserve complete
WorkGraph certification plus a checked source/prepared frontier. Merely skipping
these records would turn unprepared data into false absence. The next work is
to separate durable source publication from derived preparation and connect their
shared project ownership, rather than tune recommendation weights.

Ended profile/comparison DBs, caches, unused helpers, generated C and raw logs
are deleted after sealing compact records. No archive is made. Current sources,
necessary native objects/interfaces/link inputs and the candidate helper remain;
protected originals and controls are checked before and after cleanup.
