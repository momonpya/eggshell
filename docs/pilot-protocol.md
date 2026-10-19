# Small pilot protocol draft

Status on 2026-10-20: the subject is pinned, its upstream tests run, and three
chained task prompts/acceptance oracles are reference-checked. No model trial
or seed-memory acquisition has been performed. This is preparation for
stage 5 of [GOAL.md](../GOAL.md), not a frozen preregistration or a paper result.

## Verified subject readiness

The first candidate is [Pallets ItsDangerous](https://github.com/pallets/itsdangerous),
at commit `672971d66a2ef9f85151e53283113f33d642dabd`. Its signing, timestamp and
serialization modules provide related source areas with executable tests.
The [pinned project configuration](https://github.com/pallets/itsdangerous/blob/672971d66a2ef9f85151e53283113f33d642dabd/pyproject.toml)
declares pytest and freezegun as test dependencies. This subject does not reuse
the earlier AAMAS/LLVM dataset or its reported numbers.

Reproduce the subject preflight in a dedicated directory:

```sh
python3 tools/prepare_pilot_subject.py \
  --output /absolute/experiment/pilot \
  --python python3.12
```

The tool checks the exact origin/commit and a clean tree, creates a private
environment, resolves the platform-applicable test dependencies from the
subject's lock, and installs those exact versions. The build backend is fixed
by the resulting environment freeze before any model run. The tool preserves
installation logs, environment versions, every tracked-file hash and JUnit
results. It refuses to overwrite a completed subject manifest or reset an
existing subject with another origin, commit or local changes.
Use the captured environment freeze for matched trials; do not independently
resolve new dependencies or acquire new seeds for each comparison condition.

Observed preflight: Python 3.12.12 on macOS arm64; **297 tests, zero failures,
errors or skips**, and all 50 tracked-file hashes unchanged. Test execution
took 0.89 s; preparation and tests together took 5.44 s, aggregate descendant
peak 150,512 KiB under the 3,500,000 KiB guard. These timings describe one
readiness run, not a performance distribution. Generation-model calls: 0.

Local evidence is under
`/Users/ovm/.codex/experiments/eggshell/recommendation-certification-pilot-20261020/`:
`subject-manifest.json`, `preflight-audit.json`, `baseline.xml`, the full test
log, locked test requirements, environment freeze and process guard report.
An Eggshell seed DB and its warm/index receipts have not yet been created.

## Design to freeze before model trials

The pilot uses one repository and a related sequence of three maintenance
tasks: serialized-byte limits, bounded URL-safe inflation, and propagation
through timed/file/unsafe loading paths. The [fixed task material](pilot-tasks.md)
contains the prompts, chained starting snapshots, cumulative checks and
reference patches. The starts fail 13/2/75 new checks; references pass all
313/324/407 cumulative tests, including the original 297 at each stage. Fifteen
grader controls reject missing behavior, unbounded accumulation and grading
integrity failures. These are oracle-validation outcomes, not model results.
Any material change requires a new frozen suite and revalidation before
collecting model outcomes; old outputs remain immutable.

Keep the six conditions from the goal:

| Condition | Available prior context | Work omission authority |
| --- | --- | --- |
| Eggshell | Semantic recommendations and stored observations | Existing Exact-preserving certification and freshness checks |
| Fresh | No prior task context or Eggshell delivery | Requested tools execute normally |
| Previous answer pasted | Only the same recorded prior answer | Requested tools execute normally |
| Same-chat continuation | The preceding task's native conversation | Requested tools execute normally |
| Lexical-only Eggshell | Lexical DB recommendations and the same stored observations | The same certification and freshness checks |
| Similarity equality control | The same semantic nominations, with similarity promoted to equality | Isolated experimental control; retain all other guards |

The similarity control must have its own implementation and data root; it
cannot change the production kernel or a shared source DB. The exact condition
settings and absence of ambient memory/hooks in the three non-Eggshell
conditions must be checked before collecting outcomes.

Memory conditions use the same saved observation snapshot and source set,
with completed indexing and full warm coverage. Include the shared read-only
DB configuration with DB-identity-scoped private cache storage. A cold query
must not trigger whole-DB foreground embedding. Record actual semantic status,
scored-window coverage, delivered body, stdout digest and ACK for every hook;
lexical fallback must carry original DB body when semantic search is incomplete.

Use at least three equal repetitions for every planned cell. Fix the initial
use and history-available definitions for topics 1, 2 and 3, task order and
condition order before running. Hold source snapshots, questions, model,
reasoning settings and harness constant across matched cells. Reuse the same
saved seed instead of generating independent seeds to compare implementations.

Primary outcomes are incorrect reuse and acceptance-test success. Define the
reuse event and denominator, mechanical grading and any blind-human review
before collection. Preserve all trials, including failures, timeouts and
unknown ancestry. Missing provenance is never classified as zero congruence;
the incomplete delivery ancestry cannot yet supply the Phase 3 fraction.

Secondary accounting uses inclusive input plus output tokens, including cached
input and failed billed attempts. Do not add reasoning tokens twice. Record
seed acquisition separately and report its amortized cost. Character count,
packet size and this subject's readiness timings are not token-savings results.
Report each topic/history cell and every repetition, not only an overall sum.
The [offline usage auditor](pilot-usage.md) checks cumulative App Server usage
boundaries and separates seed/trial reported totals. It preserves failed and
unknown attempts, but cannot establish billing coverage for upstream failures.
Provider usage reconciliation is an open gate before the inclusive metric or
an adoption comparison can be reported.

Fix source changes, function renames, same-name/different-meaning cases and
injection-bearing observations before trials. The evaluator must run the
original verification files and fixed task checks; edits that weaken the
checks cannot count as quality success. Source/receipt hashes, changes,
commands and actual test results must be retained for audit.

## Remaining execution gates

The task material is reference-checked. Before the first model run, seal the runner
and condition implementations, model/reasoning settings, repetitions/order,
perturbations, token/time limits, seed snapshot and completed warm receipts.
Check the shared read-only configuration on that seed and fix the incorrect-reuse
event/denominator and receipt/trajectory adjudication. Acceptance tests alone
cannot identify incorrect memory reuse. These gates are still open; neither
the upstream preflight nor the reference task solutions satisfy them.
The offline usage auditor is prepared, while live capture, configuration
isolation and complete billed-attempt accounting still need implementation
and validation. No App Server model turn has been started for this preparation.

The observed public Eggshell `main` was
`51873167c11c447a0af67e73430b5ab6635b2a65` during readiness. Refresh and freeze
the latest public reference when the comparison is sealed. Development and
subject-readiness checks are not a public-main adoption comparison. Preserve
the workspace's stricter token/quality adoption rules; unchanged warm delivery
does not require redundant generation-model trials for cache ownership or
receipt-only edits. No runtime, README result or release adoption is implied
by this draft or its preflight.
