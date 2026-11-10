module
public import tools.research.FactoredIncidence
@[expose] public section
namespace Eggshell.Research.RangeIncidence

/-- Scalar source coordinates work for files, JSON and opaque tool output.
The scope key is supplied by the checked snapshot, never inferred from a tool
name. No catalogue of future query endpoints is required. -/
structure Row (S U : Type) where
  scope : S
  first : Nat
  last : Nat
  unit : U
  deriving BEq

def contains (row : Row S U) (first last : Nat) : Bool :=
  row.first ≤ first && last ≤ row.last

inductive Tree (S U : Type) where
  | leaf (row : Row S U)
  | branch (lower upper : Nat) (left right : Tree S U)

def Tree.lower : Tree S U → Nat
  | .leaf row => row.first
  | .branch lower _ _ _ => lower

def Tree.upper : Tree S U → Nat
  | .leaf row => row.last
  | .branch _ upper _ _ => upper

def Tree.rows : Tree S U → List (Row S U)
  | .leaf row => [row]
  | .branch _ _ left right => left.rows ++ right.rows

def Tree.Valid : Tree S U → Prop
  | .leaf _ => True
  | .branch lower upper left right =>
    left.Valid ∧ right.Valid ∧ lower ≤ left.lower ∧ lower ≤ right.lower ∧
      left.upper ≤ upper ∧ right.upper ≤ upper

theorem Tree.bounds (tree : Tree S U) (valid : tree.Valid)
    (row : Row S U) (present : row ∈ tree.rows) :
    tree.lower ≤ row.first ∧ row.last ≤ tree.upper := by
  induction tree with
  | leaf item =>
    have same : row = item := by simpa [rows] using present
    subst row
    exact ⟨Nat.le_refl _,Nat.le_refl _⟩
  | branch lower upper left right ihLeft ihRight =>
    rcases valid with ⟨vl,vr,ll,lr,ul,ur⟩
    rcases List.mem_append.mp present with hit | hit
    · have := ihLeft vl hit; simp only [Tree.lower,Tree.upper]; omega
    · have := ihRight vr hit; simp only [Tree.lower,Tree.upper]; omega

/-- Exact dominance lookup, including the old predicate's empty/reversed spans.
Bounds only prune impossible subtrees; they never estimate relevance. -/
def Tree.query (tree : Tree S U) (first last : Nat) : List (Row S U) :=
  if tree.lower > first || tree.upper < last then [] else
    match tree with
    | .leaf row => if contains row first last then [row] else []
    | .branch _ _ left right => left.query first last ++ right.query first last

theorem Tree.query_exact (tree : Tree S U) (valid : tree.Valid) (first last : Nat) :
    tree.query first last = tree.rows.filter (contains · first last) := by
  induction tree with
  | leaf row =>
    by_cases fit : contains row first last = true
    · have limits : row.first ≤ first ∧ last ≤ row.last := by simpa [contains] using fit
      simp [query,lower,upper,rows,fit,Nat.not_lt.mpr limits.1,Nat.not_lt.mpr limits.2]
    · have reject : contains row first last = false := Bool.eq_false_iff.mpr fit
      simp [query,lower,upper,rows,reject]
  | branch lower upper left right ihLeft ihRight =>
    unfold query
    split
    · rename_i outside
      symm
      apply List.filter_eq_nil_iff.mpr
      intro row present
      have limits := Tree.bounds (.branch lower upper left right) valid row present
      simp only [Tree.lower,Tree.upper] at limits
      have outside' : lower > first ∨ upper < last := by
        rcases Bool.or_eq_true_iff.mp outside with hit | hit
        · exact Or.inl (of_decide_eq_true hit)
        · exact Or.inr (of_decide_eq_true hit)
      intro accepted
      have matched : row.first ≤ first ∧ last ≤ row.last := by simpa [contains] using accepted
      omega
    · simp only [rows,List.filter_append]
      rw [ihLeft valid.1,ihRight valid.2.1]

