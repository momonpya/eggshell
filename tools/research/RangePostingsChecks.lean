import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter

#print axioms PointBuckets.key_mem_keys
#print axioms UnitPlan.covered_first_bucket
#print axioms bonus_pieces_exact
#print axioms bundle_recipe_indexed_exact
#print axioms Plan.keeps_control
#print axioms Plan.within_budget

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def unit (family : Nat) (ranges : List (Nat × Nat)) : UnitPlan := {
  family,ranges,slice := {owner := none,keys := [],text := "",members := [],visibleKeys := []}}

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "new range-posting result directory required")
  let root := System.FilePath.mk output
  check (!(← root.pathExists)) "preserve earlier range checks"
  IO.FS.createDir root
  let mut pointChecks := 0
  for width in [0,1,7,16,512,1024] do
    for scope in ["0","other:scope"] do
      for (first,limit) in [(0,0),(4,2),(0,1),(1,2),(510,514),(511,512),(512,513),
          (500,530),(1020,1040),(0,1050)] do
        let keys := PointBuckets.keys width scope first limit
        if limit ≤ first then check keys.isEmpty "invalid interval populated range keys"
        for point in [0,1,first-1,first,first+1,limit-1,limit,limit+1,511,512,513,1023,1024,4096] do
          if first ≤ point && point < limit then
            check (keys.contains (PointBuckets.key width scope point)) "coarse interval lost an interior point"
          pointChecks := pointChecks+1
  let mut coveredChecks := 0
  for ranges in [[],[(0,0)],[(0,2),(4,6)],[(0,2),(2,6)],[(0,4),(2,6)],[(4,8),(0,5)],[(500,530),(1020,1040)]] do
    let candidate := unit 3 ranges
    for first in [0,1,2,3,4,5,6,7,8,500,511,512,529,530,1023,1024,1039,1040] do
      for last in [first,first+1,first+2,first+10] do
        if candidate.coversPrepared first last then
          for width in [0,1,7,16,512,1024] do
            check ((candidate.bucketKeys width).contains (PointBuckets.key width "3" first))
              "a covered cue was absent from the unit's bucket nomination"
            coveredChecks := coveredChecks+1
  let entries : Array (CuePiece × Nat) := (List.range 6000).map (fun id =>
    let first := (id%400)*32
    (({family := id/400,first,last := first+8,weight := 1,baseWeight := 0} : CuePiece),id)) |>.toArray
  let familyIndex := PreparedCueIndex.prepare cueFamilyKey entries
  let rangeIndex := PreparedCueIndex.prepare cueBucketKey entries
  let request := fun query =>
    let family := query%15
    let first := (query*17)%390*32
    unit family [(first,first+192)]
  let accept := fun (candidate : UnitPlan) (entry : CuePiece × Nat) =>
    entry.1.family == candidate.family && candidate.coversPrepared entry.1.first entry.1.last
  let mut exactChecks := 0
  let mut oldCandidates := 0
  let mut rangeCandidates := 0
  for query in [:60] do
    let candidate := request query
    let expected := entries.toList.filter (accept candidate)
    let requested := candidate.bucketKeys cueBucketWidth
    let old := familyIndex.many [toString candidate.family] (accept candidate)
    let selected := rangeIndex.many (requested ++ requested) (accept candidate)
    check (old.map (·.2) == expected.map (·.2) && selected.map (·.2) == expected.map (·.2))
      "range narrowing changed ordered cue IDs"
    oldCandidates := oldCandidates+(familyIndex.index.postings[toString candidate.family]?.getD []).length
    rangeCandidates := rangeCandidates+(requested.eraseDups.flatMap fun key =>
      rangeIndex.index.postings[key]?.getD []).length
    exactChecks := exactChecks+1
  let run := fun (fast : Bool) => do
    let started ← IO.monoMsNow
    let mut checksum := 0
    for query in [:1000] do
      let candidate := request query
      let rows := if fast then rangeIndex.many (candidate.bucketKeys cueBucketWidth) (accept candidate)
        else familyIndex.many [toString candidate.family] (accept candidate)
      checksum := checksum+rows.foldl (fun sum entry => sum+entry.2+1) 0
    pure ((← IO.monoMsNow)-started,checksum)
  let mut timings := #[]
  for round in [:3] do
    let mut totals := #[]
    for fast in (if round%2 == 0 then [false,true] else [true,false]) do
      let (elapsed,checksum) ← run fast
      totals := totals.push checksum
      timings := timings.push (round,fast,elapsed,checksum)
    check (totals[0]? == totals[1]?) "range query checksum changed"
  IO.FS.writeFile (root / "result.json") (Json.mkObj [
    ("allPassed",toJson true),("pointBoundaryChecks",toJson pointChecks),("coveredCueChecks",toJson coveredChecks),
    ("orderedCueComparisons",toJson exactChecks),("familyPostingCandidates",toJson oldCandidates),
    ("rangePostingCandidates",toJson rangeCandidates),("microbenchRows",toJson entries.size),
    ("microbenchQueriesPerArm",toJson (1000 : Nat)),("microbenchTimingsRoundFastMsChecksum",toJson timings),
    ("productionLatencyClaim",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
