/-- Source identity and the identity of a priced presentation are different.
Every field used by fragment rendering belongs to this price key. -/
structure RenderFragmentKey where
  first : Nat
  original : String
  decoded : Bool
  path : Option (List JsonScalars.Segment)
  compact : Bool
  deriving DecidableEq

instance : BEq RenderFragmentKey := ⟨fun a b => decide (a = b)⟩
instance : LawfulBEq RenderFragmentKey where
  rfl := by intro value; change decide (value = value) = true; simp
  eq_of_beq := by intro a b same; change decide (a = b) = true at same; exact of_decide_eq_true same
-- Path equality is checked by BEq. Omitting it from the hash changes only
-- collision work, and avoids serializing a JSON path to build a cache key.
instance : Hashable RenderFragmentKey := ⟨fun key => hash (key.first,key.original,key.decoded,key.compact)⟩

def DeliveryFragment.renderKey (fragment : DeliveryFragment) (compact : Bool) : RenderFragmentKey :=
  ⟨fragment.first,fragment.original,fragment.decoded,fragment.path,compact⟩
def RenderFragmentKey.fragment (key : RenderFragmentKey) : DeliveryFragment :=
  ⟨key.first,key.original,key.decoded,key.path⟩
def RenderFragmentKey.text (key : RenderFragmentKey) : String := key.fragment.render key.compact

theorem fragment_render_key_exact (fragment : DeliveryFragment) (compact : Bool) :
    (fragment.renderKey compact).fragment = fragment ∧
    (fragment.renderKey compact).text = fragment.render compact := by
  cases fragment
  exact ⟨rfl,rfl⟩

/-- Deduplicate whole, already-priced pieces. Assembly must not cut them and
manufacture new captions after their prices have been used by the selector. -/
def pricedFragments (compact : Bool) (fragments : List DeliveryFragment) : List DeliveryFragment :=
  ((hashDistinct (fragments.map (·.renderKey compact))).map (·.fragment)).mergeSort (fun a b => a.first ≤ b.first)

theorem priced_fragments_mem (compact : Bool) (fragments : List DeliveryFragment) (fragment : DeliveryFragment) :
    fragment ∈ pricedFragments compact fragments ↔ fragment ∈ fragments := by
  unfold pricedFragments
  rw [List.mem_mergeSort]
  constructor
  · intro present
    obtain ⟨key,known,same⟩ := List.mem_map.mp present
    obtain ⟨original,present,produced⟩ := List.mem_map.mp ((HashDistinct.mem key _).mp known)
    rw [← produced] at same
    have restored := (fragment_render_key_exact original compact).1
    rw [restored] at same
    exact same ▸ present
  · intro present
    apply List.mem_map.mpr
    refine ⟨fragment.renderKey compact,(HashDistinct.mem _ _).mpr (List.mem_map.mpr ⟨fragment,present,rfl⟩),?_⟩
    exact (fragment_render_key_exact fragment compact).1

def checkedPricedContextAssembly (prior offered : ContextDelivery) : Option
    {result : ContextDelivery // result.sameEnvelope prior ∧
      ∀ fragment ∈ prior.fragments, fragment ∈ result.fragments} :=
  if offered.sameEnvelope prior && prior.compactCaptions == offered.compactCaptions &&
      prior.fragments.all (fun fragment => offered.fragments.all (fun next => decide (next.agrees fragment))) then
    let result := {prior with
      planKey := offered.planKey
      cues := prior.cues ++ offered.cues
      fragments := pricedFragments prior.compactCaptions (prior.fragments ++ offered.fragments)}
    some ⟨result,by simp [result,ContextDelivery.sameEnvelope],by
      intro fragment present
      exact (priced_fragments_mem _ _ _).mpr (List.mem_append_left _ present)⟩
  else none

