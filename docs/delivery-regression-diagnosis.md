# Delivery and token regression diagnosis

The required outcome is recovery of token savings and answer quality while
retaining the cache fixes. A rollback is not the acceptance criterion.

The historical README records 76.0% first-lap and 96.4% retained-lap savings
against fresh. The current topic-1 first-use candidate records 74.1% and 45.3%
in its two completed repetitions. The latter is candidate repetition 1:
2,932,984 fresh versus 1,604,261 candidate total tokens. Candidate repetition 2
and the current retained-lap model trials have not run. The answering Luna
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

The same combined-search versus full-candidate comparison also byte-matches
on topics 2 and 3, with identical input graph and prompt hashes. This checks
the cumulative performance boundary on all three questions at the seed
checkpoint; individual overlay boundaries and the retained checkpoint remain
unmeasured. Per-command exits and source-integrity checks complete, but the
last resource supervisor failed while parsing a multiline `ps` argument. Its
missing final peak measurement remains unavailable. The parser was corrected;
no model trial was repeated and this observation is not a latency result.

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
