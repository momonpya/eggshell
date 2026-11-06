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
  | _ => throw (IO.userError "AllocatorStudy setup ACTION FRESH_TAG | generate | link")
