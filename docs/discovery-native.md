# Isolated discovery data structures

This continues the [fixed scale diagnosis](semantic-scale-native.md). It does
not adopt a production change or report generation-model token savings.
The shared saved publication has 9,969 owners and 10,000 original windows.
The same first question, receipt, workspace and warm DB supply every standalone
inspection. Source/cache bytes remain unchanged. Each candidate must match
the entire reference Handoff, including text, packet, source records, delivery
keys, selection and completion metadata.

## Ordinal ownership

`discovery_owner_candidate.py` replaces the repeatedly sorted owner list with
one `Std.TreeMap Nat IndexedOwner`. The publication ordinal is its only key;
the row no longer duplicates that ordinal. Each value still carries the
original compiler certificate. Tree values supply the original order to the
graph and matcher, and tree membership handles repeated loads. Rejected Work
is checked again on later demands and quotient states.

`IndexedOwners.original_order` proves ordered publication keys for every
state. `DiscoveryOwnerTests.lean` checks all 720 insertion permutations of six
sparse ordinals, empty input, duplicate requests, exact body/graph/candidate
order, one hydration per retained ordinal, rejection followed by admission,
and rejection of a Work/owner disagreement. Its 722 ordering cases and four
admission cases pass in the native candidate.

## Work and child projections

`discovery_work_candidate.py` stops constructing all loaded Outcomes merely
to read `WorkGraph.subworks`, which depends on All children alone.
`sourceSubworks_exact` proves equality with the original graph projection for
arbitrary All and Outcome lists. Existing `HashDistinct.reference` preserves
the exact ordering of the Work-owner and child-demand lists. The saved and
staged membership-demand certificates remain mandatory. No source membership
check, Work comparison, candidate or evidence position is omitted.

## Retained diagnostic observations

| Standalone implementation | Full fallback | Complete reference Handoff |
| --- | ---: | --- |
| Original without instrumentation | 69,939 ms | reference |
| Original with instrumentation | 73,317 ms | equal |
| Exact depth relation set | 44,857 ms | equal |
| Depth set plus ordinal owner tree | 29,003 ms | equal |
| Depth, owner tree and Work projections | 26,274 ms | equal |

These are individual diagnostics, not balanced performance trials or a
passing hook gate. The instrumented original includes an additional native
stack observation. The candidate still exceeds the five-second goal, and a
semantic attempt consumes additional time before fallback. In the last
inspection, `loadWork` takes 5.586 seconds on the first discovery and 2.801
seconds on the second, versus 13.835/11.235 seconds in the instrumented
original. Child-membership work takes 1.527/2.043 seconds. Original loaded
owners and complete returned content are unchanged.

The owner build/inspection takes 68.486 seconds, sampled peak 2,882,176 KiB.
The combined Work inspection takes 60.151 seconds, peak 2,719,072 KiB. Neither
triggers the 3,500,000 KiB aggregate descendant guard.

A separate 24-second, 10-ms native stack observation covers the remaining
Work implementation. It retains complete reference Handoff equality. Its
recursive stack totals are not phase durations: recursive wire encoding and
grounding appear many times in one sampled stack. The exclusive sample table
and call ancestry instead identify further value comparisons, Match upsert
filtering, indexed reads and allocation work. Grouping each outermost Value
equality stack once finds 332 sampled branches under `Matcher.upsertMatch`,
versus one under the new depth membership count. These are sample counts,
not durations. `addMatches` currently filters all accumulated Matches for
each addition. Its replacement must retain the latest complete Match for
each exact `(demand, relation, currentFragment, pastFragment)` key, the same
final order and all untouched prior entries. Optimize only with that exact
sequence/authority preservation; keep the full scoring domain.

## Uninstrumented qualification

`prepare_discovery_candidate.py` reconstructs the exact candidate from the
qualified baseline and content-hashed component sources. It removes the
profiling wrappers, freezes every source file and builds the real executable,
the complete existing regression suite, owner checks and ContractAudit.
The failed first run is retained: the harness supplied an empty
`EGGSHELL_CONFIG`, which `Daemon.attachClientConfig` correctly attached over
the native fixture's own configuration. The first semantic hook therefore
returned `{}` without an offer. The unchanged ACK assertion rejected it.

The corrected harness unsets that variable for the regression subprocess so
each fixture supplies its own configuration. It reuses a completed build
only after comparing every source and still invokes Lake for all targets.
No body, ACK, timeout, ranking or ownership assertion is relaxed. The corrected
full qualification passes. All existing regression tests finish in 98.938
seconds, including native semantic-first/fallback/cold/corrupt delivery and
receipt checks. The 722 owner-order and four admission cases also pass in the
uninstrumented executable's build. ContractAudit builds successfully.

