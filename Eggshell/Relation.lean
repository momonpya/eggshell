module

public import Eggshell.Union

@[expose] public section

namespace Eggshell

def maxOutcomeObservations : Nat := 1024

namespace Relation

def semanticValues {α : Type} : List (Authority × α) → Option (List α)
  | [] => some []
  | (.semantic, value) :: tail => (value :: ·) <$> semanticValues tail
  | (.exact, _) :: _ => none

theorem semanticValues_sound {α : Type} {references : List (Authority × α)} {values : List α}
    (decoded : semanticValues references = some values) :
    references = values.map (Authority.semantic, ·) := by
  induction references generalizing values with
  | nil => simp [semanticValues] at decoded; simp [decoded]
  | cons head tail induction =>
      rcases head with ⟨authority, value⟩
      cases authority with
      | exact => simp [semanticValues] at decoded
      | semantic =>
          simp only [semanticValues] at decoded
          cases decodedTail : semanticValues tail with
          | none => simp [decodedTail] at decoded
          | some tailValues =>
              simp [decodedTail] at decoded
              subst values
              simp [induction decodedTail]

def exactValues {α : Type} : List (Authority × α) → Option (List α)
  | [] => some []
  | (.exact, value) :: tail => (value :: ·) <$> exactValues tail
  | (.semantic, _) :: _ => none

theorem exactValues_sound {α : Type} {references : List (Authority × α)} {values : List α}
    (decoded : exactValues references = some values) :
    references = values.map (Authority.exact, ·) := by
  induction references generalizing values with
  | nil => simp [exactValues] at decoded; simp [decoded]
  | cons head tail induction =>
      rcases head with ⟨authority, value⟩
      cases authority with
      | semantic => simp [exactValues] at decoded
      | exact =>
          simp only [exactValues] at decoded
          cases decodedTail : exactValues tail with
          | none => simp [decodedTail] at decoded
          | some tailValues =>
              simp [decodedTail] at decoded
              subst values
              simp [induction decodedTail]

def splitOccurrence {α : Type} : List (Authority × α) → Option (List α × List α)
  | [] => none
  | references =>
      let semantic := references.takeWhile (fun reference => reference.1 == .semantic)
      let exact := references.drop semantic.length
      match semanticValues semantic, exactValues exact with
      | some [], _ => none
      | some meanings, some occurrences => some (meanings, occurrences)
      | _, _ => none

theorem semanticValues_map {α β : Type} (f : α → β) (references : List (Authority × α)) :
    semanticValues (references.map fun ref => (ref.1, f ref.2)) =
      (semanticValues references).map (List.map f) := by
  induction references with
  | nil => rfl
  | cons head tail ih =>
      rcases head with ⟨authority, value⟩
      cases authority <;> simp [semanticValues, ih, Option.map_map, Function.comp_def]

theorem exactValues_map {α β : Type} (f : α → β) (references : List (Authority × α)) :
    exactValues (references.map fun ref => (ref.1, f ref.2)) =
      (exactValues references).map (List.map f) := by
  induction references with
  | nil => rfl
  | cons head tail ih =>
      rcases head with ⟨authority, value⟩
      cases authority <;> simp [exactValues, ih, Option.map_map, Function.comp_def]

/-- Reading payload values cannot change observation orientation or authority
positions. The same parser is used on persisted ids and resolved Values. -/
theorem splitOccurrence_map {α β : Type} (f : α → β) (references : List (Authority × α)) :
    splitOccurrence (references.map fun ref => (ref.1, f ref.2)) =
      (splitOccurrence references).map (fun pair => (pair.1.map f, pair.2.map f)) := by
  cases references with
  | nil => rfl
  | cons head tail =>
      simp only [List.map_cons, splitOccurrence]
      have leading :
          ((head.1, f head.2) :: tail.map (fun ref => (ref.1, f ref.2))).takeWhile
            (fun ref => ref.1 == .semantic) =
          ((head :: tail).takeWhile (fun ref => ref.1 == .semantic)).map
            (fun ref => (ref.1, f ref.2)) := by
        change ((head :: tail).map (fun ref => (ref.1, f ref.2))).takeWhile _ = _
        exact List.takeWhile_map
      have suffix (count : Nat) :
          ((head.1, f head.2) :: tail.map (fun ref => (ref.1, f ref.2))).drop count =
          ((head :: tail).drop count).map (fun ref => (ref.1, f ref.2)) := by
        simpa only [List.map_cons] using
          (List.map_drop (f := fun ref : Authority × α => (ref.1, f ref.2))
            (l := head :: tail) (i := count)).symm
      rw [leading, List.length_map, suffix, semanticValues_map, exactValues_map]
      cases sem : semanticValues ((head :: tail).takeWhile (fun ref => ref.1 == .semantic)) with
      | none => simp
      | some meanings =>
          cases meanings with
          | nil => simp
          | cons first rest =>
              cases exact : exactValues ((head :: tail).drop
                ((head :: tail).takeWhile (fun ref => ref.1 == .semantic)).length) <;> simp

def observesOutcomeWork (outcome work : Value) : Value → Bool
  | .apply .occurrence arguments =>
      match splitOccurrence arguments.toList with
      | some ([observed, invoked], _) => observed == outcome && invoked == work
      | _ => false
  | _ => false

