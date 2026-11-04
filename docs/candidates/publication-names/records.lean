import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def folder := workspace/"docs/candidates/publication-names"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def write (name : String) (value : Json) : IO Unit := IO.FS.writeFile (folder/name) (value.pretty++"\n")
def nat (value : Json) (name : String) : Nat := (value.getObjValAs? Nat name).toOption.getD 0
def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return result.stdout.take 64 |>.toString
def guards : IO (Array Json) := do
  let mut rows := #[]
  for entry in ← base.readDir do
    if (entry.fileName.startsWith "interest-traffic-" || entry.fileName.startsWith "publication-names-probe-") &&
        entry.fileName.endsWith ".guard.json" then
      let row ← read entry.path
      unless row.getObjValD "state" == toJson "finished" && row.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "a controlled guard still owns work")
      rows := rows.push ((row.setObjVal! "settings" Json.null).setObjVal! "tag" (toJson entry.fileName))
  return rows
def summary (name : String) : IO Json := do
  let root := base/("interest-traffic-fixture-"++name)
  let report ← read (root/"numeric-execution-report.json")
  let outcomes ← read (root/"load-outcomes.json")
  let queries ← IO.ofExcept (outcomes.getObjValAs? (Array Json) "queries")
  let errors ← IO.ofExcept (outcomes.getObjValAs? (Array Json) "errors")
  unless report.getObjValD "allPassed" == toJson true && queries.size == 80 && errors.isEmpty &&
      nat outcomes "durableSaves" == 80 && queries.all (fun row => row.getObjValD "evidencePassed" == toJson true) do
    throw (IO.userError s!"incomplete trial cannot enter the final series: {name}")
  let audit := report.getObjValD "preparationAudit"
  let inspections ← IO.ofExcept (audit.getObjValAs? (Array Json) "inspections")
  let coverage : Nat × Nat × Nat := inspections.foldl (fun result source =>
    let counts := source.getObjValD "coverage"
    (result.1+nat counts "windows",result.2.1+nat counts "missing",result.2.2+nat counts "invalid")) (0,0,0)
  let prep := (report.getObjValD "afterLoad").getObjValD "preparation"
  let selected := #["p50Ms","p95Ms","maxMs","saveP50Ms","saveP95Ms","saveMaxMs","queryMs","saveMs",
    "semanticReadyReplies","lexicalFallbackReplies","independentOriginalStreams","writerClients","elapsedMs"]
  let mut result := Json.mkObj (selected.toList.map fun key => (key,report.getObjValD key))
  result := result.setObjVal! "trial" (toJson name) |>.setObjVal! "queries" (toJson queries)
    |>.setObjVal! "evidenceQueriesPassed" (toJson (queries.filter (fun row => row.getObjValD "evidencePassed" == toJson true)).size)
    |>.setObjVal! "durableSaves" (outcomes.getObjValD "durableSaves")
    |>.setObjVal! "restoredOriginals" (audit.getObjValD "restoredOriginals")
    |>.setObjVal! "drainMs" ((audit.getObjValD "drain").getObjValD "elapsedMs")
    |>.setObjVal! "drainComplete" ((audit.getObjValD "drain").getObjValD "complete")
    |>.setObjVal! "newQuery" (audit.getObjValD "newQuery")
    |>.setObjVal! "restartQuery" (audit.getObjValD "restartQuery")
    |>.setObjVal! "originalHeadsUnchanged" (audit.getObjValD "originalHeadsUnchanged")
    |>.setObjVal! "numericWindows" (toJson coverage.1)
    |>.setObjVal! "numericMissing" (toJson coverage.2.1)
    |>.setObjVal! "numericInvalid" (toJson coverage.2.2)
    |>.setObjVal! "preparationAfterLoad" prep
    |>.setObjVal! "preparationAfterDrain" (((audit.getObjValD "drain").getObjValD "samples").getArr?.toOption.getD #[] |>.back?.map (·.getObjValD "state") |>.getD Json.null)
    |>.setObjVal! "errors" (toJson errors)
  if name == "prepared6" || name == "cold7" then
    for sample in ["semantic-body.txt","fallback-body.txt","traffic-new-reader-body.txt"] do
      if ← (root/sample).pathExists then
        IO.FS.writeFile (folder/(name++"-"++sample)) (← IO.FS.readFile (root/sample))
  return result
partial def bytes (path : System.FilePath) : IO Nat := do
  let stat ← path.symlinkMetadata
  if stat.type != .dir then return stat.byteSize.toNat
  let mut total := 0
  for entry in ← path.readDir do total := total+(← bytes entry.path)
  return total
def main (args : List String) : IO Unit := do
  let guarded ← guards
  if args == ["collect"] then
    IO.FS.createDirAll folder
    let mut trials := #[]
    for name in ["prepared6","prepared7","prepared8","cold7","cold8","cold9"] do
      trials := trials.push (← summary name)
    write "trials.json" (toJson trials)
    write "resources.json" (Json.mkObj [("guards",toJson guarded),
      ("peakRssKiB",toJson (guarded.foldl (fun peak row => max peak (nat row "sampledPeakRssKiB")) 0)),
      ("aggregateStopRssKiB",toJson (3670016 : Nat)),("hardRssKiB",toJson (4194304 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat))])
    let mut failures := #[]
    for row in guarded do
      if row.getObjValD "exitCode" != toJson (0 : Nat) then
        let tag ← IO.ofExcept (row.getObjValAs? String "tag")
        let log := (tag.dropEnd ".guard.json".length).copy++".log"
        let text ← IO.FS.readFile (base/log)
        let errors := text.splitOn "\n" |>.filter (fun line =>
          line.contains ": error" || line.contains " failed:" || line.contains "uncaught exception")
        failures := failures.push (Json.mkObj [("guard",row),("logSha256",toJson (← digest (base/log))),
          ("errors",toJson errors)])
    write "save-stage-diagnosis.json" (← read (base/"interest-traffic-fixture-prepared3/save-stage-diagnosis.json"))
    write "clock-probe.json" (← read (base/"interest-traffic-fixture-prepared3/clock-probe.json"))
    write "immutable.json" (← read (base/"interest-traffic-fixture-names-immutable/report.json"))
    write "allocation.json" (← read (base/"interest-traffic-fixture-names-allocation/allocation.json"))
    write "allocation-ablation.json" (← read (base/"interest-traffic-fixture-names-ablation/allocation-ablation.json"))
    write "negative-checks.json" (toJson failures)
    let mut patch := ""
    for name in ["Eggshell/FileSystem.lean","Eggshell/DB/PageMap.lean"] do
      let original := base/"publication-names-baseline"/name
      let present ← original.pathExists
      let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","--label",
        if present then "a/"++name else "/dev/null","--label","b/"++name,
        if present then original.toString else "/dev/null",(base/"interest-traffic-core"/name).toString]}
      unless result.exitCode ≤ 1 do throw (IO.userError result.stderr)
      patch := patch++result.stdout
    IO.FS.writeFile (folder/"candidate.patch") patch
    let mut unchanged := #[]
    let prior ← read (workspace/"docs/candidates/interest-traffic/identity.json")
    let preserved ← IO.ofExcept (prior.getObjValAs? (Array Json) "unchanged")
    for row in preserved do
      let name ← IO.ofExcept (row.getObjValAs? String "source")
      let before ← IO.ofExcept (row.getObjValAs? String "sha256")
      let after ← digest (base/"interest-traffic-core"/name)
      unless before == after do throw (IO.userError s!"original authority or delivery code changed: {name}")
      unchanged := unchanged.push (Json.mkObj [("source",toJson name),("sha256",toJson before)])
    write "identity.json" (Json.mkObj [("helperSha256",toJson (← digest (base/"interest-traffic-build/StudyMain"))),
      ("probeSha256",toJson (← digest (base/"publication-names-probe-build/StudyMain"))),
      ("parentSha256",prior.getObjValD "helperSha256"),
      ("unchanged",toJson unchanged),("answeringModelCalls",toJson (0 : Nat)),
      ("tokenComparisons",toJson (0 : Nat)),("adopted",toJson false)])
    for (source,target) in [("interest-traffic-setup.lean","setup.lean"),("publication-names-records.lean","records.lean"),
        ("publication-names-probe-setup.lean","probe-setup.lean"),
        ("interest-traffic-laws-setup.lean","laws-setup.lean"),("interest-traffic-laws3.log","laws.txt")] do
      IO.FS.writeFile (folder/target) (← IO.FS.readFile (base/source))
    write "series.json" (Json.mkObj [("status",toJson "six-native-bursts-passed"),
      ("requiredPerCondition",toJson (3 : Nat)),("fullyPassedTrials",toJson trials.size),
      ("sustainedEightyPeopleEightHours",toJson false),("practical98PercentDelivery",toJson false),
      ("adopted",toJson false)])
    IO.println s!"collected {trials.size} native trials"
  else if args == ["cleanup"] then
    unless (← (folder/"identity.json").pathExists) && !(← (folder/"cleanup.json").pathExists) do
      throw (IO.userError "seal evidence first; preserve existing cleanup accounting")
    let mut removed := #[]
    let mut total := 0
    for entry in ← base.readDir do
      let fixture := entry.fileName.startsWith "interest-traffic-fixture-" ||
        entry.fileName == "publication-names-baseline" || entry.fileName == "publication-names-probe-build"
      let latest ← IO.ofExcept ((← read (base/"interest-traffic-latest-build.json")).getStr?)
      let disposable := (entry.fileName.startsWith "interest-traffic-" ||
          entry.fileName.startsWith "publication-names-probe-") &&
        ([".log",".guard.json",".guard-settings.json"].any (fun suffix => entry.fileName.endsWith suffix) ||
          (entry.fileName.startsWith "interest-traffic-probe" && entry.fileName.endsWith ".olean"))
      if (fixture || disposable) && entry.fileName != latest then
        let size ← bytes entry.path
        if fixture then IO.FS.removeDirAll entry.path else IO.FS.removeFile entry.path
        total := total+size
        removed := removed.push (Json.mkObj [("path",toJson entry.path.toString),("apparentBytes",toJson size)])
    write "cleanup.json" (Json.mkObj [("removed",toJson removed),("apparentBytes",toJson total),
      ("archiveCreated",toJson false),("currentBuildInputsRetained",toJson true)])
    IO.println s!"deleted {total} apparent bytes without archives"
  else throw (IO.userError "collect or cleanup required")
