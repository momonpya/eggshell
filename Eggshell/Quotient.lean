module

public import Eggshell.Extract
public import Std.Data.HashMap.Basic
public import Std.Data.HashMap.Lemmas

@[expose] public section

namespace Eggshell

/-- One checked equivalence class. The producer may be heuristic; this certificate is not. -/
structure EquivalenceClass where
  representative : Value
  members : List Value
  exactAuthority : ∀ member, member ∈ members →
    Value.SameExactFootprint member representative

namespace EquivalenceClass

def certify? : List Value → Option EquivalenceClass
  | [] => none
  | representative :: tail =>
      let members := representative :: tail
      if accepted : members.all
          (fun member => Value.sameExactFootprint member representative) then
        some {
          representative
          members
          exactAuthority := by
            intro member present
            apply Value.sameExactFootprint_sound
            exact (List.all_eq_true.mp accepted) member present
        }
      else none

end EquivalenceClass

namespace RepresentativeIndex

abbrev T := Std.HashMap Value Value

def Sound (index : T) : Prop :=
  ∀ value, Value.SameExactFootprint value (index.getD value value)

def insertMembers (representative : Value) : T → List Value → T
  | index, [] => index
  | index, member :: tail =>
      insertMembers representative (index.insert member representative) tail

def build : T → List EquivalenceClass → T
  | index, [] => index
  | index, equivalenceClass :: tail =>
      build (insertMembers equivalenceClass.representative index equivalenceClass.members) tail

theorem empty_sound : Sound ({} : T) := by
  intro value
  have lookup : ({} : T).getD value value = value := by
    apply Std.HashMap.getD_of_isEmpty
    exact Std.HashMap.isEmpty_emptyWithCapacity
  rw [lookup]
  exact Value.sameExactFootprint_refl value

theorem insert_sound {index : T} (sound : Sound index) {member representative : Value}
    (safe : Value.SameExactFootprint member representative) :
    Sound (index.insert member representative) := by
  intro value
  rw [Std.HashMap.getD_insert]
  split
  · rename_i same
    have equality : member = value := by simpa using same
    subst value
    exact safe
  · exact sound value

theorem insertMembers_sound {index : T} (sound : Sound index)
    {representative : Value} {members : List Value}
    (safe : ∀ member, member ∈ members →
      Value.SameExactFootprint member representative) :
    Sound (insertMembers representative index members) := by
  induction members generalizing index with
  | nil => exact sound
  | cons head tail induction =>
      apply induction (insert_sound sound (safe head (by simp)))
      intro member present
      exact safe member (by simp [present])

theorem build_sound {index : T} (sound : Sound index)
    (classes : List EquivalenceClass) : Sound (build index classes) := by
  induction classes generalizing index with
  | nil => exact sound
  | cons equivalenceClass tail induction =>
      apply induction
      exact insertMembers_sound sound equivalenceClass.exactAuthority

end RepresentativeIndex

structure Quotient where
  classes : List EquivalenceClass
  representatives : RepresentativeIndex.T
  exactAuthority : RepresentativeIndex.Sound representatives

namespace Quotient

/-- With no Union, structural equality needs no corpus-dependent index. -/
def literal : Quotient := ⟨[], {}, RepresentativeIndex.empty_sound⟩

def canonical (quotient : Quotient) (value : Value) : Value :=
  quotient.representatives.getD value value

theorem literal_canonical (value : Value) : literal.canonical value = value := by
  simp [literal, canonical]

def toEquality (quotient : Quotient) : Equality where
  same left right := decide (quotient.canonical left = quotient.canonical right)
  reflexive value := by simp [canonical]
  symmetric := by
    simp only [decide_eq_true_eq]
    exact Eq.symm
  transitive := by
    simp only [decide_eq_true_eq]
    exact Eq.trans
  preservesExact := by
    intro left right same
    simp only [decide_eq_true_eq] at same
    have middle : Value.SameExactFootprint
        (quotient.canonical left) (quotient.canonical right) := by
      rw [same]
      exact Value.sameExactFootprint_refl _
    exact Value.sameExactFootprint_trans (quotient.exactAuthority left)
      (Value.sameExactFootprint_trans middle
        (Value.sameExactFootprint_symm (quotient.exactAuthority right)))

@[simp]
theorem same_iff_canonical_eq (quotient : Quotient) {left right} :
    quotient.toEquality.same left right ↔
      quotient.canonical left = quotient.canonical right := by
  simp [toEquality]

theorem equality_of_canonical (left right : Quotient)
    (same : left.canonical = right.canonical) :
    left.toEquality = right.toEquality := by
  simp only [toEquality, same]

theorem equality_preserves_exact (quotient : Quotient) {left right}
    (same : quotient.toEquality.same left right) :
    Value.SameExactFootprint left right :=
  quotient.toEquality.preservesExact same

namespace AliasBuckets

abbrev T := Std.HashMap Value (List Value)

def add (buckets : T) (row : Value × Value) : T :=
  buckets.insert row.2 (row.1 :: buckets.getD row.2 [])

def collect (rows : List (Value × Value)) (buckets : T) : T :=
  rows.foldl add buckets

theorem collect_membership (rows : List (Value × Value)) (buckets : T)
    (value representative : Value) :
    value ∈ (collect rows buckets).getD representative [] ↔
      value ∈ buckets.getD representative [] ∨ (value, representative) ∈ rows := by
  induction rows generalizing buckets with
  | nil => simp [collect]
  | cons row rest ih =>
      obtain ⟨source, target⟩ := row
      simp only [collect, List.foldl_cons]
      rw [← collect, ih]
      by_cases same : target = representative
      · subst target
        simp [add, List.mem_cons, or_assoc, or_comm, or_left_comm]
      · simp [add, Std.HashMap.getD_insert, same, List.mem_cons]
        constructor
        · rintro (present | present)
          · exact Or.inl present
          · exact Or.inr (Or.inr present)
        · rintro (present | equal | present)
          · exact Or.inl present
          · exact False.elim (same equal.2.symm)
          · exact Or.inr present

end AliasBuckets

/-- Invert the current quotient once per discovery pass. The certificate
includes every key of the actual representative table, not just explicit
Union endpoints. Congruence-created structured aliases therefore participate
in child-role lookup without loading every saved All's descendants. -/
structure AliasIndex (quotient : Quotient) where
  buckets : AliasBuckets.T
  complete : ∀ value representative,
    value ∈ buckets.getD representative [] ↔
      quotient.representatives[value]? = some representative

