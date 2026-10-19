# Retrieval review, 2026-10-20

The truncation and missing lexical scripts are real defects. This change adds
isolated numerical and native Lean experiments, not a production retrieval
change. No generation-model trials, study seeds, token-saving claims, README
results or releases are added. The production executable, matcher, source
index and provider remain unchanged. Normal use still requires a warm DB.

## Decisions

| Review | Evidence and decision |
| --- | --- |
| Embedding truncation | Confirmed. The installed tokenizer config contains `max_length=128` and `model_max_length=512`; FastEmbed uses their minimum. Special tokens leave 126 source tokens. Preserve original DB windows and encode every bounded token segment, for both questions and sources. |
| Multilingual lexical loss | Confirmed by running the actual native `SearchRank.terms`: Korean, Cyrillic, halfwidth Kana and fullwidth ASCII examples return no terms; accented words are fragmented. Use dictionary-free overlapping script pairs, word/path units and auxiliary single characters. |
| NFKC and accent deletion | Refine rather than apply globally. The candidate unifies ASCII/Kana width, including voiced marks, and retains Unicode letters/numbers/combining marks. Accents remain part of a word. General NFKC and composed/decomposed Latin equivalence are not implemented. Retrieval aliases never enter `LogicalText` or equality authority. |
| One file per window | A valid scaling concern. Do not infer a 50,000-window latency from a per-open estimate. A float32 binary coefficient takes one quarter of the current hex binary64 bytes, excluding metadata. That is a storage calculation, not a retrieval, ranking or token-saving result. Measure native read/decode/check/score costs before changing persistence. |
| Encoder residency | Repeated initialization is observed, including discovery/focus in a fresh hook. First evaluate sharing one encoder within a supervised hook; a permanent daemon requires additional scheduling and lifetime design. Historical 1.4–4.6 s kernel profiles precede later optimizations and cannot establish the current bottleneck. |
| Larger latency gate | Required before a pilot makes a general practicality claim. The current fixed gate covers only up to 1,024 original windows, one per source, not arbitrary DBs. Add 10,000/50,000 windows and an actual saved DB under the same accounting and deadline rules. |

No morphology analyzer, language dictionary, stopword table, extra continuity
bonus or manually numbered cache/index format is introduced. The generated
Unicode category intervals and width maps are small deterministic tables in
the native binary; Python is only their offline generator.

## Complete token input experiment

[`context_encoding.py`](../tools/context_encoding.py) clones the model tokenizer
once per encoder. It tokenizes without truncation, splits the complete token
sequence into context-sized segments with 16-token overlap, and adds the
model's special tokens afterwards. Each segment's token IDs, order and original
offsets are checked against the corresponding complete sequence slice. It
never decodes/re-tokenizes text fragments. ONNX inference and pooling use the
installed FastEmbed kernel; batches contain at most 32 segments.

The shortcut `tokenizer.encode(text).overflowing` lost a suffix in this
environment (Tokenizers 0.23.1); the first construction attempt was rejected
by token/offset checking. Explicitly splitting the untruncated encoding avoids
that observed failure. This is an observation about the installed path, not a
claim about every tokenizer release.

The [`retrieval_audit.py`](../tools/retrieval_audit.py) diagnostic uses fixed
controlled texts, original 512-character windows and stride 384. Its coverage
denominator is the source's non-whitespace characters; the numerator is their
union of attended non-special token offsets across **all** original windows.
Per-window token-mapped characters are separately recorded. Token coverage
does not mean the model understands or retrieves the relevant fact.

| Text | Current embedded characters | Complete candidate |
| --- | --- | --- |
| Japanese | 595 / 1,140 (52.2%) | 1,140 / 1,140 |
| Korean | 912 / 1,140 (80.0%) | 1,140 / 1,140 |
| Code | 1,874 / 1,960 (95.6%) | 1,960 / 1,960 |
| English | 1,420 / 1,420 | 1,420 / 1,420 |
| Cyrillic | 1,575 / 1,575 | 1,575 / 1,575 |

These are examples, not language-wide omission rates. All 23 original windows
remain present; the candidate produces 41 vectors. It evaluates every query
and source segment pair and retains the complete order for each of three
fixed queries. No quality improvement is inferred from those ranks.
Five short inputs, including Japanese, Korean, empty text and combining/emoji
sequences, have one candidate vector each, bit-identical to the ordinary
float32-normalized output in the same batch.

Observed final isolated timing: constructor 297.1 ms, one-time tokenizer clone
181.9 ms, current embedding 356.2 ms, candidate embedding 619.8 ms. These are
single diagnostic timings outside a native hook. A rejected implementation
cloned the tokenizer per window and took 6,049.8 ms for candidate embedding;
the encoder-scoped planner removes that repeated work. More input segments
still cost inference time, cache space and scoring, so this candidate needs
native latency and matched quality/token evaluation.

Eleven boundary controls cover omitted source/question suffixes, empty and
whitespace text, combining/emoji/control characters, literal special tokens,
long repeated characters, invalid overlap and non-mutation of the original
tokenizer. They pass separately from the inference diagnostic.

