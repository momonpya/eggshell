import tools.research.StudyLocal
open Lean StudyLocal
namespace ReadonlySaveStudy
def practical := base/"practical-runtime"
def parent := practical/"block-seek"
def root := practical/"readonly-save"
def records := project/"docs/candidates/readonly-save"
def parentSha := "73376c698d715f79e825109751c54f6dd3096f976821f13645e73e5fed23fd7c"
def changes := #["Eggshell.PluginModel","Eggshell.PluginHooks","Eggshell.Worker"]

def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh isolated save candidate required"
  check ((← hash (parent/"build/StudyMain")) == parentSha) "parent runtime changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  copyLocalArtifacts (parent/"build") (root/"build")
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "force" (toJson (#[] : Array String))
  write (root/"build-settings.json") settings
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson parentSha),
    ("changedProductModules",toJson changes),("capturedWriteTargetControlsPersistence",toJson true),
    ("freshnessAndNativeReceiptsUnchanged",toJson true),
    ("readonlyQueriesPerWave",toJson (10 : Nat)),("readonlyWaves",toJson (3 : Nat)),
    ("mixedWriters",toJson (4 : Nat)),("mixedReaders",toJson (6 : Nat)),("mixedWaves",toJson (3 : Nat)),
    ("sameFrozenEvidence",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def sealPatch : IO Unit := do
  idle
  check (!(← (records/"candidate.patch").pathExists)) "preserve sealed candidate"
  let mut patch := ""
  for name in changes do
    let relative := name.replace "." "/"++".lean"
    let result ← IO.Process.output {
      cmd := "/usr/bin/diff"
      args := #["-u","-L","a/"++relative,"-L","b/"++relative,
        (parent/"source"/relative).toString,(root/"source"/relative).toString]}
    check (result.exitCode == 1) "declared source must contain a real change"
    patch := patch++result.stdout
  IO.FS.writeFile (records/"candidate.patch") patch
  guard "readonly-save-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]

def audit : IO Unit := do
  idle
  discard <| finished "readonly-save-build"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for args in [#["inspect",(root/"build").toString,(records/"native.json").toString],
      #["compare-sources",(parent/"build").toString,(root/"build").toString,
        (records/"sources.json").toString]++changes] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString]++args))

def prepareInstallation : IO Unit := do
  idle
  check ((← read (records/"native.json")).getObjValD "consistent" == toJson true) "native closure must pass"
  check (!(← (root/"prefix").pathExists)) "fresh installation required"
  discard <| command "/bin/cp" #["-cR",(parent/"prefix").toString,(root/"prefix").toString]
  IO.FS.removeFile (root/"prefix/libexec/eggshell")
  discard <| command "/bin/ln" #["-s",(root/"build/StudyMain").toString,(root/"prefix/libexec/eggshell").toString]
  discard <| command "/bin/cp" #["-cR",(root/"build/lib").toString,(root/"helper-lib").toString]
  let library := (root/"helper-lib").toString++":"++(compiler/"lib/lean").toString
  let output ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M2048","-DwarningAsError=true","-o",
      (root/"helper-lib/tools/research/StudyLaunchers.olean").toString,
      (project/"tools/research/StudyLaunchers.lean").toString]
    env := #[("LEAN_PATH",some library)]}
  check (output.exitCode == 0) (output.stdout++output.stderr)
  IO.FS.writeFile (root/"launcher.lean") "import tools.research.StudyLaunchers\ndef main := Eggshell.Research.StudyLaunchers.cliMain\n"
  let result ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M2048","--run",(root/"launcher.lean").toString,"bind",
      (root/"prefix").toString,(parent/"prefix").toString,(records/"launcher-binding.json").toString]
    env := #[("LEAN_PATH",some library)]}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  let previous ← read (parent/"installation.json")
  let mut files := #[]
  for file in ← IO.ofExcept (previous.getObjValAs? (Array Json) "pluginFiles") do
    let path : String ← IO.ofExcept (file.getObjValAs? _ "path")
    let originalPrefix := (parent/"prefix").toString++"/"
    check (path.startsWith originalPrefix) "plugin artifact escaped inherited installation"
    let relative := path.drop originalPrefix.length |>.toString
    let destination := root/"prefix"/relative
    let digest ← hash destination
    unless ["plugins/eggshell/bin/egg","plugins/eggshell/bin/eggshelld"].contains relative do
      check (toJson digest == file.getObjValD "sha256") "unrelated installed artifact changed"
    files := files.push (file.setObjVal! "path" (toJson destination.toString) |>.setObjVal! "sha256" (toJson digest))
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (previous.getObjValD "environment"))
  let updates := #[("EGGSHELL_PREFIX",some (root/"prefix").toString),
    ("PLUGIN_ROOT",some (root/"prefix/plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (root/"run/data").toString),("TMPDIR",some (root/"tmp").toString)]
  let installation := previous
    |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (root/"prefix/libexec/eggshell").toString),
      ("sha256",toJson (← hash (root/"build/StudyMain")))])
    |>.setObjVal! "pluginRoot" (toJson (root/"prefix/plugins/eggshell").toString)
    |>.setObjVal! "pluginFiles" (toJson files)
    |>.setObjVal! "environment" (toJson (env.filter (fun row => !updates.any (·.1 == row.1))++updates))
  IO.FS.createDirAll (root/"tmp")
  write (root/"installation.json") installation
  write (records/"installation.json") installation

