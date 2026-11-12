import tools.research.StudyLocal
open Lean StudyLocal
namespace RequestSocketStudy
def parent := base/"practical-runtime/hook-command"
def root := base/"practical-runtime/request-socket"
def records := project/"docs/candidates/request-socket"
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh owned-socket candidate required"
  check ((← hash (parent/"build/StudyMain")) == "ea5b3861dfba62fe0e600552a13facb59595304c67b28fa9f2d3f395d66e0e35")
    "fixed request-socket parent changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  IO.FS.createDirAll (root/"source/Eggshell/Storage")
  for (name,target) in [("OwnedSocket.lean","OwnedSocket.lean"),("socket.c","Storage/socket.c")] do
    IO.FS.writeFile (root/"source/Eggshell"/target)
      (← IO.FS.readFile (project/"tools/research/request-socket"/name))
  copyLocalArtifacts (parent/"build") (root/"build")
  write (records/"plan.json") (Json.mkObj [("parentBackendSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("purpose",toJson "cancel and join a direct request without a gateway subprocess"),
    ("osBoundary",toJson "nonblocking POSIX connect/poll/send/recv/close; protocol and deadlines in Lean"),
    ("macClients",toJson (16 : Nat)),("pollMilliseconds",toJson (25 : Nat)),
    ("productIntegrated",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "request-socket-ffi" #[(compiler/"bin/leanc").toString,"-c","-O2","-fPIC","-Wall","-Wextra","-Werror",
    (root/"source/Eggshell/Storage/socket.c").toString,"-o",(root/"socket.o").toString]
def build : IO Unit := do
  idle
  write (records/"ffi.guard.json") (← finished "request-socket-static-ffi")
  IO.FS.writeFile (root/"source/tools/research/OwnedSocketChecks.lean")
    (← IO.FS.readFile (project/"tools/research/OwnedSocketChecks.lean"))
  let response := (← IO.FS.readFile (parent/"build/runtime.rsp"))++(toJson (root/"socket.o").toString).compress++"\n"
  IO.FS.writeFile (root/"baseline.rsp") response
  write (records/"ffi.json") (Json.mkObj [("sourceSha256",toJson (← hash (root/"source/Eggshell/Storage/socket.c"))),
    ("objectSha256",toJson (← hash (root/"socket.o"))),
    ("compilerSha256",toJson (← hash "/usr/bin/cc")),
    ("compilerVersion",toJson (← command "/usr/bin/cc" #["--version"]))])
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"baseline.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.OwnedSocketChecks")
  write (root/"settings.json") settings
  guard "request-socket-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def nativeCompiler : IO Unit := do
  idle
  let stopped ← read (base/"request-socket-ffi.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" != toJson (0 : Nat)) "retain the stopped SDK-header rejection"
  write (records/"ffi-rejection.json") (Json.mkObj [("guard",stopped),
    ("reason",toJson "bundled leanc C driver did not find macOS errno.h; use the system SDK compiler"),
    ("sourceChanged",toJson false),("databaseOrQueryStarted",toJson false)])
  guard "request-socket-native-ffi" #["/usr/bin/cc","-c","-O2","-fPIC","-Wall","-Wextra","-Werror",
    "-I",(compiler/"include").toString,(root/"source/Eggshell/Storage/socket.c").toString,
    "-o",(root/"socket.o").toString]
def staticClass : IO Unit := do
  idle
  write (records/"first-ffi.json") (Json.mkObj [("guard",← finished "request-socket-native-ffi"),
    ("sourceSha256",toJson (← hash (root/"source/Eggshell/Storage/socket.c"))),
    ("objectSha256",toJson (← hash (root/"socket.o"))),
    ("executed",toJson false),
    ("supersededReason",toJson "static callback table removes module FFI initialization and mutable class registration")])
  for (name,target) in [("OwnedSocket.lean","OwnedSocket.lean"),("socket.c","Storage/socket.c")] do
    IO.FS.writeFile (root/"source/Eggshell"/target)
      (← IO.FS.readFile (project/"tools/research/request-socket"/name))
  guard "request-socket-static-ffi" #["/usr/bin/cc","-c","-O2","-fPIC","-Wall","-Wextra","-Werror",
    "-I",(compiler/"include").toString,(root/"source/Eggshell/Storage/socket.c").toString,
    "-o",(root/"socket.o").toString]
def repairChecks : IO Unit := do
  idle
  let stopped ← read (base/"request-socket-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" != toJson (0 : Nat)) "only repair the stopped fixture elaboration"
  write (records/"checks-rejection.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"build/tools_research_OwnedSocketChecks-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"build/tools_research_OwnedSocketChecks-lean.stderr"))),
    ("fixtureSourceSha256",toJson (← hash (root/"source/tools/research/OwnedSocketChecks.lean"))),
    ("socketCoreChanged",toJson false)])
  IO.FS.writeFile (root/"source/tools/research/OwnedSocketChecks.lean")
    (← IO.FS.readFile (project/"tools/research/OwnedSocketChecks.lean"))
  guard "request-socket-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def repairPhase : IO Unit := do
  idle
  let stopped ← read (base/"request-socket-checked-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" != toJson (0 : Nat)) "only repair the stopped fixture's local deadline expression"
  write (records/"checks-phase-rejection.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"build/tools_research_OwnedSocketChecks-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"build/tools_research_OwnedSocketChecks-lean.stderr"))),
    ("socketCoreChanged",toJson false)])
  IO.FS.writeFile (root/"source/tools/research/OwnedSocketChecks.lean")
    (← IO.FS.readFile (project/"tools/research/OwnedSocketChecks.lean"))
  guard "request-socket-phase-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def repairMap : IO Unit := do
  idle
  let stopped ← read (base/"request-socket-phase-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" != toJson (0 : Nat)) "retain the stopped duplicate-object link"
  write (records/"link-rejection.json") (Json.mkObj [("guard",stopped),
    ("stderr",toJson (← IO.FS.readFile (root/"build/link.stderr"))),
    ("cause",toJson "custom FFI baseline.rsp bypassed automatic runtime.rsp parent-manifest mapping"),
    ("socketCoreChanged",toJson false)])
  let mut linked : Std.HashSet String := {}
  for line in (← IO.FS.readFile (parent/"build/runtime.rsp")).splitOn "\n" do
    if !line.trimAscii.isEmpty then linked := linked.insert (← IO.ofExcept (Json.parse line >>= Json.getStr?))
  let mut mapping := (← read (parent/"build/object-mapping.json"))
  for row in ← IO.ofExcept ((← read (parent/"build/build.json")).getObjValAs? (Array Json) "modules") do
    let path : String ← IO.ofExcept (row.getObjValAs? _ "object")
    if linked.contains path then
      let name : String ← IO.ofExcept (row.getObjValAs? _ "module")
      if let .ok previous := mapping.getObjVal? path then
        check (previous == toJson name) "parent mapping contradicts its native producer"
      mapping := mapping.setObjVal! path (toJson name)
  write (root/"inherited-mapping.json") mapping
  write (root/"settings.json") ((← read (root/"settings.json"))
    |>.setObjVal! "objectModules" (toJson (root/"inherited-mapping.json").toString))
  guard "request-socket-mapped-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def lifecycleBuild : IO Unit := do
  idle
  write (records/"first-build.json") (Json.mkObj [("guard",← finished "request-socket-mapped-build"),
    ("runtimeSha256",toJson (← hash (root/"build/StudyMain"))),
    ("executed",toJson false),("newChecks",toJson #["descriptor census","escaped closed scope"])])
  IO.FS.writeFile (root/"source/tools/research/OwnedSocketChecks.lean")
    (← IO.FS.readFile (project/"tools/research/OwnedSocketChecks.lean"))
  guard "request-socket-lifecycle-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def audit : IO Unit := do
  idle
  write (records/"build.guard.json") (← finished "request-socket-live-result-build")
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditing.toString,
    "inspect",(root/"build").toString,(records/"native.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditing.toString,
    "component-sources",(parent/"build").toString,(root/"build").toString,(records/"common-sources.json").toString,
    "Eggshell.DaemonWire","Eggshell.SourceObservation","Eggshell.TaskDeadline"]
  let ffi ← read (records/"ffi.json")
  check (ffi.getObjValD "sourceSha256" == toJson (← hash (root/"source/Eggshell/Storage/socket.c")) &&
    ffi.getObjValD "objectSha256" == toJson (← hash (root/"socket.o"))) "socket OS object changed after compilation"
  let linked := (← IO.FS.readFile (root/"build/runtime.rsp")).splitOn "\n" |>.filter (!·.trimAscii.isEmpty)
  check ((linked.filter (· == (toJson (root/"socket.o").toString).compress)).length == 1)
    "the audited OS object must be linked exactly once"
  for (name,source) in [("Eggshell_OwnedSocket","tools/research/request-socket/OwnedSocket.lean"),
      ("tools_research_OwnedSocketChecks","tools/research/OwnedSocketChecks.lean")] do
    let witness ← read (root/"build"/(name++".source"))
    let (text,_included) : String × Array (String × String) ← IO.ofExcept (fromJson? witness)
    check (text == (← IO.FS.readFile (project/source))) "native socket source differs from its reviewable source"
  let result ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768","-DwarningAsError=true",(project/"tools/research/OwnedSocketAudit.lean").toString]
    env := #[("LEAN_PATH",some (root/"build/lib").toString)]}
  write (records/"proofs.json") (Json.mkObj [("exitCode",toJson result.exitCode.toNat),
    ("stdout",toJson result.stdout),("stderr",toJson result.stderr),
    ("sourceSha256",toJson (← hash (project/"tools/research/OwnedSocketAudit.lean")))])
  check (result.exitCode == 0 && result.stderr.isEmpty && !result.stdout.contains "sorryAx" &&
    !result.stdout.contains "Lean.trustCompiler" && !result.stdout.contains "Lean.ofReduceBool") "owned socket audit failed"
  write (records/"run-plan.json") (Json.mkObj [("runtimeSha256",toJson (← hash (root/"build/StudyMain"))),
    ("socketObjectSha256",ffi.getObjValD "objectSha256"),
    ("clientCount",toJson (16 : Nat)),("projectQueries",toJson (0 : Nat)),("nativeKernelBoundary",toJson true)])
  guard "request-socket-checks" #["/usr/bin/env","-u","LEAN_NUM_THREADS",(root/"build/StudyMain").toString,
    (records/"checks.json").toString]
def liveResult : IO Unit := do
  idle
  write (records/"lifecycle-build.json") (Json.mkObj [("guard",← finished "request-socket-lifecycle-build"),
    ("runtimeSha256",toJson (← hash (root/"build/StudyMain"))),
    ("executed",toJson false),("newCheck",toJson "reject a callback result after its absolute deadline")])
  IO.FS.writeFile (root/"source/tools/research/OwnedSocketChecks.lean")
    (← IO.FS.readFile (project/"tools/research/OwnedSocketChecks.lean"))
  IO.FS.writeFile (root/"source/Eggshell/OwnedSocket.lean")
    (← IO.FS.readFile (project/"tools/research/request-socket/OwnedSocket.lean"))
  guard "request-socket-live-result-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def conclude : IO Unit := do
  idle
  write (records/"checks.guard.json") (← finished "request-socket-checks")
  let checks ← read (records/"checks.json")
  check ((checks.getObjValD "echo").getObjValD "clients" == toJson (16 : Nat) &&
    checks.getObjValD "tcpDescriptorsBefore" == checks.getObjValD "tcpDescriptorsAfter" &&
    (checks.getObjValD "lateResult").getObjValD "lateSuccessRefused" == toJson true)
    "retain the complete native lifecycle result"
  let plan ← read (records/"run-plan.json")
  check (plan.getObjValD "runtimeSha256" == toJson (← hash (root/"build/StudyMain")) &&
    plan.getObjValD "socketObjectSha256" == toJson (← hash (root/"socket.o"))) "native socket test input changed"
  let mut guards := #[]
  for tag in ["ffi","native-ffi","static-ffi","build","checked-build","phase-build","mapped-build",
      "lifecycle-build","live-result-build","checks"] do
    let record ← read (base/("request-socket-"++tag++".guard.json"))
    check (record.getObjValD "state" == toJson "finished" && record.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "socket stage is still live"
    guards := guards.push (tag,record)
  write (records/"guard-records.json") (toJson guards)
  let mut inputs : Array (String × String) := #[]
  for line in (← IO.FS.readFile (root/"build/runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    if path.endsWith ".o" then inputs := inputs.push (path,← hash (.mk path))
  write (records/"protected-native-inputs.json") (toJson inputs)
  let mut targets : Array String := #[]
  for entry in ← (root/"build").readDir do
    if entry.fileName.endsWith ".o" && !(inputs.any (·.1 == entry.path.toString)) then
      for extension in ["o","source","dependencies"] do
        let path := entry.path.withExtension extension
        if ← path.pathExists then targets := targets.push path.toString
    else if (entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr") &&
        (← entry.path.metadata).byteSize == 0 then targets := targets.push entry.path.toString
  check (targets.all fun target => !(inputs.any (·.1 == target))) "pruning selected an active socket input"
  write (records/"cleanup-plan.json") (toJson targets)
  write (records/"summary.json") (checks.setObjVal! "runtimeSha256" (plan.getObjValD "runtimeSha256")
    |>.setObjVal! "normalHookIntegrated" (toJson false)
    |>.setObjVal! "projectGatewayProcessRemoved" (toJson false)
    |>.setObjVal! "parentBackendUnchanged" (toJson ((← hash (parent/"build/StudyMain")) ==
      "ea5b3861dfba62fe0e600552a13facb59595304c67b28fa9f2d3f395d66e0e35")))
def afterCleanup : IO Unit := do
  idle
  let inputs : Array (String × String) ← IO.ofExcept (fromJson? (← read (records/"protected-native-inputs.json")))
  for (path,digest) in inputs do check ((← hash (.mk path)) == digest) "active native input changed during pruning"
  let plan ← read (records/"run-plan.json")
  check (plan.getObjValD "runtimeSha256" == toJson (← hash (root/"build/StudyMain"))) "socket binary changed during pruning"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(root/"build").toString,
    (records/"socket-after-cleanup.json").toString]
end RequestSocketStudy
def main : List String → IO Unit
  | ["prepare"] => RequestSocketStudy.prepare
  | ["build"] => RequestSocketStudy.build
  | ["native-compiler"] => RequestSocketStudy.nativeCompiler
  | ["static-class"] => RequestSocketStudy.staticClass
  | ["repair-checks"] => RequestSocketStudy.repairChecks
  | ["repair-phase"] => RequestSocketStudy.repairPhase
  | ["repair-map"] => RequestSocketStudy.repairMap
  | ["lifecycle-build"] => RequestSocketStudy.lifecycleBuild
  | ["audit"] => RequestSocketStudy.audit
  | ["live-result"] => RequestSocketStudy.liveResult
  | ["conclude"] => RequestSocketStudy.conclude
  | ["after-cleanup"] => RequestSocketStudy.afterCleanup
  | _ => throw (IO.userError "RequestSocketStudy prepare|native-compiler|static-class|build|repair-checks|repair-phase|repair-map|lifecycle-build|live-result|audit|conclude|after-cleanup")
