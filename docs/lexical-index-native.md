# Dictionary-free lexical index candidate

The isolated candidate connects overlapping character pairs to persisted DB
retrieval and native hooks. It has **not** been adopted into the ordinary
executable, README results or a release. It has no generation-model trials or
evidence of improved inclusive token use. The latest public main remains the
adoption baseline; complete input coverage and passing tests do not replace
the matched quality/token comparison.

## Retrieval policy

[`RetrievalGrams.lean`](../tools/RetrievalGrams.lean) emits adjacent pairs for
continuous Kana/Han/Hangul runs, with single characters in an auxiliary lane.
Words and identifiers/paths remain complete units. Primary IDF scores precede
auxiliary scores lexicographically; original source order resolves remaining
ties. A one-character question can therefore retrieve its source. No dictionary,
morphology analyzer, stopword table, continuity bonus or blending constant is
needed. Limited ASCII/Kana width aliases are retrieval-only; accents remain.
`LogicalText`, Exact matching and Work identity retain their original policy.

The emitter uses stable hash sets while scanning; it does not accumulate all
repeated pairs before deduplication. There are 224 comparisons against the
independent list/run oracle, plus 200,000 Han scalars yielding 20,000 distinct
pairs and 20,000 auxiliary characters. The adjacent-pair theorem, 15 ordinary
controls, four multilingual probes and 4,364 Unicode category boundaries pass.

## Derived storage and maintenance

[`RetrievalIndex.lean`](../tools/RetrievalIndex.lean) stores a collision-checked
term dictionary, owner postings, global frequencies and chunked reverse terms
in the existing PageMap B-tree. Long terms do not become giant filenames. The
index belongs to the DB incarnation, under `derived/<identity>/lexical/` for
writable owners and the existing private `read-cache/<identity>/` otherwise.
No source graph rewrite or question text is needed.

The path and readiness record bind the actual grammar/category/normalization,
ranking and index code bytes. No manual version is introduced. Readiness also
binds DB identity, authority, root append counter and live candidate count.
Derived matcher/query memo publications do not invalidate the corpus. Old
inline retrieval postings cannot certify the new policy.

Explicit/background warm invalidates readiness before publishing any delta,
uses at most 32 owners per batch, and bounds pending term writes at 256. Only
new owners hydrate source bodies. Deletion removes their postings; re-addition
reuses immutable reverse terms. Ready is published only after validating the
complete live owner catalogue and unchanged source stamp. A pinned old reader
keeps its complete immutable root across a later publication.

Native hooks open the ready index once per source; they never build it.
Hybrid search requires both complete lexical and numerical preparation. A cold
lexical index is explicitly pending; fallback may consult the old original-unit
postings as coarse advice. Width/case aliases are guaranteed only after warm.
This cold route does not certify complete new-policy rankings. A partial index
cannot be interpreted as a completed empty corpus.

The checked [`lexical_candidate.py`](../tools/lexical_candidate.py) overlays make
indexed, staged, body-focus and ordinary provider scoring share one grammar.
Federated postings rebind local owners to checked canonical identities and
deduplicate them before counting global frequency. Exact/Work postings stay
separate. Encoder-disabled saves persist built-in lexical-only tickets through
the existing DB-owned queue. `egg warm` and `doctor` work without Python or a
numerical installation in this mode.

The index test performs 140 exact complete-order comparisons with direct
plaintext scoring over 40 sources, at anchored and unanchored settings. It
covers multiple batches, memo stability, append, deletion, re-addition,
interrupted publication, immutable old readers, DB copies and DB isolation.
It is not an assertion of retrieval relevance or token savings.

## Native evidence

[`lexical_native_probe.py`](../tools/lexical_native_probe.py) first uses a binary
compiled **before** the overlay to save five real Outcome roots. Korean has no
old retrieval posting. Both candidate layouts copy that identical graph rather
than independently generating seeds. The fixtures contain original Korean,
Cyrillic, halfwidth Kana/fullwidth ASCII, Japanese and accented Latin bodies.

