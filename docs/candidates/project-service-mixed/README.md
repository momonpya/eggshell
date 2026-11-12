# Shared service with concurrent capture and interrupted clients

The existing native mixed-lifecycle workload now has a project-service mode.
It uses registered hook commands, two logical project DBs with four physical
owners each, four writer sessions, single-project/combined readers and an
actual restart of the host publisher, client publisher and frontend.
No answering model is called and no manual `keep` or `warm` runs.

The predeclared base workload has nine writer turns and 27 original tool
observations. Two turns stop with real tool results held by the fixture. After
restart, those results arrive late, with duplicate events; one session starts
a new turn writing BETA before its older ALPHA results arrive. Captured
destinations, native receipts and visible original evidence are checked.
An additional mode adds four growth waves on one physical owner per project,
with at most fourteen simultaneous clients on this Mac.

## Baseline result: interrupted-source preparation is not recovered

Product `d3496cae…` passes four fresh baseline readers in 1.665 seconds.
Four writers overlapping eight fresh/existing readers pass in 2.527 seconds.
All twelve completed reader queries include their previously frozen original
requirements. This is component evidence; the whole workload fails afterward.

After service restart, the project-switch prompt receives an incomplete
notice. Its pending turn, selected writer and captured descriptor all correctly
name BETA. A native read-only postmortem verifies all 20 observations and six
answers published before that point; original source files are unchanged.
The unfinished operations are not counted as lost observations.

A second native read-only probe opens the actual failed cut. All four populated
owners lack both captured query inputs and captured owner-identity inputs;
their current heads have the same readiness failure. All four empty owners
have both inputs. This is distinct from the earlier missing-empty-owner bug.

The publisher creates an empty in-memory preparation plan at startup and does
not discover its durable registry. Re-registering the new BETA writer neither
recovers every ALPHA job nor waits for background preparation. Query execution
also looks up the raw captured cut immediately. The next isolated candidate
addresses recovery and admission; weights and model files are untouched.

The guard is terminal, untriggered and drained, with sampled peak RSS
3,613,872 KiB. The failed run, actual callback bytes, runtime/observer bindings,
partial stage results, service stops and native postmortems are retained.
The corrected probe's 322 native objects and all 320 common product sources
are audited separately; a probe compiler rejection and a metadata-audit
attempt to overwrite earlier evidence are not successful validations.

See [failed run](overlapping-rejection.json), [original storage audit](overlapping-postmortem.json),
[captured-cut preparation audit](overlapping-prepared-inspect.json),
[probe source audit](probe-sources.json) and [predeclared workload](plan.json).

This is a small, scripted, single-machine functional test with a
500,000-character allowance. It does not establish production p99, general 98%
delivery, 80-user sustained operation, answer quality, or token reduction.
Adoption and paid matched comparisons remain zero.