def AliasIndex.prepare (quotient : Quotient) : AliasIndex quotient := {
  buckets := AliasBuckets.collect quotient.representatives.toList {}
  complete := by
    intro value representative
    change value ∈ (AliasBuckets.collect quotient.representatives.toList
      ({} : AliasBuckets.T)).getD representative [] ↔ _
    rw [AliasBuckets.collect_membership]
    simp
}

/-- A value outside the finite table represents itself. Include that value
only if it really is absent; no idempotence assumption about representatives
is needed for this lookup. All other aliases come from one inverse bucket. -/
def AliasIndex.aliases (index : AliasIndex quotient) (work : Value) : List Value :=
  let representative := quotient.canonical work
  let members := index.buckets.getD representative []
  if quotient.representatives[representative]?.isNone then representative :: members
  else members

theorem AliasIndex.aliases_exact (index : AliasIndex quotient) (work value : Value) :
    value ∈ index.aliases work ↔ quotient.toEquality.same work value = true := by
  rw [Quotient.same_iff_canonical_eq]
  unfold aliases
  dsimp only
  cases found : quotient.representatives[quotient.canonical work]? with
  | none =>
      simp only [Option.isNone_none, ↓reduceIte, List.mem_cons, index.complete]
      cases actual : quotient.representatives[value]? with
      | none =>
          have literal : quotient.canonical value = value := by
            simp [canonical, Std.HashMap.getD_eq_getD_getElem?, actual]
          simp [literal, eq_comm]
      | some representative =>
          have different : value ≠ quotient.canonical work := by
            intro same
            rw [same, found] at actual
            contradiction
          have canonical : quotient.canonical value = representative := by
            simp [Quotient.canonical, Std.HashMap.getD_eq_getD_getElem?, actual]
          simp [canonical, different, eq_comm]
  | some representative =>
      simp only [Option.isNone_some, Bool.false_eq_true, ↓reduceIte, index.complete]
      cases actual : quotient.representatives[value]? with
      | none =>
          have different : value ≠ quotient.canonical work := by
            intro same
            rw [same, found] at actual
            contradiction
          have literal : quotient.canonical value = value := by
            simp [canonical, Std.HashMap.getD_eq_getD_getElem?, actual]
          simp [literal, different, eq_comm]
      | some representative =>
          have canonical : quotient.canonical value = representative := by
            simp [Quotient.canonical, Std.HashMap.getD_eq_getD_getElem?, actual]
          simp [canonical, eq_comm]

/-- The indexed predicate used by completion is exactly the full child scan,
including structured congruence aliases, absent values and literal equality.
The IO adapter separately checks the saved child-posting frames and roots. -/
theorem AliasIndex.child_role_exact (index : AliasIndex quotient)
    (children : List Value) (work : Value) :
    (index.aliases work).any children.contains =
      children.any (quotient.toEquality.same work) := by
  apply Bool.eq_iff_iff.mpr
  simp only [List.any_eq_true, List.contains_iff_mem]
  constructor
  · rintro ⟨value, present, child⟩
    exact ⟨value, child, (index.aliases_exact work value).mp present⟩
  · rintro ⟨value, child, same⟩
    exact ⟨value, (index.aliases_exact work value).mpr same, child⟩

end Quotient

namespace QuotientBuilder

abbrev RawClass := List Value
abbrev RawPartition := List RawClass

def initial (values : List Value) : RawPartition :=
  hashDistinct values |>.map (fun value => [value])

def same (partition : RawPartition) (left right : Value) : Bool :=
  left == right || partition.any fun equivalenceClass =>
    equivalenceClass.contains left && equivalenceClass.contains right

def takeClass (value : Value) : RawPartition → RawClass × RawPartition
  | [] => ([value], [])
  | equivalenceClass :: tail =>
      if equivalenceClass.contains value then (equivalenceClass, tail)
      else
        let (found, rest) := takeClass value tail
        (found, equivalenceClass :: rest)

def merge (partition : RawPartition) (left right : Value) : RawPartition :=
  if same partition left right then partition
  else
    let (leftClass, withoutLeft) := takeClass left partition
    let (rightClass, rest) := takeClass right withoutLeft
    hashDistinct (leftClass ++ rightClass) :: rest

def mergeExplicit (partition : RawPartition) (edges : List UnionEdge) : RawPartition :=
  edges.foldl (fun classes edge => merge classes edge.left edge.right) partition

abbrev Representatives := Std.HashMap Value Value

def representatives (partition : RawPartition) : Representatives :=
  partition.foldl (fun index equivalenceClass =>
    match equivalenceClass with
    | [] => index
    | representative :: _ => equivalenceClass.foldl
        (fun current member => current.insert member representative) index) {}

def normalizeRefs (index : Representatives) : Refs → Refs
  | .nil => .nil
  | .semantic value tail =>
      .semantic (index.getD value value) (normalizeRefs index tail)
  | .exact value tail => .exact value (normalizeRefs index tail)

@[simp]
theorem normalizeRefs_nil (index : Representatives) :
    normalizeRefs index .nil = .nil := rfl

@[simp]
theorem normalizeRefs_semantic (index : Representatives) (value : Value)
    (tail : Refs) :
    normalizeRefs index (.semantic value tail) =
      .semantic (index.getD value value) (normalizeRefs index tail) := rfl

/-- Congruence canonicalizes beneath Semantic authority, never Exact authority. -/
@[simp]
theorem normalizeRefs_exact (index : Representatives) (value : Value)
    (tail : Refs) :
    normalizeRefs index (.exact value tail) =
      .exact value (normalizeRefs index tail) := rfl

/-- Canonical structural signature under one equivalence snapshot. -/
def signature (index : Representatives) : Value → Value
  | atom@(.atom _) => atom
  | .apply operator arguments => .apply operator (normalizeRefs index arguments)

/--
Hash-consed congruence pass. Hashing only nominates a bucket; `HashMap` confirms
full structural equality, so collisions never enter semantic identity.
-/
def congruenceStep (index : Representatives) (state : Representatives × RawPartition)
    (value : Value) : Representatives × RawPartition :=
  let (seen, current) := state
  let key := signature index value
  match seen[key]? with
  | some prior => (seen, merge current prior value)
  | none => (seen.insert key value, current)

/-- Full-scan specification retained independently of the runtime scan. -/
def referenceCongruencePass (values : List Value) (partition : RawPartition) : RawPartition :=
  (values.foldl (congruenceStep (representatives partition)) ({}, partition)).2

/-- Atom signatures never change and cannot collide with application
signatures. Skipping them avoids hashing their potentially large payloads in
every congruence round. Explicit Union processing remains unchanged. -/
def applicationStep (index : Representatives) (state : Representatives × RawPartition) :
    Value → Representatives × RawPartition
  | .atom _ => state
  | value@(.apply _ _) => congruenceStep index state value

