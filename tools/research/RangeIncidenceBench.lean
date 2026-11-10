module
public import tools.research.ProductRangeIncidence
import Lean.Data.Json.FromToJson
@[expose] public section
open Lean Eggshell Eggshell.Research
open RangeIncidence
namespace RangeIncidenceBench
structure Scope where
  db : String
  owner : String
  fingerprint : String
  deriving BEq,Hashable,ReflBEq,LawfulBEq
abbrev Request := FactoredIncidence.Request (Coordinate Scope) (Nat × Nat)

structure Dataset where
  units : List Nat
  geometries : Array (Geometry Scope)
  sharing : Sharing (fun unit => geometries[unit]?.getD ⟨⟨"absent","",""⟩,[]⟩) units
  requests : List Request

def compileSharing [Hashable Scope] [Hashable Nat] (geometries : Array (Geometry Scope)) (units : List Nat) := Id.run do
  let mut ids : Std.HashMap (Geometry Scope) Nat := {}
  let mut assignments : Std.HashMap Nat Nat := {}
  let mut classes := #[]
  for unit in units do
    let geometry := geometries[unit]?.getD ⟨⟨"absent","",""⟩,[]⟩
    let id := ids[geometry]?.getD classes.size
    if id == classes.size then ids := ids.insert geometry id; classes := classes.push geometry
    assignments := assignments.insert unit id
  return Sharing.check (fun unit => geometries[unit]?.getD ⟨⟨"absent","",""⟩,[]⟩) units
    (fun unit => assignments[unit]?.getD classes.size) classes

def scope (family : Nat) : Scope := ⟨"project-"++toString (family%3),"owner-"++toString family,"checked-content"⟩

def make (scopes count width degree requestCount : Nat) : IO Dataset := do
  let units := List.range count
  let geometries := (Array.range count).map fun unit =>
    ({scope := scope (unit%scopes),ranges := (List.range degree).map fun offset =>
      let first := ((unit/scopes+offset)%width)*11
      (first,first+9)} : Geometry Scope)
  let some sharing := compileSharing geometries units | throw (IO.userError "geometry certificate rejected")
  let requests := (List.range requestCount).map fun id =>
    let first := ((id/scopes)%width)*11+3 -- not a published endpoint
    ({coordinate := ⟨scope (id%scopes),first,first+2⟩,active := id%11 != 0,
      value := (id,if id%17 == 0 then 2^384+id else id+1)} : Request)
  return ⟨units,geometries,sharing,requests⟩

@[noinline,nospecialize] def reference [Hashable Scope] (input : Dataset) : Array (List Request) := Id.run do
  let byScope := OrderedIncidence.build (fun request : Request => [request.coordinate.scope]) input.requests
  return input.units.toArray.map fun unit =>
    let geometry := input.geometries[unit]?.getD ⟨⟨"absent","",""⟩,[]⟩
    (byScope.lookup geometry.scope).filter (fun request => request.active && geometry.accept request.coordinate)

@[noinline,nospecialize] def indexed (input : Dataset) : Array (List Request) :=
  let query := input.sharing.project input.requests
  input.units.attach.toArray.map fun unit =>
    query.table.getD ⟨input.sharing.classOf unit.val,input.sharing.admitted unit.val unit.property⟩ []

def measured (method : Dataset → Array (List Request)) (input : IO.Ref Dataset) : IO (Array (List Request) × Nat) := do
  let began ← IO.monoNanosNow
  let output := method (← input.get)
  let output ← (← IO.mkRef output).get
  return (output,((← IO.monoNanosNow)-began)/1000)

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

