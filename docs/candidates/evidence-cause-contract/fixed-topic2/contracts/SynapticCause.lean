module
public import Eggshell.SynapticRoutingStore
@[expose] public section

namespace Eggshell.Synapses.Cause
open Lean Recommend Routing.Store

/-- Relation meaning survives coordinate projection. Coquotation associates
records; it does not state that all coquoted records are prerequisites. -/
inductive Role where
  | support | consumption | association | omittedRead | omittedConsumed | cited
  deriving Inhabited, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def Role.joint : Role → Bool
  | .support | .consumption => true
  | _ => false

def Role.label : Role → String
  | .support => "support" | .consumption => "consumption" | .association => "coquotation"
  | .omittedRead => "omitted_then_read" | .omittedConsumed => "omitted_then_consumed"
  | .cited => "delivered_then_cited"

def role? : Nat → Option Role
  | 0 => some .support | 1 => some .consumption | 2 => some .association
  | 3 => some .omittedRead | 4 => some .omittedConsumed | 5 => some .cited | _ => none

inductive Origin where
  | group (group : Group)
  | fact (evidence : String)
  deriving DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

structure Reason where
  database : String
  role : Role
  origin : Origin
  deriving DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

/-- A dependency is grouped by its original reason; an association or use
event retains its own source. Neither key depends on its display binding. -/
structure Key where
  reason : Reason
  independentSource : Option Range
  deriving DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def key? (database : String) (hint : Hint) : Option Key := do
  let role ← role? hint.kind
  if database.isEmpty || !digest hint.evidence then none else do
    if role == .support then
      let some (.claim claim) := hint.group | none
      if claim.database != database then none else pure ()
    if role == .association then
      let some group := hint.group | none
      let scope := match group with | .claim claim => claim.database | .answer scope _ => scope
      if scope != database then none else pure ()
    let source ← if role.joint then some none else hint.target.source?.map some
    let origin := hint.group.map Origin.group |>.getD (.fact hint.evidence)
    return ⟨⟨database,role,origin⟩,source⟩

def Key.identity (key : Key) : String := Index.contentKey key
def Key.joint (key : Key) : Bool := key.reason.role.joint

def outputKey (database evidence : String) : Key :=
  ⟨⟨database,.consumption,.fact evidence⟩,none⟩

structure ScopedHint where
  database : String
  hint : Hint

structure Demand where
  reason : Key
  key : String
  keyExact : key = reason.identity
  sources : Array Range
  priority : Nat
  witnesses : Array String

def Demand.kind (demand : Demand) : String := demand.reason.reason.role.label

/-- Output-only witnesses are bound separately to complete native fragments.
Range requests include unavailable targets: binding cannot shrink a demand
by silently discarding a source that failed to locate. -/
def demands (inputs : Array ScopedHint) : Array Demand := Id.run do
  let mut groups : Std.HashMap Key (List (Range × Nat × String)) := {}
  for input in inputs do
    let some key := key? input.database input.hint | continue
    let some source := input.hint.target.source? | continue
    groups := groups.insert key ((source,input.hint.priority,input.hint.evidence) :: (groups[key]?.getD []))
  return (groups.toArray.map fun (reason,backward) =>
    let rows := backward.reverse
    let sources := rows.map (·.1) |>.eraseDups.toArray
    let priority := rows.foldl (fun best row => min best row.2.1) ((rows.head?.map (·.2.1)).getD 0)
    ⟨reason,reason.identity,rfl,sources,priority,(rows.map (·.2.2)).eraseDups.toArray⟩).qsort fun a b =>
      if a.priority == b.priority then a.key < b.key else a.priority < b.priority

/-- A recorded reason is credited only with its complete requested evidence.
This is a recommendation contract, not a claim of semantic necessity. -/
def Demand.credited (demand : Demand) (covered : Range → Bool) : Bool :=
  !demand.sources.isEmpty && demand.sources.all covered

theorem credited_requires_all (demand : Demand) (covered : Range → Bool)
    (credit : demand.credited covered = true) (source : Range) (member : source ∈ demand.sources) :
    covered source = true := by
  exact (Array.all_eq_true'.mp (Bool.and_eq_true_iff.mp credit).2) source member

theorem credited_binding_invariant (demand : Demand) (raw file : Range → Bool)
    (same : ∀ source ∈ demand.sources, raw source = file source) :
    demand.credited raw = demand.credited file := by
  have sameAll : demand.sources.all raw = demand.sources.all file := by
    have truths : demand.sources.all raw = true ↔ demand.sources.all file = true := by
      constructor
      · intro accepted
        apply Array.all_eq_true'.mpr
        intro source member
        rw [← same source member]
        exact Array.all_eq_true'.mp accepted source member
      · intro accepted
        apply Array.all_eq_true'.mpr
        intro source member
        rw [same source member]
        exact Array.all_eq_true'.mp accepted source member
    cases rawResult : demand.sources.all raw <;>
      cases fileResult : demand.sources.all file <;> simp_all
  simp only [Demand.credited,sameAll]

def admits (causes : List Key) (reason : Key) (complete : Bool) : Bool :=
  causes.contains reason && complete

theorem admitted_requires_same_reason (causes : List Key) (reason : Key) (complete : Bool)
    (accepted : admits causes reason complete = true) : reason ∈ causes := by
  exact List.contains_iff_mem.mp (Bool.and_eq_true_iff.mp accepted).1

theorem admitted_requires_completion (causes : List Key) (reason : Key) (complete : Bool)
    (accepted : admits causes reason complete = true) : complete = true :=
  (Bool.and_eq_true_iff.mp accepted).2

theorem association_is_independent : Role.joint .association = false := rfl
theorem omissions_do_not_imply_joint_dependencies :
    Role.joint .omittedRead = false ∧ Role.joint .omittedConsumed = false := by decide

structure Projection where
  cause : Key
  first : Nat
  limit : Nat

def Projection.rebind (projection : Projection) (first limit : Nat) : Projection :=
  {projection with first,limit}

theorem projection_preserves_cause (projection : Projection) (first limit : Nat) :
    (projection.rebind first limit).cause = projection.cause := rfl

end Eggshell.Synapses.Cause
