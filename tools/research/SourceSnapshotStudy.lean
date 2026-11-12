import tools.research.StudyLocal
open Lean StudyLocal
namespace SourceSnapshotStudy
def parent := base/"practical-runtime/request-socket"
def root := base/"practical-runtime/source-snapshot"
def records := project/"docs/candidates/source-snapshot"
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh source-snapshot candidate required"
  check ((← hash (parent/"gateway-build/StudyMain")) == "6ece69c62bb845d7c955a681450fe873f58b75c6e208bc28ede708b47d6e70ed")
    "connected project-service parent changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  copyLocalArtifacts (parent/"gateway-build") (root/"build")
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"gateway-build/StudyMain"))),
    ("purpose",toJson "mount a captured existing native DB as a read-only project without rebuilding its work graph"),
    ("immutableSource",toJson "copy exactly the committed prefix from the pinned descriptor; retain original head and byte values"),
    ("cacheAuthority",toJson "one checked project manifest; source membership instead of conflating project naming and source authority"),
    ("certification",toJson "imported source stays read-only; advisory retrieval does not create completion authority"),
    ("modelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def build : IO Unit := do
  idle
  IO.FS.writeFile (root/"source/Eggshell/DB/ProjectCacheScope.lean")
    (← IO.FS.readFile (project/"tools/research/source-snapshot/ProjectCacheScope.lean"))
  let settings := (← read (parent/"gateway-build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"gateway-build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"gateway-build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"gateway-build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"gateway-build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.StudyMain")
  write (root/"settings.json") settings
  guard "source-snapshot-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def checkedBuild : IO Unit := do
  idle
  let stopped ← read (base/"source-snapshot-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" == toJson (1 : Nat)) "retain the stopped membership proof rejection"
  write (records/"membership-rejection.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"build/Eggshell_DB_ProjectCacheScope-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"build/Eggshell_DB_ProjectCacheScope-lean.stderr"))),
    ("sourceSha256",toJson (← hash (root/"source/Eggshell/DB/ProjectCacheScope.lean"))),
    ("databaseOrModelStarted",toJson false)])
  IO.FS.writeFile (root/"source/Eggshell/DB/ProjectCacheScope.lean")
    (← IO.FS.readFile (project/"tools/research/source-snapshot/ProjectCacheScope.lean"))
  guard "source-snapshot-membership-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def exactMembershipBuild : IO Unit := do
  idle
  let stopped ← read (base/"source-snapshot-membership-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" == toJson (1 : Nat)) "retain the stopped Boolean equality proof"
  write (records/"equality-rejection.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"build/Eggshell_DB_ProjectCacheScope-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"build/Eggshell_DB_ProjectCacheScope-lean.stderr"))),
    ("reason",toJson "use decidable head equality, without assuming a LawfulBEq instance for PageMap.Head"),
    ("databaseOrModelStarted",toJson false)])
  IO.FS.writeFile (root/"source/Eggshell/DB/ProjectCacheScope.lean")
    (← IO.FS.readFile (project/"tools/research/source-snapshot/ProjectCacheScope.lean"))
  guard "source-snapshot-exact-membership-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def prepareChecks : IO Unit := do
  idle
  write (records/"build.guard.json") (← finished "source-snapshot-exact-membership-build")
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",
    (root/"build").toString,(records/"native.json").toString]
  check ((← read (records/"native.json")).getObjValD "consistent" == toJson true) "product native closure is inconsistent"
  IO.FS.writeFile (root/"source/tools/research/SourceSnapshotChecks.lean")
    (← IO.FS.readFile (project/"tools/research/SourceSnapshotChecks.lean"))
  copyLocalArtifacts (root/"build") (root/"checks-build")
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"checks-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.SourceSnapshotChecks")
  write (root/"checks-settings.json") settings
  guard "source-snapshot-checks-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"checks-settings.json").toString]
def checks : IO Unit := do
  idle
  write (records/"checks-build.guard.json") (← finished "source-snapshot-checks-build")
  guard "source-snapshot-checks" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    (root/"checks-build/StudyMain").toString,"checks",(root/"checks").toString,(records/"checks.json").toString]
def audit (arguments : Array String) : IO Unit := do
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
def changed := #["DB/ProjectCacheScope","ExplicitWarm","PluginCli","ProjectPublication","ProjectSources",
  "ProjectStore","PublicationWire"]
def renderPatch : IO Unit := do
  idle
  let mut patch := ""
  for name in changed do
    let relative := "Eggshell/"++name++".lean"
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/"++relative,
      "-L","b/"++relative,(parent/"source"/relative).toString,(root/"source"/relative).toString]}
    check (diff.exitCode == 1) "declared source snapshot change is missing or unreadable"
    patch := patch++diff.stdout
  IO.FS.writeFile (records/"candidate.patch") patch
