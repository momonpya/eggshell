# Immutable checks and selection-state ownership

Diagnostic and isolated Lean candidate; **unadopted**. Product ranking, source
scope, authority, model, budget and runtime are unchanged.

The preceding cue-sharing trial did not establish capacity improvement. Before
adding another cache or removing validation, a native component measured four
unchanged functions over the actual 40 original documents and their published
descriptors. Three trials each perform four complete-inventory passes. Approximate
time per pass:

| Operation | Time |
| --- | ---: |
| Hash original identities | 22.1 ms |
| Validate descriptor scope | 0.60–0.64 ms |
| Expand descriptor reads | 0.98–1.03 ms |
| Expand shell keys | 0.12 ms |

See `component.json`. All 40 documents are native, containing 722,548 source
bytes. The document file-provenance list is empty in this component because none
of the four measured functions consumes it. These are function costs, not full
hook times or allocations retained across requests. Heartbeats count small
allocations on the executing thread, not bytes or RSS. The installed Lean
`Init/System/IO.lean` documents that boundary. Scope validation was not weakened:
these costs do not justify identifying it as the seconds-long bottleneck.

An unchanged `c1de4407…` four-hook diagnostic then sampled the owned publisher
for three seconds at 5 ms intervals, after a measured-wave focus marker. The
sampler checked that the publisher belonged to its native controller. All four
semantic/synaptic bodies and ACKs passed and matched canonical bodies; three
primes were separate. Wave time was 5,412 ms and related RSS peaked at
2,863,776 KiB. Sampling can perturb timings; this is not a speed comparison,
p99 or an 80-client success.

The bounded `cpu-stack-excerpt.txt` shows selection updates, including
`Sparse.Values.advance`, `Evaluation.advance`, array copying and winner-tree
updates. It includes idle threads; stack counts must not become CPU percentages.
It does not prove the cause of the earlier 80-client RSS stop. The older
batch-winner trial already saved only about 50 ms without a measured RSS benefit;
that proposal is not retried here.

## New isolated ownership ordering

[OwnedCoverageAdvance.lean](../../../tools/research/OwnedCoverageAdvance.lean)
finishes reads of the previous evaluator and resolves affected postings before
constructing the next evaluator. Its winner-update helper consumes the already
computed change list and next values. The recursive selection path therefore
does not need to pass previous values into the winner update after advancing.
No cache, mutable array API, queue, lock, worker cap or allocator policy is added.
External aliases remain safe under Lean's normal copy-on-write behavior.

Five generic Lean theorems cover evaluator equality, all sparse values,
winner-cache equality, every recursive selection and the complete final selected
result. Warnings are errors; the checked axioms are only `propext`,
`Classical.choice` and `Quot.sound`. No `sorry`, `native_decide`, Z3 or new axiom
is used. `owned-order.c.txt` records generated code with trailing whitespace
removed for display; the full original digest is in `owned-proof.json`. Affected postings are
computed before advancing values, and the specialized winner helper has no old
stored-values parameter. This establishes compilation order, not a performance
improvement or global absence of aliases.

No compiler substitution or product call to this candidate is installed. Native
timing/ownership controls, full actual delivery and capacity evaluation of this
new selector are still required. The next measurement must distinguish consumed
inputs from deliberately retained snapshots; do not integrate or retry 80 on
proofs alone. Paid answering-model comparisons and adoption remain zero.

The first sampling setup rejected its own active resource guard before spawning
native hooks. The observer was corrected only in its guarded branch, preserving
the input/runtime/limits. The refusal is retained in
`cpu-preflight-refusal.json`; it is not a hook failure or successful hook count.

Ended native component source/build, raw samples, trial outputs, private receipts
and logs were deleted without archives: 3,241 files / 434,523,651 logical bytes.
Original DB hashes and retained native inputs were checked before and after
deletion (`cleanup.json`). The Lean candidate and reduced evidence remain.