structure Index (S U : Type) where
  tree : Tree S U
  valid : tree.Valid

def Index.leaf (row : Row S U) : Index S U := ⟨.leaf row,True.intro⟩

def Index.join (left right : Index S U) : Index S U :=
  ⟨.branch (min left.tree.lower right.tree.lower) (max left.tree.upper right.tree.upper)
    left.tree right.tree,by
    exact ⟨left.valid,right.valid,Nat.min_le_left _ _,Nat.min_le_right _ _,
      Nat.le_max_left _ _,Nat.le_max_right _ _⟩⟩

def combine (left right : Option (Index S U)) : Option (Index S U) :=
  match left,right with
  | none,other | other,none => other
  | some left,some right => some (left.join right)

def allRows (index : Option (Index S U)) : List (Row S U) :=
  match index with | none => [] | some ready => ready.tree.rows

theorem combine_rows (left right : Option (Index S U)) :
    allRows (combine left right) = allRows left ++ allRows right := by
  cases left <;> cases right <;> simp [combine,allRows,Index.join,Tree.rows]

/-- Publication-only construction. Sorted first endpoints make the bounds
useful; balancing preserves original order and does not affect correctness. -/
def build (rows : List (Row S U)) : Option (Index S U) :=
  if small : rows.length ≤ 1 then
    match rows with | [] => none | row::_ => some (Index.leaf row)
  else combine (build (rows.take (rows.length/2))) (build (rows.drop (rows.length/2)))
termination_by rows.length
decreasing_by
  · simp only [List.length_take]
    have := Nat.div_lt_self (show 0 < rows.length by omega) (show 1 < 2 by omega)
    omega
  · simp only [List.length_drop]
    have := Nat.div_pos (show 2 ≤ rows.length by omega) (show 0 < 2 by omega)
    omega

theorem build_rows (rows : List (Row S U)) : allRows (build rows) = rows := by
  unfold build
  split
  · rename_i small
    match rows with
    | [] => rfl
    | [row] => rfl
    | _::_::_ => simp at small
  · rw [combine_rows,build_rows,build_rows,List.take_append_drop]
termination_by rows.length
decreasing_by
  · simp only [List.length_take]
    have := Nat.div_lt_self (show 0 < rows.length by omega) (show 1 < 2 by omega)
    omega
  · simp only [List.length_drop]
    have := Nat.div_pos (show 2 ≤ rows.length by omega) (show 0 < 2 by omega)
    omega

def lookup (ready : Option (Index S U)) (first last : Nat) : List (Row S U) :=
  match ready with | none => [] | some ready => ready.tree.query first last

theorem lookup_exact (ready : Option (Index S U)) (first last : Nat) :
    lookup ready first last = (allRows ready).filter (contains · first last) := by
  cases ready with
  | none => rfl
  | some ready => exact ready.tree.query_exact ready.valid first last

variable [BEq S] [LawfulBEq S] [Hashable S]

/-- A project snapshot supplies full scope keys (including DB/source identity).
The table contains immutable trees, not per-chat weights or mutable workers. -/
structure Scoped (rows : List (Row S U)) where
  table : Std.HashMap S (Option (Index S U))
  exact : ∀ scope, allRows (table.getD scope none) = rows.filter (scope == ·.scope)

def prepare (rows : List (Row S U)) : Scoped rows :=
  let groups := Eggshell.OrderedIncidence.build (fun row : Row S U => [row.scope]) rows
  ⟨groups.table.map (fun _ reversed => build reversed.reverse),by
    intro scope
    have ordered := groups.lookup_exact scope
    simp only [Eggshell.OrderedIncidence.Index.lookup] at ordered
    rw [Std.HashMap.getD_eq_getD_getElem?] at ordered
    simp only [Std.HashMap.getD_eq_getD_getElem?,Std.HashMap.getElem?_map]
    cases found : groups.table[scope]? with
    | none => simpa [found,allRows] using ordered
    | some items => simpa [found,build_rows] using ordered⟩

