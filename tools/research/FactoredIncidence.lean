module
public import Eggshell.OrderedIncidence
@[expose] public section
namespace Eggshell.Research.FactoredIncidence

variable {U C A : Type} [BEq C] [LawfulBEq C] [Hashable C]

/-- Immutable structural incidence. There is no question, weight, query budget,
or completion authority here. The caller supplies full scoped coordinate keys. -/
structure Static (keys : U → List C) (units : List U) where
  incidence : OrderedIncidence.Index keys units

def compile (keys : U → List C) (units : List U) : Static keys units :=
  ⟨OrderedIncidence.build keys units⟩

def Static.neighbors {keys : U → List C} {units : List U}
    (ready : Static keys units) (coordinate : C) : List U :=
  ready.incidence.lookup coordinate

theorem Static.member {keys : U → List C} {units : List U}
    (ready : Static keys units) (coordinate : C) (unit : U) :
    unit ∈ ready.neighbors coordinate ↔ unit ∈ units ∧ coordinate ∈ keys unit := by
  rw [Static.neighbors,OrderedIncidence.Index.lookup_exact]
  simp

/-- Only the new unit rows are processed. Persistent map paths may be copied;
old coordinates are not decoded or re-enumerated. Old readers retain old data. -/
def Static.extend {keys : U → List C} {units : List U}
    (ready : Static keys units) (next : List U) : Static keys (units++next) :=
  ⟨⟨next.foldl (OrderedIncidence.add keys) ready.incidence.table,by
    intro coordinate
    have step := OrderedIncidence.fold_lookup keys next ready.incidence.table coordinate
    have reversed := congrArg List.reverse step
    simpa only [List.reverse_append,List.reverse_reverse,ready.incidence.exact,List.filter_append] using reversed⟩⟩

theorem Static.extended_lookup {keys : U → List C} {units : List U}
    (ready : Static keys units) (next : List U) (coordinate : C) :
    (ready.extend next).neighbors coordinate =
      ready.neighbors coordinate ++ (compile keys next).neighbors coordinate := by
  simp only [Static.neighbors,OrderedIncidence.Index.lookup_exact,List.filter_append]

variable [BEq U] [LawfulBEq U] [Hashable U]

structure Request (C A : Type) where
  coordinate : C
  active : Bool
  value : A
  deriving BEq

def requestKeys {keys : U → List C} {units : List U}
    (ready : Static keys units) (request : Request C A) : List U :=
  if request.active then ready.neighbors request.coordinate else []

/-- Transpose the active structural hits once, in original request order.
Repeated requests remain repeated rows. Repeated structural witnesses do not
manufacture duplicate votes for one request. -/
def project {keys : U → List C} {units : List U}
    (ready : Static keys units) (requests : List (Request C A)) :
    OrderedIncidence.Index (requestKeys ready) requests :=
  OrderedIncidence.build (requestKeys ready) requests

def accepts (keys : U → List C) (units : List U) (unit : U)
    (request : Request C A) : Bool :=
  request.active && decide (unit ∈ units) && decide (request.coordinate ∈ keys unit)

omit [Hashable U] in
theorem request_key_exact {keys : U → List C} {units : List U}
    (ready : Static keys units) (request : Request C A) (unit : U) :
    decide (unit ∈ requestKeys ready request) = accepts keys units unit request := by
  cases active : request.active <;> simp [requestKeys,active,accepts,Static.member]

/-- Full ordered equality, including payloads, inactive rows and duplicates.
This is a relation-level theorem, not yet a proof that a product's coordinate
catalogue completely represents all of its interval-containment predicates. -/
theorem project_exact {keys : U → List C} {units : List U}
    (ready : Static keys units) (requests : List (Request C A)) (unit : U) :
    (project ready requests).lookup unit = requests.filter (accepts keys units unit) := by
  rw [OrderedIncidence.Index.lookup_exact]
  apply List.filter_congr
  intro request _
  exact request_key_exact ready request unit

theorem payloads_exact {keys : U → List C} {units : List U}
    (ready : Static keys units) (requests : List (Request C A)) (unit : U) :
    ((project ready requests).lookup unit).map Request.value =
      (requests.filter (accepts keys units unit)).map Request.value := by
  rw [project_exact]

def reference (keys : U → List C) (units : List U) (requests : List (Request C A)) (unit : U) :
    List (Request C A) :=
  if unit ∈ units then
    let coordinates := keys unit
    requests.filter (fun row => row.active && decide (row.coordinate ∈ coordinates))
  else []

omit [Hashable C] [Hashable U] in
theorem reference_exact (keys : U → List C) (units : List U) (requests : List (Request C A)) (unit : U) :
    reference keys units requests unit = requests.filter (accepts keys units unit) := by
  by_cases present : unit ∈ units
  · rw [reference,if_pos present]
    apply List.filter_congr
    intro request _
    simp [accepts,present]
  · have inactive : accepts keys units unit = (fun _ : Request C A => false) := by
      funext request
      simp [accepts,present]
    simp [reference,present,inactive]

theorem lookup_reference {keys : U → List C} {units : List U}
    (ready : Static keys units) (requests : List (Request C A)) (unit : U) :
    (project ready requests).lookup unit = reference keys units requests unit := by
  rw [project_exact,reference_exact]

#print axioms Static.extended_lookup
#print axioms project_exact
#print axioms lookup_reference

end Eggshell.Research.FactoredIncidence