Both DB-owned and user-private layouts warm exactly five owners; repeated warm
hydrates and adds zero. The numerical prefix is empty. Each layout then runs
six new native chats against an OS write-protected DB: Korean, Cyrillic, Kana
width, ASCII width, one-character Japanese and accented Latin queries. All
deliver the corresponding original body without invoking numerical search.
Each stdout matches its published SHA-256/bytes, flush deadline and accepted
ACK. All protected DB bytes and the common seed remain unchanged.

Observed single-run lexical hooks are 100.124–113.870 ms across these 12 cells.
The federated original/copy case delivers the original body once, in 112.533 ms.
Numerically cold search reports `pending`, performs no source embedding and
delivers the original Korean body in 148.267 ms. A deliberately stalled test
provider yields `timedOut` plus that body in 4,653.288 ms, below the unchanged
five-second gate; its PID is gone after cleanup. These are diagnostic timings,
not a latency distribution or the larger fixed gate.

A native encoder-disabled save then leaves one DB-owned lexical ticket. The
test removes the saving chat, persists the pre-drain head hash, and starts a
different native daemon. It drains the ticket, makes the index ready without
changing the graph head or restoring that chat, and the new Korean body is
delivered in another chat. Both shutdown client and owned daemon exit zero.

The complete existing native regression passes in 81.70 s, peak 2,984,832 KiB.
The isolated test overlays explicitly prepare lexical indexes for ordinary
warm-DB semantic fixtures and encode handcrafted term sets with the candidate
grammar. Existing matching, ordering, ownership and rejection assertions stay
in place. Native cold/timeout/worker tests do not use that preparation wrapper.
The first unprepared fixture failure is retained alongside its test-only
adaptation; the ordinary source and executable are unchanged.
After regression, the repaired shared `drain_indexes` harness recovers all
three remaining DB tickets with another daemon. Its pre-drain head hash is
persisted and unchanged afterwards; both client and daemon exit zero, with
no active tickets. This qualifies the shared harness fix, separately from the
one-ticket native save test above.

## Owned daemon test lifecycle

The earlier complete-context cleanup's shutdown failure is reproduced with
the unchanged binary. A test parent that synchronously waits for the shutdown
client leaves its already-exited daemon as a zombie. The client's `kill -0`
exit check therefore times out. Concurrently polling/reaping both owned child
processes completes the same shutdown with both exit codes zero (34.152 ms).
[`owned_daemon.py`](../tools/owned_daemon.py) applies that parent lifecycle fix
to `pilot_memory_probe.py`; the production daemon is unchanged. Pre-drain
head evidence is now saved before starting recovery. This does not establish
the head hash missing from the earlier three-ticket run, and is unrelated to
the user-deferred original `hook output missing` investigation.

## Evidence and remaining work

- `/Users/ovm/.codex/experiments/eggshell/lexical-index-20261020/construction-4/`
  contains the standalone grammar/index prototype and independent rank tests.
- `/Users/ovm/.codex/experiments/eggshell/lexical-native-20261020/construction-3/`
  contains the legacy seed executable, native overlays, build and unit checks.
- `/Users/ovm/.codex/experiments/eggshell/lexical-native-probe-20261020/construction-3/`
  contains the common saved DB, all 16 native deliveries, receipts, protected
  layouts, failed-source/timeout controls and independent ticket recovery.
- `/Users/ovm/.codex/experiments/eggshell/owned-daemon-20261020/counterfactual-1/`
  records both unchanged-binary shutdown conditions.
- `.lake/hook-audit/lexical-*` and `owned-daemon-*` retain guard logs and earlier
  construction failures. The native build took 57.00 s, peak 2,962,448 KiB;
  the final 16-hook diagnostic took 12.46 s, peak 152,512 KiB. Neither reached
  the 3,500,000 KiB guard.

The complete-context numerical candidate and this lexical candidate are
qualified separately so far. Their combined native path, the 10,000/50,000
window and actual-DB latency strata, and the fixed matched quality/token study
remain required before adoption. No large-DB claim follows from these five
source fixtures.
