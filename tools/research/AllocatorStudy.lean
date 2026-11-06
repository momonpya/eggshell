import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output := base/"allocator-profile-build"
def allocatorToolchain : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def destination := workspace/"docs/candidates/allocator-profile"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty
def run (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String := do
  return ((← run "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def arr (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def number (value : Json) (key : String) : Nat := (value.getObjValAs? Nat key).toOption.getD 0
def script (path : String) (args : Array String) : IO Unit := do
  discard <| run (allocatorToolchain/"bin/lean").toString (#["-j1","-M1536","--run",(workspace/path).toString]++args)
def protectedInputs : IO Unit := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (result.exitCode == 0) "protected input digest changed"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) : Except String (Array (String × String × String)))
  for (path,bytes,sha) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == sha) "original head changed"
def drained : IO (Array (String × Json)) := do
  let mut values := #[]
  for entry in ← base.readDir do
    unless (entry.fileName.startsWith "allocator-profile-" || entry.fileName.startsWith "allocator-service-") &&
      entry.fileName.endsWith ".guard.json" && !entry.fileName.contains "-milestone-" do continue
    let value ← read entry.path
    check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "allocator study workload not drained"
    let pid := number value "guardPid"
    let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
    check (probe.exitCode != 0 && probe.stdout.trimAscii.isEmpty) "allocator study guard remains live"
    values := values.push (entry.fileName.dropEnd 11 |>.toString,value)
  return values
def recordFixtures : IO Unit := do
  let abi ← read (destination/"abi.json")
  check (abi.getObjValD "leanSourceSha256" == toJson (← hash (workspace/"tools/research/AllocatorProfile.lean")) &&
    abi.getObjValD "nativeAdapterSha256" == toJson (← hash (output/"allocator_probe.source"))) "model-free source witness changed"
  check ((← IO.FS.readFile (workspace/"tools/research/native/allocator_probe.c")).startsWith (← IO.FS.readFile (output/"allocator_probe.source"))) "owner-only observer changed original probe functions"
  check ((← read (destination/"build.json")).getObjValD "runtimeSha256" == toJson (← hash (output/"StudyMain"))) "model-free runtime changed"
  let mut modes := #[]
  for tag in ["allocator-profile-drop1","allocator-profile-drop-collect1","allocator-profile-keep1","allocator-profile-keep-collect1"] do
    let root := base/(tag++"-result")
    let mut timeline := #[]
    let mut actors := #[]
    for round in [:4] do
      for stage in ["held","joined","main-collected"] do
        let value ← read (root/s!"wave-{round}-{stage}.json")
        timeline := timeline.push (value.setObjVal! "round" (toJson round) |>.setObjVal! "stage" (toJson stage)
          |>.setObjVal! "globalCommittedCounterAccepted" (toJson (decide (number value "committedBytes" < 2^63))))
      for actor in [:8] do actors := actors.push (← read (root/s!"wave-{round}-actor-{actor}.json"))
    modes := modes.push (Json.mkObj [("tag",toJson tag),("report",← read (root/"report.json")),
      ("initial",← read (root/"initial.json")),("timeline",toJson timeline),("actorAreas",toJson actors)])
  IO.FS.writeFile (destination/"fixtures.json") (Json.mkObj [("modes",toJson modes),
    ("invalidGlobalCommittedCounterObserved",toJson (modes.any fun mode => (arr mode "timeline").any fun v =>
      v.getObjValD "globalCommittedCounterAccepted" == toJson false)),
    ("probeAdapterPrefixUtf8Bytes",toJson (← IO.FS.readFile (output/"allocator_probe.source")).utf8ByteSize),
    ("globalCountersRejectedForServiceAttribution",toJson true),("notRealServiceAttribution",toJson true)]).compress
def recordStudy : IO Unit := do
  let controls ← drained
  protectedInputs
  recordFixtures
  if ← (destination/"candidate.patch").pathExists then
    discard <| run "/usr/bin/git" #["-C",(base/"interest-traffic-core").toString,"apply","--reverse","--unidiff-zero","--check",(destination/"candidate.patch").toString]
  else script "tools/research/CaptureConcurrentPatches.lean" #["allocator-profile"]
  if ← (destination/"evidence.json").pathExists then
    let evidence ← read (destination/"evidence.json")
    let mut runs := #[]
    for trial in arr evidence "runs" do
      check (trial.getObjValD "tag" == toJson "allocator-service-hook16-1" &&
        trial.getObjValD "guard" == (← read (base/"allocator-service-hook16-1.guard.json"))) "resumed allocator trial identity changed"
      for row in arr trial "rowsIncludingPrime" do
        let session ← IO.ofExcept (row.getObjValAs? String "session")
        check (row.getObjValD "stdoutSha256" == toJson (← hash (base/"allocator-service-hook16-1-result"/(session++".stdout")))) "resumed raw stdout changed"
      let mut waves := #[]
      for wave in arr trial "waves" do
        let mut receipts := #[]
        for receipt in arr wave "receipts" do
          let id ← IO.ofExcept (receipt.getObjValAs? String "receipt")
          let original ← read (base/"allocator-service-hook16-1-result/private/receipts"/id/"query-allocator.json")
          receipts := receipts.push (receipt.setObjVal! "query-allocator" (original.getObjValD "data"))
        waves := waves.push (wave.setObjVal! "receipts" (toJson receipts))
      runs := runs.push (trial.setObjVal! "waves" (toJson waves))
    write (destination/"evidence.json") (evidence.setObjVal! "runs" (toJson runs))
  else script "docs/candidates/shared-leases/records.lean" #["--allocator-profile","allocator-service-hook16-1"]
  script "docs/candidates/shared-leases/records.lean" #["--allocator-profile","verify","35"]
  let rows (file : System.FilePath) (tag : String) : IO (Array Json) := do
    let some trial := (arr (← read file) "runs").find? (fun value => value.getObjValD "tag" == toJson tag) |
      throw (IO.userError "specified hook control absent")
    return (arr trial "rowsIncludingPrime").filter fun row =>
      ((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-wave-"
  let before ← rows (workspace/"docs/candidates/owner-metadata-image/evidence.json") "owner-metadata-image-hook16-1"
  let after ← rows (destination/"evidence.json") "allocator-service-hook16-1"
  check (before.size == 32 && after.size == 32) "allocator observer control domain changed"
  for row in before do
    check (after.any fun other => other.getObjValD "session" == row.getObjValD "session" &&
      other.getObjValD "stdoutSha256" == row.getObjValD "stdoutSha256") "observer changed actual hook bytes"
  let inputs ← read (destination/"service-adapter.json")
  check (inputs.getObjValD "objectSha256" == toJson (← hash (base/"allocator-service-ffi/adapter.o"))) "native observer object changed"
  check ((← read (destination/"native-service-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "service source audit incomplete"
  let report ← read (base/"allocator-service-hook16-1-result/report.json")
  let stages := #[report.getObjValD "prime",report.getObjValD "first",report.getObjValD "second"]
  let cacheStates := stages.map fun stage => Json.mkObj [("name",stage.getObjValD "name"),
    ("host",toJson ((arr stage "after").filter fun p => p.getObjValD "role" == toJson "publication-service")),
    ("preparedSources",stage.getObjValD "serviceStats" |>.getObjValD "preparedSources"),
    ("operations",stage.getObjValD "serviceStats" |>.getObjValD "operations"),
    ("paletteQueries",stage.getObjValD "serviceStats" |>.getObjValD "paletteQueries"),
    ("statsOwnerHeap",stage.getObjValD "serviceStats" |>.getObjValD "statsOwnerHeap")]
  let some trial := (arr (← read (destination/"evidence.json")) "runs").find? (fun v =>
    v.getObjValD "tag" == toJson "allocator-service-hook16-1") | throw (IO.userError "observer receipt trial absent")
  let areas := ((arr trial "waves").filter fun v => v.getObjValD "name" != toJson "prime").flatMap fun wave =>
    (arr wave "receipts").map (·.getObjValD "query-allocator")
  check (areas.size == 32 && areas.all (fun value => value.getObjValD "ownerOnlyNotWholeProcessLiveBytes" == toJson true)) "owner area receipt domain changed"
  IO.FS.writeFile (destination/"attribution.json") (Json.mkObj [("stages",toJson cacheStates),("phaseOwnerAreas",toJson areas),
    ("stableCacheCardinalityDoesNotProveStableHeap",toJson true),
    ("ownerReportedUsedMayIncludePendingRemoteFrees",toJson true),
    ("liveGraphVsPendingFreesUnresolved",toJson true),
    ("next",toJson "Test producer-owned graphs freed on the producer versus after cross-thread ownership transfer and producer exit. Audit typed SearchReply and Json result lifetimes at asynchronous boundaries before changing allocator settings,concurrency,ranking or deadlines.")]).compress
  let mut failures := #[]
  for (tag,value) in controls do
    if value.getObjValD "exitCode" == toJson (0 : Nat) then continue
    failures := failures.push (Json.mkObj [("tag",toJson tag),("guard",value),
      ("log",toJson (← IO.FS.readFile (base/(tag++".log"))))])
  let mut helperFailures := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "allocator-service-milestone-" && entry.fileName.endsWith ".guard.json" do continue
    let value ← read entry.path
    unless value.getObjValD "state" == toJson "finished" && value.getObjValD "exitCode" != toJson (0 : Nat) do continue
    helperFailures := helperFailures.push (Json.mkObj [("guard",value),("log",toJson (← IO.FS.readFile
      (base/((entry.fileName.dropEnd 11 |>.toString)++".log"))))])
  write (destination/"controls.json") (Json.mkObj [("guards",toJson controls),("failures",toJson failures),("helperFailures",toJson helperFailures),
    ("setupFailures",toJson #["toolchain name ambiguity before first guard","nested action in service hook settings before launch","ToJson Prop in fixture counter validation before build4 setup"]),
    ("serviceNativeChecks",← read (base/"allocator-service-checks1-result/report.json")),
    ("actualHookStdoutBytesEqual",toJson (32 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("paidComparisons",toJson "0/18"),("adopted",toJson false)])
  write (destination/"seal.json") (Json.mkObj [("runtimeSha256",toJson (← hash (base/"allocator-service-build/StudyMain"))),
    ("parentRuntimeSha256",toJson (← hash (base/"owner-metadata-image-build/StudyMain"))),
    ("clientSha256",toJson (← hash (base/"numerical-stages-client-build/StudyMain")))])
partial def removeTree (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut files := 0
    let mut bytes := 0
    for entry in ← path.readDir do
      let (n,b) ← removeTree entry.path
      files := files+n
      bytes := bytes+b
    IO.FS.removeDir path
    return (files,bytes)
  IO.FS.removeFile path
  return (1,metadata.byteSize.toNat)
def cleanStudy : IO Unit := do
  let controls ← drained
  protectedInputs
  check ((← read (destination/"verification.json")).getObjValD "actualOutputs" == toJson (35 : Nat) &&
    (← read (destination/"fixtures.json")).getObjValD "modes" != Json.null) "retained actual outputs and fixture evidence required"
  let processes ← run "/bin/ps" #["-axo","command="]
  let mut paths := #[]
  for (tag,_) in controls do
    for path in [base/(tag++"-result"),base/(tag++".log")] do
      if ← path.pathExists then paths := paths.push path
  paths := paths.push output
  for entry in ← (base/"allocator-service-build").readDir do
    if entry.fileName.endsWith ".c" || entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then paths := paths.push entry.path
  let mut removed := #[]
  for path in paths do
    check (!processes.contains path.toString) "allocator data path remains active"
    let (files,bytes) ← removeTree path
    removed := removed.push (path.toString,files,bytes)
  protectedInputs
  IO.FS.writeFile (destination/"cleanup.json") (Json.mkObj [("removed",toJson removed),
    ("files",toJson (removed.foldl (fun n value => n+value.2.1) 0)),
    ("logicalBytes",toJson (removed.foldl (fun n value => n+value.2.2) 0)),
    ("archive",toJson false),("originalsAndRequiredServiceLinkInputsRetained",toJson true)]).compress
def restoreStudy : IO Unit := do
  discard <| drained
  protectedInputs
  let core := base/"interest-traffic-core"
  for study in ["allocator-profile","owner-metadata-image","immutable-deadline","readonly-pages","owned-receive",
      "numerical-capacity","numerical-waits","numerical-stages","numerical-ready","provider-stages","query-stages","shared-leases"] do
    let path := workspace/"docs/candidates"/study/(if study == "shared-leases" then "combined.patch" else "candidate.patch")
    discard <| run "/usr/bin/git" #["-C",core.toString,"apply","--reverse","--unidiff-zero","--check",path.toString]
    discard <| run "/usr/bin/git" #["-C",core.toString,"apply","--reverse","--unidiff-zero",path.toString]
  let helper := core/"tools/research/AllocatorServiceChecks.lean"
  check ((← IO.FS.readFile helper) == (← IO.FS.readFile (workspace/"tools/research/AllocatorServiceChecks.lean"))) "allocator service helper changed"
  IO.FS.removeFile helper
  protectedInputs
  write (destination/"restoration.json") (Json.mkObj [("allOverlaysReversed",toJson true),("adopted",toJson false)])
def completeStudy : IO Unit := do
  let controls ← drained
  protectedInputs
  for file in ["bodies.json","evidence.json","controls.json"] do
    let value ← read (destination/file)
    check ((← IO.ofExcept (Json.parse value.compress)) == value) "formatting changed allocator evidence"
    IO.FS.writeFile (destination/file) value.compress
  script "docs/candidates/shared-leases/records.lean" #["--allocator-profile","verify","35"]
  let frozen ← read (destination/"seal.json")
  check (frozen.getObjValD "runtimeSha256" == toJson (← hash (base/"allocator-service-build/StudyMain")) &&
    frozen.getObjValD "parentRuntimeSha256" == toJson (← hash (base/"owner-metadata-image-build/StudyMain")) &&
    frozen.getObjValD "clientSha256" == toJson (← hash (base/"numerical-stages-client-build/StudyMain"))) "retained service runtime changed"
  discard <| run "/usr/bin/git" #["diff","--quiet","--","Eggshell","Main.lean"]
  check ((← read (destination/"restoration.json")).getObjValD "allOverlaysReversed" == toJson true &&
    (← read (destination/"cleanup.json")).getObjValD "archive" == toJson false) "allocator restoration/cleanup incomplete"
  write (destination/"completion.json") (Json.mkObj [("guardsDrained",toJson controls.size),
    ("actualOutputsVerifiedAfterDeletion",toJson (35 : Nat)),("protectedOriginalsUnchanged",toJson true),
    ("productCoreUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("paidComparisons",toJson "0/18"),("adopted",toJson false)])
def generate : IO Unit := do
  check (!(← (destination/"completion.json").pathExists)) "preserve sealed allocator study"
  if ← output.pathExists then
    check ((← output.readDir).isEmpty) "preserve preceding allocator outputs"
  IO.FS.createDirAll output
  let source := workspace/"tools/research/AllocatorProfile.lean"
  discard <| run (allocatorToolchain/"bin/lean").toString #["-j1","-M1536","-c",(output/"profile.c").toString,
    "-o",(output/"AllocatorProfile.olean").toString,source.toString]
  let generated ← IO.FS.readFile (output/"profile.c")
  let declarations := (generated.splitOn "\n").filter fun line => line.contains "eggshell_research_allocator_"
  write (destination/"abi.json") (Json.mkObj [("generatedDeclarationsAndCalls",toJson declarations),
    ("leanSourceSha256",toJson (← hash source)),
    ("nativeAdapterSha256",toJson (← hash (workspace/"tools/research/native/allocator_probe.c"))),
    ("toolchainRuntimeSha256",toJson (← hash (allocatorToolchain/"lib/lean/libleanrt.a")))])
def link : IO Unit := do
  let abi ← read (destination/"abi.json")
  check (abi.getObjValD "leanSourceSha256" == toJson (← hash (workspace/"tools/research/AllocatorProfile.lean")) &&
    abi.getObjValD "nativeAdapterSha256" == toJson (← hash (workspace/"tools/research/native/allocator_probe.c"))) "allocator build input changed"
  discard <| run (allocatorToolchain/"bin/leanc").toString #["-c","-O2","-o",(output/"profile.o").toString,(output/"profile.c").toString]
  let sdk := (← run "/usr/bin/xcrun" #["--show-sdk-path"]).trimAscii.toString
  discard <| run (allocatorToolchain/"bin/leanc").toString #["-c","-O2","-Wall","-Wextra","-Werror","-isysroot",sdk,
    "-isystem",sdk++"/usr/include",
    "-o",(output/"allocator_probe.o").toString,(workspace/"tools/research/native/allocator_probe.c").toString]
  discard <| run (allocatorToolchain/"bin/leanc").toString #["-Wl,-dead_strip","-o",(output/"StudyMain").toString,
    (output/"profile.o").toString,(output/"allocator_probe.o").toString]
  let symbols ← run "/usr/bin/nm" #["-g",(output/"StudyMain").toString]
  check (((symbols.splitOn "\n").filter (·.endsWith " T _mi_version")).length == 1) "allocator symbol was absent or duplicated"
  write (destination/"build.json") (Json.mkObj [("runtimeSha256",toJson (← hash (output/"StudyMain"))),
    ("leanSourceSha256",abi.getObjValD "leanSourceSha256"),("nativeAdapterSha256",abi.getObjValD "nativeAdapterSha256"),
    ("toolchainRuntimeSha256",abi.getObjValD "toolchainRuntimeSha256"),("noAdditionalAllocatorLibrary",toJson true),
    ("sdk",toJson sdk),("noPythonOrRuby",toJson true),("nativeBoundaryDiagnosticOnly",toJson true)])
def setup (action tag : String) : IO Unit := do
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh allocator guard tag required"
  let serviceHash ← if action == "service-hooks" then hash (base/"allocator-service-build/StudyMain") else pure ""
  let command := if ["generate","link","service-ffi","service-build","record","cleanup","restore","complete"].contains action then
      #[(allocatorToolchain/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/AllocatorStudy.lean").toString,action]
    else if action == "service-checks" then #[(base/"allocator-service-build/StudyMain").toString,
      "allocator-service-check",(base/(tag++"-result")).toString]
    else if action == "service-audit" then #[(allocatorToolchain/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildClosureAudit.lean").toString,"compare-sources",
      (base/"owner-metadata-image-build").toString,(base/"allocator-service-build").toString,
      (destination/"native-service-sources.json").toString,"Eggshell.OperationPool","Eggshell.PublicationService",
      "Eggshell.CanonicalSourcePrepared","tools.research.SharedMetadataCache","Eggshell.ContractAudit",
      "+tools.research.AllocatorDiagnostics"]
    else if action == "service-hooks" then #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
      "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
      "PLUGIN_ROOT="++(base/"worker-cpu-target").toString,"EGGSHELL_TRACE_SERVICE_PROFILE=1",
      "EGGSHELL_TRACE_QUERY_STAGES=1","EGGSHELL_TRACE_NUMERICAL_STAGES=1","EGGSHELL_TRACE_ALLOCATOR=1",
      (base/"numerical-stages-client-build/StudyMain").toString,(base/(tag++"-result")).toString,
      (base/"allocator-service-build/StudyMain").toString,serviceHash]
    else #["/usr/bin/env","LEAN_NUM_THREADS=1",(output/"StudyMain").toString,(base/(tag++"-result")).toString,action]
  write path (Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def serviceFfi : IO Unit := do
  let target := base/"allocator-service-ffi"
  check (!(← target.pathExists)) "preserve service allocator adapter"
  IO.FS.createDirAll target
  let source := workspace/"tools/research/native/allocator_probe.c"
  IO.FS.writeFile (target/"adapter.c.txt") (← IO.FS.readFile source)
  let sdk := (← run "/usr/bin/xcrun" #["--show-sdk-path"]).trimAscii.toString
  discard <| run (allocatorToolchain/"bin/leanc").toString #["-c","-O2","-Wall","-Wextra","-Werror",
    "-isysroot",sdk,"-isystem",sdk++"/usr/include","-o",(target/"adapter.o").toString,source.toString]
  write (destination/"service-adapter.json") (Json.mkObj [("sourceSha256",toJson (← hash source)),
    ("objectSha256",toJson (← hash (target/"adapter.o"))),("sdk",toJson sdk),
    ("noGlobalCounterMergeOrCollectionInOwnerObserver",toJson true)])
def serviceBuild : IO Unit := do
  let parent := base/"owner-metadata-image-build"
  let wrapper := base/"allocator-service-base"
  IO.FS.createDirAll wrapper
  IO.FS.writeFile (wrapper/"object-mapping.json") (← IO.FS.readFile (parent/"object-mapping.json"))
  let parentBuild ← read (parent/"build.json")
  write (wrapper/"build.json") (parentBuild.setObjVal! "settings"
    ((parentBuild.getObjValD "settings").setObjVal! "output" (toJson wrapper.toString)))
  IO.FS.writeFile (wrapper/"runtime.rsp") ((← IO.FS.readFile (parent/"runtime.rsp"))++
    (toJson (base/"allocator-service-ffi/adapter.o").toString).compress++"\n")
  let mut settings ← read (base/"owner-metadata-image-build-settings.json")
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  settings := settings.setObjVal! "parents" (toJson (#[parent.toString]++parents))
  for (key,value) in [("output",(base/"allocator-service-build").toString),
      ("baselineResponse",(wrapper/"runtime.rsp").toString),
      ("baselineMain",(parent/"tools_research_OwnerMetadataChecks.o").toString),
      ("objectModules",(wrapper/"object-mapping.json").toString),
      ("mainModule","tools.research.AllocatorServiceChecks")] do
    settings := settings.setObjVal! key (toJson value)
  let path := base/"allocator-service-build-settings.json"
  write path settings
  discard <| run (allocatorToolchain/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
def coherentHeapSetup (action tag : String) : IO Unit := do
  check (["build","hooks"].contains action) "unknown coherent heap action"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh coherent heap tag required"
  let target := base/"transport-heap-coherent-build/StudyMain"
  let runtimeHash ← if action == "hooks" then hash target else pure ""
  let args := if action == "build" then #[(allocatorToolchain/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"transport-heap-coherent-settings.json").toString]
    else #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=1","EGGSHELL_TRACE_QUERY_STAGES=1",
      "EGGSHELL_TRACE_NUMERICAL_STAGES=1","EGGSHELL_TRACE_ALLOCATOR=1","EGGSHELL_TRACE_ACTOR_HEAP=1",
      "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
      "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
      (base/"numerical-stages-client-build/StudyMain").toString,(base/(tag++"-result")).toString,target.toString,runtimeHash]
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def heapDistribution (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("count",toJson sorted.size),("min",toJson sorted[0]?),
    ("median",toJson sorted[sorted.size/2]?),("max",toJson sorted.back?)]
def heapControls (mode : String) : IO (Array (String × Json)) := do
  let mut controls := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith (mode++"-") && entry.fileName.endsWith ".guard.json" do continue
    let value ← read entry.path
    check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "heap control not terminal"
    let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString (number value "guardPid"),"-o","pid="]}
    check (probe.exitCode != 0 && probe.stdout.trimAscii.isEmpty) "heap control guard remains live"
    controls := controls.push (entry.fileName,value)
  return controls
def actorHeapRecord (transport : Bool := false) (coherent : Bool := false) (service : Bool := false) : IO Unit := do
  let mode := if transport then "transport-heap" else "actor-heap"
  let study := workspace/"docs/candidates"/mode
  let target := base/(if coherent then "transport-heap-coherent-build" else mode++"-build")
  let tag := if service then "transport-heap-service-hook16-1" else if coherent then "transport-heap-coherent-hook16-1" else mode++"-hook16-1"
  let root := base/(tag++"-result")
  let controls ← heapControls mode
  protectedInputs
  let build ← read (study/(if service then "service-build.json" else if coherent then "coherent-build.json" else "build.json"))
  check (build.getObjValD "runtimeSha256" == toJson (← hash (target/"StudyMain"))) "selected heap runtime changed"
  let existing ← if ← (study/"evidence.json").pathExists then read (study/"evidence.json") else pure Json.null
  if !(arr existing "runs").any (fun row => row.getObjValD "tag" == toJson tag) then
    script "docs/candidates/shared-leases/records.lean" #["--"++mode,tag]
  let evidence ← read (study/"evidence.json")
  let count := (arr evidence "runs").foldl (fun n run => n+(arr run "rowsIncludingPrime").size) 0
  script "docs/candidates/shared-leases/records.lean" #["--"++mode,"verify",toString count]
  let some trial := (arr evidence "runs").find? (fun row => row.getObjValD "tag" == toJson tag) |
    throw (IO.userError "heap hook trial missing")
  let some before := (arr (← read (destination/"evidence.json")) "runs").find? (fun row => row.getObjValD "tag" == toJson "allocator-service-hook16-1") |
    throw (IO.userError "sealed parent hook trial missing")
  let measured := (arr trial "rowsIncludingPrime").filter fun row => ((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-wave-"
  let previous := (arr before "rowsIncludingPrime").filter fun row => ((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-wave-"
  check (measured.size == 32 && previous.size == 32) "heap hook domain changed"
  for row in previous do
    check (measured.any fun next => next.getObjValD "session" == row.getObjValD "session" &&
      next.getObjValD "stdoutSha256" == row.getObjValD "stdoutSha256") "heap observer changed actual output bytes"
  let mut stages : Std.HashMap String (Array Json) := {}
  let mut profiles := #[]
  for directory in ← (root/"private/receipts").readDir do
    unless ← directory.path.isDir do continue
    for file in ← directory.path.readDir do
      unless file.fileName.endsWith ".json" do continue
      let record ← read file.path
      let value := record.getObjValD "data"
      if file.fileName == "request-pages.json" then
        for row in arr value "ownerHeapStages" do
          let pair ← IO.ofExcept (fromJson? row : Except String (String × Json))
          stages := stages.insert pair.1 ((stages[pair.1]?.getD #[]).push pair.2)
      let owner := value.getObjValD "ownerHeap"
      if owner != Json.null then
        let label := (file.fileName.dropEnd 5 |>.toString)++"/"++((value.getObjValAs? String "kind").toOption.getD "")
        stages := stages.insert label ((stages[label]?.getD #[]).push owner)
        profiles := profiles.push (Json.mkObj [("receipt",toJson directory.fileName),("pid",record.getObjValD "pid"),("stage",toJson label),("data",value)])
  for label in ["restore-request:start","restore-request:end","execute:start","execute:end","actor-finalized"] do
    check ((stages[label]?.getD #[]).size == 35) "fixed actor ownership observations missing"
  if transport then check (!profiles.isEmpty) "actual transport owner observations missing"
  let summary := (stages.toArray.qsort (fun a b => a.1 < b.1)).map fun (label,values) => Json.mkObj [
    ("stage",toJson label),("used",heapDistribution (values.map (number · "ownerUsedBytes"))),
    ("committed",heapDistribution (values.map (number · "ownerCommittedBytes"))),
    ("reserved",heapDistribution (values.map (number · "ownerReservedBytes")))]
  write (study/"heap-stages.json") (Json.mkObj [("summary",toJson summary),("profiles",toJson profiles),
    ("notWholeProcessLiveReachability",toJson true),("allActorStageRowsRetainedInEvidence",toJson true)])
  let objects ← IO.ofExcept (build.getObjValAs? (Array String) "selectedObjects")
  let changed := objects.filter (·.startsWith target.toString)
  if coherent then
    check ((← read (study/(if service then "service-native-sources.json" else "coherent-native-sources.json"))).getObjValD "exactExpectedChangeSet" == toJson true) "coherent source change audit failed"
  else check (changed.size == (if transport then 3 else 2)) "undeclared native observer module set"
  let hashes ← changed.mapM fun path => do return (path,← hash (.mk path),← hash ((System.FilePath.mk path).withExtension "source"))
  if transport && !coherent then
    let beforeStream := base/"readonly-pages-build/Eggshell_PublicationStream.source"
    let old ← IO.ofExcept (fromJson? (← read beforeStream) : Except String (String × Array (String × String)))
    IO.FS.writeFile (target/"before-stream.lean") old.1
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/PublicationStream.lean","--label","b/Eggshell/PublicationStream.lean",
      (target/"before-stream.lean").toString,(target/"Eggshell/PublicationStream.lean").toString]}
    check (patch.exitCode == 1) "transport observer diff missing"
    IO.FS.writeFile (study/"transport.patch") patch.stdout
  write (study/"controls.json") (Json.mkObj [("guards",toJson controls),("changedNativeObjectAndSourceHashes",toJson hashes),
    ("completeStdoutByteEqualToParent",toJson (32 : Nat)),("actualOutputsIncludingPriorFailuresVerified",toJson count),
    ("protected16HeadsAnd5InputsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("paidComparisons",toJson "0/18"),("adopted",toJson false)])
def coherentHeapSeal (service : Bool := false) : IO Unit := do
  let target := base/"transport-heap-coherent-build"
  let study := workspace/"docs/candidates/transport-heap"
  let controls ← heapControls "transport-heap-coherent"
  check (!controls.isEmpty && controls.all (fun (_,value) => value.getObjValD "exitCode" == toJson (0 : Nat))) "coherent native build did not complete"
  let audit := study/(if service then "service-native-sources.json" else "coherent-native-sources.json")
  if ← audit.pathExists then
    if (← read audit).getObjValD "exactExpectedChangeSet" != toJson true then
      let rejected := study/"coherent-audit-argument-error.json"
      check (!(← rejected.pathExists)) "preserve previous audit rejection"
      IO.FS.rename audit rejected
  if !(← audit.pathExists) then
    script "tools/research/StudyBuildClosureAudit.lean" (#["compare-sources",(base/"allocator-service-build").toString,target.toString,
      audit.toString,"Eggshell.OperationPool","Eggshell.PublicationStream"]++if service then #["Eggshell.PublicationService"] else #[])
  let objects ← ((← IO.FS.readFile (target/"runtime.rsp")).splitOn "\n").filterMapM fun row => do
    if row.trimAscii.isEmpty then return none
    return some (← IO.ofExcept (Json.parse row >>= Json.getStr?))
  write (study/(if service then "service-build.json" else "coherent-build.json")) (Json.mkObj [("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("parentRuntimeSha256",toJson (← hash (base/"allocator-service-build/StudyMain"))),
    ("selectedObjects",toJson objects),("sourceChangeAudit",← read audit),
    ("selectedInterfacesAndFullDependencyClosureChecked",toJson true),("adopted",toJson false)])
def serviceHeapPrepare : IO Unit := do
  let study := workspace/"docs/candidates/transport-heap"
  let source : System.FilePath := base/"transport-heap-coherent-source/Eggshell/PublicationService.lean"
  let text ← IO.FS.readFile source
  let previous := "def profile (stage : String) (fields : List (String × Json)) : IO Unit := do\n  if (← IO.getEnv \"EGGSHELL_TRACE_SERVICE_PROFILE\") == some \"1\" then\n    Receipt.observe (some (← Receipt.fresh)) stage (Json.mkObj fields)\n"
  check ((text.splitOn previous).length == 2) "duplicated service profile boundary changed"
  for name in ["coherent-build.json","heap-stages.json","controls.json"] do
    let path := study/("stream-only-"++name)
    check (!(← path.pathExists)) "preserve first coherent observation"
    write path (← read (study/name))
  let replacement := "def profile (stage : String) (fields : List (String × Json)) : IO Unit :=\n  Stream.profile stage fields\n\ntheorem profile_uses_shared_diagnostics (stage : String) (fields : List (String × Json)) :\n    profile stage fields = Stream.profile stage fields := rfl\n"
  IO.FS.writeFile (base/"transport-heap-coherent-source/service-profile-before.lean") text
  IO.FS.writeFile source (text.replace previous replacement)
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/PublicationService.lean","--label","b/Eggshell/PublicationService.lean",
    (base/"transport-heap-coherent-source/service-profile-before.lean").toString,source.toString]}
  check (patch.exitCode == 1) "shared profile delegation diff missing"
  IO.FS.writeFile (study/"service-profile.patch") patch.stdout
def coherentHeapPrepare : IO Unit := do
  let parent := base/"allocator-service-build"
  let sourceRoot := base/"transport-heap-coherent-source"
  let target := base/"transport-heap-coherent-build"
  let study := workspace/"docs/candidates/transport-heap"
  check (!(← sourceRoot.pathExists)) "preserve materialized coherent source"
  IO.FS.createDirAll sourceRoot
  let parentBuild ← read (parent/"build.json")
  let mut mapping ← read (parent/"object-mapping.json")
  for row in arr parentBuild "modules" do
    let path ← IO.ofExcept (row.getObjValAs? String "object")
    let name ← IO.ofExcept (row.getObjValAs? String "module")
    mapping := mapping.setObjVal! path (toJson name)
  let objects ← ((← IO.FS.readFile (parent/"runtime.rsp")).splitOn "\n").filterMapM fun row => do
    if row.trimAscii.isEmpty then return none
    return some (← IO.ofExcept (Json.parse row >>= Json.getStr?))
  let mut files : Std.HashMap String String := {}
  let mut includes := #[]
  let mut modules := #[]
  for object in objects do
    let witness := (System.FilePath.mk object).withExtension "source"
    unless ← witness.pathExists do continue
    let name ← IO.ofExcept (mapping.getObjValAs? String object)
    let source := sourceRoot/(name.replace "." "/"++".lean")
    let stamp ← IO.ofExcept (fromJson? (← read witness) : Except String (String × Array (String × String)))
    files := files.insert source.normalize.toString stamp.1
    for (relative,bytes) in stamp.2 do
      includes := includes.push ((source.parent.get!/relative).normalize.toString,bytes)
    modules := modules.push (name,object,← hash witness)
  let mut conflicts := #[]
  for (path,bytes) in includes do
    check (path.startsWith sourceRoot.toString) "embedded source escaped materialized root"
    if let some existing := files[path]? then
      if existing != bytes then conflicts := conflicts.push path
    else files := files.insert path bytes
  write (study/"coherent-input-audit.json") (Json.mkObj [("parentModules",toJson modules),("conflictingEmbeddedSources",toJson conflicts)])
  check (conflicts.isEmpty) "parent source witnesses disagree with embedded identity inputs"
  for (path,bytes) in files do
    let path := System.FilePath.mk path
    IO.FS.createDirAll path.parent.get!
    IO.FS.writeFile path bytes
  for patch in [workspace/"docs/candidates/actor-heap/observer.patch",study/"transport.patch",study/"service-profile.patch"] do
    let applied ← IO.Process.output {cmd := "/usr/bin/git",args := #["apply","--unidiff-zero",patch.toString],cwd := some sourceRoot}
    check (applied.exitCode == 0) ("cannot apply recorded observer source: "++applied.stderr)
  IO.FS.createDirAll (sourceRoot/".lake/build/lib")
  discard <| run "/bin/ln" #["-s",(parent/"lib").toString,(sourceRoot/".lake/build/lib/lean").toString]
  write (sourceRoot/"object-mapping.json") mapping
  let mut settings := parentBuild.getObjValD "settings"
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  settings := settings.setObjVal! "parents" (toJson (#[parent.toString]++parents))
  for (key,value) in [("project",sourceRoot.toString),("core",sourceRoot.toString),("output",target.toString),
      ("baselineResponse",(parent/"runtime.rsp").toString),
      ("baselineMain",(parent/"tools_research_AllocatorServiceChecks.o").toString),
      ("objectModules",(sourceRoot/"object-mapping.json").toString)] do
    settings := settings.setObjVal! key (toJson value)
  settings := settings.setObjVal! "force" (toJson (#[] : Array String))
  write (base/"transport-heap-coherent-settings.json") settings
def finishHeapStudy : IO Unit := do
  protectedInputs
  check ((← IO.FS.realPath (base/"worker-cpu-target/bin/eggshelld")) == base/"allocator-service-build/StudyMain") "restore active parent alias before cleanup"
  for (mode,count) in [("actor-heap",35),("transport-heap",73)] do
    script "docs/candidates/shared-leases/records.lean" #["--"++mode,"verify",toString count]
  let controls ← heapControls "transport-heap"
  let study := workspace/"docs/candidates/transport-heap"
  check ((← read (study/"controls.json")).getObjValD "guards" == toJson controls) "record final heap guards before cleanup"
  let build ← read (study/"service-build.json")
  check (build.getObjValD "runtimeSha256" == toJson (← hash (base/"transport-heap-coherent-build/StudyMain"))) "current diagnostic runtime changed"
  let processes ← run "/bin/ps" #["-axo","command="]
  let mut paths := #[base/"transport-heap-coherent-source/service-profile-before.lean"]
  for (name,_) in controls do
    let tag := name.dropEnd 11 |>.toString
    for suffix in ["-result",".log",".guard-settings.json"] do paths := paths.push (base/(tag++suffix))
  let mut compileLogs := #[]
  for entry in ← (base/"transport-heap-coherent-build").readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
      compileLogs := compileLogs.push (entry.fileName,← hash entry.path,(← IO.FS.readFile entry.path).utf8ByteSize)
      paths := paths.push entry.path
  let mut removed := #[]
  for path in paths do
    unless ← path.pathExists do continue
    check (!processes.contains path.toString) "retired diagnostic path remains active"
    let (files,bytes) ← removeTree path
    removed := removed.push (path.toString,files,bytes)
  protectedInputs
  write (study/"coherent-cleanup.json") (Json.mkObj [("removed",toJson removed),("compileLogDigests",toJson compileLogs),
    ("archive",toJson false),("logicalBytes",toJson (removed.foldl (fun n row => n+row.2.2) 0)),
    ("currentValidatedDiagnosticRuntimeSourceAndLinkInputsRetained",toJson true),("originalsAndActiveParentUnchanged",toJson true)])
def compactHeapRecords : IO Unit := do
  for name in ["phase-lifetime","actor-heap","transport-heap","typed-original-reads"] do
    for entry in ← (workspace/"docs/candidates"/name).readDir do
      if entry.fileName.endsWith ".json" then
        IO.FS.writeFile entry.path (← read entry.path).compress
  let duplicate := workspace/"docs/candidates/transport-heap/observer.patch"
  if ← duplicate.pathExists then
    check ((← IO.FS.readFile duplicate) == (← IO.FS.readFile (workspace/"docs/candidates/actor-heap/observer.patch")))
      "transport observer is not a duplicate"
    IO.FS.removeFile duplicate
def main (args : List String) : IO Unit := do
  match args with
  | ["setup",action,tag] => setup action tag
  | ["generate"] => generate
  | ["link"] => link
  | ["service-ffi"] => serviceFfi
  | ["service-build"] => serviceBuild
  | ["record"] => recordStudy
  | ["cleanup"] => cleanStudy
  | ["restore"] => restoreStudy
  | ["complete"] => completeStudy
  | ["actor-heap-record"] => actorHeapRecord
  | ["transport-heap-record"] => actorHeapRecord true
  | ["coherent-heap-prepare"] => coherentHeapPrepare
  | ["heap-finish"] => finishHeapStudy
  | ["heap-compact"] => compactHeapRecords
  | ["coherent-heap-setup",action,tag] => coherentHeapSetup action tag
  | ["coherent-heap-seal"] => coherentHeapSeal
  | ["coherent-heap-record"] => actorHeapRecord true true
  | ["service-heap-prepare"] => serviceHeapPrepare
  | ["service-heap-seal"] => coherentHeapSeal true
  | ["service-heap-record"] => actorHeapRecord true true true
  | _ => throw (IO.userError "AllocatorStudy setup ACTION FRESH_TAG | generate | link")