Three pending index tickets are recorded before independent recovery. The
candidate daemon drains all three; both pre-recorded graph heads remain
byte-identical, and the shutdown client and daemon both exit 0. Every frozen
candidate/baseline source and ordinary runtime hash remains unchanged. The
qualification takes 104.581 seconds with sampled aggregate peak 3,197,824 KiB;
the guard does not trigger. A verified existing build cache reduces the
unchanged build check to 0.869 seconds. This is regression evidence, not
large-DB latency or generation-model token evidence.

The fixed 60-hook failures remain authoritative. Further discovery/ranking
work and complete focus warm coverage are required before repeating that
gate. Latest-public-main matched task quality and inclusive token accounting
remain required for adoption.

## Complete focus warm closure

The actual LLVM failure has a separate cause: discovery uses original saved
windows, while focus removes the Work prefix from those same window slots.
An original-window-only warm therefore leaves some focus inputs cold. The
isolated `focus_warm_candidate.py` shares the exact suffix function between
warm and indexed focus. Warm plans the union of original and focus text keys,
deduplicates it, and encodes only the missing or invalid inputs in bounded
batches. It reads Work and only bounded original prefix windows to derive the
extra keys. Original source windows, ordinal positions, model contract and
valid vector bytes stay unchanged.

Doctor reports the unique union as its total, with separate discovery/focus
coverage denominators. Neither is a count of all original window references.
The warm scheduling checkpoint includes the actual suffix implementation's
content digest. Existing original vectors remain valid; an old scheduling
hint cannot certify the new input closure. Query vectors remain private.

Durable indexed focus no longer repairs numerical inputs in the foreground.
Staged sources retain their existing bounded repair allowance. Cold/corrupt
durable input must remain explicitly unfinished and fall back to lexical DB
body delivery. This change remains isolated pending the complete latency
gate and latest-public-main quality/inclusive-token adoption comparison.

The targeted native tests pass with synthetic vectors: original-only warm
is still cold for focus, only the difference is added, corrupt focus input
is diagnosed separately, repeated warm starts no unavailable provider, and
a durable provider pull cannot trigger foreground repair. The original
staged-repair test is unchanged. The complete existing regression suite
passes in 101.758 seconds and ContractAudit builds. Three pending index
tickets drain through a separate daemon with the pre-recorded graph heads
unchanged; the shutdown client and daemon both exit 0. Qualification takes
179.241 seconds, sampled peak 3,189,376 KiB, without triggering the guard.
The first three failed constructions are retained; their new test fixture
needed syntax/type fixes and explicit cache-directory preparation before
direct synthetic writes. Existing regression assertions were not relaxed.

The same frozen LLVM publication is copied to both cache layouts. Each
requires precisely 51 additional inputs in two batches (3,940/3,470 ms),
preserving every original vector's bytes. Repeated warm requests no work.
Original discovery has 2,081 unique inputs; focus has 2,080; their union has
2,132. All 2,081 original reference positions remain. Warm on the protected
shared DB writes only the private cache. The reference repair-enabled and
candidate cache-only focus return exactly the same complete 46-owner order
and original evidence positions in both layouts. Both perform the expected
52 bounded prefix reads and no subsequent repair reads.

All 12 fixed LLVM hooks complete discovery and focus scoring of every
original reference with zero source misses, invalid records or encoding.
This closes the missing-focus-input defect, but **the delivery gate is unmet
(0/12 pass)**: after scoring, the outer semantic attempt reaches its 4.5-second
deadline and falls back to lexical delivery. The unchanged required gold
body marker is absent in every response. Publication/stdout hashes and ACKs
agree in 12/12. The 4,831.253–4,922.529 ms response range is not successful
semantic/body delivery. Diagnose the remaining post-scoring matching and
extraction before claiming practical recovery or repeating the entire scale
gate. The old failed 60 samples remain unchanged. Native collection takes
160.706 seconds, sampled peak 1,626,368 KiB; the guard does not trigger.
Frozen DBs, source-vector bytes, model/runtime assets and ordinary sources
remain unchanged. No generation-model trial or adoption comparison ran.

## Reusable context preparation

