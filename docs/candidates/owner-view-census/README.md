# Original-view admission: native component census

The previous [producer-window candidate](../producer-windows/README.md) was
rejected before search. This census separates its window-group representation
from the unrelated change to `OwnerReady.bytes`. No product, threshold, model,
ranking rule, window width or budget is changed by the census.

A compiled Lean observer reads the exact original revision 41 and the 40 owner
identities recorded by the parent's real topic-1 query. It reconstructs owner
metadata using the actual publication functions and the same producer-window
module. It does not create a DB, warm indexes, run retrieval or call a model.
The [native closure](native.json) is consistent and the [source audit](sources.json)
finds all product core present and 307 common sources unchanged.

The census checks all four original source-file hashes before and after reading.
The data covers 9,583 per-owner original rows. This is an independent transient
reconstruction without a prepared supplement index, not a new measurement of the
previous hook's live view or heap. The two producer totals are counterfactual
metadata representations, not successful deliveries.

| Count, including original record geometry | Bytes | Reservation before lease |
| --- | ---: | ---: |
| Parent's descriptor-plus-focus definition | 3,897,917 | 124,798,880 |
| Producer groups with that same definition | 3,913,532 | 125,298,560 |
| Producer groups with full stored metadata counted | 4,660,697 | 149,207,840 |

The unchanged view capacity is 134,217,728 bytes. The unchanged reservation is
`65536 + 32 * countedBytes + leaseCharge`; the table excludes the lease charge.
Producer grouping adds only 15,615 counted bytes (about 0.4%). Changing the
accounting definition adds another 747,165 bytes and crosses the fixed capacity.
Thus the previous run did not test whether the grouping improves selection.
The next isolated comparison preserves the parent's exact accounting definition,
all limits and the multiplier, and changes only the proposed grouping.

The [per-owner data](census.json) also separates the main components: focus
2,461,025 bytes, parent descriptor 585,103, original geometry 851,789, parent plan
575,301, bounded-record indices 52,009 and scopes 23,765. These serialized
component counts overlap where representations refer to the same values; they
are not additive unique heap measurements. The selector needs prepared rows,
units, scopes and records as well as descriptor/focus data, so removing all of
those fields from the query view would be incorrect.

The [guard](guards.json) finishes normally with no owned processes: 11.508 s
overall, 4.406 s inside the reconstruction loop, sampled related peak 134,928 KiB.
These are census timings, not hook timings. The first observer compile refusal
is recorded and is not a passing run. Answering calls, actual queries and
adoption remain zero.

Ended copied source/build/compiler-cache files are [deleted without archives](cleanup.json):
2,792 files / 555,769,239 logical bytes. All 355 protected native hashes agree
before and after cleanup. The original source and current product remain.
