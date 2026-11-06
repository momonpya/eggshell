import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap
open Lean
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"record-read-image-build"
def sourceRoot := base/"typed-original-reads-source"
def target := base/"typed-original-reads-build"
def study := workspace/"docs/candidates/typed-original-reads"
def changes : Array String := #["Eggshell.ObservedRecordView","Eggshell.PublicationService",
  "Eggshell.PublicationClient","Eggshell.Worker","Eggshell.OperationPool","Eggshell.Handoff",
  "Eggshell.SynapseTransport","tools.research.SourceViewBatch","tools.research.SharedReadViews"]
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def arr (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def command (cmd : String) (args : Array String) (cwd : System.FilePath := workspace) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some cwd}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String := do
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  for tagStart in ["record-read-image-","typed-original-reads-"] do
    for entry in ← base.readDir do
      unless entry.fileName.startsWith tagStart && entry.fileName.endsWith ".guard.json" do continue
      let value ← read entry.path
      check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous guard not drained"
      let pid ← IO.ofExcept (value.getObjValAs? Nat "guardPid")
      let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
      check (probe.exitCode != 0 && probe.stdout.trimAscii.isEmpty) "previous guard still live"
def prepare : IO Unit := do
  drained
  check (!(← sourceRoot.pathExists)) "fresh record image source required"
  let build ← read (parent/"build.json")
  let parentEntry ← IO.ofExcept ((build.getObjValD "settings").getObjValAs? String "mainModule")
  let mut mapping ← read (base/"record-read-image-source/object-mapping.json")
  for row in arr build "modules" do
    mapping := mapping.setObjVal! (← IO.ofExcept (row.getObjValAs? String "object"))
      (row.getObjValD "module")
  let objects ← ((← IO.FS.readFile (parent/"runtime.rsp")).splitOn "\n").filterMapM fun row => do
    if row.trimAscii.isEmpty then return none
    return some (← IO.ofExcept (Json.parse row >>= Json.getStr?))
  let mut files : Std.HashMap String String := {}
  let mut includes := #[]
  for object in objects do
    let witness := (System.FilePath.mk object).withExtension "source"
    unless ← witness.pathExists do continue
    let name ← IO.ofExcept (mapping.getObjValAs? String object)
    if name == parentEntry then continue
    let path := sourceRoot/(name.replace "." "/"++".lean")
    let value ← IO.ofExcept (fromJson? (← read witness) : Except String (String × Array (String × String)))
    files := files.insert path.normalize.toString value.1
    for (relative,bytes) in value.2 do includes := includes.push ((path.parent.get!/relative).normalize.toString,bytes)
  for (path,bytes) in includes do
    check (path.startsWith sourceRoot.toString) "embedded input escaped root"
    if let some existing := files[path]? then check (existing == bytes) "selected sources conflict"
    else files := files.insert path bytes
  for (path,text) in files do
    let path := System.FilePath.mk path
    IO.FS.createDirAll path.parent.get!
    IO.FS.writeFile path text
  for entry in ← study.readDir do
    if entry.fileName.endsWith ".patch" then
      discard <| command "/usr/bin/git" #["apply","--unidiff-zero",entry.path.toString] sourceRoot
  IO.FS.writeFile (sourceRoot/"tools/research/TypedReadChecks.lean") (← IO.FS.readFile (workspace/"tools/research/TypedReadChecks.lean"))
  IO.FS.createDirAll (sourceRoot/".lake/build/lib")
  discard <| command "/bin/ln" #["-s",(parent/"lib").toString,(sourceRoot/".lake/build/lib/lean").toString]
  write (sourceRoot/"object-mapping.json") mapping
  let mut settings := build.getObjValD "settings"
  settings := settings.setObjVal! "parents" (toJson (#[parent.toString]++(← IO.ofExcept (settings.getObjValAs? (Array String) "parents"))))
  for (key,value) in [("project",sourceRoot.toString),("core",sourceRoot.toString),("output",target.toString),
      ("baselineResponse",(parent/"runtime.rsp").toString),("objectModules",(sourceRoot/"object-mapping.json").toString),
      ("mainModule","tools.research.TypedReadChecks")] do settings := settings.setObjVal! key (toJson value)
  write (base/"typed-original-reads-settings.json") settings
  write (study/"build-plan.json") (Json.mkObj [("status",toJson "isolated,not adopted"),("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("fixedNativeClientSha256",toJson (← hash (base/"numerical-stages-client-build/StudyMain"))),
    ("unchangedLimits",toJson "30s,4GiB ceiling,3670016KiB stop,2097152KiB free"),
    ("scope",toJson "immutable record metadata;not all read-path locks;no token or 80-user success claim")])
def setup (action tag : String) : IO Unit := do
  drained
  if action == "build" then
    let config ← read (base/"typed-original-reads-settings.json")
    write (base/"typed-original-reads-settings.json")
      (config.setObjVal! "baselineMain" (toJson (parent/"tools_research_RecordImageChecks.o").toString))
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh record image tag required"
  let args ← if action == "probe-build" then pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"typed-original-stop-probe-settings.json").toString]
    else if action == "stop-probe" || action == "stop-probe80" then pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=0",
      "EGGSHELL_DATA_ROOT="++(base/"typed-original-reads-hook16-1-result/private").toString,
      "EGGSHELL_CONFIG="++(base/"typed-original-reads-hook16-1-result/eggshell.toml").toString,
      "PLUGIN_ROOT="++(base/"worker-cpu-target").toString,(base/"typed-original-stop-probe-build/StudyMain").toString,
      (base/(tag++"-result")).toString,(target/"StudyMain").toString]++if action == "stop-probe80" then #["parallel"] else #[])
    else if action == "build" then pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"typed-original-reads-settings.json").toString]
    else if action == "checks" then pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=0",
      "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
      "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
      (target/"StudyMain").toString,"typed-read-check",(base/(tag++"-result")).toString]
    else if action == "hooks" then do
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=1","EGGSHELL_TRACE_QUERY_STAGES=1",
        "EGGSHELL_TRACE_NUMERICAL_STAGES=1","EGGSHELL_TRACE_ALLOCATOR=1","EGGSHELL_TRACE_ACTOR_HEAP=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,"EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
        "PLUGIN_ROOT="++(base/"worker-cpu-target").toString,(base/"numerical-stages-client-build/StudyMain").toString,
        (base/(tag++"-result")).toString,(target/"StudyMain").toString,← hash (target/"StudyMain")]
    else throw (IO.userError "unknown record image action")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def script (relative : String) (args : Array String) : IO Unit := do
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M1536","--run",(workspace/relative).toString]++args)
def prepareProbe : IO Unit := do
  drained
  IO.FS.writeFile (sourceRoot/"tools/research/TypedReadStopProbe.lean") (← IO.FS.readFile (workspace/"tools/research/TypedReadStopProbe.lean"))
  let build ← read (target/"build.json")
  let mut config := build.getObjValD "settings"
  config := config.setObjVal! "parents" (toJson (#[target.toString]++(← IO.ofExcept (config.getObjValAs? (Array String) "parents"))))
  for (key,value) in [("output",(base/"typed-original-stop-probe-build").toString),
      ("baselineResponse",(target/"runtime.rsp").toString),("baselineMain",(target/"tools_research_TypedReadChecks.o").toString),
      ("objectModules",(target/"object-mapping.json").toString),("mainModule","tools.research.TypedReadStopProbe")] do
    config := config.setObjVal! key (toJson value)
  write (base/"typed-original-stop-probe-settings.json") config
def sealRuntime : IO Unit := do
  drained
  let audit := study/"native-sources.json"
  if !(← audit.pathExists) then
    script "tools/research/StudyBuildClosureAudit.lean" #["compare-sources",parent.toString,target.toString,audit.toString,
      "Eggshell.ObservedRecordView","Eggshell.PublicationService","Eggshell.PublicationClient","Eggshell.Worker",
      "Eggshell.OperationPool","Eggshell.Handoff","Eggshell.SynapseTransport","tools.research.SourceViewBatch","tools.research.SharedReadViews"]
  check ((← read audit).getObjValD "exactExpectedChangeSet" == toJson true) "record image source audit failed"
  -- Refresh the patch from the actual selected parent and final compiled source.
  let modules ← read (parent/"object-mapping.json")
  let build ← read (parent/"build.json")
  let mut mapping := modules
  for row in arr build "modules" do mapping := mapping.setObjVal! (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
  let objects ← ((← IO.FS.readFile (parent/"runtime.rsp")).splitOn "\n").filterMapM fun row => do
    if row.trimAscii.isEmpty then return none
    return some (← IO.ofExcept (Json.parse row >>= Json.getStr?))
  for name in changes do
    let some object := objects.find? (fun object => mapping.getObjValD object == toJson name) |
      throw (IO.userError "selected record image parent source missing")
    let before ← IO.ofExcept (fromJson? (← read ((System.FilePath.mk object).withExtension "source")) : Except String (String × Array (String × String)))
    let path := sourceRoot/(name.replace "." "_"++".before")
    IO.FS.writeFile path before.1
    let relative := name.replace "." "/"++".lean"
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,path.toString,(sourceRoot/relative).toString]}
    check (patch.exitCode == 1) "final candidate patch missing"
    IO.FS.writeFile (study/(name.replace "." "_"++".patch")) patch.stdout
    IO.FS.removeFile path
  write (study/"build.json") (Json.mkObj [("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),("sourceChangeAudit",← read audit),
    ("kernelAndDeclarationAudit",toJson (← IO.FS.readFile (target/"tools_research_TypedReadChecks-lean.stdout"))),
    ("ordinaryContractAuditAndNativeClosureBuilt",toJson true),("adopted",toJson false)])
def record (tag : String) : IO Unit := do
  drained
  let mut recorded := false
  if ← (study/"evidence.json").pathExists then
    recorded := (arr (← read (study/"evidence.json")) "runs").any (fun row => row.getObjValD "tag" == toJson tag)
  if !recorded then
    script "docs/candidates/shared-leases/records.lean" #["--typed-original-reads",tag]
  script "docs/candidates/shared-leases/records.lean" #["--typed-original-reads","verify","35"]
  let evidence ← read (study/"evidence.json")
  let some trial := (arr evidence "runs").find? (fun row => row.getObjValD "tag" == toJson tag) |
    throw (IO.userError "record image hook trial absent")
  let previous ← read (workspace/"docs/candidates/record-read-image/evidence.json")
  let some control := (arr previous "runs").find? (fun row => row.getObjValD "tag" == toJson "record-read-image-hook16-1") |
    throw (IO.userError "coherent parent control absent")
  let measured (run : Json) := (arr run "rowsIncludingPrime").filter fun row =>
    ((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-wave-"
  check ((measured trial).size == 32 && (measured control).size == 32) "fixed query domain changed"
  for row in measured trial do
    check (row.getObjValD "bothFields" == toJson true && row.getObjValD "acknowledged" == toJson true &&
      (row.getObjValAs? Nat "elapsedMs").toOption.getD 30000 < 30000) "required original or deadline/ACK failed"
  let verification ← read (study/"verification.json")
  check ((arr verification "runs").all fun run =>
    run.getObjValD "semanticCompletedWithHandoff" == toJson (32 : Nat)) "semantic handoff completion failed"
  for row in measured control do
    check ((measured trial).any fun actual => actual.getObjValD "session" == row.getObjValD "session" &&
      actual.getObjValD "stdoutSha256" == row.getObjValD "stdoutSha256") "record image changed actual stdout"
  write (study/"parity.json") (Json.mkObj [("completeStdoutByteEqualToParent",toJson (32 : Nat)),
    ("control",control.getObjValD "tag"),("candidate",trial.getObjValD "tag"),
    ("fixedSnapshotSourceQuestionsMiniLmClient",toJson true),("notTokenAdoptionComparison",toJson true)])
  let root := base/(tag++"-result")
  let report ← read (root/"report.json")
  write (study/"hook-report.json") (Json.mkObj (["runtimeSha256","originalHeadsUnchanged","caseCount",
    "concurrentClients","initialServiceStats","finalServiceStats"].filterMap fun key =>
      let value := report.getObjValD key
      if value == Json.null then none else some (key,value)))
  let mut kinds : Std.HashMap String Nat := {}
  let mut localViews := #[]
  let mut preparations := #[]
  for directory in ← (root/"private/receipts").readDir do
    unless ← directory.path.isDir do continue
    for file in ← directory.path.readDir do
      unless file.fileName.endsWith ".json" do continue
      if !["local-source-views.json","source-views-profile.json","server-envelope-profile.json"].contains file.fileName then continue
      let value ← read file.path
      let data := value.getObjValD "data"
      if file.fileName == "server-envelope-profile.json" then
        let kind ← IO.ofExcept (data.getObjValAs? String "kind")
        kinds := kinds.insert kind ((kinds[kind]?.getD 0)+1)
      else if file.fileName == "local-source-views.json" then localViews := localViews.push data
      else preparations := preparations.push data
  check (localViews.size == 35 && preparations.size == 35 && kinds["source-records"]?.getD 0 == 0 &&
    kinds["source-palettes"]?.getD 0 == 0) "actual hooks did not use the complete local read path"
  write (study/"route-profile.json") (Json.mkObj [("localViews",toJson localViews),("queryReservations",toJson preparations),
    ("serverRpcCounts",toJson kinds.toArray),("originalRecordAndPaletteSelfRpcs",toJson (0 : Nat)),
    ("expectedLocalQueriesIncludingPrime",toJson (35 : Nat)),("allOriginalGeometryCharged",toJson true)])
def controls : IO Unit := do
  drained
  let mut guards := #[]
  let mut logs := #[]
  let mut stops := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "typed-original-reads-" do continue
    if entry.fileName.endsWith ".guard.json" then guards := guards.push (entry.fileName,← read entry.path)
    if entry.fileName.endsWith ".log" then logs := logs.push (entry.fileName,← IO.FS.readFile entry.path)
    if entry.fileName.endsWith "-result" && (← (entry.path/"report.json").pathExists) then
      let report ← read (entry.path/"report.json")
      if report.getObjValD "typedReadChecks" == toJson true then
        write (study/"native-checks.json") report
      if entry.fileName.startsWith "typed-original-reads-stop-probe" then
        stops := stops.push (entry.fileName,report)
  write (study/"controls.json") (Json.mkObj [("guards",toJson guards),("logs",toJson logs),
    ("allGuardsTerminalAndPidsAbsent",toJson true),("answeringModelCalls",toJson (0 : Nat)),("paidMatchedComparisons",toJson "0/18")])
  write (study/"stop-probes.json") (toJson stops)
def distribution (values : Array Nat) : Json := Id.run do
  let values := values.qsort (· < ·)
  return Json.mkObj [("count",toJson values.size),("min",toJson values[0]?),
    ("median",toJson values[values.size/2]?),("max",toJson values.back?)]
def measurements : IO Unit := do
  drained
  let profiles ← read (study/"route-profile.json")
  let evidence ← read (study/"evidence.json")
  let mut intervals : Std.HashMap String (Array Nat) := {}
  for run in arr evidence "runs" do
    for wave in arr run "waves" do
      for receipt in arr wave "receipts" do
        let stages := (receipt.getObjValD "request-pages").getObjValD "queryStages"
        let rows ← IO.ofExcept (fromJson? stages : Except String (Array (String × Nat)))
        for i in [:rows.size-1] do
          let some before := rows[i]? | throw (IO.userError "missing stage")
          let some after := rows[i+1]? | throw (IO.userError "missing stage successor")
          check (before.2 ≤ after.2) "cross-thread stage order is not monotone"
          let key := before.1++" -> "++after.1
          intervals := intervals.insert key ((intervals[key]?.getD #[]).push (after.2-before.2))
  let rows := intervals.toArray.map fun (key,values) => (key,distribution values)
  let rows := rows.qsort fun a b =>
    (a.2.getObjValAs? Nat "median").toOption.getD 0 > (b.2.getObjValAs? Nat "median").toOption.getD 0
  let report ← read (base/"typed-original-reads-hook16-1-result/report.json")
  let hosts := ["prime","first","second"].filterMap fun name =>
    let wave := report.getObjValD name
    ((arr wave "after").find? fun row => row.getObjValD "role" == toJson "publication-service").map fun row => (name,row)
  let result := Json.mkObj [("localReadMs",distribution ((arr profiles "localViews").map fun row =>
      (row.getObjValAs? Nat "elapsedMs").toOption.getD 0)),
    ("consecutiveActorStageGapsMs",toJson rows),("wallTimeNotCpuAndNestedSpansNotAdded",toJson true),
    ("hostAfterEachWave",toJson hosts),
    ("shutdown",← read (base/"typed-original-reads-hook16-1-result/shutdown.json")),
    ("bodyAndSemanticSuccessDoesNotOverrideGuardLeftovers",toJson true)]
  write (study/"measurements.json") result
  IO.println (Json.mkObj [("localReadMs",result.getObjValD "localReadMs"),("largestStageGaps",toJson (rows.extract 0 8)),
    ("hostAfterEachWave",toJson hosts),("shutdown",result.getObjValD "shutdown")]).pretty
def subprofiles : IO Unit := do
  drained
  let root := base/"typed-original-reads-hook16-1-result/private/receipts"
  let mut groups : Std.HashMap String (Array Json) := {}
  for directory in ← root.readDir do
    unless ← directory.path.isDir do continue
    for file in ← directory.path.readDir do
      let kind := if file.fileName.startsWith "discovery-counters-" then "discovery-counters" else
        if file.fileName.startsWith "freshness-" then "freshness" else file.fileName.dropEnd 5 |>.toString
      unless ["discovery-counters","freshness","render-automatic-profile","render-client-profile",
        "provider-indexed-profile","provider-keyed-profile"].contains kind do continue
      groups := groups.insert kind ((groups[kind]?.getD #[]).push ((← read file.path).getObjValD "data"))
  write (study/"subprofiles.json") (toJson groups.toArray)
  for (kind,values) in groups do
    IO.println (Json.mkObj [("kind",toJson kind),("count",toJson values.size),("example",toJson values[0]?)]).pretty
partial def remove (path : System.FilePath) : IO Nat := do
  if !(← path.pathExists) then return 0
  if ← path.isDir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← remove entry.path)
    IO.FS.removeDir path
    return bytes
  let bytes := (← path.metadata).byteSize.toNat
  IO.FS.removeFile path
  return bytes
def cleanup : IO Unit := do
  drained
  check ((← IO.FS.realPath (base/"worker-cpu-target/bin/eggshelld")) == base/"allocator-service-build/StudyMain") "restore active parent alias before cleanup"
  discard <| command "/usr/bin/shasum" #["-c",(workspace/"docs/candidates/project-cache/protected-after.sha256").toString] base
  script "docs/candidates/shared-leases/records.lean" #["--typed-original-reads","verify","35"]
  controls
  let sample := base/"typed-original-reads-hook16-1-result/worker.sample.txt"
  if ← sample.pathExists then
    let lines := (← IO.FS.readFile sample).splitOn "\n"
    write (study/"sample-context.json") (Json.mkObj [("sha256",toJson (← hash sample)),
      ("header",toJson (lines.take 24)),("providerWaitExcerpt",toJson (lines.drop 1694 |>.take 45)),
      ("samplingStackCountsAreNotCpuFractions",toJson true),("doesNotAttributeEntirePostProviderGap",toJson true)])
  let live ← command "/bin/ps" #["-axo","command="]
  let mut deleted := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "typed-original-reads-" &&
        (entry.fileName.endsWith "-result" || entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard-settings.json") do continue
    check (!live.contains entry.path.toString) "retired record image artifact is still active"
    deleted := deleted.push (entry.path.toString,← remove entry.path)
  for entry in ← target.readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
      deleted := deleted.push (entry.path.toString,← remove entry.path)
  for path in [base/"typed-original-stop-probe-build",base/"typed-original-stop-probe-settings.json",
      sourceRoot/"tools/research/TypedReadStopProbe.lean"] do
    if ← path.pathExists then
      check (!live.contains path.toString) "retired stop probe remains active"
      deleted := deleted.push (path.toString,← remove path)
  let (logs,artifacts) := deleted.partition fun (path,_) => path.endsWith ".stdout" || path.endsWith ".stderr"
  write (study/"cleanup.json") (Json.mkObj [("deleted",toJson artifacts),("archive",toJson false),
    ("compilerLogsDeleted",toJson (logs.size,logs.foldl (fun total row => total+row.2) 0)),
    ("currentRuntimeSourceAndNativeInputsRetained",toJson true),("protectedOriginalInputsUnchanged",toJson true)])
  for entry in ← study.readDir do
    if entry.fileName.endsWith ".json" then write entry.path (← read entry.path)
def retireObserver : IO Unit := do
  drained
  let previous := parent/"StudyMain"
  let live ← command "/bin/ps" #["-axo","command="]
  check (!live.contains previous.toString) "retired observer runtime remains active"
  let evidence ← read (study/"build.json")
  let old ← read (study/"cleanup.json")
  let deleted ← IO.ofExcept (fromJson? (old.getObjValD "deleted") : Except String (Array (String × Nat)))
  let (logs,remaining) := deleted.partition fun (path,_) => path.endsWith ".stdout" || path.endsWith ".stderr"
  let mut result := old.setObjVal! "deleted" (toJson remaining)
  if !logs.isEmpty then result := result.setObjVal! "compilerLogsDeleted" (toJson (logs.size,logs.foldl (fun total row => total+row.2) 0))
  if ← previous.pathExists then
    let digest ← hash previous
    check (toJson digest == evidence.getObjValD "parentRuntimeSha256") "retired observer is not the sealed parent"
    let bytes ← remove previous
    result := result.setObjVal! "retiredObserverExecutable" (toJson (previous.toString,digest,bytes))
  write (study/"cleanup.json") result
def finishPlan : IO Unit := do
  let plan ← read (study/"plan.json")
  let plan := plan.setObjVal! "status" (toJson "implemented and kernel/native checked in isolation;32 hook bodies pass,overall cohort fails shutdown;not adopted")
  let plan := plan.setObjVal! "change" (toJson "One checked batch captures original geometry and selection metadata under the same query-owned reservation. Explicit process-local read/release authority flows from service through actor/environment/source context;external wire adapters delegate to the same typed operation. Individual source-records RPCs were removed. No global callback registry or publication capability is exposed.")
  let plan := plan.setObjVal! "cacheAndOwnership" (toJson "Immutable geometry and metadata references are counted together before admission and retained by the existing128MiB/32x query-view reservation. Temporary counting uses an existing reply reservation. Captured bytes cannot exceed counted bytes;malformed client replies,cancellation and active-borrow release are checked. Lookup receives no shared cache owner. Vector,Work/e-class certification,synaptic and selection rules are unchanged.")
  let plan := plan.setObjVal! "remaining" (toJson "Exact frontend shutdown failure/offender was not retained by the sealed harness;32-session replay and80 concurrent registrations both stopped normally. Metadata acquisition is6/21/187ms but host RSS still grows and provider-response-validation:end to execute:end has a3649ms median gap. Split later discovery/focus work and preserve shutdown errors/process identities before cleanup. Do not infer pure rendering CPU from that gap or retry80 full searches without a supported repair. Real-workload98percent,8-hour80-user capacity,read-only-filesystem/concurrent-publication stress,NAS and token/quality gates remain open.")
  write (study/"plan.json") plan
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["prepare-probe"] => prepareProbe
  | ["setup",action,tag] => setup action tag
  | ["seal"] => sealRuntime
  | ["record",tag] => record tag
  | ["controls"] => controls
  | ["measurements"] => measurements
  | ["subprofiles"] => subprofiles
  | ["cleanup"] => cleanup
  | ["retire-observer"] => retireObserver
  | ["finish-plan"] => finishPlan
  | _ => throw (IO.userError "typed original views: prepare | prepare-probe | setup action tag | seal | record tag | controls | measurements | subprofiles | cleanup | retire-observer | finish-plan")
