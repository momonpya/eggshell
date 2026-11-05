# Ordinary mixed load after the replay registration fix

Isolated, not adopted. The same four core files validated in
[replay-registration](../replay-registration/README.md) are frozen. The actual
service entry point is rebuilt rather than using the replay-check executable.
The harness adds read-only queue/feed-frontier observations during readiness
waiting. No worker, owner, queue, response-budget or memory bound is increased.

The ordinary fixture runs eighty query/Pre/Post/Stop writer loops, sixteen append
owners,5000-byte tool outputs, background preparation and eighty fresh reader
chats. It is an independently generated functional fixture. Neither the older
67/80 mixed result nor the frozen read-only80/80 result is a matched control for
this run. Do not claim a causal improvement or regression from their differences.

| Observation | Result |
| --- | ---: |
| Successful writer lifecycles | 80/80 |
| Exact original inputs/outputs after fresh-process reopen | 82/82 |
| Source/owner readiness gate after writer phase | 155,388 ms |
| Prepared sources / remaining preparation requests at that gate | 16/16 / 0 |
| Preparation retries at the gate | 307 |
| Fresh-reader complete original fields within30 seconds | 60/80 |
| Actual semantic / lexical deliveries | 9 / 51 |
| Complete captured inputs / admitted requests | 80/80 / 80/80 |
| Failure-inclusive hook minimum / median / maximum | 9,249 / 25,720 / 29,756 ms |
| Observed operation queue median / maximum | 20,240 / 26,282 ms |
| Observed operation work median / maximum | 661 / 6,871 ms |

Only67 operations have final timing observations; do not call those all-request
quantiles or p99. Twenty ordinary clients fail. The raw hook evidence and body
hashes are retained, including failure notifications. The original audit finds
no posted-but-unpublished observations, no pending saved sessions and no changed
original heads. These results fail the mixed-capacity gate and do not validate
real98% necessary evidence, sustained eighty-person use, token savings or quality.
Answering calls0; paid matched comparisons0/18.

The new readiness observer runs177 times, with median95 ms and maximum222 ms
per metadata sample. This is measurable diagnostic overhead. Do not use its
155-second gate as an uninstrumented performance comparison, and do not retain
that full scan in the next ordinary capacity measurement after diagnosis.

The inventory is decisive about one source of amplification: there are sixteen
index targets but256 synaptic targets, sixteen per physical owner. They contain
the owner-local target plus all fifteen foreign ingress sources. Source confirms
that ingress identity participates in `Journal.Target` registration and that
maintenance enumerates those target references. This is the Cartesian product
of physical source owners, not a missing parallel-writer implementation. It does
not by itself quantify how much of the155 seconds belongs to repeated replay.

The next correction is the preparation boundary, described in[next-project-scope.md](next-project-scope.md):
retain all independently durable original streams and exact captured source
cuts, but prepare each logical project/read scope once rather than treating
every owner/ingress pair as an independent replay destination. Prove and test
that the resulting facts, provenance and certification domain are preserved.
Separately trace the three workers' initial6.7–6.9-second work and2.6–2.8-second
ready phases and later queueing. The18 numerical observations take242–753 ms
each; assigning the whole initial cost to vector arithmetic is unsupported.

All native guards end with no owned survivors and no resource stop; maximum
related RSS is3,563,296 KiB, below the unchanged3,670,016 KiB stop/4 GiB ceiling.
The initial native build fails on an observer variable name, then succeeds.
The lexical summary classification is corrected from `completed` to the actual
`finished` status using the sealed raw events; no experiment is rerun to repair
that aggregate. Controller failures are retained.

Disk cleanup traces actual active link responses, resolved interfaces and native
producers before deleting43,316 unreferenced generated files:8,775,261,849 apparent
bytes. Two ended diagnostic executables release another236,618,416 bytes.
Sources, original DBs, models and active compilation inputs remain. The compact
retirement receipt retains counts, per-build totals and a digest of the removed
path manifest. No archive is created. After recording, the ended mixed fixture,
private caches and raw logs are deleted.
The ended fixture/log cleanup releases362,611,170 further apparent bytes, with
the protected originals unchanged and no owned processes left.