@[simp]
theorem applicationStep_atom (index : Representatives) (state : Representatives × RawPartition)
    (bytes : ByteArray) : applicationStep index state (.atom bytes) = state := rfl

def congruencePass (values : List Value) (partition : RawPartition) : RawPartition :=
  (values.foldl (applicationStep (representatives partition)) ({}, partition)).2

namespace ApplicationScan

def Sound (index seen : Representatives) : Prop :=
  ∀ key value, seen[key]? = some value → signature index value = key

def Agree (first second : Representatives) : Prop :=
  ∀ operator arguments, first[Value.apply operator arguments]? = second[Value.apply operator arguments]?

theorem signature_atom (index : Representatives) (value : Value) (bytes : ByteArray)
    (same : signature index value = .atom bytes) : value = .atom bytes := by
  cases value <;> simp_all [signature]

theorem merge_self (partition : RawPartition) (value : Value) : merge partition value value = partition := by
  simp [merge, same]

theorem sound_insert (index seen : Representatives) (sound : Sound index seen) (value : Value) :
    Sound index (seen.insert (signature index value) value) := by
  intro query found stored
  rw [Std.HashMap.getElem?_insert] at stored
  split at stored
  · have same : signature index value = query := by simpa using ‹(signature index value == query) = true›
    have equal : value = found := Option.some.inj stored
    simpa [← equal] using same
  · exact sound query found stored

theorem agree_insert (first second : Representatives) (agree : Agree first second)
    (key value : Value) : Agree (first.insert key value) (second.insert key value) := by
  intro operator arguments
  simp only [Std.HashMap.getElem?_insert, agree operator arguments]

theorem agree_atom_insert (first second : Representatives) (agree : Agree first second)
    (bytes : ByteArray) : Agree (first.insert (.atom bytes) (.atom bytes)) second := by
  intro operator arguments
  simpa only [Std.HashMap.getElem?_insert, show (Value.atom bytes == .apply operator arguments) = false from by simp,
    Bool.false_eq_true, ↓reduceIte] using agree operator arguments

theorem step (index : Representatives) (first second : Representatives × RawPartition)
    (partition : first.2 = second.2) (sound : Sound index first.1) (agree : Agree first.1 second.1)
    (value : Value) :
    (congruenceStep index first value).2 = (applicationStep index second value).2 ∧
    Sound index (congruenceStep index first value).1 ∧
    Agree (congruenceStep index first value).1 (applicationStep index second value).1 := by
  rcases first with ⟨seen, before⟩
  rcases second with ⟨other, after⟩
  dsimp only at partition sound agree
  subst after
  cases value with
  | atom bytes =>
    cases found : seen[Value.atom bytes]? with
    | none =>
      simp only [congruenceStep, applicationStep, signature, found]
      exact ⟨True.intro, sound_insert index seen sound (.atom bytes), agree_atom_insert seen other agree bytes⟩
    | some prior =>
      have same := signature_atom index prior bytes (sound _ _ found)
      subst prior
      simp only [congruenceStep, applicationStep, signature, found, merge_self]
      exact ⟨True.intro, sound, agree⟩
  | apply operator arguments =>
    have same := agree operator (normalizeRefs index arguments)
    cases found : seen[Value.apply operator (normalizeRefs index arguments)]? with
    | none =>
      have otherFound : other[Value.apply operator (normalizeRefs index arguments)]? = none := same.symm.trans found
      simp only [congruenceStep, applicationStep, signature, found, otherFound]
      exact ⟨True.intro, sound_insert index seen sound (.apply operator arguments),
        agree_insert seen other agree _ _⟩
    | some prior =>
      have otherFound : other[Value.apply operator (normalizeRefs index arguments)]? = some prior := same.symm.trans found
      simp only [congruenceStep, applicationStep, signature, found, otherFound]
      exact ⟨True.intro, sound, agree⟩

theorem fold (index : Representatives) (values : List Value)
    (first second : Representatives × RawPartition)
    (partition : first.2 = second.2) (sound : Sound index first.1) (agree : Agree first.1 second.1) :
    (values.foldl (congruenceStep index) first).2 =
      (values.foldl (applicationStep index) second).2 := by
  induction values generalizing first second with
  | nil => exact partition
  | cons value rest ih =>
    have next := step index first second partition sound agree value
    exact ih _ _ next.1 next.2.1 next.2.2

end ApplicationScan

/-- Exact partition equality for arbitrary Values and arbitrary incoming
partitions, including mixed explicit Unions. No atom-only corpus assumption
or completed-output equivalence premise is needed. -/
theorem congruencePass_reference (values : List Value) (partition : RawPartition) :
    congruencePass values partition = referenceCongruencePass values partition := by
  symm
  exact ApplicationScan.fold (representatives partition) values ({}, partition) ({}, partition)
    rfl (by simp [ApplicationScan.Sound]) (by intro _ _; rfl)

namespace CongruenceMemo

/-- Hashing is a cached calculation, not equality authority. A key carries
the full current structural signature and the hash of exactly that signature.
It cannot supply an arbitrary hash that hides an equal key in another bucket. -/
structure Key where
  value : Value
  fingerprint : UInt64
  exact : fingerprint = hash value

def Key.make (value : Value) : Key := ⟨value, hash value, rfl⟩

theorem Key.ext (left right : Key) (same : left.value = right.value) : left = right := by
  cases left with
  | mk lv lh le =>
    cases right with
    | mk rv rh re =>
      dsimp only at same
      subst rv
      cases le
      cases re
      rfl

instance : BEq Key where
  beq left right := left.value == right.value

instance : LawfulBEq Key where
  rfl := by intro key; change (key.value == key.value) = true; simp
  eq_of_beq := by
    intro left right equal
    apply Key.ext
    change (left.value == right.value) = true at equal
    exact beq_iff_eq.mp equal

instance : Hashable Key where
  hash key := key.fingerprint

instance : DecidableEq Key := fun left right =>
  if same : left.value = right.value then isTrue (Key.ext left right same)
  else isFalse (fun equal => same (congrArg Key.value equal))

@[simp] theorem Key.make_beq (left right : Value) :
    (Key.make left == Key.make right) = (left == right) := rfl

structure Prepared (value : Value) where
  key : Key
  exact : key.value = value
  reused : Bool

/-- Validate the complete current dependency sequence without first allocating
its normalized replacement. Exact references remain literal; a Semantic
reference must name precisely today's representative, including after splits.
Both missing and additional references reject the old calculation. -/
def refsAgree (index : Representatives) : Refs → Refs → Bool
  | .nil, .nil => true
  | .semantic value tail, .semantic observed rest =>
      observed == index.getD value value && refsAgree index tail rest
  | .exact value tail, .exact observed rest =>
      observed == value && refsAgree index tail rest
  | _, _ => false

