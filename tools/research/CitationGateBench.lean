import tools.research.CitationGate
import Lean.Data.Json.FromToJson
open Lean Eggshell Eggshell.Plugin.SharedRangeAdapter
namespace Eggshell.Research.CitationGateBench
open CitationGate

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def subject : Synapses.Range := .original ⟨"synthetic",String.ofList (List.replicate 64 '0'),65536⟩ 0 65536
def bundle (owners : Nat) (spans : Nat → List (Nat × Nat)) : Synapses.AdvisoryBundles.Bundle :=
  ⟨(Array.range 61).map fun i => ⟨subject,#[⟨s!"owner-{i%owners}",spans i⟩]⟩⟩

def controls : IO Nat := do
  let split : Synapses.AdvisoryBundles.Bundle :=
    ⟨#[⟨subject,#[⟨"owner-0",[(1,4)]⟩,⟨"owner-0",[(4,8)]⟩]⟩]⟩
  let whole : Synapses.AdvisoryBundles.Bundle :=
    ⟨#[⟨subject,#[⟨"owner-0",[(1,4),(4,8)]⟩]⟩]⟩
  check (!(supportsOwner (prepare split) "owner-0" 1 8) &&
    supportsOwner (prepare whole) "owner-0" 1 8) "different citation alternatives were joined"
  let cases := #[split,whole,bundle 3 (fun _ => []),bundle 3 (fun _ => [(8,1),(2,2),(3,9)]),
    bundle 3 (fun _ => [(1,5),(1,5),(3,9)]),⟨#[]⟩]
  let mut count := 1
  for value in cases do
    let prepared := prepare value
    for key in ["owner-0","owner-1","unknown"] do
      for first in [:12] do
        for last in [:12] do
          let reference := value.members.any fun member => member.choices.any fun choice =>
            choice.owner == key && Eggshell.Plugin.SharedRangeAdapter.covers choice.spans first last
          check (supportsOwner prepared key first last == reference) "compiled citation changed an alternative"
          count := count+1
  return count

structure Input where
  keys : Array String
  units : Array UnitShape
  plan : BundlePlan keys units
  entries : Array (CuePiece × Nat)
  index : PreparedCueIndex.Prepared cueBucketKey entries

def make (owners count : Nat) (dense : Bool) : IO Input := do
  let keys := (Array.range owners).map fun i => s!"owner-{i}"
  let units : Array UnitShape := (Array.range 64).map fun i => {family := i%owners,ranges := [(0,65536)]}
  let projected := bundle owners (fun i => if dense then [(0,65536)] else [(i*512,i*512+32)])
  let indices := List.finRange units.size
  let plan ← if valid : projected.members.all (memberCovered keys units indices) = true then
    pure ({projected,indices,complete := valid} : BundlePlan keys units)
    else throw (IO.userError "synthetic bundle lacks a complete original binding")
  let entries : Array (CuePiece × Nat) := (Array.range count).map fun i =>
    (⟨i%owners,(i*7)%32768,(i*7)%32768+1,1,if i%11 == 0 then 1 else 0,none⟩,i)
  return ⟨keys,units,plan,entries,PreparedCueIndex.prepare cueBucketKey entries⟩

def fields (rows : List (CuePiece × Nat)) := rows.map fun (piece,id) =>
  (piece.family,piece.first,piece.last,piece.weight,piece.baseWeight,piece.sourceKey,id)

def measure (input : IO.Ref Input) (method : String) : IO (List (CuePiece × Nat) × Nat) := do
  let began ← IO.monoNanosNow
  let input ← input.get
  let rows := if method == "reference" then
    bonusPiecesPrepared input.keys input.units input.entries input.index input.plan
    else if method == "citation" then CitationGate.bonusPieces input.keys input.units input.entries input.index input.plan
    else if method == "keys" then Eggshell.Research.HashedCueKeys.many input.index
      (input.plan.indices.flatMap fun i => input.units[i].bucketKeys cueBucketWidth)
      (bonusPieceAccept input.keys input.units input.plan)
    else CitationGate.bonusPiecesHashed input.keys input.units input.entries input.index input.plan
  let rows ← (← IO.mkRef rows).get
  return (rows,((← IO.monoNanosNow)-began)/1000)

def run (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh citation component output required"
  IO.FS.createDirAll root
  let controls ← controls
  let cases := #[("dense",1,2048,true),("sparse",1,2048,false),
    ("mixed",46,2048,false),("larger-cue-domain",46,17414,false)]
  let orders := #[#["reference","citation","keys","combined"],#["combined","keys","citation","reference"],
    #["citation","reference","combined","keys"],#["keys","combined","reference","citation"]]
  let mut results := #[]
  for (label,owners,count,dense) in cases do
    let input ← IO.mkRef (← make owners count dense)
    let mut expected := none
    let mut measurements := #[]
    for order in orders do
      for method in order do
        let (rows,time) ← measure input method
        let output := fields rows
        if let some reference := expected then check (output == reference) "native ordered citation rows differ"
        else expected := some output
        measurements := measurements.push (Json.mkObj [("method",toJson method),("elapsedUs",toJson time),
          ("outputEntries",toJson rows.length),("exactOrderedOutput",toJson true)])
    results := results.push (Json.mkObj [("case",toJson label),("owners",toJson owners),
      ("units",toJson (64 : Nat)),("pieces",toJson count),("members",toJson (61 : Nat)),
      ("candidatePreparationIncluded",toJson true),("measurements",toJson measurements)])
    IO.FS.writeFile (root/"progress.json") (toJson results).compress
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("controls",toJson controls),
    ("cases",toJson results),("orders",toJson orders),("syntheticOnly",toJson true),
    ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.CitationGateBench
