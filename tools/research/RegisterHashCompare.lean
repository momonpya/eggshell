import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (p : System.FilePath) : IO Json :=
  IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def hash (p : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",p.toString]}
  check (result.exitCode == 0) "cannot seal benchmark artifact"
  let some first := (result.stdout.splitOn " ").head? | throw (IO.userError "missing artifact hash")
  check (first.length == 64) "invalid artifact hash"
  return first
private def median (values : Array Nat) : IO Nat := do
  check (values.size == 6) "predeclared six timings per arm and size changed"
  let sorted := values.qsort (· < ·)
  let some a := sorted[2]? | throw (IO.userError "missing lower median")
  let some b := sorted[3]? | throw (IO.userError "missing upper median")
  return (a+b)/2

def main (args : List String) : IO Unit := do
  check args.isEmpty "fixed native hash comparison only"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/register-hash"
  let out := records / "comparison"
  check (!(← out.pathExists)) "preserve completed fixed comparison"
  let baseline := root / "register-hash-baseline-build"
  let candidate := root / "register-hash-candidate-build"
  for name in ["tools_research_RegisterHashBench.source","tests_Blake3Fixtures.source"] do
    check ((← IO.FS.readBinFile (baseline / name)) == (← IO.FS.readBinFile (candidate / name)))
      "hash arms changed the benchmark or its known-answer tests"
  let mut seals := #[]
  for file in [baseline / "StudyMain",candidate / "StudyMain",project / "tools/research/RegisterMix.lean",
      project / "tools/research/RegisterHashBench.lean",root / "query-cache-baseline-core/Eggshell/Blake3.lean",
      root / "register-hash-core/Eggshell/Blake3.lean"] do
    seals := seals.push (file.toString,← hash file)
  IO.FS.createDirAll out
  IO.FS.writeFile (out / "sealed-inputs.json") (toJson seals).pretty
  let mut results := #[]
  for (round,order) in #[(0,#["baseline","candidate"]),(1,#["candidate","baseline"])] do
    for arm in order do
      let binary := (if arm == "baseline" then baseline else candidate) / "StudyMain"
      let target := out / s!"order-{round}-{arm}"
      let response ← IO.Process.output {cmd := binary.toString,args := #[target.toString,arm]}
      check (response.exitCode == 0) s!"fixed hash arm failed: {arm}"
      let value ← read (target / "result.json")
      check (value.getObjValD "arm" == toJson arm && value.getObjValD "knownAnswerChecks" == toJson (2 : Nat) &&
        value.getObjValD "segmentationChecks" == toJson (63 : Nat)) "fixed checks changed between arms"
      results := results.push (value.setObjVal! "order" (toJson round))
      IO.println s!"Completed order {round}: {arm}"
  let mut timings : Std.HashMap (String × Nat) (Array Nat) := {}
  let mut checkedPairs := 0
  for round in [0:2] do
    let old ← match results.find? (fun row => row.getObjValD "order" == toJson round &&
        row.getObjValD "arm" == toJson "baseline") with
      | some row => pure row
      | none => throw (IO.userError "missing original hash arm")
    let next ← match results.find? (fun row => row.getObjValD "order" == toJson round &&
        row.getObjValD "arm" == toJson "candidate") with
      | some row => pure row
      | none => throw (IO.userError "missing candidate hash arm")
    check (old.getObjValD "boundaryDigests" == next.getObjValD "boundaryDigests") "boundary hashes changed"
    let before ← IO.ofExcept (old.getObjValAs? (Array Json) "samples")
    let after ← IO.ofExcept (next.getObjValAs? (Array Json) "samples")
    check (before.size == 9 && after.size == 9) "predeclared timing corpus changed"
    for (a,b) in before.zip after do
      for field in ["bytes","repetition","digest"] do
        check (a.getObjValD field == b.getObjValD field) "candidate changed a complete native digest"
      checkedPairs := checkedPairs+1
      for (arm,sample) in [("baseline",a),("candidate",b)] do
        let size ← IO.ofExcept (sample.getObjValAs? Nat "bytes")
        let elapsed ← IO.ofExcept (sample.getObjValAs? Nat "elapsedNs")
        check (0 < elapsed) "invalid native clock interval"
        let key := (arm,size)
        timings := timings.insert key ((timings[key]?.getD #[]).push elapsed)
  let mut summary := #[]
  for size in [65536,1048576,8388608] do
    let before := timings[("baseline",size)]?.getD #[]
    let after := timings[("candidate",size)]?.getD #[]
    let oldMedian ← median before
    let newMedian ← median after
    summary := summary.push (Json.mkObj [("bytes",toJson size),("baselineNs",toJson before),
      ("candidateNs",toJson after),("baselineMedianNs",toJson oldMedian),("candidateMedianNs",toJson newMedian),
      ("speedup",toJson (oldMedian.toFloat/newMedian.toFloat))])
  for (path,expected) in seals do check ((← hash (.mk path)) == expected) "benchmark inputs changed during comparison"
  IO.FS.writeFile (out / "result.json") (Json.mkObj [("allDigestsEqual",toJson true),
    ("matchedNativeDigestPairs",toJson checkedPairs),("summaries",toJson summary),
    ("inputHashesUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("actualHookCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
