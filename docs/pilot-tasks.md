# Fixed pilot task material

The three maintenance requests in [tasks.json](../benchmarks/itsdangerous/tasks.json)
extend related loading paths in the pinned ItsDangerous subject. Each starts
from the upstream snapshot plus the preceding reference changes. Starting
source is fixed across conditions; one condition's model-produced patch must
not silently become another condition's input.

The task prompts, cumulative acceptance checks and reference patches are
research material. Reference implementations are not model trial outcomes.
The whole study remains a [protocol draft](pilot-protocol.md).

| Task | Request | Starting-state failures | Reference result |
| --- | --- | --- | --- |
| `payload-limit` | Serialized-byte budget before text/binary deserialization; preserve authentication, fallback signers and default overrides | 13 / 313 | 313 / 313 pass |
| `compressed-limit` | Bound URL-safe inflation itself, not merely reject after decoding | 2 / 324 | 324 / 324 pass |
| `timed-unsafe-limit` | Carry the budget through timed, file and bad-signature recovery paths; retain expiry ordering and timestamp results | 75 / 407 | 407 / 407 pass |

Totals are cumulative and include the original **297 upstream tests** at
every stage. Starting-state failures occur only in the new acceptance checks;
there are no collection errors, upstream failures or skips. These counts
establish that the requests distinguish missing behavior from checked reference
behavior. They are not success rates for a model or memory implementation.

The third task's name refers to ItsDangerous's `loads_unsafe` API. It is separate
from the study's isolated similarity-equality experimental condition.
An authenticated oversized payload raises `BadPayload`; recovering an oversized
invalid/expired payload returns `(False, None)`. The task does not mislabel an
authenticated signature as invalid merely because decoding was refused.

## Reproduce the checks

First prepare the subject using [the subject tool](../tools/prepare_pilot_subject.py).
Then freeze and check the three task snapshots:

```sh
python3 tools/pilot_tasks.py prepare \
  --subject-root /absolute/experiment/pilot \
  --output /absolute/experiment/task-suite

python3 tools/check_pilot_tasks.py \
  --suite /absolute/experiment/task-suite \
  --output /absolute/experiment/grader-controls
```

The suite stores the exact task assets, starting/reference file hashes, Python
identity, environment-freeze digest, grader code, test identities and before/after
JUnit logs. Old outputs are preserved rather than overwritten. The fixed
starting source must match the seed's recorded read bytes before actual trials;
replacing a prior model patch with reference code cannot make its old observations
current.

Grade a candidate with the frozen grader. Keep output outside the candidate
and the frozen suite:

```sh
python3 /absolute/experiment/task-suite/grader.py grade \
  --suite /absolute/experiment/task-suite \
  --task compressed-limit \
  --candidate /absolute/experiment/candidate \
  --output /absolute/experiment/grade
```

Only Python source changes inside `src/itsdangerous/` are admitted. Evaluation
reconstructs the fixed starting files and overlays those source changes, uses
original tests and the frozen acceptance checks, and verifies that the actual
candidate package was imported. Passing requires the exact expected test set,
no errors/failures/skips, unchanged protected files, unchanged starting snapshot
and unchanged task material after execution. The grader invokes no model;
`grader_model_calls` is not the evaluated trial's token or billing record.

## Validate the evaluator

Controls check references and unchanged starts, then deliberately disable the
base byte limit, perform unbounded inflation followed by a size check, split
over-budget output across bounded calls, or omit the recovery-path budget.
Those incorrect candidates must fail. The inflation probes observe both
positive per-call limits and the total bytes returned across all calls; a
bounded call followed by unchecked accumulation cannot pass.

The Python API specifies that zero `max_length` is unlimited and that a flush
length initializes a buffer rather than imposing an output cap. The tests
therefore distinguish those operations from bounded inflation and check stream
completion. See the [official zlib API](https://docs.python.org/3.12/library/zlib.html).
This byte budget concerns serialized/decompressed payload size, not a total
wire-input or execution-time bound.

Additional controls reject protected configuration edits, changes to frozen
checks during import even when all tests pass, output paths overlapping inputs,
and accidentally importing the preflight's installed editable package. These
integrity checks do not constitute an execution sandbox. Runner isolation and
artifact/trajectory auditing remain required before running model-produced code.

This evaluator measures task acceptance. Test failure alone is not evidence of
incorrect memory reuse, and passing tests do not establish safe reuse. Reuse
events/denominators and receipt-based adjudication still need to be fixed before
the primary incorrect-reuse rate can be reported. Unknown ancestry stays unknown.

The subject is [Pallets ItsDangerous](https://github.com/pallets/itsdangerous/tree/672971d66a2ef9f85151e53283113f33d642dabd).
Reference patches derive from that pinned source; its copyright and BSD terms
are preserved in [LICENSE.txt](../benchmarks/itsdangerous/LICENSE.txt).

## Observed validation, 2026-10-20

The final reference precheck took 3.30 s, aggregate descendant peak 77,408 KiB;
the 15-control evaluator check took 6.31 s, peak 98,240 KiB. Both were serial
under the 3,500,000 KiB guard. All references passed their exact expected test
sets; unchanged starts failed their new acceptance checks. Deliberately
disabled limits failed six checks, unbounded post-check inflation failed two,
split bounded calls with over-budget accumulated output failed two, and
uncapped unsafe recovery failed twelve.

The integrity control also rejected a candidate which changed frozen checks
during import despite all 407 tests passing. Protected configuration edits,
both input/output overlaps and the foreign editable import were rejected.
Those are expected negative controls, not failed model trials.

An earlier construction oracle checked per-call bounds but not accumulated
output. The same split-call candidate passed all 324 tests there and failed
two in the corrected frozen material. That matched counterexample is retained;
no model outcome was collected while refining the checks. All construction
snapshots/logs remain under
`/Users/ovm/.codex/experiments/eggshell/pilot-tasks-20261020/`.
The final material is `oracles-3/`, its controls are `grader-controls-4/`, and
the before/after counterexample is `chunked-gap-audit.json`.

Model trials, seed acquisition and token/incorrect-reuse measurements remain
unexecuted. Production Eggshell source and executables are unchanged by this
task-material work.
