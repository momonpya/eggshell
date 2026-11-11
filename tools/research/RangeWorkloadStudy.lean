import tools.research.StudyLocal
open Lean StudyLocal
namespace RangeWorkloadStudy
def root := base/"range-workload"
def parent := base/"canonical-decoder-runtime"
def records := project/"docs/candidates/range-workload"
def driver := project/"tools/research/RangeWorkloadStudy.lean"

def setup : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "preserve real range workload evidence"
  for name in ["sessions","confirmed-delivery","receipts"] do
    check (!(← (parent/"data"/name).pathExists)) "capture must own its fresh diagnostic state"
  let runtime := parent/"prefix/libexec/eggshell"
  let digest ← hash runtime
  check (digest == "7cc1432d2d3931a26d60e3e614807545e3f6b522737838bdabc1b1c626e657ab") "current native runtime changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
  let trial := root/"trial"
  let config := trial/"config.toml"
  let plugin := parent/"prefix/share/eggshell/codex-plugin"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
  let updates := #[("EGGSHELL_PREFIX",some (parent/"prefix").toString),("PLUGIN_ROOT",some plugin.toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_DATA_ROOT",some (parent/"data").toString),
    ("EGGSHELL_TRACE_SELECTOR_INPUT",some "1"),("EGGSHELL_TRACE_SELECTION_RANGES",none),
    ("EGGSHELL_TRACE_SERVICE_PROFILE",some "1"),("EGGSHELL_TRACE_QUERY_STAGES",none),
    ("EGGSHELL_TRACE_ACTOR_HEAP",none),("EGGSHELL_TRACE_ALLOCATOR",none),("EGGSHELL_HANDOFF_TRACE",none)]
  let environment := environment.filter (fun row => !updates.any (·.1 == row.1)) ++ updates
  let input := original.setObjVal! "runtime" (toJson runtime.toString) |>.setObjVal! "runtimeSha256" (toJson digest)
    |>.setObjVal! "output" (toJson trial.toString) |>.setObjVal! "config" (toJson config.toString)
    |>.setObjVal! "data" (toJson (parent/"data").toString) |>.setObjVal! "plugin" (toJson plugin.toString)
    |>.setObjVal! "environment" (toJson environment) |>.setObjVal! "diagnostic" (toJson true)
    |>.setObjVal! "counts" (toJson (#[(4 : Nat)]))
  write (root/"input.json") input
  write (records/"plan.json") (Json.mkObj [
    ("classificationPreviousTurn",toJson "progress:arbitrary-coordinate incidence and product predicate refinement proved;synthetic native speedup;whole-hook connection not made"),
    ("purpose",toJson "capture actual three-topic range geometry/cues and compare to publication catalogue before integration"),
    ("runtimeSha256",toJson digest),("input",input),
    ("existingMultipartObserver",toJson true),("newProductBuild",toJson false),
    ("threePrimesAndFourDiagnosticClients",toJson true),("performanceComparison",toJson false),
    ("newDbOrCache",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  let unsets := environment.filterMap (fun (key,value) => if value.isNone then some key else none)
    |>.flatMap (fun key => #["-u",key])
  let assignments := environment.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  guard "range-workload-capture" (#["/usr/bin/env"]++unsets++assignments++#[runtime.toString,"owned-selection-capacity",(root/"input.json").toString])

def captureStopped : IO Json := do
  let status ← read (base/"range-workload-capture.guard.json")
  check (status.getObjValD "state" == toJson "finished" && status.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    status.getObjValD "guardTriggered" == toJson false) "capture not terminal or resource stop"
  for role in ["frontend","publisher"] do
    let stopped ← read (root/"trial"/(role++"-shutdown.json"))
    check (stopped.getObjValD "processExited" == toJson true && stopped.getObjValD "daemonExitCode" == toJson (0 : Nat) &&
      stopped.getObjValD "endpointRemoved" == toJson true) "capture service did not stop"
  return status

def prepareNative : IO Unit := do
  idle
  let status ← captureStopped
  let clients ← read (root/"trial/prime.json")
  write (records/"capture.json") (Json.mkObj [("guard",status),("primes",clients),
    ("wholeHookSuccessClaimed",toJson false),("subsequentTopicsNotRunAfterFailure",toJson true),
    ("searchPhaseCompletedButReplyRejected",toJson true),
    ("next",toJson "native inspection of completed private manifest and original encoding bound before any further hook")])
  materialize (parent/"build") (root/"source") (root/"build")
    "tools.research.RangeWorkloadNative" "range-workload-native-settings.json"
  for name in ["FactoredIncidence","RangeIncidence","ProductRangeIncidence"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  guard "range-workload-native-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"range-workload-native-settings.json").toString]

def auditNative : IO Unit := do
  discard <| finished "range-workload-native-build"
  guard "range-workload-native-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",driver.toString,"audit-worker"]

def auditWorker : IO Unit := do
  let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",inspector.toString,
    "inspect",(root/"build").toString,(records/"native.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",inspector.toString,
    "component-sources",(parent/"build").toString,(root/"build").toString,(records/"sources.json").toString,
    "Eggshell.Handoff","Eggshell.CanonicalSourceCache","tools.research.SelectionReceipt"]
  for name in ["FactoredIncidence","RangeIncidence","ProductRangeIncidence","RangeWorkloadNative"] do
    let (actual,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (root/"build"/("tools_research_"++name++".source"))))
    check (actual == (← IO.FS.readFile (project/"tools/research"/(name++".lean"))) && literals.isEmpty) "native real range sources differ"
  write (records/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (root/"build/StudyMain"))),
    ("productChanges",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])

def analyze : IO Unit := do
  discard <| finished "range-workload-native-audit"
  check ((← read (records/"runtime.json")).getObjValD "sha256" == toJson (← hash (root/"build/StudyMain"))) "native real range auditor changed"
  guard "range-workload-analysis" #[(root/"build/StudyMain").toString,(root/"input.json").toString,(records/"report.json").toString]

def observer := root/"observer"

def prepareObserver : IO Unit := do
  idle
  discard <| finished "range-workload-analysis"
  check (!(← observer.pathExists)) "preserve observer candidate"
  let current ← read (parent/"build/build.json")
  check ((current.getObjValD "settings").getObjValD "mainModule" == toJson "tools.research.OwnedSelectionRuntime") "native entry changed"
  materialize (parent/"build") (observer/"source") (observer/"build")
    "tools.research.OwnedSelectionRuntime" "range-workload-observer-settings.json"
  for name in ["SelectionReplyBoundary","SelectionReplyBoundaryCheck"] do
    IO.FS.writeFile (observer/"source/tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  let pool := observer/"source/Eggshell/OperationPool.lean"
  let original ← IO.FS.readFile pool
  let old := "pool.withReplyEncoding job reply (fun reply => pure (toJson reply))"
  check ((original.splitOn old).length == 2) "native search reply boundary changed"
  let patched := original.replace "public import tools.research.ReplyHold\n"
    "public import tools.research.ReplyHold\npublic import tools.research.SelectionReplyBoundary\n"
    |>.replace old "pool.withReplyEncoding job (SelectionReplyBoundary.forDelivery reply) (fun reply => pure (SelectionReplyBoundary.encode reply))"
  IO.FS.writeFile pool patched
  let entry := observer/"source/tools/research/OwnedSelectionRuntime.lean"
  let originalEntry ← IO.FS.readFile entry
  let oldBranch := "  | [\"owned-selection-capacity\",input] =>"
  check ((originalEntry.splitOn oldBranch).length == 2) "native capacity entry changed"
  IO.FS.writeFile entry ("import tools.research.SelectionReplyBoundaryCheck\n"++
    originalEntry.replace oldBranch ("  | [\"selection-reply-boundary-check\",input,output] => Eggshell.Research.SelectionReplyBoundaryCheck.run (.mk input) (.mk output); return 0\n"++oldBranch))
  IO.FS.createDirAll (observer/"prefix/libexec")
  discard <| command "/bin/ln" #["-s",(observer/"build/StudyMain").toString,(observer/"prefix/libexec/eggshell").toString]
  discard <| command "/bin/ln" #["-s",(parent/"prefix/share").toString,(observer/"prefix/share").toString]
  write (records/"observer-plan.json") (Json.mkObj [
    ("reason",toJson "completed private selection diagnostic exceeded 8MiB search reply;strip only private field at typed encoding boundary after receipt emission"),
    ("changedProductModules",toJson #["Eggshell.OperationPool"]),
    ("changedHarnessEntry",toJson "tools.research.OwnedSelectionRuntime"),
    ("unchangedBodySelectionAuthorityAndFrameBound",toJson true),
    ("noNewCacheOrWeightsOrWorkerLimit",toJson true),("paidRuntimeNotReplaced",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "range-workload-observer-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"range-workload-observer-settings.json").toString]

def auditObserver : IO Unit := do
  discard <| finished "range-workload-observer-inherited-build"
  guard "range-workload-observer-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",driver.toString,"audit-observer-worker"]

def auditObserverWorker : IO Unit := do
  let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
  IO.FS.createDirAll (records/"observer")
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",inspector.toString,
    "inspect",(observer/"build").toString,(records/"observer/native.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",inspector.toString,
    "compare-sources",(parent/"build").toString,(observer/"build").toString,(records/"observer/sources.json").toString,
    "Eggshell.OperationPool",
    "+tools.research.SelectionReplyBoundary","+tools.research.SelectionReplyBoundaryCheck"]
  for name in ["SelectionReplyBoundary","SelectionReplyBoundaryCheck"] do
    let (actual,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (observer/"build"/("tools_research_"++name++".source"))))
    check (actual == (← IO.FS.readFile (project/"tools/research"/(name++".lean"))) && literals.isEmpty) "observer native source differs"
  let (actualEntry,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (observer/"build/tools_research_OwnedSelectionRuntime.source")))
  check (actualEntry == (← IO.FS.readFile (observer/"source/tools/research/OwnedSelectionRuntime.lean")) && literals.isEmpty)
    "observer harness entry differs from frozen source"
  let proof ← IO.FS.readFile (observer/"build/tools_research_SelectionReplyBoundary-lean.stdout")
  check (!proof.contains "sorryAx") "private/public boundary proof not closed"
  IO.FS.writeFile (records/"observer/axioms.txt") proof
  write (records/"observer/runtime.json") (Json.mkObj [("sha256",toJson (← hash (observer/"build/StudyMain"))),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def checkBoundary : IO Unit := do
  discard <| finished "range-workload-observer-audit"
  check ((← read (records/"observer/runtime.json")).getObjValD "sha256" == toJson (← hash (observer/"build/StudyMain"))) "observer runtime changed"
  guard "range-workload-boundary-check" #[(observer/"build/StudyMain").toString,"selection-reply-boundary-check",
    (root/"input.json").toString,(records/"observer/boundary.json").toString]

partial def removeOwned (path : System.FilePath) : IO (Nat × Nat) := do
  let stat ← path.symlinkMetadata
  if stat.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let count ← removeOwned entry.path
      total := (total.1+count.1,total.2+count.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if stat.type == .file then stat.byteSize.toNat else 0)

def recoverObserverCache : IO Unit := do
  idle
  check (!(← (observer/"build/StudyMain").pathExists) &&
    !(← (base/"range-workload-observer-build.guard.json").pathExists)) "initial observer build may have executed"
  let before ← hash (parent/"build/StudyMain")
  let removed ← removeOwned (observer/"build")
  check ((← hash (parent/"build/StudyMain")) == before) "cache pruning changed parent runtime"
  IO.FS.createDirAll (records/"observer")
  write (records/"observer/copied-cache-removed.json") (Json.mkObj [
    ("reason",toJson "disk guard rejected before spawning compiler;remove fresh duplicate compiler cache and inherit unchanged parent inputs"),
    ("removedItems",toJson removed.1),("removedLogicalBytes",toJson removed.2),
    ("originalBuildNeverStarted",toJson true),("sourceAndParentRuntimeKept",toJson true),
    ("archive",toJson false),("resourceBoundsUnchanged",toJson true)])
  guard "range-workload-observer-inherited-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"range-workload-observer-settings.json").toString]

def closeFailureAndPrepare : IO Unit := do
  idle
  let stopped ← captureStopped
  discard <| finished "range-workload-boundary-check"
  let verified ← read (records/"observer/boundary.json")
  check (verified.getObjValD "originalBoundRejectionReproduced" == toJson true &&
    verified.getObjValD "exactBodyAndAckProjectionPreserved" == toJson true) "wire-bound reproduction not closed"
  let input ← read (root/"input.json")
  let original : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let originals : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (file,digest) in originals do check ((← hash (original/file)) == digest) "failed capture changed the original DB"
  let clients : Array Json ← IO.ofExcept (fromJson? (← read (root/"trial/prime.json")))
  let mut evidence := #[]
  for client in clients do
    let receipt ← IO.ofExcept (client.getObjValAs? String "receipt")
    let mut stages := #[]
    for name in ["search-phase-semantic","operation-service","search","transport"] do
      stages := stages.push (name,← read (parent/"data/receipts"/receipt/(name++".json")))
    evidence := evidence.push (client,toJson stages)
  write (records/"failed-capture-evidence.json") (Json.mkObj [("clientsAndStages",toJson evidence),("guard",stopped),
    ("originalSourceFilesUnchanged",toJson true),("claimedAsSuccessfulDelivery",toJson false)])
  let protectedPaths := #[parent/"build/StudyMain",observer/"build/StudyMain",root/"build/StudyMain",original/"head"]
  let before ← protectedPaths.mapM hash
  let mut removed := #[]
  for path in #[root/"trial",parent/"data/sessions",parent/"data/confirmed-delivery",parent/"data/receipts"] do
    if ← path.pathExists then
      let count ← removeOwned path
      removed := removed.push (path.toString,count.1,count.2)
  check ((← protectedPaths.mapM hash) == before) "failed-capture cleanup changed current inputs"
  write (records/"failed-capture-removed.json") (Json.mkObj [("removed",toJson removed),("archive",toJson false),
    ("protectedHashesUnchanged",toJson true),("currentCacheAndModelsKept",toJson true)])
  let trial := root/"closed-trial"
  let config := trial/"config.toml"
  let runtime := observer/"prefix/libexec/eggshell"
  let digest ← hash runtime
  let plugin := observer/"prefix/share/eggshell/codex-plugin"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
  let updates := #[("EGGSHELL_PREFIX",some (observer/"prefix").toString),("PLUGIN_ROOT",some plugin.toString),
    ("EGGSHELL_CONFIG",some config.toString)]
  let environment := environment.filter (fun row => !updates.any (·.1 == row.1)) ++ updates
  let input := input.setObjVal! "runtime" (toJson runtime.toString) |>.setObjVal! "runtimeSha256" (toJson digest)
    |>.setObjVal! "output" (toJson trial.toString) |>.setObjVal! "config" (toJson config.toString)
    |>.setObjVal! "plugin" (toJson plugin.toString) |>.setObjVal! "environment" (toJson environment)
  write (root/"closed-input.json") input
  let unsets := environment.filterMap (fun (key,value) => if value.isNone then some key else none)
    |>.flatMap (fun key => #["-u",key])
  let assignments := environment.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  guard "range-workload-closed-capture" (#["/usr/bin/env"]++unsets++assignments++#[runtime.toString,
    "owned-selection-capacity",(root/"closed-input.json").toString])

def analyzeClosed : IO Unit := do
  discard <| finished "range-workload-cli-capture"
  check ((← read (records/"runtime.json")).getObjValD "sha256" == toJson (← hash (root/"build/StudyMain"))) "native real range analyzer changed"
  guard "range-workload-closed-analysis" #[(root/"build/StudyMain").toString,(root/"closed-input.json").toString,(records/"closed-report.json").toString]

def trimCompilerScratch : IO Unit := do
  idle
  discard <| finished "range-workload-observer-inherited-build"
  let protectedPaths := #[parent/"build/StudyMain",observer/"build/StudyMain",root/"build/StudyMain",
    base/"snapshot-scheduling/work/work.egg/head"]
  let before ← protectedPaths.mapM hash
  let mut deleted := #[]
  for directory in #[observer/"build",root/"build"] do
    for entry in ← directory.readDir do
      if !entry.fileName.endsWith ".c" then continue
      let stat ← entry.path.symlinkMetadata
      check (stat.type == .file) "generated C scratch is not a regular file"
      IO.FS.removeFile entry.path
      deleted := deleted.push (entry.path.toString,stat.byteSize.toNat)
  check ((← protectedPaths.mapM hash) == before) "compiler scratch cleanup changed native runtime or source"
  write (records/"compiler-scratch-removed.json") (Json.mkObj [("generatedC",toJson deleted),
    ("objectSourceDependencyAndInterfaceInputsKept",toJson true),("protectedHashesUnchanged",toJson true),
    ("archive",toJson false)])

partial def shareIdentical (directory original : System.FilePath) : IO (Array (String × Nat × String)) := do
  let mut shared := #[]
  for entry in ← directory.readDir do
    let stat ← entry.path.symlinkMetadata
    let existing := original/entry.fileName
    if stat.type == .dir then
      if ← existing.isDir then shared := shared ++ (← shareIdentical entry.path existing)
      continue
    if stat.type != .file || !(← existing.pathExists) then continue
    if ![".o",".olean",".olean.private",".olean.server",".ir",".ir.sig",".source",".dependencies"].any
        (fun suffix => entry.fileName.endsWith suffix) then continue
    let before ← hash entry.path
    if (← hash existing) != before then continue
    let target ← IO.FS.realPath existing
    IO.FS.removeFile entry.path
    discard <| command "/bin/ln" #["-s",target.toString,entry.path.toString]
    check ((← hash entry.path) == before) "identical native input changed while sharing"
    shared := shared.push (entry.path.toString,stat.byteSize.toNat,before)
  return shared

def shareCompilerInputs : IO Unit := do
  idle
  discard <| finished "range-workload-observer-inherited-build"
  let protectedPaths := #[parent/"build/StudyMain",observer/"build/StudyMain",root/"build/StudyMain",
    base/"snapshot-scheduling/work/work.egg/head"]
  let before ← protectedPaths.mapM hash
  let mut shared := #[]
  for directory in #[observer/"build",root/"build"] do
    shared := shared ++ (← shareIdentical directory (parent/"build"))
  check ((← protectedPaths.mapM hash) == before) "input sharing changed runtime or source"
  write (records/"shared-compiler-inputs.json") (Json.mkObj [("shared",toJson shared),
    ("exactBytesComparedBeforeAndAfter",toJson true),("protectedHashesUnchanged",toJson true),
    ("archive",toJson false),("productCacheOrRuntimeChange",toJson false)])

def retireUnusedAncestorExecutable : IO Unit := do
  idle
  let ancestor := base/"register-rounds-runtime"
  let executable := ancestor/"build/StudyMain"
  let alias := ancestor/"prefix/libexec/eggshell"
  check ((← hash executable) == "1153215e50e63191a46b1f80a34d8c2c0d056478b30b81e5c22958d2c1a8c965") "old ancestor executable changed"
  let shared ← IO.FS.realPath (ancestor/"prefix/share")
  let directories := #[parent/"source",parent/"build",parent/"data",shared,
    base/"current-six/fixed-sequence"]
  let lookup ← IO.Process.output {cmd := "rg",args := #["-l","-F","-e",executable.toString,"-e",alias.toString,
    "--glob","*.lean","--glob","*.json","--glob","*.toml","--glob","*.py","--glob","*.sh","--glob","*.source"]++directories.map (·.toString)}
  check (lookup.exitCode == 1 && lookup.stdout.isEmpty) "current source/configuration still references the old executable"
  let processes := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(processes.any fun row =>
    let executableName := (row.trimAscii.toString.splitOn " ").headD ""
    executableName == executable.toString || executableName == alias.toString)) "ancestor executable is live"
  for build in #[parent/"build",observer/"build",root/"build"] do
    check (!(← IO.FS.readFile (build/"runtime.rsp")).contains executable.toString) "old executable is a native input"
  let protectedPaths := #[parent/"build/StudyMain",observer/"build/StudyMain",root/"build/StudyMain",
    base/"current-six/stable-source-rows/build/StudyMain",base/"current-six/fixed-sequence/controller-build/StudyMain",
    base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",base/"byte-pages-prefix/libexec/eggshell",
    base/"snapshot-scheduling/work/work.egg/head"]
  let before ← protectedPaths.mapM hash
  let stat ← executable.symlinkMetadata
  check (stat.type == .file) "old executable is not a regular file"
  let linked ← try pure ((← alias.symlinkMetadata).type == .symlink && (← IO.FS.realPath alias) == executable)
    catch _ => pure false
  if linked then IO.FS.removeFile alias
  IO.FS.removeFile executable
  check ((← protectedPaths.mapM hash) == before) "ancestor retirement changed an active runtime or DB"
  IO.FS.createDirAll (records/"observer")
  write (records/"observer/unused-ancestor-removed.json") (Json.mkObj [("executable",toJson executable.toString),
    ("sha256",toJson "1153215e50e63191a46b1f80a34d8c2c0d056478b30b81e5c22958d2c1a8c965"),
    ("logicalBytes",toJson stat.byteSize.toNat),("removedDeadAlias",toJson linked),
    ("currentUsageScan",toJson (directories.map (·.toString))),("currentExecutableReferences",toJson (0 : Nat)),
    ("ancestorNativeObjectsInterfacesAndModelsKept",toJson true),("protectedHashesUnchanged",toJson true),("archive",toJson false)])

