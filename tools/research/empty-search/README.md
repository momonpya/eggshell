# Accepted empty search results

Apply `docs/candidates/empty-search-runtime.patch` to the pinned original
lexical-witness candidate, then copy this helper into `tools/research/`.
Build every affected public caller. This is an isolated candidate, not product,
README-result or release adoption.

`EmptySearchAudit NEW-OUTPUT.json` checks the two routes and five semantic
statuses, current accepted empty decoding, missing/malformed/expired/stale
replies, oversized native bytes and retained real pending results. Empty status
metadata must add neither body nor authority, source checkpoint, packet or
delivery claims. Its observed search trace must be unchanged. The helper also
audits ordinary axioms for the accepted-empty and authority-free metadata proofs.

The native 10k/50k check uses the unchanged `HookScaleRun` harness, original
read-only sources and source-only cache copies. It records actual stdout,
publication SHA, current search receipt, memory ACK, acknowledged history and
owned-manager shutdown. Empty metadata is not a memory offer. Semantic timeout
must remain visible even when lexical delivery is valid and empty.
