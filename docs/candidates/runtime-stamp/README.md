# Build the service identity once

This is an isolated, unadopted experiment. The current parent remains
`ea5b3861dfba62fe0e600552a13facb59595304c67b28fa9f2d3f395d66e0e35`.
No project query, answering model, new LLVM seed or mixed growth workload ran.

`PublicationWire` previously constructed its implementation digest from source
bytes during initialization of every full runtime process. The [candidate
patch](candidate.patch) evaluates the same expression during Lean elaboration
and emits a string literal. There is no manually supplied digest or version.
Source bytes, their order, the hash algorithm, and the transitive source stamps
remain inputs. The source file itself changes, so its digest is expected to
differ from the parent's; equality is checked against the **same current
candidate source**, not against an older source revision.

The [346-object native audit](native.json) is consistent. The [source audit](sources.json)
finds exactly one changed product module, `Eggshell.PublicationWire`, with no
added or removed module. The [declaration audit](literal-audit.json) checks
that `implementation` is a literal 64-character hexadecimal string with no
runtime call dependencies. An [independent native computation](reference.json),
using the former expression and the actual candidate sources, agrees exactly.
The [reference source](RuntimeStampChecks.lean) is a witness generated into
`source/Eggshell` by the controller; it is not linked into the product.
These checks do not constitute a kernel proof of the entire digest computation.

## A phase error in the initial observer

The first ABBA observation only sampled 400–1,200 ms after spawning the
supervisor. Its first candidate backend did not record initialized ingress
until at least 1,212 ms after that spawn; its final sample was at 1,189 ms.
All of that observation therefore preceded ingress. The apparently larger
RSS reduction is **invalid**, retained in [raw observations](footprint.json)
and the [receipt-based rejection](unphased-rejection.json).

The observer now requires a fresh ingress receipt belonging to the observed
backend PID and takes samples 100–700 ms after ingress, with at least 200 ms
of observations. It retains every sample, receipt, output and child identity.
This is a correction to the measurement phase, not a product or resource-limit
change. See [predeclared ready plan](ready-plan.json) and
[native observer audit](ready-probe-native.json).

## Initialized comparison

Both arms use the exact same small supervisor
`259d63ec1ca2c3b8f4dd8eb6c32a867b53055de3e1a2d20a2481cbc21a8cbe72`,
ordinary unset `LEAN_NUM_THREADS`, blocked stdin, and the same two-second
supervisor deadline. The backend is the treatment.

| Order | Backend | Owned pair peak RSS | Exit time |
| --- | --- | --- | --- |
| A | Parent | 93,072 KiB | 2.480 s |
| B | Candidate | 90,304 KiB | 2.217 s |
| B | Candidate | 90,288 KiB | 2.234 s |
| A | Parent | 93,008 KiB | 2.242 s |

The [initialized observations](ready-footprint.json) show paired reductions of
**2,768 / 2,720 KiB**, about 2.7 MiB. They miss the predeclared **8,192 KiB**
condition for another growth run. The smaller positive component effect is
retained; no 14-client retry, capacity claim, whole-hook speedup, token saving
or adoption follows. The intentionally blocked-input timing is not query time.
See the [decision](result.json).

Initial compilation exposed a declaration comment attached to `run_cmd` and
missing explicit meta imports. The reference then needed a public import,
the declaration auditor needed a qualified logger, and the generalized
observer needed an IO hash lifted out of a conditional expression. Failures
remain alongside [all terminal guard records](guard-records.json). These
corrections did not alter search, ranking, budgets, writers or the final
product binary after its successful build.

Ended candidate source copies, binaries, native caches and synthetic receipt
data are deleted: 7,250 entries / 1,650,128,696 logical bytes, without an archive.
[Cleanup](retired.json) and the
[parent audit after cleanup](product-after-cleanup.json) retain the counts and
integrity evidence. The parent backend, small supervisor, model and protected
LLVM original remain.

The current whole-workload failure is still the parent's fourth additional
14-client wave at the memory guard. General 98% delivery, sustained 80-user
operation, the accepted LLVM seed and both topic passes, inclusive token and
quality comparisons, and NAS deployment remain unfinished. The next structural
target is per-query gateway process creation, preserving cancellation, scope,
captured read cuts and durable ACKs rather than serializing independent queries.
