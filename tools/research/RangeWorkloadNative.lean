module
public import tools.research.ProductRangeIncidence
public import Eggshell.CanonicalSourceCache
public import tools.research.SelectionReceipt
import Lean.Data.Json.FromToJson
@[expose] public section
namespace Eggshell.Research.RangeWorkloadNative
open Lean Plugin Plugin.SharedRangeAdapter Synapses
open RangeIncidence
abbrev Entry := CuePiece × Nat
abbrev Request := FactoredIncidence.Request (Coordinate Nat) Entry

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress

structure UnitData where
  family : Nat
  ranges : List (Nat × Nat)
  keys : Array CanonicalSource.Key
  generic : Option Nat

structure Input where
  units : Array UnitData
  pieces : List Entry
  owners : Array String
  files : Array Json

def decode (witness : Json) : Except String Input := do
  let owners ← witness.getObjValAs? (Array String) "owners"
  let nodes ← witness.getObjValAs? (Array (Option Nat × CanonicalSource.Key)) "sourceNodes"
  let mut keys : Std.HashMap Nat CanonicalSource.Key := {}
  for (id,key) in nodes do
    let some id := id | throw "captured source row has no cost identity"
    unless !keys.contains id do throw "captured source row identity is repeated"
    keys := keys.insert id key
  let rawUnits ← witness.getObjValAs? (Array (Array Json)) "units"
  let units ← rawUnits.mapM fun row => do
    unless row.size == 4 do throw "invalid captured unit width"
    let family ← fromJson? row[0]!
    unless family < owners.size do throw "captured unit escaped its owner domain"
    let ranges ← fromJson? row[1]!
    let ids ← fromJson? (α := Array (Option Nat)) row[2]!
    let selected ← ids.mapM fun id => do
      let some id := id | throw "captured unit source key has no cost identity"
      let some key := keys[id]? | throw "captured unit source key is absent"
      pure key
    let generic ← fromJson? row[3]!
    return ({family,ranges,keys := selected,generic} : UnitData)
  let rawPieces ← witness.getObjValAs? (Array (Array Json)) "pieces"
  let pieces ← rawPieces.toList.zipIdx.mapM fun (row,id) => do
    unless row.size == 6 do throw "invalid captured piece width"
    let family ← fromJson? row[0]!
    unless family < owners.size do throw "captured piece escaped its owner domain"
    let first ← fromJson? row[1]!
    let last ← fromJson? row[2]!
    let baseWeight ← fromJson? row[3]!
    let weight ← fromJson? row[4]!
    let source ← fromJson? (α := Option Nat) row[5]!
    let sourceKey ← source.mapM fun id => do
      let some key := keys[id]? | throw "captured piece source key is absent"
      pure key
    pure (({family,first,last,baseWeight,weight,sourceKey} : CuePiece),id)
  let files ← witness.getObjValAs? (Array Json) "files"
  return ⟨units,pieces,owners,files⟩

def geometry (input : Input) (unit : Nat) : Geometry Nat :=
  match input.units[unit]? with
  | none => ⟨input.owners.size,[]⟩
  | some unit => ⟨unit.family,unit.ranges⟩

def prepare (input : Input) := Id.run do
  let units := List.range input.units.size
  let mut ids : Std.HashMap (Geometry Nat) Nat := {}
  let mut classes := #[]
  let mut assignments := #[]
  for unit in units do
    let shape := geometry input unit
    let id := ids[shape]?.getD classes.size
    if id == classes.size then ids := ids.insert shape id; classes := classes.push shape
    assignments := assignments.push id
  return Sharing.check (geometry input) units (fun unit => assignments[unit]?.getD classes.size) classes

@[noinline,nospecialize] def reference (input : Input) : Array (List Nat) :=
  let index := PreparedCueIndex.prepare cueFamilyKey input.pieces.toArray
  input.units.map fun unit =>
    (index.one (toString unit.family) fun entry =>
      entry.1.baseWeight > 0 && entry.1.family == unit.family &&
        unit.ranges.any (fun (first,last) => first ≤ entry.1.first && entry.1.last ≤ last)).map Prod.snd

def requests (input : Input) : List Request := input.pieces.map fun entry =>
  ⟨⟨entry.1.family,entry.1.first,entry.1.last⟩,entry.1.baseWeight > 0,entry⟩

@[noinline,nospecialize] def indexed (input : Input)
    (ready : Sharing (geometry input) (List.range input.units.size)) : Array (List Nat) :=
  let query := ready.project (requests input)
  (List.range input.units.size).attach.toArray.map fun unit =>
    (query.table.getD ⟨ready.classOf unit.val,ready.admitted unit.val unit.property⟩ []).map (·.value.2)

structure Prepared where
  input : Input
  index : Sharing (geometry input) (List.range input.units.size)

def measured (action : IO (Array (List Nat))) : IO (Array (List Nat) × Nat) := do
  let began ← IO.monoNanosNow
  let rows ← action
  let rows ← (← IO.mkRef rows).get
  return (rows,((← IO.monoNanosNow)-began)/1000)

