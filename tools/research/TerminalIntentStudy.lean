import tools.research.StudyLocal
open Lean StudyLocal
namespace TerminalIntentStudy
def practical := base/"practical-runtime"
def parent := practical/"terminal-capture"
def root := practical/"terminal-intent"
def records := project/"docs/candidates/terminal-intent"
def changes := #["Eggshell.PluginHooks","Eggshell.Daemon","Eggshell.SynapseLive",
  "Eggshell.HookFrontend","Eggshell.ContractAudit"]
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh terminal intent candidate required"
  check ((← hash (parent/"build/StudyMain")) ==
    "92328c0d61288d879b572cc37bbe47d7d021faa422ca009578283b147cd8f4a2") "parent runtime changed"
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
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("changedProductModules",toJson changes),("preserveObservedClockAndContext",toJson true),
    ("recoverJournalAndLifecycle",toJson true),("unverifiedClockCannotBecomeCurrent",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

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
    check (result.exitCode == 1) "declared source change absent"
    patch := patch++result.stdout
  IO.FS.writeFile (records/"candidate.patch") patch
  guard "terminal-intent-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]

def audit : IO Unit := do
  idle
  discard <| finished "terminal-intent-checked-build"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for args in [#["inspect",(root/"build").toString,(records/"native.json").toString],
      #["compare-sources",(parent/"build").toString,(root/"build").toString,
        (records/"sources.json").toString]++changes] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString]++args))

def correctBeforeBuild : IO Unit := do
  idle
  check (!(← (base/"terminal-intent-build.guard.json").pathExists)) "native compilation already started"
  write (records/"pre-build-correction.json") (Json.mkObj [
    ("reason",toJson "foreground must also find unresolved intents; never fall through to the current context"),
    ("previousPatch",toJson (← IO.FS.readFile (records/"candidate.patch"))),
    ("actualHookCalls",toJson (0 : Nat))])
  let mut patch := ""
  for name in changes do
    let relative := name.replace "." "/"++".lean"
    let result ← IO.Process.output {
      cmd := "/usr/bin/diff"
      args := #["-u","-L","a/"++relative,"-L","b/"++relative,
        (parent/"source"/relative).toString,(root/"source"/relative).toString]}
    check (result.exitCode == 1) "declared source change absent"
    patch := patch++result.stdout
  IO.FS.writeFile (records/"candidate.patch") patch

def retryBuild : IO Unit := do
  idle
  let prior ← read (base/"terminal-intent-build.guard.json")
  check (prior.getObjValD "state" == toJson "finished" &&
    prior.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "prior native compiler is not terminal"
  write (records/"build-attempt.json") (Json.mkObj [("guard",prior),
    ("patch",toJson (← IO.FS.readFile (records/"candidate.patch"))),
    ("compilerOutput",toJson (← IO.FS.readFile (root/"build/Eggshell_PluginHooks-lean.stdout"))),
    ("actualHookCalls",toJson (0 : Nat))])
  let mut patch := ""
  for name in changes do
    let relative := name.replace "." "/"++".lean"
    let result ← IO.Process.output {
      cmd := "/usr/bin/diff"
      args := #["-u","-L","a/"++relative,"-L","b/"++relative,
        (parent/"source"/relative).toString,(root/"source"/relative).toString]}
    check (result.exitCode == 1) "declared source change absent"
    patch := patch++result.stdout
  IO.FS.writeFile (records/"candidate.patch") patch
  guard "terminal-intent-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]

def reviewPatch : IO Unit := do
  idle
  check (!(← (base/"terminal-intent-checked-build.guard.json").pathExists)) "checked compilation already started"
  write (records/"patch-review.json") (Json.mkObj [
    ("reason",toJson "scope the missing-lifecycle error to terminal metadata; restore the unrelated acknowledgment path"),
    ("previousPatch",toJson (← IO.FS.readFile (records/"candidate.patch"))),
    ("actualHookCalls",toJson (0 : Nat))])
  let mut patch := ""
  for name in changes do
    let relative := name.replace "." "/"++".lean"
    let result ← IO.Process.output {
      cmd := "/usr/bin/diff"
      args := #["-u","-L","a/"++relative,"-L","b/"++relative,
        (parent/"source"/relative).toString,(root/"source"/relative).toString]}
    check (result.exitCode == 1) "declared source change absent"
    patch := patch++result.stdout
  IO.FS.writeFile (records/"candidate.patch") patch