def Scoped.query {rows : List (Row S U)} (ready : Scoped rows) (scope : S)
    (first last : Nat) : List (Row S U) := lookup (ready.table.getD scope none) first last

omit [LawfulBEq S] in
theorem Scoped.query_exact {rows : List (Row S U)} (ready : Scoped rows) (scope : S)
    (first last : Nat) : ready.query scope first last =
      rows.filter (fun row => scope == row.scope && contains row first last) := by
  rw [Scoped.query,lookup_exact,ready.exact,List.filter_filter]
  simp only [Bool.and_comm]

/-- A resolver is exact for every coordinate, including endpoints absent at
publication. A geometry producer must establish this stronger contract. -/
structure Resolver (U C : Type) (related : U → C → Bool) where
  neighbors : C → List U
  exact : ∀ coordinate unit,unit ∈ neighbors coordinate ↔ related unit coordinate = true

variable [BEq U] [LawfulBEq U] [Hashable U]

def Resolver.project {related : U → C → Bool} (ready : Resolver U C related)
    (requests : List (Eggshell.Research.FactoredIncidence.Request C A)) :=
  Eggshell.OrderedIncidence.build
    (fun request => if request.active then ready.neighbors request.coordinate else []) requests

theorem Resolver.project_exact {related : U → C → Bool} (ready : Resolver U C related)
    (requests : List (Eggshell.Research.FactoredIncidence.Request C A)) (unit : U) :
    (ready.project requests).lookup unit =
      requests.filter (fun request => request.active && related unit request.coordinate) := by
  rw [Eggshell.OrderedIncidence.Index.lookup_exact]
  apply List.filter_congr
  intro request _
  cases request.active <;> simp [ready.exact]

structure Coordinate (S : Type) where
  scope : S
  first : Nat
  last : Nat
  deriving BEq

def related (rows : List (Row S U)) (unit : U) (coordinate : Coordinate S) : Bool :=
  rows.any fun row => coordinate.scope == row.scope && row.unit == unit &&
    contains row coordinate.first coordinate.last

/-- Sorting changes only structural witness order. Projection below restores
the original request order and retains every duplicate request. -/
def resolve (rows : List (Row S U)) : Resolver U (Coordinate S) (related rows) :=
  let sorted := rows.mergeSort (fun a b => a.first ≤ b.first)
  let index := prepare sorted
  ⟨(fun coordinate => (index.query coordinate.scope coordinate.first coordinate.last).map Row.unit),by
    intro coordinate unit
    rw [Scoped.query_exact,List.mem_map]
    simp only [List.mem_filter,sorted,List.mem_mergeSort,related,List.any_eq_true]
    constructor
    · rintro ⟨row,⟨present,hit⟩,same⟩
      refine ⟨row,present,?_⟩
      simpa [same,Bool.and_assoc] using hit
    · rintro ⟨row,present,hit⟩
      have split := Bool.and_eq_true_iff.mp hit
      have same : row.unit = unit := beq_iff_eq.mp (Bool.and_eq_true_iff.mp split.1).2
      refine ⟨row,⟨present,?_⟩,same⟩
      exact Bool.and_eq_true_iff.mpr ⟨(Bool.and_eq_true_iff.mp split.1).1,split.2⟩⟩

def rowsFor (units : List U) (scope : U → S) (ranges : U → List (Nat × Nat)) : List (Row S U) :=
  units.flatMap fun unit => (ranges unit).map fun (first,last) => ⟨scope unit,first,last,unit⟩

/-- The actual base-range predicate, rather than equality on a finite sample
of observed coordinates. This includes empty and reversed ranges verbatim. -/
def baseAccept (units : List U) (scope : U → S) (ranges : U → List (Nat × Nat))
    (unit : U) (coordinate : Coordinate S) : Bool :=
  decide (unit ∈ units) && coordinate.scope == scope unit &&
    (ranges unit).any (fun (first,last) => first ≤ coordinate.first && coordinate.last ≤ last)

