import tools.research.SelectorFixture
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter
namespace BaseCueScanChecks

def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)

def accept (shape : UnitShape) (entry : CuePiece × Nat) : Bool :=
  entry.1.baseWeight > 0 && entry.1.family == shape.family &&
    shape.ranges.any (fun (a,b) => a ≤ entry.1.first && entry.1.last ≤ b)

/-- Keep the original total predicate: even empty or inverted input pieces
can satisfy it. They have a separate nomination, not an altered acceptance. -/
def rangeKey (entry : CuePiece × Nat) : String :=
  if entry.1.first < entry.1.last then cueBucketKey entry else cueFamilyKey entry++":unordered"

def requested (shape : UnitShape) : List String :=
  shape.bucketKeys cueBucketWidth ++ [toString shape.family++":unordered"]

@[noinline, nospecialize] def familyRows (entries : Array (CuePiece × Nat))
    (index : PreparedCueIndex.Prepared cueFamilyKey entries) (shape : UnitShape) : List (CuePiece × Nat) :=
  index.one (toString shape.family) (accept shape)

@[noinline, nospecialize] def rangeRows (entries : Array (CuePiece × Nat))
    (index : PreparedCueIndex.Prepared rangeKey entries) (shape : UnitShape) : List (CuePiece × Nat) :=
  index.many (requested shape) (accept shape)

def checksum (rows : List (CuePiece × Nat)) : Nat :=
  rows.foldl (fun value entry => (value*31+entry.2+1)%1000000007) 0

def boundaries : IO Nat := do
  let entries := ([(0,0),(0,1),(1,0),(2,2),(510,514),(512,513),(1000,2)].flatMap fun (first,last) =>
    [({family := 0,first,last,weight := 1,baseWeight := 1} : CuePiece),
     {family := 1,first,last,weight := 1,baseWeight := 0}]).zipIdx.toArray
  let byFamily := PreparedCueIndex.prepare cueFamilyKey entries
  let byRange := PreparedCueIndex.prepare rangeKey entries
  let mut n := 0
  for ranges in [[],[(0,0)],[(0,1)],[(0,2),(2,514)],[(0,2),(4,514)],[(510,513),(512,515)],[(4,2)]] do
    for family in [:3] do
      let shape : UnitShape := {family,ranges}
      let expected := entries.toList.filter (accept shape)
      check ((familyRows entries byFamily shape).map Prod.snd == expected.map Prod.snd &&
        (rangeRows entries byRange shape).map Prod.snd == expected.map Prod.snd)
        "range nomination changed zero/reversed/overlap/gap/duplicate semantics"
      n := n+1
  return n

def observe (_choose : Bool) (_expected : ServiceChoice) (_query : ServiceQuery)
    (units : Array ServiceUnit) (pieces : List CuePiece) (_source : Synapses.PreparedSourceView.Domain) : IO (Option Json) := do
  let entries := pieces.zipIdx.toArray
  let familyStart ← IO.monoNanosNow
  let byFamily := PreparedCueIndex.prepare cueFamilyKey entries
  let familyBuild := (← IO.monoNanosNow)-familyStart
  let rangeStart ← IO.monoNanosNow
  let byRange := PreparedCueIndex.prepare rangeKey entries
  let rangeBuild := (← IO.monoNanosNow)-rangeStart
  let mut oldChecks := 0
  let mut proposedChecks := 0
  let mut matched := 0
  for unit in units do
    let expected := familyRows entries byFamily unit.shape
    let actual := rangeRows entries byRange unit.shape
    check (actual.map Prod.snd == expected.map Prod.snd) "actual ordered base cue IDs changed"
    matched := matched+expected.length
    oldChecks := oldChecks+(byFamily.index.postings[toString unit.shape.family]?.getD []).length
    for key in (requested unit.shape).eraseDups do
      proposedChecks := proposedChecks+(byRange.index.postings[key]?.getD []).length
  let mut timings := #[]
  for round in [:3] do
    let mut totals := #[]
    for narrowed in (if round%2 == 0 then [false,true] else [true,false]) do
      let started ← IO.monoNanosNow
      let result := units.foldl (fun total unit => total+checksum
        (if narrowed then rangeRows entries byRange unit.shape else familyRows entries byFamily unit.shape)) 0
      let result ← (← IO.mkRef result).get
      let elapsed := (← IO.monoNanosNow)-started
      timings := timings.push (Json.mkObj [("round",toJson round),("rangeNarrowed",toJson narrowed),
        ("nanos",toJson elapsed),("checksum",toJson result)])
      totals := totals.push result
    check (totals[0]? == totals[1]?) "timed actual base cue IDs changed"
  return some (Json.mkObj [("units",toJson units.size),("pieces",toJson entries.size),
    ("unorderedPieces",toJson (pieces.countP fun piece => piece.last ≤ piece.first)),
    ("matchedCueReferences",toJson matched),("familyCandidateChecks",toJson oldChecks),
    ("rangeCandidateChecks",toJson proposedChecks),("familyBuildNanos",toJson familyBuild),
    ("rangeBuildNanos",toJson rangeBuild),("allOrderedIdsExact",toJson true),("timings",toJson timings)])
end BaseCueScanChecks

def main (args : List String) : IO Unit := do
  let [project,fixture,output] := args | throw (IO.userError "BaseCueScanChecks PROJECT FIXTURE OUTPUT")
  let cases ← BaseCueScanChecks.boundaries
  unless cases == 21 do throw (IO.userError "all boundary controls required")
  SelectorStructure.runObserved BaseCueScanChecks.observe false (.mk project) (.mk fixture) (.mk output)