theorem refsAgree_exact (index : Representatives) (source observed : Refs) :
    refsAgree index source observed = true ↔ observed = normalizeRefs index source := by
  cases source with
  | nil => cases observed <;> simp [refsAgree, normalizeRefs]
  | semantic value tail =>
      cases observed with
      | nil => simp [refsAgree, normalizeRefs]
      | exact observed rest => simp [refsAgree, normalizeRefs]
      | semantic observed rest =>
          simp only [refsAgree, normalizeRefs, Bool.and_eq_true, beq_iff_eq, Refs.semantic.injEq]
          exact and_congr Iff.rfl (refsAgree_exact index tail rest)
  | exact value tail =>
      cases observed with
      | nil => simp [refsAgree, normalizeRefs]
      | semantic observed rest => simp [refsAgree, normalizeRefs]
      | exact observed rest =>
          simp only [refsAgree, normalizeRefs, Bool.and_eq_true, beq_iff_eq, Refs.exact.injEq]
          exact and_congr Iff.rfl (refsAgree_exact index tail rest)

/-- A position nominates an old signature, but never authorizes it. Check
operator, authority and every current child before reusing its cached hash. -/
def signatureAgrees (index : Representatives) : Value → Value → Bool
  | .atom source, .atom observed => decide (observed = source)
  | .apply operator source, .apply observedOperator observed =>
      decide (observedOperator = operator) && refsAgree index source observed
  | _, _ => false

theorem signatureAgrees_exact (index : Representatives) (source observed : Value) :
    signatureAgrees index source observed = true ↔ observed = signature index source := by
  cases source <;> cases observed <;>
    simp [signatureAgrees, signature, refsAgree_exact]

/-- The hit path checks current dependencies and returns the existing key.
Only a miss builds and hashes a fresh structural signature. Its dependent
result certifies the entire signature for arbitrary previous metadata. -/
def prepareSignature (previous : Option Key) (index : Representatives) (source : Value) :
    Prepared (signature index source) :=
  match previous with
  | some key =>
      if same : signatureAgrees index source key.value = true then
        ⟨key, (signatureAgrees_exact index source key.value).mp same, true⟩
      else ⟨Key.make (signature index source), rfl, false⟩
  | none => ⟨Key.make (signature index source), rfl, false⟩

theorem Prepared.canonical (prepared : Prepared value) : prepared.key = Key.make value :=
  Key.ext prepared.key (Key.make value) prepared.exact

abbrev Seen := Std.HashMap Key Value

def Agree (cached : Seen) (reference : Representatives) : Prop :=
  ∀ value, cached[Key.make value]? = reference[value]?

theorem agree_insert (cached : Seen) (reference : Representatives)
    (agree : Agree cached reference) (key value : Value) :
    Agree (cached.insert (Key.make key) value) (reference.insert key value) := by
  intro query
  simp only [Std.HashMap.getElem?_insert, Key.make_beq, agree query]

def keyedStep (state : Seen × RawPartition) (key : Key) (value : Value) :
    Seen × RawPartition :=
  match state.1[key]? with
  | some prior => (state.1, merge state.2 prior value)
  | none => (state.1.insert key value, state.2)

theorem keyedStep_exact (index : Representatives) (cached : Seen × RawPartition)
    (reference : Representatives × RawPartition) (partition : cached.2 = reference.2)
    (agree : Agree cached.1 reference.1) (key : Key) (value : Value)
    (exact : key.value = signature index value) :
    (keyedStep cached key value).2 = (congruenceStep index reference value).2 ∧
      Agree (keyedStep cached key value).1 (congruenceStep index reference value).1 := by
  have canonical : key = Key.make (signature index value) := Key.ext _ _ exact
  simp only [keyedStep, canonical, congruenceStep]
  rw [agree (signature index value)]
  cases found : reference.1[signature index value]? with
  | none => exact ⟨partition, agree_insert cached.1 reference.1 agree _ value⟩
  | some prior => exact ⟨congrArg (fun p => merge p prior value) partition, agree⟩

abbrev Row := Key × Value

def rows (index : Representatives) (values : List Value) : List Row :=
  values.filterMap fun value => match value with
    | .atom _ => none
    | .apply .. => some (Key.make (signature index value), value)

structure Rows (index : Representatives) (values : List Value) where
  rows : List Row
  exact : rows = CongruenceMemo.rows index values
  reused : Nat
  computed : Nat

/-- The source Value is part of every row. Two different applications whose
normalized signatures coincide cannot silently exchange cached instructions. -/
def prepareRows (previous : List Key) (index : Representatives) :
    (values : List Value) → Rows index values
  | [] => ⟨[], rfl, 0, 0⟩
  | value :: values => match value with
    | .atom _ =>
        let rest := prepareRows previous index values
        ⟨rest.rows, rest.exact, rest.reused, rest.computed⟩
    | .apply operator arguments =>
        let value := Value.apply operator arguments
        let prepared := prepareSignature previous.head? index value
        let rest := prepareRows previous.tail index values
        ⟨(prepared.key, value) :: rest.rows,
          by simp only [rows, List.filterMap_cons]; rw [prepared.canonical, rest.exact]; rfl,
          rest.reused + if prepared.reused then 1 else 0,
          rest.computed + if prepared.reused then 0 else 1⟩

def instructions (seen : Seen) : List Row → List (Option Value)
  | [] => []
  | (key, value) :: rows =>
      let prior := seen[key]?
      let next := if prior.isSome then seen else seen.insert key value
      prior :: instructions next rows

/-- A compiled join script has a producer certificate, not an assumed cached
output. It covers all ordered rows, including new and formerly negative keys. -/
structure Script (seen : Seen) (rows : List Row) where
  instructions : List (Option Value)
  exact : instructions = CongruenceMemo.instructions seen rows
  reused : Nat := 0
  computed : Nat := 0

def Script.make (seen : Seen) (rows : List Row) : Script seen rows :=
  ⟨CongruenceMemo.instructions seen rows, rfl, 0, rows.length⟩

/-- Rebuildable disk hints have no producer proof attached. Validate once
against their entire recorded dependency sequence before exposing a Script. -/
def Script.check? (seen : Seen) (rows : List Row) (observed : List (Option Value)) :
    Option (Script seen rows) :=
  if exact : observed = CongruenceMemo.instructions seen rows then
    some ⟨observed, exact, 0, rows.length⟩ else none

