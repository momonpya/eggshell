import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean

def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/frontend-quiescence"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (name : String) (value : Json) : IO Unit := IO.FS.writeFile (output/name) (value.compress++"\n")
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "hashing failed")
  return (result.stdout.splitOn " ").head!
def counts (values : Array String) : Json := Id.run do
  let mut result : List (String × Nat) := []
  for value in values do
    if result.any (·.1 == value) then result := result.map fun (key,n) => (key,n+if key == value then 1 else 0)
    else result := result++[(value,1)]
  return toJson result
def stage (root : System.FilePath) (receipt name : String) : IO Json := do
  let path := root/"private/receipts"/receipt/(name++".json")
  if !(← path.pathExists) then return Json.null
  return (← read path).getObjValD "data"
def events (root : System.FilePath) (receipt : String) : IO (Array (String × Json)) := do
  let folder := root/"private/receipts"/receipt
  if !(← folder.pathExists) then return #[]
  let mut result := #[]
  for entry in ← folder.readDir do
    if !entry.fileName.endsWith ".json" then continue
    if entry.fileName.startsWith "operation-" || entry.fileName.startsWith "search-phase-" ||
        entry.fileName.startsWith "discovery-counters-" ||
        ["search.json","prepared-inputs-turn.json","prepared-inputs-operation.json","transport.json",
         "canonical-source-reuse.json","original-read.json","projection.json","published.json"].contains entry.fileName then
      result := result.push (entry.fileName,(← read entry.path).getObjValD "data")
  return result

