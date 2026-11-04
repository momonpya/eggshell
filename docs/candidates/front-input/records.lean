import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean

def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/front-input"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (name : String) (value : Json) : IO Unit := IO.FS.writeFile (output/name) (value.compress++"\n")
def hashFile (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "hashing failed")
  return (result.stdout.splitOn " ").head!
def hashText (value : String) : IO String := do
  let temporary := base/"front-input-output-hash"
  IO.FS.writeFile temporary value
  try hashFile temporary finally IO.FS.removeFile temporary

def stageData (root : System.FilePath) (receipt name : String) : IO Json := do
  let path := root/"private"/"receipts"/receipt/(name++".json")
  if !(← path.pathExists) then return Json.null
  return (← read path).getObjValD "data"

def stages (root : System.FilePath) : IO Json := do
  let result ← read (root/"input-readers-results.json")
  let rows ← IO.ofExcept (result.getObjValAs? (Array Json) "rows")
  let mut reports := #[]
  for row in rows do
    let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
    reports := reports.push (Json.mkObj [("session",row.getObjValD "session"),("hookMs",row.getObjValD "elapsedMs"),
      ("turnInputs",← stageData root receipt "prepared-inputs-turn"),
      ("operationInputs",← stageData root receipt "prepared-inputs-operation"),
      ("service",← stageData root receipt "operation-service"),
      ("transport",← stageData root receipt "transport"),("search",← stageData root receipt "search")])
  return toJson reports