/-- Read the same pinned publication metadata. No query, source text decoder,
embedding, repair, latest-root substitution or new cache is involved. -/
def catalogue (source : DB.PageMap.Snapshot) (recipes : DB.PageMap.Snapshot) (input : Input) : IO Json := do
  let mut result := #[]
  let mut staticUnits := 0
  let mut dynamicUnits := 0
  for file in input.files do
    let family ← IO.ofExcept (file.getObjValAs? Nat "family")
    let owner ← IO.ofExcept (file.getObjValAs? String "owner")
    check (input.owners[family]? == some owner) "captured owner differs from its file family"
    let ready ← PreparedSourceView.readOwner recipes source.head.identity owner
    let shapes := Std.HashSet.ofArray (ready.units.map (fun unit => (unit.ranges,unit.keys)))
    let ranges := Std.HashSet.ofArray (ready.units.map (·.ranges))
    let units := input.units.filter (fun unit => unit.family == family && unit.generic.isNone)
    let fully := units.countP (fun unit => shapes.contains (unit.ranges,unit.keys))
    let rangeOnly := units.countP (fun unit => ranges.contains unit.ranges)
    staticUnits := staticUnits+fully
    dynamicUnits := dynamicUnits+(units.size-fully)
    let descriptor ← recipes.get (PreparedSourceView.ownerName owner)
    result := result.push (Json.mkObj [("owner",toJson owner),("family",toJson family),
      ("databaseIdentity",toJson source.head.identity),("metadataReference",toJson (descriptor.map Blake3.hex)),
      ("publishedUnits",toJson ready.units.size),("queryUnits",toJson units.size),
      ("sameRangesAndSourceKeys",toJson fully),("sameRangesOnly",toJson rangeOnly),
      ("additionalQueryUnits",toJson (units.size-fully))])
  return Json.mkObj [("owners",toJson result),("staticUnits",toJson staticUnits),("dynamicUnits",toJson dynamicUnits),
    ("genericUnits",toJson (input.units.countP (·.generic.isSome))),("questionIndependentCatalogueVerified",toJson true)]

def run (inputPath output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve real range report"
  let captured ← read inputPath
  let data : System.FilePath := .mk (← IO.ofExcept (captured.getObjValAs? String "data"))
  let trial : System.FilePath := .mk (← IO.ofExcept (captured.getObjValAs? String "output"))
  let original : System.FilePath := .mk (← IO.ofExcept (captured.getObjValAs? String "project"))
  let source ← DB.PageMap.pin original
  let cache := data/"read-cache"/source.head.identity/"canonical-source"
  let some manifest ← CanonicalSource.Cache.manifestAt? source cache | throw (IO.userError "current prepared source manifest absent")
  let some recipes ← CanonicalSource.Cache.preparedAt? source cache manifest | throw (IO.userError "checked recipe snapshot absent")
  let clients ← IO.ofExcept (fromJson? (α := Array Json) (← read (trial/"prime.json")))
  let mut reports := #[]
  for client in clients do
    let topic ← IO.ofExcept (client.getObjValAs? Nat "topic")
    let receipt ← IO.ofExcept (client.getObjValAs? String "receipt")
    let decision ← Receipt.readSelection (data/"receipts"/receipt)
    let witness ← IO.ofExcept (decode (decision.getObjValD "selectionWitness"))
    let preparationStart ← IO.monoNanosNow
    let some ready := prepare witness | throw (IO.userError "real geometry certificate rejected")
    let prepared ← (← IO.mkRef ready).get
    let preparationUs := ((← IO.monoNanosNow)-preparationStart)/1000
    let stored ← catalogue source recipes witness
    let input ← IO.mkRef (⟨witness,prepared⟩ : Prepared)
    let mut trials := #[]
    let mut hits := 0
    for round in [:3] do
      let a := measured (do pure (reference (← input.get).input))
      let b := measured (do let value ← input.get; pure (indexed value.input value.index))
      let (a,b) ← if round%2 == 0 then do let a ← a; let b ← b; pure (a,b)
        else do let b ← b; let a ← a; pure (a,b)
      check (a.1 == b.1) "real product base matching changed order or source piece identity"
      hits := a.1.foldl (fun total row => total+row.length) 0
      trials := trials.push (Json.mkObj [("referenceUs",toJson a.2),("indexedUs",toJson b.2),("allOrderedPieceIdsEqual",toJson true)])
    reports := reports.push (Json.mkObj [("topic",toJson topic),("receipt",toJson receipt),
      ("actualHookSucceeded",client.getObjValD "success"),("units",toJson witness.units.size),
      ("pieces",toJson witness.pieces.length),("geometryClasses",toJson prepared.classes.size),
      ("structuralRanges",toJson (witness.units.foldl (fun total unit => total+unit.ranges.length) 0)),
      ("baseHits",toJson hits),("classAndTreePreparationUs",toJson preparationUs),
      ("selectionPlanJsonBytes",toJson decision.compress.utf8ByteSize),
      ("operationFrameBytes",toJson Daemon.maxFrameBytes),("catalogue",stored),("trials",toJson trials)])
  let after ← DB.PageMap.pin original
  check (after.head == source.head) "real range analysis changed source head"
  write output (Json.mkObj [("topics",toJson reports),("sourceHead",toJson source.head),
    ("recipeHead",toJson recipes.head),("originalHeadUnchanged",toJson true),
    ("nativeMetadataReadOnly",toJson true),("baseMatchingOnly",toJson true),
    ("wholeHookOrTokenImprovementMeasured",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
end Eggshell.Research.RangeWorkloadNative
def main (args : List String) : IO Unit := do
  let [input,output] := args | throw (IO.userError "real range input and report required")
  Eggshell.Research.RangeWorkloadNative.run (.mk input) (.mk output)