theorem Script.wrong_instructions_rejected (seen : Seen) (rows : List Row)
    (observed : List (Option Value))
    (wrong : observed ≠ CongruenceMemo.instructions seen rows) :
    Script.check? seen rows observed = none := by
  simp [check?, wrong]

def advanceSeen (seen : Seen) (row : Row) (prior : Option Value) : Seen :=
  if prior.isSome then seen else seen.insert row.1 row.2

theorem advanceSeen_outside (seen : Seen) (row : Row) (prior : Option Value) (key : Key)
    (different : key ≠ row.1) : (advanceSeen seen row prior)[key]? = seen[key]? := by
  unfold advanceSeen
  split
  · rfl
  · simp [Std.HashMap.getElem?_insert, Ne.symm different]

/-- Only keys touched by a changed row can have different earliest sources.
The former seen map is a proof index, not a second runtime table. -/
structure ChangedKeys (old current : Seen) where
  keys : Std.HashMap Key Unit
  agrees : ∀ key, keys.contains key = false → old[key]? = current[key]?

def changedAfter (keys : Std.HashMap Key Unit) (before row : Row) : Std.HashMap Key Unit :=
  if before = row then keys else (keys.insert before.1 ()).insert row.1 ()

def ChangedKeys.advance (scope : ChangedKeys old current) (before row : Row)
    (oldPrior prior : Option Value) (oldHead : oldPrior = old[before.1]?)
    (head : prior = current[row.1]?) :
    ChangedKeys (advanceSeen old before oldPrior) (advanceSeen current row prior) :=
  if same : before = row then
    ⟨scope.keys, by
      subst before
      intro key outside
      by_cases atRow : key = row.1
      · subst key
        have equal : oldPrior = prior := oldHead.trans ((scope.agrees row.1 outside).trans head.symm)
        rw [equal]
        cases prior with
        | none => simp [advanceSeen]
        | some value => simpa only [advanceSeen, Option.isSome_some, ↓reduceIte]
            using scope.agrees row.1 outside
      · rw [advanceSeen_outside _ _ _ _ atRow, advanceSeen_outside _ _ _ _ atRow]
        exact scope.agrees key outside⟩
  else
    ⟨(scope.keys.insert before.1 ()).insert row.1 (), by
      intro key outside
      have separated : key ≠ row.1 ∧ key ≠ before.1 ∧ scope.keys.contains key = false := by
        simp only [Std.HashMap.contains_insert] at outside
        have rowAbsent := (Bool.or_eq_false_iff.mp outside).1
        have rest := Bool.or_eq_false_iff.mp (Bool.or_eq_false_iff.mp outside).2
        have beforeAbsent := rest.1
        refine ⟨?_, ?_, rest.2⟩
        · intro same
          subst key
          simp at rowAbsent
        · intro same
          subst key
          simp at beforeAbsent
      rw [advanceSeen_outside _ _ _ _ separated.2.1,
        advanceSeen_outside _ _ _ _ separated.1]
      exact scope.agrees key separated.2.2⟩

theorem ChangedKeys.advance_keys (scope : ChangedKeys old current) (before row : Row)
    (oldPrior prior : Option Value) (oldHead : oldPrior = old[before.1]?)
    (head : prior = current[row.1]?) :
    (scope.advance before row oldPrior prior oldHead head).keys =
      changedAfter scope.keys before row := by
  unfold ChangedKeys.advance changedAfter
  split <;> rfl

/-- Package the former prefix state exclusively in a proposition. Keeping it
as a recursive value argument would cause the compiler to rebuild a second
seen table even though only the dependency invariant requires it. -/
structure ReplayState (current : Seen) (old : List Row) where
  hints : List (Option Value)
  changed : Std.HashMap Key Unit
  valid : ∃ previous : Seen, hints = instructions previous old ∧
    ∀ key, changed.contains key = false → previous[key]? = current[key]?

def ReplayState.start (seen : Seen) (old : List Row) (script : Script seen old) :
    ReplayState seen old := ⟨script.instructions, {}, ⟨seen, script.exact, by intro _ _; rfl⟩⟩

def ReplayState.next (state : ReplayState current (before :: old)) (row : Row)
    (prior : Option Value) (head : prior = current[row.1]?) :
    ReplayState (advanceSeen current row prior) old :=
  ⟨state.hints.tail, changedAfter state.changed before row, by
    rcases state.valid with ⟨previous, original, agree⟩
    let oldPrior := state.hints.headD none
    have oldHead : oldPrior = previous[before.1]? := by
      dsimp only [oldPrior]
      rw [original]
      cases before
      rfl
    let next := advanceSeen previous before oldPrior
    let scope : ChangedKeys previous current := ⟨state.changed, agree⟩
    let advanced := scope.advance before row oldPrior prior oldHead head
    refine ⟨next, ?_, ?_⟩
    · rw [original]
      dsimp only [next, advanceSeen]
      rw [oldHead]
      cases before
      rfl
    · intro key outside
      apply advanced.agrees key
      rw [scope.advance_keys before row oldPrior prior oldHead head]
      exact outside⟩

/-- Repair the affected signature keys, including negative first occurrences.
An unchanged row after a correction can still reuse its prior instruction
when none of its signature dependencies changed. No old partition survives
retraction; only current-row instructions obtain the exact producer proof. -/
def Script.repairFrom (currentSeen : Seen) (old : List Row)
    (state : ReplayState currentSeen old) :
    (current : List Row) → Script currentSeen current
  | [] => ⟨[], rfl, 0, 0⟩
  | row :: current => match old with
    | [] => Script.make currentSeen (row :: current)
    | before :: old =>
        let oldPrior := state.hints.headD none
        let reused := decide (before = row) && !state.changed.contains row.1
        let prior := if reused then oldPrior else currentSeen[row.1]?
        have head : prior = currentSeen[row.1]? := by
          dsimp only [prior]
          split
          · rename_i allowed
            have same : before = row ∧ state.changed.contains row.1 = false := by
              have parts : before = row ∧ (!state.changed.contains row.1) = true := by
                simpa only [reused, Bool.and_eq_true, decide_eq_true_eq] using allowed
              refine ⟨parts.1, ?_⟩
              cases absent : state.changed.contains row.1
              · rfl
              · simp [absent] at parts
            rcases state.valid with ⟨previous, original, agree⟩
            have oldHead : oldPrior = previous[before.1]? := by
              dsimp only [oldPrior]
              rw [original]
              cases before
              rfl
            rw [oldHead, same.1, agree row.1 same.2]
          · rfl
        let next := advanceSeen currentSeen row prior
        let advanced := state.next row prior head
        let rest := Script.repairFrom next old advanced current
        ⟨prior :: rest.instructions, by
          rw [rest.exact]
          dsimp only [next, advanceSeen]
          rw [head]
          cases row
          rfl,
          rest.reused + if reused then 1 else 0,
          rest.computed + if reused then 0 else 1⟩

