import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.SourceIncidenceChecks

#print axioms OrderedIncidence.Index.lookup_exact
#print axioms OrderedIncidence.Index.flatMap_exact
#print axioms SourceIncidence.neighbors_exact
#print axioms SourceIncidence.neighborhood_exact

run_meta do
  let environment ← getEnv
  let some body := (environment.find? ``indexedDiscoveryUsing).bind (·.value?) |
    throwError "Missing actual indexed discovery"
  for required in #[``SourceIncidence.build,``SourceIncidence.neighborhood] do
    unless body.getUsedConstants.contains required do
      throwError "Actual source discovery bypasses incidence: {required}"

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

/-- The previous literal scan, independently retained as a native oracle. -/
private def referenceNeighbors (all : List AllEdge) (unions : List UnionEdge) (origin : Value) :
    List (SourceNeighbor all unions origin) :=
  (all.attach.flatMap fun ⟨edge,saved⟩ =>
    (if parent : origin = edge.parent then edge.children.attach.map fun ⟨work,member⟩ =>
      ⟨work,parent ▸ SourceLink.child edge saved work member⟩ else []) ++
    (if child : origin ∈ edge.children then
      [⟨edge.parent,SourceLink.parent edge saved origin child⟩] else [])) ++
  unions.attach.flatMap fun ⟨edge,saved⟩ =>
    (if left : origin = edge.left then [⟨edge.right,left ▸ SourceLink.forward edge saved⟩] else []) ++
    (if right : origin = edge.right then [⟨edge.left,right ▸ SourceLink.backward edge saved⟩] else [])

private def makeAll (parent : Value) (children : List Value) : IO AllEdge := do
  let some edge := AllEdge.fromValue? (.applyList .all
      ((.semantic,parent)::children.map fun child => (.semantic,child))) |
    throw (IO.userError "invalid All fixture")
  return edge

private structure CollisionKey where
  value : Nat
  deriving BEq,ReflBEq,LawfulBEq
private instance : Hashable CollisionKey := ⟨fun _ => 0⟩

private def collisionChecks (size : Nat) : IO Nat := do
  let rows : List (Nat × List CollisionKey) := (List.range size).map fun i =>
    (i,[⟨i%7⟩,⟨i%7⟩,⟨(i+3)%7⟩])
  let index := OrderedIncidence.build Prod.snd rows
  for query in List.range 11 do
    let key : CollisionKey := ⟨query⟩
    check (index.lookup key == rows.filter (fun row => row.2.contains key)) "colliding incidence lost row order"
  return 11

private def node (i : Nat) := Value.text s!"project/owner-{i%3}/work-{i}"
private def atomAlias (left right : String) : UnionEdge :=
  ⟨.text left,.text right,.workspace (.text "original authority"),by intro value; rfl⟩

private def graphFixture (size : Nat) : IO (List AllEdge × List UnionEdge × List Value) := do
  let values := (List.range (size+1)).map node
  let structured := Value.applyList .inquiry [(.exact,.text "tool"),(.exact,.text "environment"),
    (.semantic,node 0),(.exact,.text "input"),(.exact,.text "read"),(.exact,.text "source")]
  let mut all := [← makeAll structured [node 0,node 0]]
  if size > 0 then
    for i in [:size+1] do
      let edge ← makeAll (node i) [node ((i+1)%(size+1)),node ((i+1)%(size+1))]
      all := all++[edge]
      if i%3 == 0 then all := all++[edge]
  let unions : List UnionEdge := [⟨node 0,node 0,
    .workspace (.text "original authority"),Value.sameExactFootprint_refl _⟩,
    ⟨structured,structured,.workspace (.text "original authority"),Value.sameExactFootprint_refl _⟩,
    atomAlias "project/owner-0/work-0" "different owner/alias"]
  return (all,unions,structured::(.text "absent")::values)

private def routes (items : List (ReachedSource roots all unions)) : List (Value × List Value) :=
  items.map fun row => (row.work,row.route.works)

private def graphChecks (size : Nat) : IO Nat := do
  let (all,unions,values) ← graphFixture size
  let index := SourceIncidence.build all unions
  let mut count := 0
  for value in values do
    check ((index.neighbors value).map (·.work) == (referenceNeighbors all unions value).map (·.work))
      "original neighbor order/multiplicity differs"
    for roots in [[],[value],[value,value],[node 0,value]] do
      let observed := routes (index.neighborhood roots)
      let expected := routes (sourceNeighborhoodUsing roots all unions (referenceNeighbors all unions))
      check (observed == expected) "original traversal order or actual route differs"
      count := count+1
  return count

def run : IO Unit := do
  let mut compared := 0
  for size in [0,1,2,8,64] do compared := compared+(← collisionChecks size)
  let mut graphCases := 0
  for size in [0,1,2,4,8,16] do graphCases := graphCases+(← graphChecks size)
  IO.println (Json.mkObj [("allPassed",toJson true),("collisionLookupCases",toJson compared),
    ("graphRouteCases",toJson graphCases),("referenceOrderAndRoutesEqual",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress

end Eggshell.Research.SourceIncidenceChecks