def install : IO Unit := do
  idle
  check ((← read (records/"native.json")).getObjValD "consistent" == toJson true) "native closure must pass"
  check (!(← (root/"prefix").pathExists)) "fresh prefix required"
  discard <| command "/bin/cp" #["-cR",(parent/"prefix").toString,(root/"prefix").toString]
  IO.FS.removeFile (root/"prefix/libexec/eggshell")
  discard <| command "/bin/ln" #["-s",(root/"build/StudyMain").toString,(root/"prefix/libexec/eggshell").toString]
  discard <| command "/bin/cp" #["-cR",(root/"build/lib").toString,(root/"helper-lib").toString]
  let library := (root/"helper-lib").toString++":"++(compiler/"lib/lean").toString
  let compiled ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M2048","-DwarningAsError=true","-o",
      (root/"helper-lib/tools/research/StudyLaunchers.olean").toString,
      (project/"tools/research/StudyLaunchers.lean").toString]
    env := #[("LEAN_PATH",some library)]}
  check (compiled.exitCode == 0) (compiled.stdout++compiled.stderr)
  IO.FS.writeFile (root/"launcher.lean") "import tools.research.StudyLaunchers\ndef main := Eggshell.Research.StudyLaunchers.cliMain\n"
  let binding ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M2048","--run",(root/"launcher.lean").toString,"bind",
      (root/"prefix").toString,(parent/"prefix").toString,(records/"launcher-binding.json").toString]
    env := #[("LEAN_PATH",some library)]}
  check (binding.exitCode == 0) (binding.stdout++binding.stderr)
  let previous ← read (parent/"installation.json")
  let mut artifacts := #[]
  for artifact in ← IO.ofExcept (previous.getObjValAs? (Array Json) "pluginFiles") do
    let path : String ← IO.ofExcept (artifact.getObjValAs? _ "path")
    let old := (parent/"prefix").toString++"/"
    check (path.startsWith old) "plugin artifact escaped prefix"
    let destination := root/"prefix"/(path.drop old.length |>.toString)
    let digest ← hash destination
    unless ["plugins/eggshell/bin/egg","plugins/eggshell/bin/eggshelld"].any (destination.toString.endsWith ·) do
      check (toJson digest == artifact.getObjValD "sha256") "unrelated installed asset changed"
    artifacts := artifacts.push (artifact.setObjVal! "path" (toJson destination.toString) |>.setObjVal! "sha256" (toJson digest))
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (previous.getObjValD "environment"))
  let updates := #[("EGGSHELL_PREFIX",some (root/"prefix").toString),
    ("PLUGIN_ROOT",some (root/"prefix/plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (root/"run/data").toString),("TMPDIR",some (root/"tmp").toString)]
  let installation := previous
    |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (root/"prefix/libexec/eggshell").toString),
      ("sha256",toJson (← hash (root/"build/StudyMain")))])
    |>.setObjVal! "pluginRoot" (toJson (root/"prefix/plugins/eggshell").toString)
    |>.setObjVal! "pluginFiles" (toJson artifacts)
    |>.setObjVal! "environment" (toJson (env.filter (fun row => !updates.any (·.1 == row.1))++updates))
  IO.FS.createDirAll (root/"tmp")
  write (root/"installation.json") installation
  write (records/"installation.json") installation

def prepareChecks : IO Unit := do
  idle
  discard <| finished "terminal-intent-checked-build"
  IO.FS.writeFile (root/"source/tools/research/TerminalIntentChecks.lean")
    (← IO.FS.readFile (project/"tools/research/TerminalIntentChecks.lean"))
  copyLocalArtifacts (root/"build") (root/"checks-build")
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"checks-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.TerminalIntentChecks")
  write (root/"checks-build-settings.json") settings
  guard "terminal-intent-checks-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"checks-build-settings.json").toString]

def auditChecks : IO Unit := do
  idle
  discard <| finished "terminal-intent-checks-build"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for args in [#["inspect",(root/"checks-build").toString,(records/"checks-native.json").toString],
      #["subset-sources",(root/"build").toString,(root/"checks-build").toString,
        (records/"checks-sources.json").toString,"Main"]++changes] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString]++args))

