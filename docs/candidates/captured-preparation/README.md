# A captured source can be skipped by latest-head preparation

Isolated work following [source-cues](../source-cues/README.md). The complete
80-person/eight-hour/98%/30-second goal and matched token/quality gate remain.
The ordinary runtime and previous lexical correction remain unchanged.

## Confirmed counterexample

The [native checker](../../../tools/research/CapturedPreparationChecks.lean)
creates one logical project with two independent original owners. Actual native
publication and ordinary warm prepare A0/B0. It publishes A1, captures a normal
turn at A1/B0, then publishes and warms A2. Before examining readiness, the
checker verifies the required `original A1` in the complete six-owner cut.

[Observed result](counterexample.json): A2 is ready, A1 is not, and the ordinary
worker refuses the captured turn with `source query inputs are pending
preparation`. An explicit warm of A1 then fails with `older source cannot
replace a later synaptic publication`. Original source heads stay unchanged.
This is a preparation-availability failure, not a measured hook body or proof
that the entire original database has been audited for corruption.

Another notification of the ordinary job would still pin latest. Removing
the forward-only check would instead mix mutable derived state. Neither is
the repair. The [replacement preparation contract](../../captured-preparation.md)
retains interests in exact source cuts and derives from checked prepared
ancestors without rolling back completed readers or original publications.

## Implemented foundation, not the full repair

The [PageMap candidate](candidate.patch) adds `withWriterFrom`: its logical
B-tree basis can be a retained head, while append/recovery use the current
physical published extent and the next physical revision. The existing
`withWriter` remains strict and retains its original reader/trace behavior.
The new operation reuses the existing region writer guard; this is not a
lock-free IO or CAS-removal claim. Other original owners do not acquire it.

The retained-head check verifies identity, authority and extent bounds. Cache
callers must separately prove original-source ancestry and complete coverage.
The operation is not yet connected to synapse, lexical, canonical, numerical
and owner preparation. It does not make A1 ready. The post-change
[ordinary-path regression](regression.json) deliberately still reproduces the
same skipped-cut failure; different fixture identities are not a controlled
performance comparison.

## Native and Lean checks

[Branch results](branch.json): a 137,511-byte basis receives a 10,639-byte delta
after a later physical publication. The branch contains the older rows and
its own edit, excluding later-only rows. The later root retains its own changes.
After a flushed but interrupted append, recovery preserves the entire already
published byte prefix. All four logical roots pass 256 row checks each, both
in the writer process and a [fresh process](restored.txt). Stale, foreign and
out-of-extent bases are rejected; a no-op leaves the physical tip unchanged.
These are component checks, not large-DB throughput or p99 measurements.

The [Lean laws](../../../tools/research/CapturedPreparationLaws.lean) compose
the existing append/recovery equalities using actual `HistoryReader` and
`PinnedBlob` types: both an older-basis blob and a later physical-tip blob keep
their exact bytes. They use only standard Lean axioms. [Output](laws.txt)
confirms the new API and both theorems. This is not a proof of native filesystem
semantics, concurrent ownership, cache-source ancestry or whole-hook completion.

[Resources](resources.json) keep the unchanged 3.5 GiB stop/4 GiB ceiling and
2 GiB disk floor. [Negative checks](negative-checks.json) retain the initial
checker parse error caused by a reserved Lean identifier. Models are uncalled,
token comparisons remain 0/18, and the candidate is not adopted.

The aggregate peak is 2,766,720 KiB across compilation and native/proof checks;
no aggregate guard trips or owned survivors remain. It is not the RSS of an
80-client workload or evidence of sustained preparation capacity.

[Cleanup](cleanup.json) deletes the three finished diagnostic DB/cache trees
and raw guard logs/settings (721,139 apparent bytes), with no archive.
The current helper and required build inputs remain for integration work.
[Protected original checks](protected-after.txt) pass after deletion. The
deleted fixture roots are historical evidence, not currently replayable inputs.

Next: connect source-specific interests, checked ancestor roots, derived branch
updates and ready-root publication through the normal worker. Re-run this
counterexample as an actual fulfilment test before combined sustained load.
