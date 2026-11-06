import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def target := base/"transferred-graph-build"
def study := workspace/"docs/candidates/transferred-graph"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String := do
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def build : IO Unit := do
  check (!(← (target/"StudyMain").pathExists)) "preserve completed transfer build"
  IO.FS.createDirAll target
  let source := workspace/"tools/research/TransferredGraphProfile.lean"
  let adapter := workspace/"tools/research/native/allocator_probe.c"
  IO.FS.writeFile (target/"profile.source") (← IO.FS.readFile source)
  IO.FS.writeFile (target/"adapter.c.txt") (← IO.FS.readFile adapter)
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","-c",(target/"profile.c").toString,
    "-o",(target/"profile.olean").toString,source.toString]
  let generated ← IO.FS.readFile (target/"profile.c")
  let sdk := (← command "/usr/bin/xcrun" #["--show-sdk-path"]).trimAscii.toString
  discard <| command (compiler/"bin/leanc").toString #["-c","-O2","-o",(target/"profile.o").toString,(target/"profile.c").toString]
  discard <| command (compiler/"bin/leanc").toString #["-c","-O2","-Wall","-Wextra","-Werror",
    "-isysroot",sdk,"-isystem",sdk++"/usr/include","-o",(target/"adapter.o").toString,adapter.toString]
  discard <| command (compiler/"bin/leanc").toString #["-Wl,-dead_strip","-o",(target/"StudyMain").toString,
    (target/"profile.o").toString,(target/"adapter.o").toString]
  write (study/"build.json") (Json.mkObj [("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("sourceSha256",toJson (← hash source)),("adapterSha256",toJson (← hash adapter)),
    ("sdk",toJson sdk),("nativeApiDeclarations",toJson ((generated.splitOn "\n").filter fun line =>
      line.contains "eggshell_research_thread_")),("noAdditionalAllocator",toJson true),
    ("noPythonOrRuby",toJson true),("adopted",toJson false)])
def phaseBuild : IO Unit := do
  let phaseTarget := base/"transferred-phase-build"
  let parent := base/"allocator-service-build"
  check (!(← (phaseTarget/"StudyMain").pathExists)) "preserve completed phase build"
  IO.FS.createDirAll phaseTarget
  let source := workspace/"tools/research/OwnedPhaseRetention.lean"
  IO.FS.writeFile (phaseTarget/"entry.source") (← IO.FS.readFile source)
  let options : IO.Process.SpawnArgs := {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M1536","-c",(phaseTarget/"entry.c").toString,
      "-o",(phaseTarget/"entry.olean").toString,source.toString]
    env := #[("LEAN_PATH",some ((parent/"lib").toString))]
    cwd := some workspace }
  let result ← IO.Process.output options
  check (result.exitCode == 0) (result.stdout++result.stderr)
  let generated ← IO.FS.readFile (phaseTarget/"entry.c")
  let calls := (generated.splitOn "\n").filter (·.contains "OperationPool_ownedPhase")
  check (calls.length ≥ 2) "fixture did not call the real native phase helper"
  discard <| command (compiler/"bin/leanc").toString #["-c","-O2","-o",(phaseTarget/"entry.o").toString,(phaseTarget/"entry.c").toString]
  let original ← ((← IO.FS.readFile (parent/"runtime.rsp")).splitOn "\n").filterMapM fun line => do
    if line.trimAscii.isEmpty then return none
    return some (← IO.ofExcept (Json.parse line >>= Json.getStr?))
  let oldEntry := (parent/"tools_research_AllocatorServiceChecks.o").toString
  let oldAdapter := (base/"allocator-service-ffi/adapter.o").toString
  check ((original.filter (· == oldEntry)).length == 1 && (original.filter (· == oldAdapter)).length == 1)
    "parent closure did not contain the exact selected entry and adapter"
  let selected := original.filterMap fun path => if path == oldEntry then none else
    some (if path == oldAdapter then (target/"adapter.o").toString else path)
  let selected := selected++[(phaseTarget/"entry.o").toString]
  let response := phaseTarget/"runtime.rsp"
  IO.FS.writeFile response (String.intercalate "\n" (selected.map (fun path => (toJson path).compress))++"\n")
  discard <| command (compiler/"bin/leanc").toString #["-Wl,-dead_strip","-o",(phaseTarget/"StudyMain").toString,"@"++response.toString]
  let core := parent/"Eggshell_OperationPool.o"
  write (study/"phase-build.json") (Json.mkObj [("runtimeSha256",toJson (← hash (phaseTarget/"StudyMain"))),
    ("entrySourceSha256",toJson (← hash source)),("coreObjectSha256",toJson (← hash core)),
    ("coreSourceWitnessSha256",toJson (← hash (core.withExtension "source"))),
    ("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("parentResponseSha256",toJson (← hash (parent/"runtime.rsp"))),
    ("nativeHelperCalls",toJson calls),("onlyEntryAndOsAdapterReplaced",toJson true),
    ("selectedObjects",toJson selected),("adopted",toJson false)])
def setup (action tag : String) : IO Unit := do
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh transfer guard tag required"
  let args := if action == "build" || action == "phase-build" then #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/TransferredGraphStudy.lean").toString,action]
    else if action.startsWith "phase-" then #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/"transferred-phase-build/StudyMain").toString,
      (base/(tag++"-result")).toString,(action.drop 6 |>.toString)]
    else #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,(base/(tag++"-result")).toString,action]
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def drained : IO (Array (String × Json)) := do
  let mut controls := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "transferred-graph-" && entry.fileName.endsWith ".guard.json" do continue
    let value ← read entry.path
    check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "transfer guard not terminal"
    let pid ← IO.ofExcept (value.getObjValAs? Nat "guardPid")
    let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
    check (probe.exitCode != 0 && probe.stdout.trimAscii.isEmpty) "transfer guard PID remains"
    controls := controls.push (entry.fileName,value)
  return controls
