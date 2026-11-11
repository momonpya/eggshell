import tools.research.StudyLocal
open Lean StudyLocal
namespace BlockSeekStudy
def practical := base/"practical-runtime"
def parent := practical/"independent-maintenance"
def root := practical/"block-seek"
def records := project/"docs/candidates/block-seek"
def parentSha := "bd9096c4378e207b22e1ad48de5906f6967cf7dbbcb1c12722bfc6ce6bb25707"

def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← (records/"plan.json").pathExists)) "fresh block preparation candidate required"
  check ((← hash (parent/"build/StudyMain")) == parentSha) "fixed product changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  for name in ["before-source","source"] do
    discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/name).toString]
    IO.FS.writeFile (root/name/"tools/research/BlockSeekChecks.lean")
      (← IO.FS.readFile (project/"tools/research/BlockSeekChecks.lean"))
  let previous := (← read (parent/"build/build.json")).getObjValD "settings"
  for (sourceName,buildName) in [("before-source","before-build"),("source","component-build")] do
    let settings := previous
      |>.setObjVal! "project" (toJson (root/sourceName).toString)
      |>.setObjVal! "core" (toJson (root/sourceName).toString)
      |>.setObjVal! "output" (toJson (root/buildName).toString)
      |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
      |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
      |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
      |>.setObjVal! "mainModule" (toJson "tools.research.BlockSeekChecks")
      |>.setObjVal! "force" (toJson (#[] : Array String))
    write (root/(buildName++"-settings.json")) settings
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson parentSha),
    ("changedProductModules",toJson #["Eggshell.Blake3"]),("declaredShapes",toJson (4 : Nat)),
    ("blockCasesPerRuntime",toJson (308 : Nat)),("salts",toJson #[19,41]),
    ("startupOrder",toJson #["before","candidate","candidate","before"]),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def build (candidate : Bool) (tag : Option String := none) : IO Unit := do
  idle
  let name := if candidate then "component-build" else "before-build"
  guard (tag.getD ("block-seek-"++name)) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/(name++"-settings.json")).toString]

def sealCandidate : IO Unit := do
  idle
  let patch ← IO.Process.output {
    cmd := "/usr/bin/diff"
    args := #["-u","-L","a/Eggshell/Blake3.lean","-L","b/Eggshell/Blake3.lean",
      (parent/"source/Eggshell/Blake3.lean").toString,(root/"source/Eggshell/Blake3.lean").toString]}
  check (patch.exitCode == 1 && !patch.stdout.isEmpty) "actual source candidate required"
  check (!(← (records/"candidate.patch").pathExists)) "preserve sealed source"
  IO.FS.writeFile (records/"candidate.patch") patch.stdout
  build true

def retryBuild (previous next : String) : IO Unit := do
  idle
  let stopped ← read (base/(previous++".guard.json"))
  check (stopped.getObjValD "state" == toJson "finished" &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous compiler remains live"
  let log ← IO.FS.readFile (root/"component-build/Eggshell_Blake3-lean.stdout")
  let path := records/"build-attempts.json"
  let attempts ← if ← path.pathExists then IO.ofExcept ((← read path).getArr?) else pure #[]
  write path (toJson (attempts.push (Json.mkObj [("guard",stopped),
    ("error",toJson log),("previousPatchSha256",toJson (← hash (records/"candidate.patch"))),
    ("actualHookCalls",toJson (0 : Nat))])))
  let patch ← IO.Process.output {
    cmd := "/usr/bin/diff"
    args := #["-u","-L","a/Eggshell/Blake3.lean","-L","b/Eggshell/Blake3.lean",
      (parent/"source/Eggshell/Blake3.lean").toString,(root/"source/Eggshell/Blake3.lean").toString]}
  check (patch.exitCode == 1) "actual source candidate required"
  IO.FS.writeFile (records/"candidate.patch") patch.stdout
  guard next #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"component-build-settings.json").toString]

def correctControl : IO Unit := do
  idle
  discard <| finished "block-seek-component-trial"
  check (!(← (records/"empty-control-source.lean").pathExists)) "preserve the previous input control"
  IO.FS.writeFile (records/"empty-control-source.lean")
    (← IO.FS.readFile (root/"source/tools/research/BlockSeekChecks.lean"))
  write (records/"empty-control-correction.json") (Json.mkObj [
    ("reason",toJson "first performance field was empty; keep the old result and add a nonempty single-field control"),
    ("productSourceChanged",toJson false),("previousResult",toJson (records/"components.json").toString)])
  for name in ["before-source","source"] do
    IO.FS.writeFile (root/name/"tools/research/BlockSeekChecks.lean")
      (← IO.FS.readFile (project/"tools/research/BlockSeekChecks.lean"))
  build false (some "block-seek-before-nonempty-build")

def audit (label beforeTag candidateTag : String) : IO Unit := do
  idle
  discard <| finished candidateTag
  discard <| finished beforeTag
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  let runAudit := fun args => command (compiler/"bin/lean").toString
    (#["-j1","-M768","--run",auditing.toString] ++ args)
  for name in ["before-build","component-build"] do
    IO.println (← runAudit #["inspect",(root/name).toString,(records/(label++name++"-native.json")).toString])
  IO.println (← runAudit #["compare-sources",(root/"before-build").toString,(root/"component-build").toString,
    (records/(label++"component-sources.json")).toString,"Eggshell.Blake3"])
  let law := root/"laws.lean"
  IO.FS.writeFile law "import Eggshell.Blake3\n#print axioms Eggshell.Blake3.Source.seek_byteAt\n#print axioms Eggshell.Blake3.prepared_block_words_compiled\n"
  let proof ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768",law.toString]
    env := #[("LEAN_PATH",some ((root/"component-build/lib").toString++":"++(compiler/"lib/lean").toString))]}
  IO.FS.writeFile (records/(label++"laws.txt")) (proof.stdout++proof.stderr)
  check (proof.exitCode == 0) "native compiler rewrite lacks a kernel proof"
  guard ("block-seek-"++label++"component-trial") #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/BlockSeekStudy.lean").toString,"__components",label]

def components (label : String) : IO Unit := do
  let before := root/"before-build/StudyMain"
  let candidate := root/"component-build/StudyMain"
  let identities ← #[before,candidate].mapM fun path => do pure (path.toString,← hash path)
  let mut observations := #[]
  for salt in [19,41] do
    let mut expected : Option Json := none
    for label in ["before","candidate","candidate","before"] do
      let runtime := if label == "before" then before else candidate
      let result ← IO.Process.output {cmd := runtime.toString,args := #[toString salt]}
      check (result.exitCode == 0 && result.stderr.isEmpty) "native block component failed"
      let parsed ← IO.ofExcept (Json.parse result.stdout)
      check (parsed.getObjValD "scalarBlockChecks" == toJson (308 : Nat)) "independent scalar block oracle was not exercised"
      let rows ← IO.ofExcept (parsed.getObjValAs? (Array Json) "measurements")
      if label == "nonempty-" then
        check (rows.size == 4 && rows[0]!.getObjValD "bytes" == toJson (262144 : Nat))
          "single-field performance control must contain the declared nonempty payload"
      let signature := toJson (rows.map fun row => row.setObjVal! "elapsedMs" Json.null)
      if let some previous := expected then check (previous == signature) "native framed digest changed under identical inputs"
      else expected := some signature
      observations := observations.push (Json.mkObj [("runtime",toJson label),("salt",toJson salt),
        ("result",parsed),("actualStdout",toJson result.stdout),("exitCode",toJson result.exitCode.toNat)])
  write (records/(label++"components.json")) (Json.mkObj [("identities",toJson identities),
    ("observations",toJson observations),("allDigestsExact",toJson true),
    ("scalarCasesPerInvocation",toJson (308 : Nat)),("actualHookCalls",toJson (0 : Nat)),("adopted",toJson false)])

def copyArtifact (origin target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target.parent.get!
  if ← target.pathExists then
    if (← target.symlinkMetadata).type == .symlink then IO.FS.removeFile target
  IO.FS.writeBinFile target (← IO.FS.readBinFile origin)

def prepareProduct : IO Unit := do
  idle
  discard <| finished "block-seek-nonempty-component-trial"
  let trial ← read (records/"nonempty-components.json")
  check (trial.getObjValD "allDigestsExact" == toJson true) "nonempty numerical comparison has not passed"
  check ((← hash (parent/"build/StudyMain")) == parentSha) "fixed parent changed"
  check (!(← (root/"build").pathExists)) "fresh native product destination required"
  copyLocalArtifacts (parent/"build") (root/"build")
  for name in ["Eggshell.Blake3","tools.research.RegisterMix","tools.research.RegisterRounds"] do
    let stem := name.replace "." "_"
    for extension in ["o","source","dependencies"] do
      copyArtifact (root/"component-build"/(stem++"."++extension)) (root/"build"/(stem++"."++extension))
    let original := root/"component-build/lib"/(name.replace "." "/")
    let destination := root/"build/lib"/(name.replace "." "/")
    let moduleName := (name.splitOn ".").getLast!
    for entry in ← original.parent.get!.readDir do
      if entry.fileName.startsWith (moduleName++".") && !(← entry.path.isDir) then
        copyArtifact entry.path (destination.parent.get! / entry.fileName)
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "force" (toJson (#[] : Array String))
  write (root/"product-build-settings.json") settings
  write (records/"product-plan.json") (Json.mkObj [("parentSha256",toJson parentSha),
    ("patchSha256",toJson (← hash (records/"candidate.patch"))),
    ("componentResultSha256",toJson (← hash (records/"nonempty-components.json"))),
    ("changedProductModules",toJson #["Eggshell.Blake3"]),("fullNativeClosureRequired",toJson true),
    ("selectorChanged",toJson false),("newLockOrWorker",toJson false),("adopted",toJson false)])
  guard "block-seek-product-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"product-build-settings.json").toString]

def auditProduct : IO Unit := do
  idle
  discard <| finished "block-seek-product-build"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  let runAudit := fun args => command (compiler/"bin/lean").toString
    (#["-j1","-M768","--run",auditing.toString] ++ args)
  IO.println (← runAudit #["inspect",(root/"build").toString,(records/"native.json").toString])
  IO.println (← runAudit #["compare-sources",(parent/"build").toString,(root/"build").toString,
    (records/"sources.json").toString,"Eggshell.Blake3"])
  check (!(← (root/"prefix").pathExists)) "fresh isolated product prefix required"
  discard <| command "/bin/cp" #["-cR",(practical/"bound-product/prefix").toString,(root/"prefix").toString]
  guard "block-seek-installation" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/BlockSeekStudy.lean").toString,"__configure"]

def configure : IO Unit := do
  let previous ← read (practical/"bound-product/installation.json")
  let oldRuntime : System.FilePath := .mk (← IO.ofExcept ((previous.getObjValD "runtime").getObjValAs? String "path"))
  let oldRoot := oldRuntime.parent.get!.parent.get!
  let executable := root/"prefix/libexec/eggshell"
  check ((← executable.symlinkMetadata).type == .symlink &&
    (← IO.FS.realPath executable) == (← IO.FS.realPath oldRuntime)) "copied product alias changed"
  IO.FS.removeFile executable
  discard <| command "/bin/ln" #["-s",(root/"build/StudyMain").toString,executable.toString]
  discard <| command "/bin/cp" #["-cR",(root/"build/lib").toString,(root/"helper-lib").toString]
  let library := (root/"helper-lib").toString++":"++(compiler/"lib/lean").toString
  let compiled ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M2048","-DwarningAsError=true","-o",
      (root/"helper-lib/tools/research/StudyLaunchers.olean").toString,
      (project/"tools/research/StudyLaunchers.lean").toString]
    env := #[("LEAN_PATH",some library)]}
  check (compiled.exitCode == 0) (compiled.stdout++compiled.stderr)
  let runner := root/"launcher-main.lean"
  IO.FS.writeFile runner "import tools.research.StudyLaunchers\ndef main := Eggshell.Research.StudyLaunchers.cliMain\n"
  let bound ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M2048","--run",runner.toString,"bind",(root/"prefix").toString,oldRoot.toString,
      (records/"launcher-binding.json").toString]
    env := #[("LEAN_PATH",some library)]}
  check (bound.exitCode == 0) (bound.stdout++bound.stderr)
  let mut files := #[]
  for file in ← IO.ofExcept (previous.getObjValAs? (Array Json) "pluginFiles") do
    let path : String ← IO.ofExcept (file.getObjValAs? _ "path")
    let originalPrefix := oldRoot.toString++"/"
    check (path.startsWith originalPrefix) "declared plugin artifact escaped its prefix"
    let relative := path.drop originalPrefix.length |>.toString
    let destination := root/"prefix"/relative
    let digest ← hash destination
    unless ["plugins/eggshell/bin/egg","plugins/eggshell/bin/eggshelld"].contains relative do
      check (toJson digest == file.getObjValD "sha256") "unrelated installed artifact changed"
    files := files.push (file.setObjVal! "path" (toJson destination.toString)
      |>.setObjVal! "sha256" (toJson digest))
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (previous.getObjValD "environment"))
  let updates := #[("EGGSHELL_PREFIX",some (root/"prefix").toString),
    ("PLUGIN_ROOT",some (root/"prefix/plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (root/"run/data").toString),("TMPDIR",some (root/"tmp").toString)]
  let env := env.filter (fun row => !updates.any (·.1 == row.1)) ++ updates
  let installation := previous
    |>.setObjVal! "runtime" (Json.mkObj [("path",toJson executable.toString),("sha256",toJson (← hash executable))])
    |>.setObjVal! "pluginRoot" (toJson (root/"prefix/plugins/eggshell").toString)
    |>.setObjVal! "pluginFiles" (toJson files)
    |>.setObjVal! "environment" (toJson env)
  check (!(← (root/"installation.json").pathExists)) "preserve sealed installation"
  IO.FS.createDirAll (root/"tmp")
  write (root/"installation.json") installation
  write (records/"installation.json") installation
  write (records/"identity.json") (Json.mkObj [("runtime",installation.getObjValD "runtime"),
    ("parentSha256",toJson parentSha),("patchSha256",toJson (← hash (records/"candidate.patch"))),
    ("globalInstallChanged",toJson false)])

def prepareStartup : IO Unit := do
  idle
  discard <| finished "block-seek-installation"
  guard "block-seek-product-startup" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/BlockSeekStudy.lean").toString,"__startup"]

def startup : IO Unit := do
  let installation ← read (root/"installation.json")
  check (toJson (← hash (root/"build/StudyMain")) == (installation.getObjValD "runtime").getObjValD "sha256")
    "candidate startup differs from its sealed installation"
  let mut observations := #[]
  let mut expected : Option String := none
  for wave in [:4] do
    for label in ["before","candidate","candidate","before"] do
      let path := if label == "before" then parent/"build/StudyMain" else root/"build/StudyMain"
      let started ← IO.monoMsNow
      let output ← IO.Process.output {cmd := "/usr/bin/time",args := #["-l",path.toString,"--help"]}
      let elapsed := (← IO.monoMsNow)-started
      check (output.exitCode == 0 && !output.stdout.isEmpty) "native startup command failed"
      if let some previous := expected then check (previous == output.stdout) "native help response changed"
      else expected := some output.stdout
      observations := observations.push (Json.mkObj [("wave",toJson (wave+1)),("runtime",toJson label),
        ("elapsedMs",toJson elapsed),("time",toJson output.stderr),("exitCode",toJson output.exitCode.toNat)])
  write (records/"startup.json") (Json.mkObj [("parentSha256",toJson parentSha),
    ("candidate",installation.getObjValD "runtime"),("observations",toJson observations),
    ("stdout",toJson expected),("actualHookCalls",toJson (0 : Nat)),("adopted",toJson false)])

def prepareTraffic : IO Unit := do
  idle
  discard <| finished "block-seek-product-startup"
  let installation ← read (root/"installation.json")
  check (toJson (← hash (root/"build/StudyMain")) == (installation.getObjValD "runtime").getObjValD "sha256")
    "candidate traffic differs from its sealed product"
  let binding ← read (records/"launcher-binding.json")
  check (binding.getObjValD "newBindingVerified" == toJson true) "actual launcher binding is unverified"
  for file in ← IO.ofExcept (installation.getObjValAs? (Array Json) "pluginFiles") do
    let path : String ← IO.ofExcept (file.getObjValAs? _ "path")
    check (toJson (← hash (.mk path)) == file.getObjValD "sha256") "sealed plugin changed"
  let frozen ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let seed ← read (practical/"cohort/study/seed-1/plan.json")
  let input := Json.mkObj [("installation",installation),("original",frozen.getObjValD "source"),
    ("originalFiles",frozen.getObjValD "sourceFiles"),("workspace",seed.getObjValD "workspace"),
    ("definitions",← read (practical/"interrupted-recovery/definitions.json")),("preparedReference",Json.null),
    ("activeReaders",toJson (3 : Nat)),("llvmReaders",toJson (3 : Nat)),("registered",toJson true),
    ("observeMaintenance",toJson false)]
  check (!(← (root/"input.json").pathExists)) "preserve admitted full-product traffic"
  write (root/"input.json") input
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := env.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  let redirect := "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\""
  guard "block-seek-product-traffic" (#["/bin/sh","-c",redirect,"block-seek-traffic",
    (records/"traffic.stdout").toString,(records/"traffic.stderr").toString,"/usr/bin/env"] ++
    unset.flatMap (fun key => #["-u",key]) ++ assigned ++ #[(root/"build/StudyMain").toString,
      "shared-traffic",(root/"input.json").toString,(root/"run").toString])

def retainTraffic : IO Unit := do
  idle
  discard <| finished "block-seek-product-traffic"
  for action in ["retain-at","profiles-at"] do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
      (project/"tools/research/SharedTrafficStudy.lean").toString,action,
      root.toString,records.toString,"block-seek-product-traffic"]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/SharedTrafficStudy.lean").toString,"reuse-at",records.toString]
  let result ← read (records/"result.json")
  let mut terminal := #[]
  let mut warnings := #[]
  for session in ← (root/"run/calls").readDir do
    for call in ← session.path.readDir do
      if (← call.path.symlinkMetadata).type != .dir then continue
      let stderr ← IO.FS.readFile (call.path/"stderr")
      unless stderr.isEmpty do
        warnings := warnings.push (Json.mkObj [("session",toJson session.fileName),
          ("label",toJson call.fileName),("stderr",toJson stderr)])
      if !["stop","compact-start","post-compact","interrupt","end"].contains call.fileName then continue
      let timing ← read (call.path/"record.json")
      check ((← IO.ofExcept (Json.parse (← IO.FS.readFile (call.path/"stdout")))) == Json.mkObj [])
        "terminal event returned an incomplete notice"
      check (timing.getObjValD "stdoutSha256" == toJson (← hash (call.path/"stdout"))) "terminal reply changed"
      terminal := terminal.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("timing",timing),("registration",← read (call.path/"registration.json"))])
  check (terminal.size == 88) "all Stops and reader terminal events required"
  write (records/"terminal-events.json") (toJson terminal)
  write (records/"client-warnings.json") (toJson warnings)
  write (records/"baseline.json") (Json.mkObj [("answers",← read (root/"run/baseline-auto-answers.json")),
    ("synapses",← read (root/"run/baseline-facts.json"))])
  let rows ← IO.ofExcept (result.getObjValAs? (Array Json) "summary")
  let compact := rows.map fun row => Json.mkObj [("wave",row.getObjValD "wave"),
    ("elapsedMs",row.getObjValD "elapsedMs"),("maxReaderMs",row.getObjValD "maxHookMs"),
    ("semanticCompleted",row.getObjValD "semanticCompleted"),
    ("observations",(row.getObjValD "census").getObjValD "count"),("answers",row.getObjValD "automaticAnswers")]
  let summary := Json.mkObj [("waves",toJson compact),("terminalEvents",toJson terminal.size),
    ("clientWarnings",toJson warnings.size),
    ("peakRssKiB",(result.getObjValD "guard").getObjValD "sampledPeakRssKiB"),
    ("paidMatchedComparisons",toJson (0 : Nat)),("adopted",toJson false)]
  write (records/"summary.json") summary
  IO.println summary.compress

def prepareTenReaders : IO Unit := do
  idle
  discard <| finished "block-seek-product-traffic"
  check ((← (records/"terminal-events.json").pathExists) && !(← (root/"readers-build").pathExists))
    "retain mixed traffic and use a fresh readonly controller"
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
  write (records/"ten-readers-plan.json") (Json.mkObj [("product",(← read (root/"installation.json")).getObjValD "runtime"),
    ("source",toJson (root/"run/llvm.egg").toString),("queriesPerWave",toJson (10 : Nat)),
    ("waves",toJson (3 : Nat)),("topicCountsPerWave",toJson #[4,3,3]),("newDataRoot",toJson true),
    ("sourceOnlyReadonly",toJson true),("noWarmCommand",toJson true),
    ("sameFrozenEvidence",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "block-seek-ten-readers-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"readers-build-settings.json").toString]

def runTenReaders : IO Unit := do
  idle
  discard <| finished "block-seek-ten-readers-build"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for args in [#["inspect",(root/"readers-build").toString,(records/"ten-readers-native.json").toString],
      #["subset-sources",(root/"build").toString,(root/"readers-build").toString,
        (records/"ten-readers-sources.json").toString,"Main","Eggshell.HookFrontend","Eggshell.PublicationService",
        "Eggshell.Handoff","Eggshell.Blake3"]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString] ++ args))
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? ((← read (root/"installation.json")).getObjValD "environment"))
  let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := env.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  let redirect := "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\""
  guard "block-seek-ten-readers" (#["/bin/sh","-c",redirect,"ten-readers",
    (records/"ten-readers.stdout").toString,(records/"ten-readers.stderr").toString,"/usr/bin/env"] ++
    unset.flatMap (fun key => #["-u",key]) ++ assigned ++ #[(root/"readers-build/StudyMain").toString,
      (root/"input.json").toString,(root/"run/llvm.egg").toString,
      (records/"frozen-before-delivery.json").toString,(root/"ten-readers").toString])

def retainTenReaders : IO Unit := do
  idle
  let monitor ← finished "block-seek-ten-readers"
  let area := root/"ten-readers"
  let result ← read (area/"result.json")
  let waves ← IO.ofExcept (result.getObjValAs? (Array Json) "waves")
  check (waves.size == 3) "all three ten-query waves required"
  IO.FS.createDirAll (records/"ten-reader-bodies")
  let mut summaries := #[]
  let mut queries := #[]
  let mut terminal := #[]
  let mut warnings := #[]
  for wave in waves do
    let outcomes ← IO.ofExcept (wave.getObjValAs? (Array Json) "outcomes")
    check (outcomes.size == 10) "each readonly wave must contain ten real requests"
    for outcome in outcomes do
      let topic : Nat ← IO.ofExcept (outcome.getObjValAs? _ "topic")
      let delivery := outcome.getObjValD "delivery"
      let session : String ← IO.ofExcept (delivery.getObjValAs? _ "session")
      let originalBody : String ← IO.ofExcept (delivery.getObjValAs? _ "body")
      let call := area/"calls"/session/"prompt"
      let timing ← read (call/"record.json")
      let bodyHash ← hash (.mk originalBody)
      let stdoutHash ← hash (call/"stdout")
      check (delivery.getObjValD "bodySha256" == toJson bodyHash &&
        timing.getObjValD "stdoutSha256" == toJson stdoutHash) "actual readonly output changed before retention"
      let known := project/"docs/practical-runtime/recovery"/s!"topic-{topic}"
      let bodySame := (← hash (known/"body.txt")) == bodyHash
      let stdoutSame := (← hash (known/"stdout.json")) == stdoutHash
      let body := if bodySame then known/"body.txt" else records/"ten-reader-bodies"/(bodyHash++".txt")
      let stdout := if stdoutSame then known/"stdout.json" else records/"ten-reader-bodies"/(stdoutHash++".json")
      unless bodySame do copyArtifact (.mk originalBody) body
      unless stdoutSame do copyArtifact (call/"stdout") stdout
      queries := queries.push (Json.mkObj [("wave",wave.getObjValD "wave"),("topic",toJson topic),
        ("delivery",delivery),("timing",timing),("request",← read (call/"stdin")),
        ("retainedBody",toJson body.toString),("retainedStdout",toJson stdout.toString),
        ("sameKnownBody",toJson bodySame),("sameKnownStdout",toJson stdoutSame)])
      let ending := area/"calls"/session/"end"
      check ((← IO.ofExcept (Json.parse (← IO.FS.readFile (ending/"stdout")))) == Json.mkObj [])
        "readonly terminal event returned an incomplete notice"
      terminal := terminal.push (Json.mkObj [("session",toJson session),("timing",← read (ending/"record.json")),
        ("registration",← read (ending/"registration.json"))])
      for label in ["start","prompt","end"] do
        let text ← IO.FS.readFile (area/"calls"/session/label/"stderr")
        unless text.isEmpty do
          warnings := warnings.push (Json.mkObj [("session",toJson session),("label",toJson label),("stderr",toJson text)])
    summaries := summaries.push (Json.mkObj [("wave",wave.getObjValD "wave"),("elapsedMs",wave.getObjValD "elapsedMs"),
      ("audits",wave.getObjValD "audits")])
  check (queries.size == 30 && terminal.size == 30) "all actual readonly calls required"
  write (records/"ten-readers-result.json") (Json.mkObj [("native",result),("guard",monitor),
    ("summary",toJson summaries),("queries",toJson queries),("terminalEvents",toJson terminal),
    ("clientWarnings",toJson warnings),("sameUnixUserAndHost",toJson true),
    ("newPrivateStateWithoutWarm",toJson true),("paidModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  write (records/"ten-readers-stopped.json") (Json.mkObj [("frontend",← read (area/"frontend-stop.json")),
    ("publisher",← read (area/"publisher-stop.json"))])
  let allBodies := queries.all fun query => query.getObjValD "sameKnownBody" == toJson true
  let allStdout := queries.all fun query => query.getObjValD "sameKnownStdout" == toJson true
  let compact := Json.mkObj [("elapsedMs",toJson (waves.map (·.getObjValD "elapsedMs"))),
    ("queries",toJson queries.size),("sameKnownBody",toJson allBodies),("sameKnownStdout",toJson allStdout),
    ("terminalEvents",toJson terminal.size),("clientWarnings",toJson warnings.size),
    ("peakRssKiB",monitor.getObjValD "sampledPeakRssKiB"),("adopted",toJson false)]
  write (records/"ten-readers-summary.json") compact
  IO.println compact.compress

def prepareReadonlyPostmortem : IO Unit := do
  idle
  let stopped ← read (base/"block-seek-ten-readers.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "reason" == toJson "aggregate-rss") "readonly load is not terminal with the recorded resource stop"
  IO.FS.writeFile (root/"source/tools/research/TenReaderAudit.lean")
    (← IO.FS.readFile (project/"tools/research/TenReaderAudit.lean"))
  copyLocalArtifacts (root/"readers-build") (root/"postmortem-build")
  let settings := (← read (root/"readers-build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"postmortem-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"readers-build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"readers-build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"readers-build/tools_research_TenReaders.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"readers-build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.TenReaderAudit")
  write (root/"postmortem-build-settings.json") settings
  guard "block-seek-postmortem-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"postmortem-build-settings.json").toString]

def runReadonlyPostmortem : IO Unit := do
  idle
  discard <| finished "block-seek-postmortem-build"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for args in [#["inspect",(root/"postmortem-build").toString,(records/"postmortem-native.json").toString],
      #["subset-sources",(root/"build").toString,(root/"postmortem-build").toString,
        (records/"postmortem-sources.json").toString,"Main","Eggshell.Blake3","Eggshell.Handoff"]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString] ++ args))
  guard "block-seek-readonly-postmortem" #[(root/"postmortem-build/StudyMain").toString,
    (root/"input.json").toString,(root/"run/llvm.egg").toString,(records/"frozen-before-delivery.json").toString,
    (root/"ten-readers").toString,(records/"ten-readers-postmortem.json").toString]

partial def files (directory : System.FilePath) : IO (Array System.FilePath) := do
  let mut found := #[]
  for entry in ← directory.readDir do
    if (← entry.path.symlinkMetadata).type == .dir then found := found ++ (← files entry.path)
    else found := found.push entry.path
  return found

partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut count := (0,0)
    for entry in ← path.readDir do
      let part ← remove entry.path
      count := (count.1+part.1,count.2+part.2)
    IO.FS.removeDir path
    return count
  IO.FS.removeFile path
  return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)

def retainStoppedReaders : IO Unit := do
  idle
  discard <| finished "block-seek-readonly-postmortem"
  let monitor ← read (base/"block-seek-ten-readers.guard.json")
  check (monitor.getObjValD "state" == toJson "finished" &&
    monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    monitor.getObjValD "exitCode" == toJson (137 : Nat)) "preserve the failed readonly series as failed"
  let area := root/"ten-readers"
  let postmortem ← read (records/"ten-readers-postmortem.json")
  let completed ← IO.ofExcept (postmortem.getObjValAs? (Array Json) "observedCompletedRequests")
  let mut queries := #[]
  for row in completed do
    let session : String ← IO.ofExcept (row.getObjValAs? _ "session")
    let topic : Nat ← IO.ofExcept (row.getObjValAs? _ "topic")
    let path : String ← IO.ofExcept (row.getObjValAs? _ "body")
    let known := project/"docs/practical-runtime/recovery"/s!"topic-{topic}"
    check ((← hash (.mk path)) == (← hash (known/"body.txt")) &&
      (row.getObjValD "timing").getObjValD "stdoutSha256" == toJson (← hash (known/"stdout.json")))
      "completed readonly bytes differ; retain the raw trial before any cleanup"
    queries := queries.push (row.setObjVal! "body" (toJson (known/"body.txt").toString)
      |>.setObjVal! "bodySha256" (toJson (← hash (known/"body.txt")))
      |>.setObjVal! "retainedBody" (toJson (known/"body.txt").toString)
      |>.setObjVal! "retainedStdout" (toJson (known/"stdout.json").toString)
      |>.setObjVal! "request" (← read (area/"calls"/session/"prompt/stdin")))
  let mut calls := #[]
  for session in ← (area/"calls").readDir do
    for label in ["start","prompt","end"] do
      let call := session.path/label
      if !(← (call/"stdin").pathExists) then continue
      let hasRecord ← (call/"record.json").pathExists
      let timing ← if hasRecord then read (call/"record.json") else pure Json.null
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson label),
        ("request",← read (call/"stdin")),("terminalRecordPresent",toJson hasRecord),
        ("timing",timing)])
  let mut control := #[]
  for session in ← (area/"data/sessions").readDir do
    let mut queuedNone := 0
    let mut queuedSome := 0
    for name in ["checkpoints","deferred"] do
      let directory := session.path/name
      if !(← directory.pathExists) then continue
      for entry in ← directory.readDir do
        if !entry.fileName.endsWith ".json" then continue
        let value ← read entry.path
        if (value.getObjVal? "write").toOption == some Json.null then queuedNone := queuedNone+1
        else queuedSome := queuedSome+1
    let observations := session.path/"observed-files"
    let observed ← if ← observations.pathExists then files observations else pure #[]
    let mut bytes := 0
    for path in observed do
      let metadata ← path.symlinkMetadata
      if metadata.type == .file then bytes := bytes+metadata.byteSize.toNat
    control := control.push (Json.mkObj [("session",toJson session.fileName),
      ("queuedCapturedNoWrite",toJson queuedNone),("queuedOtherOrUnknown",toJson queuedSome),
      ("observedFilesCount",toJson observed.size),("observedFilesLogicalBytes",toJson bytes)])
  write (records/"readonly-control.json") (toJson control)
  let peaks ← IO.ofExcept (monitor.getObjValAs? (Array Json) "peakProcesses")
  let sourceWorkers := peaks.filter fun row => row.getObjValD "role" == toJson "codex-worker" &&
    row.getObjValD "lane" == toJson "save"
  let mut workerRss := 0
  for worker in sourceWorkers do workerRss := workerRss+(← IO.ofExcept (worker.getObjValAs? Nat "rssKiB"))
  write (records/"ten-readers-failed.json") (Json.mkObj [("guard",monitor),
    ("completedWaves",← read (area/"waves.json")),("completedRequests",toJson queries),
    ("failedNativeRequests",postmortem.getObjValD "failedNativeRequests"),("calls",toJson calls),
    ("sourceUnchanged",postmortem.getObjValD "sourceUnchanged"),
    ("replayedHooks",toJson (0 : Nat)),("completedSeriesClaimed",toJson false),
    ("sourceWorkersAtPeak",toJson sourceWorkers.size),("sourceWorkerRssKiBAtPeak",toJson workerRss),
    ("readonlySourceWorkIsOnlyCauseProven",toJson false)])
  write (records/"ten-readers-postmortem.json")
    (postmortem.setObjVal! "observedCompletedRequests" (toJson queries))