def traffic : IO Unit := do
  idle
  check (!(← (root/"run").pathExists)) "preserve previous native traffic"
  let installation ← read (root/"installation.json")
  let frozen ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let seed ← read (practical/"cohort/study/seed-1/plan.json")
  let input := Json.mkObj [("installation",installation),("original",frozen.getObjValD "source"),
    ("originalFiles",frozen.getObjValD "sourceFiles"),("workspace",seed.getObjValD "workspace"),
    ("definitions",← read (practical/"interrupted-recovery/definitions.json")),("preparedReference",Json.null),
    ("activeReaders",toJson (3 : Nat)),("llvmReaders",toJson (3 : Nat)),("registered",toJson true),
    ("observeMaintenance",toJson false)]
  write (root/"input.json") input
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := env.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  let redirect := "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\""
  guard "readonly-save-traffic" (#["/bin/sh","-c",redirect,"readonly-save-traffic",
    (records/"traffic.stdout").toString,(records/"traffic.stderr").toString,"/usr/bin/env"] ++
    unset.flatMap (fun key => #["-u",key]) ++ assigned ++ #[(root/"build/StudyMain").toString,
      "shared-traffic",(root/"input.json").toString,(root/"run").toString])

def prepareController (reader : Bool) : IO Unit := do
  idle
  discard <| finished "readonly-save-build"
  let name := if reader then "TenReaders" else "ReadonlySaveChecks"
  let area := if reader then "readers-build" else "checks-build"
  IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
    (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  copyLocalArtifacts (root/"build") (root/area)
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/area).toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson ("tools.research."++name))
  write (root/(area++"-settings.json")) settings
  guard ("readonly-save-"++area) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/(area++"-settings.json")).toString]

def auditController (reader : Bool) : IO Unit := do
  idle
  let area := if reader then "readers-build" else "checks-build"
  discard <| finished (if reader then "readonly-save-readers-build" else "readonly-save-checks-compile4")
  let evidence := if reader then area else "checks-compile4"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for args in [#["inspect",(root/area).toString,(records/(evidence++"-native.json")).toString],
      #["subset-sources",(root/"build").toString,(root/area).toString,
        (records/(evidence++"-sources.json")).toString,"Main","Eggshell.PluginHooks","Eggshell.Worker",
        "Eggshell.PluginModel","Eggshell.SourceEvidence"]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString]++args))

