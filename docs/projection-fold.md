# Stable graph projection without repeated list scans

This isolated Lean change removes the repeated membership scans and list copies
identified in `projectMatches`. It preserves the complete graph result; it does
not change recommendation, Match admission, Unions, freshness or source scope.
Source/link hashes and raw evidence are in [the review](candidates/projection-fold-review.json).

The generic `AppendUnique.merge` builds an exact membership set from the existing
keys, accumulates new original payloads in reverse, and appends once. Existing
duplicates remain. New duplicate keys keep their first payload and insertion
order. Hashes nominate buckets; full key equality decides membership. The result
is not reconstructed from keys. Hash work depends on key size and collisions;
no worst-case constant-time lookup guarantee is claimed.

Ordinary Lean proves equality with the complete original append/check fold for
all lists and lawful key instances. `Matcher.projectMatchesFast_exact` then
proves graph equality for every base graph and Match list, including nonautomatic
Matches. A `csimp` equality preserves the original logical specification and
all existing authority witnesses. ContractAudit checks the four refinements.
The actual Handoff caller was rebuilt; generated C calls the fast projection
and has no call to the original quadratic projector. Its tested linked object
also retains the preceding exact admission-policy index.

## Fixed-input results

All 32 small cases and four 10k cases agree in every Handoff field and body byte.
Small cases include seven completed results, five blocking results and a positive
local Union. The reference is the retained admission-policy candidate, not public
main. Controlled nomination/focus callbacks are fixed; these are not model trials.

| Controlled 10k discovery | Reference ms | Candidate ms |
| --- | ---: | ---: |
| Local Union, first | 9,271 | 9,210 |
| Local Union, acknowledged history | 9,211 | 9,314 |
| Local Union disabled, first | 28,330 | 23,039 |
| Local Union disabled, acknowledged history | 28,460 | 22,953 |

Both arms use the same source publication and question. The disabled mode keeps
the same nominations; it is not lexical-only search. The repeated projection
cost falls in this single comparison. Normal-path improvement and p99 are not
established. Do not combine these times with older cohorts as a causal estimate.

## Actual UserPromptSubmit

Both native arms use the same original 10k DB, MiniLM contract, configuration and
question, with separate fresh private query/session state. Source caches are warm;
the first query is a recorded cache miss and the continuation a hit in both arms.
No source windows are re-encoded. Warm's child exits before foreground measurement.

| Native hook | Reference ms | Candidate ms | Output |
| --- | ---: | ---: | --- |
| First, including manager startup | 19,332 | 17,849 | Identical stdout and 17,803-byte original evidence body |
| Same query after confirmed ACK | 17,115 | 16,463 | Identical empty reply suppressing acknowledged evidence |

Both semantic searches complete in the correct first/continued stratum and
retain identical ACK history. Neither reply is an incomplete notice. One pair
per arm does not establish a normal-hook latency improvement or 50k qualification.
The maximum aggregate RSS is 2,776,272 KiB; native arms peak at
1,603,536/1,936,416 KiB. All owned managers/processes finish. Original source
head/pages remain unchanged.

## Remaining architecture work

A separate seven-second processing-thread sample, starting about one second
after helper launch, covers context preparation and part of the first normal
discovery. It includes original Work/payload reads, frequency work and geometric
matching. Profiled results equal the unprofiled results; profiled timings are
excluded. Its mode/window differ from the earlier 74% projection sample, so
those fractions cannot be compared or extrapolated to complete native latency.

Whole-source Work restoration and per-window numerical acquisition remain.
The next priority is the complete Work/canonical/affected-parent access path,
independent of recommendation routing, rather than more local list tuning.
Publication preparation must support that path without moving complete scans
back into each hook. The snapshot, Exact and original-source witnesses must
survive the replacement; recommendation top-K cannot bound recognition.

This pure projector equality does not close the parent deferred scheduler's
full-fixpoint proof. Cross-DB/shared lifecycle, capture privacy, routed additions,
50k/p99, all-topic/both-lap token/quality qualification and Phases 0–6 remain
unfinished. No answering-model calls or new seeds were made. The candidate is
unadopted under AGENTS.md; product source, README results and releases are unchanged.
