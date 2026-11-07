import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.LocalBatchStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def study := workspace/"docs/candidates/local-batch"
def relatives := ["tools/research/SourceViewBatch.lean","Eggshell/PublicationClient.lean",
  "Eggshell/PublicationService.lean","Eggshell/ContractAudit.lean",
  "tools/research/RuntimeReadControls.lean","tools/research/ReplayReadinessChecks.lean"]
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def drained : IO Unit := do
  for tag in ["memory-capacity-small1","memory-capacity-trace1","memory-capacity-build4"] do
    let record ← read (base/(tag++".guard.json"))
    check (record.getObjValD "state" == toJson "finished" && record.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "previous runtime still owns processes"
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (!(result.stdout.splitOn "\n").any (·.contains "controller/StudyMain guard ")) "guard still running"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "local-batch-" && entry.fileName.endsWith ".guard.json" then
      let record ← read entry.path
      check (record.getObjValD "state" == toJson "finished" && record.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "candidate still owns processes"
def command (args : Array String) : IO Unit := do
  let result ← IO.Process.output {cmd := (compiler/"bin/lean").toString,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
def prepare : IO Unit := do
  drained
  check (!(← (base/"local-batch-source").pathExists) && !(← (base/"local-batch-build").pathExists))
    "fresh isolated source and build required"
  command #["-j1","-M1536","--run",(workspace/"tools/research/DiscoveryStagesStudy.lean").toString,
    "materialize-native",(base/"delivery-ledger-build").toString,(base/"local-batch-source").toString,
    (base/"local-batch-build").toString,"tools.research.ReplayReadinessChecks",(base/"local-batch-settings.json").toString]
  for relative in relatives do
    let result ← IO.Process.output {cmd := "/usr/bin/patch",args := #["-s","-p1","-i",
      (study/(relative.replace "/" "_"++".patch")).toString],cwd := some (base/"local-batch-source")}
    check (result.exitCode == 0) ("isolated source patch rejected "++relative)
def sealRuntime : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  command #["-j1","-M1536","--run",audit,"inspect",(base/"local-batch-build").toString,
    (study/"native-closure.json").toString]
  command #["-j1","-M1536","--run",audit,"compare-sources",(base/"delivery-ledger-build").toString,
    (base/"local-batch-build").toString,(study/"native-sources.json").toString,
    "tools.research.SourceViewBatch","Eggshell.PublicationClient","Eggshell.PublicationService",
    "Eggshell.ContractAudit","tools.research.RuntimeReadControls"]
def retireObsolete : IO Unit := do
  drained
  let mut removed := #[]
  for name in ["allocator-service-build","read-runtime-client-build","replay-readiness-client-build"] do
    let path := base/name/"StudyMain"
    check (← (base/name/"runtime.rsp").pathExists) "old executable lost native provenance"
    let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
    check (result.exitCode == 0) "cannot identify obsolete executable"
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson ((result.stdout.splitOn " ").headD "")),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  write (study/"retired-executables.json") (Json.mkObj [("removed",toJson removed),
    ("currentParentOriginalsAndNativeDependenciesRetained",toJson true),("archived",toJson false)])
  for row in removed do IO.FS.removeFile (.mk (← IO.ofExcept (row.getObjValAs? String "path")))
def freeze : IO Unit := do
  drained
  IO.FS.createDirAll study
  for relative in relatives do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/"delivery-ledger-source"/relative).toString,(base/"local-batch-source"/relative).toString]}
    check (result.exitCode == 1) ("candidate has no declared change "++relative)
    IO.FS.writeFile (study/(relative.replace "/" "_"++".patch")) result.stdout
def setup (action tag : String) : IO Unit := do
  drained
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh guard identity required"
  let command ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"local-batch-settings.json").toString]
    | "checks" => do
      check ((← read (study/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
        "source/runtime coherence required before controls"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(base/"local-batch-controls-data").toString,
        (base/"local-batch-build/StudyMain").toString,
        "local-batch-check",(base/(tag++"-result")).toString]
    | _ => throw (IO.userError "build or checks required")
  write path (Json.mkObj [("command",toJson command),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def collect : IO Unit := do
  drained
  let root := base/"local-batch-checks1-result"
  let result ← read (root/"report.json")
  check (result.getObjValD "typedReadChecks" == toJson true &&
    result.getObjValD "allReservationsReleased" == toJson true &&
    result.getObjValD "originalHeadsUnchanged" == toJson true) "native read boundary controls failed"
  write (study/"controls.json") (Json.mkObj [("result",result),
    ("readBoundary",← read (root/"read-boundary.json")),("heldLockReads",← read (root/"held-lock-reads.json")),
    ("eightyComponentReaders",← read (root/"shared-eighty.json")),
    ("buildGuard",← read (base/"local-batch-build1.guard.json")),
    ("controlsGuard",← read (base/"local-batch-checks1.guard.json")),
    ("buildSettings",← read (base/"local-batch-settings.json")),
    ("answeringModelCalls",toJson (0 : Nat)),("fullHookCapacityPassed",toJson false),("adopted",toJson false)])
  IO.FS.removeDirAll (root/"file-fixture")
  if ← (base/"local-batch-controls-data").pathExists then IO.FS.removeDirAll (base/"local-batch-controls-data")
  write (study/"cleanup.json") (Json.mkObj [("removed",toJson #[(root/"file-fixture").toString,
    (base/"local-batch-controls-data").toString]),("originalsAndCurrentProjectCacheRetained",toJson true),("archived",toJson false)])
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["freeze"] => freeze
  | ["seal"] => sealRuntime
  | ["retire-obsolete"] => retireObsolete
  | ["collect"] => collect
  | ["setup",action,tag] => setup action tag
  | _ => throw (IO.userError "freeze|setup build/checks tag")
end Eggshell.Research.LocalBatchStudy
def main := Eggshell.Research.LocalBatchStudy.main