def record : IO Unit := do
  let controls ← drained
  let mut reports := #[]
  for tag in ["owner1","alive1","exited1","encoded1","phase-plain1","phase-quiet1","phase-ready1"] do
    let path := base/("transferred-graph-"++tag++"-result/report.json")
    reports := reports.push (tag,← read path,← hash path)
  let mut failures := #[]
  for (name,value) in controls do
    if value.getObjValD "exitCode" != toJson (0 : Nat) then
      let log := base/((name.dropEnd 11 |>.toString)++".log")
      failures := failures.push (name,← IO.FS.readFile log)
  write (study/"evidence.json") (Json.mkObj [("controls",toJson controls),("reports",toJson reports),
    ("failures",toJson failures),("preNativeFixes",toJson #["publishGraph missing do","finally task registry changed to IO.Ref before native execution","typed SpawnArgs syntax in phase setup"]),
    ("interpretation",toJson "Simple graph transfer did not reproduce the service's hundreds-of-MiB cumulative growth. Actual quiet ownedPhase increased about10MiB/wave in this four-wave sample;ready ownedPhase plateaued after wave2. Neither proves a retained graph leak or justifies replacing the service wire or allocator."),
    ("adopted",toJson false)])
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
  let controls ← drained
  let evidence ← read (study/"evidence.json")
  check (evidence.getObjValD "controls" == toJson controls) "record all guards before cleanup"
  let processes ← command "/bin/ps" #["-axo","command="]
  let mut paths := #[target,base/"transferred-phase-build"]
  for (name,_) in controls do
    let tag := name.dropEnd 11 |>.toString
    for suffix in ["-result",".log",".guard-settings.json"] do paths := paths.push (base/(tag++suffix))
  let mut removed := #[]
  for path in paths do
    unless ← path.pathExists do continue
    check (!processes.contains path.toString) "retired transfer artifact is still used"
    let (files,bytes) ← removeTree path
    removed := removed.push (path.toString,files,bytes)
  write (study/"cleanup.json") (Json.mkObj [("removed",toJson removed),("archive",toJson false),
    ("logicalBytes",toJson (removed.foldl (fun n row => n+row.2.2) 0)),
    ("parentServiceObjectsAndOriginalsRetained",toJson true)])
def main (args : List String) : IO Unit := do
  match args with
  | ["setup",action,tag] => setup action tag
  | ["build"] => build
  | ["phase-build"] => phaseBuild
  | ["record"] => record
  | ["cleanup"] => clean
  | _ => throw (IO.userError "TransferredGraphStudy setup ACTION FRESH_TAG | build")
