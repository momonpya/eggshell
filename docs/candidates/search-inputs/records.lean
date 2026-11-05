import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/search-inputs"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless reply.exitCode == 0 do throw (IO.userError "cannot seal artifact")
  return (reply.stdout.splitOn " ").headD ""
def save (name : String) (value : Json) : IO Unit := IO.FS.writeFile (output/name) value.pretty
def readGuard (tag : String) : IO Json := do
  let record ← read (base/(tag++".guard.json"))
  unless record.getObjValD "state" == toJson "finished" &&
      record.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "guard still live or not finalized")
  let pid ← IO.ofExcept (record.getObjValAs? Nat "guardPid")
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
  unless process.stdout.trimAscii.toString.isEmpty do throw (IO.userError "terminal guard process remains")
  let path := base/(tag++".log")
  let log ← IO.FS.readFile path
  return Json.mkObj [("record",record),("logSha256",toJson (← hash path)),
    ("failureExcerpt",if record.getObjValD "exitCode" == toJson (0 : Nat) then Json.null else
      toJson (log.takeEnd 4000).toString)]
def verifyOriginals : IO Unit := do
  let frozen ← read (base/"frontend-quiescence-fixture-small1/frozen-readback.json")
  let heads ← IO.ofExcept (frozen.getObjValAs? (Array Json) "sourceHeads")
  unless heads.size == 16 do throw (IO.userError "wrong frozen source count")
  for i in [:heads.size] do
    let path := base/s!"frontend-quiescence-fixture-small1/work.project/owners/{i}/source.egg/head"
    unless (← read path) == heads[i]! do throw (IO.userError "original source head changed")
  let registry ← read (output.parent.get!/"source-incidence/evidence.json")
  let originals ← IO.ofExcept (registry.getObjValAs? (Array (String × String × String)) "originalHeads")
  for (raw,expected,digest) in originals do
    let path : System.FilePath := .mk raw
    unless (← IO.FS.readFile path) == expected && (← hash path) == digest do
      throw (IO.userError "original head bytes changed")
  let controlsChecked ← IO.Process.output {
    cmd := "/usr/bin/shasum"
    args := #["-a","256","-c",(output.parent.get!/"project-cache/protected-after.sha256").toString]
    cwd := some base}
  unless controlsChecked.exitCode == 0 do throw (IO.userError "protected original/build inputs changed")
def productFiles : List String := ["Eggshell/KeyedSearchProvider.lean","Eggshell/PreparedReaders.lean","Eggshell/BuiltinSearch.lean","Eggshell/KeyedSearchClient.lean","Eggshell/Handoff.lean"]
def patch : IO Unit := do
  let previous := base/"search-inputs-baseline-core"
  let core := base/"interest-traffic-core"
  let mut patchText := ""
  for name in productFiles do
    let reply ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--no-index","--no-prefix","--unified=0",(previous/name).toString,(core/name).toString]}
    unless reply.exitCode == 1 do throw (IO.userError "missing isolated product diff")
    let lines := reply.stdout.splitOn "\n" |>.drop 1 |>.map fun line =>
      if line.startsWith "--- " then "--- a/"++name
      else if line.startsWith "+++ " then "+++ b/"++name else line
    patchText := patchText++s!"diff --git a/{name} b/{name}\n"++"\n".intercalate lines
  IO.FS.writeFile (output/"candidate.patch") patchText
  let reply ← IO.Process.output {
    cmd := "/usr/bin/git"
    args := #["apply","--check","--unidiff-zero",(output/"candidate.patch").toString]
    cwd := some previous}
  unless reply.exitCode == 0 do throw (IO.userError ("isolated patch mismatch: "++reply.stderr))
def distribution (values : Array Nat) : Json := Id.run do
  let rows := values.qsort (· < ·)
  return Json.mkObj [("count",toJson rows.size),("min",toJson rows[0]?),
    ("median",toJson rows[rows.size/2]?),("max",toJson rows.back?)]
