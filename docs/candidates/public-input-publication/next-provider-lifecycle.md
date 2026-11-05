# Reuse preparation through the actual provider lifetime

The public capture experiment removes a repeat owner-book lookup, but its
ordinary running-hook gain is only2–48 ms. Native80 remains71/80 whole clients
(parent66/80), with nearly unchanged observed worker median527/529 ms and queues
around20–21 seconds. Do not repeat that experiment or add another cache solely
on the strength of its component result.

The actual running hook's Handoff trace is0 start,692 semantic nominations,
739 discovery,761 provenance/topology,1475 source hydration,1734 source focus,
2656 rendered. These are wall-clock phase boundaries, not CPU attribution.
Numerical receipts in that same hook report107/168 ms, in separate provider
PIDs55207/55601; they do not measure all startup, source restoration or Handoff.
The running operation takes2814 ms; frontend capture is only16 ms. The render
subprofile measures25 ms preparation and296 ms service/finish, so assigning the
whole922 ms after focus to the selector would also be wrong.

The source confirms a preparation-lifetime gap:

- `MiniLM.command` returns the native executable's `search-provider` command.
- `KeyedSearchClient.nominate` calls `SemanticMatcher.withProvider`, which starts
  a fresh child for each invocation and stops it afterward.
- `KeyedSearchProvider.handle` repins every source, restores every supplied
  window/lexical/numeric root and restores the owner view in that fresh process.
- `SemanticMatcher.nominateIndexed` also starts a provider for focus.
- `SearchProvider.encoder` is already a direct `Numerical.Client`. The earlier
  direct-numerical change removed a different adapter; it did not remove these
  search-provider lifetimes. Do not redo that old adapter experiment.

Next compare the same captured `KeyedProtocol.Request` through the existing
process and a direct typed call to the same provider handler, in alternating
native pairs. Keep the same original cuts, complete scopes, model/encoder,
thresholds/router and private query storage. Compare the complete checked
response, ranks, window evidence and coverage, not just top eight owners. Include
startup/restore time outside the provider's current numerical counters.

If direct execution removes substantial work, put the built-in provider's
question-independent prepared readers in the existing worker lifetime and borrow
independent traces/bitmap/private operation state. Separate the transport from
the response checker to avoid an import cycle, preserving the same validation
and absolute cancellation/deadline contract. Private query/usage and authority
capabilities must not enter the public cache. Keep arbitrary external-provider
handling only where it is actually configured; never silently run it as builtin.

Do not attribute all unexplained time to process startup. The714 ms hydration
and remaining post-focus work still need their existing phase/profile evidence.
Remove only measured repeated preparation; preserve complete certification and
all authorized projects. Recheck actual bodies and a contemporaneous native80
pair without changing worker/owner/queue/deadline bounds. Sustained mixed save/
prepare/query load and the full98%/30-second goal remain required afterward.
