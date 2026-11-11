import tools.research.StudyLocal
open Lean StudyLocal
namespace TerminalCaptureStudy
def practical := base/"practical-runtime"
def parent := practical/"readonly-save"
def root := practical/"terminal-capture"
def records := project/"docs/candidates/terminal-capture"
def changes := #["Eggshell.PluginHooks","Eggshell.Daemon","Eggshell.ContractAudit"]
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh terminal capture candidate required"
  check ((← hash (parent/"build/StudyMain")) ==
    "04476843d0af2e9440ac2287cc85235c7bf4e1299d99ae2db866c3e99ea0b3ac") "parent runtime changed"
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
    ("changedProductModules",toJson changes),("captureBeforeFrontendRPC",toJson true),
    ("capturedTurnAndWriteTargetRequired",toJson true),("unboundAnswerCannotPublish",toJson true),
    ("normalSynapticJournalRetained",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false)])

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
  guard "terminal-capture-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]

def audit : IO Unit := do
  idle
  discard <| finished "terminal-capture-checked-build"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for args in [#["inspect",(root/"build").toString,(records/"native.json").toString],
      #["compare-sources",(parent/"build").toString,(root/"build").toString,
        (records/"sources.json").toString]++changes] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString]++args))

def retryBuild : IO Unit := do
  idle
  let previous ← read (base/"terminal-capture-build.guard.json")
  check (previous.getObjValD "state" == toJson "finished" &&
    previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "prior compiler is not terminal"
  check (!(← (records/"build-attempt.json").pathExists)) "preserve compiler failure"
  write (records/"build-attempt.json") (Json.mkObj [("guard",previous),
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
  guard "terminal-capture-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]

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
    let relative := path.drop old.length |>.toString
    let destination := root/"prefix"/relative
    let digest ← hash destination
    unless ["plugins/eggshell/bin/egg","plugins/eggshell/bin/eggshelld"].contains relative do
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
  discard <| finished "terminal-capture-checked-build"
  IO.FS.writeFile (root/"source/tools/research/TerminalCaptureChecks.lean")
    (← IO.FS.readFile (project/"tools/research/TerminalCaptureChecks.lean"))
  copyLocalArtifacts (root/"build") (root/"checks-build")
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"checks-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.TerminalCaptureChecks")
  write (root/"checks-build-settings.json") settings
  guard "terminal-capture-checks-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"checks-build-settings.json").toString]

def auditChecks : IO Unit := do
  idle
  discard <| finished "terminal-capture-checks-checked-build"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for args in [#["inspect",(root/"checks-build").toString,(records/"checks-native.json").toString],
      #["subset-sources",(root/"build").toString,(root/"checks-build").toString,
        (records/"checks-sources.json").toString,"Main","Eggshell.PluginHooks","Eggshell.Daemon","Eggshell.ContractAudit"]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString]++args))

