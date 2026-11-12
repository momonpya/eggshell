# Clear a discarded model context

The mixed-project lifecycle fixture reproduces an existing defect in product
`ed077918…`: a registered clear event reuses delivery acknowledgements belonging
to the discarded model context. An unchanged DB can therefore appear already
delivered even though the agent no longer sees it.

This isolated Lean patch directly changes `PluginHooks` only; `DeliveryLedger`
also embeds that exact source in its implementation identity. Clear cancels an old search,
advances the context epoch, drops pending offers, the confirmed delivery head,
all delivery claims (including compaction-retained checkpoints), and the old
handoff/search display. It resets delivery uncertainty while preserving profile,
enabled state, pending user settings, original DB evidence, and shared indexes.
Resume and compaction keep their separate existing behavior. Disabled chats
also lose stale delivery claims when cleared.

Four kernel-checked laws state that clear has no delivery claims or confirmed
head, advances the epoch, and preserves user settings. This is a context-state
fix; it adds no shared read lock, search queue, model, ranking rule, or DB repair.
The axiom audit reports only `propext`, `Classical.choice`, and `Quot.sound`.

The real-hook mixed-project fixture passes on product `5d37ec14…`: 22 semantic
queries, 206/206 required row appearances in actual visible context, and a final
ten-client phase of 2.217 seconds. Resume preserves confirmed context, while
clear and compact require the needed original rows in the new reply. All 161
actual callbacks are clean. This is a small native fixture, not a production
p99 or answering-model/token experiment.

The candidate is isolated from the current implementation and global install.
It has no matched token/quality comparison and is **not adopted**. See the
[mixed lifecycle record](../../practical-runtime/mixed-chat-lifecycle/README.md)
for the real-hook test and its validation limits.
