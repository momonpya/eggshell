# Stable reads of atomically retired storage

Isolated candidate on terminal-closure (`302ead20…`), not adopted. Product
SHA-256 is `ed077918092c75ac1a2416b157cb37f1186a387314455febf3f010c03e5f5817`.
The only direct product source change is `Eggshell.FileSystem`; ContentCapture's
embedded copy of that source changes with it. The model, numerical scores,
synaptic graph, WorkGraph certification, selection, and delivery instructions
are unchanged. The 336 native objects and all 335 product modules/literal inputs
match the declared source change.

## Problem and implementation

The [parent's concurrent-publication test](../../practical-runtime/automatic-publication/README.md)
had one Pre callback return an incomplete notice with `storage object mutated
during read`. A native postmortem separately reproduced the underlying failure
mechanism: replacing an atomic metadata path changes the old inode's ctime while
its held descriptor still contains the complete old committed bytes. Rejecting
that image forever is unnecessary for snapshot-based storage. The exact file
behind the original callback was not identified, so this is not a claim of
definitive attribution of that particular failure.

The reader now makes at most three immediate attempts on the same pinned
descriptor. Every returned `StorageImage` carries checked full before/after
version equality, complete original size, and the caller's byte bound. An
unstable attempt contributes no returned bytes. A stable first attempt still
performs one read; no lock, wait, sleep, path reopening, or catch-all error
handler was added. Truncation, budget errors, and native IO exceptions propagate
without retries. The separate external-source freshness check is unchanged:
replacing a source path still invalidates its old evidence.

Six new kernel laws cover accepted image invariants and rejection of mutated,
incomplete, and oversized images. The four existing read/freshness laws also
pass; their recorded axiom sets contain only standard Lean axioms. This proves
the checked predicate, not the OS adapter or arbitrary physical IO behavior.
The native diagnostic's dependency audit separately forbids locks, sleeping,
and reopening from the pinned reader.

## Native boundary checks

- An unchanged 9,001-byte image is read once: two version checks, three pages.
- A real atomic replacement during the first page succeeds on attempt two:
  four version checks and six pages return the original held bytes, while the
  path contains the new bytes. External freshness rejects the original.
- Two in-place mutations stabilize on the third attempt.
- Continuous mutation is rejected after exactly three attempts.
- Oversize is rejected before any page read; truncation and an injected native
  IO error fail on their first page; an empty committed image remains readable.

The first strict subset audit rejected the additional shared fixture library.
That rejection is retained, and no native checks ran before correcting the
audit's scope. The replacement comparison checks every product core module,
313 common native sources, and exact separately hashed fixture/helper source
bytes. It does not exempt a product change. The product source audit remains
the full 335-module comparison above.

## Actual registered hooks under incremental publication

The same automatic-publication fixture runs on the new product, with two empty
logical projects, four owners each, and four waves of four writers. Each writer
reads both projects and writes only its selected project. Ten new read-only
clients query after each wave; another ten readers overlap each incremental
writer wave. No manual keep/warm, hook replay, or generative answering model is
used. Readiness probes only inspect stored references.

All 70 semantic searches complete. Before admission, the test freezes required
fields from published original observations. Actual bodies contain **640/640**
required original rows. An additional audit checks each row inside the `CODE`
block belonging to its own `SOURCE` path and native content fingerprint, rather
than merely finding those strings somewhere in the body. Project isolation,
48 observations, 16 final answers, and all three synaptic edge types survive
automatic publication and preparation.

| Wave | Four writers, plus ten overlapping readers in waves 1–3 | Ten fresh readers |
| --- | ---: | ---: |
| 0 | 4.624 s | 1.933 s |
| 1 | 7.434 s | 2.038 s |
| 2 | 7.992 s | 2.320 s |
| 3 | 8.720 s | 2.197 s |

SessionStart setup precedes each batch gate. Reader batch times include prompt
delivery and SessionEnd. Sequential readiness probes are residual waits, not
independent publication/preparation latency estimates. All reader searches
report zero warm requests and zero warm time.

All 354 actual callbacks have zero exit status, empty stderr, and no incomplete
notice. Failed receipt count is zero. UserPromptSubmit's observed maximum is
1.959 seconds (86 calls), Pre p95 is 2.528 seconds (48), Post p95 is 1.047 seconds
(48), and Stop maximum is 539 ms (16). These are fixture observations, not
production p99 or large-DB performance. Four background state-guard timeout
warnings remain recorded despite successful eventual persistence; they are
not declared fixed by this reader change.

Related sampled RSS peaks at 3,859,072 KiB, below the unchanged 4,358,524 KiB
protective bound. All six guards finish successfully, without triggering, and
all services stop with no owned processes remaining. Ended fixture DBs, caches,
helper executable/interfaces, and controls (16,529 entries, 1,041,164,509 logical
bytes) are deleted without an archive. Protected originals, current runtimes,
model, and native dependencies are checked before/after deletion; the surviving
336-object product closure remains consistent.

## Remaining gates

The parent and candidate each demonstrate this small automatic-publication
fixture; these are not matched total-token experiments or evidence of a speed
improvement. There is no accepted new LLVM seed, no answering-model six-stage
run, no quality comparison, and no matched paid comparison (0/18). Product
adoption remains zero under AGENTS.md. Large growing DBs, general 98% evidence
delivery, 80 people over eight hours, multiple hosts/NAS, and MCP privacy remain
unverified. State-guard contention and current-runtime LLVM delivery are next
practical checks; do not repeat the incomplete paid seed or relax its cap.

Reproduce by applying `candidate.patch` to the stated parent source and building
with the fixed toolchain. `StableStorageReadStudy.lean` records the native build,
source audits, deterministic boundaries, isolated installation, automatic flow,
fingerprints, and kernel laws. `AutomaticPublicationStudy.lean` provides shared
retention, source-block/callback audits, and retirement; fixture orchestration
is a library with a separate CLI entry. Raw outputs and initial audit failures
are preserved; no failed attempt is relabeled successful.
