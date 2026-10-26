module
public import Std.Data.HashMap
public import Std.Data.HashSet.Lemmas
@[expose] public section

/- Content correspondence has no command, file-system, Work, Match or Union
input. A capture adapter must supply verified acquired input records and retain
their identities. This module proves equality of content at actual positions;
it does not turn a matching string into an execution or freshness certificate. -/
namespace ContentCorrespondence

abbrev Inputs := Array (Array String)
abbrev Position := Nat × Nat
variable {inputs : Inputs}

def positions (inputs : Inputs) : List Position :=
  (List.finRange inputs.size).flatMap fun source =>
    (List.finRange inputs[source].size).map fun row => (source.val,row.val)

theorem position_present (source : Fin inputs.size) (row : Fin inputs[source].size) :
    (source.val,row.val) ∈ positions inputs := by
  apply List.mem_flatMap.mpr
  refine ⟨source,by simp,?_⟩
  exact List.mem_map.mpr ⟨row,by simp,rfl⟩

def textAt (inputs : Inputs) (position : Position) : String :=
  ((inputs[position.1]?).bind fun rows => rows[position.2]?).getD ""

@[simp] theorem textAt_present (source : Fin inputs.size) (row : Fin inputs[source].size) :
    textAt inputs (source.val,row.val) = inputs[source][row] := by
  simp [textAt]

