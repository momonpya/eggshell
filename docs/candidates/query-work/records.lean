import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/query-work"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "identity hashing failed")
  return (result.stdout.splitOn " ").head!
def save (name : String) (value : Json) : IO Unit := IO.FS.writeFile (output/name) (value.compress++"\n")
def events (root : System.FilePath) (receipt : String) : IO (Array (String × Json)) := do
  let folder := root/"private/receipts"/receipt
  if !(← folder.pathExists) then return #[]
  let mut result := #[]
  for entry in ← folder.readDir do
    if entry.fileName.endsWith ".json" &&
        (["operation-","search-phase-","discovery-counters-","numerical-"].any (fun stem => entry.fileName.startsWith stem) ||
         ["search.json","transport.json","failure.json","prepared-inputs-turn.json","canonical-source-reuse.json"].contains entry.fileName) then
      result := result.push (entry.fileName,← read entry.path)
  return result
def main : IO Unit := do
  unless !(← (output/"evidence.json").pathExists) do throw (IO.userError "preserve sealed evidence")
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "query-work-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "query-work-records" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      let path := base/(entry.fileName.replace ".guard.json" ".log")
      let text ← IO.FS.readFile path
      let lines := text.splitOn "\n"
      guards := guards.push (Json.mkObj [("tag",toJson entry.fileName),("guard",guard),
        ("logSha256",toJson (← hash path)),("tail",toJson (String.intercalate "\n" (lines.drop (lines.length-16))))])
  let prior := base/"query-work-baseline-core/Eggshell/Handoff.lean"
  let current := base/"interest-traffic-core/Eggshell/Handoff.lean"
  let diff ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--",prior.toString,current.toString]}
  unless diff.exitCode ≤ 1 do throw (IO.userError "source diff failed")
  IO.FS.writeFile (output/"candidate.patch") (diff.stdout.replace
    ("a"++(base/"query-work-baseline-core").toString++"/") "a/"
    |>.replace ("b"++(base/"interest-traffic-core").toString++"/") "b/")
  let mut unchanged := #[]
  for name in ["MiniLM.lean","Numerical.lean","SearchProvider.lean","BlockScore.lean","GraphStore.lean","DB/PageMap.lean",
      "NativePublication.lean","ProjectSources.lean","PublicationService.lean","SearchRank.lean","SourceOwners.lean",
      "HookFrontend.lean","Matcher.lean","Extract.lean","Worker.lean","PluginHooks.lean","OperationPool.lean","Daemon.lean"] do
    let old ← hash (base/"query-work-baseline-core/Eggshell"/name)
    let actual ← hash (base/"interest-traffic-core/Eggshell"/name)
    unless old == actual do throw (IO.userError ("unrelated source changed: "++name))
    unchanged := unchanged.push (name,actual)
  let mut profiles := #[]
  for tag in ["query-work-profile3","query-work-sample1","query-work-sample2","query-work-candidate1","query-work-candidate-sample1"] do
    let root := base/("query-work-fixture-"++tag)
    if !(← root.pathExists) then continue
    let mut files := #[]
    for name in ["runtime.sha256","warm-result.json","rows.json","report.json","sampler.json",
        "cold-frontend-stdout.json","running-frontend-stdout.json","cold-frontend-trace.txt","running-frontend-trace.txt",
        "cold-frontend-stderr.txt","running-frontend-stderr.txt","stages.json"] do
      if ← (root/name).pathExists then files := files.push (name,← IO.FS.readFile (root/name))
    profiles := profiles.push (tag,files)
  let parent := base/"query-work-fixture-query-work-profile3"
  let candidate := base/"query-work-fixture-query-work-candidate1"
  let mut bodyChecks := #[]
  for name in ["cold-frontend","running-frontend"] do
    let body := fun (value : Json) => ((value.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
    let before := body (← read (parent/(name++"-stdout.json")))
    let after := body (← read (candidate/(name++"-stdout.json")))
    unless !before.isEmpty && before == after do throw (IO.userError "query optimization changed actual body")
    bodyChecks := bodyChecks.push (name,Json.mkObj [("byteIdentical",toJson true),("bodyBytes",toJson before.utf8ByteSize)])
  for (tag,name) in [("query-work-sample2","parent-stack.txt"),("query-work-candidate-sample1","candidate-stack.txt")] do
    let stack := base/("query-work-fixture-"++tag)/"worker.sample.txt"
    let lines := (← IO.FS.readFile stack).splitOn "\n"
    let filtered := lines.filter (fun line => ["sourceNeighborhood","indexedDiscoveryUsing","filterMapTR","citationReach","citedParents"].any (fun needle => line.contains needle))
    IO.FS.writeFile (output/name) ("Full native sample SHA-256: "++(← hash stack)++"\n"++
      "Recursive sample counts are not CPU percentages. The sampler targets the verified child search worker.\n"++
      String.intercalate "\n" (filtered.take 45))
  let trial := base/"query-work-fixture-query-work-readback1"
  let mut hooks := #[]
  let mut observations := #[]
  let mut actual : Array (String × String) := #[]
  let mut delivered := 0
  let mut admitted := 0
  let mut times : List Nat := []
  for entry in ← trial.readDir do
    if !entry.fileName.endsWith "-measurement.json" then continue
    let row ← read entry.path
    let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
    let body := (row.getObjValAs? String "body").toOption.getD ""
    let head := body.contains "\"observed-head-case-79-7b319c\""
    let tail := body.contains "\"observed-tail-case-79-d82a04\""
    if head && tail && row.getObjValD "complete" == toJson true then delivered := delivered+1
    let log ← events trial receipt
    if log.any (fun (name,_) => name.endsWith "-admitted.json") then admitted := admitted+1
    observations := observations.push (entry.fileName,log)
    hooks := hooks.push (entry.fileName,row.setObjVal! "body" Json.null |>.setObjVal! "head" (toJson head) |>.setObjVal! "tail" (toJson tail))
    times := ((row.getObjValAs? Nat "elapsedMs").toOption.getD 0)::times
    let digest ← IO.ofExcept (row.getObjValAs? String "outputSha256")
    if !actual.any (·.1 == digest) then
      let framed ← IO.FS.readFile (trial/(entry.fileName.replace "-measurement.json" ".json"))
      unless framed.endsWith "\n" do throw (IO.userError "receiver framing changed")
      let text := (framed.dropEnd 1).toString
      let scratch := base/"query-work-output-hash"
      IO.FS.writeFile scratch text
      let checked ← try hash scratch finally IO.FS.removeFile scratch
      unless checked == digest do throw (IO.userError "actual output differs from receipt")
      actual := actual.push (digest,text)
  let source := base/"frontend-quiescence-fixture-small1"
  let frozen ← read (source/"frozen-readback.json")
  let heads ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson heads == frozen.getObjValD "sourceHeads" do throw (IO.userError "original heads changed")
  let mut reports := #[]
  for name in ["before-originals.json","warm-result.json","warm-stdout.json","readers-results.json","report.json"] do
    if ← (trial/name).pathExists then reports := reports.push (name,← read (trial/name))
  for (tag,name) in [("query-work-proofs1","laws.txt"),("query-work-contract1","contract-audit.txt")] do
    let path := base/(tag++".log")
    let lines := (← IO.FS.readFile path).splitOn "\n"
    IO.FS.writeFile (output/name) ("Full output SHA-256: "++(← hash path)++"\n"++String.intercalate "\n" (lines.drop (lines.length-16)))
  let ordered := times.mergeSort (· ≤ ·)
  let summary := Json.mkObj [("deliveredBothOriginalFields",toJson delivered),("readers",toJson (80 : Nat)),
    ("admitted",toJson admitted),("minMs",toJson (ordered.headD 0)),("maxMs",toJson (ordered.getLast?.getD 0)),
    ("profileBodiesByteIdentical",toJson true),("originalHeadsUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("matchedComparisons",toJson "0/18"),("adopted",toJson false)]
  save "evidence.json" (Json.mkObj [("parent",toJson "e6e9e2e5c40bb7b441903ee66acd6cf6291f2b1b"),
    ("sourceHashes",toJson (← hash prior,← hash current)),("unchanged",toJson unchanged),("guards",toJson guards),
    ("profiles",toJson profiles),("bodyChecks",toJson bodyChecks),("runtimeSha256",toJson (← hash (base/"query-work-build/StudyMain"))),
    ("readbackRuntime",toJson (← IO.FS.readFile (trial/"runtime.sha256"))),
    ("reports",toJson reports),("hooks",toJson hooks),("stages",toJson observations),
    ("actualOutputsBySha256",toJson actual),("originalHeads",toJson heads),("summary",summary)])
  save "summary.json" summary
  IO.println summary.compress