def readback (tag : String) : IO Json := do
  let root := base/(tag++"-result")
  let results ← read (root/"readers-results.json")
  let successes ← IO.ofExcept (results.getObjValAs? (Array Json) "rows")
  let failures ← IO.ofExcept (results.getObjValAs? (Array Json) "errors")
  unless successes.size+failures.size == 80 do throw (IO.userError "missing native reader result")
  let mut measurements := #[]
  let mut times := #[]
  let mut fields := 0
  let mut timelyFields := 0
  let mut services := #[]
  let mut queues := #[]
  let mut workTimes := #[]
  let mut semanticPhases := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "retained-reader-" && entry.fileName.endsWith "-measurement.json" then
      let row ← read entry.path
      let body ← IO.ofExcept (row.getObjValAs? String "body")
      let both := body.contains "\"observed-head-case-79-7b319c\"" &&
        body.contains "\"observed-tail-case-79-d82a04\""
      let elapsed ← IO.ofExcept (row.getObjValAs? Nat "elapsedMs")
      if both then fields := fields+1
      if both && elapsed < 30000 then timelyFields := timelyFields+1
      times := times.push elapsed
      measurements := measurements.push (row.setObjVal! "body" Json.null
        |>.setObjVal! "bothOriginalFields" (toJson both)
        |>.setObjVal! "bodyBytes" (toJson body.utf8ByteSize))
      let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
      let directory := root/"private/receipts"/receipt
      if ← (directory/"operation-service.json").pathExists then
        let record := (← read (directory/"operation-service.json")).getObjValD "data"
        queues := queues.push (← IO.ofExcept (record.getObjValAs? Nat "queueMs"))
        workTimes := workTimes.push (← IO.ofExcept (record.getObjValAs? Nat "workMs"))
        services := services.push (receipt,record)
      if ← (directory/"search-phase-semantic.json").pathExists then
        let record := (← read (directory/"search-phase-semantic.json")).getObjValD "data"
        semanticPhases := semanticPhases.push (receipt,record)
  return Json.mkObj [("protocolSuccesses",toJson successes.size),("errors",toJson failures),
    ("measuredHooks",toJson measurements.size),("bothFields",toJson fields),
    ("bothFieldsAndHookUnder30s",toJson timelyFields),("hookIncludingAckMs",distribution times),
    ("allPassed",toJson (successes.size == 80 && timelyFields == 80)),
    ("serviceQueueMs",distribution queues),("serviceWorkMs",distribution workTimes),
    ("services",toJson services),("semanticPhases",toJson semanticPhases),
    ("measurements",toJson measurements),("originalAudit",← read (root/"before-originals.json")),
    ("warm",← read (root/"warm-result.json"))]
