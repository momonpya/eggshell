# Compile advisory topology before querying

Status: an isolated Lean prototype. It is **not connected to the product
hook**, persisted as a segmented view, or adopted.

## Diagnosis

The fixed topic-1 source and the exact recorded nomination/hydration were
walked independently of selection. With the existing fact/request/byte caps,
the first lookup was still incomplete after 2,757 ms: 5,840 facts and no
admitted offers. With diagnostic limits, the whole walk completed in
24,390 ms: 5,151 lookups, 41,244 encountered facts, and 27,825 offers.
Its offered original ranges cover **4/4** frozen necessary items.
This is graph reachability, not actual delivery.

The product's 500 ms walk cannot finish even its first answer lookup.
Each posting leads to another B-tree point lookup, canonical JSON decoding,
validation and content hashing. The same full evidence is reconstructed
again when reached through another address. Raising the time limit or
admitting a timing-dependent prefix is not the proposed fix.

## Prototype

[SynapticRouting.lean](candidates/synaptic-routing/Eggshell/SynapticRouting.lean)
projects the existing support, reverse-consumption, coquotation and usage
transitions. It interns nodes and targets once and shares checked immutable
facts. The query loop follows integer IDs with a hash set for visitation.
It does no B-tree lookup, JSON decoding, or evidence hashing per transition.
Priority inheritance and omission-over-positive-citation handling are kept.
There is no command recognizer, reference answer, question-specific rule,
new score, or e-graph authority in this projection.

`project_carries` proves that every projected target is carried by its
underlying fact. Returned Offers retain the original fact validity and
identity proofs; their target predicate is rechecked. This is not a proof
of the complete storage/refinement path or of end-to-end delivery recall.

On the actual shared/private fixed snapshot:

| Measurement | Result |
| --- | ---: |
| Facts read and validated | 39,777 |
| Nodes / distinct targets / compiled arcs | 5,177 / 5,118 / 41,382 |
| Source fact read and validation | 5,693 ms |
| Compilation | 2,173 ms |
| Three traversals, each with a 500 ms limit | 13 / 13 / 13 ms |
| Offers per traversal | 27,825 |
| Independent reference comparison | Exact, including evidence and priority |
| Guarded aggregate peak RSS | 351,280 KiB |

The comparison normalizes offer order only; it retains multiplicity, target,
evidence identity, kind and priority. It checks the saved independent complete
walk rather than generating an expected result with the new traversal.
See [report](candidates/synaptic-routing/records/routing-report.json) and
[graph coverage](candidates/synaptic-routing/records/walk-coverage.json).

## Required next integration

The prototype reads the whole fixed fact set once. Treating that resident
arena as a large shared-DB implementation would repeat the scaling mistake.
The next implementation must publish compact topology in bounded immutable
blocks, bind them to the same source/index publication and implementation
bytes, read/cache blocks with an explicit memory bound, and fetch original
evidence only where needed. Publication deltas must update affected blocks;
source/private scopes must remain separate. It must not move an 8-second
full preparation into every prompt or add another original-body writer.

After connecting that view to the hook, rerun the fixed model-free topic
audit, including timeout failures. Actual topic delivery remains 2/4, 0/6,
3/5. A new product runtime requires a new seed for the answering-model study.
No product token improvement, p99, million-window, or 80-user claim follows
from these three traversal measurements.