omit [Hashable S] [Hashable U] in
theorem rowsFor_related (units : List U) (scope : U → S) (ranges : U → List (Nat × Nat))
    (unit : U) (coordinate : Coordinate S) :
    related (rowsFor units scope ranges) unit coordinate = baseAccept units scope ranges unit coordinate := by
  apply Bool.eq_iff_iff.mpr
  simp only [related,rowsFor,List.any_eq_true,List.mem_flatMap,List.mem_map,baseAccept,
    Bool.and_eq_true,decide_eq_true_eq,beq_iff_eq]
  constructor
  · rintro ⟨row,⟨owner,present,pair,pairPresent,same⟩,⟨sameScope,sameUnit⟩,inside⟩
    cases same
    change owner = unit at sameUnit
    subst owner
    exact ⟨⟨present,sameScope⟩,pair,pairPresent,by simpa [contains] using inside⟩
  · rintro ⟨⟨present,sameScope⟩,pair,pairPresent,inside⟩
    refine ⟨⟨scope unit,pair.1,pair.2,unit⟩,⟨unit,present,pair,pairPresent,rfl⟩,⟨sameScope,rfl⟩,?_⟩
    simpa [contains] using inside

def resolveBase (units : List U) (scope : U → S) (ranges : U → List (Nat × Nat)) :
    Resolver U (Coordinate S) (baseAccept units scope ranges) :=
  let ready := resolve (rowsFor units scope ranges)
  ⟨ready.neighbors,by intro coordinate unit; rw [ready.exact,rowsFor_related]⟩

theorem resolveBase_exact (units : List U) (scope : U → S) (ranges : U → List (Nat × Nat))
    (requests : List (Eggshell.Research.FactoredIncidence.Request (Coordinate S) A)) (unit : U) :
    ((resolveBase units scope ranges).project requests).lookup unit =
      requests.filter (fun request => request.active && baseAccept units scope ranges unit request.coordinate) :=
  Resolver.project_exact _ _ _

/-- An over-approximating structural lookup may be refined with the original
predicate. The completeness obligation prevents silently missing a span
which is covered by a union but not by any one constituent interval. -/
def Resolver.refine {related : U → C → Bool} (ready : Resolver U C related)
    (accept : U → C → Bool) (complete : ∀ unit coordinate,
      accept unit coordinate = true → related unit coordinate = true) : Resolver U C accept :=
  ⟨(fun coordinate => (ready.neighbors coordinate).filter (accept · coordinate)),by
    intro coordinate unit
    rw [List.mem_filter,ready.exact]
    exact ⟨And.right,fun hit => ⟨complete unit coordinate hit,hit⟩⟩⟩

def Resolver.comap {related : U → C → Bool} (ready : Resolver U C related) (f : D → C) :
    Resolver U D (fun unit input => related unit (f input)) :=
  ⟨(fun input => ready.neighbors (f input)),fun input unit => ready.exact (f input) unit⟩

structure Forward (related : U → C → Bool) (requests : List (FactoredIncidence.Request C A)) where
  table : Std.HashMap U (List (FactoredIncidence.Request C A))
  exact : ∀ unit,table.getD unit [] = requests.filter (fun request => request.active && related unit request.coordinate)

/-- Each class posting is made forward once. Clients share its immutable list
without reversing or copying it for every unit in that class. -/
def Resolver.finish {related : U → C → Bool} (ready : Resolver U C related)
    (requests : List (FactoredIncidence.Request C A)) : Forward related requests :=
  let index := ready.project requests
  ⟨index.table.map (fun _ rows => rows.reverse),by
    intro unit
    have exact := ready.project_exact requests unit
    unfold OrderedIncidence.Index.lookup at exact
    change (index.table.getD unit []).reverse = _ at exact
    rw [Std.HashMap.getD_eq_getD_getElem?] at exact
    simp only [Std.HashMap.getD_eq_getD_getElem?,Std.HashMap.getElem?_map]
    cases found : index.table[unit]? with
    | none => simpa [found] using exact
    | some rows => simpa [found] using exact⟩