The cache contract must be derived from model bytes, tokenizer bytes,
pooling implementation and segment policy/code bytes. The prototype records
model/tokenizer/code digests and the numerical class name; binding the actual
pooling/runtime implementation remains part of integration. A changed contract
must make old one-vector windows cold; their existence cannot certify complete
input coverage. The production cache/doctor/receipt integration is **pending**.
An eventual record must distinguish original DB windows, segment vectors,
token-offset coverage and model-normalization omissions, and must retain no
question plaintext in shared storage.

## Dictionary-free native lexical candidate

[`RetrievalGrams.lean`](../tools/RetrievalGrams.lean) retains words and paths as
units. Kana, Han and Hangul form script runs separated by word boundaries,
punctuation and whitespace. Every adjacent pair in a run is a primary term;
every scalar is an auxiliary term. ASCII width is folded before case folding;
halfwidth Kana and voiced marks compose to their ordinary forms. Unicode
letters/numbers and attached combining marks survive instead of disappearing.

Primary IDF score orders rows first; auxiliary IDF score breaks ties, then
the original stable ordinal does. A one-character question has only auxiliary
terms and therefore still retrieves a longer script run. Corpus frequencies
are compiled once with the existing `Frequency` kernel, not rescanned for
every scored row. No blending weight or language dictionary is needed.

The Lean theorem `adjacent_pair_present` proves that any adjacent pair in one
normalized run is retained. It does not assert that normalization preserves
arbitrary original substrings, retrieval relevance or source identity.
The candidate is built in a separate checkout/compiler cache by
[`prepare_retrieval_research.py`](../tools/prepare_retrieval_research.py).
Fifteen native controls and four multilingual probes check overlapping pairs, word/script/punctuation boundaries,
single-character retrieval, supplementary Han, width aliases, preserved
accents and unchanged identity units. Generated Unicode interval boundaries
are checked against a linear oracle at 4,364 points; the generator is reproducible.

The production DB postings are built with the **old** terms. Connecting this
candidate to those postings without rebuilding would turn valid matches into
false negatives. The index contract must therefore be content-derived and
checked before use. Read-only shared DBs need a user-owned derived index, not
a graph rewrite. Both indexed and fallback scoring must use the same terms.
This index integration and a native end-to-end retrieval comparison are
**pending**; the standalone grammar is not a replacement provider yet.

## Expanded gate and remaining order

First connect the complete encoder/cache contract and dictionary-free index
in an isolated candidate, including coverage in doctor/receipts. Then freeze
the same saved snapshots for both runtime arms. Use sizes 2, 1,024, 10,000 and
50,000 **windows**, DB/private-overlay layouts, fresh/cached questions, and
three predetermined repetitions: 48 hooks per arm. An actual saved DB is an
additional 12-cell stratum, not a substitute for failed synthetic cells.
Record owner counts, window counts and segment counts separately, including
a source with many windows; one source per window is not a general workload.

Preserve the current five-second gate, 4,500 ms semantic cap, warm-before-use
condition and read-only protections. Freeze each actual DB's graph/input
hashes, model, question, source target, runtime and harness. Record warm/index
completion and exact published body/stdout/SHA/ACK, semantic completion,
source/query probes, process startup, model initialization, embedding,
read/decode/check, scoring, kernel extraction, lexical fallback and cleanup.
Keep timeouts and failures; do not increase the budget, resample or replace
them. Do not present phase-only or synthetic file-open measurements as hook
completion. Keep preparation/seed costs separate and RSS below the existing
3,500,000 KiB guard.

Only those measurements determine whether an immutable per-DB float32 matrix,
hook-scoped encoder reuse or residency should come next. Full original scoring
and complete-rank comparisons remain required; a smaller candidate subset is
not an optimization here. Any matrix design must also preserve bounded reads,
pinned file identity, finite/dimension checks, atomic publication and read-only
DB ownership rather than trading them for raw mmap speed.

After the practical gate, resume the six-condition pilot with the common seed,
initial/history use × topics 1–3 × equal predeclared repetitions. The latest
public main remains the adoption baseline. Inclusive input+output tokens,
cached input, failed attempts, answer quality and deadline completion determine
adoption. Coverage, proof checks and storage bytes are not substitutes.

## Evidence

Root: `/Users/ovm/.codex/experiments/eggshell/retrieval-review-20261020/`.
`qualified-final/` contains the complete numerical results, all ranks, final
native lexical output, frozen helpers and independent source/runtime audit.
`qualified-2/` retains the earlier 311.5/185.9/360.4/621.9 ms numerical diagnostic
and original native lexical output before width folding. No timing difference
between these runs is claimed as an optimization. `grammar-qualified-final/`
contains the final isolated native build/tests and source hashes.
Earlier construction failures and the slow planner diagnostic
are retained. Guard/process records are under `.lake/hook-audit/retrieval-*`
and `context-encoding-controls-1-*`.

The latest full 48-hook production-candidate gate still has maximum 4,055.051 ms
at up to 1,024 windows; see [semantic-latency-results.md](semantic-latency-results.md).
It is not rerun or extended by the diagnostics above, and the original
`hook output missing` investigation remains user-deferred.
