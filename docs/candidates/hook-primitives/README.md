# Primitive import separation: no footprint benefit

This isolated candidate is rejected. It is not integrated into the backend,
installed, or used for another mixed-client growth run. The fixed parent is
the [small hook supervisor](../hook-command/README.md), whose mixed two-DB
workload still fails its fourth additional wave at the unchanged memory guard.

The client previously imported storage and BLAKE3 for receipt IDs and SHA-256's
initial words and hexadecimal encoding. The [candidate patch](candidate.patch)
separates hexadecimal encoding and receipt-ID primitives, gives SHA-256 its
own identical initial words, and narrows the process helper's import. It does
not change search, work graphs, e-classes, synapses, ranking, budgets or workers.

The [kernel audit](proofs.json) checks the former hexadecimal and SHA-256
definitions, receipt-ID validation and generation, and existing reply laws.
It uses standard axioms only. This is refinement against the former code,
not a cryptographic correctness proof. The supervisor's transitive action
contains 815 declarations without storage, the other digest algorithm, backend
or model actions. The [actual native closure](command-native.json) and
[module list](command-modules.json) contain seven consistent objects, with no
Receipt, FileSystem, Paths, Blake3 or backend import.

The controlled experiment compares the old and new small clients against
the **same parent backend**. It uses native observation, ABBA order and the
ordinary installation's unset `LEAN_NUM_THREADS`, with stdin held and owned
processes sampled from 400–1,200 ms. The minimum saving was fixed at 8,192 KiB
per paired observation before running it. See [plan](probe-plan.json),
[raw samples](footprint.json) and [result](result.json).

| Observation | Client | Pair peak RSS | Exit time |
| --- | --- | --- | --- |
| A | Parent | 92,992 KiB | 2.028 s |
| B | Candidate | 92,976 KiB | 2.910 s |
| B | Candidate | 93,008 KiB | 2.016 s |
| A | Parent | 92,976 KiB | 1.999 s |

The paired savings are **16 / −32 KiB**, failing the predeclared 8 MiB gate.
Removing imports did not establish a resident-memory improvement. No full
backend rebuild or identical 14-client retry follows. These blocked-input
component measurements are not query, delivery, token or throughput results.
All four observations exit with empty stderr; the resource guard finishes
normally and owns no surviving processes. Client/probe build and probe guard
records are retained alongside the result.

This older observer did not bind sampling to backend ingress. The later
[runtime-stamp experiment](../runtime-stamp/README.md) finds a cold-start phase
error in its own first comparison and adds PID-bound ingress sampling. The
old primitive-import observations are retained without a causal or
initialized-memory claim; they still establish no adoption benefit.

Ended candidate sources, binaries, interfaces and synthetic receipt caches
were removed: [560 entries / 218,495,258 logical bytes](retired.json), without
an archive. The parent backend and client hashes remain unchanged. The
[parent backend after cleanup](product-after-cleanup.json) still has 346
consistent native objects. The candidate patch, proof source, controller and
compact evidence remain; the deleted candidate is not a current runtime.

The latest mixed-client evidence remains the parent's completed 52 semantic
queries and 788/788 visible required-evidence appearances, with the fourth
growth wave failed. This candidate adds no mixed-query success. Sustained
growth, general 98% delivery, accepted LLVM seed and both topic passes,
inclusive token improvement, quality, NAS and 80-user operation remain
unfinished. Answering-model calls and adopted changes are zero.
