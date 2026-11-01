import tools.research.BindingPageScan
import tools.research.BindingPageOracle
import tools.research.ArtifactHash
open Lean Eggshell Eggshell.Synapses

#print axioms Eggshell.Research.CertifiedRangeDirectory.Tree.find_exact
#print axioms Eggshell.Research.CertifiedRangeDirectory.Tree.overlap_exact
#print axioms BindingPageScan.ReadDirectory.find_exact
#print axioms BindingPageScan.ReadDirectory.find_after_filter

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def projection (result : IndexedBindings.Resolved) : Json :=
  Json.mkObj [("rows",toJson (result.rows.toArray.qsort fun a b => (toJson a.1).compress < (toJson b.1).compress)),
    ("complete",toJson result.complete),("requests",toJson result.requests),("inspected",toJson result.inspected),
    ("bytes",toJson result.bytes),("unresolved",toJson result.unresolved),("unusable",toJson result.unusable)]

def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/certified-binding"
  check (!(← (records / "reader-result.json").pathExists)) "preserve completed reader comparison"
  let database := root / "selection-witness-trial/candidate/work.egg"
  let source ← DB.PageMap.pin database
  let path := database / "derived" / source.head.identity / "synapses/recommendations"
  let index ← DB.PageMap.pin path
  let some manifest ← Index.manifest? index | throw (IO.userError "prepared binding manifest missing")
  check (manifest.scope == .shared && manifest.source == source.head && manifest.implementation == Index.implementation)
    "prepared binding source or implementation changed"
  let reader : Index.Reader := ⟨index,manifest⟩
  let saved ← read (root / "selection-witness-trial/candidate/data/receipts/506bf0da7d3f58bd61aa14c5316459f76ee91dd49b89b4377abe48142ec4e66d/synaptic-delivery.json")
  let rows : Array Json ← IO.ofExcept ((saved.getObjValD "data").getObjValAs? _ "sharedRows")
  let mut wanted := #[]
  let mut allowed : Std.HashSet String := {}
  for row in rows do
    let range : Range ← IO.ofExcept (row.getObjValAs? _ "source")
    wanted := wanted.push range
    let owner : String ← IO.ofExcept ((row.getObjValD "binding").getObjValAs? _ "owner")
    allowed := allowed.insert owner
  wanted := (hashDistinct wanted.toList).toArray
  check (!wanted.isEmpty) "retained operational query ranges missing"
  let missing := wanted.extract 0 20 |>.map fun range => {range with first := range.first+1000000,last := range.last+1000000}
  let cases := #[("empty",#[]),("single",wanted.extract 0 1),("small",wanted.extract 0 64),
    ("retained",wanted),("absent",missing),("mixed",wanted ++ missing)]
  IO.FS.writeFile (records / "before-reader.json") (Json.mkObj [("source",toJson source.head),
    ("index",toJson index.head),("cases",toJson (cases.map fun (name,ranges) => (name,ranges.size))),
    ("repetitions",toJson (3 : Nat)),("goldRead",toJson false),("modelCalls",toJson (0 : Nat))]).pretty
  let mut measurements := #[]
  for (name,ranges) in cases do
    for repetition in [:3] do
      let mut reference : Option (Json × Nat × Nat × Nat) := none
      let mut candidate : Option (Json × Nat × Nat × Nat) := none
      for fast in (if repetition % 2 == 0 then [false,true] else [true,false]) do
        let started ← IO.monoMsNow
        let (value,pages,leaves) ← if fast then do
          let result ← BindingPageScan.resolveReport reader ranges allowed (started+60000)
          pure (result.resolved,result.pages,result.leaves)
        else do
          let result ← BindingPageOracle.resolveReport reader ranges allowed (started+60000)
          pure (result.resolved,result.pages,result.leaves)
        let elapsed := (← IO.monoMsNow)-started
        check value.complete "component comparison was incomplete"
        let outcome := (projection value,elapsed,pages,leaves)
        if fast then candidate := some outcome else reference := some outcome
      let some (before,beforeMs,beforePages,beforeLeaves) := reference | throw (IO.userError "missing reference")
      let some (after,afterMs,afterPages,afterLeaves) := candidate | throw (IO.userError "missing candidate")
      check (before == after && beforePages == afterPages && beforeLeaves == afterLeaves)
        "certified directory changed actual binding rows, ordering, counters or physical page selection"
      let result := Json.mkObj [("case",toJson name),("repetition",toJson repetition),("targets",toJson ranges.size),
        ("referenceMs",toJson beforeMs),("candidateMs",toJson afterMs),("pages",toJson beforePages),
        ("leaves",toJson beforeLeaves),("resultSha256",toJson (Sha256.hex before.compress.toUTF8)),("identical",toJson true)]
      measurements := measurements.push result
      IO.println result.compress
  check ((← DB.PageMap.pin database).head == source.head && (← DB.PageMap.pin path).head == index.head)
    "read-only component comparison changed a publication"
  IO.FS.writeFile (records / "reader-result.json") (Json.mkObj [("source",toJson source.head),("index",toJson index.head),
    ("measurements",toJson measurements),("changedSource",toJson false),("createdDbOrCache",toJson false),
    ("modelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
