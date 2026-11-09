import tools.research.StudyLocal
open Lean StudyLocal
def number (value : Json) (key : String) : Nat := (value.getObjValAs? Nat key).toOption.getD 0
def sampleSummary (path : System.FilePath) : IO Json := do
  let mut largestRss := Json.null
  let mut largestFootprint := Json.null
  let mut largestSwapped := Json.null
  let mut processes : Std.HashMap Nat Json := {}
  let mut count := 0
  let mut errors := 0
  for line in (← IO.FS.readFile path).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let record ← IO.ofExcept (Json.parse line)
    if record.getObjValD "noLiveNativeProcesses" == toJson true then continue
    count := count+1
    let os := record.getObjValD "osFootprint"
    let rows ← IO.ofExcept (record.getObjValAs? (Array Json) "rows")
    let rss := rows.foldl (fun sum row => sum+number (row.getObjValD "before") "rssKiB") 0
    let swapped := number ((os.getObjValD "summary").getObjValD "total") "swapped"
    let total := number os "total footprint"
    if number record "footprintExit" != 0 || !(os.getObjValD "errors" == toJson (#[] : Array Json)) then errors := errors+1
    let sample := Json.mkObj [("fromMs",record.getObjValD "fromMs"),("toMs",record.getObjValD "toMs"),
      ("nativeRssKiB",toJson rss),("osTotalFootprintBytes",toJson total),("swappedBytes",toJson swapped),
      ("observerRssKiB",record.getObjValD "observerRssKiB"),
      ("identitiesStable",toJson (rows.all (·.getObjValD "sameIdentityAfter" == toJson true)))]
    if rss > number largestRss "nativeRssKiB" then largestRss := sample
    if total > number largestFootprint "osTotalFootprintBytes" then largestFootprint := sample
    if swapped > number largestSwapped "swappedBytes" then largestSwapped := sample
    for process in ← IO.ofExcept (os.getObjValAs? (Array Json) "processes") do
      let pid := number process "pid"
      let old := processes[pid]?.getD Json.null
      let peak := max (number (process.getObjValD "auxiliary") "phys_footprint_peak") (number old "lifetimePeakBytes")
      let high := max (number process "footprint") (number old "sampledFootprintPeakBytes")
      processes := processes.insert pid (Json.mkObj [("pid",toJson pid),("name",process.getObjValD "name"),
        ("lifetimePeakBytes",toJson peak),("sampledFootprintPeakBytes",toJson high)])
  check (count > 0 && number largestFootprint "osTotalFootprintBytes" > 0) "OS observation was vacuous"
  return Json.mkObj [("samples",toJson count),("osErrors",toJson errors),("largestNativeRssSample",largestRss),
    ("largestTotalFootprintSample",largestFootprint),("largestSwappedSample",largestSwapped),
    ("processPeaksNotSimultaneous",toJson (processes.toArray.map Prod.snd)),
    ("observerExcludedFromNativeFootprint",toJson true),("rssGuardIncludesObserver",toJson true)]
def main (args : List String) : IO Unit := do
  match args with
  | ["observer-build"] =>
    guard "footprint-native-build2" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M768","--run",(base/"footprint-native-build.lean").toString,"compile"]
  | ["plan"] =>
    idle
    discard <| finished "footprint-native-build2"
    check ((← read (base/"footprint-baseline-closure.json")).getObjValD "consistent" == toJson true) "baseline native closure failed"
    check ((← read (base/"footprint-baseline-common.json")).getObjValD "commonSourcesUnchanged" == toJson true) "baseline product sources differ"
    let observer := base/"footprint-native/Observer"
    let previous ← read (base/"footprint-diagnostic-input.json")
    let mut arms := #[]
    for (tag,isCandidate) in #[("a1",false),("b1",true),("b2",true),("a2",false)] do
      let installRoot := base/(if isCandidate then "compiled-owner-plan-prefix" else "byte-pages-prefix")
      let harness := base/(if isCandidate then "compiled-owner-plan-auditor-build/StudyMain" else "footprint-baseline-build/StudyMain")
      let runtime := installRoot/"libexec/eggshell"
      let root := base/("footprint-"++tag++"-result")
      let config := root/"config.toml"
      let environment ← IO.ofExcept (previous.getObjValAs? (Array (String × Option String)) "environment")
      let environment := environment.map fun (key,value) => (key,
        if key == "EGGSHELL_CONFIG" then some config.toString
        else if key == "EGGSHELL_PREFIX" then some installRoot.toString
        else if key == "PLUGIN_ROOT" then some (installRoot/"share/eggshell/codex-plugin").toString
        else value)
      check (!(← root.pathExists)) "preserve existing arm results"
      let input := previous.setObjVal! "output" (toJson root.toString) |>.setObjVal! "config" (toJson config.toString)
        |>.setObjVal! "environment" (toJson environment) |>.setObjVal! "counts" (toJson (#[(4 : Nat),16]))
        |>.setObjVal! "diagnostic" (toJson false) |>.setObjVal! "runtime" (toJson runtime.toString)
        |>.setObjVal! "runtimeSha256" (toJson (← hash runtime))
        |>.setObjVal! "plugin" (toJson (installRoot/"share/eggshell/codex-plugin").toString)
      let path := base/("footprint-"++tag++"-input.json")
      write path input
      let unset := environment.toList.flatMap fun (key,value) => if value.isNone then ["-u",key] else []
      let command := #["/usr/bin/env"]++unset.toArray++
        environment.filterMap (fun (key,value) => value.map (fun value => key++"="++value))++
        #[observer.toString,harness.toString,path.toString,(base/("footprint-"++tag++"-samples.jsonl")).toString]
      guard ("footprint-"++tag) command
      arms := arms.push (Json.mkObj [("tag",toJson tag),("candidate",toJson isCandidate),
        ("harnessSha256",toJson (← hash harness)),("input",input)])
    let evidence := project/"docs/candidates/process-footprint/paired-plan.json"
    check (!(← evidence.pathExists)) "preserve predeclared plan"
    write evidence (Json.mkObj [("order",toJson #["a1","b1","b2","a2"]),("arms",toJson arms),
      ("observerSha256",toJson (← hash observer)),("observerSourceSha256",toJson (← hash (base/"footprint-native/Observer.lean"))),
      ("counts",toJson (#[(4 : Nat),16])),("nativeClosure",← read (base/"footprint-baseline-closure.json")),
      ("commonProductSources",← read (base/"footprint-baseline-common.json")),
      ("sameCapacityAlgorithm",toJson true),("rssLimitKiB",toJson (4358524 : Nat)),
      ("userCeilingBytes",toJson (5000000000 : Nat)),("observationAffectsTiming",toJson true),
      ("performanceAdoptionTest",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["summarize",tag] =>
    idle
    let record ← finished ("footprint-"++tag)
    let root := base/("footprint-"++tag++"-result")
    let report ← read (root/"report.json")
    let phases ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
    let stages ← phases.mapM fun phase => do
      let rows ← IO.ofExcept (phase.getObjValAs? (Array Json) "rows")
      let counts := rows.foldl (fun total row => total+number row "frozenOriginals") 0
      let times := rows.map (fun row => number row "elapsedMs")
      return Json.mkObj [("clients",phase.getObjValD "clients"),("passed",phase.getObjValD "passed"),
        ("semanticCompleted",phase.getObjValD "semanticCompleted"),("synapsesCompleted",phase.getObjValD "synapsesCompleted"),
        ("allBodiesByteEqual",phase.getObjValD "allBodiesByteEqual"),("wallMs",phase.getObjValD "wallMs"),
        ("clientMinMs",toJson (times.foldl min (times[0]?.getD 0))),("clientMaxMs",toJson (times.foldl max 0)),
        ("frozenOriginalDeliveries",toJson counts),("allAcknowledged",toJson (rows.all (·.getObjValD "acknowledged" == toJson true)))]
    let output := project/"docs/candidates/process-footprint"/(tag++".json")
    check (!(← output.pathExists)) "preserve observed arm"
    write output (Json.mkObj [("tag",toJson tag),("stages",toJson stages),
      ("rssGuardPeakKiB",record.getObjValD "sampledPeakRssKiB"),("guardExit",record.getObjValD "exitCode"),
      ("ownedPids",record.getObjValD "ownedPids"),("observations",← sampleSummary (base/("footprint-"++tag++"-samples.jsonl"))),
      ("frontendShutdown",← read (root/"frontend-shutdown.json")),("publisherShutdown",← read (root/"publisher-shutdown.json")),
      ("adopted",toJson false)])
    IO.println (← read output).compress
  | ["failure"] =>
    idle
    let record ← read (base/"footprint-a1.guard.json")
    check (record.getObjValD "state" == toJson "finished" && record.getObjValD "exitCode" == toJson (1 : Nat) &&
      record.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "failed arm not fully drained"
    let root := base/"footprint-a1-result"
    let phase ← read (root/"phase-4/result.json")
    let receipts ← read (root/"phase-4/receipts.json")
    let rows ← IO.ofExcept (phase.getObjValAs? (Array Json) "rows")
    let some failed := rows.find? (·.getObjValD "success" == toJson false) | throw (IO.userError "no failed client")
    let receipt ← IO.ofExcept (failed.getObjValAs? String "receipt")
    let mut numeric := #[]
    for entry in ← (base/"prepared-literals-fixture/data/receipts"/receipt).readDir do
      if !entry.fileName.startsWith "numerical-" then continue
      let actual := (← read entry.path).getObjValD "data"
      let counters := actual.getObjValD "counters"
      numeric := numeric.push (Json.mkObj [("status",actual.getObjValD "status"),("elapsedMs",actual.getObjValD "elapsedMs"),
        ("corpus",actual.getObjValD "corpus"),("queryMs",counters.getObjValD "queryMs"),
        ("scoreMs",counters.getObjValD "scoreMs"),("scoredWindows",counters.getObjValD "scoredWindows"),
        ("projectionHits",counters.getObjValD "projectionHits"),("projectionMisses",counters.getObjValD "projectionMisses"),
        ("numericalReplies",counters.getObjValD "numericalReplies")])
    let diagnostic := base/"footprint-diagnostic-result"
    write (project/"docs/candidates/process-footprint/observation.json") (Json.mkObj [
      ("candidateFourClientDiagnostic",Json.mkObj [("report",← read (diagnostic/"report.json")),
        ("observations",← sampleSummary (base/"footprint-diagnostic-samples.jsonl")),
        ("guard",← finished "footprint-diagnostic2")]),
      ("baselineFailedArm",Json.mkObj [("phase",phase),("receipts",receipts),("numerical",toJson numeric),
        ("observations",← sampleSummary (base/"footprint-a1-samples.jsonl")),
        ("guard",record),("frontendShutdown",← read (root/"frontend-shutdown.json")),
        ("publisherShutdown",← read (root/"publisher-shutdown.json")),
        ("stdoutSha256",toJson (← hash (root/"phase-4/client-0/stdout")))]),
      ("pairedComparisonCompleted",toJson false),("remainingArmsStarted",toJson false),
      ("conclusion",toJson "RSS and OS footprint are different; the baseline failed before paired 16-client memory evidence. No candidate memory improvement established."),
      ("rootCauseConfirmed",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | _ => throw (IO.userError "observer-build|plan|summarize TAG")
