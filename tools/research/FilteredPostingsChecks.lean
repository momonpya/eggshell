import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter

#print axioms OwnerUnitPostings.Index.select_filtered_exact
#print axioms OwnerUnitPostings.select_filter_compiled
#print axioms PreparedCueIndex.Prepared.many_exact
#print axioms Plan.keeps_control
#print axioms Plan.within_budget

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

/-- Retain the old full-tree construction explicitly, so the compiled
select replacement cannot turn the independent native reference into itself. -/
private def reference {n : Nat} {ownerOf : Fin n → Option String}
    (index : OwnerUnitPostings.Index ownerOf) (keys : List String)
    (accept : Fin n → Bool) : List (Fin n) :=
  (index.union keys).toList.filter accept

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "new native result directory required")
  let root := System.FilePath.mk output
  check (!(← root.pathExists)) "preserve previous posting checks"
  IO.FS.createDir root
  let mut cases := 0
  let mut oldInsertions := 0
  let mut filteredInsertions := 0
  for size in [0,1,2,17,129,1024] do
    let ownerOf := fun i : Fin size =>
      if i.val%7 == 0 then none else some ("owner-" ++ toString (i.val%4))
    let index := OwnerUnitPostings.prepare ownerOf
    for keys in [[],["missing"],["owner-0"],["owner-0","owner-0"],
        ["owner-2","owner-0"],["owner-3","missing","owner-0","owner-2","owner-1"],
        ["owner-3","owner-2","owner-1","owner-0","owner-1"]] do
      for divisor in [1,2,5] do
        for mode in [0,1,2] do
          let accept := fun i : Fin size =>
            if mode == 0 then false else if mode == 1 then true else i.val%divisor == 0
          let expected := reference index keys accept
          let selected := index.select keys accept
          let narrowed := index.selectFiltered keys accept
          check (selected == expected && narrowed == expected)
            "filter-before-union changed candidate IDs, duplicates or original tie order"
          oldInsertions := oldInsertions+(keys.flatMap fun key => index.postings[key]?.getD []).length
          filteredInsertions := filteredInsertions+(keys.flatMap fun key =>
            (index.postings[key]?.getD []).filter accept).length
          cases := cases+1
  let size := 6000
  let ownerOf := fun i : Fin size => some ("family-" ++ toString (i.val/400))
  let index := OwnerUnitPostings.prepare ownerOf
  let run := fun (fast : Bool) => do
    let started ← IO.monoMsNow
    let mut checksum := 0
    for query in [:1000] do
      let family := query%15
      let first := family*400+(query*17)%390
      let accept := fun i : Fin size => first ≤ i.val && i.val < first+6
      let keys := ["family-" ++ toString family]
      let rows := if fast then index.select keys accept else reference index keys accept
      checksum := checksum+rows.foldl (fun sum row => sum+row.val+1) 0
    pure ((← IO.monoMsNow)-started,checksum)
  let mut timings := #[]
  for round in [:3] do
    let order := if round%2 == 0 then [false,true] else [true,false]
    let mut totals := #[]
    for fast in order do
      let (elapsed,checksum) ← run fast
      totals := totals.push checksum
      timings := timings.push (round,fast,elapsed,checksum)
    check (totals[0]? == totals[1]?) "sparse-recipe microbenchmark changed selected IDs"
  IO.FS.writeFile (root / "result.json") (Json.mkObj [
    ("allPassed",toJson true),("nativeDifferentialCases",toJson cases),
    ("oldTreeInsertionsInFixtures",toJson oldInsertions),
    ("filteredTreeInsertionsInFixtures",toJson filteredInsertions),
    ("microbenchRows",toJson size),("microbenchQueriesPerArm",toJson (1000 : Nat)),
    ("microbenchRounds",toJson (3 : Nat)),("microbenchTimingsRoundFastMsChecksum",toJson timings),
    ("candidateOrderAndDuplicatesPreserved",toJson true),("productionLatencyClaim",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
