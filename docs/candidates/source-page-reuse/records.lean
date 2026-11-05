import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/source-page-reuse"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "page audit identity unavailable")
  return (result.stdout.splitOn " ").head!
def hashText (value : String) : IO String := do
  let scratch := base/"source-page-reuse-record-text"
  IO.FS.writeFile scratch value
  try hash scratch finally IO.FS.removeFile scratch
def body (value : Json) : String :=
  ((value.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
def main : IO Unit := do
  unless !(← (output/"evidence.json").pathExists) do throw (IO.userError "preserve sealed audit")
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "source-page-reuse-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "source-page-reuse-records" && !entry.fileName.startsWith "source-page-reuse-cleanup" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      let path := base/(entry.fileName.replace ".guard.json" ".log")
      let lines := (← IO.FS.readFile path).splitOn "\n"
      guards := guards.push (entry.fileName,guard,← hash path,String.intercalate "\n" (lines.drop (lines.length-10)))
  let auditPath := base/"source-page-reuse-audit1-result/report.json"
  let audit ← read auditPath
  unless audit.getObjValD "allPassed" == toJson true &&
      audit.getObjValD "allGraphDigestsAndReadTracesEqual" == toJson true do
    throw (IO.userError "native page audit did not pass")
  let rows ← IO.ofExcept (audit.getObjValAs? (Array Json) "rows")
  let compact ← rows.mapM fun row => do
    return row.setObjVal! "tracesSha256" (toJson (← hashText (row.getObjValD "traces").compress))
      |>.setObjVal! "traces" Json.null
  let mut profiles := #[]
  let prior ← read (output.parent.get!/"owner-binding/evidence.json")
  let expectedBodies ← IO.ofExcept (fromJson? (prior.getObjValD "actualBodiesBySha256") : Except String (Array (String × String)))
  for name in ["lexical1","meaning1","sample1"] do
    let root := base/("source-page-reuse-"++name++"-result")
    let mut bodies := #[]
    for stage in ["cold-frontend","running-frontend"] do
      let text := body (← read (root/(stage++"-stdout.json")))
      unless !text.isEmpty && expectedBodies.any (·.2 == text) do throw (IO.userError "instrumented actual body differs from retained parent")
      bodies := bodies.push (stage,text.utf8ByteSize,← hashText text)
    let files ← ["report.json","warm-result.json","rows.json","stages.json"].toArray.mapM fun (file : String) => do
      return (file,← read (root/file))
    let traces ← ["cold-frontend-trace.txt","running-frontend-trace.txt"].toArray.mapM fun (file : String) => do
      return (file,← IO.FS.readFile (root/file))
    profiles := profiles.push (name,files,traces,bodies)
  let before := base/"source-page-reuse-baseline-core/Eggshell/Worker.lean"
  let after := base/"interest-traffic-core/Eggshell/Worker.lean"
  let diff ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--unified=0","--",before.toString,after.toString]}
  unless diff.exitCode == 1 do throw (IO.userError "diagnostic patch missing")
  let patch := diff.stdout.replace ("a"++(base/"source-page-reuse-baseline-core").toString++"/") "a/"
    |>.replace ("b"++(base/"interest-traffic-core").toString++"/") "b/"
  IO.FS.writeFile (output/"diagnostic.patch") (String.intercalate "\n" ((patch.splitOn "\n").map fun line =>
    if line.startsWith "@@" then (line.splitOn " @@").head!++" @@" else line))
  let mut unchanged := #[]
  for name in ["Handoff.lean","OwnerViews.lean","SourceOwners.lean","PreparedInputs.lean","SynapseRecommend.lean",
      "ProjectSources.lean","ProjectAccess.lean","PluginProjectContext.lean","DB/PageMap.lean","PluginModel.lean",
      "PublicationService.lean","PublicationClient.lean","OperationPool.lean","Matcher.lean","Extract.lean","MiniLM.lean"] do
    let original ← hash (base/"source-page-reuse-baseline-core/Eggshell"/name)
    let current ← hash (base/"interest-traffic-core/Eggshell"/name)
    unless original == current do throw (IO.userError ("unrelated code changed: "++name))
    unchanged := unchanged.push (name,current)
  let source := base/"frontend-quiescence-fixture-small1"
  let heads ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson heads == (← read (source/"frozen-readback.json")).getObjValD "sourceHeads" do
    throw (IO.userError "instrumentation changed original source heads")
  let sampled := base/"source-page-reuse-sample1-result"
  let evidence := Json.mkObj [("parent",toJson "ea4711e8750718cfc8574e158f7215006d2c661a"),
    ("diagnosticOnly",toJson true),("guards",toJson guards),
    ("audit",audit.setObjVal! "rows" (toJson compact)),("auditReportSha256",toJson (← hash auditPath)),
    ("profiles",toJson profiles),("sample",← read (sampled/"sampler.json")),
    ("sampleSha256",toJson (← hash (sampled/"worker.sample.txt"))),("sampleSummary",← read (sampled/"worker-summary.json")),
    ("sampleClassifierMissesIdlePipeRead",toJson true),("samplingPerturbsLatency",toJson true),
    ("workerSourceHashes",toJson (← hash before,← hash after)),("unchanged",toJson unchanged),
    ("originalHeads",toJson heads),("auditRuntimeSha256",toJson (← hash (base/"source-page-reuse-build/StudyMain"))),
    ("profileRuntimeSha256",toJson (← hash (base/"source-page-profile-build/StudyMain"))),
    ("answeringModelCalls",toJson (0 : Nat)),("matchedComparisons",toJson "0/18"),("adopted",toJson false)]
  IO.FS.writeFile (output/"evidence.json") (evidence.compress++"\n")
  IO.println (Json.mkObj [("auditPassed",toJson true),("actualBodiesEqualParent",toJson (6 : Nat)),("adopted",toJson false)]).compress
