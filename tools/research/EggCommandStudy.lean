import tools.research.StudyLocal
open Lean StudyLocal
namespace EggCommandStudy
def parent := base/"canonical-decoder-runtime"
def practical := base/"practical-runtime"
def area := practical/"egg-commands"
def records := project/"docs/candidates/egg-commands"

/-- Metadata and compiler setup only. All DB operations run in the guarded
native executable, never in this Lean interpreter. -/
def prepare : IO Unit := do
  idle
  check (!(← area.pathExists)) "fresh isolated command candidate required"
  IO.FS.createDirAll area
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(area/"source").toString]
  discard <| command "/bin/cp" #["-cR",(parent/"build").toString,(area/"build").toString]
  IO.FS.writeFile (area/"source/Eggshell/PluginCli.lean")
    (← IO.FS.readFile (records/"Eggshell/PluginCli.lean"))
  let entry := area/"source/tools/research/OwnedSelectionRuntime.lean"
  let original ← IO.FS.readFile entry
  check ((original.splitOn "\ndef main (args : List String)").length == 2) "entrypoint boundary changed"
  IO.FS.writeFile entry (original.replace "\ndef main (args : List String)"
    "\ndef productMain (args : List String)" ++ "\n" ++ (← IO.FS.readFile (records/"NativeChecks.lean")))
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (area/"source").toString)
    |>.setObjVal! "core" (toJson (area/"source").toString)
    |>.setObjVal! "output" (toJson (area/"build").toString)
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_OwnedSelectionRuntime.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "force" (toJson (#[] : Array String))
  write (area/"build-settings.json") settings
  guard "practical-egg-commands-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(area/"build-settings.json").toString]

def qualify : IO Unit := do
  discard <| finished "practical-egg-commands-ready"
  guard "practical-egg-commands-native" #["/usr/bin/env",
    "EGGSHELL_DATA_ROOT="++(area/"checks/data").toString,
    "EGGSHELL_PREFIX="++(area/"checks/prefix").toString,
    "CODEX_THREAD_ID=egg-command-native-check",
    (area/"build/StudyMain").toString,"egg-command-checks",(area/"checks").toString]

def resume : IO Unit := do
  idle
  let previous ← read (base/"practical-egg-commands-build.guard.json")
  check (previous.getObjValD "state" == toJson "finished" &&
    previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous build is still live"
  IO.FS.writeFile (area/"source/Eggshell/PluginCli.lean")
    (← IO.FS.readFile (records/"Eggshell/PluginCli.lean"))
  let original ← IO.FS.readFile (parent/"source/tools/research/OwnedSelectionRuntime.lean")
  IO.FS.writeFile (area/"source/tools/research/OwnedSelectionRuntime.lean")
    (original.replace "\ndef main (args : List String)" "\ndef productMain (args : List String)" ++
      "\n" ++ (← IO.FS.readFile (records/"NativeChecks.lean")))
  guard "practical-egg-commands-ready" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(area/"build-settings.json").toString]

def collect : IO Unit := do
  let monitor ← finished "practical-egg-commands-native"
  let result ← read (area/"checks/result.json")
  write (records/"native-checks.json") (result
    |>.setObjVal! "runtimeSha256" (toJson (← hash (area/"build/StudyMain")))
    |>.setObjVal! "parentRuntimeSha256" (toJson (← hash (parent/"build/StudyMain")))
    |>.setObjVal! "guard" monitor)
  IO.println "Native command checks retained; candidate is not adopted."

def audit : IO Unit := do
  discard <| finished "practical-egg-commands-ready"
  let auditor := project/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditor.toString,
    "inspect",(area/"build").toString,(records/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditor.toString,
    "compare-sources",(parent/"build").toString,(area/"build").toString,
    (records/"source-changes.json").toString,"Eggshell.PluginCli"]
  let mut failed := #[]
  for name in ["practical-egg-commands-build","practical-egg-commands-resume","practical-egg-commands-entry-fix"] do
    let monitor ← read (base/(name++".guard.json"))
    check (monitor.getObjValD "state" == toJson "finished" &&
      monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous failed build did not drain"
    failed := failed.push (Json.mkObj [("stage",toJson name),("exitCode",monitor.getObjValD "exitCode"),
      ("elapsedMs",monitor.getObjValD "elapsedMs"),("ownedPids",monitor.getObjValD "ownedPids")])
  write (records/"build-attempts.json") (Json.mkObj [("failedNativeBuilds",toJson failed),
    ("reason",toJson "Native test-entry record layout and UInt32 JSON errors; no DB or answering-model operation ran."),
    ("standaloneTypecheck",toJson "A 768 MiB interpreter typecheck hit its own limit; the guarded native compiler uses the existing 3 GiB limit."),
    ("successfulBuild",← finished "practical-egg-commands-ready")])

def retire : IO Unit := do
  idle
  discard <| finished "practical-egg-commands-native"
  let result ← read (records/"native-checks.json")
  let original ← hash (parent/"build/StudyMain")
  let candidate ← hash (area/"build/StudyMain")
  check (result.getObjValD "runtimeSha256" == toJson candidate &&
    result.getObjValD "parentRuntimeSha256" == toJson original) "retained executable changed"
  check ((← read (records/"native-closure.json")).getObjValD "consistent" == toJson true &&
    (← read (records/"source-changes.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "native input audit is incomplete"
  let checks := area/"checks"
  check (← checks.pathExists) "command fixture already retired"
  let usage ← command "/usr/bin/du" #["-sk",checks.toString]
  discard <| command "/bin/rm" #["-rf",checks.toString]
  check (!(← checks.pathExists) && (← hash (parent/"build/StudyMain")) == original &&
    (← hash (area/"build/StudyMain")) == candidate) "fixture retirement changed protected inputs"
  write (records/"retired.json") (Json.mkObj [("removed",toJson checks.toString),
    ("beforeDiskUsageKiB",toJson usage.trimAscii.toString),("archive",toJson false),
    ("originalRuntimeUnchanged",toJson true),("candidateRuntimeUnchanged",toJson true),
    ("sourceDbTouched",toJson false)])

def main : List String → IO Unit
  | ["prepare"] => prepare
  | ["resume"] => resume
  | ["qualify"] => qualify
  | ["collect"] => collect
  | ["audit"] => audit
  | ["retire"] => retire
  | _ => throw (IO.userError "EggCommandStudy prepare|resume|qualify|collect|audit|retire")
end EggCommandStudy
def main := EggCommandStudy.main
