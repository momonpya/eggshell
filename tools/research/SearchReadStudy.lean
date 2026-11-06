import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.SearchReadStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"read-runtime-build"
def source := base/"search-read-source"
def target := base/"search-read-build"
def study := workspace/"docs/candidates/search-read"
def wire := base/"search-read-wire/Fixture"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let all ← command "/bin/ps" #["-axo","command="]
  check (!(all.splitOn "\n").any (fun row => row.contains "controller/StudyMain guard ")) "native guard still active"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "search-read-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "search-read guard not drained"
def prepare : IO Unit := do
  drained
  check ((← hash (parent/"StudyMain")) == "a7abe3c71ba50f0b20f492d8291b4df993d0454bf2e5fa4e3e5e59fdbab3f78f")
    "recorded parent runtime changed"
  check (!(← source.pathExists)) "new immutable parent materialization required"
  IO.FS.createDirAll study
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,target.toString,"tools.research.ReplayReadinessChecks",(base/"search-read-settings.json").toString]
def refresh : IO Unit := do
  drained
  for name in ["SearchReadCut","SearchReadChecks"] do
    let relative := "tools/research/"++name++".lean"
    IO.FS.writeFile (source/relative) (← IO.FS.readFile (workspace/relative))
def buildWire : IO Unit := do
  IO.FS.createDirAll wire.parent.get!
  let c := wire.withExtension "c"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","-c",c.toString,
    (workspace/"tools/research/SearchReadWire.lean").toString]
  discard <| command (compiler/"bin/leanc").toString #["-O2",c.toString,"-o",wire.toString,"-lLean"]
def setup (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh guard required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"search-read-settings.json").toString]
    | "wire" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/SearchReadStudy.lean").toString,"build-wire"]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,
        "search-read-check",(base/(tag++"-result")).toString,wire.toString]
    | _ => throw (IO.userError "unknown action")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def patches : IO Unit := do
  drained
  for relative in ["Eggshell/Worker.lean","Eggshell/ContractAudit.lean","tools/research/ReplayReadinessChecks.lean"] do
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/"read-runtime-source"/relative).toString,(source/relative).toString]}
    check (patch.exitCode == 1) "declared patch missing"
    IO.FS.writeFile (study/(relative.replace "/" "_"++".patch")) patch.stdout
def record (tag : String) : IO Unit := do
  drained
  let guard ← read (base/(tag++".guard.json"))
  write (study/(tag++".guard.json")) guard
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
    "candidate control failed"
  write (study/"controls.json") (← read (base/(tag++"-result/report.json")))
  patches
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"native-sources.json").toString,
    "Eggshell.Worker","Eggshell.ContractAudit","+tools.research.SearchReadCut","+tools.research.SearchReadChecks"]
  write (study/"runtime.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"StudyMain"))),
    ("sha256",toJson (← hash (target/"StudyMain"))),("adopted",toJson false),("paidComparisons",toJson "0/18")])
def applyPatches : IO Unit := do
  drained
  for relative in ["Eggshell/Worker.lean","Eggshell/ContractAudit.lean","tools/research/ReplayReadinessChecks.lean"] do
    check ((← IO.FS.readFile (source/relative)) == (← IO.FS.readFile (base/"read-runtime-source"/relative)))
      "patch only the exact unmodified parent source"
    let result ← IO.Process.output {cmd := "/usr/bin/patch",args := #["-s","-p1","-i",
      (study/(relative.replace "/" "_"++".patch")).toString],cwd := some source}
    check (result.exitCode == 0) "recorded source patch rejected"
  refresh
def preserveReview : IO Unit := do
  drained
  let prior ← read (study/"cleanup-review.json")
  let sources ← read (study/"native-sources.json")
  check (sources.getObjValD "candidateRuntimeSha256" == (prior.getObjValD "priorRuntime").getObjValD "sha256")
    "only the recorded pre-cleanup audit may move"
  let destination := study/"cleanup-review-native.json"
  check (!(← destination.pathExists)) "preserve existing review evidence"
  write destination (Json.mkObj [("sources",sources),("closure",← read (study/"native-closure.json"))])
  IO.FS.removeFile (study/"native-sources.json")
  IO.FS.removeFile (study/"native-closure.json")
