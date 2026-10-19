# Scripted saved-observation transport

`tools/pilot_memory_probe.py` extends the [native-hook qualification](pilot-hook-probe.md)
with a saved DB, completed warm coverage and independent consumer chats. It uses
the real Codex App Server, command tool, Eggshell plugin and CPU embedding runtime.
Responses come from a local deterministic fixture. This checks the study runner's
memory connection; it does not acquire a study seed or evaluate model behavior.

## Reproduce

Use a successful native-hook qualification and the [frozen task suite](pilot-tasks.md):

```sh
python3 -B tools/pilot_memory_probe.py \
  --qualification /absolute/pilot/qualified-hook-probe \
  --suite /absolute/pilot/task-suite \
  --source /absolute/eggshell-checkout \
  --output /absolute/pilot/new-memory-probe \
  --runtime-read-root /opt/homebrew \
  --runtime-read-root /Library/Developer/CommandLineTools
python3 -B tools/check_pilot_memory.py
```

The observed host uses macOS and Codex CLI 0.145.0. The qualification must match
the current candidate executable. Its private installed prefix is reused without
installation or mutation; its full file-hash map must remain unchanged. Each
case gets private Codex, Eggshell and temporary roots. Only the task's 50 declared
source files enter the workspace. No oracle or reference solution is copied there.
Output must be new; failures and their evidence are retained.

## Saved body and isolation checks

The writer's scripted native command reads `Serializer.load_payload` from the
original subject. The real hooks observe that tool result; `egg keep` commits it
before the writer closes. The controller stops the daemon, inspects the committed
graph, completes `egg warm`, and requires zero remaining index tickets before
consumer turns. It creates a byte-identical graph-only copy with the same DB
identity, excluding the derived cache. These are test-only observations.

Both DBs sit outside the agent's allowed workspace. During all consumer cases,
every DB file and directory has macOS `UF_IMMUTABLE` protection. Actual attempted
writes must fail. Before/after snapshots compare bytes, size, permissions, flags
and modification times; original flags are restored even on an exception. DB
symlinks are rejected before any flags change. This exercises OS-rejected writes
and a private profile, rather than relying only on a profile declaration.

| Consumer | Cache preparation | Required first-request evidence |
| --- | --- | --- |
| Fresh | No plugin or hooks | No saved source body |
| Semantic, primary cache | Already warm inside the protected DB; zero windows requested | Exact published hook context and all saved discovery windows scored |
| Semantic, private cache | Graph-only DB; warm missing windows into private `read-cache/<DB identity>/` | The same source body and full discovery coverage |
| Lexical only | Numerical search disabled | Original saved body; no numerical search receipts |

Each consumer has a new native thread and receives one fixed final response,
with no tool call. Its first HTTP request must contain the exact published
`additionalContext`, including `EGGSHELL PRIOR WORK` and the original source line
`return use_serializer.loads(payload)`. That line is absent from the question
and fixed answer. Inherited tool calls or outputs cannot substitute for DB
delivery. The native catalogs must match the writer and expose no agent namespace.

For each memory consumer, native receipts must confirm stdout bytes/SHA-256,
complete publication within the deadline and the actual search route. Semantic
discovery must score every saved window with only source-cache hits and zero
source-encoding time. Query-dependent focus windows are recorded separately:
their new embeddings are not reported as original-DB cache misses. Query vectors
remain in private storage and have no plaintext `text` field. The shared DB
snapshots and all 50 source hashes must remain unchanged.

Eight counterfactual controls reject missing context, marker-only evidence,
incomplete notices, strings in tool arguments, native history and hidden prior
body in fresh. They also check actual write rejection, flag restoration after an
injected failure, and symlink rejection without changing an external target.

## Observed qualification

Final evidence is under
`/Users/ovm/.codex/experiments/eggshell/pilot-memory-20261020/qualified-final/`.
The manifest seals the helper code, candidate, suite and source hashes. Saved
snapshot/warm records, all six local HTTP requests, native RPC/hook receipts,
protected DB snapshots and each case's results are retained.

The run passed: **five saved windows, five scripted turns, six local requests**.
Both semantic consumers completed discovery with 5/5 cache hits, all five windows
scored and no original-source embedding. Primary-cache warm requested zero
windows; the same graph without derived files requested five in private storage.
Both semantic cases and lexical-only delivered the original body in their first
request; fresh did not. Shared DBs, runtime prefix and source files were unchanged,
and DB flags were restored. All eight controls passed with no skips on this host.

The complete fixture took 10.25 s, aggregate sampled peak 1,260,752 KiB under
the 3,500,000 KiB guard. This is one connection qualification, not a latency
distribution or a comparison between implementations. It does not replace the
fixed warm-DB latency study. No generation-model call, study-seed acquisition,
quality assessment, token-savings result or adoption decision is included.

## Remaining pilot work

This closes the scripted saved-body transport check. The [pilot protocol](pilot-protocol.md)
still needs the actual common seed/history definition, its acquisition and warm
receipts, the similarity control and complete runner, model/reasoning settings,
balanced repetitions, perturbations and limits, incorrect-reuse adjudication,
and complete billed-attempt accounting. Synthetic observations and requests
must not enter study outcomes or seed costs. The original user-deferred
`hook output missing` investigation remains deferred.
The [history probe](pilot-history-probe.md) separately qualifies fresh,
pasted-answer and live same-chat context transport with fixed responses;
repeated-history restoration remains open.
