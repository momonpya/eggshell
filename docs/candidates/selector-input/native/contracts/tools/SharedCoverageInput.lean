module
public import tools.SharedCoverage
public import Lean.Data.Json.FromToJson
@[expose] public section

namespace SharedCoverage.Input
open Lean

structure RawOffer where
  closure : List Nat
  covers : List Nat
  deriving BEq, FromJson, ToJson

structure RawProblem where
  costs : Array (Nat × Nat)
  weights : Array Nat
  offers : Array RawOffer
  fixed : Nat × Nat
  limit : Nat × Nat
  deriving BEq, FromJson, ToJson

def ofOffer {nodes cues : Nat} (offer : Offer nodes cues) : RawOffer :=
  {closure := offer.closure.map (·.val),covers := offer.covers.map (·.val)}

def ofProblem (p : Problem) : RawProblem := {
  costs := p.costs,weights := p.weights,fixed := p.fixed,limit := p.limit
  offers := p.offers.map ofOffer}

def checkedIndices (size : Nat) (indices : List Nat) : Except String (List (Fin size)) :=
  indices.mapM fun index => if h : index < size then pure ⟨index,h⟩
    else throw "selector input has an out-of-bounds feature"

theorem checked_indices_values (indices : List (Fin size)) :
    checkedIndices size (indices.map (·.val)) = .ok indices := by
  induction indices with
  | nil => rfl
  | cons index rest ih =>
      simp only [checkedIndices] at ih
      simp only [List.map_cons,checkedIndices,List.mapM_cons,dif_pos index.isLt]
      rw [ih]
      rfl

def RawOffer.decode (nodes cues : Nat) (raw : RawOffer) : Except String (Offer nodes cues) := do
  let closure ← checkedIndices nodes raw.closure
  let covers ← checkedIndices cues raw.covers
  return {closure,covers}

def RawProblem.decode (raw : RawProblem) : Except String Problem := do
  let offers ← raw.offers.toList.mapM (RawOffer.decode raw.costs.size raw.weights.size)
  return {costs := raw.costs,weights := raw.weights,offers := offers.toArray,fixed := raw.fixed,limit := raw.limit}

theorem decode_offer {nodes cues : Nat} (offer : Offer nodes cues) :
    (ofOffer offer).decode nodes cues = .ok offer := by
  cases offer
  simp only [ofOffer,RawOffer.decode,checked_indices_values]
  rfl

private theorem decode_offers {nodes cues : Nat} (offers : List (Offer nodes cues)) :
    ((offers.map ofOffer).mapM (RawOffer.decode nodes cues)) = .ok offers := by
  induction offers with
  | nil => rfl
  | cons head tail ih => simp only [List.map_cons,List.mapM_cons,decode_offer,ih]; rfl

theorem decode_problem (p : Problem) : (ofProblem p).decode = .ok p := by
  cases p with | mk costs weights offers fixed limit =>
  change _ = Except.ok ({costs,weights,offers,fixed,limit} : Problem)
  simp only [ofProblem,RawProblem.decode,Array.toList_map,decode_offers]
  change Except.ok ({costs,weights,offers := offers.toList.toArray,fixed,limit} : Problem) = _
  simp

def encode (p : Problem) : Json := toJson (ofProblem p)
end SharedCoverage.Input
