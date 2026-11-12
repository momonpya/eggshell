# Mixed projects and chat lifecycles

This is a native Lean fixture using actual registered plugin hook commands,
real source reads, and a real frontend/publication-service restart. It does not
create Codex UI chats or call an answering model. Both projects start empty;
no manual `keep` or `warm` command runs.

The predeclared workload has two logical project DBs with four storage owners
each, four writer sessions, nine writer turns, and three reader waves of
4 / 8 / 10 requests. Single-project and combined readers are mixed. Four writers
overlap eight fresh/existing readers, for at most twelve simultaneous clients.
Two writer turns are interrupted with actual tool results held by the host.
After restarting both services, late Post and Stop events are delivered, with
duplicate Post/Stop events. One writer starts a newer turn targeting BETA before
its old ALPHA results arrive. The old results must retain ALPHA as their captured
destination, and the old Stop must not close the newer turn.

Readers retain only bodies actually returned by earlier hooks. Resume preserves
that visible context; compact and clear discard it. Requirements are frozen from
DB-present original observations and independently fingerprinted files before
each stable reading phase. Every required row must occur in the CODE block of
its own SOURCE path/fingerprint. A position, a matching line in an unrelated
block, or an expected answer is insufficient. During the overlapping write wave,
the frozen requirements cover the previously published baseline, not every
concurrent append. The final stable wave requires all eighteen source fields.

## Failures that the test exposed

The first run on product `ed077918…` stopped at a faulty storage oracle. It
required 27 *timed synaptic provenance* records as evidence of 27 stored tool
observations. A read-only postmortem instead found all 27 native observations,
all nine final answers, and all eighteen source fields in the correct DBs. Each
native observation agrees with its immutable receipt's complete tool input and
output. Four late results lack a verified interval across the interruption and
service-clock change; the other 23 have verified timed provenance. No clock is
invented or filled from a newer turn. The original failed run stays failed.
`postmortem.json` and `native-originals.json` preserve both measurements without
replaying a hook, repairing a DB, or changing original publication bytes.

The corrected oracle counts native identities for durability and reports timed
provenance separately. It also rejects duplicate identities and wrong-project
publication. On the unchanged product, this reaches the final lifecycle phase
and exposes a **real clear defect**: `SessionStart(source=clear)` retains
`confirmedDelivery` and prior delivery claims. Compact resets the confirmed head;
resume is supposed to retain it. `clear-failure.json` records this failure.

The isolated [clear correction](../../candidates/context-clear/README.md) clears
context delivery without deleting DB evidence or changing project settings.
It is not adopted into the main implementation or global installation.

## Result with the isolated correction

Product SHA-256 is `5d37ec1454fe36e1247e0488646d70886312c5a701638c102fe691fdc83a352d`.
The direct source change is `PluginHooks`; `DeliveryLedger` also embeds those
exact changed source bytes in its implementation identity. All 336 native product
objects are consistent. The 315-object fixture has the same complete product
core and 313 byte-identical common imported sources; its two added fixture
sources are bound independently.

| Reading phase | Clients | Entire gated phase |
| --- | ---: | ---: |
| Initial fresh readers | 4 | 1.423 s |
| Fresh/existing readers overlapping four writers | 8 + 4 writers | 2.658 s |
| After restart: resume, compact, clear, fresh | 10 | 2.217 s |

These gates include each reader's Stop and exclude its preceding SessionStart.
All 22 searches complete semantically. Independent reconstruction from retained
actual hook outputs verifies **206/206** required row appearances in visible
context. Existing readers may count earlier actually delivered bodies; all fresh,
cleared, and compacted contexts must obtain their rows in the new body itself.
The final frozen inventory has eighteen distinct source fields across nine turns.
All 27 native observations and nine answers remain in their captured projects.
The four unknown intervals remain separately reported; 23 are verified.

All 161 callbacks in this candidate run have exit zero, empty stderr, and no
incomplete notice. The two earlier failed fixtures retain their own 245 callbacks,
so the combined audit covers 406 actual callbacks without relabeling those runs
as successful. All three advisory edge types remain in every populated owner.
Background service warnings and both services' stop receipts are retained.
Sampled related RSS peaks at 3,308,800 KiB. The resource guard does not trigger,
both services stop normally, and no owned process remains.

The first metadata retention attempt incorrectly required additionalContext on
an existing-context empty reply. Retention now accepts an absent context as
empty and rejects nontext values, then checks the actual body and before/after
visible hashes. No product execution was repeated for this metadata correction.

Ended DBs, caches, and duplicate diagnostic builds were deleted: 26,892 entries,
2,822,586,145 logical bytes, with no archive. The original diagnostic LLVM DB and
current product/model/native inputs retain their hashes. The current isolated
product's 336-object closure passes again after deletion.

## Validation boundary

This fixture cannot establish 80-user long-term operation, SMB/NFS behavior,
production p99, unrestricted evidence recall, answer quality, or token savings.
The current adoption count and paid matched-comparison count remain zero.
An interval that is unknown after restart remains unknown; successful raw
storage and delivery do not certify that interval or promote a recommendation
to completed work.
