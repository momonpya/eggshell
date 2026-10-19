# Scripted native-hook integration

`tools/pilot_hook_probe.py` drives a real Codex App Server, its ordinary tool
router and the installed Eggshell command hooks with a **local deterministic
Responses fixture**. It is preparation for the [pilot](pilot-protocol.md).
No generative model, study participant or model-acquired seed is involved.

The fixture uses the [custom provider configuration](https://learn.chatgpt.com/docs/enterprise/connect-to-a-gateway#configure-the-provider)
and [Responses stream events](https://developers.openai.com/api/reference/resources/responses/streaming-events#response.completed).
It binds only to `127.0.0.1`, accepts no credentials and has no forwarding path.
Two fixed responses per condition request the prescribed native operations and
then acknowledge completion. The recognized `gpt-5.6-sol` slug supplies CLI
protocol metadata; every response is scripted locally. This does not select
the study's eventual model or reasoning settings.

## Reproduce

Use the [frozen task suite](pilot-tasks.md), candidate checkout and an existing
CPU MiniLM installation. For the observed macOS host:

```sh
python3 -B tools/pilot_hook_probe.py \
  --suite /absolute/pilot/task-suite \
  --source /absolute/eggshell-checkout \
  --minilm-assets /absolute/install/share/eggshell/minilm \
  --output /absolute/pilot/new-hook-probe \
  --runtime-read-root /opt/homebrew \
  --runtime-read-root /Library/Developer/CommandLineTools
```

Output must be new. The tool copies only the task's 50 declared source files;
it does not copy oracle checks, reference solutions or pytest caches into the
workspace. It copies MiniLM dependencies, model cache and their readiness marker
into a private prefix, then uses the standard candidate installer with private
Codex and Eggshell state roots. Original asset hashes are checked afterward.
Search embeddings can execute inside the actual hooks; the fixture makes no
generative-model requests.

Fresh and Eggshell use the same source path, files, prompt, scripted program,
provider endpoint and native tool catalog. Fresh discovers and runs no hooks.
Eggshell enables only the isolated installed command plugin. Before recording
trust, the tool checks the hook event set and commands, canonical hook JSON
against the repository source, cached launchers/manifest against the installed
payload, and installed executable against the selected candidate. It records
the reviewed hook hashes in that private configuration and checks the resulting
trusted status. No hook-trust bypass is used.

The plugin fixture declares a read-only prior DB path that is absent. Thus it
tests connection and callback processing, **not saved DB body delivery**.

## Observed checks

The real native command tool reads the copied serializer and prints its SHA-256,
then attempts an outside-canary read. The native edit tool creates an allowed
workspace canary and attempts an outside edit. Both conditions must deliver the
same actual terminal result to their second fixture request; the allowed edit
must exist and the outside canary must be unchanged. The terminal checker reads
only structured tool outputs. Strings in the scripted program or earlier
messages do not constitute evidence that a command executed.

Eggshell's SessionStart, UserPromptSubmit, PreToolUse, PostToolUse and Stop
callbacks completed; SessionEnd was also recorded during shutdown. Native
receipts retain actual stdout bytes and SHA-256, publication completion and
deadline checks, and available semantic-search traces. Default client RPCs
remain restricted; only the scripted client enables the required thread/turn
methods. Notifications received before an RPC response remain available to
completion checks.

The actual request catalog initially retained the collaboration namespace even
with multi-agent feature flags disabled. The explicit `[agents] enabled = false`
setting removed it. Both final condition catalogs match and contain no exposed
agent namespace. No delegation tool was called at any point.

Local final evidence is in
`/Users/ovm/.codex/experiments/eggshell/pilot-hook-connection-20261020/qualified-final/`:
helper/runtime fingerprints, copied-asset manifest, installation and trust
records, all four HTTP request bodies, RPC exchanges, tool results, and native
stdout/search receipts. The two scripted turns passed with 50 source hashes
unchanged. The observed run took **13.71 s**, aggregate sampled peak
**1,311,600 KiB**, with the 3,500,000 KiB guard untriggered.

One PreToolUse search in this empty-DB fixture timed out at 4,503 ms, emitted an
incomplete notice and delivered no saved body. This is retained as a timeout;
it is not counted as successful memory delivery or warm-DB performance. A
previous construction run had the same timeout. Earlier failed construction
checks, including a byte-versus-JSON whitespace mismatch and accidentally
searching the program text instead of its output, are retained. Fifteen
transport/evidence controls cover the corrected behavior. These are fixture
validation outcomes, not study results or a latency distribution.

The existing command-only preflight was rerun after disabling agents: the exact
original 297-test set still passes, with all 50 source hashes unchanged.

## Remaining pilot gates

The [subsequent memory fixture](pilot-memory-probe.md) now checks scripted native
save/warm/body delivery, including OS-protected shared DBs and private caches.
Its observations are separate from the study seed. The [history probe](pilot-history-probe.md)
also checks pasted-answer and live native continuation. The similarity control,
complete task runner, common model-acquired seed/history definitions and that
seed's completed warm/index receipts still need implementation and sealing. Native image/file surfaces
beyond the exercised command/edit paths have not been qualified. Real model
choice, repetitions, perturbations, token/time limits, wrong-reuse adjudication,
live usage semantics and failed-request billing remain open. Scripted requests,
their missing/synthetic usage and test-only observations must not enter the
model dataset or seed-cost calculation. The scripted RPC log has no seed/trial
attempt labels and is not an input for the model usage auditor.

The original deferred `hook output missing` investigation remains deferred.
This fixture does not establish a cause or resolution for it. Production
Eggshell source/executables are unchanged by this runner preparation; no new
warm latency or generation-token adoption comparison is claimed.
