import Lean
import tools.DeferredCoverage

open Lean
namespace CanonicalSelectionAnalysis

structure FileId where
  relative : String
  fingerprint : String
  bytes : Nat
  deriving BEq, Hashable, FromJson, ToJson
structure Key where
  file : FileId
  line : Nat
  deriving BEq, Hashable, FromJson, ToJson
structure Binding where
  owner : String
  deriving FromJson
structure Origin where
  binding : Binding
  deriving FromJson
structure Row where
  key : Key
  origins : Array Origin
  deriving FromJson
structure Family where
  owner : String
  windows : List Nat
  referenceRanks : List (Nat × Nat)
  referenceRanges : List (Nat × List (Nat × Nat))
  synapticRanges : List (Nat × Nat × Nat)
  rows : Array Row
  deriving FromJson
structure UnitRow where
  family : Nat
  ranges : List (Nat × Nat)
  sharedRows : Option (Array Key)
  deriving FromJson
structure Piece where
  family : Nat
  first : Nat
  last : Nat
  weight : Nat
  baseWeight : Nat
  sourceKey : Option Key
  deriving FromJson
structure Snapshot where
  families : Array Family
  units : Array UnitRow
  pieces : Array Piece
  costs : Array (Nat × Nat)
  weights : Array Nat
  offers : Array (List Nat × List Nat)
  fixed : Nat × Nat
  limit : Nat × Nat
  recipes : Array (List Nat × List Nat)
  chosen : List Nat
  expanded : List Nat
  deriving FromJson
structure Requirement where
  name : String
  path : String
  first : Nat
  last : Nat
  originalOwners : Array String
  deriving FromJson
structure CaseRow where
  stage : Nat
  required : Array Requirement
  deriving FromJson

def fins (bound : Nat) (values : List Nat) : Except String (List (Fin bound)) :=
  values.mapM fun value => if h : value < bound then .ok ⟨value,h⟩ else .error "invalid snapshot index"

def problem (snapshot : Snapshot) : Except String SharedCoverage.Problem := do
  let offers ← snapshot.offers.mapM fun (closure,covers) => do
    let closure ← fins snapshot.costs.size closure
    let covers ← fins snapshot.weights.size covers
    pure ({closure,covers} : SharedCoverage.Offer snapshot.costs.size snapshot.weights.size)
  pure {costs := snapshot.costs,weights := snapshot.weights,offers,fixed := snapshot.fixed,limit := snapshot.limit}