def sealRecords : IO Unit := do
  unless !(← (output/"evidence.json").pathExists) do throw (IO.userError "preserve previous evidence")
  verifyOriginals
  patch
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "search-inputs-" && entry.fileName.endsWith ".guard.json" then
      let tag := (entry.fileName.dropEnd ".guard.json".length).toString
      guards := guards.push (tag,← readGuard tag)
  let pairs ← read (base/"search-inputs-pairs1-result/report.json")
  let trials ← IO.ofExcept (pairs.getObjValAs? (Array Json) "trials")
  let retainedBody := output.parent.get!/"metadata-ingress/actual-body.txt"
  let body ← IO.FS.readFile retainedBody
  for trial in trials do
    let directory ← IO.ofExcept (trial.getObjValAs? String "directory")
    let actual ← read ((System.FilePath.mk directory)/"report.json")
    for row in ← IO.ofExcept (actual.getObjValAs? (Array Json) "rows") do
      unless row.getObjValD "body" == toJson body do throw (IO.userError "actual body differs from parent")
  let laws ← IO.FS.readFile (base/"search-inputs-build/tools_research_SearchInputChecks-lean.stdout")
  IO.FS.writeFile (output/"laws.txt") laws
  let sources ← productFiles.toArray.mapM fun (name : String) => do
    return (name,← hash (base/"interest-traffic-core"/name))
  save "evidence.json" (Json.mkObj [("guards",toJson guards),
    ("parentRuntimeSha256",toJson (← hash (base/"metadata-ingress-candidate-build/StudyMain"))),
    ("candidateRuntimeSha256",toJson (← hash (base/"search-inputs-build/StudyMain"))),
    ("candidateSources",toJson sources),
    ("components",← read (base/"search-inputs-checks2-result/report.json")),("pairs",pairs),
    ("readbackParent",← readback "search-inputs-readback-parent1"),
    ("readbackCandidate",← readback "search-inputs-readback-candidate1"),
    ("actualBodyFile",toJson "../metadata-ingress/actual-body.txt"),
    ("actualBodySha256",toJson (← hash retainedBody)),("actualBodyBytes",toJson body.utf8ByteSize),
    ("originalHeadsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("paidComparisons",toJson (0 : Nat)),("adopted",toJson false)])
partial def erase (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← erase entry.path)
    IO.FS.removeDir path
    return bytes
  unless metadata.type == .file || metadata.type == .symlink do throw (IO.userError "special cleanup input")
  IO.FS.removeFile path
  return metadata.byteSize.toNat
def restoreParent : IO Unit := do
  unless (← (output/"evidence.json").pathExists) && !(← (output/"restoration.json").pathExists) do
    throw (IO.userError "seal evidence first; preserve restoration")
  let evidence ← read (output/"evidence.json")
  for (tag,_) in ← IO.ofExcept (evidence.getObjValAs? (Array (String × Json)) "guards") do
    let _ ← readGuard tag
    pure ()
  let core := base/"interest-traffic-core"
  let previous := base/"search-inputs-baseline-core"
  for (name,digest) in ← IO.ofExcept (evidence.getObjValAs? (Array (String × String)) "candidateSources") do
    unless (← hash (core/name)) == digest do throw (IO.userError "candidate source changed since recording")
  let mut restored := #[]
  for name in productFiles++["tools/research/FrontTrafficChecks.lean"] do
    let expected ← IO.FS.readFile (previous/name)
    IO.FS.writeFile (core/name) expected
    unless (← IO.FS.readFile (core/name)) == expected do throw (IO.userError "source restoration failed")
    restored := restored.push (name,← hash (core/name))
  IO.FS.removeFile (core/"tools/research/SearchInputChecks.lean")
  verifyOriginals
  save "restoration.json" (Json.mkObj [("restored",toJson restored),
    ("activeParentRuntimeSha256",toJson (← hash (base/"metadata-ingress-candidate-build/StudyMain"))),
    ("reason",toJson "No eighty-reader capacity improvement established; token and quality gates unrun"),
    ("candidateIsNextRuntime",toJson false),("originalHeadsUnchanged",toJson true)])
def receiptProfile : IO Unit := do
  unless !(← (output/"receipt-profile.json").pathExists) do throw (IO.userError "preserve profile evidence")
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "search-inputs-receipt-" && entry.fileName.endsWith ".guard.json" then
      let tag := (entry.fileName.dropEnd ".guard.json".length).toString
      guards := guards.push (tag,← readGuard tag)
  for name in ["Eggshell/FileSystem.lean","Eggshell/Receipt.lean"] do
    unless (← IO.FS.readFile (base/"interest-traffic-core"/name)) ==
        (← IO.FS.readFile (base/"search-inputs-baseline-core"/name)) do
      throw (IO.userError "profile changed filesystem or receipt product code")
  verifyOriginals
  save "receipt-profile.json" (Json.mkObj [("guards",toJson guards),
    ("runtimeSha256",toJson (← hash (base/"search-inputs-receipt-build/StudyMain"))),
    ("result",← read (base/"search-inputs-receipt-profile1-result/report.json")),
    ("filesystemAndReceiptSourceUnchanged",toJson true),("originalHeadsUnchanged",toJson true),
    ("durabilityChanged",toJson false),("notLoadedHookAttribution",toJson true)])
def cleanup : IO Unit := do
  unless (← (output/"evidence.json").pathExists) && !(← (output/"cleanup.json").pathExists) do
    throw (IO.userError "seal first; preserve previous cleanup")
  verifyOriginals
  let evidence ← read (output/"evidence.json")
  let guards ← IO.ofExcept (evidence.getObjValAs? (Array (String × Json)) "guards")
  for (tag,_) in guards do
    let _ ← readGuard tag
    pure ()
  unless (← (output/"receipt-profile.json").pathExists) do throw (IO.userError "seal receipt profile first")
  for entry in ← base.readDir do
    if entry.fileName.startsWith "search-inputs-" && entry.fileName.endsWith ".guard.json" then
      let _ ← readGuard (entry.fileName.dropEnd ".guard.json".length).toString
      pure ()
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axww","-o","command="]}
  for name in ["search-inputs-build","search-inputs-receipt-build","metadata-ingress-candidate-build"] do
    let engine := (base/name/"StudyMain").toString
    if processes.stdout.splitOn "\n" |>.any (fun line =>
        let value := line.trimAscii.toString
        value == engine || value.startsWith (engine++" ")) then throw (IO.userError "runtime still live")
  let mut removed := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "search-inputs-" && entry.fileName.endsWith "-result" &&
        (← entry.path.symlinkMetadata).type == .dir then
      removed := removed.push (entry.fileName,← erase entry.path)
  if ← (output/"restoration.json").pathExists then
    for name in ["search-inputs-build","search-inputs-receipt-build","search-inputs-baseline-core",
        "search-inputs-build-settings.json","search-inputs-receipt-build-settings.json"] do
      removed := removed.push (name,← erase (base/name))
    let helper := base/"interest-traffic-core/tools/research/ReceiptPublicationProfile.lean"
    removed := removed.push (helper.toString,← erase helper)
  for entry in ← base.readDir do
    if entry.fileName.startsWith "search-inputs-" &&
        [".guard.json",".guard-settings.json",".log","-result.json"].any (fun suffix => entry.fileName.endsWith suffix) then
      removed := removed.push (entry.fileName,← erase entry.path)
  verifyOriginals
  save "cleanup.json" (Json.mkObj [("deleted",toJson removed),("archived",toJson false),
    ("retainedActiveOriginalsAndParentBuildInputs",toJson true),("originalHeadsUnchanged",toJson true)])
def main (args : List String) : IO Unit := do
  match args with
  | ["check"] => pure ()
  | ["seal"] => sealRecords
  | ["restore"] => restoreParent
  | ["receipt-profile"] => receiptProfile
  | ["cleanup"] => cleanup
  | _ => throw (IO.userError "check, seal, restore, receipt-profile or cleanup required")