def runCheck (fault : Bool) : IO Unit := do
  idle
  discard <| finished "terminal-intent-checks-build"
  let installation ← read (root/"installation.json")
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let label := if fault then "fault" else "boundaries"
  let updates := #[("EGGSHELL_DATA_ROOT",some (root/label/"data").toString)]
  let env := env.filter (fun row => !updates.any (·.1 == row.1))++updates
  let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := env.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  let args := if fault then #["fault",(root/"installation.json").toString,(root/label).toString]
    else #["boundaries",(root/label).toString]
  guard ("terminal-intent-"++label) (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    label,(records/(label++".stdout")).toString,(records/(label++".stderr")).toString,"/usr/bin/env"]++
    unset.flatMap (fun key => #["-u",key])++assigned++#[(root/"checks-build/StudyMain").toString]++args)

def retainChecks : IO Unit := do
  idle
  let boundary ← finished "terminal-intent-boundaries"
  let fault ← finished "terminal-intent-fault"
  for (folder,name) in [("boundaries","result"),("fault","result"),
      ("fault","captured-before-services-stop"),("fault","intent-before-restart"),
      ("fault","recovered-answer")] do
    let destination := if name == "result" then folder else name
    write (records/(destination++".json")) (← read (root/folder/(name++".json")))
  for name in ["fault-frontend-stop","fault-publisher-stop","final-frontend-stop","final-publisher-stop"] do
    write (records/(name++".json")) (← read (root/"fault"/(name++".json")))
  let mut calls := #[]
  for session in ← (root/"fault/calls").readDir do
    for call in ← session.path.readDir do
      if (← call.path.symlinkMetadata).type != .dir ||
          !(← (call.path/"registration.json").pathExists) then continue
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("request",← read (call.path/"stdin")),("stdout",toJson (← IO.FS.readFile (call.path/"stdout"))),
        ("stderr",toJson (← IO.FS.readFile (call.path/"stderr"))),
        ("timing",← read (call.path/"record.json")),("registration",← read (call.path/"registration.json"))])
  write (records/"registered-fault-calls.json") (toJson calls)
  write (records/"check-guards.json") (Json.mkObj [("boundaries",boundary),("fault",fault)])
def traffic : IO Unit := do
  idle
  discard <| finished "terminal-intent-fault"
  check (!(← (root/"run").pathExists) && !(← (records/"traffic-plan.json").pathExists)) "fresh mixed traffic required"
  let installation ← read (root/"installation.json")
  let frozen ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let seed ← read (practical/"cohort/study/seed-1/plan.json")
  let input := Json.mkObj [("installation",installation),("original",frozen.getObjValD "source"),
    ("originalFiles",frozen.getObjValD "sourceFiles"),("workspace",seed.getObjValD "workspace"),
    ("definitions",← read (practical/"interrupted-recovery/definitions.json")),("preparedReference",Json.null),
    ("activeReaders",toJson (3 : Nat)),("llvmReaders",toJson (3 : Nat)),("registered",toJson true),
    ("observeMaintenance",toJson false)]
  write (root/"input.json") input
  write (records/"traffic-plan.json") (Json.mkObj [("runtime",installation.getObjValD "runtime"),
    ("writers",toJson (4 : Nat)),("readers",toJson (6 : Nat)),("waves",toJson (3 : Nat)),
    ("sameFrozenOriginals",toJson true),("manualKeep",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := env.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  guard "terminal-intent-traffic" (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "mixed-traffic",(records/"traffic.stdout").toString,(records/"traffic.stderr").toString,"/usr/bin/env"]++
    unset.flatMap (fun key => #["-u",key])++assigned++#[(root/"build/StudyMain").toString,
      "shared-traffic",(root/"input.json").toString,(root/"run").toString])

def retainTraffic : IO Unit := do
  idle
  discard <| finished "terminal-intent-traffic"
  for action in ["retain-at","profiles-at"] do
    IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
      (project/"tools/research/SharedTrafficStudy.lean").toString,action,
      root.toString,records.toString,"terminal-intent-traffic"])
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/SharedTrafficStudy.lean").toString,"reuse-at",records.toString]
  let mut endings := #[]
  let mut warnings := #[]
  for session in ← (root/"run/calls").readDir do
    for call in ← session.path.readDir do
      if (← call.path.symlinkMetadata).type != .dir ||
          !(← (call.path/"registration.json").pathExists) then continue
      let stderr ← IO.FS.readFile (call.path/"stderr")
      unless stderr.isEmpty do warnings := warnings.push (Json.mkObj [("session",toJson session.fileName),
        ("label",toJson call.fileName),("stderr",toJson stderr)])
      unless ["stop","compact-start","post-compact","interrupt","end"].contains call.fileName do continue
      check ((← read (call.path/"stdout")) == Json.mkObj []) "terminal hook did not complete"
      endings := endings.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("timing",← read (call.path/"record.json")),("registration",← read (call.path/"registration.json"))])
  check (endings.size == 88) "all terminal responses required"
  write (records/"terminal-events.json") (toJson endings)
  write (records/"client-warnings.json") (toJson warnings)
  let result ← read (records/"result.json")
  let mut rows := #[]
  for row in ← IO.ofExcept (result.getObjValAs? (Array Json) "summary") do
    rows := rows.push (Json.mkObj [("wave",row.getObjValD "wave"),("elapsedMs",row.getObjValD "elapsedMs"),
      ("maxReaderMs",row.getObjValD "maxHookMs"),("semanticCompleted",row.getObjValD "semanticCompleted"),
      ("origins",(row.getObjValD "census").getObjValD "count"),("answers",row.getObjValD "automaticAnswers")])
  let compact := Json.mkObj [("waves",toJson rows),("terminalResponses",toJson endings.size),
    ("clientWarnings",toJson warnings.size),("serviceStderr",toJson (← IO.FS.readFile (records/"traffic.stderr"))),
    ("peakRssKiB",(result.getObjValD "guard").getObjValD "sampledPeakRssKiB"),
    ("adopted",toJson false)]
  write (records/"summary.json") compact
  IO.println compact.compress