def selectedKeys (snapshot : Snapshot) (indices : List Nat) : List Key :=
  Eggshell.hashDistinct (indices.flatMap fun index =>
    ((snapshot.units[index]?).bind (·.sharedRows)).getD #[] |>.toList)

def covers (files : Array FileId) (requirement : Requirement) (keys : List Key) : Bool :=
  files.any fun file => (List.range (requirement.last+1-requirement.first)).all fun offset =>
    keys.contains ⟨file,requirement.first+offset⟩

def eligibleFiles (snapshot : Snapshot) (requirement : Requirement) : Array FileId :=
  (snapshot.families.toList.flatMap fun family => family.rows.toList.filterMap fun row =>
    if row.key.file.relative == requirement.path && row.origins.any
      (fun origin => requirement.originalOwners.contains origin.binding.owner) then some row.key.file else none).eraseDups.toArray

def directory (pieces : Array Piece) : Array (Option Key) := Id.run do
  let mut seen : Std.HashSet Key := {}
  let mut keys := #[]
  for piece in pieces do
    if let some key := piece.sourceKey then
      if seen.contains key then continue
      seen := seen.insert key
    keys := keys.push piece.sourceKey
  return keys

def evaluate (snapshot : Snapshot) (requirements : Array Requirement) : Except String Json := do
  let p ← problem snapshot
  let chosen ← fins p.offers.size snapshot.expanded
  let total := SharedCoverage.cost p chosen
  unless total.1 ≤ p.limit.1 && total.2 ≤ p.limit.2 do throw "recorded selected payload exceeds original bounds"
  let keys := selectedKeys snapshot snapshot.expanded
  let allKeys := selectedKeys snapshot (List.range snapshot.units.size)
  let sourceKeys := directory snapshot.pieces
  let details ← requirements.mapM fun requirement => do
    let files := eligibleFiles snapshot requirement
    let isRequired := fun (key : Key) => files.contains key.file &&
      requirement.first ≤ key.line && key.line ≤ requirement.last
    let candidates := (List.range snapshot.units.size).filter fun index =>
      covers files requirement (selectedKeys snapshot [index])
    let units ← candidates.mapM fun index => do
      let [value] ← fins p.offers.size [index] | throw "unit index changed"
      let alone := SharedCoverage.cost p [value]
      let together := SharedCoverage.cost p (chosen ++ [value])
      pure (Json.mkObj [("index",toJson index),("family",toJson ((snapshot.units[index]?).map (·.family))),
        ("selected",toJson (snapshot.expanded.contains index)),("aloneCost",toJson alone),
        ("additionalCost",toJson (together.1-total.1,together.2-total.2)),
        ("fitsAfterSelection",toJson (together.1 ≤ p.limit.1 && together.2 ≤ p.limit.2))])
    let graphRecipes ← ((List.range snapshot.recipes.size).drop p.offers.size).filterMapM fun index => do
      let some (parts,bonus) := snapshot.recipes[index]? | throw "recipe index missing"
      let offered := selectedKeys snapshot parts
      if !offered.any isRequired then return none
      let parts ← fins p.offers.size parts
      let alone := SharedCoverage.cost p parts
      let together := SharedCoverage.cost p (chosen ++ parts)
      pure (some (Json.mkObj [("index",toJson index),("selected",toJson (snapshot.chosen.contains index)),
        ("parts",toJson (parts.map (·.val))),("completeRequiredRange",toJson (covers files requirement offered)),
        ("bonusCues",toJson bonus.length),("aloneCost",toJson alone),
        ("fitsAlone",toJson (alone.1 ≤ p.limit.1 && alone.2 ≤ p.limit.2)),
        ("additionalCost",toJson (together.1-total.1,together.2-total.2))]))
    let pieces := snapshot.pieces.filter fun piece => piece.sourceKey.any isRequired
    let actualWeights := sourceKeys.zipIdx.filterMap fun (key,index) =>
      if key.any isRequired then some (key,(snapshot.weights[index*2]?).getD 0,
        (snapshot.weights[index*2+1]?).getD 0) else none
    pure (Json.mkObj [("name",toJson requirement.name),("originalFilesInAdmittedDomain",toJson files),
      ("selected",toJson (covers files requirement keys)),("candidateUnionCoversRange",toJson (covers files requirement allKeys)),
      ("completeCandidateCount",toJson units.length),("completeCandidates",toJson units),
      ("sourceCuePieces",toJson pieces.size),("positiveBasePieces",toJson (pieces.filter (·.baseWeight > 0)).size),
      ("positiveGraphPieces",toJson (pieces.filter fun piece => piece.baseWeight < piece.weight).size),
      ("canonicalCueWeights",toJson actualWeights),("graphRecipes",toJson graphRecipes)])
  pure (Json.mkObj [("families",toJson snapshot.families.size),("units",toJson snapshot.units.size),
    ("recipes",toJson snapshot.recipes.size),("selectedOffers",toJson snapshot.chosen.length),
    ("expandedUnits",toJson snapshot.expanded.length),("selectedCost",toJson total),("limit",toJson p.limit),
    ("requirements",toJson details)])
end CanonicalSelectionAnalysis

open CanonicalSelectionAnalysis
/-- Post-hoc read-only diagnosis. Human requirements cannot enter the producer,
extractor, graph, selector, numerical runtime or stored snapshot. -/
def main (args : List String) : IO Unit := do
  let [specification,root,destination] := args |
    throw (IO.userError "CanonicalSelectionAnalysis SPEC PROBE-ROOT OUTPUT")
  let cases ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk specification)) >>= fromJson? (α := Array CaseRow))
  let mut reports := #[]
  for row in cases do
    let path := System.FilePath.mk root / s!"probe-stage{row.stage}" / "selection.json"
    if !(← path.pathExists) then continue
    let snapshot ← IO.ofExcept (Json.parse (← IO.FS.readFile path) >>= fromJson? (α := Snapshot))
    let report ← IO.ofExcept (evaluate snapshot row.required)
    reports := reports.push (report.setObjVal! "stage" (toJson row.stage))
  IO.FS.writeFile (.mk destination) (toJson reports).compress
  IO.println s!"audited {reports.size} recorded selection snapshots"
