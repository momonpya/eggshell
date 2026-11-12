import tools.research.StudyLocal
open Lean StudyLocal
namespace ProducerWindowStudy
def parent := base/"practical-runtime/source-snapshot"
def root := base/"practical-runtime/producer-windows"
def records := project/"docs/candidates/producer-windows"
def patchFile := project/"tools/research/producer-windows/candidate.patch"
def changed := #["tools/research/PreparedSourceView.lean","Eggshell/CanonicalSourceCache.lean"]
def capturePatch : IO Unit := do
  idle
  let mut patch := ""
  for relative in changed do
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/"++relative,
      "-L","b/"++relative,(parent/"source"/relative).toString,(root/"source"/relative).toString]}
    check (diff.exitCode == 1) "producer-window source change missing"
    patch := patch++diff.stdout
  IO.FS.writeFile patchFile patch
  let plan ← read (records/"plan.json")
  write (records/"plan.json") (plan
    |>.setObjVal! "contextInvariant" (toJson "every selected original row retains its published producer basis, including graph-derived groups and federated views")
    |>.setObjVal! "preparation" (toJson "window membership and per-row basis are prepared on publication; retrieval only combines these immutable identities")
    |>.setObjVal! "proofs" (toJson #["all original rows remain eligible","producer rows and bounded records retained","basis index names a containing unit","original authority unchanged"]))
def settings : IO Unit := do
  let configuration := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
  write (root/"settings.json") configuration
  guard "producer-windows-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh producer-window candidate required"
  check ((← hash (parent/"build/StudyMain")) == "720e64d9daf08a8c8f5e716b8cb877bc378253ba51fb43738dc33e05c1b6c534")
    "fixed real-corpus parent changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  copyLocalArtifacts (parent/"build") (root/"build")
  IO.FS.writeFile (root/"source/Eggshell/ProducerWindows.lean")
    (← IO.FS.readFile (project/"tools/research/producer-windows/ProducerWindows.lean"))
  discard <| command "/usr/bin/patch" #["-p1","-d",(root/"source").toString,"-i",patchFile.toString]
  write (records/"plan.json") (Json.mkObj [("parent",toJson (← hash (parent/"build/StudyMain"))),
    ("hypothesis",toJson "preserve producer-window and original-record membership rather than fit independently credited row fragments"),
    ("unchanged",toJson #["source snapshot","questions","MiniLM","rank/weight expressions","actual byte costs","120000-character budget","authority rules"]),
    ("newObservableAssociation",toJson "carry the producer's actual window-to-original-row membership through publication and selection"),
    ("comparison",toJson "same frozen 4/7/5 evidence units as the real LLVM parent; six first-delivery audits; no answering models"),
    ("stopRule",toJson "no fitted window widths, owner reservations, weight or budget adjustments after a failed candidate"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  settings
def checkedBuild : IO Unit := do
  idle
  let stopped ← read (base/"producer-windows-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" == toJson (1 : Nat)) "only correct the stopped producer-window elaboration"
  write (records/"build-rejection.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"build/Eggshell_ProducerWindows-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"build/Eggshell_ProducerWindows-lean.stderr"))),
    ("databaseOrModelStarted",toJson false)])
  IO.FS.writeFile (root/"source/Eggshell/ProducerWindows.lean")
    (← IO.FS.readFile (project/"tools/research/producer-windows/ProducerWindows.lean"))
  guard "producer-windows-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def basisBuild : IO Unit := do
  idle
  let stopped ← read (base/"producer-windows-checked-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" == toJson (1 : Nat)) "only correct the stopped dependent basis elaboration"
  write (records/"basis-build-rejection.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"build/Eggshell_ProducerWindows-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"build/Eggshell_ProducerWindows-lean.stderr"))),
    ("databaseOrModelStarted",toJson false)])
  IO.FS.writeFile (root/"source/Eggshell/ProducerWindows.lean")
    (← IO.FS.readFile (project/"tools/research/producer-windows/ProducerWindows.lean"))
  guard "producer-windows-basis-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def retryBuild (previous next : String) : IO Unit := do
  idle
  check ([previous,next].all fun tag => tag.startsWith "producer-windows-" &&
    tag.toList.all (fun char => char.isAlphanum || char == '-')) "isolated producer build tags required"
  let stopped ← read (base/(previous++".guard.json"))
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" == toJson (1 : Nat)) "only correct a stopped build"
  let receipt := records/(previous++"-rejection.json")
  check (!(← receipt.pathExists)) "preserve previous build refusal"
  let mut elaboration : Array (String × String) := #[]
  for stem in ["Eggshell_ProducerWindows","tools_research_PreparedSourceView"] do
    for stream in ["stdout","stderr"] do
      let file := root/"build"/(stem++"-lean."++stream)
      if ← file.pathExists then elaboration := elaboration.push (file.fileName.get!,← IO.FS.readFile file)
  write receipt (Json.mkObj [("guard",stopped),
    ("elaboration",toJson elaboration),
    ("databaseOrModelStarted",toJson false)])
  IO.FS.writeFile (root/"source/Eggshell/ProducerWindows.lean")
    (← IO.FS.readFile (project/"tools/research/producer-windows/ProducerWindows.lean"))
  guard next #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def audit (arguments : Array String) : IO Unit := do
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
def installObserverSources : IO Unit := do
  for name in ["Audit","Checks"] do
    IO.FS.writeFile (root/"source/tools/research"/("ProducerWindow"++name++".lean"))
      (← IO.FS.readFile (project/"tools/research/producer-windows"/(name++".lean")))
  let observer ← IO.FS.readFile (project/"tools/research/LLVMProjectChecks.lean")
  let observer := observer.replace "import Main\n" "import Main\nimport tools.research.ProducerWindowChecks\n"
    |>.replace "  | [\"bind\",directory,inherited]" ("  | [\"checks\",output] => do ProducerWindowChecks.run (.mk output); return 0\n"++
      "  | [\"bind\",directory,inherited]")
  IO.FS.writeFile (root/"source/tools/research/LLVMProjectChecks.lean") observer