The complete configured LLVM diagnostic, outside the hook deadline, returns
the required gold body in 19,142 ms. Existing trace points put source focus
at 1,412 ms and completed rendering at 18,238 ms: the rendering interval is
16,826 ms. A three-second native stack sample retains exact complete Handoff
equality. It locates repeated context preparation under budget alternatives.
Generated C confirms `prepareContextualOwnerPart` has seven runtime arguments,
including the budget: its source preparation is repeated on each application.

The isolated `context_plan_candidate.py` materializes `BudgetPlan`: either
a constant result or a prepared renderer for a variable allowance. The
budget-independent work runs before constructing the sized plan. Both actual
renderer call sites use those values. The original context functions remain
the specifications. Three universal Lean equalities preserve the complete
owner part, selected slice and supporting slice for every input and budget.
No budget level, nominated position, payload or completion field is removed.
The 72 native comparisons cover short/plain/canonical escaped Unicode bodies,
empty and multiple positions, and allowances from zero through 8,192.

A second native stack and generated C identify another repeated source scan:
the default-argument partial application in `coherentContextRanges` places
record/head scans inside each range's map iteration. Naming these two values
before the map preserves the original function definitionally; a `rfl`
compiler equality retains its kernel specification. Actual generated C has
one record scan and one head scan before the map, zero of either inside its
loop, and the optimized call in `ownerContextDemand`. Prepared owner/slice
factories now have six/three runtime arguments, excluding the budget.

The same frozen publication, question, workspace, receipt and model inputs
produce exactly the same complete Handoff in both candidate diagnostics.
The first reports 8,330 ms, the composed candidate 8,549 ms; their render
intervals are 3,990/2,878 ms. The second candidate's Handoff source, BudgetPlan
source and generated Handoff C are byte-identical to the qualified build.
These are individual diagnostics, with other time outside the existing trace
intervals; they are not balanced latency evidence, token savings or hook passes.

An attempted duplicate whole-renderer proof expansion hit the unchanged
3,500,000 KiB guard at 3,530,624 KiB. It is retained and removed from the final
candidate. The smaller candidate uses one renderer and the three exact
component contracts. Its first qualification correctly fails ContractAudit's
old direct-function reachability requirement. The updated isolated audit
requires the actual prepared producers/evaluator, retains every other source
boundary check, checks the three equalities against their exact original
function types, and restricts their axioms plus the compiler equality to the
existing allowed set. No `sorry` or new trusted/native-decide axiom is used.

Final qualification passes: all existing regression tests in 100.222 seconds,
the 72 native comparisons, ContractAudit, and separate recovery of three
recorded tickets with both recorded graph heads unchanged. Shutdown client
and daemon exit 0. The qualification takes 161.857 seconds, sampled peak
3,225,776 KiB; the guard does not trigger. Ordinary sources/runtime remain
unchanged. Latest-public-main adoption and the full scale gate remain open.

The new fixed LLVM collection reuses the exact complete discovery/focus
caches; both layouts repeat warm with zero requests or batches. Complete
focus owner/window rankings again equal the reference in both layouts, and
all source/vector bytes remain unchanged. All 12 hooks complete both numerical
passes without source misses or encoding, and publication/stdout hashes and
ACKs agree in 12/12. Nevertheless the semantic/gold-body gate remains **0/12**:
every configured attempt reaches the 4.5-second deadline. Total replies take
4,820.030–4,917.034 ms and carry lexical fallback without the required gold
marker. No failed sample is replaced. Collection takes 153.765 seconds,
sampled peak 1,602,304 KiB, without a guard trigger.

One additional actual cached hook observes trace appends from outside the
worker on a monotonic timeline, without changing the runtime. It retains
the same deadline/body classification and fails in 4,839.647 ms. Its
configured trace reaches source focus at 1,443 ms and never reaches completed
rendering. The observer sees about 2,381 ms between that focus event and the
start of fallback, and 3,827 ms from configured trace start to fallback,
versus 4,510 ms for the complete configured attempt. These are passive
observations with polling resolution/jitter, not exact phase subtraction.
They show the indexed-discovery trace omits earlier configured work and that
rendering still does not fit its remaining deadline. The fallback renders in
206 ms; its body is not the required gold observation. Keep improving the
actual deadline path and instrument its omitted preparation interval before
repeating a broad scale gate or starting the adoption pilot.

The qualified executable is also checked against the original complete
Handoff with a separately built helper: exact equality and the gold body
pass. Its internal complete-delivery interval is 5,414 ms, including a
3,052 ms render interval; actual helper-process wall time is 17,233 ms.
The earlier diagnostic times above are likewise internal intervals, distinct
from process wall time and actual native-hook latency. All observations are
retained. This check takes 36.508 seconds overall, sampled peak 1,555,104 KiB,
without a guard trigger; it does not change the 0/12 native gate result.

