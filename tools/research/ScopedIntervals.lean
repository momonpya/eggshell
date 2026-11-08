module
public import Eggshell.OriginalStructure
public import tools.KeyPostings
public import Eggshell.HashDistinct
@[expose] public section

namespace Eggshell.Research.ScopedIntervals
open Plugin
variable {κ : Type} [BEq κ] [Hashable κ] [LawfulBEq κ]

structure Entry (κ : Type) where
  scope : κ
  span : DeliveryInterval

def Entry.covers (entry : Entry κ) (scope : κ) (position : Nat) : Prop :=
  entry.scope = scope ∧ entry.span.covers position

/-- Compile one exact posting per scope, then merge only touching intervals
inside that posting. No coordinate domain is expanded into individual points. -/
def pack (entries : Array (Entry κ)) : Array (Entry κ) :=
  let scopes := hashDistinct (entries.toList.map (·.scope))
  let directory := KeyPostings.prepare Entry.scope entries
  (scopes.flatMap fun scope =>
    (DeliveryInterval.coalesce ((directory.lookup scope).toList.map (·.span))).map
      (fun span => (⟨scope,span⟩ : Entry κ))).toArray

theorem bucket_member (entries : Array (Entry κ)) (scope : κ) (entry : Entry κ) :
    entry ∈ (KeyPostings.prepare Entry.scope entries).lookup scope ↔
      entry ∈ entries ∧ entry.scope = scope := by
  rw [KeyPostings.Index.lookup_exact]
  constructor
  · intro selected
    obtain ⟨original,inputMember,computed⟩ := Array.mem_filterMap.mp selected
    by_cases scopeEqual : original.scope = scope
    · have equal : original = entry := by simpa [scopeEqual] using computed
      exact ⟨equal ▸ inputMember,by simpa only [← equal] using scopeEqual⟩
    · simp [scopeEqual] at computed
  · rintro ⟨member,scopeEqual⟩
    exact Array.mem_filterMap.mpr ⟨entry,member,by simp [scopeEqual]⟩

/-- Every point and its entire scope are preserved, in both directions.
This includes gaps, touching intervals, duplicate entries and hash collisions. -/
theorem pack_covers (entries : Array (Entry κ)) (scope : κ) (position : Nat) :
    (∃ entry ∈ pack entries,entry.covers scope position) ↔
      ∃ entry ∈ entries,entry.covers scope position := by
  constructor
  · rintro ⟨entry,outputMember,entryInside⟩
    obtain ⟨key,_,groupMember⟩ := List.mem_flatMap.mp (List.mem_toArray.mp outputMember)
    obtain ⟨span,spanMember,valueEqual⟩ := List.mem_map.mp groupMember
    have mappedInside : (⟨key,span⟩ : Entry κ).covers scope position := valueEqual ▸ entryInside
    obtain ⟨scopeEqual,inside⟩ := mappedInside
    change key = scope at scopeEqual
    subst key
    obtain ⟨priorSpan,priorMember,priorInside⟩ :=
      (DeliveryInterval.coalesce_covers _ position).mp ⟨span,spanMember,inside⟩
    obtain ⟨original,originalMember,spanEqual⟩ := List.mem_map.mp priorMember
    have originalScope := (bucket_member entries scope original).mp (Array.mem_toList_iff.mp originalMember)
    exact ⟨original,originalScope.1,originalScope.2,by simpa only [spanEqual] using priorInside⟩
  · rintro ⟨entry,inputMember,same,inside⟩
    have admitted : entry ∈ (KeyPostings.prepare Entry.scope entries).lookup scope :=
      (bucket_member entries scope entry).mpr ⟨inputMember,same⟩
    have original : ∃ span ∈ ((KeyPostings.prepare Entry.scope entries).lookup scope).toList.map (·.span),
        span.covers position := ⟨entry.span,List.mem_map.mpr ⟨entry,Array.mem_toList_iff.mpr admitted,rfl⟩,inside⟩
    obtain ⟨span,member,inside⟩ := (DeliveryInterval.coalesce_covers _ position).mpr original
    refine ⟨⟨scope,span⟩,?_,rfl,inside⟩
    apply List.mem_toArray.mpr
    apply List.mem_flatMap.mpr
    refine ⟨scope,?_,List.mem_map.mpr ⟨span,member,rfl⟩⟩
    rw [HashDistinct.reference]
    apply List.mem_eraseDups.mpr
    exact List.mem_map.mpr ⟨entry,Array.mem_toList_iff.mpr inputMember, same⟩

end Eggshell.Research.ScopedIntervals
