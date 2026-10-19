# Pilot command-environment preflight

The fresh-condition command environment is now checked against a real Codex
App Server without starting a thread or model turn. This is one part of the
[pilot runner preparation](pilot-protocol.md), not a completed six-condition
runner or a model result.

The [App Server protocol](https://learn.chatgpt.com/docs/app-server#protocol)
provides JSONL request/response transport. Its `command/exec` endpoint can run
commands without a model turn. The
[permission-profile documentation](https://learn.chatgpt.com/docs/permissions#file-access-limited-to-workspace)
describes restricting filesystem reads to workspace and selected runtime paths.
These are command boundaries; hosted tools, connectors and native agent
instruction loading require their own checks.

## Reproduce

Use the [frozen task suite](pilot-tasks.md) and the same subject environment:

```sh
python3 -B tools/pilot_preflight.py \
  --suite /absolute/pilot/task-suite \
  --output /absolute/pilot/new-preflight \
  --runtime-read-root /opt/homebrew \
  --runtime-read-root /Library/Developer/CommandLineTools
```

The two explicit runtime roots above describe this macOS host. List the actual
tool/dependency paths for another host and requalify it. The tool also grants
read access to the pinned Python environment and its base runtime. A supplied
runtime root cannot contain the experiment output or oracle suite. Record
the grants and resulting tool versions with the sealed experiment environment.

The tool creates a new private output directory, copies the first fixed task
start, and starts `codex-cli 0.145.0` with `--strict-config`. A task-specific
configuration root is selected through the child process's `CODEX_HOME`;
the parent environment is untouched. No user authentication file is copied.
Native memory generation/injection, plugins, hooks, skills, browser/computer
capabilities and web search are disabled. Agent tools are disabled explicitly
with `[agents] enabled = false`; feature flags alone did not remove their
namespace from actual requests in the [scripted native probe](pilot-hook-probe.md).
Nonempty foreign
configuration layers and legacy sandbox overrides fail qualification.

The command profile makes the workspace writable, its runtime dependencies
read-only, and other paths unreadable. Commands receive an explicit environment
and no network access. An outside listener is positively checked before a
sandboxed connection tests network denial.

The preflight checks all of the following with actual commands:

- Workspace read/write, import from the copied candidate source, and usable
  Git, rg and Python.
- Absence of a synthetic inherited environment secret.
- Runtime read access with write rejection.
- Read rejection for an outside canary, private configuration canary and actual
  frozen reference source, including symlink and parent-path access.
- Command network rejection, empty hook/skill/MCP discovery, and the effective
  configuration source.
- All original **297 upstream tests**, their exact frozen test identities,
  and unchanged hashes for all **50 source files**.

`pilot_server.py` permits only preflight metadata methods and `command/exec`.
It rejects `thread/start`, `turn/start`, resume, review and login methods before
sending them. It records unexpected generation events, bounds messages and
transcripts, applies read/write deadlines, and closes its process group and
reader. Fifteen synthetic transport/evidence controls exercise fragmentation, EOF,
malformed/oversized messages, response mismatch, server requests, unexpected
generation, stalled input/output, notification retention, output-versus-program
evidence, redaction and immutable evidence.

The output retains the configuration, source/tool/schema identifiers,
effective-policy projection, command results, JUnit, source hashes, exchange
log and process termination. Configuration-read responses are replaced in the
log by a hash of their canonical JSON to avoid copying unknown credentials
from configuration layers. This redacted **preflight log** is separate from
the eventual unmodified model-turn captures required by the
[usage auditor](pilot-usage.md). Output directories, including failed runs,
are never reused or overwritten.

## Observed evidence and remaining scope

Local records are under
`/Users/ovm/.codex/experiments/eggshell/pilot-isolation-20261020/`.
The official online configuration schema exposed flags absent from the
installed CLI; strict parsing rejected those initial probes. The retained
feature inventory and successful configuration use the installed CLI's
capabilities. An early runtime grant prevented Python execution, and another
omitted Apple's Git runtime. Those failed probes are retained alongside the
final successful qualification; they are not model outcomes.

The verified boundary covers the fresh-condition configuration and sandboxed
commands on this host. A model runner still needs to validate its actual
instruction sources, native file/tool access and denied escalation behavior.
The isolated Eggshell plugin now executes callbacks in the scripted probe.
The three memory conditions still need the same saved DB, completed warm/index
receipts and actual saved-body delivery.
Native continuation, previous-answer replay, similarity-equality control,
perturbations and reuse adjudication remain unfinished. Live usage semantics
and complete failed-request billing are also unverified. No experimental
model trial or seed acquisition has been started, and this preflight does not
establish token savings or qualify a runtime change for adoption.
