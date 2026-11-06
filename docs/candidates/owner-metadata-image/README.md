# Immutable owner metadata in a pinned query view

Status: isolated candidate, unadopted. Product code and README performance
claims are unchanged. Answering-model calls: 0; paid matched comparisons: 0/18.

Palette creation already reads checked metadata to establish the complete
reply size. After query admission, the old code reacquired the shared metadata
cache for rendering and again inside source selection. Every hit changed
borrower counts and LRU metadata under its owner mutex.

The candidate captures references to the immutable checked values after the
existing query-view reservation. A scope-checked image contains a string and
an immutable map of `OwnerReady` values. It has no cache owner, promise,
mutable reference, mutex or CAS capability. Palette rendering and source
selection use its pure lookup; they cannot update shared cache bookkeeping.
This retains checked metadata references under the existing query-view
reservation rather than asserting that returning a value from `withReady`
makes its lifetime free. No cache capacity or original deadline is increased.

Lean proves exact retrieval after insertion, rejection of a different pinned
identity, and preservation of other owners. ContractAudit checks that the
actual source selector calls this pure lookup and does not call
`Loaded.withMetadata`. The native test holds the original metadata-cache mutex
while another task reads its captured view, checks the original checked JSON,
duplicate/missing owners and foreign identity rejection, and verifies that
cache bookkeeping is unchanged and the query reservation is released.

The metadata-load/admission path still synchronizes mutable ownership. File
headers, original/page reads, view/lease acquire and release, and the public
frame coordinator remain separate paths. This candidate is not a proof of
whole-query lock freedom, linear IO ownership, or total heap/RSS safety.
The remaining 80-client memory failure must be diagnosed before repeating
that full-hook load. Real 98% evidence delivery, eight-hour traffic, growing
projects, NAS behavior, quality and total-token improvement remain open.

The native checks and ordinary ContractAudit pass. The same sealed client
completes two16-client waves:32/32 required originals plus ACKs,32/32 semantic
handoffs,and all32 complete stdout values byte-identical to the immutable
deadline parent. Latency min/median/max is7,129/8,068/8,828ms;related peak RSS
is2,698,336KiB. This single control does not establish a latency or memory
improvement. No80-client full-hook retry was run.

Native-source comparison binds both executable SHAs and252 candidate modules
against251 parent modules. The only new module is the declared immutable
image;the only existing source changes are SharedReadViews,PublicationService
and ContractAudit. Two failed builds and a failed record-selection helper are
retained as failures. The record helper was corrected to select the explicit
parent hook tag,and validated all retained stdout hashes before resuming.

[Controls](controls.json),[actual hook evidence](evidence.json),
[independent body verification](verification.json),[native source audit](native-sources.json).

[Plan](plan.json), [implementation](candidate.patch),
[native checks](../../../tools/research/OwnerMetadataChecks.lean),
[kernel laws](../../../tools/research/OwnerMetadataImage.lean).