partial def libraryTargets (directory : System.FilePath) : IO (Array String) := do
  let mut result := #[]
  for entry in ← directory.readDir do
    let kind := (← entry.path.symlinkMetadata).type
    if kind == .dir then result := result ++ (← libraryTargets entry.path)
    else result := result.push (← IO.FS.realPath entry.path).toString
  return result

def retireComponentScratch : IO Unit := do
  idle
  discard <| finished "range-workload-analysis"
  discard <| finished "range-workload-observer-inherited-build"
  let old := base/"factored-incidence"
  let retiredPrefix := old.toString++"/"
  let protectedPaths := #[parent/"build/StudyMain",observer/"build/StudyMain",root/"build/StudyMain",
    base/"snapshot-scheduling/work/work.egg/head"]
  let before ← protectedPaths.mapM hash
  let mut checked := 0
  let mut removedInterfaces := #[]
  for directory in #[root/"build",observer/"build"] do
    for line in (← IO.FS.readFile (directory/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      if path.startsWith "-" then
        check (!path.contains retiredPrefix) "linker flag still references old component"
        continue
      check (!(← IO.FS.realPath (.mk path)).toString.startsWith retiredPrefix) "old component still owns a native object"
      checked := checked+1
    let metadata ← read (directory/"build.json")
    let entry ← IO.ofExcept ((metadata.getObjValD "settings").getObjValAs? String "mainModule")
    let dependencies : Array (String × String) ← IO.ofExcept (fromJson? (← read (directory/(entry.replace "." "_"++".dependencies"))))
    for name in ["SharedIncidence","FactoredIncidenceBench","RangeIncidenceBench"] do
      check (!(dependencies.any (fun row => row.1 == "tools.research."++name))) "retired test remains in active imports"
      for suffix in [".olean",".olean.private",".olean.server",".ir",".ir.sig"] do
        let path := directory/"lib/tools/research"/(name++suffix)
        if !(← path.pathExists) then continue
        if !(← IO.FS.realPath path).toString.startsWith retiredPrefix then continue
        check ((← path.symlinkMetadata).type == .symlink) "unused interface is not an inherited link"
        IO.FS.removeFile path
        removedInterfaces := removedInterfaces.push path.toString
    let targets ← libraryTargets (directory/"lib")
    check (!(targets.any (·.startsWith retiredPrefix))) "old component still owns a compiler interface"
    checked := checked+targets.size
  let fallback := root/"source/.lake/build/lib/lean"
  if (← IO.FS.realPath fallback).toString.startsWith retiredPrefix then
    check ((← fallback.symlinkMetadata).type == .symlink) "component fallback is not a link"
    IO.FS.removeFile fallback
    discard <| command "/bin/ln" #["-s",(parent/"build/lib").toString,fallback.toString]
  let removed ← removeOwned old
  check ((← protectedPaths.mapM hash) == before) "component retirement changed active inputs"
  write (records/"retired-component.json") (Json.mkObj [("removedItems",toJson removed.1),
    ("removedLogicalBytes",toJson removed.2),("checkedNativeAndInterfacePaths",toJson checked),
    ("removedUnimportedTestInterfaces",toJson removedInterfaces),
    ("noActivePathInRetiredRoot",toJson true),("fallbackUsesCurrentParent",toJson true),
    ("protectedHashesUnchanged",toJson true),("archive",toJson false)])

abbrev NativeChild := IO.Process.Child {stdin := .null,stdout := .inherit,stderr := .inherit}

def readyNative (child : NativeChild) (terminal : IO.Ref (Option UInt32)) (endpoint : System.FilePath) : IO Unit := do
  let cutoff := (← IO.monoMsNow)+10000
  repeat
    if let some code ← child.tryWait then
      terminal.set (some code)
      throw (IO.userError "owned native service exited before readiness")
    if ← endpoint.pathExists then
      check ((← read endpoint).getObjValD "pid" == toJson child.pid.toNat) "native endpoint belongs to another process"
      return
    check ((← IO.monoMsNow) < cutoff) "native service readiness expired"
    IO.sleep 5

def stopNative (child : NativeChild) (terminal : IO.Ref (Option UInt32)) (endpoint runtime report : System.FilePath)
    (arguments : Array String) (environment : Array (String × Option String)) : IO Unit := do
  try
    if (← terminal.get).isNone then terminal.set (← child.tryWait)
    if (← terminal.get).isNone then
      check ((← read endpoint).getObjValD "pid" == toJson child.pid.toNat) "native service was replaced"
      let stopped ← IO.Process.output {cmd := runtime.toString,args := arguments,env := environment}
      check (stopped.exitCode == 0) "native shutdown command failed"
      let cutoff := (← IO.monoMsNow)+15000
      repeat
        if let some code ← child.tryWait then terminal.set (some code); break
        check ((← IO.monoMsNow) < cutoff) "native service exit expired"
        IO.sleep 5
    let code := (← terminal.get).getD 1
    write report (Json.mkObj [("pid",toJson child.pid.toNat),("daemonExitCode",toJson code.toNat),
      ("processExited",toJson true),("endpointRemoved",toJson (!(← endpoint.pathExists)))])
    check (code == 0 && !(← endpoint.pathExists)) "native service did not close cleanly"
  finally
    if (← terminal.get).isNone then
      if let some code ← child.tryWait then terminal.set (some code)
      else
        discard <| IO.Process.output {cmd := "/bin/kill",args := #["-TERM","--","-"++toString child.pid.toNat]}
        terminal.set (some (← child.wait))

def prepareCliCapture : IO Unit := do
  idle
  check (!(← (base/"range-workload-closed-capture.guard.json").pathExists)) "four-client capture already executed"
  let input ← read (root/"closed-input.json")
  let input := input.setObjVal! "counts" (toJson (#[] : Array Nat))
    |>.setObjVal! "captureMode" (toJson "three serial native product CLI hooks")
  write (root/"closed-input.json") input
  write (records/"closed-capture-plan.json") (Json.mkObj [("schedule",toJson "one actual native CLI hook for each topic1/2/3;no concurrent wave"),
    ("reason",toJson "collect actual geometry only;four extra concurrent diagnostic clients are unnecessary on this low-memory Mac"),
    ("allProductDbIoNative",toJson true),("controllerOnlyReadsJsonMetadataAndStartsNativeProcesses",toJson true),
    ("capacityOrPerformanceComparisonClaimed",toJson false),("resourceBoundsUnchanged",toJson true)])
  guard "range-workload-cli-capture" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",driver.toString,"cli-capture-worker"]

def cliCaptureWorker : IO Unit := do
  let input ← read (root/"closed-input.json")
  let runtime : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "runtime"))
  check (toJson (← hash runtime) == input.getObjValD "runtimeSha256") "native CLI runtime changed"
  let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let trial : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "output"))
  let config : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "config"))
  let original : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
  let sourceFiles : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (file,digest) in sourceFiles do check ((← hash (original/file)) == digest) "native CLI source changed"
  check (!(← trial.pathExists) && !(← (data/"daemon.json").pathExists) && !(← (data/"publisher/endpoint.json").pathExists)) "native CLI scope already owned"
  IO.FS.createDirAll trial
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = "++(toJson #[runtime.toString,"search-provider"]).compress++
    "\n[eggs]\nwork = "++(toJson original.toString).compress++"\n[profiles.work]\nread = [\"work\"]\nhandoff_chars = 500000\n")
  let publisher ← IO.Process.spawn {
    cmd := runtime.toString
    args := #["codex-publication-daemon"]
    env := environment
    stdin := .null,stdout := .inherit,stderr := .inherit,setsid := true}
  let publisherExit ← IO.mkRef none
  try
    readyNative publisher publisherExit (data/"publisher/endpoint.json")
    let warmed ← IO.Process.output {cmd := runtime.toString,args := #["egg","warm","work"],env := environment}
    IO.FS.writeFile (trial/"warm.stdout") warmed.stdout
    IO.FS.writeFile (trial/"warm.stderr") warmed.stderr
    check (warmed.exitCode == 0) "native CLI warm failed"
    let frontend ← IO.Process.spawn {
      cmd := runtime.toString
      args := #["codex-daemon","range-cli"]
      env := environment
      stdin := .null,stdout := .inherit,stderr := .inherit,setsid := true}
    let frontendExit ← IO.mkRef none
    try
      readyNative frontend frontendExit (data/"daemon.json")
      let topics ← IO.ofExcept (input.getObjValAs? (Array Json) "topics")
      let mut results := #[]
      for topic in topics do
        let ordinal ← IO.ofExcept (topic.getObjValAs? Nat "topic")
        let prompt ← IO.ofExcept (topic.getObjValAs? String "prompt")
        let body : System.FilePath := .mk (← IO.ofExcept (topic.getObjValAs? String "body"))
        check (toJson (← hash body) == topic.getObjValD "sha256") "canonical body changed"
        let session := s!"range-cli-{publisher.pid.toNat}-{ordinal}"
        let directory := trial/s!"topic-{ordinal}"
        IO.FS.createDirAll directory
        let mut output := ""
        let mut elapsed := 0
        for event in ["SessionStart","UserPromptSubmit"] do
          let request := Json.mkObj [("session_id",toJson session),("turn_id",toJson "first"),
            ("cwd",input.getObjValD "workspace"),("_eggshell_config",toJson config.toString),
            ("hook_event_name",toJson event),("prompt",toJson (if event == "UserPromptSubmit" then prompt else ""))]
          let path := directory/(event++".stdin.json")
          write path request
          let before ← IO.monoMsNow
          let reply ← IO.Process.output {cmd := "/bin/sh",args := #["-c","exec \"$1\" codex-hook < \"$2\"","range-hook",runtime.toString,path.toString],env := environment}
          elapsed := (← IO.monoMsNow)-before
          check (reply.exitCode == 0) "native product hook CLI failed"
          IO.FS.writeFile (directory/(event++".stdout")) reply.stdout
          IO.FS.writeFile (directory/(event++".stderr")) reply.stderr
          output := reply.stdout
        let decoded ← IO.ofExcept (Json.parse output)
        let delivered ← IO.ofExcept ((decoded.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
        let mut receipts := #[]
        for entry in ← (data/"receipts").readDir do
          let path := entry.path/"request.json"
          if !(← path.pathExists) then continue
          let request := (← read path).getObjValD "data"
          if request.getObjValD "session" == toJson session && request.getObjValD "event" == toJson "UserPromptSubmit" then receipts := receipts.push entry.fileName
        check (receipts.size == 1) "native CLI receipt is absent or ambiguous"
        let receipt := receipts[0]!
        let published := (← read (data/"receipts"/receipt/"published.json")).getObjValD "data"
        let ack := (← read (data/"receipts"/receipt/"ack.json")).getObjValD "data"
        let same := delivered == (← IO.FS.readFile body)
        let acknowledged := ack.getObjValD "rpcCompleted" == toJson true && ack.getObjValD "offerAccepted" == toJson true
        let exact := published.getObjValD "output" == toJson output && published.getObjValD "replyComplete" == toJson true
        let success := same && acknowledged && exact && elapsed < 30000
        let row := Json.mkObj [("topic",toJson ordinal),("receipt",toJson receipt),("elapsedMs",toJson elapsed),
          ("bodyBytes",toJson delivered.utf8ByteSize),("bodyByteEqual",toJson same),("acknowledged",toJson acknowledged),
          ("publishedStdoutExact",toJson exact),("success",toJson success),("clientTransport",toJson "native product CLI")]
        results := results.push row
        write (trial/"prime.json") (toJson results)
        check success "native CLI body, publication, ACK or deadline failed"
      for (file,digest) in sourceFiles do check ((← hash (original/file)) == digest) "native CLI changed source publication"
    finally stopNative frontend frontendExit (data/"daemon.json") runtime (trial/"frontend-shutdown.json") #["codex-daemon","shutdown"] environment
  finally stopNative publisher publisherExit (data/"publisher/endpoint.json") runtime (trial/"publisher-shutdown.json") #["publication-control","shutdown"] environment

def collectClosed : IO Unit := do
  idle
  let capture ← finished "range-workload-cli-capture"
  let analysis ← finished "range-workload-closed-analysis"
  let input ← read (root/"closed-input.json")
  let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let trial : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "output"))
  let rows : Array Json ← IO.ofExcept (fromJson? (← read (trial/"prime.json")))
  check (rows.map (·.getObjValD "topic") == (#[1,2,3] : Array Nat).map toJson &&
    rows.all (fun row => row.getObjValD "success" == toJson true)) "three actual CLI bodies/ACKs incomplete"
  let report ← read (records/"closed-report.json")
  let topics ← IO.ofExcept (report.getObjValAs? (Array Json) "topics")
  check (topics.size == 3 && topics.all (fun row => row.getObjValD "actualHookSucceeded" == toJson true)) "actual range report incomplete"
  let mut briefs := #[]
  for topic in topics do
    let trials ← IO.ofExcept (topic.getObjValAs? (Array Json) "trials")
    check (trials.size == 3 && trials.all (fun row => row.getObjValD "allOrderedPieceIdsEqual" == toJson true)) "real range ordered outputs differ"
    let receipt ← IO.ofExcept (topic.getObjValAs? String "receipt")
    let search := (← read (data/"receipts"/receipt/"search.json")).getObjValD "data"
    let synapse := (← read (data/"receipts"/receipt/"synaptic-delivery.json")).getObjValD "data"
    check ((search.getObjValD "trace").getObjValD "semantic" == toJson "completed" &&
      (search.getObjValD "trace").getObjValD "route" == toJson "configured" &&
      synapse.getObjValD "complete" == toJson true && synapse.getObjValD "packetVerified" == toJson true)
      "actual vector/synapse route was not complete"
    let catalogue := topic.getObjValD "catalogue"
    briefs := briefs.push (Json.mkObj [("topic",topic.getObjValD "topic"),("units",topic.getObjValD "units"),
      ("pieces",topic.getObjValD "pieces"),("ranges",topic.getObjValD "structuralRanges"),
      ("geometryClasses",topic.getObjValD "geometryClasses"),("baseHits",topic.getObjValD "baseHits"),
      ("staticUnits",catalogue.getObjValD "staticUnits"),("dynamicUnits",catalogue.getObjValD "dynamicUnits"),
      ("genericUnits",catalogue.getObjValD "genericUnits"),("trials",toJson trials),
      ("vectorAndSynapsesCompleted",toJson true)])
  let warm ← read (trial/"warm.stdout")
  let databases ← IO.ofExcept (warm.getObjValAs? (Array Json) "databases")
  check (databases.size == 1 && databases[0]!.getObjValD "path" == input.getObjValD "project") "warm changed project inventory"
  let sources ← IO.ofExcept (databases[0]!.getObjValAs? (Array Json) "sources")
  check (sources.size == 1) "warm changed original source inventory"
  for source in sources do
    let after := source.getObjValD "after"
    let prepared := source.getObjValD "prepared"
    check (prepared.getObjValD "source" == report.getObjValD "sourceHead" &&
      after.getObjValD "model" == toJson "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2" &&
      after.getObjValD "encoderContract" == toJson "1417508ca8aee8ee45bff632925ff6a23447d0d1a766d1c7411b775bc10a83f4" &&
      after.getObjValD "missing" == toJson (0 : Nat) && after.getObjValD "invalid" == toJson (0 : Nat) &&
      after.getObjValD "valid" == after.getObjValD "windows" &&
      source.getObjValD "requested" == toJson (0 : Nat) && source.getObjValD "batches" == toJson (0 : Nat)) "warm was incomplete, foreign or rebuilt vectors"
    for key in ["windows","lexical","numeric","canonical","shared"] do
      check (prepared.getObjValD key != Json.null) ("warm omitted required index:"++key)
  for role in ["frontend","publisher"] do
    let status ← read (trial/(role++"-shutdown.json"))
    check (status.getObjValD "daemonExitCode" == toJson (0 : Nat) && status.getObjValD "endpointRemoved" == toJson true)
      "native capture service did not stop"
  write (records/"closed-warm.json") warm
  write (records/"summary.json") (Json.mkObj [("topics",toJson briefs),("actualCliClients",toJson rows),
    ("allThreeBodiesAndAcksExact",toJson true),("warmCompleteWithoutEncoding",toJson true),
    ("captureGuard",capture),("analysisGuard",analysis),("sixStageOrConcurrentCapacityClaimed",toJson false),
    ("wholeHookPerformanceComparison",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def freezeAndRetire : IO Unit := do
  idle
  discard <| finished "range-workload-closed-analysis"
  check ((← read (records/"summary.json")).getObjValD "allThreeBodiesAndAcksExact" == toJson true) "collect exact native capture first"
  let input ← read (root/"closed-input.json")
  let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let trial : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "output"))
  let clients : Array Json ← IO.ofExcept (fromJson? (← read (trial/"prime.json")))
  let fixture := root/"fixtures"
  check (!(← fixture.pathExists)) "preserve active query fixtures"
  IO.FS.createDirAll fixture
  discard <| command "/bin/chmod" #["700",fixture.toString]
  let mut files := #[]
  for client in clients do
    let receipt ← IO.ofExcept (client.getObjValAs? String "receipt")
    let source := data/"receipts"/receipt
    let target := fixture/receipt
    IO.FS.createDirAll target
    for entry in ← source.readDir do
      if !entry.fileName.startsWith "selection-" || !entry.fileName.endsWith ".json" then continue
      let destination := target/entry.fileName
      let size := (← entry.path.metadata).byteSize.toNat
      let digest ← hash entry.path
      IO.FS.rename entry.path destination
      check ((← hash destination) == digest) "active query fixture changed while moving"
      files := files.push (receipt,entry.fileName,size,digest)
  let report ← read (records/"closed-report.json")
  write (fixture/"input.json") (Json.mkObj [("originalSource",input.getObjValD "project"),
    ("cacheDataRoot",input.getObjValD "data"),("sourceHead",report.getObjValD "sourceHead"),
    ("recipeHead",report.getObjValD "recipeHead"),("topics",toJson clients),
    ("receiptDirectories",toJson true),("purpose",toJson "active actual geometry and problem inputs for next selector refinement")])
  write (records/"fixtures.json") (Json.mkObj [("directory",toJson fixture.toString),("files",toJson files),
    ("notCommittedRawQueryInputs",toJson true),("notDbOrCacheCopy",toJson true),("activeForNextStep",toJson true)])
  let original : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let sourceFiles : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (name,digest) in sourceFiles do check ((← hash (original/name)) == digest) "source changed before capture retirement"
  let protectedPaths := #[parent/"build/StudyMain",base/"current-six/stable-source-rows/build/StudyMain",
    base/"current-six/fixed-sequence/controller-build/StudyMain",base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",
    base/"byte-pages-prefix/libexec/eggshell",original/"head"]
  let before ← protectedPaths.mapM hash
  let mut resources := #[]
  for entry in ← base.readDir do
    if !entry.fileName.startsWith "range-workload-" || !entry.fileName.endsWith ".guard.json" then continue
    let guard ← read entry.path
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "capture still owns a process"
    resources := resources.push (entry.fileName,guard)
  write (records/"resources.json") (toJson resources)
  let mut deleted := #[]
  let alias := observer/"prefix/libexec/eggshell"
  if ← alias.pathExists then
    check ((← alias.symlinkMetadata).type == .symlink && (← IO.FS.realPath alias) == observer/"build/StudyMain") "observer alias belongs to another executable"
    IO.FS.removeFile alias
  for path in #[trial,data/"sessions",data/"confirmed-delivery",data/"receipts",root/"build/StudyMain",observer/"build/StudyMain"] do
    if ← path.pathExists then
      let count ← removeOwned path
      deleted := deleted.push (path.toString,count.1,count.2)
  check ((← protectedPaths.mapM hash) == before) "capture retirement changed active runtime or DB"
  for (name,digest) in sourceFiles do check ((← hash (original/name)) == digest) "source changed during retirement"
  write (records/"retired.json") (Json.mkObj [("deleted",toJson deleted),("protectedHashesUnchanged",toJson true),
    ("sourceFilesUnchanged",toJson true),("currentProjectCacheAndModelsKept",toJson true),
    ("onlyActiveQueryMetadataRetained",toJson true),("unusedNativeExecutablesRemoved",toJson true),("archive",toJson false)])

def main (args : List String) : IO Unit := do
  match args with
  | ["setup"] => setup
  | ["prepare-native"] => prepareNative
  | ["audit-native"] => auditNative
  | ["audit-worker"] => auditWorker
  | ["analyze"] => analyze
  | ["prepare-observer"] => prepareObserver
  | ["audit-observer"] => auditObserver
  | ["audit-observer-worker"] => auditObserverWorker
  | ["check-boundary"] => checkBoundary
  | ["recover-observer-cache"] => recoverObserverCache
  | ["close-failure-prepare"] => closeFailureAndPrepare
  | ["analyze-closed"] => analyzeClosed
  | ["trim-compiler-scratch"] => trimCompilerScratch
  | ["share-compiler-inputs"] => shareCompilerInputs
  | ["retire-unused-ancestor"] => retireUnusedAncestorExecutable
  | ["retire-component"] => retireComponentScratch
  | ["prepare-cli-capture"] => prepareCliCapture
  | ["cli-capture-worker"] => cliCaptureWorker
  | ["collect-closed"] => collectClosed
  | ["freeze-retire"] => freezeAndRetire
  | ["show-summary"] => IO.println ((← read (records/"summary.json")).getObjValD "topics").compress
  | _ => throw (IO.userError "range workload setup")
end RangeWorkloadStudy
def main := RangeWorkloadStudy.main