## Exact scalar-range reuse and indexed characters

The next native renderer sample still retains the complete reference Handoff.
It locates repeated scalar-range validation and character-prefix traversal in
`decodedEvidenceUsing?`. The isolated `context_memo_candidate.py` changes
evaluation while preserving the original decoder as its kernel specification.

`ExactMemo` uses a dependent hash table: a stored result carries equality to
the exact function at its actual key. Its universal `map`/`filterMap`
equalities retain order, duplicates and absent results, including hash
collisions. Context and cue factories reuse validation of duplicate ranges
within each preparation. The table is local to the exact source/function;
it is neither persistent nor a cross-source cache.

`IndexedCharacters` binds an immutable character array to the exact original
String. Its slice theorem preserves the existing character coordinates for
every string and bound, including Unicode, empty and out-of-bounds slices.
The decoder's bounded re-encoding decision uses those slices, with an exact
compiler equality to the original decoder. The full prefix certificate and
every bounds check remain. There is no hash-based substitute for validation.
The prepared owner also uses the same exact slices for original fragments.

Native checks pass 2,730 memo comparisons, including forced collisions,
315 range inputs and 162 character slices. Two retained development
diagnostics preserve the entire old Handoff, original positions, metadata
and required gold body. Their internal intervals are 7,152/6,986 ms, with
render intervals 2,653/2,433 ms. These single diagnostics are not balanced
performance comparisons, actual hook passes or token-saving evidence.

The final uninstrumented qualification passes ContractAudit and all existing
regressions in 106.044 seconds. Three remaining tickets are recovered by a
separate daemon with both recorded graph heads unchanged; shutdown client
and daemon exit 0. Qualification takes 180.119 seconds, sampled peak
3,073,968 KiB, without a guard trigger. Generated C confirms six actual calls
to the exact fast decoder, its indexed decision, and zero old bounded
`EvidenceRange.text` calls inside that decoder. Ordinary sources/runtime
remain unchanged. The candidate remains isolated and unadopted.

The fixed actual LLVM collection again uses the complete warmed inputs from
the previous collection, with no seed recreation. Both layouts repeat warm
with zero requests/batches. Complete focus orders and positions equal the
reference in both layouts, and all original source/vector bytes are unchanged.
All 12 hooks complete discovery and focus scoring without source misses,
invalid records or encoding. Publication/stdout hashes and ACKs agree in
12/12. The gate remains **0/12**: every semantic attempt times out at the
unchanged 4.5-second deadline, then returns lexical fallback without the
unchanged required gold marker. Replies take 4,825.375–4,913.502 ms. This is
not a notice-only failure or an absent publication; the required observation
is missing from the fallback. Collection takes 155.182 seconds, sampled
peak 1,650,576 KiB, without a guard trigger. All failed samples are retained.

The final qualified executable also reproduces the exact complete original
Handoff and gold body outside the hook deadline. Its internal interval is
4,732 ms, with 2,375 ms from source focus to completed rendering; the helper
process wall interval is 17,294 ms. Qualification and diagnostic inputs are
frozen and unchanged. This single diagnostic takes 28.714 seconds overall,
sampled peak 1,550,672 KiB, without a guard trigger. It does not supersede
the twelve actual hook failures or establish a balanced latency effect.

A further three-second native stack observation preserves exact complete
Handoff equality (internal interval 4,728 ms). It still shows decoded-width
scans, full prefix re-encoding and dynamic range validation inside rendering.
Those checks remain required; the next candidate must share or index their
work while preserving the same certificates. The observed process also has
sleeping provider-deadline tasks during task-manager finalization; their
presence is recorded separately from the internal delivery interval and
does not by itself explain the whole process wall time. Sampling takes
17.880 seconds, sampled peak 234,864 KiB, without a guard trigger.

## Prefix multiplicity and a disconnected lazy memo primitive

A diagnostic copy records every prefix decision after the bounded
re-encoding check. Its complete Handoff equals the original reference. It
records 7,423 decisions, grouped into 2,667 source-hash/character-length/start
tuples, with 4,756 repeated observations. These hashes are grouping hints,
not identity certificates or proposed runtime cache keys. Logging, hashing
and character counting add overhead: the internal 7,927 ms interval and
20,108 ms process wall interval are not latency comparison evidence. The
diagnostic takes 50.937 seconds, sampled peak 2,627,104 KiB, without a guard
trigger. The two earlier instrumentation proof failures are retained; the
successful trace has an exposed logical identity and preserves the decoder's
compiler equality. Neither instrumentation nor debug output enters a runtime.

