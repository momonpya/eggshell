# Native warm-DB similarity-control connection

`tools/pilot_similarity_probe.py` connects the [isolated control](pilot-similarity-control.md)
to the real installed plugin, CPU embeddings and Codex App Server. Three fixed
responses consume the same saved observation graph, source workspace and
question: ordinary semantic retrieval, the semantic-equality control, and the
same control executable with numerical search disabled.

This is a scripted connection fixture. The saved graph comes from the
[scripted observation probe](pilot-memory-probe.md), not a model-acquired study
seed. No generative model, model-chosen tool omission, quality judgment, token
comparison or adoption decision is involved.

## Reproduce

Use the ordinary hook qualification, saved-memory fixture, frozen task suite,
and separate control build:

```sh
python3 -B tools/pilot_similarity_probe.py \
  --ordinary /absolute/pilot/qualified-hook-probe \
  --memory /absolute/pilot/qualified-memory-probe \
  --control /absolute/pilot/qualified-control-build \
  --source /absolute/ordinary-eggshell-checkout \
  --suite /absolute/pilot/task-suite \
  --output /absolute/pilot/new-native-control-probe \
  --installed-control /absolute/private-installed-control-prefix \
  --runtime-read-root /opt/homebrew \
  --runtime-read-root /Library/Developer/CommandLineTools
python3 -B tools/check_pilot_similarity.py
```

Output must be new. Without `--installed-control`, the tool clones embedding
assets to a new private prefix and runs the control's standard installer with
private Codex/Eggshell roots. With it, the executable must match the qualified
control and embedding-asset hashes must match the ordinary prefix. Installation
is separate from consumer roots; a study runner must freeze and reuse its
qualified installation rather than silently reinstall for individual cells.

The tool verifies the control's declared source overlay/helper/executable hashes,
the original binary, suite, 50 source hashes and saved graph bytes. Active index
tickets are forbidden. It copies that same DB, including its warm cache, with
bytes and metadata preserved, then protects every file/directory with macOS
immutable flags. Both semantic cases must request zero warm windows, score all
five saved windows from cache, and perform no original-source embedding.

Each condition uses a new native thread and private Codex/data roots. Installed
hooks are reviewed against source before recording trust. All native catalogs
must match and expose no agent namespace. Consumers perform no tool call; the
first HTTP request must contain the exact published hook context and original
source body. Native stdout SHA-256, byte count, complete publication, deadline
and ACK are checked. Numerical search is forbidden in the lexical control.

For the semantic control, the private pre-promotion journal must contain new
identity nominations. Each distinct compared pair must occur as an actual
run-local generator in the captured selection snapshot. The native
`inspect-equality` command must replay that snapshot. Nomination alone, unrelated
or persistent edges, and identity already true before promotion do not qualify.
Four counterfactual controls check this evidence boundary. The ordinary and
lexical cases must remain advisory for this fixed fixture.

## Observed result and retained failure

Final evidence is under
`/Users/ovm/.codex/experiments/eggshell/pilot-similarity-native-20261020/qualified-final/`.
All three consumers used DB identity
`aec3fc5fd4075583327e1bc61c3f724adffa7e749fcef16fbcbba3dabbd533a3`
and the same source workspace/question. Both semantic discoveries had 5/5
source-cache hits, all five windows scored, and zero original-source encoding.

| Condition | Semantic status | Run-local unions | Completed deliveries |
| --- | --- | --- | --- |
| Ordinary | Completed | 1 | 0 |
| Similarity equality | Completed | 3 | 1 |
| Control executable, lexical only | Not requested | 1 | 0 |

The two experimental nomination pairs occur in actual generators. The control's
completed owner was visible in the delivered context; this does not establish
that a model omitted a tool or that reuse was wrong. Native analysis retains
`deliveryAncestry = untracked` and partial provenance. Successful replay does
not close that gap or provide the ordinary Phase 3 congruence fraction.

All three published bodies reached their first requests and were acknowledged.
The protected DB, original saved DB, original runtime prefix, installed control
and all 50 source files remained unchanged. Original DB flags were restored.
Three scripted turns/three local requests passed; all four evidence controls
passed. The final fixture took 9.36 s, aggregate sampled peak 1,337,648 KiB under
the 3,500,000 KiB guard.

The first native semantic attempt on a newly installed private control prefix
timed out and remains in `construction-2/`. Discovery completed its five-window
scoring in 3,926 ms, including 3,542,615 us of encoder initialization; the next
focus stage and surrounding work exhausted the unchanged 4,500 ms semantic
budget. The hook delivered the lexical DB body. Subsequent connection checks
reused that same installation and completed semantic search. The timeout is
retained, not replaced by a successful latency sample. These runs do not form
a latency distribution or prove the new-installation startup gate. An earlier
copy check failed because directory modification times were not preserved;
that construction output is also retained.

All six planned context paths now have scripted connection evidence. The full
task runner, actual common study seed and repeatable native history, fixed model,
settings/order/repetitions/perturbations/limits, incorrect-reuse adjudication,
complete billed-attempt accounting and remaining provenance work still need
completion. Synthetic requests/observations cannot enter the model dataset or
seed costs. The original deferred `hook output missing` investigation stays deferred.