structure Correspondence (inputs : Inputs) (text : String) (position : Position) : Type where
  sourceBound : position.1 < inputs.size
  rowBound : position.2 < (inputs[position.1]'sourceBound).size
  original : (inputs[position.1]'sourceBound)[position.2]'rowBound = text

def check? (inputs : Inputs) (text : String) (position : Position) :
    Option (Correspondence inputs text position) :=
  if sourceBound : position.1 < inputs.size then
    if rowBound : position.2 < inputs[position.1].size then
      if original : inputs[position.1][position.2] = text then
        some ⟨sourceBound,rowBound,original⟩ else none
    else none
  else none

abbrev Buckets := Std.HashMap String (Std.HashSet Position)

def bucket (buckets : Buckets) (text : String) : Std.HashSet Position :=
  buckets[text]?.getD {}

/-- The one-time completeness check permits safe absence/ambiguity decisions.
Hash collisions never suffice: the map key is the full original string. -/
def complete (inputs : Inputs) (buckets : Buckets) : Bool :=
  (positions inputs).all fun position => (bucket buckets (textAt inputs position)).contains position

structure Index (inputs : Inputs) where
  buckets : Buckets
  complete : complete inputs buckets = true

def checkedIndex? (inputs : Inputs) (buckets : Buckets) : Option (Index inputs) :=
  if checked : complete inputs buckets = true then some ⟨buckets,checked⟩ else none

def prepare? (inputs : Inputs) : Option (Index inputs) := Id.run do
  let mut buckets : Buckets := {}
  for position in positions inputs do
    let text := textAt inputs position
    buckets := buckets.insert text ((bucket buckets text).insert position)
  return checkedIndex? inputs buckets

theorem Index.contains_original (index : Index inputs) (source : Fin inputs.size)
    (row : Fin inputs[source].size) (text : String) (same : inputs[source][row] = text) :
    (bucket index.buckets text).contains (source.val,row.val) = true := by
  have present := List.all_eq_true.mp index.complete (source.val,row.val) (position_present source row)
  simpa only [textAt_present,same] using present

structure Unique (index : Index inputs) (text : String) where
  position : Position
  correspondence : Correspondence inputs text position
  only : (bucket index.buckets text).toList = [position]

def Index.unique? (index : Index inputs) (text : String) : Option (Unique index text) :=
  match found : (bucket index.buckets text).toList with
  | [position] => do
      let correspondence ← check? inputs text position
      some ⟨position,correspondence,found⟩
  | _ => none

theorem Unique.only_original {index : Index inputs} {text : String}
    (unique : Unique index text) (source : Fin inputs.size)
    (row : Fin inputs[source].size) (same : inputs[source][row] = text) :
    unique.position = (source.val,row.val) := by
  have included := index.contains_original source row text same
  have present : (source.val,row.val) ∈ (bucket index.buckets text).toList :=
    Std.HashSet.mem_toList.mpr (Std.HashSet.mem_iff_contains.mpr included)
  rw [unique.only] at present
  exact (List.mem_singleton.mp present).symm

/-- Neighboring records are accepted only through literal sequence equality.
The adapter may propose a run around a unique anchor, but cannot fill a gap
from a path name, line-number hint or presumed tool operation. -/
structure Run (inputs : Inputs) (output : Array String)
    (source first outputFirst count : Nat) : Type where
  nonempty : 0 < count
  sourceBound : source < inputs.size
  sourceEnd : first+count ≤ (inputs[source]'sourceBound).size
  outputEnd : outputFirst+count ≤ output.size
  original : ∀ offset : Fin count,
    (inputs[source]'sourceBound)[first+offset.val]'(by have := offset.isLt; omega) =
      output[outputFirst+offset.val]'(by have := offset.isLt; omega)

def run? (inputs : Inputs) (output : Array String) (source first outputFirst count : Nat) :
    Option (Run inputs output source first outputFirst count) :=
  if nonempty : 0 < count then
    if sourceBound : source < inputs.size then
      if sourceEnd : first+count ≤ inputs[source].size then
        if outputEnd : outputFirst+count ≤ output.size then
          if original : (List.finRange count).all (fun offset =>
              decide (inputs[source][first+offset.val]'(by have := offset.isLt; omega) =
                output[outputFirst+offset.val]'(by have := offset.isLt; omega))) = true then
            some ⟨nonempty,sourceBound,sourceEnd,outputEnd,by
              intro offset
              simpa only [decide_eq_true_eq] using
                (List.all_eq_true.mp original offset (by simp))⟩
          else none
        else none
      else none
    else none
  else none

structure AnchoredRun (index : Index inputs) (output : Array String) (anchorIndex : Fin output.size)
    (anchor : Unique index output[anchorIndex]) (first count : Nat) : Type where
  contains : first ≤ anchorIndex.val ∧ anchorIndex.val < first+count
  preceding : anchorIndex.val-first ≤ anchor.position.2
  original : Run inputs output anchor.position.1 (anchor.position.2-(anchorIndex.val-first)) first count

/-- The source and its starting position come from a unique content anchor,
not a guessed path. Every neighboring output record is checked again. -/
def anchoredRun? (index : Index inputs) (output : Array String) (anchorIndex : Fin output.size)
    (anchor : Unique index output[anchorIndex]) (first count : Nat) :
    Option (AnchoredRun index output anchorIndex anchor first count) :=
  if contains : first ≤ anchorIndex.val ∧ anchorIndex.val < first+count then
    if preceding : anchorIndex.val-first ≤ anchor.position.2 then do
      let original ← run? inputs output anchor.position.1 (anchor.position.2-(anchorIndex.val-first)) first count
      some ⟨contains,preceding,original⟩
    else none
  else none

theorem AnchoredRun.anchor_preserved (run : AnchoredRun index output anchorIndex anchor first count) :
    anchor.position.2-(anchorIndex.val-first)+(anchorIndex.val-first) = anchor.position.2 := by
  have := run.preceding
  omega

/-- Capture needs only absence, one location, or proven ambiguity. It never
stores an unbounded posting list for common records such as `}`. Replaying
the same immutable input position does not manufacture ambiguity. -/
inductive Candidate where
  | absent
  | one (position : Position)
  | ambiguous
  deriving DecidableEq, BEq, Repr

def Candidate.join : Candidate → Candidate → Candidate
  | .absent,right => right
  | left,.absent => left
  | .one left,.one right => if left = right then .one left else .ambiguous
  | _,_ => .ambiguous

@[simp] theorem Candidate.absent_join (candidate : Candidate) :
    Candidate.absent.join candidate = candidate := rfl

@[simp] theorem Candidate.join_absent (candidate : Candidate) :
    candidate.join .absent = candidate := by cases candidate <;> rfl

@[simp] theorem Candidate.ambiguous_join (candidate : Candidate) :
    Candidate.ambiguous.join candidate = .ambiguous := by cases candidate <;> rfl

@[simp] theorem Candidate.join_ambiguous (candidate : Candidate) :
    candidate.join .ambiguous = .ambiguous := by cases candidate <;> rfl

theorem Candidate.join_idempotent (candidate : Candidate) :
    candidate.join candidate = candidate := by
  cases candidate <;> simp [join]

theorem Candidate.join_commutative (left right : Candidate) :
    left.join right = right.join left := by
  cases left <;> cases right <;>
    try simp only [absent_join,join_absent,ambiguous_join,join_ambiguous]
  rename_i a b
  by_cases same : a = b
  · subst b; simp [join]
  · simp [join,same,Ne.symm same]

theorem Candidate.join_associative (left middle right : Candidate) :
    (left.join middle).join right = left.join (middle.join right) := by
  cases left <;> cases middle <;> cases right <;>
    try simp only [absent_join,join_absent,ambiguous_join,join_ambiguous]
  rename_i a b c
  by_cases same : a = b
  · subst b
    by_cases next : a = c <;> simp [join,next]
  · by_cases next : b = c
    · subst c; simp [join,same]
    · simp [join,same,next]

abbrev StreamIndex := Std.HashMap String Candidate

def start (output : Array String) : StreamIndex :=
  output.foldl (fun index text => index.insert text .absent) {}

/-- Index the bounded observed output, then stream the acquired input once.
Unwanted input records allocate no entry. The capture adapter must seal all
input fingerprints and EOF before treating a `.one` as final correspondence. -/
def observe (index : StreamIndex) (position : Position) (text : String) : StreamIndex :=
  index.modify text (fun candidate => candidate.join (.one position))

theorem observe_size (index : StreamIndex) (position : Position) (text : String) :
    (observe index position text).size = index.size := by
  exact Std.HashMap.size_modify

theorem observe_keeps_domain (index : StreamIndex) (position : Position) (text query : String) :
    (observe index position text).contains query = index.contains query := by
  exact Std.HashMap.contains_modify

end ContentCorrespondence
