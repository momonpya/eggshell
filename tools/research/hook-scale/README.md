# Isolated native hook scale work

These Lean files are review inputs, with their original relative paths under
this directory. They are not an alternative installed product. Reconstruct
the native-observation parent, then prepared-domain and hook-scale patches
before placing them at those original paths. Apply the final hook-scale delta
with `git apply --unidiff-zero`; its context-free hunks avoid treating patch
context prefixes as source whitespace. The review manifest pins the
actual source, executable, link inputs, settings, guards and native receipts.

- `HookScaleFixture` generates and checks original 10k/50k publications using
  existing RetrievalScale content and bounded publication batches.
- `HookScaleRun` exercises real native stdout/publication/history and owned
  manager exit. A fresh nonce and current receipt classify first/continued
  requests. Empty acknowledged continuation and incomplete search differ.
- `HookLatencyAudit` streams saved caller notifications, pairs scoped hook
  starts/terminals and reports event and per-turn cumulative handler cost.
  It never runs a hook or model; overlapping durations are not turn wall time.
- `DiscoveryCounters` observes existing callbacks without changing their
  returned value or exception. Nested durations overlap.
- `WorkPostings` prepares a bounded, content-stamped ordered index during warm;
  a hook verifies the payload and never rebuilds it. Original owner authority
  is still checked after admission. Frequency batching preserves source values.
- `WorkPostingsAudit` checks complete original nomination order, independent
  document frequencies, corruption, stale domain rejection and unchanged warm.
- `SynapseUsage` and `SharedPresentationTests` recognize renderer-owned CODE
  frames using original source coordinates and full declared provenance.
  Multiple consecutive file frames must all be recognized. Locations, changed
  code/fingerprints/origins and incomplete frames cannot count as delivered
  originals. This telemetry does not create a Match, Union or completion.

See `docs/native-hook-scale.md` for actual findings. All current results are
isolated and unadopted. Small paired timings and identical body bytes are not
the matched inclusive-token/quality/deadline adoption conditions in AGENTS.md.
The current scale gate is useful delivery with sample p99 below 30 seconds;
the previous three-second aspiration is not a user requirement.
