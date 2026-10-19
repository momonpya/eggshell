# Complete-context native candidate, 2026-10-20

The complete-token experiment now connects to the actual native provider,
DB-owned cache, warm checkpoint, doctor and receipts in an isolated checkout.
Production sources/executable remain unchanged. This is not public-main
token/quality adoption or a completion claim for the paper goal.

## Representation

One original DB window still owns one bounded record. Its vector field is a
typed array of packed vectors, with mandatory coverage and encoder-contract
fields. The decoder rejects the old single-string form. The checked record
requires finite encodings, matching group count, complete model-token offsets,
character-count bounds and the current contract. Secure bounded reads, original
window/model identity, ownership and atomic publication remain required.
Numerical records never establish equality or completion authority.

Source and question windows use the same complete splitter. Query groups are
flattened once; every original source window retains its group. Scoring compares
all query/source segments and takes the maximum per original window. Original
window positions, 32-window transport batches and the candidate domain remain.
Subsegments do not add files.

The contract hashes numerical code and a compiled manifest of six model assets
and 72 listed runtime files, including tokenizer, pooling code and numerical
native libraries. Paths are relative to installation roots. Those listed files
are verified before inference. The warm checkpoint binds the same contract,
so old single-vector files and scheduling hints cannot falsely suppress warm.
This experiment pins one installed model/runtime; production installer support
for refreshing this contract is pending. No manual format version is added.

Doctor separates unique live window inputs from vectors, model tokens,
non-whitespace characters, tokenizer-mapped characters and attended token
offset characters. Receipts count actual source/question window references.
Overlapping windows count their input positions separately; these are not unique
whole-document character counts. Token coverage is not model comprehension.

## Native evidence

[`prepare_context_candidate.py`](../tools/prepare_context_candidate.py) clones
sources/build outputs and applies [`context_candidate.py`](../tools/context_candidate.py)
only in the copy. The executable and `ContractAudit` build. Native controls in
[`ContextWindowTests.lean`](../tools/ContextWindowTests.lean) cover grouped IO,
source/query flattening, changed contract, seven invalid records, rejection of
the old JSON shape, source binding, receipt counts and warm-hint invalidation.

[`context_native_probe.py`](../tools/context_native_probe.py) saves one Japanese
observation, warms it with the ordinary provider and copies that exact snapshot
into two layouts. Candidate doctor sees its three old windows as cold. Warm
rebuilds three windows into six vectors; repeated warm requests zero windows
and batches. Doctor counts 904 input characters, 896 visible/mapped/embedded
characters and 552 model tokens, summed over the three unique windows.

The long question has two original windows and five vectors. Receipts count
834 input characters, 833 visible/mapped/embedded characters and 528 model
tokens. Discovery hits every source window and does no source embedding.

| Layout | Fresh question / new chat | Cached question / another new chat |
| --- | --- | --- |
| DB cache, read-only delivery | 1,855.753 ms | 275.900 ms |
| OS-protected DB, private cache | 1,853.545 ms | 271.000 ms |

All four hooks complete semantics and deliver original DB body, with exact
stdout/publication/bytes/SHA/accepted ACK. Both cached chats use all five query
vectors with zero initialization/inference. Shared DB bytes remain unchanged
by read-only delivery and private warming. Private query records contain only
model/window/contract/coverage/vector fields, not question plaintext.

A fifth hook changes pooling source only in a private installation copy and
submits an uncached suffix. Fingerprint mismatch prevents inference; explicit
`pending` and original lexical body arrive in 1,068.162 ms, with matching
publication and ACK. The common snapshot and production installation remain
unchanged. OS page caches were not reset. These individual diagnostics are
neither an LLM trial nor a latency distribution.

The final five-hook run took 9.59 s with sampled descendant peak 1,267,296 KiB.
Full regression passed in 108.40 s, peak 2,964,560 KiB, below the 3,500,000 KiB
guard. Only synthetic numerical inputs and their serialized nonfinite fixture
were adapted to the new schema; batching/ranking/ownership/rejection assertions
remain. No production compatibility reader was added. Generation-model calls
are zero; no token/quality adoption or enlarged latency gate has run.

Earlier construction errors and a secure-IO fixture using macOS's `/var` alias
are retained. Canonicalizing that temporary path required only a helper rebuild;
the qualified runtime executable was unchanged. Initial failures, repaired
helper hashes, full-suite fixture changes and separate guard logs remain in
the evidence. Existing deferred-work `NoSuchFile` warnings are retained, not
treated as resolution of the user-deferred `hook output missing` investigation.

The full-suite's three remaining index tickets disappeared after a separate
daemon drained them. Its shutdown command acknowledged shutdown but hit its
exit-wait timeout (exit 1); subsequent inspection found no daemon endpoint or
matching process. That failed command is retained. Pre-drain head hashes were
not persisted before the wrapper's exception, so this particular three-ticket
cleanup does **not** prove head immutability. The full regression's separate
native index-recovery immutability checks did pass. Ordinary probe hooks all
shut down successfully. The subsequent [owned-process counterfactual](lexical-index-native.md#owned-daemon-test-lifecycle)
reproduces and repairs the test parent's reaping order without changing the
runtime daemon. The missing pre-drain head hash remains a limitation of this
earlier run.

Evidence roots:

- `/Users/ovm/.codex/experiments/eggshell/context-candidate-20261020/qualified-1/`
  contains inputs, overlays, executable, helper repair and full-suite fixtures.
- `/Users/ovm/.codex/experiments/eggshell/context-native-20261020/qualified-final/`
  contains the common seed, both warm/doctor paths, all five native deliveries,
  receipts and private question-record hashes. The earlier three-hook
  construction diagnostic is retained separately.
- `.lake/hook-audit/context-*` contains process guards and complete logs.

Next: dictionary-free 2-gram index integration, 10,000/50,000-window and actual-DB
latency strata, then a measured storage/residency decision and the fixed matched
pilot. Complete delivery ancestry, main theorem, the 61-proof inventory, sound
tool rules, full experiments and paper remain required.