def prepareObserver : IO Unit := do
  idle
  write (records/"build.guard.json") (← finished "producer-windows-layout-build")
  capturePatch
  audit #["inspect",(root/"build").toString,(records/"native.json").toString]
  audit #["compare-sources",(parent/"build").toString,(root/"build").toString,(records/"sources.json").toString,
    "tools.research.PreparedSourceView","Eggshell.CanonicalSourceCache","+Eggshell.ProducerWindows"]
  installObserverSources
  copyLocalArtifacts (root/"build") (root/"llvm-build")
  let configuration := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"llvm-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.LLVMProjectChecks")
  write (root/"llvm-settings.json") configuration
  guard "producer-windows-observer-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"llvm-settings.json").toString]
def observerRetry (previous next : String) : IO Unit := do
  idle
  check ([previous,next].all fun tag => tag.startsWith "producer-windows-" &&
    tag.toList.all (fun char => char.isAlphanum || char == '-')) "isolated observer tags required"
  let stopped ← read (base/(previous++".guard.json"))
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" == toJson (1 : Nat)) "only correct the stopped test observer"
  let receipt := records/(previous++"-rejection.json")
  check (!(← receipt.pathExists)) "preserve previous observer refusal"
  let mut elaboration : Array (String × String) := #[]
  for stem in ["tools_research_ProducerWindowChecks","tools_research_LLVMProjectChecks"] do
    for stream in ["stdout","stderr"] do
      let file := root/"llvm-build"/(stem++"-lean."++stream)
      if ← file.pathExists then elaboration := elaboration.push (file.fileName.get!,← IO.FS.readFile file)
  write receipt (Json.mkObj [("guard",stopped),
    ("elaboration",toJson elaboration),
    ("productChanged",toJson false),("databaseOrModelStarted",toJson false)])
  installObserverSources
  guard next #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"llvm-settings.json").toString]