def retryChecks : IO Unit := do
  idle
  let previous ← read (base/"terminal-capture-checks-build.guard.json")
  check (previous.getObjValD "state" == toJson "finished" &&
    previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "prior control compiler is not terminal"
  check (!(← (records/"checks-build-attempt.json").pathExists)) "preserve compiler failure"
  write (records/"checks-build-attempt.json") (Json.mkObj [("guard",previous),
    ("source",toJson (← IO.FS.readFile (root/"source/tools/research/TerminalCaptureChecks.lean"))),
    ("compilerOutput",toJson (← IO.FS.readFile (root/"checks-build/tools_research_TerminalCaptureChecks-lean.stdout"))),
    ("actualHookCalls",toJson (0 : Nat)),("productSourceChanged",toJson false)])
  IO.FS.writeFile (root/"source/tools/research/TerminalCaptureChecks.lean")
    (← IO.FS.readFile (project/"tools/research/TerminalCaptureChecks.lean"))
  guard "terminal-capture-checks-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"checks-build-settings.json").toString]

def refreshChecks : IO Unit := do
  idle
  check (!(← (root/"checks-build/StudyMain").pathExists)) "native control has already been built"
  IO.FS.writeFile (root/"source/tools/research/TerminalCaptureChecks.lean")
    (← IO.FS.readFile (project/"tools/research/TerminalCaptureChecks.lean"))

def runCheck (fault : Bool) : IO Unit := do
  idle
  let installation ← read (root/"installation.json")
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let label := if fault then "fault" else "boundaries"
  let updates := #[("EGGSHELL_DATA_ROOT",some (root/label/"data").toString)]
  let env := env.filter (fun row => !updates.any (·.1 == row.1))++updates
  let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := env.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  let args := if fault then #["fault",(root/"installation.json").toString,(root/label).toString]
    else #["boundaries",(root/label).toString]
  guard ("terminal-capture-"++label) (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    label,(records/(label++".stdout")).toString,(records/(label++".stderr")).toString,"/usr/bin/env"]++
    unset.flatMap (fun key => #["-u",key])++assigned++#[(root/"checks-build/StudyMain").toString]++args)

def retainChecks : IO Unit := do
  idle
  let boundary ← finished "terminal-capture-boundaries"
  let fault ← finished "terminal-capture-fault"
  write (records/"boundaries.json") (← read (root/"boundaries/result.json"))
  write (records/"fault.json") (← read (root/"fault/result.json"))
  write (records/"captured-before-services-stop.json") (← read (root/"fault/captured-before-services-stop.json"))
  write (records/"recovered-answer.json") (← read (root/"fault/recovered-answer.json"))
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
  let mut stops := #[]
  for receipt in ← (root/"fault/data/receipts").readDir do
    if !(← (receipt.path/"request.json").pathExists) then continue
    let request ← read (receipt.path/"request.json")
    if (request.getObjValD "data").getObjValD "event" != toJson "Stop" then continue
    let mut stages := #[]
    for entry in ← receipt.path.readDir do
      if entry.fileName.endsWith ".json" then stages := stages.push (entry.fileName,← read entry.path)
    stops := stops.push (Json.mkObj [("receipt",toJson receipt.fileName),("stages",toJson stages)])
  write (records/"registered-fault-calls.json") (toJson calls)
  write (records/"stop-receipts.json") (toJson stops)
  write (records/"check-guards.json") (Json.mkObj [("boundaries",boundary),("fault",fault)])
  let law := root/"laws.lean"
  IO.FS.writeFile law "import Eggshell.PluginHooks\n#print axioms Eggshell.Plugin.final_capture_preserves_scope\n#print axioms Eggshell.Plugin.final_capture_seals_answer\n#print axioms Eggshell.Plugin.final_capture_checks_identity\n#print axioms Eggshell.Plugin.final_capture_named_turn\n#print axioms Eggshell.Plugin.readonly_final_capture_has_no_source_job\n"
  let result ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768",law.toString]
    env := #[("LEAN_PATH",some ((root/"build/lib").toString++":"++(compiler/"lib/lean").toString))]}
  IO.FS.writeFile (records/"laws.txt") (result.stdout++result.stderr)
  check (result.exitCode == 0) "terminal scope laws failed"

def traffic : IO Unit := do
  idle
  discard <| finished "terminal-capture-fault"
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
    ("sameFrozenOriginals",toJson true),("manualKeep",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := env.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  guard "terminal-capture-traffic" (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "mixed-traffic",(records/"traffic.stdout").toString,(records/"traffic.stderr").toString,"/usr/bin/env"]++
    unset.flatMap (fun key => #["-u",key])++assigned++#[(root/"build/StudyMain").toString,
      "shared-traffic",(root/"input.json").toString,(root/"run").toString])

def proofAudit : IO Unit := do
  idle
  check (!(← (records/"laws-first.txt").pathExists)) "preserve previous proof inspection"
  IO.FS.writeFile (records/"laws-first.txt") (← IO.FS.readFile (records/"laws.txt"))
  guard "terminal-capture-proof-audit" #["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "kernel-axioms",(records/"laws.txt").toString,(records/"laws.stderr").toString,"/usr/bin/env",
    "LEAN_PATH="++(root/"build/lib").toString++":"++(compiler/"lib/lean").toString,
    (compiler/"bin/lean").toString,"-j1","-M2048",(root/"laws.lean").toString]

def retainTraffic : IO Unit := do
  idle
  discard <| finished "terminal-capture-traffic"
  for action in ["retain-at","profiles-at"] do
    IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
      (project/"tools/research/SharedTrafficStudy.lean").toString,action,
      root.toString,records.toString,"terminal-capture-traffic"])
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/SharedTrafficStudy.lean").toString,"reuse-at",records.toString]
  let result ← read (records/"result.json")
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
  discard <| finished "terminal-capture-traffic"
  discard <| finished "terminal-capture-proof-audit"
  check (!(← (records/"retired.json").pathExists)) "preserve retirement record"
  let result ← read (records/"result.json")
  check ((← IO.ofExcept (result.getObjValAs? (Array Json) "queries")).size == 18 &&
    (← (records/"terminal-events.json").pathExists) &&
    (← (records/"recovered-answer.json").pathExists)) "retain actual source, response and fault evidence first"
  for query in ← IO.ofExcept (result.getObjValAs? (Array Json) "queries") do
    let body : String ← IO.ofExcept (query.getObjValAs? _ "retainedBody")
    let output : String ← IO.ofExcept (query.getObjValAs? _ "retainedStdout")
    check ((query.getObjValD "delivery").getObjValD "bodySha256" == toJson (← hash (.mk body))) "retained body changed"
    check ((query.getObjValD "timing").getObjValD "stdoutSha256" == toJson (← hash (.mk output))) "retained output changed"
  let mut guards := []
  for tag in ["terminal-capture-build","terminal-capture-checked-build","terminal-capture-checks-build",
      "terminal-capture-checks-checked-build","terminal-capture-boundaries","terminal-capture-fault",
      "terminal-capture-proof-audit","terminal-capture-traffic"] do
    let value ← read (base/(tag++".guard.json"))
    check (value.getObjValD "state" == toJson "finished" &&
      value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "a candidate guard is still live"
    guards := guards++[(tag,value)]
  write (records/"guards.json") (Json.mkObj guards)
  let targets := #[root/"run",root/"fault",root/"boundaries",root/"checks-build",root/"helper-lib",
    root/"tmp",root/"launcher.lean",root/"laws.lean"]
  let retiredPath := fun (text : String) => targets.any fun target =>
    text == target.toString || text.startsWith (target.toString++"/")
  let builds := #[root/"build",parent/"build",practical/"block-seek/build",practical/"build",
    practical/"independent-maintenance/build",practical/"coordinated-warm/build",base/"canonical-decoder-runtime/build"]
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
  check (!(processes.splitOn "\n").any fun line => targets.any (fun target => line.contains target.toString)) "ended artifact still belongs to a process"
  let mut removed := (0,0)
  for path in targets do
    if !(← path.pathExists) then continue
    let next ← remove path
    removed := (removed.1+next.1,removed.2+next.2)
  for (path,digest) in protectedRuntimes do check ((← hash path) == digest) "protected runtime changed"
  for (name,digest) in protectedFiles do check ((← hash (System.FilePath.mk source/name)) == digest) "original changed during retirement"
  let mut output := #[]
  for entry in ← records.readDir do
    if !(entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr") then continue
    let bytes ← IO.FS.readBinFile entry.path
    output := output.push (Json.mkObj [("name",toJson entry.fileName),("bytes",toJson bytes.size),
      ("sha256",toJson (← hash entry.path)),("retained",toJson (!bytes.isEmpty))])
    if bytes.isEmpty then IO.FS.removeFile entry.path
  write (records/"service-output.json") (toJson output)
  write (records/"retired.json") (Json.mkObj [("files",toJson removed.1),("logicalBytes",toJson removed.2),
    ("archiveCreated",toJson false),("sourceAndRuntimeHashesUnchanged",toJson true),
    ("nativeInputsAndInterfacesOutsideRetiredTargets",toJson true),("candidateProductRetained",toJson true)])
end TerminalCaptureStudy
def main : List String → IO Unit
  | ["prepare"] => TerminalCaptureStudy.prepare
  | ["seal"] => TerminalCaptureStudy.sealPatch
  | ["audit"] => TerminalCaptureStudy.audit
  | ["retry-build"] => TerminalCaptureStudy.retryBuild
  | ["install"] => TerminalCaptureStudy.install
  | ["prepare-checks"] => TerminalCaptureStudy.prepareChecks
  | ["audit-checks"] => TerminalCaptureStudy.auditChecks
  | ["retry-checks"] => TerminalCaptureStudy.retryChecks
  | ["refresh-checks"] => TerminalCaptureStudy.refreshChecks
  | ["boundaries"] => TerminalCaptureStudy.runCheck false
  | ["fault"] => TerminalCaptureStudy.runCheck true
  | ["retain-checks"] => TerminalCaptureStudy.retainChecks
  | ["traffic"] => TerminalCaptureStudy.traffic
  | ["proof-audit"] => TerminalCaptureStudy.proofAudit
  | ["retain-traffic"] => TerminalCaptureStudy.retainTraffic
  | ["retire"] => TerminalCaptureStudy.retire
  | _ => throw (IO.userError "TerminalCaptureStudy prepare|seal|audit")
