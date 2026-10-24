# Bound numerical reads before scoring

This isolated Lean component follows the accepted-empty candidate. The product
runtime and installed binary are unchanged. It preserves the core separation:
numerical routing supplies advisory keys; generated Work recognition must remain
complete and independent. It is not a new equivalence relation or an adopted
token/quality improvement.

## Why the full read path must change

The original 50k publication contains 49,969 owners and 50,000 discovery windows.
Its prepared matrix also contains focus projections, for 99,969 distinct keys.
An independent scalar read of all 50,000 discovery rows takes **55,715 ms**.
The split reader returns every identical coverage record and projected bitstring.
Its 54,911 ms includes these disjoint stages:

| Stage | Time |
| --- | ---: |
| Authenticated point lookup | 23,249 ms |
| Original chunk reads/checks | 19,095 ms |
| Binary-to-hex encoding | 10,563 ms |
| Descriptor decode | 503 ms |
| Before/after version checks | 115 ms |
| Coverage parse/validation | 125 ms |
| Finite-value validation | 746 ms |
| JSON framing | 363 ms |

Both readers perform 81,466 page/blob reads and read 327,716,035 bytes. Remaining
wall time includes instrumentation/bookkeeping. The scalar pass runs first and
warms the OS cache; these are access diagnostics, not a new provider speedup.
The 4,096-row check also agrees with the scalar reader. No model, warm or source
encoding runs during these profiles. Raising a hook timeout cannot make this
full access path fit the existing 30-second deadline.

## One bounded, original-key view

The prototype builds a rank-balanced binary tree from twelve exact coordinate
bit-orders. It does not quantize vectors used for scoring. Ties are split by
original key so skew and identical coordinates cannot create oversized leaves.
Each leaf holds at most 32 keys. The normal Lean `Prepared` constructor proves
that the tree's complete point list is a permutation of its original inputs;
the node codec proves a tail-preserving roundtrip. The query returns checked
leaf/key/node bounds, with a maximum allowance of 128 leaves, hence at most
4,096 vector nominations. These are structural proofs, not nearest-neighbor
recall or filesystem-refinement proofs.

Only keys and split metadata enter the derived PageMap; vector payloads stay in
the original matrix. Its atomic header binds the captured matrix head. Creation
requires every distinct matrix key, validates its original row/chunks and does
not rewrite matrix bytes. A new matrix head makes the route unavailable;
it cannot silently hide newly added vectors behind an old ready marker.
Old pinned readers survive later matrix/index publications.

The current query visits checked pages and selects nearby ordered regions.
It is deliberately approximate. All original vectors it selects are scored by
the unchanged provider. There is no conservative full-ranking skip theorem,
new source authority, Bloom-based equality or recommendation top-K limit on
Work recognition. The builder retains its coordinate rows in memory; it is
not yet an external-memory or incremental builder.

## Component measurements and recall

Building the index for all 99,969 projections takes 35,472 ms, excluding original
domain/key enumeration. It stores 8,191 nodes and 4,096 leaves. Four source-vector
queries with a 128-leaf quota each return 3,124 original projection keys.
Routing takes 41–43 ms; reading and validating those complete original vectors
takes 2,094–2,768 ms. Setup, scoring and a native hook are outside those timers.
The queried source vector reaches its own leaf, including 65 completely tied
fixture coordinates. This self-check does not establish useful-language recall.

One frozen natural-language question is then evaluated with the same current
MiniLM and unchanged reference provider. Lexical/anchor lists are empty to
isolate the numerical branch. The full request scores 50,000 windows/49,969
owners in 60,694 ms. Routing takes 37 ms and nominates 3,125 discovery windows;
the original provider scores them in 3,915 ms. The reference runs first and
creates the private query embedding; the routed call reuses it. These component
times are not a paired native-hook speedup or token result.

The original top eight owner IDs and routed top eight have **zero overlap**.
Independent Lean cosine scores on their unchanged full vectors are approximately
0.9008–0.9034 for the reference and 0.8919–0.8992 for the routed set. This diagnostic
is not bitwise NumPy-score equality. Ranking changed as expected for approximate
routing. Neither overlap nor cosine establishes whether required original code
was missed, or whether answer quality/total tokens improve. The policy is not
retuned to this question and is not adopted on these results.

## Boundary and next work

Maximum aggregate experiment RSS is 1,911,408 KiB, below the 3.5 GiB guard and
4 GiB ceiling. All final guards/owned processes finish. Terminal helper binaries
are hashed and deleted without archives; source, generated code, objects,
response files and raw evidence remain. The [review](candidates/vector-route-review.json)
and its consistency check pin those inputs and results.

The original head checks and root/lexical file hashes are retained in the review.
The fixture rejects excessive quota, duplicate keys, a stale matrix basis,
foreign models and malformed derived nodes; it also retains old pinned views.
Ordinary proof axioms are audited. Earlier compile/API/link mistakes and the
nonmatching top-eight result remain recorded rather than hidden.

This component is not connected to `Warm` or normal discovery. Next, use routed
window-key-to-original-owner postings in a coverage-reporting advisory protocol,
so the caller does not still transfer every document to choose which to read.
Preserve lexical/synaptic nominations and complete class recognition, and measure
actual required-original coverage before matched model trials. Add source-change/
delta compensation and atomic replacement before routine growing/shared use.
The current complete-head invalidation is safe availability behavior, not that
incremental design.

No million-window, p99, concurrent/shared, privacy, answer-quality or inclusive
token qualification follows. AGENTS.md's matched topic/lap/repetition, total-token,
quality and deadline adoption gates remain. Phases 0–6 remain active.