def checks : IO Unit := do
  idle
  write (records/"observer-build.guard.json") (← finished "producer-windows-native-observer-build")
  audit #["inspect",(root/"llvm-build").toString,(records/"observer-native.json").toString]
  audit #["common-sources",(root/"build").toString,(root/"llvm-build").toString,(records/"observer-sources.json").toString]
  let stdout ← IO.FS.readFile (root/"llvm-build/tools_research_ProducerWindowAudit-lean.stdout")
  let stderr ← IO.FS.readFile (root/"llvm-build/tools_research_ProducerWindowAudit-lean.stderr")
  check (!stdout.contains "sorryAx" && !stdout.contains "ofReduceBool" && stderr.isEmpty)
    "producer-window proof audit is not clean"
  write (records/"proofs.json") (Json.mkObj [("stdout",toJson stdout),("stderr",toJson stderr),
    ("sourceSha256",toJson (← hash (root/"source/tools/research/ProducerWindowAudit.lean"))),
    ("standardAxiomsOnly",toJson true),("actualPublicationAndWindowConnectionsChecked",toJson true)])
  guard "producer-windows-checks" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    (root/"llvm-build/StudyMain").toString,"checks",(records/"checks.json").toString]
def capture : IO Unit := do
  idle
  write (records/"checks.guard.json") (← finished "producer-windows-checks")
  check ((← read (records/"checks.json")).getObjValD "allPassed" == toJson true) "native producer checks failed"
  let target := root/"prefix"
  check (!(← target.pathExists) && !(← (records/"llvm").pathExists)) "fresh candidate installation required"
  discard <| command "/bin/cp" #["-cR",(parent/"prefix").toString,target.toString]
  let executable := target/"libexec/eggshell"
  check ((← executable.symlinkMetadata).type == .symlink) "inherited backend must be a symlink"
  IO.FS.removeFile executable
  discard <| command "/bin/ln" #["-s",(root/"build/StudyMain").toString,executable.toString]
  discard <| command (root/"llvm-build/StudyMain").toString #["bind",target.toString,(parent/"prefix").toString]
  let prior ← read (parent/"installation.json")
  let oldFiles : Array Json ← IO.ofExcept (prior.getObjValAs? _ "pluginFiles")
  let files ← oldFiles.mapM fun file => do
    let path ← IO.ofExcept (file.getObjValAs? String "path")
    check (path.startsWith ((parent/"prefix").toString++"/")) "plugin artifact escaped inherited installation"
    let path := path.replace (parent/"prefix").toString target.toString
    return Json.mkObj [("path",toJson path),("sha256",toJson (← hash (.mk path)))]
  let environment : Array (String × Option String) ← IO.ofExcept (prior.getObjValAs? _ "environment")
  let updates := #[("EGGSHELL_PREFIX",some target.toString),
    ("PLUGIN_ROOT",some (target/"plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (root/"llvm/client").toString),("TMPDIR",some (root/"llvm/tmp").toString)]
  let environment := environment.filter (fun field => !updates.any (·.1 == field.1))++updates
  let installation := prior
    |>.setObjVal! "runtime" (Json.mkObj [("path",toJson executable.toString),("sha256",toJson (← hash executable))])
    |>.setObjVal! "pluginRoot" (toJson (target/"plugins/eggshell").toString)
    |>.setObjVal! "pluginFiles" (toJson files)
    |>.setObjVal! "environment" (toJson environment)
    |>.setObjVal! "handoffChars" (toJson (120000 : Nat))
  write (root/"installation.json") installation
  IO.FS.createDirAll (records/"llvm")
  let before ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let plan := Json.mkObj [("installation",installation),("original",before.getObjValD "source"),
    ("originalFiles",before.getObjValD "sourceFiles"),
    ("definitions",toJson (base/"practical-runtime/interrupted-recovery/definitions.json").toString),
    ("workspace",toJson "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"),
    ("root",toJson (root/"llvm").toString),("records",toJson (records/"llvm").toString)]
  write (root/"llvm-plan.json") plan
  write (records/"llvm/plan.json") (plan.setObjVal! "adopted" (toJson false)
    |>.setObjVal! "answeringModelCalls" (toJson (0 : Nat)))
  guard "producer-windows-capture" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_PREFIX="++target.toString,"EGGSHELL_DATA_ROOT="++(root/"llvm/client").toString,
    (root/"llvm-build/StudyMain").toString,"prepare",(root/"llvm-plan.json").toString]
def run : IO Unit := do
  idle
  write (records/"llvm/capture.guard.json") (← finished "producer-windows-capture")
  let before ← read (project/"docs/candidates/source-snapshot/llvm/before-delivery.json")
  let after ← read (records/"llvm/before-delivery.json")
  let oldTopics ← IO.ofExcept ((before.getObjValD "topics").getArr?)
  let newTopics ← IO.ofExcept ((after.getObjValD "topics").getArr?)
  let frozenSame := oldTopics.map (·.getObjValD "frozen") == newTopics.map (·.getObjValD "frozen")
  check (frozenSame && before.getObjValD "capturedHead" == after.getObjValD "capturedHead" &&
    before.getObjValD "sourceFiles" == after.getObjValD "sourceFiles")
    "candidate corpus or independently frozen evidence differs from the parent"
  write (records/"llvm/fixed-inputs.json") (Json.mkObj [("sameFrozenEvidence",toJson true),
    ("sameNativeHeadAndBytes",toJson true),("sameCharacterBudget",toJson (120000 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("acceptedSeed",toJson false)])
  let installation := (← read (root/"llvm-plan.json")).getObjValD "installation"
  let environment : Array (String × Option String) ← IO.ofExcept (installation.getObjValAs? _ "environment")
  let unsets := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let values := environment.filterMap fun (key,value) => value.map (fun item => key++"="++item)
  guard "producer-windows-llvm" (#["/usr/bin/env"]++unsets.flatMap (fun key => #["-u",key])++values++
    #[(root/"llvm-build/StudyMain").toString,"run",(root/"llvm-plan.json").toString])
partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let counts ← remove entry.path
    total := (total.1+counts.1,total.2+counts.2)
  IO.FS.removeDir path
  return total
def retire : IO Unit := do
  idle
  let completed ← finished "producer-windows-llvm"
  let result ← read (records/"llvm/result.json")
  check (result.getObjValD "allSixReachTarget" == toJson false) "only retire the failed isolated candidate"
  let queries ← IO.ofExcept (result.getObjValAs? (Array Json) "queries")
  check (queries.size == 6) "preserve all six predeclared audits"
  let mut calls := #[]
  let mut bodies := #[]
  let mut eligible := 0
  let mut delivered := 0
  for query in queries do
    let session ← IO.ofExcept (query.getObjValAs? String "session")
    let pass ← IO.ofExcept (query.getObjValAs? Nat "pass")
    let topic ← IO.ofExcept (query.getObjValAs? Nat "topic")
    let delivery := (query.getObjValD "assessment").getObjValD "availableDelivery"
    eligible := eligible+(← IO.ofExcept (delivery.getObjValAs? Nat "eligible"))
    delivered := delivered+(← IO.ofExcept (delivery.getObjValAs? Nat "delivered"))
    let file := records/"llvm"/s!"pass-{pass}-topic-{topic}.txt"
    let bytes ← IO.FS.readBinFile file
    let some body := String.fromUTF8? bytes | throw (IO.userError "actual body is not UTF-8")
    check (toJson (← hash file) == query.getObjValD "bodySha256") "actual body differs from its native receipt"
    let encoded := toJson body
    let decoded : String ← IO.ofExcept (fromJson? encoded)
    check (decoded.toUTF8 == bytes) "body serialization changed original bytes"
    bodies := bodies.push (Json.mkObj [("pass",toJson pass),("topic",toJson topic),
      ("sha256",query.getObjValD "bodySha256"),("body",encoded)])
    for label in ["start","prompt","stop"] do
      let directory := root/"llvm/calls"/session/label
      calls := calls.push (Json.mkObj [("session",toJson session),("event",toJson label),
        ("record",← read (directory/"record.json")),("registration",← read (directory/"registration.json")),
        ("input",toJson (← IO.FS.readFile (directory/"stdin"))),
        ("stdout",toJson (← IO.FS.readFile (directory/"stdout"))),
        ("stderr",toJson (← IO.FS.readFile (directory/"stderr")))])
  check (eligible == 32 && delivered == 0 && calls.size == 18) "preserve the actual negative result"
  write (records/"llvm/callbacks.json") (toJson calls)
  write (records/"llvm/bodies.json") (toJson bodies)
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "producer-windows-" && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "candidate stage remains live"
      guards := guards.push (entry.fileName,value)
  write (records/"guards.json") (toJson guards)
  write (records/"observer-executed-source.json") (← read (root/"llvm-build/tools_research_LLVMProjectChecks.source"))
  let warm ← read (records/"llvm/warm.json")
  check (warm.getObjValD "exitCode" == toJson (0 : Nat) && warm.getObjValD "stderr" == toJson "")
    "warm did not finish cleanly"
  let plan ← read (root/"llvm-plan.json")
  let original : System.FilePath := .mk (← IO.ofExcept (plan.getObjValAs? String "original"))
  let originalFiles : Array (String × String) ← IO.ofExcept (plan.getObjValAs? _ "originalFiles")
  let before ← read (records/"llvm/before-delivery.json")
  let capturedFiles : Array (String × String) ← IO.ofExcept (before.getObjValAs? _ "sourceFiles")
  for (name,expected) in originalFiles do check ((← hash (original/name)) == expected) "protected original changed"
  for (name,expected) in capturedFiles do
    check ((← hash (root/"llvm/llvm.egg/owners/0/source.egg"/name)) == expected && originalFiles.contains (name,expected))
      "captured source changed during preparation or queries"
  for name in ["host-stop.json","client-publisher-stop.json","frontend-stop.json"] do
    let stopped ← read (records/"llvm"/name)
    check (stopped.getObjValD "daemonExitCode" == toJson (0 : Nat) &&
      stopped.getObjValD "acknowledged" == toJson true && stopped.getObjValD "processExited" == toJson true &&
      stopped.getObjValD "endpointRemoved" == toJson true && stopped.getObjValD "phase" == toJson "stopped")
      "candidate service did not stop normally"
  write (records/"llvm/summary.json") (Json.mkObj [("requiredAppearances",toJson eligible),
    ("deliveredAppearances",toJson delivered),("semanticCompleted",toJson (0 : Nat)),
    ("parentDeliveredAppearances",toJson (16 : Nat)),("actualHooks",toJson calls.size),
    ("allSixReachTarget",toJson false),("sourceOriginalAndCapturedBytesUnchanged",toJson true),
    ("warmElapsedMs",warm.getObjValD "elapsedMs"),("guard",completed),
    ("observedFailure",toJson "original view exceeds its query budget"),
    ("failureStage",toJson "immutable original-view admission before search; not a ranking or model result"),
    ("accountingChange",toJson "OwnerReady.bytes counts the full stored metadata rather than only the descriptor and focus"),
    ("existingViewBudget",toJson "128 MiB; reservation is 65536 + 32 * counted bytes + lease charge"),
    ("limitsRelaxed",toJson false),("furtherFitting",toJson false),
    ("acceptedSeed",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  let inputs : Array (String × String) ← IO.ofExcept
    (fromJson? (← read (project/"docs/candidates/source-snapshot/protected-native-inputs.json")))
  check (!(inputs.any fun (path,_) => path == root.toString || path.startsWith (root.toString++"/")))
    "candidate deletion overlaps protected native inputs"
  check (!((← IO.FS.readFile (parent/"build/runtime.rsp")).contains root.toString))
    "parent links the ended candidate"
  for (path,expected) in inputs do check ((← hash (.mk path)) == expected) "protected native input changed before deletion"
  let removed ← remove root
  for (path,expected) in inputs do check ((← hash (.mk path)) == expected) "deletion changed a protected native input"
  for (name,expected) in originalFiles do check ((← hash (original/name)) == expected) "deletion changed protected original"
  for query in queries do
    let pass ← IO.ofExcept (query.getObjValAs? Nat "pass")
    let topic ← IO.ofExcept (query.getObjValAs? Nat "topic")
    IO.FS.removeFile (records/"llvm"/s!"pass-{pass}-topic-{topic}.txt")
  write (records/"cleanup.json") (Json.mkObj [("target",toJson root.toString),("files",toJson removed.1),
    ("logicalBytes",toJson removed.2),("protectedNativeHashesBeforeAndAfter",toJson inputs.size),
    ("protectedOriginalFiles",toJson originalFiles),("archiveCreated",toJson false),
    ("actualBodiesRetainedLosslessly",toJson true),("parentAndModelRetained",toJson true)])
  audit #["inspect",(parent/"build").toString,(records/"parent-after-cleanup.json").toString]
def compact : IO Unit := do
  idle
  let mut refusals : Array (String × Json) := #[]
  for entry in ← records.readDir do
    if entry.fileName.endsWith "-rejection.json" then
      refusals := refusals.push (entry.fileName,← read entry.path)
  check (!refusals.isEmpty && !(← (records/"build-refusals.json").pathExists)) "fresh compact build history required"
  write (records/"build-refusals.json") (toJson refusals)
  let reread : Array (String × Json) ← IO.ofExcept (fromJson? (← read (records/"build-refusals.json")))
  check (reread == refusals) "build history changed during consolidation"
  for (name,_) in refusals do IO.FS.removeFile (records/name)
  let guards : Array (String × Json) ← IO.ofExcept (fromJson? (← read (records/"guards.json")))
  for (name,tag) in [("build.guard.json","producer-windows-layout-build"),
      ("checks.guard.json","producer-windows-checks"),
      ("observer-build.guard.json","producer-windows-native-observer-build"),
      ("llvm/capture.guard.json","producer-windows-capture")] do
    let some (_,kept) := guards.find? (·.1 == tag++".guard.json") | throw (IO.userError "guard receipt missing")
    check ((← read (records/name)) == kept) "duplicate guard differs"
    IO.FS.removeFile (records/name)
  check ((← read (records/"llvm/result.json")).getObjValD "queries" == (← read (records/"llvm/queries.json")))
    "completed query list differs from its progress copy"
  IO.FS.removeFile (records/"llvm/queries.json")
end ProducerWindowStudy
def main : List String → IO Unit
  | ["prepare"] => ProducerWindowStudy.prepare
  | ["seal"] => ProducerWindowStudy.capturePatch
  | ["checked-build"] => ProducerWindowStudy.checkedBuild
  | ["basis-build"] => ProducerWindowStudy.basisBuild
  | ["retry",previous,next] => ProducerWindowStudy.retryBuild previous next
  | ["observer"] => ProducerWindowStudy.prepareObserver
  | ["observer-retry",previous,next] => ProducerWindowStudy.observerRetry previous next
  | ["checks"] => ProducerWindowStudy.checks
  | ["capture"] => ProducerWindowStudy.capture
  | ["run"] => ProducerWindowStudy.run
  | ["retire"] => ProducerWindowStudy.retire
  | ["compact"] => ProducerWindowStudy.compact
  | _ => throw (IO.userError "ProducerWindowStudy prepare|seal")