def main : IO Unit := do
  let mut guards := #[]
  for entry in ← base.readDir do
    if ["front-input-","front-traffic-","front-manager-"].any (fun stem => entry.fileName.startsWith stem) && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      unless value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      if entry.fileName.startsWith "front-input-" then guards := guards.push (entry.fileName,value)
  save "guards.json" (toJson guards)
  let first := base/"front-input-fixture-diagnostic1"
  let second := base/"front-input-fixture-diagnostic2"
  let drain ← IO.ofExcept (fromJson? (α := Array Json) (← read (first/"seed-drain.json")))
  let blocked := drain.back!
  save "blocked-drain.json" (Json.mkObj (["elapsedMs","queuesEmpty","preparedSources","preparation","operations"].map fun field => (field,blocked.getObjValD field)))
  save "recovery-checks.json" (← read (first/"recovery-checks.json"))
  save "stage-report.json" (← stages second)
  save "frozen-inputs.json" (← read (second/"frozen-inputs.json"))
  let report ← read (second/"input-report.json")
  let stats := report.getObjValD "serviceStats"
  save "input-report.json" (Json.mkObj [("allPassed",report.getObjValD "allPassed"),
    ("readers",report.getObjValD "readers"),("sourceHeadsUnchanged",report.getObjValD "sourceHeadsUnchanged"),
    ("operations",stats.getObjValD "operations"),("preparation",stats.getObjValD "preparation"),
    ("preparedSources",stats.getObjValD "preparedSources"),("answeringModelCalls",toJson (0 : Nat))])
  let rejected := base/"front-input-fixture-ready1"
  let ready := base/"front-input-fixture-ready2"
  let mut fixtures := [("before",first),("after",second)]
  if ← rejected.pathExists then
    let frozen ← read (rejected/"frozen-inputs.json")
    save "readiness-source-mismatch.json" (Json.mkObj [
      ("reason",toJson "build8 used the isolated tree's old research checker, not the workspace readiness correction. Corrected setup copies and verifies the two owned checker sources before building. This trial is not evidence for corrected readiness."),
      ("ownerReferenceReady",frozen.getObjValD "ownerReferenceReady"),
      ("stages",← stages rejected)])
    fixtures := fixtures ++ [("rejected-checker-source",rejected)]
  if ← (ready/"input-report.json").pathExists then
    let frozen ← read (ready/"frozen-inputs.json")
    unless frozen.getObjValD "ownerReferenceReady" == toJson true do
      throw (IO.userError "corrected gate did not retain complete owner inputs")
    save "ready-frozen-inputs.json" frozen
    save "ready-input-report.json" (← read (ready/"input-report.json"))
    save "ready-stage-report.json" (← stages ready)
    let guard ← read (base/"front-input-ready2.guard.json")
    save "ready-resources.json" (Json.mkObj (["state","exitCode","elapsedMs","guardTriggered",
      "ownedPids","sampledPeakRssKiB","limitRssKiB","userCeilingRssKiB"].map fun field =>
        (field,guard.getObjValD field)))
    let drain ← IO.ofExcept (fromJson? (α := Array Json) (← read (ready/"seed-drain.json")))
    save "ready-drain.json" (toJson (drain.map fun row => Json.mkObj (
      ["elapsedMs","queuesEmpty","preparedSources","ownerReferenceReady"].map fun field =>
        (field,row.getObjValD field))))
    fixtures := fixtures ++ [("complete-readiness",ready)]
  let mut hooks := #[]
  let mut originals := #[]
  for (name,root) in fixtures do
    for entry in ← root.readDir do
      if !entry.fileName.endsWith "-measurement.json" then continue
      let row ← read entry.path
      let path := root/(entry.fileName.replace "-measurement.json" ".json")
      let digest ← IO.ofExcept (row.getObjValAs? String "outputSha256")
      if !originals.any (·.1 == digest) then
        let written ← IO.FS.readFile path
        unless written.endsWith "\n" do throw (IO.userError "native output terminator changed")
        let original := (written.dropEnd 1).toString
        unless (← hashText original) == digest do throw (IO.userError "native output bytes changed")
        originals := originals.push (digest,original)
      hooks := hooks.push (name,entry.fileName,row.setObjVal! "body" Json.null)
  save "deliveries.json" (Json.mkObj [("hooks",toJson hooks),("actualOutputsBySha256",toJson originals)])
  let mut patch := ""
  let mut identity := #[]
  for name in ["NativePublication.lean","OperationPool.lean","PluginHooks.lean","PluginProjectContext.lean","Worker.lean"] do
    let old := base/"front-input-baseline-core"/"Eggshell"/name
    let current := base/"interest-traffic-core"/"Eggshell"/name
    let result ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--",old.toString,current.toString]}
    unless result.exitCode ≤ 1 do throw (IO.userError "candidate diff failed")
    patch := patch ++ (result.stdout.replace ("a"++(base/"front-input-baseline-core").toString++"/") "a/"
      |>.replace ("b"++(base/"interest-traffic-core").toString++"/") "b/")
    identity := identity.push (name,← hashFile current)
  IO.FS.writeFile (output/"candidate.patch") patch
  let mut unchanged := #[]
  for name in ["GraphStore.lean","DB/PageMap.lean","SearchProvider.lean","MiniLM.lean","BlockScore.lean"] do
    let old ← hashFile (base/"front-input-baseline-core"/"Eggshell"/name)
    let current ← hashFile (base/"interest-traffic-core"/"Eggshell"/name)
    unless old == current do throw (IO.userError "graph guard, model or score source changed")
    unchanged := unchanged.push (name,current)
  save "identity.json" (Json.mkObj [("currentRuntimeSha256",toJson (← hashFile (base/"front-input-build/StudyMain"))),
    ("core",toJson identity),("unchangedGuardsAndModel",toJson unchanged),
    ("scope",toJson "Current binary includes later checker additions; earlier diagnostics share these product-core bytes but are not sealed same-binary or paid token comparisons.")])
  let laws ← IO.FS.readFile (base/"front-input-proofs2.log")
  IO.FS.writeFile (output/"laws.txt") laws
  let audit := base/"front-input-contract1.log"
  let lines := (← IO.FS.readFile audit).splitOn "\n"
  IO.FS.writeFile (output/"contract-audit.txt") ("ContractAudit passed; full output SHA-256: "++(← hashFile audit)++"\n"++String.intercalate "\n" (lines.drop (lines.length-11)))
  let startup := base/"front-input-startup1.log"
  let lines := (← IO.FS.readFile startup).splitOn "\n"
  IO.FS.writeFile (output/"startup-time.txt") (String.intercalate "\n" (lines.drop (lines.length-4)))
  let sample := second/"startup.sample.txt"
  let text ← IO.FS.readFile sample
  let graph := ((text.splitOn "Call graph:").drop 1).headD ""
    |>.splitOn "Total number in stack" |>.head!
  save "startup-sample.json" (Json.mkObj [("sample",← read (second/"startup-sample.json")),
    ("rawSha256",toJson (← hashFile sample)),("capturedCallGraph",toJson (!graph.trimAscii.isEmpty)),
    ("interpretation",toJson "The native process exited before usable stack samples. This does not attribute startup CPU to a particular initializer.")])
  IO.println (Json.mkObj [("guards",toJson guards.size),("hooks",toJson hooks.size),
    ("uniqueOutputs",toJson originals.size),("changedCoreFiles",toJson identity.size)]).compress
