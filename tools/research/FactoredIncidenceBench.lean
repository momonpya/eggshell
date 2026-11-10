import tools.research.FactoredIncidence
import tools.research.SharedIncidence
import Lean.Data.Json.FromToJson
open Lean Eggshell Eggshell.Research.FactoredIncidence
namespace FactoredIncidenceBench
abbrev Coord := Nat × Nat
abbrev Row := Request Coord (Nat × Nat)
structure Dataset where
  units : List Nat
  keys : Nat → List Coord
  requests : List Row
  topology : Static keys units
  scopes : Nat
  membership : Array (Std.HashSet Coord)

def keys (scopes width degree : Nat) (unit : Nat) : List Coord :=
  (List.range degree).map (fun offset => (unit%scopes,(unit/scopes+offset)%width))

def make (scopes unitCount width degree count : Nat) : Dataset := Id.run do
  let units := List.range unitCount
  let relation := keys scopes width degree
  let requests := (List.range count).map fun i => ({
    coordinate := (i%scopes,(i/scopes)%width)
    active := i%11 != 0
    value := (i,if i%17 == 0 then 2^384+i else i+1)} : Row)
  let membership := (Array.range unitCount).map (fun unit => Std.HashSet.ofList (relation unit))
  return ⟨units,relation,requests,compile relation units,scopes,membership⟩

/-- Family-only postings with O(1) prepared coordinate membership, rather than
an artificially slow Cartesian/list-membership comparator. Query index build
and complete ordered outputs are included in each timing. -/
@[noinline,nospecialize] def familyScan (data : Dataset) : Array (List Row) := Id.run do
  let index := OrderedIncidence.build (fun row : Row => [row.coordinate.1]) data.requests
  return data.units.toArray.map fun unit =>
    let available := data.membership[unit]?.getD {}
    (index.lookup (unit%data.scopes)).filter (fun row => row.active && available.contains row.coordinate)

@[noinline,nospecialize] def factored (data : Dataset) : Array (List Row) :=
  let index := project data.topology data.requests
  data.units.toArray.map index.lookup

def measured (method : Dataset → Array (List Row)) (input : IO.Ref Dataset) : IO (Array (List Row) × Nat × Nat) := do
  let start ← IO.monoNanosNow
  let allocations ← IO.getNumHeartbeats
  let rows := method (← input.get)
  let rows ← (← IO.mkRef rows).get
  return (rows,((← IO.monoNanosNow)-start)/1000,(← IO.getNumHeartbeats)-allocations)

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

def controls : IO Nat := do
  let relation := fun unit : Nat => if unit == 0 then [(3,7),(3,7),(4,7)] else [(4,7)]
  let old := compile relation [0]
  let ready := old.extend [1]
  let query : List Row := [⟨(3,7),true,(1,9)⟩,⟨(4,7),false,(2,9)⟩,
    ⟨(4,7),true,(3,2^512)⟩,⟨(3,7),true,(1,9)⟩,⟨(8,7),true,(4,9)⟩]
  let result := project ready query
  for unit in [0,1,2] do
    check (result.lookup unit == reference relation [0,1] query unit) "scope/order/duplicate projection changed"
  check (old.neighbors (4,7) == [0] && ready.neighbors (4,7) == [0,1]) "extension mutated old index or lost new rows"
  check ((result.lookup 0).length == 3 && (result.lookup 1).length == 1) "structural duplicate changed query multiplicity"
  letI : Hashable Nat := ⟨fun _ => 0⟩
  letI : Hashable Coord := ⟨fun _ => 0⟩
  let ready := compile relation [0,1]
  let result := project ready query
  for unit in [0,1,2] do
    check (result.lookup unit == reference relation [0,1] query unit) "hash collision merged scope or lost a row"
  return 8

