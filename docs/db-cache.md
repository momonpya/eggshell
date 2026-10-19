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
```

There is no chat ID in this location. Moving or copying the whole DB carries
the cache; deleting the DB deletes its cache. Two independently created DBs
remain distinct even when they use the same graph authority. A copy retains
its DB identity and cached bytes, at its new directory.

Pinned search documents carry their own cache location through ordinary,
federated and focused indexed requests. One numerical provider still scores
the complete requested corpus and ranks it globally. It does not compute
independent top-k results per DB. The original bounded repair callback retains
control of source windows; a cache locator supplies no equality or completion
authority. Records still validate the exact model and original window bytes.

The independent index worker sends the owning DB's cache in its index request.
The default provider command no longer selects a chat-owned vector directory.
Queries use the first durable document's cache; documents without a durable
DB owner use process scratch. Model weights and the numerical runtime remain
shared installation resources.

Vector publication uses the existing secure atomic-file primitive and rejects
symlink ancestors. Cached vectors remain optional hints, not graph facts.

This is the vector-ownership step. Index tickets are still in session
directories; moving them into the DB's `indexes` sidecar and discovering them
after the originating session ends is next. `egg warm`, coverage in `doctor`,
semantic-first deadlines, lexical delivery, and complete per-run receipts
remain unfinished. No quality or language-model token claim follows from this
layout change or its numerical regression tests.