def Script.repair (seen : Seen) (old : List Row) (script : Script seen old)
    (current : List Row) : Script seen current :=
  Script.repairFrom seen old (ReplayState.start seen old script) current

structure Entry where
  rows : List Row
  script : Script {} rows

def prepareScript (previous : Option Entry) (rows : List Row) : Script {} rows :=
  match previous with
  | none => Script.make {} rows
  | some previous => previous.script.repair {} previous.rows rows

def applyInstructions : List Row → List (Option Value) → RawPartition → RawPartition
  | [], _, partition => partition
  | _, [], partition => partition
  | (_, value) :: rows, prior :: instructions, partition =>
      applyInstructions rows instructions (match prior with
        | none => partition
        | some prior => merge partition prior value)

theorem apply_compiled (seen : Seen) (rows : List Row) (partition : RawPartition) :
    applyInstructions rows (instructions seen rows) partition =
      (rows.foldl (fun state row => keyedStep state row.1 row.2) (seen, partition)).2 := by
  induction rows generalizing seen partition with
  | nil => rfl
  | cons row rows ih =>
      rcases row with ⟨key, value⟩
      cases found : seen[key]? <;>
        simp [instructions, applyInstructions, found, keyedStep, ih]

theorem rows_fold (index : Representatives) (values : List Value)
    (state : Seen × RawPartition) (reference : Representatives × RawPartition)
    (partition : state.2 = reference.2) (agree : Agree state.1 reference.1) :
    ((rows index values).foldl (fun state row => keyedStep state row.1 row.2) state).2 =
      (values.foldl (applicationStep index) reference).2 ∧
    Agree ((rows index values).foldl (fun state row => keyedStep state row.1 row.2) state).1
      (values.foldl (applicationStep index) reference).1 := by
  induction values generalizing state reference with
  | nil => exact ⟨partition, agree⟩
  | cons value values ih =>
      cases value with
      | atom bytes =>
          simpa only [rows, List.filterMap_cons, List.foldl_cons, applicationStep] using
            ih state reference partition agree
      | apply operator arguments =>
          let value := Value.apply operator arguments
          have next := keyedStep_exact index state reference partition agree
            (Key.make (signature index value)) value rfl
          simpa only [rows, List.filterMap_cons, List.foldl_cons] using
            ih (keyedStep state (Key.make (signature index value)) value)
              (applicationStep index reference value) next.1 next.2

structure Pass where
  partition : RawPartition
  keys : List Key
  reused : Nat
  computed : Nat
  plan : Entry

/-- One generation of signature metadata is retained, not a copy of the
partition per application or all historical representative maps. -/
def pass (previous : List Key) (values : List Value) (partition : RawPartition)
    (previousPlan : Option Entry := none) : Pass :=
  let prepared := prepareRows previous (representatives partition) values
  let script := prepareScript previousPlan prepared.rows
  ⟨applyInstructions prepared.rows script.instructions partition,
    prepared.rows.map Prod.fst, prepared.reused, prepared.computed, ⟨prepared.rows, script⟩⟩

/-- Exact ordered classes for arbitrary Values and arbitrary incoming
partitions. No atom-only assumption, digest injectivity or stale output
equivalence premise is required. A miss cannot omit a newly added key. -/
theorem pass_exact (previous : List Key) (values : List Value) (partition : RawPartition)
    (previousPlan : Option Entry := none) :
    (pass previous values partition previousPlan).partition = congruencePass values partition := by
  simp only [pass, (prepareScript _ _).exact, apply_compiled,
    (prepareRows _ _ _).exact]
  exact (rows_fold (representatives partition) values ({}, partition) ({}, partition)
    rfl (by intro value; simp)).1

end CongruenceMemo

/-- Full scan specification of ordered application congruence. -/
def scanSaturateCongruence (values : List Value) : Nat → RawPartition → RawPartition
  | 0, partition => partition
  | fuel + 1, partition =>
      let next := congruencePass values partition
      if next = partition then partition
      else scanSaturateCongruence values fuel next

structure Saturated where
  partition : RawPartition
  keys : List CongruenceMemo.Key
  plan : Option CongruenceMemo.Entry

/-- The actual saturation interpreter carries only one generation of join
instructions. Every round repairs its demanded current dependency sequence;
an old partition is never imported through this acceleration boundary. -/
def plannedSaturateCongruence (values : List Value) (previous : List CongruenceMemo.Key)
    (plan : Option CongruenceMemo.Entry) :
    Nat → RawPartition → Saturated
  | 0, partition => ⟨partition, previous, plan⟩
  | fuel + 1, partition =>
      let next := CongruenceMemo.pass previous values partition plan
      if next.partition = partition then ⟨partition, next.keys, some next.plan⟩
      else plannedSaturateCongruence values next.keys (some next.plan) fuel next.partition

theorem plannedSaturateCongruence_exact (values : List Value)
    (previous : List CongruenceMemo.Key) (plan : Option CongruenceMemo.Entry)
    (fuel : Nat) (partition : RawPartition) :
    (plannedSaturateCongruence values previous plan fuel partition).partition =
      scanSaturateCongruence values fuel partition := by
  induction fuel generalizing previous plan partition with
  | zero => rfl
  | succ fuel ih =>
      simp only [plannedSaturateCongruence, scanSaturateCongruence,
        CongruenceMemo.pass_exact]
      split
      · rfl
      · exact ih _ _ _

def memoSaturateCongruence (values : List Value) (previous : List CongruenceMemo.Key)
    (fuel : Nat) (partition : RawPartition) : RawPartition :=
  (plannedSaturateCongruence values previous none fuel partition).partition

theorem memoSaturateCongruence_exact (values : List Value)
    (previous : List CongruenceMemo.Key) (fuel : Nat) (partition : RawPartition) :
    memoSaturateCongruence values previous fuel partition =
      scanSaturateCongruence values fuel partition := by
  exact plannedSaturateCongruence_exact values previous none fuel partition

def saturateCongruence (values : List Value) (fuel : Nat) (partition : RawPartition) :
    RawPartition := memoSaturateCongruence values [] fuel partition

@[simp] theorem saturateCongruence_zero (values : List Value) (partition : RawPartition) :
    saturateCongruence values 0 partition = partition := rfl