def validArguments : Operator → List Ref → Bool
  | .all, (.semantic, parent) :: children =>
      !children.isEmpty && children.all fun reference =>
        reference.1 == .semantic && reference.2 != parent
  | .outcome, (.semantic, _) :: (.semantic, _) :: observations =>
      observations.length ≤ maxOutcomeObservations &&
        (exactValues observations).isSome && decide observations.Nodup
  | .occurrence, arguments => (splitOccurrence arguments).isSome
  | .inquiry,
      (.exact, _) :: (.exact, _) :: (.semantic, _) ::
        (.exact, _) :: (.exact, _) :: (.exact, _) :: _ => true
  | .receipt, arguments => 7 ≤ arguments.length && (exactValues arguments).isSome
  | _, _ => false

def apply? (operator : Operator) (arguments : List Ref) : Option Value :=
  if validArguments operator arguments then
    some (.applyList operator arguments)
  else
    none

theorem apply?_sound {operator arguments value}
    (accepted : apply? operator arguments = some value) :
    value = .applyList operator arguments ∧ validArguments operator arguments := by
  unfold apply? at accepted
  split at accepted
  case isTrue valid =>
    simp only [Option.some.injEq] at accepted
    exact ⟨accepted.symm, by simpa using valid⟩
  case isFalse => simp at accepted

theorem apply?_complete {operator arguments}
    (valid : validArguments operator arguments) :
    apply? operator arguments = some (.applyList operator arguments) := by
  simp [apply?, valid]

mutual

/-- Every stored constructor and every structurally nested constructor is valid. -/
def wellFormed : Value → Bool
  | .atom _ => true
  | .apply operator arguments =>
      validArguments operator arguments.toList && refsWellFormed arguments

def refsWellFormed : Refs → Bool
  | .nil => true
  | .semantic value tail | .exact value tail =>
      wellFormed value && refsWellFormed tail

end

@[simp]
theorem atom_wellFormed (bytes : ByteArray) : wellFormed (.atom bytes) := rfl

end Relation

structure AllEdge where
  relation : Value
  parent : Value
  children : List Value
  children_nonempty : children ≠ []
  excludes_parent : parent ∉ children
  relation_eq : relation = .applyList .all
    ((.semantic, parent) :: children.map Ref.semantic)

structure OutcomeEdge where
  relation : Value
  work : Value
  outcome : Value
  observations : List Value
  observations_nodup : observations.Nodup
  observation_bound : observations.length ≤ maxOutcomeObservations
  relation_eq : relation = .applyList .outcome
    ((.semantic, work) :: (.semantic, outcome) :: observations.map Ref.exact)

deriving instance DecidableEq for AllEdge, OutcomeEdge

namespace AllEdge

def make (parent : Value) (children : List Value)
    (children_nonempty : children ≠ [])
    (excludes_parent : parent ∉ children) : AllEdge where
  relation := .applyList .all
    ((.semantic, parent) :: children.map Ref.semantic)
  parent
  children
  children_nonempty
  excludes_parent
  relation_eq := rfl

@[simp]
theorem make_parent (parent children nonempty excludes) :
    (make parent children nonempty excludes).parent = parent := rfl

@[simp]
theorem make_children (parent children nonempty excludes) :
    (make parent children nonempty excludes).children = children := rfl

def fromValue? : Value → Option AllEdge
  | .apply .all arguments =>
      match argumentList : arguments.toList with
      | (.semantic, parent) :: encodedChildren =>
          match decoded : Relation.semanticValues encodedChildren with
          | some children =>
              if nonempty : children ≠ [] then
                if excludes : parent ∉ children then
                  some {
                    relation := .apply .all arguments
                    parent
                    children
                    children_nonempty := nonempty
                    excludes_parent := excludes
                    relation_eq := by
                      apply congrArg (Value.apply .all)
                      rw [← Refs.ofList_toList arguments]
                      rw [argumentList]
                      simp only [Refs.ofList]
                      rw [Relation.semanticValues_sound decoded]
                      rfl
                  }
                else none
              else none
          | none => none
      | _ => none
  | _ => none

end AllEdge

namespace OutcomeEdge

def make (work outcome : Value) (observations : List Value)
    (observations_nodup : observations.Nodup)
    (observation_bound : observations.length ≤ maxOutcomeObservations) : OutcomeEdge where
  relation := .applyList .outcome
    ((.semantic, work) :: (.semantic, outcome) :: observations.map Ref.exact)
  work
  outcome
  observations
  observations_nodup
  observation_bound
  relation_eq := rfl

def fromValue? : Value → Option OutcomeEdge
  | .apply .outcome arguments =>
      match argumentList : arguments.toList with
      | (.semantic, work) :: (.semantic, outcome) :: encodedObservations =>
          match decoded : Relation.exactValues encodedObservations with
          | some observations =>
              if nodup : observations.Nodup then
                if bound : observations.length ≤ maxOutcomeObservations then
                  some {
                    relation := .apply .outcome arguments
                    work
                    outcome
                    observations
                    observations_nodup := nodup
                    observation_bound := bound
                    relation_eq := by
                      apply congrArg (Value.apply .outcome)
                      rw [← Refs.ofList_toList arguments]
                      rw [argumentList]
                      simp only [Refs.ofList]
                      rw [Relation.exactValues_sound decoded]
                      rfl
                  }
                else none
              else none
          | none => none
      | _ => none
  | _ => none

end OutcomeEdge

end Eggshell
