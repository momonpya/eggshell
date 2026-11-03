module

public import Eggshell.DB.PageMap
public import Eggshell.Lifecycle
public import Std

@[expose] public section

namespace Eggshell.Research.OwnedPublication

/- A design model, not a concurrent IO implementation. Each producer appends
only its own physical stream. Replacing a shared whole-map head with a locally
prepared map is explicitly NOT justified by these commutation theorems.
Source publications use real PageMap heads; runtime ownership, persistence,
owner handover and refinement to GraphStore remain separate obligations. -/

structure Domain where
  identity : String
  authority : String

variable {domain : Domain}

structure EventRef where
  producer : Nat
  offset : Nat

structure Entry (domain : Domain) where
  source : DB.PageMap.Head
  sameProject : source.identity = domain.identity
  sameAuthority : source.authority = domain.authority
  dependencies : List EventRef := []

abbrev Streams (domain : Domain) := Nat → List (Entry domain)

def append (streams : Streams domain) (producer : Nat)
    (batch : List (Entry domain)) : Streams domain :=
  fun slot => if slot = producer then streams slot ++ batch else streams slot

theorem own_append (streams : Streams domain) (producer : Nat) (batch : List (Entry domain)) :
    append streams producer batch producer = streams producer ++ batch := by
  simp [append]

theorem other_unchanged (streams : Streams domain) (producer other : Nat)
    (batch : List (Entry domain)) (different : other ≠ producer) :
    append streams producer batch other = streams other := by
  simp [append, different]

/-- Independent physical stream updates commute. No shared-map assignment,
mutex, CAS, scheduler, hash collision or arithmetic bound is assumed here. -/
theorem independent_append_commutes (streams : Streams domain) (left right : Nat)
    (a b : List (Entry domain)) (different : left ≠ right) :
    append (append streams left a) right b = append (append streams right b) left a := by
  funext slot
  by_cases atLeft : slot = left
  · subst slot
    simp [append, different]
  · by_cases atRight : slot = right
    · subst slot
      simp [append, atLeft]
    · simp [append, atLeft, atRight]

theorem same_producer_order (streams : Streams domain) (producer : Nat)
    (a b : List (Entry domain)) :
    append (append streams producer a) producer b = append streams producer (a ++ b) := by
  funext slot
  by_cases here : slot = producer <;> simp [append, here, List.append_assoc]

/-- A stale whole-state replacement loses another producer's update, despite
disjoint stream IDs. Removing synchronization from that implementation would
be incorrect; the executor must update independently owned stream locations. -/
theorem stale_whole_replacement_loses_update (left right : Nat)
    (a b : Entry domain) (different : left ≠ right) :
    append (fun _ => []) right [b] left = [] ∧
    append (append (fun _ => []) left [a]) right [b] left = [a] := by
  simp [append, different]

theorem append_grows (streams : Streams domain) (producer slot : Nat)
    (batch : List (Entry domain)) :
    (streams slot).length ≤ (append streams producer batch slot).length := by
  by_cases here : slot = producer <;> simp [append, here]

theorem retained_prefix (streams : Streams domain) (producer slot count : Nat)
    (batch : List (Entry domain)) (within : count ≤ (streams slot).length) :
    (append streams producer batch slot).take count = (streams slot).take count := by
  by_cases here : slot = producer
  · simp only [append, if_pos here]
    exact List.take_append_of_le_length within
  · simp [append, here]

/-- A fixed view must include every referenced event, including dependencies
in other producers' streams. Independent local frontiers alone are unsafe. -/
structure ReadView (streams : Streams domain) where
  frontier : Nat → Nat
  within : ∀ producer, frontier producer ≤ (streams producer).length
  closed : ∀ producer entry, entry ∈ (streams producer).take (frontier producer) →
    ∀ dependency ∈ entry.dependencies, dependency.offset < frontier dependency.producer

variable {streams : Streams domain}

@[ext] theorem ReadView.ext {left right : ReadView streams}
    (same : left.frontier = right.frontier) : left = right := by
  cases left
  cases right
  cases same
  rfl

/-- Dependency-closed views can be joined without choosing a winning mutable
head. Every dependency of either input remains inside the joined frontier. -/
def ReadView.join (left right : ReadView streams) : ReadView streams where
  frontier := fun producer => max (left.frontier producer) (right.frontier producer)
  within := by
    intro producer
    have a := left.within producer
    have b := right.within producer
    omega
  closed := by
    intro producer entry selected dependency referenced
    rcases Nat.le_total (left.frontier producer) (right.frontier producer) with smaller | smaller
    · have present : entry ∈ (streams producer).take (right.frontier producer) := by
        simpa [Nat.max_eq_right smaller] using selected
      exact Nat.lt_of_lt_of_le (right.closed producer entry present dependency referenced)
        (Nat.le_max_right _ _)
    · have present : entry ∈ (streams producer).take (left.frontier producer) := by
        simpa [Nat.max_eq_left smaller] using selected
      exact Nat.lt_of_lt_of_le (left.closed producer entry present dependency referenced)
        (Nat.le_max_left _ _)

theorem ReadView.join_comm (left right : ReadView streams) : left.join right = right.join left := by
  apply ReadView.ext
  funext producer
  exact Nat.max_comm _ _

theorem ReadView.join_assoc (a b c : ReadView streams) : (a.join b).join c = a.join (b.join c) := by
  apply ReadView.ext
  funext producer
  exact Nat.max_assoc _ _ _

theorem ReadView.join_idempotent (view : ReadView streams) : view.join view = view := by
  apply ReadView.ext
  funext producer
  exact Nat.max_self _

theorem ReadView.join_keeps_left (left right : ReadView streams) (producer : Nat) :
    left.frontier producer ≤ (left.join right).frontier producer := Nat.le_max_left _ _