def retire : IO Unit := do
  idle
  discard <| finished "block-seek-product-traffic"
  discard <| finished "block-seek-readonly-postmortem"
  check (!(← (records/"retired.json").pathExists)) "preserve previous retirement"
  let mut guards := []
  for tag in ["initialization-sampling","block-seek-component-build","block-seek-component-checked-build",
      "block-seek-before-build","block-seek-component-trial","block-seek-before-nonempty-build",
      "block-seek-nonempty-build","block-seek-nonempty-component-trial","block-seek-product-build",
      "block-seek-installation","block-seek-product-startup","block-seek-product-traffic",
      "block-seek-ten-readers-build","block-seek-ten-readers","block-seek-postmortem-build","block-seek-readonly-postmortem"] do
    let value ← read (base/(tag++".guard.json"))
    check (value.getObjValD "state" == toJson "finished" &&
      value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "a candidate guard remains live"
    guards := guards ++ [(tag,value)]
  write (records/"guards.json") (Json.mkObj guards)
  let result ← read (records/"result.json")
  let queries ← IO.ofExcept (result.getObjValAs? (Array Json) "queries")
  check (queries.size == 18 && (← (records/"terminal-events.json").pathExists) &&
    (← (records/"hook-profiles.json").pathExists)) "retain actual query and lifecycle evidence first"
  for query in queries do
    let body : String ← IO.ofExcept (query.getObjValAs? _ "retainedBody")
    let stdout : String ← IO.ofExcept (query.getObjValAs? _ "retainedStdout")
    check ((query.getObjValD "delivery").getObjValD "bodySha256" == toJson (← hash (.mk body))) "retained original changed"
    check ((query.getObjValD "timing").getObjValD "stdoutSha256" == toJson (← hash (.mk stdout))) "retained response changed"
  let readonly ← read (records/"ten-readers-failed.json")
  let additional ← IO.ofExcept (readonly.getObjValAs? (Array Json) "completedRequests")
  check (additional.size == 10 && readonly.getObjValD "completedSeriesClaimed" == toJson false)
    "preserve the partial readonly failure and its completed output first"
  for query in additional do
    let body : String ← IO.ofExcept (query.getObjValAs? _ "retainedBody")
    let stdout : String ← IO.ofExcept (query.getObjValAs? _ "retainedStdout")
    check (query.getObjValD "bodySha256" == toJson (← hash (.mk body))) "retained readonly body changed"
    check ((query.getObjValD "timing").getObjValD "stdoutSha256" == toJson (← hash (.mk stdout))) "retained readonly stdout changed"
  let original ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let source : String ← IO.ofExcept (original.getObjValAs? _ "source")
  let protectedFiles : Array (String × String) ← IO.ofExcept (original.getObjValAs? _ "sourceFiles")
  let artifacts := #[root/"build/StudyMain",parent/"build/StudyMain",practical/"build/StudyMain",
    base/"canonical-decoder-runtime/build/StudyMain",practical/"coordinated-warm/build/StudyMain"]
  let saved ← artifacts.mapM fun path => do pure (path,← hash path)
  for (name,digest) in protectedFiles do check ((← hash (System.FilePath.mk source/name)) == digest) "protected original changed"
  let targets := #[root/"run",root/"ten-readers",root/"readers-build",root/"postmortem-build",root/"tmp",root/"before-source",root/"before-build",root/"component-build",
    root/"helper-lib",root/"launcher-main.lean",practical/"initialization"]
  let retiredPath := fun (value : String) => targets.any fun target =>
    value == target.toString || value.startsWith (target.toString++"/")
  for directory in [root/"build",parent/"build",practical/"build",base/"canonical-decoder-runtime/build",practical/"coordinated-warm/build"] do
    for line in (← IO.FS.readFile (directory/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      if path.isAbsolute then check (!retiredPath (← IO.FS.realPath path).toString) "current object belongs to an ended trial"
    for path in ← files (directory/"lib") do
      if (← path.symlinkMetadata).type == .symlink then
        check (!retiredPath (← IO.FS.realPath path).toString) "current interface belongs to an ended trial"
  check (!retiredPath (← IO.FS.realPath (root/"prefix/share/eggshell/minilm")).toString) "model belongs to an ended trial"
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any fun line => line.trimAscii.toString.startsWith (base.toString++"/"))
    "native service or client remains live"
  let mut removed := (0,0)
  for path in targets do
    if !(← path.pathExists) then continue
    let part ← remove path
    removed := (removed.1+part.1,removed.2+part.2)
  for (path,digest) in saved do check ((← hash path) == digest) "protected runtime changed"
  for (name,digest) in protectedFiles do check ((← hash (System.FilePath.mk source/name)) == digest) "source changed during retirement"
  let mut outputs := #[]
  for name in ["traffic.stdout","traffic.stderr","ten-readers.stdout","ten-readers.stderr"] do
    let path := records/name
    let bytes ← IO.FS.readBinFile path
    outputs := outputs.push (Json.mkObj [("name",toJson name),("bytes",toJson bytes.size),("sha256",toJson (← hash path))])
    if bytes.isEmpty then IO.FS.removeFile path
  write (records/"service-output.json") (toJson outputs)
  write (records/"retired.json") (Json.mkObj [("files",toJson removed.1),("logicalBytes",toJson removed.2),
    ("archiveCreated",toJson false),("sourceAndRuntimeHashesUnchanged",toJson true),
    ("nativeInputsAndInterfacesOutsideRetiredTargets",toJson true),("candidateProductRetained",toJson true)])

def main : List String → IO Unit
  | ["prepare"] => prepare
  | ["seal"] => sealCandidate
  | ["build-before"] => build false
  | ["correct-control"] => correctControl
  | ["build-nonempty"] => build true (some "block-seek-nonempty-build")
  | ["retry-build",previous,next] => retryBuild previous next
  | ["audit"] => audit "" "block-seek-before-build" "block-seek-component-checked-build"
  | ["audit-nonempty"] => audit "nonempty-" "block-seek-before-nonempty-build" "block-seek-nonempty-build"
  | ["__components",label] => components label
  | ["prepare-product"] => prepareProduct
  | ["audit-product"] => auditProduct
  | ["__configure"] => configure
  | ["prepare-startup"] => prepareStartup
  | ["__startup"] => startup
  | ["prepare-traffic"] => prepareTraffic
  | ["retain-traffic"] => retainTraffic
  | ["prepare-ten-readers"] => prepareTenReaders
  | ["run-ten-readers"] => runTenReaders
  | ["retain-ten-readers"] => retainTenReaders
  | ["prepare-readonly-postmortem"] => prepareReadonlyPostmortem
  | ["run-readonly-postmortem"] => runReadonlyPostmortem
  | ["retain-stopped-readers"] => retainStoppedReaders
  | ["retire"] => retire
  | _ => throw (IO.userError "BlockSeekStudy prepare|seal|build-before")
end BlockSeekStudy
def main := BlockSeekStudy.main