`tools/ExactLazyMemo.lean` is a disconnected candidate for sharing decisions
across budget evaluations. It uses a finite binary address tree with lazy
branches and certified leaf results. Only requested paths are built; Lean's
standard cached Thunks share those computations. Its universal `read_exact`
theorem preserves the original function at every key. Outside the configured
domain, lookup evaluates the original function rather than aliasing a leaf.
The theorem uses only `propext` and `Quot.sound` in the printed axiom audit.

Native checks pass 91 comparisons, including absent results, domain
boundaries and repeated keys. Evaluation traces show each of six requested
in-domain keys computed once despite six reads per key. A second tree with
2^40 virtual addresses computes each of its three requested keys once, plus
one exact outside-domain evaluation. No whole-domain allocation occurs.
The primitive check takes 4.346 seconds including build, sampled peak
1,514,448 KiB; the guard does not trigger. Its first missing-library-root
build failure and earlier proof drafts remain in the local records.

This primitive has **not** been connected to prefix decisions, qualified
through the complete runtime or measured in a hook. The next candidate must
bind its entries to the exact source and prefix predicate, preserve every
old decoder decision, and pass complete qualification before repeating the
same fixed native gate. The existing 0/12 result remains unchanged.

## Local records

Under `/Users/ovm/.codex/experiments/eggshell/`:

- `discovery-owner-candidate-20261020/construction-1`: owner-tree proofs,
  native boundary checks and exact-Handoff timings.
- `discovery-work-candidate-20261020/construction-1`: composed projection
  proofs and exact-Handoff timings.
- `discovery-work-stack-20261020/observation-1`: whole-program native stack,
  exact target hash, raw stdout, guard and reference equality.
- `discovery-candidate-qualified-20261020/construction-1`: completed build,
  retained empty-config regression failure.
- `discovery-candidate-qualified-20261020/construction-2`: corrected harness,
  exact source/build-cache verification and uninstrumented qualification.
- `focus-warm-qualified-20261020/construction-4`: complete input closure,
  targeted tests, full regression, ContractAudit and independent recovery.
- `focus-warm-native-20261020/inspection-1`: fixed LLVM inputs, separate
  discovery/focus coverage, complete focus ranking and native delivery runs.
- `semantic-delivery-profile-20261020/inspection-1`: complete configured
  delivery, gold body and original phase trace outside the hook deadline.
- `semantic-delivery-stack-20261020/observation-1`: owned renderer sample
  and exact complete Handoff equality.
- `context-plan-inspection-20261020/inspection-1` and `inspection-2`:
  complete reference equality, native comparisons and phase traces.
- `context-plan-stack-20261020/observation-1`: remaining context preparation
  after materializing budget plans, with complete reference equality.
- `context-plan-qualified-20261020/construction-1`: retained old reachability
  audit rejection; `construction-2`: exact bridge audit, native C audit,
  complete regression and independent ticket recovery.
- `context-plan-native-20261020/inspection-1`: the new complete fixed LLVM
  12-hook collection; all failures and complete cache-only scoring retained.
- `context-plan-hook-trace-20261020/inspection-1`: one additional actual
  cached hook and passive absolute trace observations, separate from the gate.
- `context-plan-qualified-profile-20261020/inspection-1`: complete reference
  equality in the qualified executable, with internal/process timings retained.
- `context-memo-inspection-20261020/inspection-1` and `inspection-2`:
  exact complete-Handoff diagnostics for memoized decoding and indexed slices.
- `context-memo-qualified-20261020/construction-1`: exact compiler bridges,
  native checks, full regression, independent recovery and generated-C audit.
- `context-memo-native-20261020/inspection-1`: complete fixed LLVM 12-hook
  collection, full focus comparisons, cache invariance and failed delivery gate.
- `context-memo-qualified-profile-20261020/inspection-1`: qualified full
  Handoff equality, original gold observation and separate process timings.
- `context-memo-stack-20261020/observation-1`: remaining width/prefix work
  in the actual qualified renderer, with exact full Handoff equality.
- `context-prefix-profile-20261020/observation-1` and `observation-2`:
  retained instrumentation proof failures; `observation-3`: prefix counts,
  original full Handoff equality and unchanged frozen inputs.
- `exact-lazy-memo-20261020/construction-1`: retained build-root failure;
  `construction-2`: initial native checks; `construction-3`: the final 91
  comparisons, exact evaluation keys, axiom output and unchanged runtime.