structure Geometry (S : Type) where
  scope : S
  ranges : List (Nat × Nat)
  deriving BEq,Hashable,ReflBEq,LawfulBEq

def Geometry.accept (geometry : Geometry S) (coordinate : Coordinate S) : Bool :=
  coordinate.scope == geometry.scope &&
    geometry.ranges.any (fun (first,last) => first ≤ coordinate.first && coordinate.last ≤ last)

/-- Full geometry equality is checked once, not equality on yesterday's query
samples. Different cost, Work, bytes and authority stay distinct unit values. -/
structure Sharing (geometry : U → Geometry S) (units : List U) where
  classOf : U → Nat
  classes : Array (Geometry S)
  admitted : ∀ unit ∈ units,classOf unit < classes.size
  same : ∀ unit (present : unit ∈ units),classes[classOf unit]'(admitted unit present) = geometry unit
  lookup : Resolver (Fin classes.size) (Coordinate S)
    (baseAccept (List.finRange classes.size) (fun group => classes[group].scope) (fun group => classes[group].ranges))

def Sharing.check (geometry : U → Geometry S) (units : List U) (classOf : U → Nat)
    (classes : Array (Geometry S)) : Option (Sharing geometry units) :=
  if valid : units.all (fun unit => decide (classOf unit < classes.size) &&
      (classes[classOf unit]?.getD (geometry unit) == geometry unit)) = true then
    let admitted : ∀ unit ∈ units,classOf unit < classes.size := by
      intro unit present
      exact of_decide_eq_true (Bool.and_eq_true_iff.mp (List.all_eq_true.mp valid unit present)).1
    some {
      classOf,classes,admitted
      same := by
        intro unit present
        have hit := beq_iff_eq.mp (Bool.and_eq_true_iff.mp (List.all_eq_true.mp valid unit present)).2
        simpa [Array.getElem?_eq_getElem (admitted unit present)] using hit
      lookup := resolveBase (List.finRange classes.size) (fun group => classes[group].scope) (fun group => classes[group].ranges) }
  else none

def Sharing.resolver {geometry : U → Geometry S} {units : List U} (ready : Sharing geometry units) :=
  ready.lookup

def Sharing.project {geometry : U → Geometry S} {units : List U} (ready : Sharing geometry units)
    (requests : List (FactoredIncidence.Request (Coordinate S) A)) := ready.resolver.finish requests

omit [LawfulBEq S] [Hashable S] [BEq U] [LawfulBEq U] [Hashable U] in
theorem Sharing.rows_exact {geometry : U → Geometry S} {units : List U} (ready : Sharing geometry units)
    (requests : List (FactoredIncidence.Request (Coordinate S) A)) (unit : U) (present : unit ∈ units) :
    (ready.project requests).table.getD ⟨ready.classOf unit,ready.admitted unit present⟩ [] =
      requests.filter (fun request => request.active && (geometry unit).accept request.coordinate) := by
  rw [Forward.exact]
  apply List.filter_congr
  intro request _
  simp only [baseAccept,List.mem_finRange,decide_true,Bool.true_and]
  change (request.active && (ready.classes[ready.classOf unit]'(ready.admitted unit present)).accept request.coordinate) = _
  rw [ready.same unit present]

#print axioms Tree.query_exact
#print axioms build_rows
#print axioms Scoped.query_exact
#print axioms Resolver.project_exact
#print axioms rowsFor_related
#print axioms resolveBase_exact
#print axioms Resolver.refine
#print axioms Sharing.rows_exact
end Eggshell.Research.RangeIncidence
