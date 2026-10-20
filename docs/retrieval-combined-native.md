# Combined retrieval candidate and review follow-up

`prepare_retrieval_candidate.py` composes the complete-context encoder/cache
with the dictionary-free derived index in one separate checkout. No ordinary
runtime, installed assets, README results or release is changed. Generation-
model trials remain zero; no inclusive-token/quality adoption has occurred.

The native numerical check reuses the **exact earlier saved legacy DB** rather
than creating a new seed under the candidate policy. Both cache contracts start
cold; explicit warm prepares all three original windows and the lexical owner.
Repeated warm adds/hydrates/encodes zero. In DB-owned and user-private layouts,
OS-protected read-only hooks complete semantic discovery and original-body
delivery at 2,004.762/2,011.161 ms; a new chat with the same cached question takes
308.859/298.101 ms, with no encoder initialization. The long question and every
original source window retain their complete segments. A changed pooling file
is rejected before inference; pending plus original lexical body arrives at
718.982 ms. Stdout/hash/bytes/flush/ACK, both indexes, original source and DB
immutability are checked. These are individual diagnostics, not distributions.

The same executable also passes all 16 lexical-only/read-only/multilingual,
copied-DB, cold-numerical, forced-timeout and independent lexical-ticket recovery
checks. Full native regression passes in 101.55 s, sampled peak 2,932,256 KiB.
All three remaining tickets are drained separately with a persisted, unchanged
pre-drain head fingerprint and zero exit codes. The combined build took
152.81 s, peak 2,649,088 KiB. The original executable is unchanged.

## Review decisions backed by current evidence

**Maximum scores.** `retrieval_bias_audit.py` seals 48 controlled unrelated
source windows (96/256/512 characters, four languages) and 32 question texts
before inference. It uses the original and candidate numerical implementations,
the pinned identical assets, and the actual NumPy scoring kernel. Questions,
including longer repeated forms, have one or two vectors; source windows have
one to four. It retains every score for all 1,536 pairs. These repeated-text
diagnostics are neither independent observations nor a real-task false-positive
estimate.

Holding actual query vectors fixed and expanding the same source bundle from
its first vector increases scores in 364 pairs (608 have multiple source
vectors), with maximum increase 0.098872. One calibration pair crosses 0.38:
0.359242 to 0.412237. The held-out **question-topic** split has 768 pairs on the
same controlled source collection; neither original nor candidate has a 0.38
crossing there. Calibration-only Q99 is 0.325190; that lower value admits one
held-out pair. Without positive/recall labels this gives no reason to adopt
that cutoff. Keep 0.38 and full input coverage; evaluate labeled quality and
matched inclusive tokens before changing aggregation or thresholds. The audit
took 5.54 s, peak 1,240,720 KiB, and changed no runtime/model bytes.

**Similarity control.** The DB-index integration missing from the review is
already complete. The sixth arm also has existing [scripted native evidence](pilot-similarity-native.md):
ordinary/control generate 1/3 actual run-local unions and 0/1 completed
deliveries. That proves a discriminating mechanism on the fixture, not its
prevalence or benefit on real tasks. Preserve actual union/completion/omission
counts and causal ancestry separately from nominations. Retain Exact, child
membership and freshness for the specified single intervention. Only a
predeclared additional perturbed-task ablation should remove another guard;
it would not isolate the retrieved-flag effect or support production soundness.

**Document length.** `retrieval_terms --rank` now accepts JSON `query` and
`documents` on stdin and reports every source's full rank, characters, bytes,
distinct primary/auxiliary terms and matched-term counts. It runs outside the
hook and does not prime query vectors. Positive/negative, long/short,
single-character and empty-query controls pass. The pilot must bind those rows
to its frozen owner catalogue and correct-source labels; this tool alone is
not evidence of correct real-task ranking. No length penalty or continuity
bonus is added without that evidence.

**Canonical Latin.** NFC/NFD Latin equivalence remains a documented retrieval
limitation, including accented filenames. Accents are preserved; canonical
retrieval aliases, if introduced, must never change filesystem identity,
`LogicalText`, Exact authority or observed source bytes.

## Larger gate

The [fixed expanded protocol](semantic-scale-protocol.md) distinguishes original
windows, owners, segment vectors and two protected cache layouts. The legacy-
policy producer saves the same graph once for each of 2/1,024/10,000/50,000
windows, including a 32-window owner. Source fingerprinting streams bounded
pages; the preparation wrapper also saves SHA-256 graph-file hashes. It
records resumable attempts and leaves all failures intact. Saving is separate
from full warm and the 48 measured hooks; saved fixtures do not pass the gate.
The actual-DB stratum, these latency hooks, labeled calibration, matched token
study and all remaining proof/paper requirements are still open.

Evidence roots under `/Users/ovm/.codex/experiments/eggshell/`:

- `retrieval-combined-20261020/construction-1/`: composed source/assets, builds,
  unit checks, full regression, added helper hashes and ticket cleanup.
- `retrieval-combined-native-20261020/{context-1,lexical-1}/`: original saved
  fixtures, both layouts, 21 native deliveries and publication evidence.
- `retrieval-segment-bias-20261020/construction-1/`: sealed protocol, all encoder
  and scorer requests/replies, all scores, coverage and per-stratum results.
- `retrieval-scale-producer-20261020/construction-3/` and
  `retrieval-scale-fixtures-20261020/saved-1/`: original-policy fixture producer,
  bounded preparation, source snapshots and progress. Preparation is not warm.

The prototype's scale/rank helpers were compiled separately after the composed
runtime; its binary hash is checked unchanged. The builder now includes those
same targets. Earlier construction errors remain archived. Resource guards and
logs are under `.lake/hook-audit/`. Original `hook output missing` remains
user-deferred.