def prepareReaders : IO Unit := do
  idle
  discard <| finished "terminal-intent-traffic"
  IO.FS.writeFile (root/"source/tools/research/TenReaders.lean")
    (← IO.FS.readFile (project/"tools/research/TenReaders.lean"))
  copyLocalArtifacts (root/"build") (root/"readers-build")
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"readers-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.TenReaders")
  write (root/"readers-build-settings.json") settings
  guard "terminal-intent-readers-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"readers-build-settings.json").toString]

def auditReaders : IO Unit := do
  idle
  discard <| finished "terminal-intent-readers-build"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for args in [#["inspect",(root/"readers-build").toString,(records/"readers-native.json").toString],
      #["subset-sources",(root/"build").toString,(root/"readers-build").toString,
        (records/"readers-sources.json").toString,"Main"]++changes] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString]++args))

def readers : IO Unit := do
  idle
  check ((← read (records/"readers-native.json")).getObjValD "consistent" == toJson true) "native reader closure required"
  let installation ← read (root/"installation.json")
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let updates := #[("EGGSHELL_DATA_ROOT",some (root/"ten-readers/data").toString)]
  let env := env.filter (fun row => !updates.any (·.1 == row.1))++updates
  let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := env.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  guard "terminal-intent-ten-readers" (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "ten-readers",(records/"ten-readers.stdout").toString,(records/"ten-readers.stderr").toString,"/usr/bin/env"]++
    unset.flatMap (fun key => #["-u",key])++assigned++#[(root/"readers-build/StudyMain").toString,
      (root/"input.json").toString,(root/"run/llvm.egg").toString,
      (records/"frozen-before-delivery.json").toString,(root/"ten-readers").toString])