def ReadView.retain (view : ReadView streams) (producer : Nat)
    (batch : List (Entry domain)) : ReadView (append streams producer batch) where
  frontier := view.frontier
  within := fun slot => Nat.le_trans (view.within slot) (append_grows streams producer slot batch)
  closed := by
    intro slot entry selected dependency referenced
    rw [retained_prefix streams producer slot (view.frontier slot) batch (view.within slot)] at selected
    exact view.closed slot entry selected dependency referenced

theorem ReadView.no_missing_dependency (view : ReadView streams) (producer : Nat)
    (entry : Entry domain) (selected : entry ∈ (streams producer).take (view.frontier producer))
    (dependency : EventRef) (referenced : dependency ∈ entry.dependencies) :
    ∃ original, (streams dependency.producer)[dependency.offset]? = some original := by
  have bounds := Nat.lt_of_lt_of_le (view.closed producer entry selected dependency referenced)
    (view.within dependency.producer)
  exact ⟨(streams dependency.producer)[dependency.offset],
    List.getElem?_eq_some_iff.mpr ⟨bounds,rfl⟩⟩

theorem missing_dependency_rejects_view (frontier : Nat → Nat) (producer : Nat)
    (entry : Entry domain) (selected : entry ∈ (streams producer).take (frontier producer))
    (dependency : EventRef) (referenced : dependency ∈ entry.dependencies)
    (missing : frontier dependency.producer ≤ dependency.offset) :
    ¬ ∃ view : ReadView streams, view.frontier = frontier := by
  rintro ⟨view, same⟩
  have covered := view.closed producer entry (by simpa [same] using selected) dependency referenced
  rw [same] at covered
  omega

def ReadView.originals (view : ReadView streams) (producers : List Nat) : List (Entry domain) :=
  producers.flatMap fun producer => (streams producer).take (view.frontier producer)

/-- The requested original boundary is fixed independently of readiness.
A closed but older view must not silently replace that requested boundary. -/
structure QueryView (streams : Streams domain) (requested : Nat → Nat) where
  view : ReadView streams
  exactBoundary : view.frontier = requested
  producers : List Nat
  inventory : ∀ producer, 0 < requested producer → producer ∈ producers

theorem lagging_view_is_not_requested (view : ReadView streams) (requested : Nat → Nat)
    (producer : Nat) (behind : view.frontier producer < requested producer) :
    view.frontier ≠ requested := by
  intro same
  rw [same] at behind
  exact Nat.lt_irrefl _ behind

/-- The manifest must name every nonempty stream. An available dependency in
an omitted stream is not sufficient: it must enter the assembled graph input. -/
theorem ReadView.dependencies_in_originals (view : ReadView streams) (producers : List Nat)
    (inventory : ∀ producer, 0 < view.frontier producer → producer ∈ producers)
    (entry : Entry domain) (selected : entry ∈ view.originals producers)
    (dependency : EventRef) (referenced : dependency ∈ entry.dependencies) :
    ∃ original, (streams dependency.producer)[dependency.offset]? = some original ∧
      original ∈ view.originals producers := by
  obtain ⟨producer, _, present⟩ := List.mem_flatMap.mp selected
  have covered := view.closed producer entry present dependency referenced
  obtain ⟨original, available⟩ := view.no_missing_dependency producer entry present dependency referenced
  have positive : 0 < view.frontier dependency.producer := by omega
  have inPrefix : original ∈ (streams dependency.producer).take (view.frontier dependency.producer) := by
    apply List.mem_of_getElem? (i := dependency.offset)
    rw [List.getElem?_take_of_lt covered]
    exact available
  exact ⟨original, available, List.mem_flatMap.mpr
    ⟨dependency.producer, inventory dependency.producer positive, inPrefix⟩⟩

theorem ReadView.originals_unchanged (view : ReadView streams) (producer : Nat)
    (batch : List (Entry domain)) (producers : List Nat) :
    (view.retain producer batch).originals producers = view.originals producers := by
  change producers.flatMap (fun slot => (append streams producer batch slot).take (view.frontier slot)) =
    producers.flatMap (fun slot => (streams slot).take (view.frontier slot))
  apply congrArg (fun pick : Nat → List (Entry domain) => producers.flatMap pick)
  funext slot
  exact retained_prefix streams producer slot (view.frontier slot) batch (view.within slot)

/-- The complete named-owner input is unchanged, not merely each separately
scored range. This applies to any pure consumer of that exact fixed input. -/
theorem ReadView.consumer_unchanged (view : ReadView streams) (producer : Nat)
    (batch : List (Entry domain)) (producers : List Nat) (consume : List (Entry domain) → α) :
    consume ((view.retain producer batch).originals producers) = consume (view.originals producers) :=
  congrArg consume (view.originals_unchanged producer batch producers)

/-- Ownership removes competing writes, not freshness checks. Reuse still
uses the actual native request stamp, including its existing deadline. -/
theorem expired_still_rejected (stamp : Plugin.RequestStamp) (turn : String)
    (epoch now : Nat) (expired : stamp.deadline ≤ now) : stamp.accepts turn epoch now = false :=
  Plugin.expired_request_cannot_publish stamp turn epoch now expired

#print axioms independent_append_commutes
#print axioms stale_whole_replacement_loses_update
#print axioms ReadView.join
#print axioms ReadView.join_comm
#print axioms ReadView.join_assoc
#print axioms ReadView.join_idempotent
#print axioms ReadView.no_missing_dependency
#print axioms missing_dependency_rejects_view
#print axioms lagging_view_is_not_requested
#print axioms ReadView.dependencies_in_originals
#print axioms ReadView.consumer_unchanged
#print axioms expired_still_rejected

end Eggshell.Research.OwnedPublication
