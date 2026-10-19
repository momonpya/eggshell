# DB-owned numerical cache candidate

Unadopted candidate. The implementation order is in [GOAL.md](../GOAL.md).

A page DB already has a random `head.identity` that survives ordinary
publications. Its revision and page-root reference change independently.
Rebuildable numerical data lives inside the owning DB:

```
project.egg/
  head
  writer
  ... page data ...
  derived/<head.identity>/
    semantic/vectors/<model-key>-<window-key>.json
    indexes/<local-provider-key>/<ticket-key>.json
    index.guard
```

There is no chat ID in this location. Moving or copying the whole DB carries
the cache; deleting the DB deletes its cache. Two independently created DBs
remain distinct even when they use the same graph authority. A copy retains
its DB identity and cached bytes, at its new directory.

Pinned search documents carry their DB directory and incarnation through ordinary,
federated and focused indexed requests. One numerical provider still scores
the complete requested corpus and ranks it globally. It does not compute
independent top-k results per DB. The original bounded repair callback retains
control of source windows; a cache locator supplies no equality or completion
authority. Records still validate the exact model and original window bytes.

The independent index worker sends the owning DB's cache in its index request.
The default provider command no longer selects a chat-owned vector directory.
Queries use the first durable document's cache; documents without a durable
DB owner use process scratch. Model weights and the numerical runtime remain
shared installation resources. The default command's trace also lives in
installation data, so its provider identity does not change with the chat.

Vector publication uses an existing parent directory and secure atomic-file
publication. Preparing its sidecar pins the DB incarnation and creates one
child at a time. An in-flight write cannot recreate deleted DB ancestors.
Cached vectors remain optional hints, not graph facts.

Index tickets contain only DB identity, provider identity, graph authority and
published owner keys. The original observation body stays in the graph.
Executables and absolute destinations belong to a private installation registry
at `index-targets/`, outside the DB. Imported DB metadata cannot select a command.
The current session's configured DBs register their new locations, so a daemon
can recover moved or copied tickets without the originating chat directory.
The provider lane uses the exact local command identity; a different installation
or provider configuration needs warming with its own configured provider.

Drain admission is installation-wide and a non-waiting DB claim prevents duplicate
index work. The graph writer and session state lock are independent. Failed
acknowledgements and expired index workers retain their tickets; only exact
batch acknowledgement consumes them. Invalid metadata is renamed with a
`.corrupt-` suffix and retained outside active draining, so later valid work
can proceed. Missing or replaced DBs retire discovery
records. Their sidecars remain owned by the DB directory.

The isolated candidate adds explicit warming and read-only coverage:

```
egg doctor
egg warm
egg warm work
egg warm /absolute/path/imported.egg
```

`warm` uses the configured profile's DBs, a configured DB name, or a DB path.
A path also works without a project config when the default numerical runtime
is installed. `EGGSHELL_CONFIG` selects an explicit configuration as for the
other CLI commands. Warming does not need a chat ID or modify chat state.

The live DB window-key set is compared with records valid for the exact model
and window digest. Query vectors and retired windows are excluded from coverage.
Doctor reports valid, missing and invalid counts without reading DB source
bodies, creating sidecars or starting inference. Unsupported custom provider
formats and unavailable providers are reported explicitly.

Warm pins the source publication, reads only missing original windows and sends
at most 32 in each exact-window request. A single provider serves all batches;
windows are not split into overlapping windows again. Every batch requires an
exact acknowledgement, followed by actual cache validation. Index and warm
share a DB claim. Valid records survive partial failure. A fully warm repeat
does not start the provider or rewrite records. Output identifies the pinned DB
revision, before/after coverage, requested count, batch count and elapsed time.

The isolated candidate gives semantic discovery the first search window:
at most 1,500 ms and at most half the remaining caller deadline. On an incomplete
reply, the requesting worker is retired before a DB request uses the remaining
deadline. Turn/epoch, source checks, delivery claims and packet limits still
apply. The fallback may read an existing validated demand memo, but does not
publish a new memo or derived DB revision after cancelling the configured search.
Semantic completion and the route used for body delivery are separate
observations. A status notice never counts as an original source body.

The DB request first preserves any ordinary Work result, including an empty
body carrying source-refresh metadata. If there is no such result, keyword
postings nominate the highest eight positive owners as advisory evidence.
Weights use the complete population and document frequencies; nonmatching
rows are omitted from scoring without changing their contribution to those
counts. Keyword nominations cannot authorize native operation reuse. A native
probe alone does not create a new advisory question.

Ordinary durable-source repair pulls are rejected before original-window reads.
A cold first batch is detected before query inference. Unpublished windows and
derived source-focus views have a cumulative budget of 32 repaired window
positions per provider request; already bounded windows are never split again. This preserves
the complete ranked corpus rather than silently scoring only cached documents.

Daemons discover configured DBs through the private installation registry.
Missing or invalid warm checkpoints schedule explicit missing-window warm in
the independent index worker. The DB-owned checkpoint records database/provider
identity, insertion frontier and live candidate count; a publication revision is
diagnostic. Query memo writes alone do not reschedule a full warm. An incomplete
foreground request registers its DBs and invalidates their checkpoints using
only metadata. Recovery remains possible after deleting the originating chat.

Acknowledged offers retain semantic status, configured/keyword route, semantic
and keyword duration, metadata-queue duration (`warmMs`) and warm-target count.
These are partial diagnostics: coverage is not per-run cache-hit telemetry,
and retaining the last acknowledged trace is not a receipt for every run.
DB-size scaling, all-run measurements, actual app ingestion, inclusive model
token comparisons and the paper's complete proof/experiment requirements remain
unfinished. No quality or language-model token claim follows from these changes.
