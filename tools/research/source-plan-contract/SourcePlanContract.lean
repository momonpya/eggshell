module
public import tools.research.PublishedPlanMetadata
public import Std.Data.HashSet.Lemmas
@[expose] public section
namespace Eggshell.Synapses.SourcePlanContract
open CanonicalSource

structure Located (size : Nat) (ordinals : List Nat) where
  values : List (Fin size)
  exact : values.map Fin.val = ordinals

def locate (size : Nat) : (ordinals : List Nat) → Except String (Located size ordinals)
  | [] => .ok ⟨[],rfl⟩
  | index :: rest => do
    if inside : index < size then
      let located ← locate size rest
      return ⟨⟨index,inside⟩ :: located.values,by simp [located.exact]⟩
    else throw "published unit contains a foreign original row"

structure UnitChecked (owner : String) (rows : Array StoredRow) (unit : PublishedPlanMetadata.Unit) where
  located : Located rows.size unit.indices
  nonempty : unit.indices ≠ []
  ranges : unit.ranges = PreparedFileUnits.bindings owner
    (located.values.toArray.map (fun index => rows[index]))

def checkUnit (owner : String) (rows : Array StoredRow) (unit : PublishedPlanMetadata.Unit) :
    Except String (UnitChecked owner rows unit) := do
  if nonempty : unit.indices ≠ [] then
    let located ← locate rows.size unit.indices
    if ranges : unit.ranges = PreparedFileUnits.bindings owner
        (located.values.toArray.map (fun index => rows[index])) then
      return ⟨located,nonempty,ranges⟩
    else throw "published unit differs from its original source ranges"
  else throw "published unit has no original rows"

def complete (rows : Array StoredRow) (metadata : PublishedPlanMetadata.Stored) : Bool :=
  let domain := Std.HashSet.ofList (metadata.units.toList.flatMap (·.indices))
  (Array.range rows.size).all domain.contains

/-- Grouping is advisory policy. Validation checks original data, exact costs,
real range witnesses and eligibility of every original row, independently of
which legal grouping a producer chose. This type contains no Work authority. -/
structure Checked (owner : String) (rows : Array StoredRow) (metadata : PublishedPlanMetadata.Stored) : Type where
  ownerExact : metadata.owner = owner
  costsExact : metadata.costs = rows.map PublishedPlanMetadata.rowCost
  unitsValid : metadata.units.all (fun unit => (checkUnit owner rows unit).isOk) = true
  covered : complete rows metadata = true

def check (owner : String) (rows : Array StoredRow) (metadata : PublishedPlanMetadata.Stored) :
    Except String (Checked owner rows metadata) := do
  if ownerExact : metadata.owner = owner then
    if costsExact : metadata.costs = rows.map PublishedPlanMetadata.rowCost then
      if unitsValid : metadata.units.all (fun unit => (checkUnit owner rows unit).isOk) = true then
        if covered : complete rows metadata = true then return ⟨ownerExact,costsExact,unitsValid,covered⟩
        else throw "published units omit an original row"
      else throw "published units have invalid original references"
    else throw "published costs differ from original rendering"
  else throw "published plan changed its original owner"

theorem UnitChecked.original (checked : UnitChecked owner rows unit) (row : StoredRow)
    (member : row ∈ checked.located.values.toArray.map (fun index => rows[index])) : row ∈ rows :=
  PreparedFileUnits.Unit.original ⟨checked.located.values,unit.ranges⟩ row member

theorem Checked.rendered_costs (checked : Checked owner rows metadata) :
    metadata.costs = rows.map (fun row => ((Packet.rowText row).length,(Packet.rowText row).utf8ByteSize)) := by
  rw [checked.costsExact]
  rw [show PublishedPlanMetadata.rowCost =
    (fun row => ((Packet.rowText row).length,(Packet.rowText row).utf8ByteSize)) from
      funext PublishedPlanMetadata.rowCost_exact]

theorem Checked.unit_checked (checked : Checked owner rows metadata) (unit : PublishedPlanMetadata.Unit)
    (member : unit ∈ metadata.units) : ∃ witness, checkUnit owner rows unit = .ok witness := by
  have valid := Array.all_eq_true_iff_forall_mem.mp checked.unitsValid unit member
  cases observed : checkUnit owner rows unit with
  | error message =>
      have wrong : (false : Bool) = true := by simpa only [Except.isOk,Except.toBool,observed] using valid
      cases wrong
  | ok witness => exact ⟨witness,rfl⟩

theorem Checked.all_rows_eligible (checked : Checked owner rows metadata) (index : Fin rows.size) :
    index.val ∈ metadata.units.toList.flatMap (·.indices) := by
  have valid := Array.all_eq_true_iff_forall_mem.mp checked.covered index.val (Array.mem_range.mpr index.isLt)
  simpa [complete,Std.HashSet.contains_ofList] using valid
end Eggshell.Synapses.SourcePlanContract
