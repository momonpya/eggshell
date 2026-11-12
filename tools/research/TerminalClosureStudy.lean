import tools.research.StudyLocal
open Lean StudyLocal
namespace TerminalClosureStudy
def parent := base/"practical-runtime/terminal-intent"
def root := base/"practical-runtime/terminal-closure"
def records := project/"docs/candidates/terminal-closure"
def guard (tag : String) (args : Array String) : IO Unit := do
  StudyLocal.guard tag args
  let path := base/(tag++".guard-settings.json")
  let original ← read path
  write path (original.setObjVal! "ownedPrefixes" (toJson #[root.toString]))
def settings (source output inherited : System.FilePath) (entry : String) : IO Json := do
  return (← read (inherited/"build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson source.toString)
    |>.setObjVal! "core" (toJson source.toString)
    |>.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "parents" (toJson #[inherited.toString])
    |>.setObjVal! "baselineResponse" (toJson (inherited/"runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (inherited/"tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (inherited/"object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson entry)
    |>.setObjVal! "force" (toJson (#[] : Array String))
def build (tag settingsName : String) : IO Unit :=
  guard tag #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/settingsName).toString]
def closedAck (fixed : Bool) : IO Unit := do
  idle
  let label := if fixed then "fixed" else "baseline"
  let productRoot := if fixed then root else parent
  guard ("terminal-closure-ack-"++label) #["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    label,(records/("ack-"++label++".json")).toString,(records/("ack-"++label++".stderr")).toString,
    "/usr/bin/env","LEAN_PATH="++(productRoot/"build/lib").toString++":"++(compiler/"lib/lean").toString,
    (compiler/"bin/lean").toString,"-j1","-M2048","--run",
    (project/"tools/research/TerminalClosedAck.lean").toString,label]
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh closure candidate required"
  check ((← hash (parent/"build/StudyMain")) == "cc3c04355df8ff020f109fb8e886508c69de45f51096d8876aa8e32d8a65620d")
    "fixed parent runtime changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  for name in ["source","baseline-source"] do
    discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/name).toString]
  for name in ["build","baseline-build"] do copyLocalArtifacts (parent/"build") (root/name)
  IO.FS.writeFile (root/"baseline-source/tools/research/TerminalClosureChecks.lean")
    (← IO.FS.readFile (project/"tools/research/TerminalClosureChecks.lean"))
  write (root/"baseline-build-settings.json") (← settings (root/"baseline-source") (root/"baseline-build")
    (parent/"build") "tools.research.TerminalClosureChecks")
  write (root/"build-settings.json") (← settings (root/"source") (root/"build")
    (parent/"build") "tools.research.StudyMain")
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("interruptions",toJson #["before writes","pending only","state only","both writes","newer state","repeat native capture"]),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  build "terminal-closure-baseline-build" "baseline-build-settings.json"

def run (mode : String) : IO Unit := do
  idle
  discard <| finished (if mode == "fixed" then "terminal-closure-fixed-fresh-build" else "terminal-closure-baseline-build")
  let folder := root/mode
  let executable := root/(if mode == "baseline" then "baseline-build" else "checks-build")/"StudyMain"
  guard ("terminal-closure-"++mode) #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(folder/"data").toString,
    executable.toString,(if mode == "baseline" then "baseline" else "fixed"),folder.toString]

def sealPatch : IO Unit := do
  idle
  discard <| finished "terminal-closure-baseline"
  write (records/"baseline.json") (← read (root/"baseline/result.json"))
  let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/Eggshell/PluginHooks.lean",
    "-L","b/Eggshell/PluginHooks.lean",(parent/"source/Eggshell/PluginHooks.lean").toString,
    (root/"source/Eggshell/PluginHooks.lean").toString]}
  check (result.exitCode == 1) "declared closure change absent"
  IO.FS.writeFile (records/"candidate.patch") result.stdout
  build "terminal-closure-build" "build-settings.json"

def revise : IO Unit := do
  idle
  let first ← finished "terminal-closure-build"
  let diagnostic ← read (base/"terminal-closure-ack-baseline.guard.json")
  check (diagnostic.getObjValD "state" == toJson "finished" &&
    diagnostic.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "baseline acknowledgment diagnostic still live"
  check (!(← (base/"terminal-closure-fixed-build.guard.json").pathExists)) "candidate checks already executed"
  write (records/"pre-admission-revision.json") (Json.mkObj [("firstBuild",first),
    ("firstRuntimeSha256",toJson (← hash (root/"build/StudyMain"))),
    ("previousPatch",toJson (← IO.FS.readFile (records/"candidate.patch"))),
    ("ackBaselineGuard",diagnostic),("ackBaselineOuterExit",toJson (2 : Nat)),
    ("ackBaselineChildEvidenceRetained",toJson true),("actualCandidateHookCalls",toJson (0 : Nat)),
    ("reason",toJson "also reject closed/finalized turns at acknowledgment; isolate future guards to this candidate root")])
  let rejected ← try discard <| finished "terminal-closure-ack-baseline"; pure false catch _ => pure true
  check rejected "a triggered guard was mistaken for a successful stage"
  write (records/"guard-audit.json") (Json.mkObj [("triggeredGuardRejected",toJson true),
    ("successfulBuildAccepted",toJson true),("descendantTrackingUnchanged",toJson true),
    ("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
  let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/Eggshell/PluginHooks.lean",
    "-L","b/Eggshell/PluginHooks.lean",(parent/"source/Eggshell/PluginHooks.lean").toString,
    (root/"source/Eggshell/PluginHooks.lean").toString]}
  check (result.exitCode == 1) "revised closure change absent"
  IO.FS.writeFile (records/"candidate.patch") result.stdout
  let prepared := base/"terminal-closure-fixed-build.guard-settings.json"
  write prepared ((← read prepared).setObjVal! "ownedPrefixes" (toJson #[root.toString]))
  build "terminal-closure-checked-build" "build-settings.json"

def audit : IO Unit := do
  idle
  discard <| finished "terminal-closure-checked-build"
  for args in [#["inspect",(root/"build").toString,(records/"checked-native.json").toString],
      #["compare-sources",(parent/"build").toString,(root/"build").toString,
        (records/"checked-sources.json").toString,"Eggshell.PluginHooks"]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))

def prepareChecks : IO Unit := do
  idle
  discard <| finished "terminal-closure-checked-build"
  IO.FS.writeFile (root/"source/tools/research/TerminalClosureChecks.lean")
    (← IO.FS.readFile (project/"tools/research/TerminalClosureChecks.lean"))
  copyLocalArtifacts (root/"build") (root/"checks-build")
  write (root/"checks-build-settings.json") (← settings (root/"source") (root/"checks-build")
    (root/"build") "tools.research.TerminalClosureChecks")
  build "terminal-closure-fixed-build" "checks-build-settings.json"

def auditControl (recovery : Bool) : IO Unit := do
  idle
  let label := if recovery then "recovery" else "fixed"
  let area := if recovery then "recovery-build" else "checks-build"
  let evidence := if recovery then label else "fixed-checked"
  discard <| finished (if recovery then "terminal-closure-recovery-build" else "terminal-closure-fixed-fresh-build")
  for args in [#["inspect",(root/area).toString,(records/(evidence++"-native.json")).toString],
      #["subset-sources",(root/"build").toString,(root/area).toString,
        (records/(evidence++"-sources.json")).toString]++
        (if recovery then #["Main","Eggshell.PluginHooks"] else #["Eggshell.PluginHooks"])] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))

def prepareRecovery : IO Unit := do
  idle
  discard <| finished "terminal-closure-fixed"
  write (records/"fixed.json") (← read (root/"fixed/result.json"))
  copyLocalArtifacts (root/"build") (root/"recovery-build")
  write (root/"recovery-build-settings.json") (← settings (root/"source") (root/"recovery-build")
    (root/"build") "tools.research.TerminalIntentChecks")
  build "terminal-closure-recovery-build" "recovery-build-settings.json"

def install : IO Unit := do
  idle
  let sourceAudit ← read (records/"checked-sources.json")
  check (sourceAudit.getObjValD "candidateRuntimeSha256" == toJson (← hash (root/"build/StudyMain")))
    "runtime changed after its final source audit"
  IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/TerminalIntentStudy.lean").toString,"install-at",root.toString,parent.toString,records.toString,
    "checked-native.json"])

def fault : IO Unit := do
  idle
  discard <| finished "terminal-closure-recovery-build"
  let installation ← read (root/"installation.json")
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let updates := #[("EGGSHELL_DATA_ROOT",some (root/"fault/data").toString)]
  let environment := environment.filter (fun row => !updates.any (·.1 == row.1))++updates
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := environment.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  guard "terminal-closure-fault" (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "fault",(records/"fault.stdout").toString,(records/"fault.stderr").toString,"/usr/bin/env"]++
    unset.flatMap (fun key => #["-u",key])++assigned++#[(root/"recovery-build/StudyMain").toString,
      "fault",(root/"installation.json").toString,(root/"fault").toString])

def retain : IO Unit := do
  idle
  discard <| finished "terminal-closure-fault"
  for name in ["result","captured-before-services-stop","intent-before-restart","recovered-answer",
      "fault-frontend-stop","fault-publisher-stop","final-frontend-stop","final-publisher-stop"] do
    write (records/((if name == "result" then "fault" else name)++".json")) (← read (root/"fault"/(name++".json")))
  let mut calls := #[]
  for session in ← (root/"fault/calls").readDir do
    for call in ← session.path.readDir do
      if (← call.path.symlinkMetadata).type != .dir || !(← (call.path/"registration.json").pathExists) then continue
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("request",← read (call.path/"stdin")),("response",toJson (← IO.FS.readFile (call.path/"stdout"))),
        ("timing",← read (call.path/"record.json")),("registration",← read (call.path/"registration.json")),
        ("stderr",toJson (← IO.FS.readFile (call.path/"stderr")))])
  write (records/"registered-fault-calls.json") (toJson calls)

def proofAudit : IO Unit := do
  idle
  let names := ["terminal_clock_keeps_observed_time","terminal_scope_keeps_target",
    "terminal_replay_does_not_advance_epoch","terminal_replay_keeps_first_answer",
    "terminal_closure_keeps_newer_epoch","terminal_closure_never_decreases_epoch",
    "terminal_closure_finishes_observed_epoch","acknowledgment_rejects_closed_turn",
    "acknowledgment_rejects_answered_turn"]
  let law := root/"laws.lean"
  IO.FS.writeFile law ("import Eggshell.PluginHooks\n"++String.join (names.map fun name =>
    "#print axioms Eggshell.Plugin."++name++"\n"))
  guard "terminal-closure-proof-audit" #["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "kernel-axioms",(records/"laws.txt").toString,(records/"laws.stderr").toString,"/usr/bin/env",
    "LEAN_PATH="++(root/"build/lib").toString++":"++(compiler/"lib/lean").toString,
    (compiler/"bin/lean").toString,"-j1","-M2048",law.toString]

partial def files (path : System.FilePath) : IO (Array System.FilePath) := do
  if (← path.symlinkMetadata).type != .dir then return #[path]
  let mut result := #[]
  for entry in ← path.readDir do result := result++(← files entry.path)
  return result

partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,metadata.byteSize.toNat)
  let mut total := (1,0)
  for entry in ← path.readDir do
    let next ← remove entry.path
    total := (total.1+next.1,total.2+next.2)
  IO.FS.removeDir path
  return total

def refreshChecks : IO Unit := do
  idle
  let stopped ← read (base/"terminal-closure-fixed-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "stale-cache compiler remains live"
  check (!(← (root/"checks-build/StudyMain").pathExists)) "a native control already completed"
  let digest ← hash (root/"build/StudyMain")
  let removed ← remove (root/"checks-build")
  write (records/"stale-control-cache.json") (Json.mkObj [("guard",stopped),
    ("requestedStop",toJson true),("reason",toJson "control cache was copied before the final product revision; avoid recompiling unchanged product modules"),
    ("removedItems",toJson removed.1),("removedLogicalBytes",toJson removed.2),
    ("productSha256",toJson digest),("actualHookCalls",toJson (0 : Nat))])
  copyLocalArtifacts (root/"build") (root/"checks-build")
  check ((← hash (root/"build/StudyMain")) == digest) "product changed during control-cache refresh"
  build "terminal-closure-fixed-fresh-build" "checks-build-settings.json"

def retire : IO Unit := do
  idle
  check (!(← (records/"retired.json").pathExists)) "preserve retirement record"
  for name in ["baseline.json","fixed.json","fault.json","laws.txt","registered-fault-calls.json"] do
    check (← (records/name).pathExists) "retain validation evidence first"
  let mut guards := []
  for tag in ["baseline-build","baseline","build","checked-build","fixed-fresh-build","fixed","recovery-build","fault","proof-audit","ack-fixed"] do
    guards := guards++[(tag,← finished ("terminal-closure-"++tag))]
  guards := guards++[("ack-baseline",← read (base/"terminal-closure-ack-baseline.guard.json"))]
  guards := guards++[("fixed-build",← read (base/"terminal-closure-fixed-build.guard.json"))]
  write (records/"guards.json") (Json.mkObj guards)
  let targets := #[root/"baseline-source",root/"baseline-build",root/"baseline",root/"checks-build",
    root/"fixed",root/"recovery-build",root/"fault",root/"helper-lib",root/"tmp",root/"launcher.lean",root/"laws.lean"]
  let retiredPath := fun (text : String) => targets.any fun target =>
    text == target.toString || text.startsWith (target.toString++"/")
  let builds := #[root/"build",parent/"build",base/"practical-runtime/terminal-capture/build",
    base/"practical-runtime/readonly-save/build",base/"practical-runtime/block-seek/build",
    base/"practical-runtime/build",base/"practical-runtime/independent-maintenance/build",
    base/"practical-runtime/coordinated-warm/build",base/"canonical-decoder-runtime/build"]
  let protectedRuntimes ← builds.mapM fun directory => do pure (directory/"StudyMain",← hash (directory/"StudyMain"))
  for directory in builds do
    for line in (← IO.FS.readFile (directory/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      if path.isAbsolute then check (!retiredPath (← IO.FS.realPath path).toString) "current native input is a retirement target"
    for path in ← files (directory/"lib") do
      if (← path.symlinkMetadata).type == .symlink then
        check (!retiredPath (← IO.FS.realPath path).toString) "current interface is a retirement target"
  check (!retiredPath (← IO.FS.realPath (root/"prefix/share/eggshell/minilm")).toString) "model is a retirement target"
  let original ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let source : String ← IO.ofExcept (original.getObjValAs? _ "source")
  let originalFiles : Array (String × String) ← IO.ofExcept (original.getObjValAs? _ "sourceFiles")
  for (name,digest) in originalFiles do check ((← hash (System.FilePath.mk source/name)) == digest) "original source changed"
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any fun line => targets.any (fun target => line.contains target.toString))
    "ended artifact still belongs to a process"
  let mut removed := (0,0)
  for path in targets do
    if !(← path.pathExists) then continue
    let next ← remove path
    removed := (removed.1+next.1,removed.2+next.2)
  for (path,digest) in protectedRuntimes do check ((← hash path) == digest) "protected runtime changed"
  for (name,digest) in originalFiles do check ((← hash (System.FilePath.mk source/name)) == digest) "original changed during retirement"
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
      if (← entry.path.metadata).byteSize == 0 then IO.FS.removeFile entry.path
  write (records/"retired.json") (Json.mkObj [("files",toJson removed.1),("logicalBytes",toJson removed.2),
    ("archiveCreated",toJson false),("sourceAndRuntimeHashesUnchanged",toJson true),
    ("nativeInputsAndInterfacesOutsideRetiredTargets",toJson true)])
end TerminalClosureStudy
def main : List String → IO Unit
  | ["prepare"] => TerminalClosureStudy.prepare
  | ["ack-baseline"] => TerminalClosureStudy.closedAck false
  | ["ack-fixed"] => TerminalClosureStudy.closedAck true
  | ["baseline"] => TerminalClosureStudy.run "baseline"
  | ["seal"] => TerminalClosureStudy.sealPatch
  | ["revise"] => TerminalClosureStudy.revise
  | ["audit"] => TerminalClosureStudy.audit
  | ["prepare-checks"] => TerminalClosureStudy.prepareChecks
  | ["fixed"] => TerminalClosureStudy.run "fixed"
  | ["audit-fixed"] => TerminalClosureStudy.auditControl false
  | ["prepare-recovery"] => TerminalClosureStudy.prepareRecovery
  | ["audit-recovery"] => TerminalClosureStudy.auditControl true
  | ["install"] => TerminalClosureStudy.install
  | ["fault"] => TerminalClosureStudy.fault
  | ["retain"] => TerminalClosureStudy.retain
  | ["proof-audit"] => TerminalClosureStudy.proofAudit
  | ["retire"] => TerminalClosureStudy.retire
  | ["refresh-checks"] => TerminalClosureStudy.refreshChecks
  | _ => throw (IO.userError "TerminalClosureStudy prepare|baseline|seal|audit|prepare-checks|fixed")
