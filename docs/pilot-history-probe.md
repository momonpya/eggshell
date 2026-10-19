# Native history and pasted-answer context

`tools/pilot_history_probe.py` checks the three non-Eggshell context conditions
through real Codex App Server turns. A local scripted provider requests one
native source read and returns a fixed prior answer. Consumer responses are
fixed acknowledgements. There is no generative model or study-seed acquisition.

## Reproduce

Use the [frozen task suite](pilot-tasks.md) on the qualified macOS host:

```sh
python3 -B tools/pilot_history_probe.py \
  --suite /absolute/pilot/task-suite \
  --output /absolute/pilot/new-history-probe \
  --runtime-read-root /opt/homebrew \
  --runtime-read-root /Library/Developer/CommandLineTools
python3 -B tools/check_pilot_context.py
```

Output must be new; old evidence is retained. The fixture requires CLI 0.145.0,
whose locally generated `ThreadReadParams` / `ThreadReadResponse` schemas were
inspected before implementation. It records the launcher, helper, source and
suite hashes. The recognized model slug supplies protocol metadata for the
local provider; it does not select the study's eventual model or reasoning.

## Context contract

All consumers use the same workspace, 50 fixed source files, current question,
native tool catalog and command permission profile. They run with Eggshell
hooks, native memory, skills, external tools and agent tools disabled. New-thread
conditions receive separate private Codex and temporary roots. No oracle or
reference solution enters the workspace.

The prior turn actually reads the original serializer. Its second HTTP request
must contain a linked native command result with exit code zero and output
exactly equal to the selected source bytes. Program strings, truncated results,
wrong call IDs and failed commands do not qualify. After completion, `thread/read`
with loaded turns supplies the unique recorded final answer. Pasting uses that
recorded answer, rather than an independent reconstruction of the planned response.

| Consumer | Required actual request contents |
| --- | --- |
| Fresh | Current question, no prior answer or native history |
| Previous answer pasted | A new user message containing JSON fields `previous_answer` and `current_task`; the answer is preserved exactly, with no native prior turns or tool observations |
| Same-chat continuation | Exact prior request history, followed by its recorded assistant final answer and the current user question |

`tools/pilot_context.py` builds the pasted input and audits the received request.
The continuation check compares the entire native prefix, including the prior
question and tool-call/result pair. Moving old text into a user message cannot
substitute for native history. The new-thread checks reject inherited tool or
assistant items and extra prior user context. The original source line is also
required in continuation and forbidden in fresh/pasted inputs; it does not occur
in the fixture's answer or current question.

The active continuation uses the original native thread with two turns. Fresh
and pasted-answer consumers have distinct IDs and one turn each. This qualifies
continuation in a live App Server. The [seed checkpoint probe](pilot-seed.md)
now restores the same frozen scripted history into independent repetitions.
Actual study-seed provenance and forked-usage accounting remain open.

Twelve counterfactual controls cover lost/changed observations, pasted history
masquerading as continuation, forged assistant roles, prior context in fresh,
tool history in pasted input, Unicode/quotes/newlines in recorded answers,
unloaded or ambiguous answers, and unlinked/failed/truncated command results.

## Observed qualification

Final evidence is under
`/Users/ovm/.codex/experiments/eggshell/pilot-history-20261020/qualified-final/`:
manifest, all five local HTTP requests, native RPC logs, prior/consumer loaded
threads and per-condition context digests. Four scripted turns across three
native threads passed, with all 50 source hashes unchanged and identical native
catalogs containing no agent namespace. All twelve controls passed.

The final fixture took 1.37 s, aggregate sampled peak 143,472 KiB under the
3,500,000 KiB guard. This is a connection qualification, not a model comparison,
latency distribution, quality result, token-savings result or adoption decision.
Its missing/synthetic usage cannot enter study accounting.

Together with the [saved-DB probe](pilot-memory-probe.md), five planned context
paths have scripted transport evidence. The [similarity-equality control](pilot-similarity-control.md)
has a separate built implementation and [native warm-DB connection evidence](pilot-similarity-native.md).
The full task runner, common acquired seed/history, repeated-history restoration,
model/reasoning settings, repetitions/order, perturbations/limits, incorrect-reuse
adjudication and complete billed-attempt accounting remain open in the
[pilot protocol](pilot-protocol.md). The original deferred `hook output missing`
investigation remains deferred. Eggshell runtime code and executables are unchanged.
