import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap
open Lean
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"transport-heap-coherent-build"
def sourceRoot := base/"record-read-image-source"
def target := base/"record-read-image-build"
def study := workspace/"docs/candidates/record-read-image"
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
  for tagStart in ["transport-heap-","record-read-image-"] do
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
  let mut mapping ← read (base/"transport-heap-coherent-source/object-mapping.json")
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
  let record := sourceRoot/"Eggshell/ObservedRecordView.lean"
  let original ← IO.FS.readFile record
  let start := "structure CachedGeometry where"
  let stop := "structure Projection where"
  check ((original.splitOn start).length == 2 && (original.splitOn stop).length == 2) "exact cache boundaries changed"
  let updated := (original.splitOn start)[0]!++(← IO.FS.readFile (study/"cache.lean.inc"))++stop++(original.splitOn stop)[1]!
  IO.FS.writeFile record updated
  let service := sourceRoot/"Eggshell/PublicationService.lean"
  let originalService ← IO.FS.readFile service
  let before := "    let mut rows : Array (String × Option ObservedRecordView.Geometry) := #[]\n    let mut size := 0\n    for owner in owners do\n      unless (← IO.monoMsNow) < deadline do throw (IO.userError \"original record projection expired\")\n      let found ← server.structures.acquire original.index scope.database owner deadline\n      let value := toJson (owner,found)\n      size := size+value.compress.utf8ByteSize\n      unless size ≤ Stream.maxBytes-4096 do throw (IO.userError \"original record projection exceeds reserved reply budget\")\n      rows := rows.push (owner,found)\n"
  check ((originalService.splitOn before).length == 2) "selected original record loop changed"
  let after := "    let batch ← server.structures.project original.index scope.database owners deadline (Stream.maxBytes-4096)\n    let rows := batch.rows\n"
  IO.FS.writeFile service ((originalService.replace before after).replace
    "rows,cache := ← server.structures.stats" "rows,cache := Json.null")
  for (name,old) in [("ObservedRecordView",original),("PublicationService",originalService)] do
    let previous := sourceRoot/(name++".before")
    IO.FS.writeFile previous old
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/"++name++".lean","--label","b/Eggshell/"++name++".lean",previous.toString,(sourceRoot/"Eggshell"/(name++".lean")).toString]}
    check (patch.exitCode == 1) "record cache patch missing"
    IO.FS.writeFile (study/(name++".patch")) patch.stdout
    IO.FS.removeFile previous
  IO.FS.writeFile (sourceRoot/"tools/research/RecordImageChecks.lean") (← IO.FS.readFile (workspace/"tools/research/RecordImageChecks.lean"))
  IO.FS.createDirAll (sourceRoot/".lake/build/lib")
  discard <| command "/bin/ln" #["-s",(parent/"lib").toString,(sourceRoot/".lake/build/lib/lean").toString]
  write (sourceRoot/"object-mapping.json") mapping
  let mut settings := build.getObjValD "settings"
  settings := settings.setObjVal! "parents" (toJson (#[parent.toString]++(← IO.ofExcept (settings.getObjValAs? (Array String) "parents"))))
  for (key,value) in [("project",sourceRoot.toString),("core",sourceRoot.toString),("output",target.toString),
      ("baselineResponse",(parent/"runtime.rsp").toString),("objectModules",(sourceRoot/"object-mapping.json").toString),
      ("mainModule","tools.research.RecordImageChecks")] do settings := settings.setObjVal! key (toJson value)
  write (base/"record-read-image-settings.json") settings
  write (study/"plan.json") (Json.mkObj [("status",toJson "isolated,not adopted"),("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("fixedNativeClientSha256",toJson (← hash (base/"numerical-stages-client-build/StudyMain"))),
    ("unchangedLimits",toJson "30s,4GiB ceiling,3670016KiB stop,2097152KiB free"),
    ("scope",toJson "immutable record metadata;not all read-path locks;no token or 80-user success claim")])
def setup (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh record image tag required"
  let args ← if action == "build" then pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"record-read-image-settings.json").toString]
    else if action == "checks" then pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,"record-image-check",(base/(tag++"-result")).toString]
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
def sealRuntime : IO Unit := do
  drained
  let audit := study/"native-sources.json"
  if !(← audit.pathExists) then
    script "tools/research/StudyBuildClosureAudit.lean" #["compare-sources",parent.toString,target.toString,audit.toString,
      "Eggshell.ObservedRecordView","Eggshell.PublicationService"]
  check ((← read audit).getObjValD "exactExpectedChangeSet" == toJson true) "record image source audit failed"
  -- Refresh the patch from the actual selected parent and final compiled source.
  let modules ← read (parent/"object-mapping.json")
  let build ← read (parent/"build.json")
  let mut mapping := modules
  for row in arr build "modules" do mapping := mapping.setObjVal! (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
  let objects ← ((← IO.FS.readFile (parent/"runtime.rsp")).splitOn "\n").filterMapM fun row => do
    if row.trimAscii.isEmpty then return none
    return some (← IO.ofExcept (Json.parse row >>= Json.getStr?))
  for name in ["ObservedRecordView","PublicationService"] do
    let some object := objects.find? (fun object => mapping.getObjValD object == toJson ("Eggshell."++name)) |
      throw (IO.userError "selected record image parent source missing")
    let before ← IO.ofExcept (fromJson? (← read ((System.FilePath.mk object).withExtension "source")) : Except String (String × Array (String × String)))
    let path := sourceRoot/(name++".before")
    IO.FS.writeFile path before.1
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/"++name++".lean","--label","b/Eggshell/"++name++".lean",path.toString,(sourceRoot/"Eggshell"/(name++".lean")).toString]}
    check (patch.exitCode == 1) "final candidate patch missing"
    IO.FS.writeFile (study/(name++".patch")) patch.stdout
    IO.FS.removeFile path
  write (study/"build.json") (Json.mkObj [("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),("sourceChangeAudit",← read audit),
    ("kernelAndDeclarationAudit",toJson (← IO.FS.readFile (target/"tools_research_RecordImageChecks-lean.stdout"))),
    ("ordinaryContractAuditAndNativeClosureBuilt",toJson true),("adopted",toJson false)])
def record (tag : String) : IO Unit := do
  drained
  let mut recorded := false
  if ← (study/"evidence.json").pathExists then
    recorded := (arr (← read (study/"evidence.json")) "runs").any (fun row => row.getObjValD "tag" == toJson tag)
  if !recorded then
    script "docs/candidates/shared-leases/records.lean" #["--record-read-image",tag]
  script "docs/candidates/shared-leases/records.lean" #["--record-read-image","verify","35"]
  let evidence ← read (study/"evidence.json")
  let some trial := (arr evidence "runs").find? (fun row => row.getObjValD "tag" == toJson tag) |
    throw (IO.userError "record image hook trial absent")
  let previous ← read (workspace/"docs/candidates/transport-heap/evidence.json")
  let some control := (arr previous "runs").find? (fun row => row.getObjValD "tag" == toJson "transport-heap-service-hook16-1") |
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
def controls : IO Unit := do
  drained
  let mut guards := #[]
  let mut logs := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "record-read-image-" do continue
    if entry.fileName.endsWith ".guard.json" then guards := guards.push (entry.fileName,← read entry.path)
    if entry.fileName.endsWith ".log" then logs := logs.push (entry.fileName,← IO.FS.readFile entry.path)
    if entry.fileName.endsWith "-result" && (← (entry.path/"report.json").pathExists) then
      let report ← read (entry.path/"report.json")
      if report.getObjValD "originalCacheMutexHeldDuring80ParallelReaders" == toJson true then
        write (study/"native-checks.json") report
  write (study/"controls.json") (Json.mkObj [("guards",toJson guards),("logs",toJson logs),
    ("allGuardsTerminalAndPidsAbsent",toJson true),("answeringModelCalls",toJson (0 : Nat)),("paidMatchedComparisons",toJson "0/18")])
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
  script "docs/candidates/shared-leases/records.lean" #["--record-read-image","verify","35"]
  controls
  let live ← command "/bin/ps" #["-axo","command="]
  let mut deleted := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "record-read-image-" &&
        (entry.fileName.endsWith "-result" || entry.fileName.endsWith ".log" || entry.fileName.endsWith ".guard-settings.json") do continue
    check (!live.contains entry.path.toString) "retired record image artifact is still active"
    deleted := deleted.push (entry.path.toString,← remove entry.path)
  for entry in ← target.readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
      deleted := deleted.push (entry.path.toString,← remove entry.path)
  write (study/"cleanup.json") (Json.mkObj [("deleted",toJson deleted),("archive",toJson false),
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
  result := result.setObjVal! "compilerLogsDeleted" (toJson (logs.size,logs.foldl (fun total row => total+row.2) 0))
  if ← previous.pathExists then
    let digest ← hash previous
    check (toJson digest == evidence.getObjValD "parentRuntimeSha256") "retired observer is not the sealed parent"
    let bytes ← remove previous
    result := result.setObjVal! "retiredObserverExecutable" (toJson (previous.toString,digest,bytes))
  write (study/"cleanup.json") result
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["setup",action,tag] => setup action tag
  | ["seal"] => sealRuntime
  | ["record",tag] => record tag
  | ["controls"] => controls
  | ["cleanup"] => cleanup
  | ["retire-observer"] => retireObserver
  | _ => throw (IO.userError "record image study: prepare | setup action tag | seal | record tag | controls | cleanup")