def controls : IO Nat := do
  let scopes := [scope 0,scope 1,{scope 0 with db := "other-project"},{scope 0 with fingerprint := "changed"},
    ⟨"mcp-project","mcp://resource/issue","etag-snapshot"⟩]
  let spans : List (Nat × Nat) := [(0,2),(2,4),(0,4),(4,4),(7,2),(100000000000000000000,100000000000000000009)]
  let geometries := (scopes.flatMap fun scope => spans.map fun span => ({scope,ranges := [span,span]} : Geometry Scope)).toArray
  let units := List.range geometries.size
  let some sharing := compileSharing geometries units | throw (IO.userError "range controls rejected")
  let requests : List Request := scopes.flatMap fun scope =>
    ([(0,0),(1,3),(2,2),(3,1),(100000000000000000003,100000000000000000007),(100,101)]++spans).zipIdx.map fun (entry : (Nat × Nat) × Nat) =>
      let (span,id) := entry
      ({coordinate := ⟨scope,span.1,span.2⟩,active := id%3 != 0,value := (id,2^256+id)} : Request)
  let input : Dataset := ⟨units,geometries,sharing,requests++requests⟩
  check (reference input == indexed input) "arbitrary endpoint/scope/degenerate/duplicate rows changed"
  let first : Geometry Scope := ⟨scope 0,[(0,2)]⟩
  let wrong : Geometry Scope := ⟨scope 1,[(0,2)]⟩
  let rejected := Sharing.check (fun _ : Nat => first) [0] (fun _ => 0) #[wrong]
  check rejected.isNone "different full geometry was shared"
  let rejected := Sharing.check (fun _ : Nat => first) [0] (fun _ => 1) #[first]
  check rejected.isNone "out-of-range geometry class accepted"
  let shape : Eggshell.Plugin.SharedRangeAdapter.UnitShape := {family := 0,ranges := [(0,2),(2,4)]}
  let product : Array Eggshell.Plugin.SharedRangeAdapter.ServiceUnit := #[{shape}]
  let coordinate : Coordinate Nat := ⟨0,1,3⟩
  check ((ProductRangeIncidence.base product).neighbors coordinate |>.isEmpty)
    "single-interval predicate incorrectly merged adjacent ranges"
  check (((ProductRangeIncidence.union product).neighbors coordinate).map Fin.val == [0]) "union coverage lost an adjacent span"
  letI : Hashable Scope := ⟨fun _ => 0⟩
  letI : Hashable Nat := ⟨fun _ => 0⟩
  match compileSharing geometries units with
  | none => throw (IO.userError "colliding range controls rejected")
  | some collision => do
    let colliding : Dataset := ⟨units,geometries,collision,requests++requests⟩
    check (reference colliding == indexed colliding) "hash collision lost scope or query order"
    return 6

def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "range benchmark output required")
  let output : System.FilePath := path
  check (!(← output.pathExists)) "preserve range benchmark evidence"
  let controlChecks ← controls
  let mut cases := #[]
  for (name,scopes,count,width,degree,requests) in [
      ("empty",1,0,1,0,0),("small",4,32,16,3,64),("balanced",46,10637,144,3,17414),
      ("single-scope",1,2048,4096,3,8192),("dense",1,128,1,3,4096),("wide",1,128,64,64,4096)] do
    let began ← IO.monoNanosNow
    let data ← make scopes count width degree requests
    let input ← IO.mkRef data
    let prepareUs := ((← IO.monoNanosNow)-began)/1000
    let mut trials := #[]
    for round in [:3] do
      let (a,b) ← if round%2 == 0 then do
        let a ← measured reference input
        let b ← measured indexed input
        pure (a,b)
      else do
        let b ← measured indexed input
        let a ← measured reference input
        pure (a,b)
      check (a.1 == b.1) "range projection changed complete ordered rows and weights"
      trials := trials.push (Json.mkObj [("referenceUs",toJson a.2),("indexedUs",toJson b.2),("allOrderedRowsEqual",toJson true)])
    cases := cases.push (Json.mkObj [("case",toJson name),("units",toJson count),("requests",toJson requests),
      ("geometryClasses",toJson data.sharing.classes.size),("wholeFixturePreparationUs",toJson prepareUs),("trials",toJson trials)])
  IO.FS.writeFile output (Json.mkObj [("cases",toJson cases),("controlComparisons",toJson controlChecks),
    ("allQueriesUseUnpublishedEndpoints",toJson true),("scopeIncludesDbOwnerFingerprint",toJson true),
    ("syntheticOnly",toJson true),("productPredicateProofs",toJson true),("actualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end RangeIncidenceBench
def main := RangeIncidenceBench.main
