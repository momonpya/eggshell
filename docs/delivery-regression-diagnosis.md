# Delivery and token regression diagnosis

The required outcome is recovery of token savings and answer quality while
retaining the cache fixes. A rollback is not the acceptance criterion.

The historical README records 76.0% first-lap and 96.4% retained-lap savings
against fresh. The current topic-1 first-use candidate records 74.1%, 45.3%
and 69.3% in its three predetermined repetitions. The 45.3% observation is
candidate repetition 1: 2,932,984 fresh versus 1,604,261 candidate total tokens.
The current retained-lap model trials have not run. The answering Luna
model and the saved seed differ from the historical study; the search MiniLM
model does not. These facts do not establish a single cause of the gap.

Generation is stopped. Existing model attempts and their consumed usage are
retained. Public-version token use is not an evaluation arm. The current
candidate has material answer errors and is not accepted.

## Fixed-input, zero-generation comparison

`tools/delivery_parity.py` builds `tools/DeliveryAudit.lean` against copies of
the already built implementations. Their frozen Eggshell executables are
checked unchanged. It prepares discovery and focus vectors and the lexical
sidecar before inspecting the real delivery function. Every comparison uses
the same saved graph bytes, exact prompt, LLVM workspace and 120,000-character
packet budget. Graph bytes are checked before and after inspection. Private
query data stays in the experiment directory.

This is an uncensored delivery comparison, not a hook-latency measurement or
a token-savings experiment. The helper allows five minutes and disables writes
of derived demand memos to the source publication. The valid full-candidate
body is checked against the actual native benchmark packet. Neither different
metadata nor a `search-incomplete` notice counts as a matching delivered body.

Artifacts are under:
`/Users/ovm/.codex/experiments/eggshell/readme-delivery-parity-20261020/`.
`inspection-2` contains the valid read-only-publication comparisons. The first
helper allowed derived publication writes; that failed harness observation is
retained. A combined-search attempt before explicit lexical-index warm also
returned pending; its original observation remains separately recorded. Neither
is used as a valid body comparison.

The comparison baseline is public `main`
`51873167c11c447a0af67e73430b5ab6635b2a65`, checked again against the remote.
With healthy prepared caches, **public versus current delivery differs on all
three initial questions**. The previous three-question equality concerned two
candidate builds; it did not establish equality with the public version.

On the common seed and topic 1:

| Implementation | Delivered body SHA-256 |
| --- | --- |
| Public delivery with prepared session vectors | `d1fbb75db3f8d22e89e6fbca464643c14edef2533c254f724d86359bddc96c7f` |
| Combined complete-context / gram search before later performance overlays | `a6c99a918aac4a2149305bd1547aae96a908a423b216e36612eff22ee14017e7` |
| Full current candidate | `a6c99a918aac4a2149305bd1547aae96a908a423b216e36612eff22ee14017e7` |
| Full current delivery with the prepared public search provider as a diagnostic control | `d1fbb75db3f8d22e89e6fbca464643c14edef2533c254f724d86359bddc96c7f` |

The candidate hash is also the actual initial packet hash in **both** completed
model repetitions. In this case the cumulative performance overlays preserve
the initial body, while changing the provider changes it. The provider control
retains current delivery and lexical-index code. It is a diagnostic, not an
adopted old provider or a production cache rollback.

The public and full-candidate body hashes for the other initial questions are:

| Topic | Prepared public body SHA-256 | Full candidate body SHA-256 |
| --- | --- | --- |
| 2 | `e4c1cc050f6a0b62454025274dc0502de79fbd7b6bbf02eabbb19a506a415426` | `3df20daa7a9e245c486b4053e82a1c6df68226b7dab9222817c8c92b28b7ebcd` |
| 3 | `484038fbdfe5dc2d9159b2ed5699001bdeff929d3b68fe9c0b4c9290190a5909` | `12473c8e1063c115a3ea8860e182f94dc74be0543058ef9fb3963f62d69546a9` |

The combined-search versus full-candidate comparison byte-matches on topics
2 and 3. That is only an internal cumulative-performance check, subordinate to
the public comparison above. Individual overlay boundaries remain unmeasured.
Per-command exits and source-integrity checks complete, but the
last resource supervisor failed while parsing a multiline `ps` argument. Its
missing final peak measurement remains unavailable. The parser was corrected;
no model trial was repeated and this observation is not a latency result.

