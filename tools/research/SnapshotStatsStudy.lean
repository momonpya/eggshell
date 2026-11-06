import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"allocator-service-build"
def target := base/"snapshot-stats-build"
def study := workspace/"docs/candidates/snapshot-stats"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty
def command (cmd : String) (args : Array String) (cwd : System.FilePath := workspace)
    (env : Array (String × Option String) := #[]) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some cwd,env}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String := do
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def checkDrained (tagStart : String) : IO (Array (String × Json)) := do
  let mut controls := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith tagStart && entry.fileName.endsWith ".guard.json" do continue
    let value ← read entry.path
    check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "preceding guard not terminal"
    let pid ← IO.ofExcept (value.getObjValAs? Nat "guardPid")
    let result ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
    check (result.exitCode != 0 && result.stdout.trimAscii.isEmpty) "guard PID still present"
    controls := controls.push (entry.fileName,value)
  return controls
partial def inheritInterfaces (source destination : System.FilePath) : IO Unit := do
  IO.FS.createDirAll destination
  for entry in ← source.readDir do
    unless ← entry.path.pathExists do continue
    let path := destination/entry.fileName
    if ← entry.path.isDir then inheritInterfaces entry.path path
    else if !(← path.pathExists) then
      discard <| command "/bin/ln" #["-s",(← IO.FS.realPath entry.path).toString,path.toString]
def build : IO Unit := do
  discard <| checkDrained "transferred-graph-"
  check (!(← (target/"StudyMain").pathExists)) "preserve completed status snapshot build"
  IO.FS.createDirAll (target/"lib/Eggshell")
  IO.FS.createDirAll study
  inheritInterfaces (parent/"lib") (target/"lib")
  for entry in ← (target/"lib/Eggshell").readDir do
    if (entry.fileName.startsWith "PublicationService." || entry.fileName.startsWith "PublicationWire.") &&
        (← entry.path.symlinkMetadata).type == .symlink then
      IO.FS.removeFile entry.path
  let witness ← IO.ofExcept (fromJson? (← read (parent/"Eggshell_PublicationService.source")) : Except String (String × Array (String × String)))
  let original := witness.1
  let marker := "def stats (server : Server) : IO Json := server.state.atomically do\n  let state ← get\n"
  check ((original.splitOn marker).length == 2) "exact selected stats boundary changed"
  let tail := (original.splitOn marker)[1]!
  let stop := "\ndef peerWaiting"
  check ((tail.splitOn stop).length == 2) "stats end boundary changed"
  let old := marker++(tail.splitOn stop)[0]!
  let stateFields := "  return Json.mkObj [(\"projects\",toJson state.projects.size),\n    (\"queued\",toJson (state.projects.foldl (fun count project => count+project.queue.size) 0)),\n    (\"active\",toJson (state.projects.filter (·.active)).size),(\"closed\",toJson state.closed),\n    (\"admittedBytes\",toJson state.admittedBytes),\n    (\"publishedGroups\",toJson state.publishedGroups),(\"publishedReplies\",toJson state.publishedReplies),\n"
  check ((old.splitOn stateFields).length == 2) "state field rendering changed"
  let child := (old.splitOn stateFields)[1]!
  let helper ← IO.FS.readFile (study/"snapshot.lean.inc")
  let replacement := helper++"\n/-- Child caches and diagnostics run after the publication snapshot lock is released. -/\ndef collectStats (server : Server) (snapshot : StatsSnapshot) : IO Json := do\n  let enabled ← IO.getEnv \"EGGSHELL_TRACE_ALLOCATOR\"\n  let heap ← if enabled == some \"1\" then Research.AllocatorDiagnostics.owner else pure Json.null\n  return Json.mkObj (snapshot.fields ++ ["++child.trimAscii.toString
  -- The old trailing list now closes the appended list and the mkObj argument.
  let replacement := replacement.replace "(\"statsOwnerHeap\",heap)]" "(\"statsOwnerHeap\",heap)])"
  let replacement := replacement++"\ndef stats (server : Server) : IO Json := do\n  let snapshot ← server.state.atomically do return StatsSnapshot.capture (← get)\n  collectStats server snapshot\n\ntheorem stats_snapshot_boundary (server : Server) : stats server = (do\n    let snapshot ← server.state.atomically do return StatsSnapshot.capture (← get)\n    collectStats server snapshot) := rfl\n"
  -- Do not mutate the shared core or product checkout: compile only this private source.
  let source := original.replace old replacement
  let sourceStart := "def scopedSource (server : Server)"
  let sourceEnd := "\ndef refreshSource"
  check ((source.splitOn sourceStart).length == 2) "exact read-authorization boundary changed"
  let sourceTail := (source.splitOn sourceStart)[1]!
  check ((sourceTail.splitOn sourceEnd).length == 2) "read-authorization end boundary changed"
  let oldSource := sourceStart++(sourceTail.splitOn sourceEnd)[0]!
  let source := source.replace oldSource (← IO.FS.readFile (study/"source.lean.inc"))
  let wire ← IO.ofExcept (fromJson? (← read (parent/"Eggshell_PublicationWire.source")) : Except String (String × Array (String × String)))
  let includes := wire.2.map fun (name,text) => (name,if name == "PublicationService.lean" then source else text)
  for (name,text) in includes do
    let path := target/"Eggshell"/name
    IO.FS.createDirAll path.parent.get!
    IO.FS.writeFile path text
  IO.FS.writeFile (target/"Eggshell/PublicationWire.lean") wire.1
  let moduleFile := target/"Eggshell/PublicationService.lean"
  IO.FS.createDirAll moduleFile.parent.get!
  IO.FS.writeFile moduleFile source
  IO.FS.writeFile (target/"original.lean") original
  let env := #[("LEAN_PATH",some ((target/"lib").toString++":"++(parent/"lib").toString))]
  let compile (file : System.FilePath) (stem : String) (olean : System.FilePath) (cwd : System.FilePath) : IO Unit := do
    let output ← command (compiler/"bin/lean").toString #["-j1","-M1536","-c",(target/(stem++".c")).toString,"-o",olean.toString,file.toString] cwd env
    IO.FS.writeFile (target/(stem++".checks.txt")) output
    discard <| command (compiler/"bin/leanc").toString #["-c","-O2","-o",(target/(stem++".o")).toString,(target/(stem++".c")).toString]
  compile (target/"Eggshell/PublicationWire.lean") "Eggshell_PublicationWire" (target/"lib/Eggshell/PublicationWire.olean") target
  compile moduleFile "Eggshell_PublicationService" (target/"lib/Eggshell/PublicationService.olean") target
  compile (workspace/"tools/research/SnapshotStatsChecks.lean") "entry" (target/"entry.olean") workspace
  let originalObjects ← ((← IO.FS.readFile (parent/"runtime.rsp")).splitOn "\n").filterMapM fun line => do
    if line.trimAscii.isEmpty then return none
    return some (← IO.ofExcept (Json.parse line >>= Json.getStr?))
  let oldEntry := (parent/"tools_research_AllocatorServiceChecks.o").toString
  let oldCore := (parent/"Eggshell_PublicationService.o").toString
  let oldWire := (parent/"Eggshell_PublicationWire.o").toString
  check ((originalObjects.filter (· == oldEntry)).length == 1 && (originalObjects.filter (· == oldCore)).length == 1 &&
    (originalObjects.filter (· == oldWire)).length == 1) "exact parent object selections changed"
  let objects := originalObjects.map fun path => if path == oldEntry then (target/"entry.o").toString
    else if path == oldCore then (target/"Eggshell_PublicationService.o").toString
    else if path == oldWire then (target/"Eggshell_PublicationWire.o").toString else path
  let response := target/"runtime.rsp"
  IO.FS.writeFile response (String.intercalate "\n" (objects.map fun path => (toJson path).compress)++"\n")
  discard <| command (compiler/"bin/leanc").toString #["-Wl,-dead_strip","-o",(target/"StudyMain").toString,"@"++response.toString]
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",(target/"original.lean").toString,moduleFile.toString]}
  check (patch.exitCode == 1) "isolated source diff missing"
  IO.FS.writeFile (study/"candidate.patch") patch.stdout
  IO.FS.writeFile (target/"Eggshell_PublicationService.source") (toJson (source,witness.2)).compress
  IO.FS.writeFile (target/"Eggshell_PublicationWire.source") (toJson (wire.1,includes)).compress
  write (study/"build.json") (Json.mkObj [("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("parentResponseSha256",toJson (← hash (parent/"runtime.rsp"))),
    ("selectedObjects",toJson objects),("onlyEntryServiceAndEmbeddedIdentityReplaced",toJson true),
    ("sourceSha256",toJson (← hash moduleFile)),("adopted",toJson false)])
def setup (action tag : String) : IO Unit := do
  discard <| checkDrained "snapshot-stats-"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh status snapshot guard required"
  let runtimeHash ← if action == "hooks" then hash (target/"StudyMain") else pure ""
  let args := if action == "build" || action == "relink-entry" then #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",(workspace/"tools/research/SnapshotStatsStudy.lean").toString,action]
    else if action == "hooks" then #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
      "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
      "PLUGIN_ROOT="++(base/"worker-cpu-target").toString,"EGGSHELL_TRACE_SERVICE_PROFILE=1",
      "EGGSHELL_TRACE_QUERY_STAGES=1","EGGSHELL_TRACE_NUMERICAL_STAGES=1","EGGSHELL_TRACE_ALLOCATOR=1",
      (base/"numerical-stages-client-build/StudyMain").toString,(base/(tag++"-result")).toString,
      (target/"StudyMain").toString,runtimeHash]
    else #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_ALLOCATOR=0",(target/"StudyMain").toString,"snapshot-stats-check",(base/(tag++"-result")).toString]
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def protectOriginals : IO Unit := do
  discard <| command "/usr/bin/shasum" #["-a","256","-c",(workspace/"docs/candidates/project-cache/protected-after.sha256").toString] base
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) : Except String (Array (String × String × String)))
  for (path,bytes,sha) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == sha) "protected original changed"
