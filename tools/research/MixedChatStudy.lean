import tools.research.StudyLocal
import tools.research.SourceBlocks
import Std.Data.HashMap
open Lean StudyLocal
namespace MixedChatStudy
def productRoot := base/"practical-runtime/stable-storage-read"
def root := base/"practical-runtime/mixed-chat-lifecycle"
def records := project/"docs/practical-runtime/mixed-chat-lifecycle"
def clearRoot := base/"practical-runtime/context-clear"
def clearRecords := project/"docs/candidates/context-clear"
def buildTag := "mixed-chat-ready-build"
def runTag := "mixed-chat-ready-run"
def area := root/"run-ready"
def guard (tag : String) (args : Array String) : IO Unit := do
  StudyLocal.guard tag args
  let path := base/(tag++".guard-settings.json")
  write path ((← read path).setObjVal! "ownedPrefixes" (toJson #[root.toString,productRoot.toString,clearRoot.toString]))
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh mixed-chat experiment required"
  check ((← hash (productRoot/"build/StudyMain")) == "ed077918092c75ac1a2416b157cb37f1186a387314455febf3f010c03e5f5817") "fixed product changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  IO.FS.createDirAll (root/"tmp")
  discard <| command "/bin/cp" #["-cR",(productRoot/"source").toString,(root/"source").toString]
  for name in ["MixedChatChecks","SourceBlocks"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  copyLocalArtifacts (productRoot/"build") (root/"build")
  let settings := (← read (productRoot/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(productRoot/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (productRoot/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (productRoot/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (productRoot/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.MixedChatChecks")
    |>.setObjVal! "force" (toJson (#[] : Array String))
  write (root/"build-settings.json") settings
  write (root/"installation.json") (← read (productRoot/"installation.json"))
  write (records/"plan.json") (Json.mkObj [("runtimeSha256",toJson (← hash (productRoot/"build/StudyMain"))),
    ("projects",toJson (2 : Nat)),("ownersPerProject",toJson (4 : Nat)),
    ("writerSessions",toJson (4 : Nat)),("writerTurns",toJson (9 : Nat)),
    ("baselineReaders",toJson (4 : Nat)),("overlappingReaders",toJson (8 : Nat)),("finalReaders",toJson (10 : Nat)),
    ("maximumConcurrentClients",toJson (12 : Nat)),("interruptedWriters",toJson (2 : Nat)),
    ("existingAndFreshMixed",toJson true),("actualServiceRestart",toJson true),
    ("lateOldResultAfterProjectSwitch",toJson true),("duplicatePostAndStop",toJson true),
    ("compactAndClearResetVisibleContext",toJson true),("contextPreservedOnlyOnResume",toJson true),
    ("manualWarmCalls",toJson (0 : Nat)),("manualKeepCalls",toJson (0 : Nat)),
    ("generativeModelCalls",toJson (0 : Nat)),("actualCodexUiChats",toJson false),
    ("singleUnixUserAndHost",toJson true),("productChanged",toJson false),("adopted",toJson false)])
  guard "mixed-chat-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]
def sealFixture : IO Unit := do
  idle
  check (!(← (base/"mixed-chat-build.guard.json").pathExists)) "do not change a started native build"
  let mut rows := #[]
  for name in ["MixedChatChecks","SourceBlocks"] do
    let file := project/"tools/research"/(name++".lean")
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean")) (← IO.FS.readFile file)
    rows := rows.push (name,← hash file)
  write (records/"fixture-plan.json") (toJson rows)
def audit : IO Unit := do
  idle
  discard <| finished buildTag
  for args in [#["inspect",(root/"build").toString,(records/"ready-native.json").toString],
      #["common-sources",(productRoot/"build").toString,(root/"build").toString,(records/"ready-sources.json").toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
  let mut fixture := #[]
  for name in ["MixedChatChecks","SourceBlocks"] do
    let stamp ← read (root/"build"/("tools_research_"++name++".source"))
    let (text,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? stamp)
    check (text == (← IO.FS.readFile (project/"tools/research"/(name++".lean"))) && literals.isEmpty)
      "native fixture does not match its declared source"
    fixture := fixture.push (Json.mkObj [("module",toJson ("tools.research."++name)),
      ("sourceSha256",toJson (← hash (project/"tools/research"/(name++".lean"))))])
  write (records/"ready-fixture-sources.json") (toJson fixture)
def checkedBuild : IO Unit := do
  idle
  let first ← read (base/"mixed-chat-build.guard.json")
  check (first.getObjValD "state" == toJson "finished" && first.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "initial compiler stage is not terminal"
  write (records/"compiler-rejection.json") (Json.mkObj [("guard",first),
    ("source",toJson (← IO.FS.readFile (root/"source/tools/research/MixedChatChecks.lean"))),
    ("output",toJson (← IO.FS.readFile (root/"build/tools_research_MixedChatChecks-lean.stdout"))),
    ("actualHookCalls",toJson (0 : Nat)),("productChanged",toJson false)])
  IO.FS.writeFile (root/"source/tools/research/MixedChatChecks.lean")
    (← IO.FS.readFile (project/"tools/research/MixedChatChecks.lean"))
  guard "mixed-chat-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]
def repairParent : IO Unit := do
  idle
  let first ← read (base/"mixed-chat-run.guard.json")
  check (first.getObjValD "state" == toJson "finished" && first.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "rejected run is not terminal"
  check (!(← (root/"run/calls").pathExists)) "this fixture repair must precede every actual hook"
  write (records/"pre-hook-rejection.json") (Json.mkObj [("guard",first),
    ("failure",← read (root/"run/failure.json")),("stderr",toJson (← IO.FS.readFile (records/"flow.stderr"))),
    ("frontendStop",← read (root/"run/final-frontend-stop.json")),
    ("publisherStop",← read (root/"run/final-publisher-stop.json")),
    ("oldFixtureSource",toJson (← IO.FS.readFile (root/"source/tools/research/MixedChatChecks.lean"))),
    ("actualHookCalls",toJson (0 : Nat)),("productChanged",toJson false)])
  IO.FS.writeFile (root/"source/tools/research/MixedChatChecks.lean")
    (← IO.FS.readFile (project/"tools/research/MixedChatChecks.lean"))
  guard buildTag #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]
def runAt (area build : System.FilePath) (tag stem : String)
    (installationPath : System.FilePath := root/"installation.json") : IO Unit := do
  idle
  check ((← read (records/(stem++"-native.json"))).getObjValD "consistent" == toJson true &&
    (← read (records/(stem++"-sources.json"))).getObjValD "commonSourcesUnchanged" == toJson true) "native product/source audit required"
  let installation ← read installationPath
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let updates := #[("EGGSHELL_DATA_ROOT",some (area/"data").toString),("TMPDIR",some (root/"tmp").toString)]
  let environment := environment.filter (fun row => !updates.any (·.1 == row.1))++updates
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := environment.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  guard tag (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "mixed-chat",(records/(stem++"-flow.stdout")).toString,(records/(stem++"-flow.stderr")).toString,"/usr/bin/env"]++
    unset.flatMap (fun key => #["-u",key])++assigned++#[(build/"StudyMain").toString,"check",
      installationPath.toString,area.toString])
def run : IO Unit := runAt area (root/"build") runTag "ready"
def prepareInspection : IO Unit := do
  idle
  let failed ← read (base/(runTag++".guard.json"))
  check (failed.getObjValD "state" == toJson "finished" && failed.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "failed traffic is still live"
  write (records/"failed-run.json") (Json.mkObj [("guard",failed),("failure",← read (area/"failure.json")),
    ("frontendStop",← read (area/"final-frontend-stop.json")),("publisherStop",← read (area/"final-publisher-stop.json")),
    ("executedFixtureSource",toJson (← IO.FS.readFile (root/"source/tools/research/MixedChatChecks.lean"))),
    ("productChanged",toJson false)])
  discard <| command "/bin/cp" #["-cR",(root/"source").toString,(root/"inspection-source").toString]
  IO.FS.writeFile (root/"inspection-source/tools/research/MixedChatChecks.lean")
    (← IO.FS.readFile (project/"tools/research/MixedChatChecks.lean"))
  copyLocalArtifacts (root/"build") (root/"inspection-build")
  let settings := (← read (root/"build-settings.json"))
    |>.setObjVal! "project" (toJson (root/"inspection-source").toString)
    |>.setObjVal! "core" (toJson (root/"inspection-source").toString)
    |>.setObjVal! "output" (toJson (root/"inspection-build").toString)
  write (root/"inspection-build-settings.json") settings
  guard "mixed-chat-inspection-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"inspection-build-settings.json").toString]
def inspect : IO Unit := do
  idle
  discard <| finished "mixed-chat-inspection-build"
  for args in [#["inspect",(root/"inspection-build").toString,(records/"inspection-native.json").toString],
      #["common-sources",(productRoot/"build").toString,(root/"inspection-build").toString,
        (records/"inspection-sources.json").toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
  guard "mixed-chat-inspection" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(area/"data").toString,
    (root/"inspection-build/StudyMain").toString,"inspect",area.toString,(records/"postmortem.json").toString]
def buildNativeOracle : IO Unit := do
  idle
  discard <| finished "mixed-chat-inspection"
  let postmortem ← read (records/"postmortem.json")
  check (postmortem.getObjValD "originalsUnchanged" == toJson true &&
    postmortem.getObjValD "readOnly" == toJson true) "read-only cause inspection required"
  check (!(← (root/"native-oracle-source").pathExists)) "do not replace a started oracle build"
  discard <| command "/bin/cp" #["-cR",(root/"inspection-source").toString,(root/"native-oracle-source").toString]
  IO.FS.writeFile (root/"native-oracle-source/tools/research/MixedChatChecks.lean")
    (← IO.FS.readFile (project/"tools/research/MixedChatChecks.lean"))
  copyLocalArtifacts (root/"inspection-build") (root/"native-oracle-build")
  let settings := (← read (root/"inspection-build-settings.json"))
    |>.setObjVal! "project" (toJson (root/"native-oracle-source").toString)
    |>.setObjVal! "core" (toJson (root/"native-oracle-source").toString)
    |>.setObjVal! "output" (toJson (root/"native-oracle-build").toString)
  write (root/"native-oracle-build-settings.json") settings
  guard "mixed-chat-native-oracle-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"native-oracle-build-settings.json").toString]
def auditNativeOracle : IO Unit := do
  idle
  discard <| finished "mixed-chat-native-checked-build"
  for args in [#["inspect",(root/"native-oracle-build").toString,(records/"verified-native.json").toString],
      #["common-sources",(productRoot/"build").toString,(root/"native-oracle-build").toString,
        (records/"verified-sources.json").toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
  guard "mixed-chat-native-originals" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(area/"data").toString,
    (root/"native-oracle-build/StudyMain").toString,"inspect",area.toString,(records/"native-originals.json").toString]
def repairNativeOracle : IO Unit := do
  idle
  let prior ← read (base/"mixed-chat-native-oracle-build.guard.json")
  check (prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "initial oracle build is not terminal"
  write (records/"oracle-compiler-rejection.json") (Json.mkObj [("guard",prior),
    ("source",toJson (← IO.FS.readFile (root/"native-oracle-source/tools/research/MixedChatChecks.lean"))),
    ("output",toJson (← IO.FS.readFile (root/"native-oracle-build/tools_research_MixedChatChecks-lean.stdout"))),
    ("actualHookCalls",toJson (0 : Nat))])
  IO.FS.writeFile (root/"native-oracle-source/tools/research/MixedChatChecks.lean")
    (← IO.FS.readFile (project/"tools/research/MixedChatChecks.lean"))
  guard "mixed-chat-native-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"native-oracle-build-settings.json").toString]
def runVerified : IO Unit := do
  idle
  discard <| finished "mixed-chat-native-originals"
  let found ← read (records/"native-originals.json")
  check ((found.getObjValD "inventory").getObjValD "observations" == toJson (27 : Nat))
    "every original must independently match its immutable native receipt"
  runAt (root/"run-verified") (root/"native-oracle-build") "mixed-chat-verified-run" "verified"
def retain : IO Unit := do
  idle
  let monitor ← finished "context-clear-mixed-run"
  let mut fixture := #[]
  for name in ["MixedChatChecks","SourceBlocks"] do
    let stamp ← read (clearRoot/"checks-build"/("tools_research_"++name++".source"))
    let (source,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? stamp)
    check (source == (← IO.FS.readFile (project/"tools/research"/(name++".lean"))) && literals.isEmpty)
      "executed fixture source has drifted"
    fixture := fixture.push (name,← hash (project/"tools/research"/(name++".lean")))
  write (records/"clear-fixture-sources.json") (toJson fixture)
  let mut calls := #[]
  let mut failures := #[]
  IO.FS.createDirAll (records/"responses")
  for (label,area) in [("failed",area),("clear-failed",root/"run-verified"),("verified",root/"run-clear")] do
    let target := records/label
    IO.FS.createDirAll target
    for entry in ← area.readDir do
      if (← entry.path.symlinkMetadata).type == .file && entry.fileName.endsWith ".json" then
        write (target/entry.fileName) (← read entry.path)
    for receipt in ← (area/"data/receipts").readDir do
      if (← receipt.path.symlinkMetadata).type == .dir && (← (receipt.path/"failure.json").pathExists) then
        failures := failures.push (Json.mkObj [("trial",toJson label),("receipt",toJson receipt.fileName),
          ("failure",← read (receipt.path/"failure.json"))])
    for session in ← (area/"calls").readDir do
      if (← session.path.symlinkMetadata).type != .dir then continue
      for call in ← session.path.readDir do
        if (← call.path.symlinkMetadata).type != .dir || !(← (call.path/"registration.json").pathExists) then continue
        let digest ← hash (call.path/"stdout")
        let stdout := records/"responses"/(digest++".json")
        unless ← stdout.pathExists do IO.FS.writeBinFile stdout (← IO.FS.readBinFile (call.path/"stdout"))
        let timing ← read (call.path/"record.json")
        check (timing.getObjValD "stdoutSha256" == toJson digest) "actual mixed hook output changed"
        calls := calls.push (Json.mkObj [("trial",toJson label),("session",toJson session.fileName),
          ("label",toJson call.fileName),("request",← read (call.path/"stdin")),("timing",timing),
          ("stdout",toJson stdout.toString),("stderr",toJson (← IO.FS.readFile (call.path/"stderr"))),
          ("registration",← read (call.path/"registration.json"))])
  write (records/"registered-calls.json") (toJson calls)
  write (records/"failed-receipts.json") (toJson failures)
  check (failures.isEmpty) "a mixed lifecycle receipt failed"
  if !(← (records/"hook-callbacks.json").pathExists) then
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
      (project/"tools/research/AutomaticPublicationStudy.lean").toString,"audit-callbacks",
      (records/"registered-calls.json").toString,(records/"hook-callbacks.json").toString]
  let callbacks ← read (records/"hook-callbacks.json")
  check (callbacks.getObjValD "calls" == toJson calls.size &&
    callbacks.getObjValD "failedOrIncompleteCallbacks" == toJson (#[] : Array Json)) "retained callback audit differs"
  let mut visible : Std.HashMap String String := {}
  let mut queries := #[]
  let mut eligible := 0
  let mut delivered := 0
  let digest := fun (text : String) => do
    let path := records/"visible-audit.tmp"
    IO.FS.writeFile path text
    let result ← hash path
    IO.FS.removeFile path
    return result
  for (phase,label) in [("read-0","baseline-readers"),("read-1","mixed-wave"),("read-2","final-readers")] do
    let wave ← read (records/"verified"/(label++".json"))
    let rows ← IO.ofExcept ((wave.getObjValD (if phase == "read-1" then "readers" else "rows")).getArr?)
    for row in rows do
      let session : String ← IO.ofExcept (row.getObjValAs? _ "session")
      let some call := calls.find? (fun call => call.getObjValD "trial" == toJson "verified" &&
        call.getObjValD "session" == toJson session && call.getObjValD "label" == toJson (phase++"-prompt")) |
        throw (IO.userError "query has no retained actual callback")
      let stdout : String ← IO.ofExcept (call.getObjValAs? _ "stdout")
      let body := ((← read (.mk stdout)).getObjValD "hookSpecificOutput").getObjValD "additionalContext"
      let body : String ← match body with
        | .null => pure ""
        | .str text => pure text
        | _ => throw (IO.userError "additional context has a nontext value")
      let captured ← read (root/"run-clear/calls"/session/(phase++"-body.json"))
      let before := if row.getObjValD "freshContext" == toJson true then "" else visible[session]?.getD ""
      let after := before++"\n"++body
      check (captured.getObjValD "body" == toJson body &&
        captured.getObjValD "previousVisibleSha256" == toJson (← digest before) &&
        captured.getObjValD "visibleSha256" == toJson (← digest after) &&
        row.getObjValD "bodySha256" == toJson (← digest body)) "recorded visible context differs from actual returned bodies"
      let wanted ← IO.ofExcept ((row.getObjValD "required").getArr?)
      let mut missing := #[]
      for item in wanted do
        let text : String ← IO.ofExcept (item.getObjValAs? _ "text")
        let path : String ← IO.ofExcept (item.getObjValAs? _ "path")
        let fingerprint : String ← IO.ofExcept (item.getObjValAs? _ "fingerprint")
        if !Eggshell.Research.SourceBlocks.contains after path fingerprint text then missing := missing.push item
      check (missing.isEmpty && row.getObjValD "missing" == toJson missing) "independent mixed delivery audit failed"
      eligible := eligible+wanted.size
      delivered := delivered+wanted.size-missing.size
      visible := visible.insert session after
      queries := queries.push (row.setObjVal! "stdout" (toJson stdout) |>.setObjVal! "independentMissing" (toJson missing))
  check (queries.size == 22 && eligible == delivered) "all predeclared mixed queries required"
  write (records/"queries.json") (toJson queries)
  write (records/"flow.guard.json") monitor
  let final ← read (records/"verified/final-inventory.json")
  let summary := Json.mkObj [("projects",toJson (2 : Nat)),("queries",toJson queries.size),
    ("eligibleFields",toJson eligible),("deliveredFields",toJson delivered),
    ("nativeObservations",final.getObjValD "observations"),("timedObservations",final.getObjValD "timedObservations"),
    ("withoutVerifiedInterval",final.getObjValD "withoutVerifiedInterval"),
    ("answers",final.getObjValD "answers"),("peakRssKiB",monitor.getObjValD "sampledPeakRssKiB"),
    ("actualServiceRestart",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("productChanged",toJson true),("runtime",(← read (clearRoot/"installation.json")).getObjValD "runtime"),
    ("adopted",toJson false)]
  write (records/"summary.json") summary
  IO.println summary.compress
def prepareClear : IO Unit := do
  idle
  let failed ← read (base/"mixed-chat-verified-run.guard.json")
  check (failed.getObjValD "state" == toJson "finished" && failed.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "clear failure is not terminal"
  write (records/"clear-failure.json") (Json.mkObj [("guard",failed),
    ("failure",← read (root/"run-verified/failure.json")),("productChanged",toJson false)])
  check (!(← clearRoot.pathExists)) "fresh isolated clear candidate required"
  IO.FS.createDirAll clearRoot
  IO.FS.createDirAll clearRecords
  discard <| command "/bin/cp" #["-cR",(productRoot/"source").toString,(clearRoot/"source").toString]
  copyLocalArtifacts (productRoot/"build") (clearRoot/"build")
  let settings := (← read (productRoot/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (clearRoot/"source").toString)
    |>.setObjVal! "core" (toJson (clearRoot/"source").toString)
    |>.setObjVal! "output" (toJson (clearRoot/"build").toString)
    |>.setObjVal! "parents" (toJson #[(productRoot/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (productRoot/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (productRoot/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (productRoot/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.StudyMain")
    |>.setObjVal! "force" (toJson (#[] : Array String))
  write (clearRoot/"build-settings.json") settings
def buildClear : IO Unit := do
  idle
  let delta ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/Eggshell/PluginHooks.lean",
    "-L","b/Eggshell/PluginHooks.lean",(productRoot/"source/Eggshell/PluginHooks.lean").toString,
    (clearRoot/"source/Eggshell/PluginHooks.lean").toString]}
  check (delta.exitCode == 1) "clear fix absent"
  IO.FS.writeFile (clearRecords/"candidate.patch") delta.stdout
  guard "context-clear-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(clearRoot/"build-settings.json").toString]
def clearChecks : IO Unit := do
  idle
  discard <| finished "context-clear-build"
  for args in [#["inspect",(clearRoot/"build").toString,(clearRecords/"native.json").toString],
      #["compare-sources",(productRoot/"build").toString,(clearRoot/"build").toString,
        (clearRecords/"sources.json").toString,"Eggshell.PluginHooks"]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/TerminalIntentStudy.lean").toString,"install-at",clearRoot.toString,productRoot.toString,clearRecords.toString]
  for name in ["MixedChatChecks","SourceBlocks"] do
    IO.FS.writeFile (clearRoot/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  copyLocalArtifacts (clearRoot/"build") (clearRoot/"checks-build")
  let settings := (← read (clearRoot/"build-settings.json"))
    |>.setObjVal! "output" (toJson (clearRoot/"checks-build").toString)
    |>.setObjVal! "parents" (toJson #[(clearRoot/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (clearRoot/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (clearRoot/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (clearRoot/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.MixedChatChecks")
  write (clearRoot/"checks-settings.json") settings
  guard "context-clear-checks-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(clearRoot/"checks-settings.json").toString]
def runClear : IO Unit := do
  idle
  discard <| finished "context-clear-checks-build"
  for args in [#["inspect",(clearRoot/"checks-build").toString,(records/"clear-native.json").toString],
      #["common-sources",(clearRoot/"build").toString,(clearRoot/"checks-build").toString,
        (records/"clear-sources.json").toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
  runAt (root/"run-clear") (clearRoot/"checks-build") "context-clear-mixed-run" "clear" (clearRoot/"installation.json")
def clearProofs : IO Unit := do
  idle
  discard <| finished "context-clear-build"
  let names := ["clear_forgets_claims","clear_forgets_delivery_projection","clear_advances_epoch","clear_preserves_settings"]
  IO.FS.writeFile (clearRoot/"laws.lean") ("import Eggshell.PluginHooks\n"++String.join (names.map fun name =>
    "#print axioms Eggshell.Plugin."++name++"\n"))
  guard "context-clear-laws" #["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "clear-laws",(clearRecords/"laws.txt").toString,(clearRecords/"laws.stderr").toString,"/usr/bin/env",
    "LEAN_PATH="++(clearRoot/"build/lib").toString++":"++(compiler/"lib/lean").toString,
    (compiler/"bin/lean").toString,"-j1","-M2048",(clearRoot/"laws.lean").toString]
def retireChecks : IO Unit := do
  idle
  discard <| finished "context-clear-laws"
  discard <| finished "context-clear-mixed-run"
  check ((← read (records/"retired.json")).getObjValD "trialDirectoryRemoved" == toJson true)
    "retain and retire the traffic trial first"
  let targets := #[clearRoot/"checks-build",clearRoot/"helper-lib",clearRoot/"launcher.lean",clearRoot/"laws.lean",
    clearRoot/"source/tools/research/MixedChatChecks.lean",clearRoot/"source/tools/research/SourceBlocks.lean"]
  write (clearRecords/"retirement-plan.json") (toJson (targets.map (·.toString)))
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/AutomaticPublicationStudy.lean").toString,"retire-artifacts-at",clearRoot.toString,
    clearRecords.toString,(clearRecords/"retirement-plan.json").toString]
def retire : IO Unit := do
  idle
  discard <| finished "context-clear-laws"
  let proof ← IO.FS.readFile (clearRecords/"laws.txt")
  check (!proof.contains "sorryAx" && !proof.contains "Lean.ofReduceBool" && proof.contains "clear_forgets_claims")
    "clear proof audit is missing or uses unapproved axioms"
  check ((← read (records/"summary.json")).getObjValD "queries" == toJson (22 : Nat)) "retain all mixed queries first"
  let tags := ["mixed-chat-build","mixed-chat-checked-build","mixed-chat-run","mixed-chat-ready-build",runTag,
    "mixed-chat-inspection-build","mixed-chat-inspection","mixed-chat-native-oracle-build",
    "mixed-chat-native-checked-build","mixed-chat-native-originals","mixed-chat-verified-run",
    "context-clear-build","context-clear-checks-build","context-clear-mixed-run","context-clear-laws"]
  for tag in tags do
    let result ← read (base/(tag++".guard.json"))
    check (result.getObjValD "state" == toJson "finished" && result.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "an old mixed study stage is not terminal"
    write (records/(tag++".guard.json")) result
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/AutomaticPublicationStudy.lean").toString,"retire-trial-at",root.toString,
    records.toString,clearRoot.toString,"mixed-chat-native-originals","context-clear-mixed-run","context-clear-laws"]
  retireChecks
end MixedChatStudy
def main : List String → IO Unit
  | ["prepare"] => MixedChatStudy.prepare
  | ["seal-fixture"] => MixedChatStudy.sealFixture
  | ["checked-build"] => MixedChatStudy.checkedBuild
  | ["repair-parent"] => MixedChatStudy.repairParent
  | ["audit"] => MixedChatStudy.audit
  | ["run"] => MixedChatStudy.run
  | ["prepare-inspection"] => MixedChatStudy.prepareInspection
  | ["inspect"] => MixedChatStudy.inspect
  | ["build-native-oracle"] => MixedChatStudy.buildNativeOracle
  | ["audit-native-oracle"] => MixedChatStudy.auditNativeOracle
  | ["repair-native-oracle"] => MixedChatStudy.repairNativeOracle
  | ["run-verified"] => MixedChatStudy.runVerified
  | ["retain"] => MixedChatStudy.retain
  | ["prepare-clear"] => MixedChatStudy.prepareClear
  | ["build-clear"] => MixedChatStudy.buildClear
  | ["clear-checks"] => MixedChatStudy.clearChecks
  | ["run-clear"] => MixedChatStudy.runClear
  | ["clear-proofs"] => MixedChatStudy.clearProofs
  | ["retire"] => MixedChatStudy.retire
  | ["retire-checks"] => MixedChatStudy.retireChecks
  | _ => throw (IO.userError "MixedChatStudy prepare|audit|run")