def main : IO Unit := do
  let mut guards := #[]
  let mut failures := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "frontend-quiescence-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      guards := guards.push (entry.fileName,guard)
      if guard.getObjValD "exitCode" != toJson (0 : Nat) then
        let log := base/(entry.fileName.replace ".guard.json" ".log")
        let lines ← if ← log.pathExists then do pure ((← IO.FS.readFile log).splitOn "\n") else pure []
        failures := failures.push (entry.fileName,String.intercalate "\n" (lines.drop (lines.length-14)))
  save "guards.json" (toJson guards)
  save "failed-attempts.json" (toJson failures)
  let mut logs := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "frontend-quiescence-" && entry.fileName.endsWith ".log" then
      let text ← IO.FS.readFile entry.path
      logs := logs.push (Json.mkObj [("file",toJson entry.fileName),("sha256",toJson (← hash entry.path)),
        ("bytes",toJson text.utf8ByteSize),("frontendFullMessages",toJson ((text.splitOn "frontend session admission is full").length-1))])
  save "logs.json" (toJson logs)
  let mut patch := ""
  let mut changed := #[]
  for name in ["HookFrontend.lean"] do
    let prior := base/"frontend-quiescence-baseline-core/Eggshell"/name
    let current := base/"interest-traffic-core/Eggshell"/name
    let result ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--",prior.toString,current.toString]}
    unless result.exitCode ≤ 1 do throw (IO.userError "source diff failed")
    patch := patch++(result.stdout.replace ("a"++(base/"frontend-quiescence-baseline-core").toString++"/") "a/"
      |>.replace ("b"++(base/"interest-traffic-core").toString++"/") "b/")
    changed := changed.push (name,← hash prior,← hash current)
  IO.FS.writeFile (output/"candidate.patch") patch
  let mut unchanged := #[]
  for name in ["MiniLM.lean","Numerical.lean","SearchProvider.lean","BlockScore.lean","GraphStore.lean",
      "DB/PageMap.lean","NativePublication.lean","ProjectSources.lean","PublicationService.lean",
      "Handoff.lean","SearchRank.lean","Matcher.lean","Extract.lean","KeyedSearchProvider.lean",
      "SemanticMatcher.lean","Worker.lean","PluginHooks.lean","OperationPool.lean","HookBudget.lean"] do
    let prior ← hash (base/"frontend-quiescence-baseline-core/Eggshell"/name)
    let current ← hash (base/"interest-traffic-core/Eggshell"/name)
    unless prior == current do throw (IO.userError "unrelated source changed")
    unchanged := unchanged.push (name,current)
  save "identity.json" (Json.mkObj [("parentRuntimeSha256",toJson (← hash (base/"single-search-build/StudyMain"))),
    ("candidateRuntimeSha256",toJson (← hash (base/"frontend-quiescence-build/StudyMain"))),
    ("changed",toJson changed),("unchanged",toJson unchanged)])
  save "policy.json" (← read (base/"frontend-quiescence-fixture-policy3/report.json"))
  save "token-boundary.json" (← read (base/"frontend-quiescence-terms1.log"))
  for (tag,name) in [("frontend-quiescence-proofs1","laws.txt"),("frontend-quiescence-contract1","contract-audit.txt")] do
    let log := base/(tag++".log")
    let lines := (← IO.FS.readFile log).splitOn "\n"
    IO.FS.writeFile (output/name) ("Full output SHA-256: "++(← hash log)++"\n"++String.intercalate "\n" (lines.drop (lines.length-18)))
  let mut reports := #[]
  let mut trials := #[]
  let mut observations := #[]
  let mut outputs : Array (String × String) := #[]
  let mut phaseSummaries := #[]
  for name in ["readers1","small1","large1"] do
    let root := base/("frontend-quiescence-fixture-"++name)
    if !(← root.pathExists) then continue
    let mut hooks := #[]
    let report := root/(if name == "readers1" then "input-report.json" else "report.json")
    if ← report.pathExists then reports := reports.push (name,← read report)
    for entry in ← root.readDir do
      if !entry.fileName.endsWith "-measurement.json" then continue
      let row ← read entry.path
      let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
      observations := observations.push (name,entry.fileName,← events root receipt)
      let digest ← IO.ofExcept (row.getObjValAs? String "outputSha256")
      if !outputs.any (·.1 == digest) then
        let written ← IO.FS.readFile (root/(entry.fileName.replace "-measurement.json" ".json"))
        unless written.endsWith "\n" do throw (IO.userError "receiver framing changed")
        let actual := (written.dropEnd 1).toString
        let temporary := base/"frontend-quiescence-output-hash"
        IO.FS.writeFile temporary actual
        let checked ← try hash temporary finally IO.FS.removeFile temporary
        unless checked == digest do throw (IO.userError "actual output differs from receipt")
        outputs := outputs.push (digest,actual)
      hooks := hooks.push (entry.fileName,row.setObjVal! "body" Json.null)
    trials := trials.push (name,hooks)
    for phase in (if name == "readers1" then ["input-readers"] else ["writers","readers"]) do
      let resultPath := root/(phase++"-results.json")
      if !(← resultPath.pathExists) then continue
      let result ← read resultPath
      let rows ← IO.ofExcept (result.getObjValAs? (Array Json) "rows")
      let errors ← IO.ofExcept (result.getObjValAs? (Array Json) "errors")
      let mut elapsed : List Nat := []
      let mut routes := #[]
      let mut semantic := #[]
      let mut admissions := #[]
      for (file,row) in hooks do
        let selected := if phase == "readers" then file.startsWith "reader-" && file.endsWith "-readback-UserPromptSubmit-measurement.json"
          else file.endsWith "-initial-UserPromptSubmit-measurement.json"
        if !selected then continue
        let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
        let log ← events root receipt
        admissions := admissions.push (toString (log.filter fun (file,_) => file.endsWith "-admitted.json").size)
        elapsed := ((row.getObjValAs? Nat "elapsedMs").toOption.getD 0)::elapsed
        let trace := (← stage root receipt "search").getObjValD "trace"
        routes := routes.push (trace.getObjValD "route").compress
        semantic := semantic.push (trace.getObjValD "semantic").compress
      let ordered := elapsed.mergeSort (· ≤ ·)
      phaseSummaries := phaseSummaries.push (Json.mkObj [("fixture",toJson name),("phase",toJson phase),
        ("completeClients",toJson rows.size),("errors",toJson errors),("hooks",toJson elapsed.length),
        ("minMs",toJson (ordered.headD 0)),("maxMs",toJson (ordered.getLast?.getD 0)),
        ("admissionsPerReceipt",counts admissions),("route",counts routes),("semantic",counts semantic)])
  let root := base/"frontend-quiescence-fixture-small1"
  let mut frozen := #[]
  for name in ["frozen-seed.json","frozen-readback.json","seed-originals.json","writers-originals.json"] do
    if ← (root/name).pathExists then frozen := frozen.push (name,← read (root/name))
  let drainPath := root/"writers-drain.json"
  let drain ← if ← drainPath.pathExists then read drainPath else pure (toJson (#[] : Array Json))
  let drain ← IO.ofExcept drain.getArr?
  save "readback-analysis.json" (← read (root/"readback-analysis.json"))
  let expected ← IO.ofExcept ((← read (root/"frozen-readback.json")).getObjValAs? (Array Json) "sourceHeads")
  let current ← (List.range 16).toArray.mapM fun owner => read (root/"work.project/owners"/toString owner/"source.egg/head")
  unless current == expected do throw (IO.userError "readback changed original heads")
  save "original-heads.json" (Json.mkObj [("frozen",toJson expected),("postReadback",toJson current),
    ("allOriginalHeadsUnchanged",toJson true)])
  save "native-reports.json" (Json.mkObj [("reports",toJson reports),("frozen",toJson frozen),
    ("lastPreparationDrain",drain.back?.getD Json.null)])
  save "native-trials.json" (Json.mkObj [("hooks",toJson trials),("actualOutputsBySha256",toJson outputs)])
  save "native-stages.json" (toJson observations)
  save "summary.json" (Json.mkObj [("phases",toJson phaseSummaries),("fullCapacityGatePassed",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("matchedComparisons",toJson "0/18"),("adopted",toJson false),
    ("scope",toJson "Quiescent frontend cache retirement and ordinary synthetic lifecycle. Sustained 80-user capacity, real-evidence 98% delivery, p99 and matched token/quality improvements are not established.")])
  IO.println (toJson (phaseSummaries.map fun row => Json.mkObj (["phase","completeClients","hooks","minMs","maxMs","admissionsPerReceipt"].map fun key => (key,row.getObjValD key)))).compress
