module
public import Lean
public import tools.SharedCoverage
public import Std.Data.HashMap.Lemmas
@[expose] public section

namespace ScopedCosts

structure Charge where
  key : String
  chars : Nat
  bytes : Nat
  deriving BEq, Lean.ToJson

abbrev Scope := List Nat × List Nat

def annotate (rows : List α) (key : α → β) : List (α × β) :=
  rows.map fun row => (row,key row)

def active (rows : List (α × β)) (keep : α → β → Bool) : List Nat :=
  rows.zipIdx.filterMap fun ((row,key),index) => if keep row key then some index else none

theorem active_annotated_exact (rows : List α) (key : α → β) (keep : α → β → Bool) :
    active (annotate rows key) keep =
      rows.zipIdx.filterMap (fun (row,index) => if keep row (key row) then some index else none) := by
  simp only [active,annotate,List.zipIdx_map,List.filterMap_map]
  rfl

/-- The cache key is the complete finite contributor set. It is not a hash
identity; collisions are compared by the ordinary structural key equality. -/
structure Directory (render : Scope → List Charge) where
  table : Std.HashMap Scope (List Charge) := {}
  correct : ∀ scope values, table[scope]? = some values → values = render scope := by simp

def Directory.get (directory : Directory render) (scope : Scope) : List Charge × Directory render :=
  match found : directory.table[scope]? with
  | some values => (values,directory)
  | none =>
    let values := render scope
    let next : Directory render := {
      table := directory.table.insert scope values
      correct := by
        intro other result accepted
        by_cases same : scope = other
        · subst other
          simpa using accepted.symm
        · have prior : directory.table[other]? = some result := by
            simpa only [Std.HashMap.getElem?_insert,beq_iff_eq,if_neg same] using accepted
          exact directory.correct other result prior }
    (values,next)

theorem Directory.get_exact (directory : Directory render) (scope : Scope) :
    (directory.get scope).1 = render scope := by
  unfold Directory.get
  split
  · rename_i values found
    exact directory.correct scope values found
  · rfl

/-- Serialization contributes one newline per nonempty metadata row. The
caller supplies already rendered immutable metadata, never source payload. -/
def lines (namespaceKey text : String) : List Charge :=
  (text.splitOn "\n").filterMap fun line =>
    if line.isEmpty then none else some ⟨namespaceKey ++ line,line.length+1,line.utf8ByteSize+1⟩

/-- Equal textual identities must have equal costs. Conflicting metadata is
rejected rather than acquiring an arbitrary price from insertion order. -/
def basis? (parts : List (List Charge)) : Option (Array Charge) := do
  let mut charges := #[]
  let mut indices : Std.HashMap String Nat := {}
  for part in parts do
    for charge in part do
      if let some index := indices[charge.key]? then
        let old ← charges[index]?
        if old != charge then none
      else
        indices := indices.insert charge.key charges.size
        charges := charges.push charge
  return charges

def total (charges : List Charge) : Nat × Nat :=
  charges.foldl (fun sum charge => (sum.1+charge.chars,sum.2+charge.bytes)) (0,0)

def offer (p : SharedCoverage.Problem) (extra : Array Charge)
    (old : SharedCoverage.Offer p.costs.size p.weights.size)
    (added : List (Fin extra.size)) : SharedCoverage.Offer (p.costs++extra.map (fun charge => (charge.chars,charge.bytes))).size p.weights.size := {
  closure := old.closure.map (fun index =>
    ⟨index.val,by simpa using Nat.lt_add_right (extra.map fun charge => (charge.chars,charge.bytes)).size index.isLt⟩) ++
    added.map (fun index => ⟨p.costs.size+index.val,by
      simp only [Array.size_append,Array.size_map]
      omega⟩)
  covers := old.covers }

def extend (p : SharedCoverage.Problem) (extra : Array Charge) (added : Array (List (Fin extra.size)))
    (debit : Nat × Nat) : SharedCoverage.Problem := {
  costs := p.costs++extra.map (fun charge => (charge.chars,charge.bytes))
  weights := p.weights
  offers := p.offers.mapIdx fun index old => offer p extra old (added[index]?.getD [])
  fixed := (p.fixed.1-debit.1,p.fixed.2-debit.2)
  limit := p.limit }

theorem extend_weights (p : SharedCoverage.Problem) (extra : Array Charge)
    (added : Array (List (Fin extra.size))) (debit : Nat × Nat) :
    (extend p extra added debit).weights = p.weights := rfl

theorem extend_limit (p : SharedCoverage.Problem) (extra : Array Charge)
    (added : Array (List (Fin extra.size))) (debit : Nat × Nat) :
    (extend p extra added debit).limit = p.limit := rfl

theorem extend_offer_count (p : SharedCoverage.Problem) (extra : Array Charge)
    (added : Array (List (Fin extra.size))) (debit : Nat × Nat) :
    (extend p extra added debit).offers.size = p.offers.size := by simp [extend]

theorem extend_covers (p : SharedCoverage.Problem) (extra : Array Charge)
    (added : Array (List (Fin extra.size))) (debit : Nat × Nat) (index : Nat)
    (bound : index < p.offers.size) :
    ((extend p extra added debit).offers[index]'(by simpa [extend] using bound)).covers.map (·.val) =
      p.offers[index].covers.map (·.val) := by
  simp [extend,offer]

theorem fixed_debit_conserved (p : SharedCoverage.Problem) (extra : Array Charge)
    (added : Array (List (Fin extra.size))) (debit : Nat × Nat)
    (chars : debit.1 ≤ p.fixed.1) (bytes : debit.2 ≤ p.fixed.2) :
    (extend p extra added debit).fixed.1+debit.1 = p.fixed.1 ∧
      (extend p extra added debit).fixed.2+debit.2 = p.fixed.2 := by
  simp only [extend]
  omega

structure Prepared where
  problem : SharedCoverage.Problem
  debit : Nat × Nat
  shared : Array Charge
  uniqueScopes : Nat

/-- Transfer exactly the full-frame variable metadata from the constant to
shared nodes. Base metadata stays reserved. Each offer activates its actual
finite scope; joining offers pays identical metadata only once. -/
def prepare? (p : SharedCoverage.Problem) (base full : Scope) (scopes : Array Scope)
    (render : Scope → List Charge) : Option Prepared := do
  if scopes.size != p.offers.size then none
  let baseCharges := render base
  let baseKeys := baseCharges.map (·.key)
  let fullCharges := render full
  let mut directory : Directory render := {}
  let mut parts : Array (List Charge) := #[]
  for scope in scopes do
    let (values,next) := directory.get scope
    directory := next
    parts := parts.push values
  let basis ← basis? (baseCharges :: fullCharges :: parts.toList)
  let fullKeys := fullCharges.map (·.key)
  let sharedCharges := basis.filter fun charge => !baseKeys.contains charge.key
  let reserved := sharedCharges.toList.filter fun charge => fullKeys.contains charge.key
  let debit := total reserved
  if debit.1 > p.fixed.1 || debit.2 > p.fixed.2 then none
  let indices := (sharedCharges.zipIdx.foldl (fun found (charge,index) => found.insert charge.key index)
    ({} : Std.HashMap String Nat))
  let added ← parts.mapM fun charges => (charges.filter fun charge => !baseKeys.contains charge.key).mapM fun charge => do
    let index ← indices[charge.key]?
    if bound : index < sharedCharges.size then some (⟨index,bound⟩ : Fin sharedCharges.size) else none
  return ⟨extend p sharedCharges added debit,debit,sharedCharges,directory.table.size⟩

end ScopedCosts