theorem saturateCongruence_step (values : List Value) (fuel : Nat) (partition : RawPartition) :
    saturateCongruence values (fuel + 1) partition =
      let next := congruencePass values partition
      if next = partition then partition else saturateCongruence values fuel next := by
  simp only [saturateCongruence, memoSaturateCongruence_exact, scanSaturateCongruence]

/-- The original full scan, including Atom signatures, in every round. -/
def referenceSaturateCongruence (values : List Value) : Nat → RawPartition → RawPartition
  | 0, partition => partition
  | fuel + 1, partition =>
      let next := referenceCongruencePass values partition
      if next = partition then partition
      else referenceSaturateCongruence values fuel next

theorem saturateCongruence_reference (values : List Value) (fuel : Nat) (partition : RawPartition) :
    saturateCongruence values fuel partition = referenceSaturateCongruence values fuel partition := by
  induction fuel generalizing partition with
  | zero => rfl
  | succ fuel ih =>
      simp only [saturateCongruence_step, referenceSaturateCongruence, congruencePass_reference, ih]

def certify (partition : RawPartition) : Option Quotient := do
  let classes ← partition.mapM EquivalenceClass.certify?
  let representatives := RepresentativeIndex.build {} classes
  pure {
    classes
    representatives
    exactAuthority := RepresentativeIndex.build_sound
      RepresentativeIndex.empty_sound classes
  }

/-- One ordered closed term domain shared by fresh builds, retained plans and
their persisted dependency basis. Exact children are not substitutable terms. -/
def kernelValues (roots : List Value) (edges : List UnionEdge) : List Value :=
  (roots ++ edges.flatMap (fun edge => edge.left.semanticNodes ++ edge.right.semanticNodes))
    |>.flatMap Value.semanticNodes |> hashDistinct

def referenceBuild? (roots : List Value) (persistent runLocal : List UnionEdge) : Option Quotient :=
  let values := kernelValues roots (persistent ++ runLocal)
  let explicit := mergeExplicit (initial values) (persistent ++ runLocal)
  certify (referenceSaturateCongruence values values.length explicit)

def kernelPartition (roots : List Value) (edges : List UnionEdge) : RawPartition :=
  let values := kernelValues roots edges
  saturateCongruence values values.length (mergeExplicit (initial values) edges)

def congruenceBuild? (roots : List Value) (persistent runLocal : List UnionEdge) : Option Quotient :=
  certify (kernelPartition roots (persistent ++ runLocal))

theorem congruenceBuild_reference (roots : List Value) (persistent runLocal : List UnionEdge) :
    congruenceBuild? roots persistent runLocal = referenceBuild? roots persistent runLocal := by
  simp only [congruenceBuild?, kernelPartition, referenceBuild?, saturateCongruence_reference]

namespace LiteralProof

def SelfIndex (index : RepresentativeIndex.T) : Prop :=
  ∀ value, index.getD value value = value

theorem empty_self : SelfIndex {} := by
  intro value
  simp

theorem insert_self (index : RepresentativeIndex.T) (known : SelfIndex index) (added : Value) :
    SelfIndex (index.insert added added) := by
  intro value
  rw [Std.HashMap.getD_insert]
  split
  · rename_i same
    simpa using same
  · exact known value

theorem fold_self (index : RepresentativeIndex.T) (known : SelfIndex index) (values : List Value) :
    SelfIndex (values.foldl (fun current value => current.insert value value) index) := by
  induction values generalizing index with
  | nil => exact known
  | cons head tail ih => exact ih _ (insert_self index known head)

theorem representatives_self (values : List Value) :
    SelfIndex (representatives (values.map (fun value => [value]))) := by
  simpa [representatives, List.foldl_map] using fold_self {} empty_self values

theorem normalize_self (index : Representatives) (known : SelfIndex index) :
    (refs : Refs) → normalizeRefs index refs = refs
  | .nil => rfl
  | .semantic value rest => by
      rw [normalizeRefs_semantic, known value, normalize_self index known rest]
  | .exact value rest => by
      rw [normalizeRefs_exact, normalize_self index known rest]

theorem signature_self (index : Representatives) (known : SelfIndex index) (value : Value) :
    signature index value = value := by
  cases value with
  | atom _ => rfl
  | apply operator refs => simp [signature, normalize_self index known refs]

theorem found_self (index : Representatives) (known : SelfIndex index) (value prior : Value)
    (found : index.get? value = some prior) : prior = value := by
  have equal := known value
  rw [Std.HashMap.getD_eq_getD_getElem?] at equal
  simpa [show index[value]? = some prior from found] using equal

theorem merge_self (partition : RawPartition) (value : Value) :
    merge partition value value = partition := by simp [merge, same]

theorem pass_fold (index seen : Representatives) (known : SelfIndex index)
    (seenSelf : SelfIndex seen) (partition : RawPartition) (values : List Value) :
    (values.foldl (fun (state : Representatives × RawPartition) value =>
      match state.1.get? (signature index value) with
      | some prior => (state.1, merge state.2 prior value)
      | none => (state.1.insert (signature index value) value, state.2))
        (seen, partition)).2 = partition := by
  induction values generalizing seen with
  | nil => rfl
  | cons value tail ih =>
    simp only [List.foldl_cons, signature_self index known value]
    cases found : seen.get? value with
    | none =>
      exact ih _ (insert_self seen seenSelf value)
    | some prior =>
      have equal := found_self seen seenSelf value prior found
      subst prior
      simp only [merge_self]
      exact ih seen seenSelf

theorem pass_singletons (values members : List Value) :
    congruencePass values (members.map (fun value => [value])) =
      members.map (fun value => [value]) := by
  rw [congruencePass_reference]
  exact pass_fold _ {} (representatives_self members) empty_self _ values

theorem saturation_singletons (values members : List Value) (fuel : Nat) :
    saturateCongruence values fuel (members.map (fun value => [value])) =
      members.map (fun value => [value]) := by
  cases fuel with
  | zero => rfl
  | succ fuel => simp [saturateCongruence_step, pass_singletons]

def singleton (value : Value) : EquivalenceClass := {
  representative := value
  members := [value]
  exactAuthority := by
    intro member present
    have equal := List.mem_singleton.mp present
    subst member
    exact Value.sameExactFootprint_refl value
}

theorem certify_singleton (value : Value) :
    EquivalenceClass.certify? [value] = some (singleton value) := by
  have reflexive : Value.sameExactFootprint value value = true := by
    simp [Value.sameExactFootprint, List.all_eq_true]
  simp [EquivalenceClass.certify?, reflexive, singleton]