def retryChecks (previous next : String) : IO Unit := do
  idle
  let failed ← read (base/(previous++".guard.json"))
  check (failed.getObjValD "state" == toJson "finished" &&
    failed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "prior compiler is not terminal"
  let source := root/"source/tools/research/ReadonlySaveChecks.lean"
  let retained := records/(previous++"-attempt.json")
  check (!(← retained.pathExists)) "preserve native control failure"
  write retained (Json.mkObj [("guard",failed),
    ("oldControlSource",toJson (← IO.FS.readFile source)),
    ("compilerOutput",toJson (← IO.FS.readFile (root/"checks-build/tools_research_ReadonlySaveChecks-lean.stdout"))),
    ("actualHookCalls",toJson (0 : Nat)),("productSourceChanged",toJson false)])
  IO.FS.writeFile source (← IO.FS.readFile (project/"tools/research/ReadonlySaveChecks.lean"))
  guard next #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"checks-build-settings.json").toString]

def inspectControl : IO Unit := do
  idle
  let failed ← read (base/"readonly-save-checks.guard.json")
  check (failed.getObjValD "state" == toJson "finished" &&
    failed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "control process is not terminal"
  write (records/"checks-failed.guard.json") failed
  write (records/"checks-failed-publisher-stop.json") (← read (root/"checks/publisher-stop.json"))
  IO.FS.writeFile (records/"checks-failed-source.lean")
    (← IO.FS.readFile (root/"source/tools/research/ReadonlySaveChecks.lean"))
  guard "readonly-save-control-inspect" #["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "inspect-original",(records/"checks-source.json").toString,(records/"checks-inspect.stderr").toString,
    (root/"build/StudyMain").toString,"source-graph",(root/"checks/old-target.egg").toString]

def inspectStoredControl : IO Unit := do
  idle
  let stopped ← read (base/"readonly-save-control-inspect.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "prior inspection is not terminal"
  write (records/"checks-inspect-failed.guard.json") stopped
  guard "readonly-save-control-inspect2" #["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "inspect-stored-original",(records/"checks-graph.json").toString,(records/"checks-graph.stderr").toString,
    (root/"build/StudyMain").toString,"inspect-graph",(root/"checks/old-target.egg").toString]

def runController (reader : Bool) : IO Unit := do
  idle
  auditController reader
  let installation ← read (root/"installation.json")
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let data := root/(if reader then "ten-readers/data" else "checks2/data")
  let updates := #[("EGGSHELL_DATA_ROOT",some data.toString)]
  let env := env.filter (fun row => !updates.any (·.1 == row.1))++updates
  let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := env.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  let label := if reader then "ten-readers" else "checks2"
  let args ← if reader then do
      let prior ← read (base/"readonly-save-traffic.guard.json")
      check (prior.getObjValD "state" == toJson "finished" &&
        prior.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "mixed traffic remains live"
      check ((← (records/"mixed-failed.json").pathExists) &&
        (← (root/"run/llvm-warm.json").pathExists)) "preserve mixed failure and source warm before independent readers"
      pure #[(root/"readers-build/StudyMain").toString,(root/"input.json").toString,
        (root/"run/llvm.egg").toString,(records/"frozen-before-delivery.json").toString,
        (root/"ten-readers").toString]
    else pure #[(root/"checks-build/StudyMain").toString,"checks",(root/"checks2").toString]
  let redirect := "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\""
  guard ("readonly-save-"++label) (#["/bin/sh","-c",redirect,label,
    (records/(label++".stdout")).toString,(records/(label++".stderr")).toString,"/usr/bin/env"]++
    unset.flatMap (fun key => #["-u",key])++assigned++args)

def retainTraffic : IO Unit := do
  idle
  discard <| finished "readonly-save-traffic"
  for action in ["retain-at","profiles-at"] do
    IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
      (project/"tools/research/SharedTrafficStudy.lean").toString,action,
      root.toString,records.toString,"readonly-save-traffic"])
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/SharedTrafficStudy.lean").toString,"reuse-at",records.toString]

def retainChecks : IO Unit := do
  idle
  write (records/"checks.guard.json") (← finished "readonly-save-checks2")
  write (records/"checks.json") (← read (root/"checks2/result.json"))
  write (records/"checks-publisher-stop.json") (← read (root/"checks2/publisher-stop.json"))
  let law := root/"laws.lean"
  IO.FS.writeFile law "import Eggshell.PluginModel\n#print axioms Eggshell.Plugin.readonly_checkpoint_has_no_effect\n#print axioms Eggshell.Plugin.readonly_save_needs_no_receipt_loading\n#print axioms Eggshell.Plugin.readonly_observer_has_no_effect\n"
  let result ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768",law.toString]
    env := #[("LEAN_PATH",some ((root/"build/lib").toString++":"++(compiler/"lib/lean").toString))]}
  IO.FS.writeFile (records/"laws.txt") (result.stdout++result.stderr)
  check (result.exitCode == 0) "readonly effect laws failed"

