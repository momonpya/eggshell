import tools.research.StudyLocal
open Lean StudyLocal
namespace BoundProductStudy

def practical := base/"practical-runtime"
def parent := practical/"independent-maintenance"
def root := practical/"bound-product"
def records := project/"docs/practical-runtime/bound-product"
def fixedProduct := "bd9096c4378e207b22e1ad48de5906f6967cf7dbbcb1c12722bfc6ce6bb25707"

def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← (records/"plan.json").pathExists)) "fresh bound installation required"
  check ((← hash (parent/"build/StudyMain")) == fixedProduct) "fixed product changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"prefix").toString,(root/"prefix").toString]
  write (records/"plan.json") (Json.mkObj [("runtimeSha256",toJson fixedProduct),
    ("productCoreChanged",toJson false),("registeredCommands",toJson true),
    ("writers",toJson (4 : Nat)),("readers",toJson (6 : Nat)),("waves",toJson (3 : Nat)),
    ("manualKeepUsed",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "bound-product-installation" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/BoundProductStudy.lean").toString,"__bind"]

def bindInstallation : IO Unit := do
  check ((← hash (parent/"build/StudyMain")) == fixedProduct) "product changed before binding"
  if !(← (root/"helper-lib/Eggshell/Install.olean").pathExists) then
    discard <| command "/bin/cp" #["-cR",(parent/"build/lib").toString++"/.",(root/"helper-lib").toString]
  let library := (root/"helper-lib").toString++":"++(parent/"build/lib").toString++":"++(compiler/"lib/lean").toString
  let helper := root/"helper-lib/tools/research/StudyLaunchers.olean"
  IO.FS.createDirAll helper.parent.get!
  let checked ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M2048","-DwarningAsError=true","-o",helper.toString,
      (project/"tools/research/StudyLaunchers.lean").toString]
    env := #[("LEAN_PATH",some library)]}
  unless checked.stdout.isEmpty && checked.stderr.isEmpty do
    IO.FS.writeFile (records/"binding-compile.txt") (checked.stdout++checked.stderr)
  check (checked.exitCode == 0) "launcher checker failed to compile"
  let runner := root/"launcher-main.lean"
  IO.FS.writeFile runner "import tools.research.StudyLaunchers\ndef main := Eggshell.Research.StudyLaunchers.cliMain\n"
  let bound ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M2048","--run",runner.toString,"bind",(root/"prefix").toString,
      (practical/"coordinated-warm/prefix").toString,(records/"launcher-binding.json").toString]
    env := #[("LEAN_PATH",some library)]}
  unless bound.stdout.isEmpty && bound.stderr.isEmpty do
    IO.FS.writeFile (records/"binding-result.txt") (bound.stdout++bound.stderr)
  check (bound.exitCode == 0) "isolated product launcher binding failed"
  let previous ← read (parent/"installation.json")
  let mut files := #[]
  for file in ← IO.ofExcept (previous.getObjValAs? (Array Json) "pluginFiles") do
    let old ← IO.ofExcept (file.getObjValAs? String "path")
    let sourceRoot := (parent/"prefix").toString++"/"
    check (old.startsWith sourceRoot) "plugin artifact outside fixed prefix"
    let path := root/"prefix"/(old.drop sourceRoot.length |>.toString)
    files := files.push (file.setObjVal! "path" (toJson path.toString)
      |>.setObjVal! "sha256" (toJson (← hash path)))
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (previous.getObjValD "environment"))
  let updates := #[("EGGSHELL_PREFIX",some (root/"prefix").toString),
    ("PLUGIN_ROOT",some (root/"prefix/plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (root/"run/data").toString),("TMPDIR",some (root/"tmp").toString)]
  let env := env.filter (fun row => !updates.any (·.1 == row.1)) ++ updates
  let runtime := root/"prefix/libexec/eggshell"
  check ((← IO.FS.realPath runtime) == (← IO.FS.realPath (parent/"build/StudyMain")) &&
    (← hash runtime) == fixedProduct) "admitted launchers do not select the fixed product"
  IO.FS.createDirAll (root/"tmp")
  let installation := previous
    |>.setObjVal! "runtime" (Json.mkObj [("path",toJson runtime.toString),("sha256",toJson fixedProduct)])
    |>.setObjVal! "pluginRoot" (toJson (root/"prefix/plugins/eggshell").toString)
    |>.setObjVal! "pluginFiles" (toJson files)
    |>.setObjVal! "environment" (toJson env)
  write (root/"installation.json") installation
  write (records/"installation.json") installation
  let inherited := practical/"coordinated-warm/prefix/libexec/eggshell"
  let correction := Json.mkObj [("oldDeclaredProductSha256",toJson fixedProduct),
    ("actualHookClientSha256",toJson (← hash inherited)),
    ("actualFrontendAndPublisherSha256",toJson fixedProduct),
    ("oldClientLaunchers",toJson #[(parent/"prefix/plugins/eggshell/bin/egg").toString,
      (parent/"prefix/plugins/eggshell/bin/eggshelld").toString]),
    ("singleRuntimeForAllProcessesWasUnverified",toJson true),
    ("allNativeSourceFunctionalityPreviouslyTested",toJson false)]
  write (records/"previous-binding.json") correction

def retryBinding : IO Unit := do
  idle
  let previous ← read (base/"bound-product-installation.guard.json")
  check (previous.getObjValD "state" == toJson "finished" &&
    previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous binding check remains live"
  write (records/"binding-attempt.json") (Json.mkObj [("guard",previous),
    ("error",toJson (← IO.FS.readFile (records/"binding-compile.txt"))),
    ("actualHookCalls",toJson (0 : Nat))])
  guard "bound-product-installation-checked" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/BoundProductStudy.lean").toString,"__bind"]

def run (bindingTag : String) : IO Unit := do
  idle
  discard <| finished bindingTag
  let installation ← read (root/"installation.json")
  let binding ← read (records/"launcher-binding.json")
  check (binding.getObjValD "newBindingVerified" == toJson true) "actual launcher binding unverified"
  check ((← hash (root/"prefix/libexec/eggshell")) == fixedProduct) "bound runtime changed"
  let source ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let seed ← read (practical/"cohort/study/seed-1/plan.json")
  let input := Json.mkObj [("installation",installation),("original",source.getObjValD "source"),
    ("originalFiles",source.getObjValD "sourceFiles"),("workspace",seed.getObjValD "workspace"),
    ("definitions",← read (practical/"interrupted-recovery/definitions.json")),("preparedReference",Json.null),
    ("activeReaders",toJson (3 : Nat)),("llvmReaders",toJson (3 : Nat)),("registered",toJson true),
    ("observeMaintenance",toJson false)]
  check (!(← (root/"input.json").pathExists)) "preserve admitted traffic"
  write (root/"input.json") input
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := env.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  guard "bound-product-traffic" (#["/usr/bin/env"] ++ unset.flatMap (fun key => #["-u",key]) ++ assigned ++
    #[(parent/"build/StudyMain").toString,"shared-traffic",(root/"input.json").toString,(root/"run").toString])

def retain : IO Unit := do
  idle
  discard <| finished "bound-product-traffic"
  for action in ["retain-at","profiles-at"] do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
      (project/"tools/research/SharedTrafficStudy.lean").toString,action,
      root.toString,records.toString,"bound-product-traffic"]
  let result ← read (records/"result.json")
  let mut events := #[]
  for session in ← (root/"run/calls").readDir do
    for call in ← session.path.readDir do
      if !["stop","compact-start","post-compact","interrupt","end"].contains call.fileName then continue
      let timing ← read (call.path/"record.json")
      let stdout ← IO.FS.readFile (call.path/"stdout")
      check ((← IO.ofExcept (Json.parse stdout)) == Json.mkObj []) "terminal event returned an incomplete notice"
      check (timing.getObjValD "stdoutSha256" == toJson (← hash (call.path/"stdout"))) "terminal output changed"
      events := events.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("timing",timing),("registration",← read (call.path/"registration.json"))])
  check (events.size == 88) "retain all Stops and reader lifecycle events"
  write (records/"terminal-events.json") (toJson events)
  write (records/"baseline.json") (Json.mkObj [("answers",← read (root/"run/baseline-auto-answers.json")),
    ("synapses",← read (root/"run/baseline-facts.json"))])
  let waves ← IO.ofExcept (result.getObjValAs? (Array Json) "summary")
  let compact := waves.map fun wave => Json.mkObj [("wave",wave.getObjValD "wave"),
    ("elapsedMs",wave.getObjValD "elapsedMs"),("maxReaderMs",wave.getObjValD "maxHookMs"),
    ("semanticCompleted",wave.getObjValD "semanticCompleted"),
    ("observations",(wave.getObjValD "census").getObjValD "count"),("answers",wave.getObjValD "automaticAnswers")]
  let summary := Json.mkObj [("waves",toJson compact),("terminalEvents",toJson events.size),
    ("peakRssKiB",(result.getObjValD "guard").getObjValD "sampledPeakRssKiB"),
    ("allProcessLaunchersBound",toJson true),("paidMatchedComparisons",toJson (0 : Nat)),("adopted",toJson false)]
  write (records/"summary.json") summary
  IO.println summary.compress