def prepareMixed : IO Unit := do
  idle
  write (records/"checks.guard.json") (← finished "source-snapshot-checks")
  audit #["inspect",(root/"checks-build").toString,(records/"checks-native.json").toString]
  audit #["component-sources",(root/"build").toString,(root/"checks-build").toString,
    (records/"checks-sources.json").toString,"Eggshell.ProjectSources","Eggshell.ProjectStore",
    "Eggshell.ProjectPublication","Eggshell.DB.ProjectCacheScope","Eggshell.DB.PageMap"]
  let names := changed
  let mut claims := #[]
  for name in names do
    let relative := "Eggshell/"++name++".lean"
    let path := root/"source"/relative
    claims := claims.push ("@"++(← hash path)++":"++path.toString)
  renderPatch
  audit (#["compare-sources",(parent/"gateway-build").toString,(root/"build").toString,
    (records/"sources.json").toString]++names.map ("Eggshell."++·.replace "/" ".")++claims)
  check ((← IO.FS.readFile (root/"source/tools/research/DelegatedConnectionMixed.lean")) ==
    (← IO.FS.readFile (project/"tools/research/DelegatedConnectionMixed.lean"))) "mixed native entry changed"
  check ((← IO.FS.readFile (root/"source/tools/research/MixedChatChecks.lean")) ==
    (← IO.FS.readFile (parent/"source/tools/research/MixedChatChecks.lean"))) "mixed lifecycle oracle changed"
  copyLocalArtifacts (root/"build") (root/"mixed-build")
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"mixed-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.DelegatedConnectionMixed")
  write (root/"mixed-settings.json") settings
  guard "source-snapshot-mixed-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"mixed-settings.json").toString]
def bind : IO Unit := do
  idle
  write (records/"mixed-build.guard.json") (← finished "source-snapshot-mixed-build")
  if !(← (records/"mixed-native.json").pathExists) then
    audit #["inspect",(root/"mixed-build").toString,(records/"mixed-native.json").toString]
  else
    check ((← read (records/"mixed-native.json")).getObjValD "consistent" == toJson true)
      "retained mixed native closure is inconsistent"
  audit #["common-sources",(root/"build").toString,(root/"mixed-build").toString,(records/"mixed-sources.json").toString]
  check (!(← (root/"prefix").pathExists)) "fresh source snapshot prefix required"
  discard <| command "/bin/cp" #["-cR",(parent/"prefix").toString,(root/"prefix").toString]
  let backend := root/"prefix/libexec/eggshell"
  check ((← backend.symlinkMetadata).type == .symlink) "unexpected copied runtime binding"
  IO.FS.removeFile backend
  discard <| command "/bin/ln" #["-s",(root/"build/StudyMain").toString,backend.toString]
  guard "source-snapshot-bind" #[(root/"mixed-build/StudyMain").toString,"bind",
    (root/"prefix").toString,(parent/"prefix").toString,(records/"launcher-binding.json").toString]