def finish : IO Unit := do
  drained
  check ((← read (study/"native-closure.json")).getObjValD "consistent" == toJson true &&
    (← read (study/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "coherent exact candidate source required"
  let controls ← read (study/"controls.json")
  check (controls.getObjValD "nativeExchanges" == toJson (240 : Nat) &&
    controls.getObjValD "cancelledReadJoined" == toJson true) "retain complete native controls first"
  for tag in ["search-read-build1","search-read-build2","search-read-build3","search-read-build4",
      "search-read-build5","search-read-build6","search-read-build7","search-read-build8",
      "search-read-checks1","search-read-checks2","search-read-checks3","search-read-checks4",
      "search-read-wire1","search-read-wire2"] do
    write (study/(tag++".guard.json")) (← read (base/(tag++".guard.json")))
  let kernel ← IO.FS.readFile (target/"tools_research_SearchReadChecks-lean.stdout")
  check (!kernel.contains "sorryAx" && !kernel.contains "error:" && kernel.contains "dependencies audited" &&
    kernel.contains "209 dependencies without IO") "retain actual kernel and dependency audit"
  IO.FS.writeFile (study/"kernel-audit.txt") kernel
  write (study/"development.json") (Json.mkObj [("nativeBuildFailures",toJson (3 : Nat)),
    ("failureReasons",toJson #["do/unless simplification in new pure proof", "Except.isOk unfolding in new pure proof", "reserved until name in new test"]),
    ("nativeControlFailures",toJson #[
      "80 full product fixture processes hit aggregate RSS stop at 3688736 KiB; no results claimed",
      "foreign negative fixture accidentally reused its expected turn; corrected to append /foreign"]),
    ("fixtureCorrectionChangesProductCode",toJson false),("noGuardLimitsRaised",toJson true),
    ("stoppedNativeBuilds",toJson (1 : Nat)),
    ("stoppedBuildReason",toJson "stopped build7 after a Bool/Prop preflight error; guard reaped compiler leftovers before the source correction"),
    ("cleanupReview",toJson "cleanup-review.json retains the first successful candidate; final candidate gives read, checked step and expired phase one retirement owner each"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  let originalCheck ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (originalCheck.exitCode == 0) "protected original changed"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
    Except String (Array (String × (String × String))))
  for (path,(bytes,digest)) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == digest) "project source head changed"
  let wireHash ← hash wire
  let mut removed : Array String := #[]
  for tag in ["search-read-checks1","search-read-checks2","search-read-checks3","search-read-checks4"] do
    let root := base/(tag++"-result")
    if ← root.pathExists then IO.FS.removeDirAll root; removed := removed.push root.toString
  for path in [wire,wire.withExtension "c"] do
    if ← path.pathExists then IO.FS.removeFile path; removed := removed.push path.toString
  write (study/"cleanup.json") (Json.mkObj [("removed",toJson removed),("wireSha256",toJson wireHash),
    ("wireLeanSourceRetained",toJson true),("productSourcesObjectsInterfacesRetained",toJson true),
    ("protectedOriginalFiles",toJson (5 : Nat)),("protectedCompleteHeads",toJson heads.size),
    ("allProtectedBytesUnchanged",toJson true),("archived",toJson false)])
def pruneLogs : IO Unit := do
  drained
  check ((← read (study/"cleanup.json")).getObjValD "allProtectedBytesUnchanged" == toJson true)
    "retain controls, failures and original checks before pruning logs"
  let mut count := 0
  for entry in ← target.readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
      let raw ← IO.FS.readFile entry.path
      check (!raw.contains "error:") "unrecorded failed build log must be retained"
      IO.FS.removeFile entry.path
      count := count+1
  write (study/"logs-cleanup.json") (Json.mkObj [("removedSuccessfulBuildLogs",toJson count),
    ("kernelAndFailedBuildLogsRetained",toJson true),("archived",toJson false)])
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["refresh"] => refresh
  | ["build-wire"] => buildWire
  | ["setup",action,tag] => setup action tag
  | ["record",tag] => record tag
  | ["apply-patches"] => applyPatches
  | ["preserve-review"] => preserveReview
  | ["finish"] => finish
  | ["prune-logs"] => pruneLogs
  | ["patches"] => patches
  | _ => throw (IO.userError "prepare | refresh | setup ACTION TAG | record TAG")
end Eggshell.Research.SearchReadStudy
def main := Eggshell.Research.SearchReadStudy.main