theorem singleton_index (index : RepresentativeIndex.T) (known : SelfIndex index)
    (values : List Value) :
    SelfIndex (RepresentativeIndex.build index (values.map singleton)) := by
  induction values generalizing index with
  | nil => exact known
  | cons head tail ih =>
    simp only [List.map_cons, RepresentativeIndex.build, singleton,
      RepresentativeIndex.insertMembers]
    exact ih _ (insert_self index known head)

def singletonQuotient (values : List Value) : Quotient := {
  classes := values.map singleton
  representatives := RepresentativeIndex.build {} (values.map singleton)
  exactAuthority := RepresentativeIndex.build_sound RepresentativeIndex.empty_sound _
}

theorem certify_singletons (values : List Value) :
    certify (values.map (fun value => [value])) = some (singletonQuotient values) := by
  have classes : (values.map (fun value => [value])).mapM EquivalenceClass.certify? =
      some (values.map singleton) := by
    induction values with
    | nil => rfl
    | cons head tail ih => simp [certify_singleton, ih]
  simp [certify, classes, singletonQuotient]

end LiteralProof

/-- The full pre-optimization algorithm succeeds with no edges and its
representative map is identity for EVERY Value, including unseen values.
No candidate-completeness or final-result-equality assumption is used. -/
theorem reference_without_unions (roots : List Value) :
    ∃ quotient, referenceBuild? roots [] [] = some quotient ∧
      ∀ value, quotient.canonical value = value := by
  unfold referenceBuild?
  simp only [kernelValues, List.append_nil, List.flatMap_nil, mergeExplicit, List.foldl_nil, initial]
  rw [← saturateCongruence_reference, LiteralProof.saturation_singletons, LiteralProof.certify_singletons]
  exact ⟨_, rfl, LiteralProof.singleton_index {} LiteralProof.empty_self _⟩

def build? (roots : List Value) (persistent runLocal : List UnionEdge) : Option Quotient :=
  if persistent.isEmpty && runLocal.isEmpty then some Quotient.literal
  else congruenceBuild? roots persistent runLocal

/-- A rebuild starts from today's explicit edges. A retained script can save
join discovery, but cannot import yesterday's partition after a retraction. -/
structure PlannedBuild (roots : List Value) (persistent runLocal : List UnionEdge) where
  quotient : Option Quotient
  plan : Option CongruenceMemo.Entry
  exact : quotient = build? roots persistent runLocal

def plannedBuild? (roots : List Value) (persistent runLocal : List UnionEdge)
    (previous : Option CongruenceMemo.Entry) : PlannedBuild roots persistent runLocal :=
  if empty : persistent.isEmpty && runLocal.isEmpty then
    ⟨some Quotient.literal, none, by simp [build?, empty]⟩
  else
    let values := kernelValues roots (persistent ++ runLocal)
    let explicit := mergeExplicit (initial values) (persistent ++ runLocal)
    let result := plannedSaturateCongruence values
      (previous.map (fun plan => plan.rows.map Prod.fst) |>.getD []) previous values.length explicit
    ⟨certify result.partition, result.plan, by
      simp only [build?, empty, Bool.false_eq_true, ↓reduceIte, congruenceBuild?, kernelPartition]
      rw [plannedSaturateCongruence_exact]
      simp only [saturateCongruence, memoSaturateCongruence_exact]
      rfl⟩

theorem plannedBuild_exact (roots : List Value) (persistent runLocal : List UnionEdge)
    (previous : Option CongruenceMemo.Entry) :
    (plannedBuild? roots persistent runLocal previous).quotient = build? roots persistent runLocal :=
  (plannedBuild? roots persistent runLocal previous).exact

theorem build_without_unions (roots : List Value) :
    build? roots [] [] = some Quotient.literal := rfl

theorem empty_build_preserves_canonical (roots : List Value) :
    ∃ previous, referenceBuild? roots [] [] = some previous ∧
      ∀ value, Quotient.literal.canonical value = previous.canonical value := by
  obtain ⟨previous, found, exact⟩ := reference_without_unions roots
  exact ⟨previous, found, fun value => (Quotient.literal_canonical value).trans (exact value).symm⟩

/-- This is equality of the actual kernel input, not just of a sampled
set of queries. Extraction therefore keeps its complete ordered result. -/
theorem empty_build_preserves_equality (roots : List Value) :
    ∃ previous, referenceBuild? roots [] [] = some previous ∧
      Quotient.literal.toEquality = previous.toEquality := by
  obtain ⟨previous, found, same⟩ := empty_build_preserves_canonical roots
  exact ⟨previous, found, Quotient.equality_of_canonical _ _ (funext same)⟩

theorem empty_build_preserves_extraction (roots : List Value) (graph : WorkGraph)
    (policy : OutcomePolicy) (work : Value) :
    (build? roots [] []).map (fun quotient =>
      Extract.runWithPolicy graph quotient.toEquality policy work) =
    (referenceBuild? roots [] []).map (fun quotient =>
      Extract.runWithPolicy graph quotient.toEquality policy work) := by
  obtain ⟨previous, found, same⟩ := empty_build_preserves_equality roots
  simp only [build_without_unions, found, Option.map_some, same]

theorem build_with_unions (roots : List Value) (persistent runLocal : List UnionEdge)
    (present : persistent ≠ [] ∨ runLocal ≠ []) :
    build? roots persistent runLocal = referenceBuild? roots persistent runLocal := by
  cases persistent <;> cases runLocal <;> simp_all [build?, congruenceBuild_reference]

/-- Even a heuristic Union producer cannot make the checked quotient cross Exact authority. -/
theorem build_equality_preserves_exact {roots persistent runLocal quotient}
    (_built : build? roots persistent runLocal = some quotient)
    {left right : Value} (same : quotient.toEquality.same left right) :
    Value.SameExactFootprint left right := by
  exact quotient.equality_preserves_exact same

end QuotientBuilder

/-- One run owns speculative equality; the durable graph is immutable here. -/
structure RunView where
  graph : WorkGraph
  quotient : Quotient
  localUnions : List UnionEdge

namespace RunView

def make? (graph : WorkGraph) (roots : List Value)
    (persistent runEdges : List UnionEdge) : Option RunView := do
  let quotient ← QuotientBuilder.build? roots persistent runEdges
  pure { graph, quotient, localUnions := runEdges }

def extract (view : RunView) (root : Value) : Extraction :=
  Extract.run view.graph view.quotient.toEquality root

def extractWith (view : RunView) (policy : OutcomePolicy) (root : Value) : Extraction :=
  Extract.runWithPolicy view.graph view.quotient.toEquality policy root

/-- Adding local identity cannot mutate durable graph facts by construction. -/
@[simp]
theorem graph_is_immutable (view : RunView) : view.graph = view.graph := rfl

end RunView

end Eggshell