def record : IO Unit := do
  let controls ← checkDrained "snapshot-stats-"
  protectOriginals
  let native ← read (base/"snapshot-stats-checks3-result/report.json")
  for field in ["allChildReportsCompletedWhileHeld","actualStatsEqualCapturedReference",
      "sourceRegistryMutexHeldThroughout4096PureLookups","foreignCapabilityDatabaseScopeRejected","actualScopedSourceConnected"] do
    check (native.getObjValD field == toJson true) "native isolation or authority check failed"
  let buildEvidence ← read (study/"build.json")
  check (buildEvidence.getObjValD "runtimeSha256" == toJson (← hash (target/"StudyMain")) &&
    buildEvidence.getObjValD "parentRuntimeSha256" == toJson (← hash (parent/"StudyMain"))) "sealed runtime changed"
  let selected ← IO.ofExcept (buildEvidence.getObjValAs? (Array String) "selectedObjects")
  let mut includeUsers := #[]
  for object in selected do
    let path := (System.FilePath.mk object).withExtension "source"
    unless ← path.pathExists do continue
    let stamp ← IO.ofExcept (fromJson? (← read path) : Except String (String × Array (String × String)))
    for (name,_) in stamp.2 do
      if name.endsWith "PublicationService.lean" then includeUsers := includeUsers.push (object,name)
  write (study/"identity-users.json") (toJson includeUsers)
  check (includeUsers == #[((target/"Eggshell_PublicationWire.o").toString,"PublicationService.lean")]) "embedded identity producer set changed"
  let wire ← IO.ofExcept (fromJson? (← read (target/"Eggshell_PublicationWire.source")) : Except String (String × Array (String × String)))
  let serviceSource ← IO.FS.readFile (target/"Eggshell/PublicationService.lean")
  check (wire.2.any fun (name,text) => name == "PublicationService.lean" && text == serviceSource) "embedded service source is stale"
  let proof ← IO.FS.readFile (target/"entry.checks.txt")
  check (proof.contains "338 pure snapshot dependencies" && !proof.contains "sorryAx") "actual declaration or kernel audit missing"
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/PublicationService.lean",
    "--label","b/Eggshell/PublicationService.lean",(target/"original.lean").toString,(target/"Eggshell/PublicationService.lean").toString]}
  check (patch.exitCode == 1) "candidate patch missing"
  IO.FS.writeFile (study/"candidate.patch") patch.stdout
  let mut failures := #[]
  for (name,value) in controls do
    if value.getObjValD "exitCode" != toJson (0 : Nat) then
      failures := failures.push (name,← IO.FS.readFile (base/((name.dropEnd 11 |>.toString)++".log")))
  write (study/"controls.json") (Json.mkObj [("controls",toJson controls),("native",native),
    ("kernelAndDeclarationAudit",toJson proof),("failures",toJson failures),
    ("preGuardSetupFailure",toJson "Renamed reserved Lean keyword prefix before native execution."),
    ("build6LaunchFailure",toJson "A nested-action setup syntax error prevented the settings file from being written;an erroneous detached launch then exited with missing settings before any workload. PID5769 was confirmed absent. Setup and launch were changed to conditional sequential execution."),
    ("embeddedIdentityUsers",toJson includeUsers),("protected16HeadsAnd5InputsUnchanged",toJson true),
    ("entrySourceSha256",toJson (← hash (workspace/"tools/research/SnapshotStatsChecks.lean"))),
    ("notLatencyDeliveryOrTokenImprovementMeasurement",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18"),("adopted",toJson false)])
def verifyHooks : IO Unit := do
  discard <| checkDrained "snapshot-stats-"
  let runRecorder (args : Array String) : IO Unit := do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M1536","--run",
      (workspace/"docs/candidates/shared-leases/records.lean").toString,"--snapshot-stats"]++args)
  if !(← (study/"evidence.json").pathExists) then runRecorder #["snapshot-stats-hook16-3"]
  runRecorder #["verify","35"]
  let rows (value : Json) (tag : String) : IO (Array Json) := do
    let runs ← IO.ofExcept (value.getObjValAs? (Array Json) "runs")
    let some trial := runs.find? (fun row => row.getObjValD "tag" == toJson tag) | throw (IO.userError "explicit hook trial missing")
    let rows ← IO.ofExcept (trial.getObjValAs? (Array Json) "rowsIncludingPrime")
    return rows.filter fun row => ((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-wave-"
  let before ← rows (← read (workspace/"docs/candidates/allocator-profile/evidence.json")) "allocator-service-hook16-1"
  let after ← rows (← read (study/"evidence.json")) "snapshot-stats-hook16-3"
  check (before.size == 32 && after.size == 32) "actual hook domain changed"
  for row in before do
    check (after.any fun next => next.getObjValD "session" == row.getObjValD "session" &&
      next.getObjValD "stdoutSha256" == row.getObjValD "stdoutSha256") "actual full hook output bytes changed"
  write (study/"hook-parity.json") (Json.mkObj [("completeStdoutBytesEqualToParent",toJson (32 : Nat)),
    ("sameFrozen16Sources",toJson true),("actualOutputsIncludingPrime",toJson (35 : Nat)),
    ("notReal98PercentOrTokenAdoption",toJson true),("adopted",toJson false)])
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
def clean : IO Unit := do
  let controls ← checkDrained "snapshot-stats-"
  protectOriginals
  let evidence ← read (study/"controls.json")
  check (evidence.getObjValD "controls" == toJson controls && evidence.getObjValD "native" != Json.null) "retain evidence before cleanup"
  check ((← read (study/"hook-parity.json")).getObjValD "completeStdoutBytesEqualToParent" == toJson (32 : Nat)) "retain actual hook bodies before cleanup"
  discard <| command "/usr/bin/git" #["diff","--quiet","--","Eggshell","Main.lean"]
  check ((← IO.FS.realPath (base/"worker-cpu-target/bin/eggshelld")) == parent/"StudyMain") "restore active parent alias before deleting candidate runtime"
  let processes ← command "/bin/ps" #["-axo","command="]
  let mut paths := #[]
  for (name,_) in controls do
    let tag := name.dropEnd 11 |>.toString
    for suffix in ["-result",".log",".guard-settings.json"] do paths := paths.push (base/(tag++suffix))
  -- Retain the small selected object/interface/source witness, not an unused executable or generated C.
  for file in ["StudyMain","entry.o","entry.c","entry.olean","entry.olean.private","entry.olean.server","entry.checks.txt",
      "Eggshell_PublicationService.c","Eggshell_PublicationService.checks.txt",
      "Eggshell_PublicationWire.c","Eggshell_PublicationWire.checks.txt","original.lean"] do
    paths := paths.push (target/file)
  paths := paths.push (target/"Eggshell") |>.push (target/"tools")
  let mut removed := #[]
  for path in paths do
    unless ← path.pathExists do continue
    check (!processes.contains path.toString) "retired status artifact is still used"
    let (files,bytes) ← removeTree path
    removed := removed.push (path.toString,files,bytes)
  protectOriginals
  write (study/"cleanup.json") (Json.mkObj [("removed",toJson removed),("archive",toJson false),
    ("logicalBytes",toJson (removed.foldl (fun n row => n+row.2.2) 0)),
    ("protectedOriginalsAndParentServiceRetained",toJson true),("productCoreUnchanged",toJson true)])
def retireInitialBuild : IO Unit := do
  discard <| checkDrained "snapshot-stats-"
  let initial ← read (study/"build.json")
  check (initial.getObjValD "onlyEntryAndPublicationServiceReplaced" == toJson true &&
    initial.getObjValD "runtimeSha256" == toJson (← hash (target/"StudyMain"))) "unexpected initial status build"
  write (study/"initial-build-audit-rejection.json") (Json.mkObj [("build",initial),
    ("native",← read (base/"snapshot-stats-checks1-result/report.json")),
    ("identityUsers",← read (study/"identity-users.json")),
    ("reason",toJson "Native lock checks passed,but embedded PublicationWire identity was inherited. Rebuild the identity producer before full service testing;this is not an accepted coherent service runtime."),
    ("adopted",toJson false)])
  IO.FS.removeFile (target/"StudyMain")
def relinkEntry : IO Unit := do
  let old ← read (study/"build.json")
  check (old.getObjValD "runtimeSha256" == toJson (← hash (target/"StudyMain"))) "entry relink lost its selected parent"
  write (study/"entry-audit-repair.json") (Json.mkObj [("previousBuild",old),
    ("nativeBeforeEntryRepair",← read (base/"snapshot-stats-checks2-result/report.json")),
    ("reason",toJson "First hook setup rejected a stale runtime alias. Second rejected the missing front-traffic-audit test entry delegation before starting any actual query. Restore the exact parent delegation;do not change product modules or fixture inputs."),
    ("adopted",toJson false)])
  let env := #[("LEAN_PATH",some ((target/"lib").toString))]
  let output ← command (compiler/"bin/lean").toString #["-j1","-M1536","-c",(target/"entry.c").toString,
    "-o",(target/"entry.olean").toString,(workspace/"tools/research/SnapshotStatsChecks.lean").toString] workspace env
  IO.FS.writeFile (target/"entry.checks.txt") output
  discard <| command (compiler/"bin/leanc").toString #["-c","-O2","-o",(target/"entry.o").toString,(target/"entry.c").toString]
  discard <| command (compiler/"bin/leanc").toString #["-Wl,-dead_strip","-o",(target/"StudyMain").toString,"@"++(target/"runtime.rsp").toString]
  write (study/"build.json") (old.setObjVal! "runtimeSha256" (toJson (← hash (target/"StudyMain"))))
def compactRecords : IO Unit := do
  for directory in [study,workspace/"docs/candidates/transferred-graph"] do
    for entry in ← directory.readDir do
      unless entry.fileName.endsWith ".json" do continue
      let value ← read entry.path
      check ((← IO.ofExcept (Json.parse value.compress)) == value) "JSON formatting changed retained evidence"
      IO.FS.writeFile entry.path value.compress
def main (args : List String) : IO Unit := do
  match args with
  | ["setup",action,tag] => setup action tag
  | ["build"] => build
  | ["record"] => record
  | ["verify-hooks"] => verifyHooks
  | ["cleanup"] => clean
  | ["retire-initial"] => retireInitialBuild
  | ["relink-entry"] => relinkEntry
  | ["compact"] => compactRecords
  | _ => throw (IO.userError "SnapshotStatsStudy setup build|checks FRESH_TAG | build")
