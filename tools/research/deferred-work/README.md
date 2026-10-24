# Isolated deferred Work discovery

The source copies here were compiled and exercised in the retained checkout.
`docs/candidates/deferred-work-runtime.patch` applies to the pinned source-delta
checkout with `git apply --unidiff-zero` and includes both Work-only factoring
and discovery integration. It
replaces, rather than stacks on, `work-inference-runtime.patch`. All seven
affected files were round-tripped byte for byte.

`DeferredWorkAudit` compares discovery with fixed nomination/focus callbacks.
`HookScaleRun` also uses the real numerical provider and native transport,
checks stdout/ACK history and stops its manager. Warm runs in a child which
exits before measurement. Neither helper invokes an answering model.

See `docs/deferred-work-discovery.md` and the review for hashes, raw receipts,
successful/failed guards and limits. The measured hook is not faster; this is
an unadopted research checkpoint.
