import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean

def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/literal-boundaries"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (name : String) (value : Json) : IO Unit := IO.FS.writeFile (output/name) (value.compress++"\n")
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "identity hashing failed")
  return (result.stdout.splitOn " ").head!
def events (root : System.FilePath) (receipt : String) : IO (Array (String × Json)) := do
  let folder := root/"private/receipts"/receipt
  if !(← folder.pathExists) then return #[]
  let mut rows := #[]
  for entry in ← folder.readDir do
    if entry.fileName.endsWith ".json" &&
        (["operation-","search-phase-","discovery-counters-"].any (fun stem => entry.fileName.startsWith stem) ||
         ["failure.json","search.json","prepared-inputs-turn.json","prepared-inputs-operation.json","transport.json",
          "canonical-source-reuse.json","original-read.json","projection.json","published.json"].contains entry.fileName) then
      rows := rows.push (entry.fileName,(← read entry.path).getObjValD "data")
  return rows
def counts (values : Array String) : Json := Id.run do
  let mut rows : List (String × Nat) := []
  for value in values do
    if rows.any (·.1 == value) then rows := rows.map fun (key,n) => (key,n+if key == value then 1 else 0)
    else rows := rows++[(value,1)]
  return toJson rows

def main : IO Unit := do
  unless !(← (output/"summary.json").pathExists) do throw (IO.userError "preserve sealed trial")
  let mut guards := #[]
  let mut failures := #[]
  let mut logs := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "literal-boundaries-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "literal-boundaries-records" && !entry.fileName.startsWith "literal-boundaries-cleanup" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      guards := guards.push (entry.fileName,guard)
      let path := base/(entry.fileName.replace ".guard.json" ".log")
      if ← path.pathExists then
        let content ← IO.FS.readFile path
        logs := logs.push (entry.fileName,← hash path,content.utf8ByteSize)
        if guard.getObjValD "exitCode" != toJson (0 : Nat) then
          let lines := content.splitOn "\n"
          failures := failures.push (entry.fileName,String.intercalate "\n" (lines.drop (lines.length-14)))
  save "guards.json" (toJson guards)
  save "failed-attempts.json" (toJson failures)
  save "logs.json" (toJson logs)
  let mut patch := ""
  let mut changed := #[]
  for name in ["tools/RetrievalGrams.lean","Eggshell/SearchRank.lean","Eggshell/Handoff.lean","tools/RetrievalGramsTests.lean"] do
    let prior := base/"literal-boundaries-baseline-core"/name
    let current := base/"interest-traffic-core"/name
    let diff ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--",prior.toString,current.toString]}
    unless diff.exitCode ≤ 1 do throw (IO.userError "source diff failed")
    let part := diff.stdout.replace ("a"++(base/"literal-boundaries-baseline-core").toString++"/") "a/"
      |>.replace ("b"++(base/"interest-traffic-core").toString++"/") "b/"
    if name == "tools/RetrievalGramsTests.lean" then IO.FS.writeFile (output/"grammar-tests.patch") part
    else patch := patch++part
    changed := changed.push (name,← hash prior,← hash current)
  IO.FS.writeFile (output/"candidate.patch") patch
  let mut unchanged := #[]
  for name in ["MiniLM.lean","Numerical.lean","SearchProvider.lean","BlockScore.lean","GraphStore.lean",
      "DB/PageMap.lean","NativePublication.lean","ProjectSources.lean","PublicationService.lean",
      "Matcher.lean","Extract.lean","KeyedSearchProvider.lean","SemanticMatcher.lean","Worker.lean",
      "PluginHooks.lean","OperationPool.lean","HookBudget.lean","HookFrontend.lean","SourceOwners.lean"] do
    let prior ← hash (base/"literal-boundaries-baseline-core/Eggshell"/name)
    let current ← hash (base/"interest-traffic-core/Eggshell"/name)
    unless prior == current do throw (IO.userError ("unrelated source changed: "++name))
    unchanged := unchanged.push (name,current)
  let probe := base/"literal-boundaries-fixture-literal-boundaries-probe2"
  let trial := base/"literal-boundaries-fixture-literal-boundaries-readback2"
  save "identity.json" (Json.mkObj [("parentCommit",toJson "6c0e40a460d3d487fe37245416a0f548e5ec4587"),
    ("parentRuntimeSha256",toJson (← hash (base/"frontend-quiescence-build/StudyMain"))),
    ("candidateProbeRuntime",toJson (← IO.FS.readFile (probe/"runtime.sha256"))),
    ("candidateReadbackRuntime",toJson (← IO.FS.readFile (trial/"runtime.sha256"))),
    ("currentRuntimeSha256",toJson (← hash (base/"literal-boundaries-build/StudyMain"))),
    ("changed",toJson changed),("unchanged",toJson unchanged),
    ("harnessRelink",toJson "Probe2 used build6. Build7 changes only the diagnostic entry-point freshness check: it must precede the numerical keeper creating its private directory. Product bytes are unchanged.")])
  let mut arms := #[]
  for arm in ["period","no-period","identifier","uri"] do
    arms := arms.push (arm,← IO.FS.readFile (probe/(arm++"-stdout.json")))
  save "probe.json" (Json.mkObj [("report",← read (probe/"report.json")),("actualStdout",toJson arms),
    ("warm",← read (probe/"warm-result.json")),("warmStdout",← read (probe/"warm-stdout.json")),
    ("warmStderr",toJson (← IO.FS.readFile (probe/"warm-stderr.txt")))])
  for (tag,name) in [("literal-boundaries-proofs2","laws.txt"),("literal-boundaries-contract2","contract-audit.txt"),
      ("literal-boundaries-grammar-run2","grammar.txt")] do
    let path := base/(tag++".log")
    IO.FS.writeFile (output/name) ("Full output SHA-256: "++(← hash path)++"\n"++(← IO.FS.readFile path))
  let mut hooks := #[]
  let mut stages := #[]
  let mut actual : Array (String × String) := #[]
  let mut admissions := #[]
  let mut routes := #[]
  let mut times : List Nat := []
  let mut delivered := 0
  for entry in ← trial.readDir do
    if !entry.fileName.endsWith "-measurement.json" then continue
    let row ← read entry.path
    let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
    let body := (row.getObjValAs? String "body").toOption.getD ""
    let head := body.contains "\"observed-head-case-79-7b319c\""
    let tail := body.contains "\"observed-tail-case-79-d82a04\""
    if head && tail && row.getObjValD "complete" == toJson true then delivered := delivered+1
    let log ← events trial receipt
    stages := stages.push (entry.fileName,log)
    admissions := admissions.push (toString (log.filter fun (file,_) => file.endsWith "-admitted.json").size)
    if let some (_,value) := log.find? (·.1 == "search.json") then
      routes := routes.push (value.getObjValD "trace" |>.getObjValD "route").compress
    times := ((row.getObjValAs? Nat "elapsedMs").toOption.getD 0)::times
    hooks := hooks.push (entry.fileName,row.setObjVal! "body" Json.null |>.setObjVal! "head" (toJson head) |>.setObjVal! "tail" (toJson tail))
    let digest ← IO.ofExcept (row.getObjValAs? String "outputSha256")
    if !actual.any (·.1 == digest) then
      let framed ← IO.FS.readFile (trial/(entry.fileName.replace "-measurement.json" ".json"))
      unless framed.endsWith "\n" do throw (IO.userError "receiver framing changed")
      let value := (framed.dropEnd 1).toString
      let scratch := base/"literal-boundaries-output-hash"
      IO.FS.writeFile scratch value
      let checked ← try hash scratch finally IO.FS.removeFile scratch
      unless checked == digest do throw (IO.userError "actual output differs from receipt")
      actual := actual.push (digest,value)
  save "native-trials.json" (Json.mkObj [("hooks",toJson hooks),("actualOutputsBySha256",toJson actual),
    ("results",← read (trial/"readers-results.json"))])
  save "native-stages.json" (toJson stages)
  let source := base/"frontend-quiescence-fixture-small1"
  let frozen ← read (source/"frozen-readback.json")
  let current ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson current == frozen.getObjValD "sourceHeads" do throw (IO.userError "original heads changed")
  save "original-heads.json" (Json.mkObj [("frozen",frozen),("postReadback",toJson current),
    ("allOriginalHeadsUnchanged",toJson true),("originalAudit",← read (trial/"before-originals.json"))])
  let report ← if ← (trial/"report.json").pathExists then read (trial/"report.json") else pure Json.null
  save "native-reports.json" (Json.mkObj [("warm",← read (trial/"warm-result.json")),
    ("warmStdout",← read (trial/"warm-stdout.json")),("warmStderr",toJson (← IO.FS.readFile (trial/"warm-stderr.txt"))),
    ("report",report)])
  let ordered := times.mergeSort (· ≤ ·)
  save "summary.json" (Json.mkObj [("readbackClients",toJson (80 : Nat)),("deliveredBothOriginalFields",toJson delivered),
    ("measurementCount",toJson hooks.size),("minMs",toJson (ordered.headD 0)),("maxMs",toJson (ordered.getLast?.getD 0)),
    ("admissionsPerReceipt",counts admissions),("routes",counts routes),
    ("answeringModelCalls",toJson (0 : Nat)),("matchedComparisons",toJson "0/18"),("adopted",toJson false),
    ("scope",toJson "Lexical spelling and nomination plus one pre-warmed retained-snapshot native 80-reader burst. Not a repeated matched full writer lifecycle, eight-hour capacity, p99, real-evidence 98%, quality or inclusive-token adoption result.")])
