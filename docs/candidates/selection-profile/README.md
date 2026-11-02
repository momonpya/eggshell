# Actual selector profiling

Model-free diagnosis, not an adopted product change. Runtime `bd609e52…` is
unchanged. The [plan](plan.json) fixed the source, six native hooks, replay
counts, exact-choice oracle, sampling and resource limits before execution.
The background save-admission warning is explained separately in the
[correction](background-admission.md); it is not source-update cancellation.

The six actual LLVM hooks again delivered the previously frozen 4/4, 7/7 and
5/5 items in both independent chats. Every topic body SHA matches the parent.
Hook times were 14,756–16,535 ms. Three other proposed requirements remain
unconfirmed in the original DB; this does not turn the interrupted source into
an accepted seed or establish first/history model-trial success.

The existing service instrumentation recorded 13 selections during harvest.
Unit construction took 26–166 ms, problem-domain construction 8–18 ms and
`selectView` 751–1,228 ms. Thus descriptor rereads alone do not explain most of
this measured selector work. These observations include instrumentation cost.

The Lean [replay driver](../../../tools/research/ReplayServiceQueries.lean)
uses original source heads, owner IDs and the exact logical query/choice saved
by [ServiceQueryLoad](../../../tools/research/ServiceQueryLoad.lean). No endpoint
secret or source capability is persisted. It prepares private source data,
obtains fresh read capabilities and runs the ordinary palette/select/release
RPCs. It makes no answering-model or embedding calls. The three untimed
warm-up queries all exactly matched their original hook choices. This input
is retained as a necessary test fixture with its path and SHA in the report;
ended DBs, caches, raw sampling logs and helper executables are deleted.

Replay completed 1/1, 6/6 and 70/80 requests, with sample maxima 1,343, 2,351 and
28,799 ms. Every completed request exactly matched its expected choice. The
ten failures and their last phases remain in the report. Four seconds of
native sampling were enabled only during the 80-request burst, so its outcome
is diagnostic, not a speed comparison with the earlier 73/80 run.

The [native stack excerpt](native-stack-summary.txt) shows repeated benefit
folds, winner-index updates, rating arithmetic, `afterBenefitFold` hash-set
construction and `basePieceAccept` membership checks. Recursive stack counts
are not CPU percentages. This narrows the next investigation to repeated pure
selection work; it does not yet validate an optimization. Existing compiled
hash-deduplication refinements must be checked before proposing them again.

The [report](report.json) contains the native results, all replay requests,
stage records, guard receipts, sampler exit and clean service shutdown. No
original source file changed. Aggregate replay RSS peaked at 2,539,968 KiB;
the 3.5 GiB stop, 4 GiB absolute ceiling and 2 GiB disk floor were unchanged.
Three helper compile attempts failed (reserved local name, record layout and
missing UInt32 JSON instance) before the successful build; no product tests
ran in those attempts. An attempt to reuse a guard receipt was rejected before
starting; subsequent attempts each used a new receipt. No failure was omitted
or relabeled as a successful run.

Actual session-lock holder timing and bounded background backlog progress
remain to be measured. Neither this selector burst nor the earlier ACK-only
check establishes 80-user full-hook capacity, p99, eight-hour operation,
98% general delivery, answer quality or total-token improvement. Paid matched
comparisons remain 0/18 and the product candidate remains unadopted.
