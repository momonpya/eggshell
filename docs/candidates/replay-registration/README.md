# Keep shared replay progress when registering dependencies

Isolated continuation of the typed-provider candidate. Not adopted. The target
remains eighty people, growing project databases, actual98% necessary evidence
within30 seconds, and the matched total-token/quality/deadline adoption gate.

The previous mixed fixture had270 preparation retries and145.5-second readiness,
but its final journal-only retry did not identify the cause. Source inspection
found a separate reproducible error: registering still-valid historical inputs
rewound an existing shared source-feed cursor to their oldest captured head.
Completed replay continuations may retain those valid historical inputs. This
could make one turn repeat source work already consumed for every subscriber.

The model-free regression first reproduces this on the unchanged parent. An old
dependency still passes `Inputs.agree` after an unrelated publication. Registering
it again changes the settled cursor and the next sync repeats one feed block.
The old late-registration path also rewinds the cursor instead of immediately
rechecking only the newly registered job.

The candidate preserves an existing cursor exactly. New fields registered at a
different head or during a partial scan enqueue only their own task; initial
registration at the same settled head needs no extra queue entry. The existing
transaction, input-validation, source replacement, row/deadline bounds and task
ticket checks remain in place. No new lock/CAS, format number, queue capacity,
worker count, Python/Ruby or recommendation/authority rule is introduced.

The initial cursor-only implementation failed the ordinary prefix-append test:
historical read heads were still treated as validation heads, so newly added
fields unnecessarily invalidated their own current ticket. That rejected patch,
runtime identity and failure are retained. The final implementation makes input
validation return its checked source heads/feed positions as well as preserving
all dependency keys/values, original Pre roots and delivery references. The
journal registers those checked frontiers. It never relabels an unchecked input
or bypasses retention, bucket membership, producer or deadline validation.

The focused native regression passes: no cursor change or repeated feed block,
late dependency individually queued, and aborted flushed registration invisible
after reopen. Six Lean lemmas cover cursor preservation, dependency preservation
and recheck conditions;
their axioms are either none or standard `propext`. These are local properties,
not a proof of all IO concurrency, sustained capacity or delivery completeness.

The final full native replay check and prefix-continuation check both pass,
including the ordinary ContractAudit. The4096-subscriber test visits4097 rows
once in111 slices, with at most37 rows per slice, and matches the complete live
subscriber set after source replacement too. Three two-tool prefix appends
decode/execute only four new events each and reload zero historical Post
originals; all facts/status agree with independent full replay. Maximum observed
warm append is788 ms on this small fixture, not a production hook bound. Expired
validation, changed negative membership and source replacement are rejected.
This does not establish the cause of the whole mixed-load delay or pass the
80-person gate; repeat the complete workload after building the actual service.

Reproduction uses the existing bounded resource guard and
[setup.lean](setup.lean). Capture and run `baseline-build`/`observe` before applying
the candidate patch, then `candidate-build`/`verify`, `full-build`/`full`, `prefix`
and `audit`. The exact earlier baseline/initial-candidate harness bytes are saved
in evidence; the final validation/prefix cases live in ReplayWorkChecks.
Each action requires its own `replay-registration-` tag; existing receipts
are never overwritten. The complete check uses a fresh private root and the
ordinary4096-subscriber/replacement/foreign-input tests. Answering calls0; paid
matched comparisons0/18. No benchmark or product-adoption claim follows.

[Evidence](evidence.json) records all thirteen build/check guards, both rejected
and final native results, exact source/runtime identities and the applicable
four-file patch. Recording-controller failures are also retained separately.
Peak related RSS is2,780,224 KiB; no resource stop or owned survivors remain.
[Cleanup](cleanup.json) removes238,388,267 apparent bytes of ended fixture DBs,
private caches, the obsolete baseline-check executable and raw check logs.
No compressed archive is created. Active originals and native build dependencies
remain for the[next mixed-load measurement](next-mixed.md).
