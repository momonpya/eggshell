import tools.research.StudyLocal
open Lean StudyLocal

def trial := base/"quiescent-page-base"
def candidateSource := trial/"source"
def candidateBuild := trial/"build"
def selectedBuild := base/"current-six/stable-source-rows/build"
def selected := base/"current-six/fixed-sequence/cohort/prefix"
def records := project/"docs/candidates/quiescent-page-base"
def entryModule := "tools.research.OwnedSelectionRuntime"
def installation := trial/"prefix"
def armOrder : Array String := #["a1","b1","b2","a2"]

def clean (tag : String) : IO Json := do
  let value ← finished tag
  check (value.getObjValD "guardTriggered" == toJson false && value.getObjValD "reason" == Json.null)
    "the supervisor did not finish normally"
  return value

def collectArm (label : String) : IO Json := do
  check (armOrder.contains label) "arm outside fixed ABBA"
  let monitor ← read (base/("quiescent-pages-arm-"++label++".guard.json"))
  check (monitor.getObjValD "state" == toJson "finished" &&
    monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "arm is not terminal and drained"
  let root := trial/"arms"/label
  let input ← read (trial/(label++"-input.json"))
  let dataRoot : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let report ← if ← (root/"report.json").pathExists then read (root/"report.json") else pure Json.null
  let mut phases := #[]
  let mut pages := #[]
  for count in (#[(4 : Nat),16]) do
    let result := root/s!"phase-{count}"/"result.json"
    if !(← result.pathExists) then continue
    let phase ← read result
    phases := phases.push phase
    for row in ← IO.ofExcept (phase.getObjValAs? (Array Json) "rows") do
      let pageRecord ← match row.getObjValAs? String "receipt" with
        | .error _ => pure Json.null
        | .ok id => do
          let path := dataRoot/"receipts"/id/"request-pages.json"
          if ← path.pathExists then read path else pure Json.null
      pages := pages.push (Json.mkObj [("clients",toJson count),("client",row),("pageRecord",pageRecord)])
  let normal := monitor.getObjValD "exitCode" == toJson (0 : Nat) &&
    monitor.getObjValD "guardTriggered" == toJson false && monitor.getObjValD "reason" == Json.null
  if normal then check (report.getObjValD "allPhasesPassed" == toJson true) "normal arm lacks its successful final report"
  let sourceRoot : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  let mut unchanged := true
  for (name,digest) in files do
    if ← (sourceRoot/name).pathExists then unchanged := unchanged && (← hash (sourceRoot/name)) == digest
    else unchanged := false
  let result := Json.mkObj [("label",toJson label),("guard",monitor),("normalExit",toJson normal),
    ("report",report),("completedPhases",toJson phases),("pageRecords",toJson pages),
    ("sourceFilesUnchanged",toJson unchanged),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.createDirAll (records/"arms")
  write (records/"arms"/(label++".json")) result
  return result

def main (args : List String) : IO Unit := do
  if args == ["setup"] then
    idle
    check ((← hash (selected/"libexec/eggshell")) == "dd53c89bc450b66b58dd57d104ccbc82f32ca6345fa9666125e7feb03017000e") "fixed parent changed"
    check (!(← trial.pathExists)) "fresh isolated candidate required"
    IO.FS.createDir trial
    IO.FS.createDirAll records
    materialize selectedBuild candidateSource candidateBuild entryModule "quiescent-pages-settings.json"
    write (records/"plan.json") (Json.mkObj [
      ("parentSha256",toJson "dd53c89bc450b66b58dd57d104ccbc82f32ca6345fa9666125e7feb03017000e"),
      ("treatment",toJson "one immutable verified-page base per live reader epoch;request-only append fronts;one-shot retirement;merge and promote only at the coordinator"),
      ("unchanged",toJson "ranking,WorkGraph,Exact,all three advisory edges,original evidence,model,prompt,deadlines,ACK"),
      ("comparison",toJson "native component checks then exact three-topic bodies;predeclared parent/candidate/candidate/parent at4and16 on one final snapshot"),
      ("maxClients",toJson (16 : Nat)),("publicPageAllowanceBytes",toJson (134217728 : Nat)),
      ("aggregateMemoryLimitBytes",toJson (5000000000 : Nat)),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  else if args.head? == some "build" then
    let [_,label] := args | throw (IO.userError "build <unique-attempt-label>")
    check (!label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-')) "invalid build label"
    let modulePath := "tools/research/QuiescentPagesChecks.lean"
    IO.FS.writeFile (candidateSource/modulePath) (← IO.FS.readFile (project/modulePath))
    let entry := candidateSource/"tools/research/OwnedSelectionRuntime.lean"
    let original ← IO.FS.readFile entry
    if !(original.contains "import tools.research.QuiescentPagesChecks") then
      let marker := "  match args with\n"
      check ((original.splitOn marker).length == 2) "one native command dispatch required"
      IO.FS.writeFile entry ("import tools.research.QuiescentPagesChecks\n"++original.replace marker
        (marker++"  | [\"quiescent-page-check\",root] => QuiescentPagesChecks.run (.mk root); return 0\n"))
    let tag := "quiescent-pages-build-"++label
    guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"quiescent-pages-settings.json").toString]
    write (records/"current-build.json") (Json.mkObj [("tag",toJson tag)])
  else if args.head? == some "audit" then
    let [_,label] := args | throw (IO.userError "audit <unique-label>")
    check (!label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-')) "invalid audit label"
    let tag ← IO.ofExcept ((← read (records/"current-build.json")).getObjValAs? String "tag")
    discard <| clean tag
    let auditTag := "quiescent-pages-audit-"++label
    guard auditTag #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/QuiescentPagesStudy.lean").toString,"audit-worker",label]
    write (records/"current-audit.json") (Json.mkObj [("tag",toJson auditTag)])
  else if args.head? == some "audit-worker" then
    let [_,label] := args | throw (IO.userError "audit-worker <label>")
    let call := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| call #["inspect",candidateBuild.toString,(records/("native-"++label++".json")).toString]
    let (oldEntry,oldLiterals) : String × Array (String × String) ← IO.ofExcept
      (fromJson? (← read (selectedBuild/"tools_research_OwnedSelectionRuntime.source")))
    let (newEntry,newLiterals) : String × Array (String × String) ← IO.ofExcept
      (fromJson? (← read (candidateBuild/"tools_research_OwnedSelectionRuntime.source")))
    let marker := "  match args with\n"
    let expected := "import tools.research.QuiescentPagesChecks\n"++oldEntry.replace marker
      (marker++"  | [\"quiescent-page-check\",root] => QuiescentPagesChecks.run (.mk root); return 0\n")
    check (newEntry == expected && oldLiterals == newLiterals) "native entry changed beyond the explicit checker command"
    write (records/"entry-verified.json") (Json.mkObj [("nativeEntryOnlyAddsChecker",toJson true),
      ("candidateSha256",toJson (← hash (candidateBuild/"StudyMain")))])
    discard <| call #["compare-sources",selectedBuild.toString,candidateBuild.toString,(records/"sources.json").toString,
      "Eggshell.DB.PageMap","Eggshell.PreparedReaders","Eggshell.SearchReaders","Eggshell.OperationPool",
      "+tools.research.QuiescentPagesChecks"]
  else if args == ["check"] then
    let tag ← IO.ofExcept ((← read (records/"current-audit.json")).getObjValAs? String "tag")
    discard <| clean tag
    guard "quiescent-pages-check" #[(candidateBuild/"StudyMain").toString,"quiescent-page-check",(trial/"checks").toString]
  else if args == ["install"] then
    discard <| clean "quiescent-pages-check"
    check (!(← installation.pathExists)) "fresh isolated installation required"
    let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let oldPlugin : System.FilePath := .mk (← IO.ofExcept (original.getObjValAs? String "plugin"))
    let plugin := installation/"share/eggshell/codex-plugin"
    IO.FS.createDirAll (installation/"libexec")
    IO.FS.createDirAll (plugin/"bin")
    discard <| command "/bin/ln" #["-s",(candidateBuild/"StudyMain").toString,(installation/"libexec/eggshell").toString]
    discard <| command "/bin/ln" #["-s",(selected/"share/eggshell/minilm").toString,(installation/"share/eggshell/minilm").toString]
    for name in ["egg","eggshelld"] do
      let text ← IO.FS.readFile (oldPlugin/"bin"/name)
      check (text.contains selected.toString) "reviewed launcher has a different runtime boundary"
      IO.FS.writeFile (plugin/"bin"/name) (text.replace selected.toString installation.toString)
      discard <| command "/bin/chmod" #["755",(plugin/"bin"/name).toString]
    check ((← IO.FS.realPath (selected/"share/eggshell/minilm")) ==
      (← IO.FS.realPath (installation/"share/eggshell/minilm"))) "model/runtime assets differ"
    write (records/"runtime.json") (Json.mkObj [("candidateSha256",toJson (← hash (candidateBuild/"StudyMain"))),
      ("parentSha256",toJson (← hash (selected/"libexec/eggshell"))),("orderedArms",toJson armOrder),
      ("countsPerArm",toJson (#[(4 : Nat),16])),("fewSecondTargetWaveMs",toJson (5000 : Nat)),
      ("referenceInputSha256",toJson (← hash (base/"snapshot-scheduling/capacity-16-input.json"))),
      ("sameModelAssets",toJson true),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  else if args.head? == some "collect-arm" then
    let [_,label] := args | throw (IO.userError "collect-arm <label>")
    discard <| collectArm label
  else if args == ["report"] then
    let mut all := #[]
    let mut parentTimes := #[]
    let mut candidateTimes := #[]
    for label in armOrder do
      let row ← collectArm label
      check (row.getObjValD "normalExit" == toJson true && row.getObjValD "sourceFilesUnchanged" == toJson true)
        "incomplete or changed-source arm cannot become a performance comparison"
      let phases : Array Json ← IO.ofExcept (fromJson? (row.getObjValD "completedPhases"))
      let some phase := phases.find? (fun item => item.getObjValD "clients" == toJson (16 : Nat)) |
        throw (IO.userError "16-client arm missing")
      check (phase.getObjValD "passed" == toJson true) "failed phase"
      let time ← IO.ofExcept (phase.getObjValAs? Nat "wallMs")
      if label.startsWith "b" then candidateTimes := candidateTimes.push time else parentTimes := parentTimes.push time
      all := all.push row
    check (parentTimes.size == 2 && candidateTimes.size == 2) "non-vacuous same-count replication required"
    let parentTotal := parentTimes.foldl Nat.add 0
    let candidateTotal := candidateTimes.foldl Nat.add 0
    check (parentTotal > 0) "invalid clock"
    let reduction := 100.0*(Float.ofNat parentTotal - Float.ofNat candidateTotal)/Float.ofNat parentTotal
    write (records/"comparison.json") (Json.mkObj [("orderedArms",toJson armOrder),("arms",toJson all),
      ("parent16WallMs",toJson parentTimes),("candidate16WallMs",toJson candidateTimes),
      ("descriptiveMeanLatencyReductionPercent",toJson reduction),
      ("fewSecond16ClientTargetMet",toJson (candidateTimes.all (· ≤ 5000))),
      ("p99Established",toJson false),("eightyConcurrentTest",toJson false),("answeringModelCalls",toJson (0 : Nat)),
      ("inclusiveTokenOrQualityBenefitEstablished",toJson false),("adopted",toJson false)])
  else if args.head? == some "prepare-arm" then
    let [_,label] := args | throw (IO.userError "prepare-arm a1|b1|b2|a2")
    let some position := armOrder.findIdx? (· == label) | throw (IO.userError "arm outside fixed ABBA")
    let declared ← read (records/"runtime.json")
    if position > 0 then
      let some prior := armOrder[position-1]? | throw (IO.userError "missing prior arm")
      discard <| clean ("quiescent-pages-arm-"++prior)
      let report ← read (trial/"arms"/prior/"report.json")
      check (report.getObjValD "allPhasesPassed" == toJson true) "stop after a failed arm"
    let chosenPrefix := if label.startsWith "b" then installation else selected
    let runtime := chosenPrefix/"libexec/eggshell"
    let expected := declared.getObjValD (if label.startsWith "b" then "candidateSha256" else "parentSha256")
    check (expected == toJson (← hash runtime)) "sealed runtime changed"
    let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let output := trial/"arms"/label
    let config := output/"config.toml"
    let plugin ← if label.startsWith "b" then pure (installation/"share/eggshell/codex-plugin").toString
      else IO.ofExcept (original.getObjValAs? String "plugin")
    let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
    let environment := environment.map fun (key,value) => (key,match key with
      | "EGGSHELL_PREFIX" => some chosenPrefix.toString
      | "PLUGIN_ROOT" => some plugin
      | "EGGSHELL_CONFIG" => some config.toString
      | _ => value)
    let input := original.setObjVal! "output" (toJson output.toString)
      |>.setObjVal! "config" (toJson config.toString) |>.setObjVal! "environment" (toJson environment)
      |>.setObjVal! "runtime" (toJson runtime.toString) |>.setObjVal! "runtimeSha256" expected
      |>.setObjVal! "plugin" (toJson plugin)
    let inputPath := trial/(label++"-input.json")
    check (!(← inputPath.pathExists)) "never overwrite or automatically retry an arm"
    write inputPath input
    let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
    guard ("quiescent-pages-arm-"++label) (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++
      #[runtime.toString,"owned-selection-capacity",inputPath.toString])
  else throw (IO.userError "setup|build|audit|audit-worker|check")