def run (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve component evidence"
  let controls ← controls
  let mut cases := #[]
  for (name,scopes,unitCount,width,degree,count) in [
      ("empty",1,0,1,0,0),("small",4,32,16,3,64),
      ("balanced",46,10637,144,3,17414),("single-scope",1,2048,4096,3,8192),
      ("dense",1,128,1,3,4096),("wide",1,128,64,64,4096)] do
    let began ← IO.monoNanosNow
    let data ← (← IO.mkRef (make scopes unitCount width degree count)).get
    let prepareUs := ((← IO.monoNanosNow)-began)/1000
    let input ← IO.mkRef data
    let mut trials := #[]
    let mut emitted := 0
    for iteration in [:3] do
      let (a,b) ← if iteration%2 == 0 then do
        let a ← measured familyScan input
        let b ← measured factored input
        pure (a,b)
      else do
        let b ← measured factored input
        let a ← measured familyScan input
        pure (a,b)
      check (a.1 == b.1) "complete ordered rows differ"
      emitted := a.1.foldl (fun total rows => total+rows.length) 0
      trials := trials.push (Json.mkObj [("scopedUs",toJson a.2.1),("factoredUs",toJson b.2.1),
        ("scopedAllocationEvents",toJson a.2.2),("factoredAllocationEvents",toJson b.2.2),
        ("allRowsAndPayloadsEqual",toJson true)])
    cases := cases.push (Json.mkObj [("case",toJson name),("units",toJson unitCount),("requests",toJson count),
      ("preparationUs",toJson prepareUs),("emittedRows",toJson emitted),("trials",toJson trials)])
  IO.FS.writeFile output (Json.mkObj [("cases",toJson cases),("controls",toJson controls),
    ("queryOrder",toJson "AB,BA,AB"),("weightsAndIdsPreserved",toJson true),
    ("componentOnly",toJson true),("actualProductContainmentRefinementClosed",toJson false),
    ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress

def canonical (coordinates : List Coord) : List Coord :=
  (hashDistinct coordinates).mergeSort (fun a b => a.1 < b.1 || (a.1 == b.1 && a.2 ≤ b.2))

theorem canonical_members (coordinates : List Coord) (coordinate : Coord) :
    coordinate ∈ canonical coordinates ↔ coordinate ∈ coordinates := by
  simp [canonical,HashDistinct.mem]

def compileShared [Hashable Nat] [Hashable Coord] (relation : Nat → List Coord) (units : List Nat) :
    Option (Sharing relation units) := Id.run do
  let mut classes : Std.HashMap (List Coord) Nat := {}
  let mut assignments : Std.HashMap Nat Nat := {}
  let mut coordinates : Array (List Coord) := #[]
  for unit in units do
    let keys := canonical (relation unit)
    let group := classes[keys]?.getD coordinates.size
    if group == coordinates.size then
      classes := classes.insert keys group
      coordinates := coordinates.push keys
    assignments := assignments.insert unit group
  return Sharing.checkUsing canonical canonical_members relation units
    (fun unit => assignments[unit]?.getD coordinates.size) coordinates

structure SharedDataset where
  data : Dataset
  sharing : Sharing data.keys data.units

@[noinline,nospecialize] def sharedProjection (input : SharedDataset) : Array (List Row) :=
  let query := input.sharing.project input.data.requests
  input.data.units.attach.toArray.map (fun unit => input.sharing.rows query unit.val unit.property)

def sharedMeasured (method : SharedDataset → Array (List Row)) (input : IO.Ref SharedDataset) :
    IO (Array (List Row) × Nat × Nat) := do
  let start ← IO.monoNanosNow
  let allocations ← IO.getNumHeartbeats
  let rows := method (← input.get)
  let rows ← (← IO.mkRef rows).get
  return (rows,((← IO.monoNanosNow)-start)/1000,(← IO.getNumHeartbeats)-allocations)

def sharedControls : IO Nat := do
  let relation := fun unit : Nat => if unit < 2 then [(3,7),(3,7)] else [(4,7)]
  let units := [0,1,2]
  let some ready := compileShared relation units | throw (IO.userError "valid structural groups rejected")
  let query : List Row := [⟨(3,7),true,(1,9)⟩,⟨(4,7),false,(2,9)⟩,
    ⟨(4,7),true,(3,2^512)⟩,⟨(3,7),true,(1,9)⟩,⟨(8,7),true,(4,9)⟩]
  check (ready.coordinates.size == 2) "equal coverage was not shared"
  let projected := ready.project query
  for unit in units.attach do
    check (ready.rows projected unit.val unit.property == reference relation units query unit.val) "grouped projection changed ordered rows"
  check ((Sharing.check relation units (fun _ => 0) #[[(3,7),(3,7)]]).isNone) "malformed group accepted"
  check ((Sharing.check relation units (fun _ => 9) #[[(3,7)]]).isNone) "out-of-domain group accepted"
  letI : Hashable Nat := ⟨fun _ => 0⟩
  letI : Hashable Coord := ⟨fun _ => 0⟩
  do
    let some collisionReady := compileShared relation units | throw (IO.userError "colliding structural groups rejected")
    let collidingProjection := collisionReady.project query
    for unit in units.attach do
      check (collisionReady.rows collidingProjection unit.val unit.property == reference relation units query unit.val) "colliding group changed scope or rows"
    return 9

def runShared (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve shared incidence evidence"
  let controls ← sharedControls
  let mut cases := #[]
  for (name,scopes,unitCount,width,degree,count) in [
      ("empty",1,0,1,0,0),("small",4,32,16,3,64),
      ("balanced",46,10637,144,3,17414),("single-scope",1,2048,4096,3,8192),
      ("dense",1,128,1,3,4096),("wide",1,128,64,64,4096)] do
    let began ← IO.monoNanosNow
    let data ← (← IO.mkRef (make scopes unitCount width degree count)).get
    let some sharing := compileShared data.keys data.units | throw (IO.userError "valid dataset grouping rejected")
    let input ← IO.mkRef ({data,sharing} : SharedDataset)
    let prepareUs := ((← IO.monoNanosNow)-began)/1000
    let mut trials := #[]
    for iteration in [:3] do
      let (a,b,c) ← if iteration%2 == 0 then do
        let a ← sharedMeasured (fun input => familyScan input.data) input
        let b ← sharedMeasured (fun input => factored input.data) input
        let c ← sharedMeasured sharedProjection input
        pure (a,b,c)
      else do
        let c ← sharedMeasured sharedProjection input
        let b ← sharedMeasured (fun input => factored input.data) input
        let a ← sharedMeasured (fun input => familyScan input.data) input
        pure (a,b,c)
      check (a.1 == b.1 && a.1 == c.1) "shared output changed payload/order/multiplicity"
      trials := trials.push (Json.mkObj [("scopedUs",toJson a.2.1),("directIncidenceUs",toJson b.2.1),
        ("sharedIncidenceUs",toJson c.2.1),("sharedAllocationEvents",toJson c.2.2),
        ("allOrderedRowsEqual",toJson true)])
    cases := cases.push (Json.mkObj [("case",toJson name),("units",toJson unitCount),
      ("coverageClasses",toJson sharing.coordinates.size),("requests",toJson count),
      ("preparationUs",toJson prepareUs),("trials",toJson trials)])
  IO.FS.writeFile output (Json.mkObj [("cases",toJson cases),("controls",toJson controls),
    ("order",toJson "ABC,CBA,ABC"),("componentOnly",toJson true),
    ("actualProductContainmentRefinementClosed",toJson false),("actualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end FactoredIncidenceBench
def main (args : List String) : IO Unit := do
  match args with
  | [output] => FactoredIncidenceBench.run (.mk output)
  | ["shared",output] => FactoredIncidenceBench.runShared (.mk output)
  | _ => throw (IO.userError "new component output required")
