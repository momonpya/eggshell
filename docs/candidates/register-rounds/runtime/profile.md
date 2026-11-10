# Execution after fixed-lane hashing

One new diagnostic, not a speed comparison. The preceding goal turn made
verified progress: the fixed ABBA sixteen-client comparison shortened mean
wall time by 11.190%, while retaining all canonical bodies. The remaining
few-second target was not met.

The product stays at `1153215e…`. The [two-object observer audit](profile-observer-native.json)
checks the minimal native observer and entry; it does not replace the separate
full product audit. The observer source is byte-identical to the already
tested success/failure/cancellation lifecycle implementation. It samples only
the directly owned publisher, three seconds at 5 ms intervals, starting two
seconds after the four-client phase is observed. Small query-stage timestamps
are enabled; heap/selection-input capture remains disabled.

[Actual records](profile-result.json): three primes and all four measured
initial hooks match the canonical bodies and ACK. Semantic search and synapses
complete in all four measured hooks. The wave takes 5.695 s with observation
interference possible, so it is not included in the ABBA comparison. The guard
exits zero, has no owned processes, and peaks at 2,685,392 KiB; original DB
files remain unchanged.

| Topic | Operation work | Ready marker | Operation after ready | After execute to operation reply value |
| --- | ---: | ---: | ---: | ---: |
| 1 | 5,106 ms | 352 ms | 4,754 ms | 40 ms |
| 2 | 4,989 ms | 335 ms | 4,654 ms | 46 ms |
| 3 | 5,102 ms | 318 ms | 4,784 ms | 38 ms |
| 1 | 5,195 ms | 358 ms | 4,837 ms | 38 ms |

Reader borrowing is 3 ms for every actor; synaptic acquisition is 22–23 ms,
and admission queues are 1–2 ms. These boundaries do not establish that every
wait is gone. The last column is inside the operation service, not the whole
client transport/stdout/ACK delay. Work after the ready marker includes multiple
steps and must not all be assigned to the selector.

The [checked CPU stack](profile-stack.json) contains 12,081 frames, with zero
inconsistent parent totals. All 77 published native exclusive entries match.
Waiting threads are included; weights are not CPU percentages or durations.
Among active functions, `lean_copy_expand_array` has weight 124 and the
`basePieceAccept` specialization 100. `selectSourcePlan` and `selectView` occur
on the relevant execution paths. Previous cue-range work already reduced its
roughly 100 ms component, so it is not repeated as a seconds-long repair.

The first parser [rejected](profile-stack-rejection.json) a name-only match:
`<deduplicated_symbol>` occurs in two different libraries. Symbol identity now
includes its image, matching the OS summary. Checks are not skipped. The same
parser also matches all 76 and 80 entries in the two old samples; no product
replay was used to repair the parser.

Source inspection confirms that `SharedReadViews.withView` releases its state
mutex before executing the supplied function. A whole-selector mutex is not
introduced as the explanation. Instead, `ownerReach` repeatedly inserts
`rows[owner]?.getD #[] |>.push entry` into the same persistent map. A retained
old bucket can force each push to copy its array. The next isolated
[component study](../../owned-buckets/README.md) tests this ownership pattern
and proves complete ordered optional-bucket equality. It does not yet prove
that this operation accounts for the whole remaining delay.

After collecting the records, [cleanup](retired-observed-components.json)
removes the ended observer/component builds and duplicate native outputs:
3,865 entries, 224,510,625 logical bytes. Five targets receive 15,600 resolved
input checks, not 15,600 distinct native inputs. The seven acknowledged
session/ledger/receipt states separately account for 534 entries and
17,016,801 bytes. No archive is made. Protected product/controller/head hashes
remain unchanged. The current raw CPU sample is kept for the ongoing execution
investigation; scalar cache/shutdown/input metadata and proof sources are kept.
The retired executables require regeneration and are not available for replay.