def retainFailure : IO Unit := do
  idle
  let monitor ← read (base/"readonly-save-traffic.guard.json")
  check (monitor.getObjValD "state" == toJson "finished" &&
    monitor.getObjValD "exitCode" == toJson (1 : Nat) &&
    monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "failed mixed traffic must be terminal"
  let area := root/"run"
  write (records/"frozen-before-delivery.json") (← read (area/"frozen-before-delivery.json"))
  let mut calls := #[]
  for session in ← (area/"calls").readDir do
    for call in ← session.path.readDir do
      if (← call.path.symlinkMetadata).type != .dir then continue
      if !(← (call.path/"registration.json").pathExists) then continue
      let response ← IO.FS.readFile (call.path/"stdout")
      let digest ← hash (call.path/"stdout")
      let stored := records/"mixed-responses"/(digest++".json")
      unless ← stored.pathExists do
        IO.FS.createDirAll stored.parent.get!
        IO.FS.writeFile stored response
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("request",← read (call.path/"stdin")),("timing",← read (call.path/"record.json")),
        ("stdout",toJson stored.toString),("stdoutSha256",toJson digest),
        ("stderr",toJson (← IO.FS.readFile (call.path/"stderr"))),
        ("registration",← read (call.path/"registration.json"))])
  let mut stops := #[]
  for entry in ← (area/"data/receipts").readDir do
    let request := entry.path/"request.json"
    if !(← request.pathExists) then continue
    let metadata ← read request
    if (metadata.getObjValD "data").getObjValD "event" != toJson "Stop" then continue
    let mut stages := #[]
    for file in ← entry.path.readDir do
      if file.fileName.endsWith ".json" then stages := stages.push (file.fileName,← read file.path)
    stops := stops.push (Json.mkObj [("receipt",toJson entry.fileName),("stages",toJson stages)])
  write (records/"mixed-failed.json") (Json.mkObj [("guard",monitor),
    ("failure",← read (area/"failure.json")),("outcomes",← read (area/"wave-1-outcomes.json")),
    ("calls",toJson calls),("stopReceipts",toJson stops),
    ("frontendStop",← read (area/"frontend-stop.json")),("publisherStop",← read (area/"publisher-stop.json")),
    ("llvmWarm",← read (area/"llvm-warm.json")),("activeWarm",← read (area/"baseline-warm.json")),
    ("stderr",toJson (← IO.FS.readFile (records/"traffic.stderr"))),
    ("passedSeries",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  IO.println (toJson stops).pretty

def retainReaders : IO Unit := do
  idle
  let monitor ← finished "readonly-save-ten-readers"
  let area := root/"ten-readers"
  let result ← read (area/"result.json")
  let waves ← IO.ofExcept (result.getObjValAs? (Array Json) "waves")
  check (waves.size == 3) "all predeclared readonly waves required"
  let mut queries := #[]
  let mut terminal := #[]
  let mut warnings := #[]
  let mut full := 0
  let mut available := 0
  let mut readonlyClosed := 0
  let mut observedDirectories := 0
  let mut queuedEntries := 0
  for wave in waves do
    let outcomes ← IO.ofExcept (wave.getObjValAs? (Array Json) "outcomes")
    check (outcomes.size == 10) "all ten simultaneous native requests required"
    for item in ← IO.ofExcept (wave.getObjValAs? (Array Json) "audits") do
      for name in ["requiredDelivery","availableDelivery"] do
        let coverage := item.getObjValD name
        check (coverage.getObjValD "targetMet" == toJson true &&
          coverage.getObjValD "delivered" == coverage.getObjValD "eligible") "frozen original evidence missing"
      full := full + (← IO.ofExcept ((item.getObjValD "requiredDelivery").getObjValAs? Nat "eligible"))
      available := available + (← IO.ofExcept ((item.getObjValD "availableDelivery").getObjValAs? Nat "eligible"))
    for outcome in outcomes do
      let topic : Nat ← IO.ofExcept (outcome.getObjValAs? _ "topic")
      let delivery := outcome.getObjValD "delivery"
      let session : String ← IO.ofExcept (delivery.getObjValAs? _ "session")
      let body : String ← IO.ofExcept (delivery.getObjValAs? _ "body")
      let call := area/"calls"/session/"prompt"
      let known := project/"docs/practical-runtime/recovery"/s!"topic-{topic}"
      let mut artifacts := #[]
      for (actual,existing,suffix) in [((System.FilePath.mk body),known/"body.txt","txt"),
          (call/"stdout",known/"stdout.json","json")] do
        let digest ← hash actual
        let same := (← hash existing) == digest
        let retained := if same then existing else records/"bodies"/(digest++"."++suffix)
        if !(← retained.pathExists) then
          IO.FS.createDirAll retained.parent.get!
          IO.FS.writeBinFile retained (← IO.FS.readBinFile actual)
        artifacts := artifacts.push (Json.mkObj [("retained",toJson retained.toString),
          ("sha256",toJson digest),("sameKnownBytes",toJson same)])
      queries := queries.push (Json.mkObj [("wave",wave.getObjValD "wave"),("topic",toJson topic),
        ("delivery",delivery),("request",← read (call/"stdin")),("timing",← read (call/"record.json")),
        ("artifacts",toJson artifacts)])
      let ending := area/"calls"/session/"end"
      check ((← read (ending/"stdout")) == Json.mkObj []) "readonly SessionEnd was not valid empty JSON"
      terminal := terminal.push (Json.mkObj [("session",toJson session),("timing",← read (ending/"record.json")),
        ("registration",← read (ending/"registration.json"))])
      for label in ["start","prompt","end"] do
        let text ← IO.FS.readFile (area/"calls"/session/label/"stderr")
        unless text.isEmpty do warnings := warnings.push (Json.mkObj [("session",toJson session),
          ("label",toJson label),("stderr",toJson text)])
      let privateFiles := area/"data/sessions"/session
      for entry in ← (privateFiles/"closed").readDir do
        let closed ← read entry.path
        check (closed.getObjValD "write" == Json.null) "readonly concurrency acquired a source writer target"
        readonlyClosed := readonlyClosed+1
      if ← (privateFiles/"observed-files").pathExists then observedDirectories := observedDirectories+1
      for name in ["deferred","checkpoints"] do
        if ← (privateFiles/name).pathExists then
          queuedEntries := queuedEntries + (← (privateFiles/name).readDir).size
  check (queries.size == 30 && terminal.size == 30 && readonlyClosed == 30 &&
    observedDirectories == 0 && queuedEntries == 0) "readonly source work was not fully elided"
  write (records/"ten-readers-result.json") (Json.mkObj [("native",result),("guard",monitor),
    ("queries",toJson queries),("terminalEvents",toJson terminal),("clientWarnings",toJson warnings),
    ("sameUnixUserAndHost",toJson true),("newPrivateStateWithoutWarm",toJson true),
    ("paidModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  write (records/"ten-readers-stopped.json") (Json.mkObj [("frontend",← read (area/"frontend-stop.json")),
    ("publisher",← read (area/"publisher-stop.json"))])
  let summary := Json.mkObj [("elapsedMs",toJson (waves.map (·.getObjValD "elapsedMs"))),
    ("queries",toJson queries.size),("fullEvidenceDelivered",toJson full),
    ("partialInclusiveEvidenceDelivered",toJson available),("readonlyClosedTurns",toJson readonlyClosed),
    ("observationDirectories",toJson observedDirectories),("sourceQueueEntries",toJson queuedEntries),
    ("clientWarnings",toJson warnings.size),("peakRssKiB",monitor.getObjValD "sampledPeakRssKiB"),
    ("allRetainedOutputsMatchKnownBytes",toJson (queries.all fun query =>
      ((query.getObjValD "artifacts").getArr?.toOption.getD #[]).all fun artifact =>
        artifact.getObjValD "sameKnownBytes" == toJson true)),("adopted",toJson false)]
  write (records/"ten-readers-summary.json") summary
  IO.println summary.compress

partial def files (path : System.FilePath) : IO (Array System.FilePath) := do
  if (← path.symlinkMetadata).type != .dir then return #[path]
  let mut result := #[]
  for entry in ← path.readDir do result := result++(← files entry.path)
  return result

partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,metadata.byteSize.toNat)
  let mut total := (1,0)
  for entry in ← path.readDir do
    let next ← remove entry.path
    total := (total.1+next.1,total.2+next.2)
  IO.FS.removeDir path
  return total

def retire : IO Unit := do
  idle
  discard <| finished "readonly-save-ten-readers"
  check (!(← (records/"retired.json").pathExists)) "preserve retirement record"
  let summaries ← read (records/"ten-readers-summary.json")
  check (summaries.getObjValD "queries" == toJson (30 : Nat) &&
    summaries.getObjValD "sourceQueueEntries" == toJson (0 : Nat)) "complete readonly evidence required"
  let mixed ← read (records/"mixed-failed.json")
  check (mixed.getObjValD "passedSeries" == toJson false) "preserve failed mixed traffic"
  let mut guards := []
  for tag in ["readonly-save-build","readonly-save-checks-build","readonly-save-checks-compile2",
      "readonly-save-checks-compile3","readonly-save-checks-compile4","readonly-save-checks",
      "readonly-save-control-inspect","readonly-save-control-inspect2","readonly-save-checks2",
      "readonly-save-traffic","readonly-save-readers-build","readonly-save-ten-readers",
      "readonly-save-audit-build","readonly-save-audit"] do
    let value ← read (base/(tag++".guard.json"))
    check (value.getObjValD "state" == toJson "finished" &&
      value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "a candidate guard is not drained"
    guards := guards++[(tag,value)]
  write (records/"guards.json") (Json.mkObj guards)
  let targets := #[root/"run",root/"ten-readers",root/"checks",root/"checks2",root/"checks-build",
    root/"readers-build",root/"audit-build",root/"helper-lib",root/"tmp",root/"launcher.lean",root/"laws.lean"]
  let retiredPath := fun (text : String) => targets.any fun target =>
    text == target.toString || text.startsWith (target.toString++"/")
  let builds := #[root/"build",parent/"build",practical/"build",practical/"independent-maintenance/build",
    practical/"coordinated-warm/build",base/"canonical-decoder-runtime/build"]
  let protectedRuntimes ← builds.mapM fun directory => do pure (directory/"StudyMain",← hash (directory/"StudyMain"))
  for directory in builds do
    for line in (← IO.FS.readFile (directory/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      if path.isAbsolute then check (!retiredPath (← IO.FS.realPath path).toString) "native input belongs to ended trial"
    for path in ← files (directory/"lib") do
      if (← path.symlinkMetadata).type == .symlink then
        check (!retiredPath (← IO.FS.realPath path).toString) "current interface belongs to ended trial"
  check (!retiredPath (← IO.FS.realPath (root/"prefix/share/eggshell/minilm")).toString) "model belongs to ended trial"
  let original ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let source : String ← IO.ofExcept (original.getObjValAs? _ "source")
  let protectedFiles : Array (String × String) ← IO.ofExcept (original.getObjValAs? _ "sourceFiles")
  for (name,digest) in protectedFiles do check ((← hash (System.FilePath.mk source/name)) == digest) "original source changed"
  let queries ← IO.ofExcept ((← read (records/"ten-readers-result.json")).getObjValAs? (Array Json) "queries")
  for query in queries do
    for artifact in ← IO.ofExcept (query.getObjValAs? (Array Json) "artifacts") do
      let name : String ← IO.ofExcept (artifact.getObjValAs? _ "retained")
      check (artifact.getObjValD "sha256" == toJson (← hash (.mk name))) "retained actual output changed"
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any fun line => targets.any (line.contains ·.toString)) "ended artifact still belongs to a live process"
  let mut removed := (0,0)
  for path in targets do
    if !(← path.pathExists) then continue
    let part ← remove path
    removed := (removed.1+part.1,removed.2+part.2)
  let calls ← IO.ofExcept (mixed.getObjValAs? (Array Json) "calls")
  for entry in ← (records/"mixed-responses").readDir do
    unless calls.any (fun call => call.getObjValD "stdout" == toJson entry.path.toString) do
      let part ← remove entry.path
      removed := (removed.1+part.1,removed.2+part.2)
  for (path,digest) in protectedRuntimes do check ((← hash path) == digest) "protected runtime changed"
  for (name,digest) in protectedFiles do check ((← hash (System.FilePath.mk source/name)) == digest) "original source changed during retirement"
  write (records/"retired.json") (Json.mkObj [("files",toJson removed.1),("logicalBytes",toJson removed.2),
    ("archiveCreated",toJson false),("sourceAndRuntimeHashesUnchanged",toJson true),
    ("nativeInputsAndInterfacesOutsideRetiredTargets",toJson true),("candidateProductRetained",toJson true)])

def prepareSaveAudit : IO Unit := do
  idle
  discard <| finished "readonly-save-ten-readers"
  IO.FS.writeFile (root/"source/tools/research/MixedSaveAudit.lean")
    (← IO.FS.readFile (project/"tools/research/MixedSaveAudit.lean"))
  copyLocalArtifacts (root/"readers-build") (root/"audit-build")
  let settings := (← read (root/"readers-build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"audit-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"readers-build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"readers-build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"readers-build/tools_research_TenReaders.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"readers-build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.MixedSaveAudit")
  write (root/"audit-build-settings.json") settings
  let session := root/"run/data/sessions/traffic-1-1-5"
  let mut queued := #[]
  for name in ["checkpoints","deferred"] do
    if ← (session/name).pathExists then
      for entry in ← (session/name).readDir do
        if entry.fileName.endsWith ".json" then
          queued := queued.push (Json.mkObj [("file",toJson entry.path.toString),("pending",← read entry.path)])
  write (records/"failed-stop-private-state.json") (Json.mkObj [("pending",← read (session/"pending.json")),
    ("state",← read (session/"state.json")),("queued",toJson queued)])
  guard "readonly-save-audit-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"audit-build-settings.json").toString]

def runSaveAudit : IO Unit := do
  idle
  discard <| finished "readonly-save-audit-build"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for args in [#["inspect",(root/"audit-build").toString,(records/"audit-native.json").toString],
      #["subset-sources",(root/"build").toString,(root/"audit-build").toString,
        (records/"audit-sources.json").toString,"Main","Eggshell.PluginHooks","Eggshell.Worker",
        "Eggshell.PluginModel","Eggshell.SourceEvidence"]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString]++args))
  guard "readonly-save-audit" #[(root/"audit-build/StudyMain").toString,(root/"run").toString,
    (records/"mixed-source-audit.json").toString]

def tidyOutputs : IO Unit := do
  idle
  check ((← (records/"retired.json").pathExists) &&
    !(← (records/"service-output.json").pathExists)) "retire ended state before output cleanup"
  let mut output := #[]
  for entry in ← records.readDir do
    unless entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" ||
        entry.fileName == "checks-source.json" do continue
    let bytes ← IO.FS.readBinFile entry.path
    let digest ← hash entry.path
    output := output.push (Json.mkObj [("name",toJson entry.fileName),("bytes",toJson bytes.size),
      ("sha256",toJson digest),("retained",toJson (!bytes.isEmpty))])
    if bytes.isEmpty then IO.FS.removeFile entry.path
  write (records/"service-output.json") (toJson output)

end ReadonlySaveStudy
def main : List String → IO Unit
  | ["prepare"] => ReadonlySaveStudy.prepare
  | ["seal"] => ReadonlySaveStudy.sealPatch
  | ["audit"] => ReadonlySaveStudy.audit
  | ["install"] => ReadonlySaveStudy.prepareInstallation
  | ["traffic"] => ReadonlySaveStudy.traffic
  | ["prepare-checks"] => ReadonlySaveStudy.prepareController false
  | ["retry-checks",previous,next] => ReadonlySaveStudy.retryChecks previous next
  | ["inspect-control"] => ReadonlySaveStudy.inspectControl
  | ["inspect-stored-control"] => ReadonlySaveStudy.inspectStoredControl
  | ["prepare-readers"] => ReadonlySaveStudy.prepareController true
  | ["checks"] => ReadonlySaveStudy.runController false
  | ["readers"] => ReadonlySaveStudy.runController true
  | ["retain-checks"] => ReadonlySaveStudy.retainChecks
  | ["retain-failure"] => ReadonlySaveStudy.retainFailure
  | ["retain-traffic"] => ReadonlySaveStudy.retainTraffic
  | ["retain-readers"] => ReadonlySaveStudy.retainReaders
  | ["retire"] => ReadonlySaveStudy.retire
  | ["prepare-save-audit"] => ReadonlySaveStudy.prepareSaveAudit
  | ["save-audit"] => ReadonlySaveStudy.runSaveAudit
  | ["tidy-outputs"] => ReadonlySaveStudy.tidyOutputs
  | _ => throw (IO.userError "ReadonlySaveStudy prepare|seal|audit|install|traffic|prepare-checks|prepare-readers|checks|readers|retain-checks|retain-traffic")