def retainReaders : IO Unit := do
  idle
  let monitor ← finished "terminal-intent-ten-readers"
  let area := root/"ten-readers"
  let result ← read (area/"result.json")
  let waves ← IO.ofExcept (result.getObjValAs? (Array Json) "waves")
  check (waves.size == 3) "all predeclared readonly waves required"
  let mut queries := #[]
  let mut total := 0
  let mut available := 0
  let mut endings := #[]
  let mut warnings := #[]
  for wave in waves do
    let outcomes ← IO.ofExcept (wave.getObjValAs? (Array Json) "outcomes")
    check (outcomes.size == 10) "all ten native requests required"
    for item in ← IO.ofExcept (wave.getObjValAs? (Array Json) "audits") do
      for name in ["requiredDelivery","availableDelivery"] do
        let coverage := item.getObjValD name
        check (coverage.getObjValD "targetMet" == toJson true &&
          coverage.getObjValD "delivered" == coverage.getObjValD "eligible") "frozen evidence missing"
      total := total+(← IO.ofExcept ((item.getObjValD "requiredDelivery").getObjValAs? Nat "eligible"))
      available := available+(← IO.ofExcept ((item.getObjValD "availableDelivery").getObjValAs? Nat "eligible"))
    for outcome in outcomes do
      let topic : Nat ← IO.ofExcept (outcome.getObjValAs? _ "topic")
      let delivery := outcome.getObjValD "delivery"
      let session : String ← IO.ofExcept (delivery.getObjValAs? _ "session")
      let body : String ← IO.ofExcept (delivery.getObjValAs? _ "body")
      let call := area/"calls"/session/"prompt"
      let known := project/"docs/practical-runtime/recovery"/s!"topic-{topic}"
      check ((← hash (.mk body)) == (← hash (known/"body.txt")) &&
        (← hash (call/"stdout")) == (← hash (known/"stdout.json"))) "readonly delivery bytes changed"
      queries := queries.push (Json.mkObj [("wave",wave.getObjValD "wave"),("topic",toJson topic),
        ("delivery",delivery),("request",← read (call/"stdin")),("timing",← read (call/"record.json")),
        ("retainedBody",toJson (known/"body.txt").toString),("retainedStdout",toJson (known/"stdout.json").toString)])
      check ((← read (area/"calls"/session/"end/stdout")) == Json.mkObj []) "readonly end did not complete"
      endings := endings.push (Json.mkObj [("session",toJson session),
        ("timing",← read (area/"calls"/session/"end/record.json"))])
      for label in ["start","prompt","end"] do
        let stderr ← IO.FS.readFile (area/"calls"/session/label/"stderr")
        unless stderr.isEmpty do warnings := warnings.push (session,label,stderr)
      let privateFiles := area/"data/sessions"/session
      check ((← (privateFiles/"closed").readDir).size == 1) "readonly closure missing"
      for entry in ← (privateFiles/"closed").readDir do
        check ((← read entry.path).getObjValD "write" == Json.null) "readonly turn acquired a writer"
      check (!(← (privateFiles/"observed-files").pathExists)) "readonly source observation was retained"
      for name in ["deferred","checkpoints","terminal-intents"] do
        if ← (privateFiles/name).pathExists then
          check ((← (privateFiles/name).readDir).isEmpty) "readonly source work remained"
  write (records/"ten-readers-result.json") (Json.mkObj [("native",result),("guard",monitor),
    ("queries",toJson queries),("terminalEvents",toJson endings),("warnings",toJson warnings)])
  write (records/"ten-readers-stopped.json") (Json.mkObj [("frontend",← read (area/"frontend-stop.json")),
    ("publisher",← read (area/"publisher-stop.json"))])
  let summary := Json.mkObj [("elapsedMs",toJson (waves.map (·.getObjValD "elapsedMs"))),
    ("queries",toJson queries.size),("fullEvidenceDelivered",toJson total),
    ("partialInclusiveEvidenceDelivered",toJson available),("readonlyClosedTurns",toJson endings.size),
    ("clientWarnings",toJson warnings.size),("peakRssKiB",monitor.getObjValD "sampledPeakRssKiB"),
    ("allRetainedOutputsMatchKnownBytes",toJson true),("adopted",toJson false)]
  write (records/"ten-readers-summary.json") summary
  IO.println summary.compress