def growth : IO Unit := do
  idle
  write (records/"bind.guard.json") (← finished "source-snapshot-bind")
  let before ← read (parent/"connection-installation.json")
  let mut files := #[]
  for artifact in ← IO.ofExcept (before.getObjValAs? (Array Json) "pluginFiles") do
    let old ← IO.ofExcept (artifact.getObjValAs? String "path")
    let inherited := (parent/"prefix").toString++"/"
    check (old.startsWith inherited) "plugin asset escaped inherited prefix"
    let path := root/"prefix"/(old.drop inherited.length |>.toString)
    let digest ← hash path
    unless ["plugins/eggshell/bin/egg","plugins/eggshell/bin/eggshelld"].any (path.toString.endsWith ·) do
      check (artifact.getObjValD "sha256" == toJson digest) "unrelated plugin asset changed"
    files := files.push (artifact.setObjVal! "path" (toJson path.toString) |>.setObjVal! "sha256" (toJson digest))
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (before.getObjValD "environment"))
  let updates := #[("EGGSHELL_PREFIX",some (root/"prefix").toString),
    ("PLUGIN_ROOT",some (root/"prefix/plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (root/"growing/data").toString),("TMPDIR",some (root/"tmp").toString)]
  IO.FS.createDirAll (root/"tmp")
  let environment := environment.filter (fun row => !updates.any (·.1 == row.1))++updates
  let installed := before
    |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (root/"prefix/libexec/eggshell").toString),
      ("sha256",toJson (← hash (root/"build/StudyMain")))])
    |>.setObjVal! "hookClient" (Json.mkObj [("path",toJson (root/"prefix/libexec/eggshell-hook").toString),
      ("sha256",toJson (← hash (root/"prefix/libexec/eggshell-hook")))])
    |>.setObjVal! "pluginRoot" (toJson (root/"prefix/plugins/eggshell").toString)
    |>.setObjVal! "pluginFiles" (toJson files)
    |>.setObjVal! "environment" (toJson environment)
  write (root/"installation.json") installed
  write (records/"installation.json") installed
  let unsets := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let values := environment.filterMap fun (key,value) => value.map (fun item => key++"="++item)
  write (records/"growth-plan.json") (Json.mkObj [("installation",installed),
    ("parentOracle",toJson "identical delegated fourteen-client mixed lifecycle and growth"),
    ("projects",toJson (2 : Nat)),("maxClients",toJson (14 : Nat)),
    ("manualKeepOrWarm",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "source-snapshot-growth" (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "snapshot-growth",(records/"growth.stdout").toString,(records/"growth.stderr").toString,"/usr/bin/env"]++
    unsets.flatMap (fun key => #["-u",key])++values++#[(root/"mixed-build/StudyMain").toString,"growth",
      (root/"installation.json").toString,(root/"growing").toString])
def retain : IO Unit := do
  idle
  let completed ← finished "source-snapshot-growth"
  write (records/"growth.guard.json") completed
  let run := root/"growing"
  let mut calls := #[]
  for session in ← (run/"calls").readDir do
    for call in ← session.path.readDir do
      if !(← (call.path/"record.json").pathExists) then continue
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("record",← read (call.path/"record.json")),("input",toJson (← IO.FS.readFile (call.path/"stdin"))),
        ("stdout",toJson (← IO.FS.readFile (call.path/"stdout"))),("stderr",toJson (← IO.FS.readFile (call.path/"stderr")))])
  let mut metadata := #[]
  for entry in ← run.readDir do
    if entry.fileName.endsWith ".json" then metadata := metadata.push (entry.fileName,← read entry.path)
  write (records/"growth-records.json") (Json.mkObj [("guard",completed),("calls",toJson calls),
    ("metadata",toJson metadata),("observer",← read (records/"mixed-sources.json")),
    ("fixtureSource",← read (root/"mixed-build/tools_research_MixedChatChecks.source"))])
  let result ← read (run/"result.json")
  check (result.getObjValD "finalOriginalObservations" == toJson (75 : Nat) &&
    result.getObjValD "finalWriterTurns" == toJson (25 : Nat)) "mixed source capture did not reach the final wave"
  let summary ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString,
    args := #["-j1","-M768","--run",(project/"tools/research/NativeMixedSummary.lean").toString,
      (records/"growth-records.json").toString,(records/"summary.json").toString],
    env := #[("LEAN_PATH",some ((base/"study-local-lib").toString++":"++(root/"mixed-build/lib").toString))]}
  check (summary.exitCode == 0) (summary.stdout++summary.stderr)
  let installation ← read (root/"installation.json")
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let unsets := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let values := environment.filterMap fun (key,value) => value.map (fun item => key++"="++item)
  guard "source-snapshot-storage" (#["/usr/bin/env"]++unsets.flatMap (fun key => #["-u",key])++values++
    #[(root/"mixed-build/StudyMain").toString,"inspect",run.toString,(records/"storage.json").toString])
def proofs (corrected : Bool := false) : IO Unit := do
  idle
  write (records/"storage.guard.json") (← finished "source-snapshot-storage")
  if corrected then
    let rejected ← read (base/"source-snapshot-proofs.guard.json")
    check (rejected.getObjValD "state" == toJson "finished" &&
      rejected.getObjValD "ownedPids" == toJson (#[] : Array Nat) && rejected.getObjValD "exitCode" == toJson (1 : Nat))
      "only correct the stopped kernel-audit elaboration"
    write (records/"proofs-rejection.json") (Json.mkObj [("guard",rejected),
      ("stdout",toJson (← IO.FS.readFile (records/"proofs.stdout"))),
      ("stderr",toJson (← IO.FS.readFile (records/"proofs.stderr"))),
      ("reason",toJson "normalize the derived SourceKind comparison definitionally before eliminating false=true"),
      ("productChanged",toJson false),("modelCalls",toJson (0 : Nat))])
  guard (if corrected then "source-snapshot-checked-proofs" else "source-snapshot-proofs") #["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "source-snapshot-proof",(records/"proofs.stdout").toString,(records/"proofs.stderr").toString,
    "/usr/bin/env","LEAN_PATH="++(root/"build/lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M1536","-DwarningAsError=true",
    (project/"tools/research/SourceSnapshotAudit.lean").toString]
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
def finalizeEvidence : IO Unit := do
  idle
  write (records/"proofs.guard.json") (← finished "source-snapshot-checked-proofs")
  let stdout ← IO.FS.readFile (records/"proofs.stdout")
  let stderr ← IO.FS.readFile (records/"proofs.stderr")
  check (stderr.isEmpty && !stdout.contains "error:" && !stdout.contains "sorryAx" &&
    !stdout.contains "Lean.trustCompiler" && !stdout.contains "Lean.ofReduceBool" &&
    (stdout.splitOn "\n" |>.filter (!·.isEmpty)).length == 5) "snapshot kernel audit has not passed"
  write (records/"proofs.json") (Json.mkObj [("stdout",toJson stdout),("stderr",toJson stderr),
    ("sourceSha256",toJson (← hash (project/"tools/research/SourceSnapshotAudit.lean"))),
    ("standardAxiomsOnly",toJson true),("actualOwnerFieldChecked",toJson true)])
  let summary ← read (records/"summary.json")
  check (summary.getObjValD "wholeWorkloadSucceeded" == toJson true &&
    summary.getObjValD "queries" == toJson (72 : Nat) && summary.getObjValD "semanticCompleted" == toJson (72 : Nat) &&
    summary.getObjValD "requiredAppearances" == summary.getObjValD "deliveredAppearances") "mixed workload is incomplete"
  let storage ← read (records/"storage.json")
  let inventory := storage.getObjValD "inventory"
  let originals : Array Json ← IO.ofExcept (inventory.getObjValAs? _ "native")
  let answers : Array String ← IO.ofExcept (inventory.getObjValAs? _ "answers")
  let fields : Array Json ← IO.ofExcept (storage.getObjValAs? _ "rawFields")
  let frozen : Array (String × Json) ← IO.ofExcept (fromJson? (← read (root/"growing/growth-required-3.json")))
  let queries : Array Json ← IO.ofExcept ((← read (root/"growing/growth-final-readers.json")).getObjValAs? _ "rows")
  let mut required : Array Json := #[]
  for row in queries do
    let groups : Array String ← IO.ofExcept (row.getObjValAs? _ "groups")
    let actual : Array Json ← IO.ofExcept (row.getObjValAs? _ "required")
    let expected := (frozen.filter (fun item => groups.contains item.1)).map (·.2)
    check (actual.size == expected.size && expected.all actual.contains) "final query changed its frozen project-specific requirements"
    for item in actual do if !required.contains item then required := required.push item
  check (storage.getObjValD "originalsUnchanged" == toJson true && storage.getObjValD "readOnly" == toJson true &&
    originals.size == 75 && answers.size == 25 && fields.size == 50 &&
    fields.all (fun field => field.getObjValD "present" == toJson true) &&
    frozen.size == 50 && required.size == 50 && frozen.all (fun item => required.contains item.2)) "stored/frozen evidence census differs"
  write (records/"storage-summary.json") (Json.mkObj [("nativeOriginals",toJson originals.size),
    ("answers",toJson answers.size),("storedFields",toJson fields.size),("distinctFrozenRequirements",toJson frozen.size),
    ("finalQueriesMatchFrozenRequirements",toJson true),("originalsUnchanged",toJson true),
    ("verifiedIntervals",inventory.getObjValD "timedObservations"),
    ("unknownIntervals",toJson ((← IO.ofExcept (inventory.getObjValAs? (Array Json) "withoutVerifiedInterval")).size)),
    ("wholeRunStatusSource",toJson "growth.guard.json and independent summary.json"),
    ("legacyRawOriginalRunPassedIsNotRunStatus",toJson true)])
  write (records/"storage.json") storage
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "source-snapshot-" && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "source snapshot stage remains live"
      guards := guards.push (entry.fileName,value)
  write (records/"guard-records.json") (toJson guards)
  let mut inputs : Array (String × String) := #[]
  for line in (← IO.FS.readFile (root/"build/runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    if path.endsWith ".o" then inputs := inputs.push (path,← hash (.mk path))
  for path in [root/"build/StudyMain",parent/"gateway-build/StudyMain",root/"prefix/libexec/eggshell-hook"] do
    inputs := inputs.push (path.toString,← hash path)
  write (records/"protected-native-inputs.json") (toJson inputs)
  let mut targets := #[root/"checks",root/"growing",root/"checks-build",root/"mixed-build",root/"tmp"]
  for entry in ← (root/"build").readDir do
    if entry.fileName.endsWith ".c" then targets := targets.push entry.path
    else if entry.fileName.endsWith ".o" && !(inputs.any (·.1 == entry.path.toString)) then
      for extension in ["o","source","dependencies"] do
        let path := entry.path.withExtension extension
        if ← path.pathExists then targets := targets.push path
  check (targets.all fun target => !(inputs.any fun (path,_) =>
    path == target.toString || path.startsWith (target.toString++"/"))) "cleanup overlaps a protected native input"
  let mut files := 0
  let mut logicalBytes := 0
  for target in targets do
    let counts ← remove target
    files := files+counts.1
    logicalBytes := logicalBytes+counts.2
  for (path,digest) in inputs do check ((← hash (.mk path)) == digest) "cleanup changed a protected native input"
  for (name,field) in [("growth.stdout","stdout"),("growth.stderr","stderr")] do
    let bytes ← IO.FS.readFile (records/name)
    if bytes.isEmpty then IO.FS.removeFile (records/name)
    else if field == "stderr" then throw (IO.userError "successful mixed workload wrote stderr")
  for name in ["proofs.stdout","proofs.stderr"] do
    let kept := if name.endsWith "stdout" then stdout else stderr
    check ((← IO.FS.readFile (records/name)) == kept) "compact proof receipt differs"
    IO.FS.removeFile (records/name)
  write (records/"retired.json") (Json.mkObj [("targets",toJson targets),("files",toJson files),
    ("logicalBytes",toJson logicalBytes),("protectedNativeHashesBeforeAndAfter",toJson inputs.size),
    ("archiveCreated",toJson false),("activeProductOriginalAndModelRetained",toJson true)])
  audit #["inspect",(root/"build").toString,(records/"after-cleanup.json").toString]
def review : IO Unit := do
  idle
  let guards : Array (String × Json) ← IO.ofExcept (fromJson? (← read (records/"guard-records.json")))
  let mut removed := #[]
  for (name,tag) in [("build","exact-membership-build"),("checks-build","checks-build"),("checks","checks"),
      ("mixed-build","mixed-build"),("bind","bind"),("storage","storage"),("proofs","checked-proofs")] do
    let path := records/(name++".guard.json")
    let some (_,retained) := guards.find? (·.1 == "source-snapshot-"++tag++".guard.json") |
      throw (IO.userError "collected guard receipt is absent")
    check ((← read path) == retained) "consolidated guard lost original receipt fields"
    IO.FS.removeFile path
    removed := removed.push path.fileName.get!
  let installed ← read (records/"installation.json")
  check ((← read (records/"growth-plan.json")).getObjValD "installation" == installed)
    "predeclared workload lost its actual installation"
  IO.FS.removeFile (records/"installation.json")
  removed := removed.push "installation.json"
  let originalReceipt ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let source : System.FilePath := .mk (← IO.ofExcept (originalReceipt.getObjValAs? String "source"))
  let files : Array (String × String) ← IO.ofExcept (originalReceipt.getObjValAs? _ "sourceFiles")
  for (name,expected) in files do
    check ((← hash (source/name)) == expected) "protected LLVM native original changed"
  write (records/"review.json") (Json.mkObj [("duplicateMetadataRemoved",toJson removed),
    ("consolidatedFieldsVerifiedExactly",toJson true),("protectedOriginal",toJson source.toString),
    ("protectedOriginalFiles",toJson files),("protectedOriginalUnchanged",toJson true),
    ("acceptedSeed",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
end SourceSnapshotStudy
def main : List String → IO Unit
  | ["prepare"] => SourceSnapshotStudy.prepare
  | ["build"] => SourceSnapshotStudy.build
  | ["checked-build"] => SourceSnapshotStudy.checkedBuild
  | ["exact-membership-build"] => SourceSnapshotStudy.exactMembershipBuild
  | ["prepare-checks"] => SourceSnapshotStudy.prepareChecks
  | ["checks"] => SourceSnapshotStudy.checks
  | ["prepare-mixed"] => SourceSnapshotStudy.prepareMixed
  | ["bind"] => SourceSnapshotStudy.bind
  | ["growth"] => SourceSnapshotStudy.growth
  | ["retain"] => SourceSnapshotStudy.retain
  | ["proofs"] => SourceSnapshotStudy.proofs
  | ["checked-proofs"] => SourceSnapshotStudy.proofs true
  | ["finalize"] => SourceSnapshotStudy.finalizeEvidence
  | ["review"] => SourceSnapshotStudy.review
  | ["patch"] => SourceSnapshotStudy.renderPatch
  | _ => throw (IO.userError "SourceSnapshotStudy SUBCOMMAND; see the candidate plan and controller definitions")