All 1,956 source/focus windows in this public-produced seed have identical
first-segment float32 bits in the public cache and the modern full bundles.
An isolated diagnostic projects only the first segment into scoring while
retaining modern full-bundle storage, DB cache ownership, warm, lexical code
and delivery/performance changes. Its initial bodies equal the prepared public
bodies on all three topics. This narrows the initial-body change to the expanded
scoring input in these cases. It does not establish the cause of token use or
quality errors, and the control is not a proposed production repair. Full stored
coverage must not be reported as full scored coverage for this control.

A native-hook preflight of the first-segment control delivers topic 1's public
body in 11,041 ms, with semantic search complete and zero source encoding.
The daemon and shutdown client exit 0. The first harness fails its overly broad
physical-publication immutability assertion: 21 memo rows and two journal rows
were added. An explicit logical-publication audit finds identical authoritative
values in order and union endpoints, unchanged existing non-memo rows, and a
neutral revision with no added/removed roots or changed unions. The original
assertion failure is retained alongside the recovered observation; physical
page/head bytes are not claimed unchanged. Each future measured turn must still
start from the exact common snapshot bytes, not this preflight's memo state.
No generation-model call was needed for these checks.

The subsequent fixed first-use scoring diagnosis completes all three control
repetitions: 269,654 / 562,109 / 443,128 total tokens, or 91.2% / 80.8% / 86.1%
reduction against their original fresh references. The control beats the full
candidate in all three repetitions. Every initial native body matches the
prepared public body; every recorded hook is below 30 seconds. Only four new
model calls are made (the missing full-candidate repetition and three controls),
with no recorded errors/reroutes, repeated existing attempt or reacquired seed.
Cached input remains included. The fixed source is unchanged. These observations
support a scoring-related token regression on this question, but do not accept
the first-segment control, establish quality recovery, or complete the other
topic/history cells. The original answers and source-review limits remain.

The saved after-topic-1 checkpoint also has three public/candidate body
differences, but its primary lexical index mixes old plain terms with newly
saved `P`-prefixed terms. For example, plain `driver` still has 24 owners, while
`Pdriver` has 10 owners; the public lookup cannot search those new primary
postings. The original seed has zero `Pdriver` postings. Therefore these history
comparisons are **not healthy public controls** and support no retained-lap
conclusion. `primary-postings-audit.json` preserves the check. Prepare an
identical private history snapshot with complete public-readable primary
postings for both arms before comparing history; preserve every authoritative
value, root order, owner ID and union. The original checkpoints stay intact.

That preparation is now complete in
`readme-history-public-index-20261020/construction-1`. A helper compiled against
the public implementation imports the same 148 authoritative values into one
new private publication through the ordinary producer. Authority, root order,
root/owner/Work/window IDs and unions remain equal; complete plain-term postings
include all 34 `driver` owners. Warm and repeat validate all 2,437 source/focus
windows. Both implementations receive byte-identical copies of this publication.
Public versus full-candidate bodies differ on all three questions, and the
first-segment control equals public on all three. The model and source graph
are not regenerated. The earlier mixed-index comparisons remain invalid; this
separate comparison establishes the healthy public boundary after topic 1. It
is not a whole retained lap, token result or quality result.

The actual three prompts are English. Executing each implementation's lexical
term function shows that their ordered query terms agree after removing the
candidate's primary-term namespace tag. Thus a Japanese-query gram-noise
explanation does not describe these prompts. Document term frequencies and
other questions still require their own checks.

## Link body differences to observed work

The initial body contains 23 Work graph blocks in each implementation. In the
candidate, identifiable tool-observation blocks total about 102 KB and the
answer/other block about 7 KB; this is a composition diagnostic, not token
accounting. The hypothesis that historical-answer prose filled the packet is
not supported by this observation.

The public and candidate bodies have 22 Work graph IDs in common. The public
body additionally includes a Darwin/GNU toolchain source observation; the
candidate instead includes a broad Driver test-file listing. Ordering and
excerpt differences within shared blocks must also be inspected. Both bodies
include the `spirv32`/`spirv64` condition relevant to the erroneous answer.

The two actual candidate repetitions execute 16 and 40 tool commands despite
identical initial bodies. Some additional commands read new test/implementation
files; a file name appearing somewhere in a packet does not establish that its
requested range was already delivered. The later packets, exact read ranges
and answer claims must be compared before treating these commands as waste.
An initial-body difference locates a behavior change; it does not by itself
prove the cause of token use or quality loss.

Continue the same fixed-input comparisons across the three topics and the
available saved checkpoints, then narrow any differing boundary. Preserve
performance improvements whose output agrees. Only a controlled fresh-relative
token and quality result can accept a behavior-changing repair. The historical
README savings claim remains unchanged and the full goal remains active.