def checkAdmission : IO Unit := do
  idle
  discard <| finished "bound-product-traffic"
  guard "bound-product-admission-check" #["/usr/bin/env",
    "LEAN_PATH="++(root/"helper-lib").toString++":"++(compiler/"lib/lean").toString,
    (compiler/"bin/lean").toString,"-j1","-M2048","-DwarningAsError=true",
    (project/"tools/research/StudySeedChecks.lean").toString]

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

def retire : IO Unit := do
  idle
  discard <| finished "bound-product-traffic"
  let admission ← finished "bound-product-admission-check"
  write (records/"admission.json") (Json.mkObj [("guard",admission),
    ("checkerSha256",toJson (← hash (project/"tools/research/StudyLaunchers.lean"))),
    ("admissionSourceSha256",toJson (← hash (project/"tools/research/StudySeedChecks.lean"))),
    ("kernelChecked",toJson true),("existingNativeControllersRebuilt",toJson false)])
  let entryRecords := project/"docs/candidates/product-entry"
  write (entryRecords/"guards.json") (Json.mkObj [("build",← finished "product-entry-build"),
    ("startup",← finished "product-entry-startup")])
  check (!(← (records/"retired.json").pathExists)) "preserve previous retirement"
  let result ← read (records/"result.json")
  let queries ← IO.ofExcept (result.getObjValAs? (Array Json) "queries")
  check (queries.size == 18 && (← (records/"terminal-events.json").pathExists) &&
    (← (records/"hook-profiles.json").pathExists)) "actual hook records must be retained first"
  for query in queries do
    let body : String ← IO.ofExcept (query.getObjValAs? _ "retainedBody")
    let response : String ← IO.ofExcept (query.getObjValAs? _ "retainedStdout")
    check ((query.getObjValD "delivery").getObjValD "bodySha256" == toJson (← hash (.mk body))) "retained body changed"
    check ((query.getObjValD "timing").getObjValD "stdoutSha256" == toJson (← hash (.mk response))) "retained stdout changed"
  let original ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let source : String ← IO.ofExcept (original.getObjValAs? _ "source")
  let files : Array (String × String) ← IO.ofExcept (original.getObjValAs? _ "sourceFiles")
  let artifacts := #[parent/"build/StudyMain",practical/"coordinated-warm/build/StudyMain",
    practical/"build/StudyMain",base/"canonical-decoder-runtime/build/StudyMain",root/"prefix/libexec/eggshell"]
  let hashes ← artifacts.mapM fun path => do pure (path,← hash path)
  for (name,digest) in files do check ((← hash (System.FilePath.mk source/name)) == digest) "protected source changed"
  let targets := #[root/"run",root/"tmp",root/"helper-lib",root/"launcher-main.lean",practical/"product-entry"]
  for directory in [parent/"build",practical/"coordinated-warm/build",practical/"build",base/"canonical-decoder-runtime/build"] do
    for line in (← IO.FS.readFile (directory/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      if path.isAbsolute then
        let actual := (← IO.FS.realPath path).toString
        check (!(targets.any (fun target => actual == target.toString || actual.startsWith (target.toString++"/"))))
          "a current native input belongs to an ended trial"
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any fun line => line.trimAscii.toString.startsWith (base.toString++"/"))
    "native service or client remains live"
  let model := (← IO.FS.realPath (root/"prefix/share/eggshell/minilm")).toString
  check (!(targets.any fun target => model.startsWith (target.toString++"/"))) "model belongs to ended trial"
  let mut removed := (0,0)
  for path in targets do
    if !(← path.pathExists) then continue
    let part ← remove path
    removed := (removed.1+part.1,removed.2+part.2)
  for (path,digest) in hashes do check ((← hash path) == digest) "protected runtime changed"
  for (name,digest) in files do check ((← hash (System.FilePath.mk source/name)) == digest) "source changed during retirement"
  write (records/"retired.json") (Json.mkObj [("files",toJson removed.1),("logicalBytes",toJson removed.2),
    ("archiveCreated",toJson false),("sourceAndRuntimeHashesUnchanged",toJson true),
    ("boundPrefixRetained",toJson true),("unusedProductEntryDeleted",toJson true)])
  write (entryRecords/"retired.json") (Json.mkObj [("directory",toJson (practical/"product-entry").toString),
    ("deleted",toJson (!(← (practical/"product-entry").pathExists))),
    ("record",toJson (records/"retired.json").toString),("archiveCreated",toJson false)])

def main : List String → IO Unit
  | ["prepare"] => prepare
  | ["__bind"] => bindInstallation
  | ["retry-bind"] => retryBinding
  | ["run",bindingTag] => run bindingTag
  | ["retain"] => retain
  | ["check-admission"] => checkAdmission
  | ["retire"] => retire
  | _ => throw (IO.userError "BoundProductStudy prepare|run")
end BoundProductStudy
def main := BoundProductStudy.main