def proofAudit : IO Unit := do
  idle
  let law := root/"laws.lean"
  let names := ["final_capture_preserves_scope","final_capture_seals_answer",
    "final_capture_checks_identity","final_capture_named_turn","readonly_final_capture_has_no_source_job",
    "terminal_clock_keeps_observed_time","terminal_scope_keeps_target",
    "terminal_replay_does_not_advance_epoch","terminal_replay_keeps_first_answer"]
  IO.FS.writeFile law ("import Eggshell.PluginHooks\n"++String.join (names.map fun name =>
    "#print axioms Eggshell.Plugin."++name++"\n"))
  guard "terminal-intent-proof-audit" #["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "kernel-axioms",(records/"laws.txt").toString,(records/"laws.stderr").toString,"/usr/bin/env",
    "LEAN_PATH="++(root/"build/lib").toString++":"++(compiler/"lib/lean").toString,
    (compiler/"bin/lean").toString,"-j1","-M2048",law.toString]

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
  check (!(← (records/"retired.json").pathExists)) "preserve retirement record"
  for name in ["fault.json","summary.json","ten-readers-summary.json","laws.txt"] do
    check (← (records/name).pathExists) "retain complete validation evidence first"
  for name in ["result.json","ten-readers-result.json"] do
    for row in ← IO.ofExcept ((← read (records/name)).getObjValAs? (Array Json) "queries") do
      let body : String ← IO.ofExcept (row.getObjValAs? _ "retainedBody")
      let output : String ← IO.ofExcept (row.getObjValAs? _ "retainedStdout")
      check ((row.getObjValD "delivery").getObjValD "bodySha256" == toJson (← hash (.mk body)))
        "retained delivery changed"
      check ((row.getObjValD "timing").getObjValD "stdoutSha256" == toJson (← hash (.mk output)))
        "retained response changed"
  let mut guards := []
  for tag in ["terminal-intent-build","terminal-intent-checked-build","terminal-intent-checks-build",
      "terminal-intent-boundaries","terminal-intent-fault","terminal-intent-traffic",
      "terminal-intent-readers-build","terminal-intent-ten-readers","terminal-intent-proof-audit"] do
    let value ← read (base/(tag++".guard.json"))
    check (value.getObjValD "state" == toJson "finished" &&
      value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "candidate guard is still live"
    guards := guards++[(tag,value)]
  write (records/"guards.json") (Json.mkObj guards)
  let targets := #[root/"run",root/"fault",root/"boundaries",root/"ten-readers",root/"checks-build",
    root/"readers-build",root/"helper-lib",root/"tmp",root/"launcher.lean",root/"laws.lean"]
  let retiredPath := fun (text : String) => targets.any fun target =>
    text == target.toString || text.startsWith (target.toString++"/")
  let builds := #[root/"build",parent/"build",practical/"readonly-save/build",practical/"block-seek/build",
    practical/"build",practical/"independent-maintenance/build",practical/"coordinated-warm/build",
    base/"canonical-decoder-runtime/build"]
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
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any fun line => targets.any (fun target => line.contains target.toString))
    "ended artifact still belongs to a process"
  let mut removed := (0,0)
  for path in targets do
    if !(← path.pathExists) then continue
    let next ← remove path
    removed := (removed.1+next.1,removed.2+next.2)
  for (path,digest) in protectedRuntimes do check ((← hash path) == digest) "protected runtime changed"
  for (name,digest) in protectedFiles do check ((← hash (System.FilePath.mk source/name)) == digest) "original changed during retirement"
  let mut outputs := #[]
  for entry in ← records.readDir do
    if !(entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr") then continue
    let bytes ← IO.FS.readBinFile entry.path
    outputs := outputs.push (Json.mkObj [("name",toJson entry.fileName),("bytes",toJson bytes.size),
      ("sha256",toJson (← hash entry.path)),("retained",toJson (!bytes.isEmpty))])
    if bytes.isEmpty then IO.FS.removeFile entry.path
  write (records/"service-output.json") (toJson outputs)
  write (records/"retired.json") (Json.mkObj [("files",toJson removed.1),("logicalBytes",toJson removed.2),
    ("archiveCreated",toJson false),("sourceAndRuntimeHashesUnchanged",toJson true),
    ("nativeInputsAndInterfacesOutsideRetiredTargets",toJson true),("candidateProductRetained",toJson true)])
end TerminalIntentStudy
def main : List String → IO Unit
  | ["prepare"] => TerminalIntentStudy.prepare
  | ["seal"] => TerminalIntentStudy.sealPatch
  | ["audit"] => TerminalIntentStudy.audit
  | ["correct-before-build"] => TerminalIntentStudy.correctBeforeBuild
  | ["retry-build"] => TerminalIntentStudy.retryBuild
  | ["review-patch"] => TerminalIntentStudy.reviewPatch
  | ["install"] => TerminalIntentStudy.install
  | ["prepare-checks"] => TerminalIntentStudy.prepareChecks
  | ["audit-checks"] => TerminalIntentStudy.auditChecks
  | ["boundaries"] => TerminalIntentStudy.runCheck false
  | ["fault"] => TerminalIntentStudy.runCheck true
  | ["retain-checks"] => TerminalIntentStudy.retainChecks
  | ["traffic"] => TerminalIntentStudy.traffic
  | ["retain-traffic"] => TerminalIntentStudy.retainTraffic
  | ["prepare-readers"] => TerminalIntentStudy.prepareReaders
  | ["audit-readers"] => TerminalIntentStudy.auditReaders
  | ["readers"] => TerminalIntentStudy.readers
  | ["retain-readers"] => TerminalIntentStudy.retainReaders
  | ["proof-audit"] => TerminalIntentStudy.proofAudit
  | ["retire"] => TerminalIntentStudy.retire
  | _ => throw (IO.userError "TerminalIntentStudy prepare|seal|audit")
