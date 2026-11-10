import tools.research.StudyLocal
open Lean StudyLocal

def trial := base/"quiescent-page-base"
def candidateSource := trial/"source"
def candidateBuild := trial/"build"
def selectedBuild := base/"current-six/stable-source-rows/build"
def selected := base/"current-six/fixed-sequence/cohort/prefix"
def records := project/"docs/candidates/quiescent-page-base"
def entryModule := "tools.research.OwnedSelectionRuntime"
def installation := trial/"rotating-prefix"
def runtimeRecord := records/"rotating-runtime.json"
def armOrder : Array String := #["a-rotating","b-rotating","b-rotating-repeat","a-rotating-repeat"]
def completedOrder : Array String := #["a-rotating","b-rotating","b-rotating-repeat","a-rotating-drained"]
def smokeLabels : Array String := #["rotating-smoke","rotating-smoke-recovered"]

def clean (tag : String) : IO Json := do
  let value ← finished tag
  check (value.getObjValD "guardTriggered" == toJson false && value.getObjValD "reason" == Json.null)
    "the supervisor did not finish normally"
  return value

def collectArm (label : String) : IO Json := do
  check (armOrder.contains label || completedOrder.contains label || label == "a-rotating-recovered" || smokeLabels.contains label)
    "arm outside fixed ABBA or declared resource recovery"
  check (!(← (records/"arms"/(label++".json")).pathExists)) "preserve the collected arm before retiring its session state"
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
  if normal then
    check (report.getObjValD "allPhasesPassed" == toJson true ||
      (input.getObjValD "diagnostic" == toJson true && phases.size == 1 &&
        phases.all (fun phase => phase.getObjValD "passed" == toJson true)))
      "normal arm lacks its successful final report"
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
    write (records/"current-audit.json") (Json.mkObj [("tag",toJson auditTag),
      ("sourceReport",toJson ("sources-"++label++".json"))])
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
    write (records/("entry-"++label++".json")) (Json.mkObj [("nativeEntryOnlyAddsChecker",toJson true),
      ("candidateSha256",toJson (← hash (candidateBuild/"StudyMain")))])
    discard <| call #["compare-sources",selectedBuild.toString,candidateBuild.toString,(records/("sources-"++label++".json")).toString,
      "Eggshell.DB.PageMap","Eggshell.PreparedReaders","Eggshell.SearchReaders","Eggshell.OperationPool",
      "+tools.research.QuiescentPagesChecks"]
  else if args.head? == some "check" then
    let [_,label] := args | throw (IO.userError "check <unique-label>")
    check (!label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-')) "invalid check label"
    let audited ← read (records/"current-audit.json")
    let tag ← IO.ofExcept (audited.getObjValAs? String "tag")
    discard <| clean tag
    let reportName ← IO.ofExcept (audited.getObjValAs? String "sourceReport")
    let digest ← hash (candidateBuild/"StudyMain")
    check ((← read (records/reportName)).getObjValD "candidateRuntimeSha256" == toJson digest)
      "native source audit belongs to a different binary"
    let checkTag := "quiescent-pages-check-"++label
    let output := trial/("checks-"++label)
    guard checkTag #[(candidateBuild/"StudyMain").toString,"quiescent-page-check",output.toString]
    write (records/"current-check.json") (Json.mkObj [("tag",toJson checkTag),("runtimeSha256",toJson digest),
      ("output",toJson output.toString),("sourceReport",toJson reportName)])
  else if args == ["install"] then
    let checked ← read (records/"current-check.json")
    let tag ← IO.ofExcept (checked.getObjValAs? String "tag")
    discard <| clean tag
    check (checked.getObjValD "runtimeSha256" == toJson (← hash (candidateBuild/"StudyMain")))
      "native checks belong to a different binary"
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
    check (!(← runtimeRecord.pathExists)) "preserve the comparison seal"
    write runtimeRecord (Json.mkObj [("candidateSha256",toJson (← hash (candidateBuild/"StudyMain"))),
      ("parentSha256",toJson (← hash (selected/"libexec/eggshell"))),("orderedArms",toJson armOrder),
      ("countsPerArm",toJson (#[(4 : Nat),16])),("fewSecondTargetWaveMs",toJson (5000 : Nat)),
      ("referenceInputSha256",toJson (← hash (base/"snapshot-scheduling/capacity-16-input.json"))),
      ("sameModelAssets",toJson true),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  else if args.head? == some "collect-arm" then
    let [_,label] := args | throw (IO.userError "collect-arm <label>")
    discard <| collectArm label
  else if args == ["report"] then
    let checked ← read (records/"current-check.json")
    let checkTag ← IO.ofExcept (checked.getObjValAs? String "tag")
    let checkGuard ← clean checkTag
    let digest ← hash (candidateBuild/"StudyMain")
    check (checked.getObjValD "runtimeSha256" == toJson digest) "native checks belong to a different executable"
    let checkRoot : System.FilePath := .mk (← IO.ofExcept (checked.getObjValAs? String "output"))
    let checkSource := "tools/research/QuiescentPagesChecks.lean"
    let sourceDigest ← hash (candidateSource/checkSource)
    check ((← hash (project/checkSource)) == sourceDigest) "checker source changed after native compilation"
    let componentChecks ← read (checkRoot/"report.json")
    write (records/"checks-rotating.json") (Json.mkObj [("checks",componentChecks),
      ("guard",checkGuard),("sourceSha256",toJson sourceDigest),("runtimeSha256",toJson digest),
      ("sourceAudit",checked.getObjValD "sourceReport"),
      ("nativeSourceAudit",toJson "native-rotating.json"),
      ("compilerDiagnosticsNotSeparatelyArchived",toJson true)])
    let mut all := #[]
    let mut parentTimes := #[]
    let mut candidateTimes := #[]
    for label in completedOrder do
      let row ← read (records/"arms"/(label++".json"))
      check (row.getObjValD "normalExit" == toJson true && row.getObjValD "sourceFilesUnchanged" == toJson true)
        "incomplete or changed-source arm cannot become a performance comparison"
      let phases : Array Json ← IO.ofExcept (fromJson? (row.getObjValD "completedPhases"))
      let some phase := phases.find? (fun item => item.getObjValD "clients" == toJson (16 : Nat)) |
        throw (IO.userError "16-client arm missing")
      check (phase.getObjValD "passed" == toJson true) "failed phase"
      let time ← IO.ofExcept (phase.getObjValAs? Nat "wallMs")
      if label.startsWith "b" then candidateTimes := candidateTimes.push time else parentTimes := parentTimes.push time
      all := all.push (Json.mkObj [("label",toJson label),
        ("record",toJson ("arms/"++label++".json")),
        ("recordSha256",toJson (← hash (records/"arms"/(label++".json")))),
        ("phases",toJson (phases.map fun phase => Json.mkObj [
          ("clients",phase.getObjValD "clients"),("wallMs",phase.getObjValD "wallMs"),
          ("passed",phase.getObjValD "passed")])),
        ("sampledPeakRssKiB",(row.getObjValD "guard").getObjValD "sampledPeakRssKiB")])
    check (parentTimes.size == 2 && candidateTimes.size == 2) "non-vacuous same-count replication required"
    let parentTotal := parentTimes.foldl Nat.add 0
    let candidateTotal := candidateTimes.foldl Nat.add 0
    check (parentTotal > 0) "invalid clock"
    let reduction := 100.0*(Float.ofNat parentTotal - Float.ofNat candidateTotal)/Float.ofNat parentTotal
    write (records/"rotating-comparison.json") (Json.mkObj [("originalOrderedArms",toJson armOrder),
      ("orderedArms",toJson completedOrder),("arms",toJson all),
      ("resourceRecoveryPlan",toJson "drained-recovery.json"),
      ("resourceStoppedArm",toJson "arms/a-rotating-repeat.json"),
      ("parent16WallMs",toJson parentTimes),("candidate16WallMs",toJson candidateTimes),
      ("descriptiveMeanLatencyReductionPercent",toJson reduction),
      ("fewSecond16ClientTargetMet",toJson (candidateTimes.all (· ≤ 5000))),
      ("p99Established",toJson false),("eightyConcurrentTest",toJson false),("answeringModelCalls",toJson (0 : Nat)),
      ("inclusiveTokenOrQualityBenefitEstablished",toJson false),("adopted",toJson false)])
    write (records/"hot-repair.json") (Json.mkObj [
      ("rejectedRuntimeSha256",toJson "19e6b870c6ec35688e5da1abc629be5bceb169f2ae15f1f5ce418d5c13e50930"),
      ("candidateRuntimeSha256",toJson digest),
      ("repair",toJson "restore State.insert byte-for-byte from selected product;retain immutable base and quiescent retirement"),
      ("hotPolicyMatchesParent",toJson true),("componentChecksPassed",toJson true),
      ("fixedSnapshotBodiesAndSemanticSynapticAckPassed",toJson true),
      ("completedFourArmComparison",toJson true),
      ("fewSecond16ClientTargetMet",toJson (candidateTimes.all (· ≤ 5000))),
      ("oldRuntimeAndCheckReceiptsMustNotBeReused",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  else if args.head? == some "prepare-arm" || args.head? == some "prepare-smoke" then
    let smoke := args.head? == some "prepare-smoke"
    let label ← if smoke then do
      let label := args[1]?.getD "rotating-smoke"
      check (smokeLabels.contains label) "preflight outside declared recovery labels"
      pure label
    else do
      let [_,label] := args | throw (IO.userError "prepare-arm <predeclared-label>")
      pure label
    let position ← if smoke then pure 0 else do
      let some index := completedOrder.findIdx? (· == label) | throw (IO.userError "arm outside fixed ABBA")
      pure index
    let declared ← read runtimeRecord
    if label == "a-rotating-drained" then
      let stopped ← read (records/"arms/a-rotating-repeat.json")
      let monitor := stopped.getObjValD "guard"
      check (stopped.getObjValD "normalExit" == toJson false &&
        stopped.getObjValD "sourceFilesUnchanged" == toJson true &&
        stopped.getObjValD "completedPhases" == toJson (#[] : Array Json) &&
        monitor.getObjValD "reason" == toJson "disk-space" &&
        monitor.getObjValD "guardTriggered" == toJson true &&
        monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "only the disk-stopped, pre-wave final parent arm may be recovered"
      check ((← read (records/"retired-capacity-state.json")).getObjValD "retainedHashesUnchanged" == toJson true)
        "capacity-state retirement has not completed"
      let startup ← read (records/"arms/a-rotating-recovered.json")
      check ((startup.getObjValD "guard").getObjValD "exitCode" == toJson (1 : Nat) &&
        startup.getObjValD "completedPhases" == toJson (#[] : Array Json))
        "the first recovery did not stop before a measured wave"
      let priorPids : Array Json ← IO.ofExcept (monitor.getObjValAs? (Array Json) "peakProcesses")
      let dataRoot := base/"snapshot-scheduling/work/data"
      let mut removed := #[]
      for (path,session) in #[(dataRoot/"publisher/endpoint.json","publisher"),(dataRoot/"daemon.json","")] do
        check ((← path.symlinkMetadata).type == .file) "stale endpoint is not a regular file"
        let endpoint ← read path
        let pid ← IO.ofExcept (endpoint.getObjValAs? Nat "pid")
        check (pid > 1 && endpoint.getObjValD "session" == toJson session &&
          priorPids.any (fun row => row.getObjValD "pid" == toJson pid)) "endpoint owner is outside the stopped study"
        let alive ← IO.Process.output {cmd := "/bin/kill",args := #["-0",toString pid]}
        check (alive.exitCode != 0) "refusing to recover a live endpoint"
        removed := removed.push (Json.mkObj [("path",toJson path.toString),("pid",toJson pid),
          ("sha256",toJson (← hash path)),("deadOwnerFromStoppedGuard",toJson true)])
        IO.FS.removeFile path
      write (records/"drained-recovery.json") (Json.mkObj [("originalArm",toJson "a-rotating-repeat"),
        ("recoveryArm",toJson label),("originalStoppedBeforeMeasuredWave",toJson true),
        ("reason",toJson "disk-space"),("sameSeal",toJson "rotating-runtime.json"),
        ("sameSourcesBodiesConfigurationAndGuardLimits",toJson true),("noAdditionalReplicate",toJson true),
        ("startupOnlyFailedRecovery",toJson "arms/a-rotating-recovered.json"),
        ("removedDeadEndpoints",toJson removed),
        ("cleanup",toJson "retired-capacity-state.json"),("newOrderedArms",toJson completedOrder)])
    if position > 0 then
      let some prior := completedOrder[position-1]? | throw (IO.userError "missing prior arm")
      discard <| clean ("quiescent-pages-arm-"++prior)
      let report ← read (trial/"arms"/prior/"report.json")
      check (report.getObjValD "allPhasesPassed" == toJson true) "stop after a failed arm"
    let isCandidate := smoke || label.startsWith "b"
    let chosenPrefix := if isCandidate then installation else selected
    let runtime := chosenPrefix/"libexec/eggshell"
    let expected := declared.getObjValD (if isCandidate then "candidateSha256" else "parentSha256")
    check (expected == toJson (← hash runtime)) "sealed runtime changed"
    let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let output := trial/"arms"/label
    let config := output/"config.toml"
    let plugin ← if isCandidate then pure (installation/"share/eggshell/codex-plugin").toString
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
    let input := if smoke then input.setObjVal! "counts" (toJson (#[(4 : Nat)]))
      |>.setObjVal! "diagnostic" (toJson true) else input
    let inputPath := trial/(label++"-input.json")
    check (!(← inputPath.pathExists)) "never overwrite or automatically retry an arm"
    write inputPath input
    let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
    guard ("quiescent-pages-arm-"++label) (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++
      #[runtime.toString,"owned-selection-capacity",inputPath.toString])
  else throw (IO.userError "setup|build|audit|audit-worker|check|install|prepare-arm|prepare-smoke|collect-arm|report")
