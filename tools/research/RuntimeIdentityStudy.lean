import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.RuntimeIdentityStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def study := workspace/"docs/candidates/runtime-key"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (args : Array String) : IO Unit := do
  let result ← IO.Process.output {cmd := (compiler/"bin/lean").toString,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot identify runtime"
  return (result.stdout.splitOn " ").headD ""
def drained : IO Unit := do
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (!result.stdout.contains "controller/StudyMain guard ") "native guard active"
def prepare : IO Unit := do
  drained
  let source := base/"runtime-key-source"
  check (!(← source.pathExists)) "fresh isolated source required"
  IO.FS.createDirAll study
  command #["-j1","-M1536","--run",(workspace/"tools/research/DiscoveryStagesStudy.lean").toString,
    "materialize-native",(base/"parallel-encoder-build").toString,source.toString,(base/"runtime-key-build").toString,
    "tools.research.ReplayReadinessChecks",(base/"runtime-key-settings.json").toString]
  IO.FS.writeFile (source/"tools/research/RuntimeIdentityChecks.lean")
    (← IO.FS.readFile (workspace/"tools/research/RuntimeIdentityChecks.lean"))
def freezeSource : IO Unit := do
  drained
  for relative in ["Eggshell/Numerical.lean","Eggshell/ContractAudit.lean","tools/research/ReplayReadinessChecks.lean"] do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/"parallel-encoder-source"/relative).toString,(base/"runtime-key-source"/relative).toString]}
    check (result.exitCode == 1) "missing declared runtime patch"
    IO.FS.writeFile (study/(relative.replace "/" "_"++".patch")) result.stdout
def sealRuntime : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  command #["-j1","-M1536","--run",audit,"inspect",(base/"runtime-key-build").toString,(study/"native-closure.json").toString]
  command #["-j1","-M1536","--run",audit,"compare-sources",(base/"parallel-encoder-build").toString,
    (base/"runtime-key-build").toString,(study/"native-sources.json").toString,"Eggshell.Numerical","Eggshell.ContractAudit",
    "+tools.research.RuntimeIdentityChecks"]
  freezeSource
def prepareAuditor : IO Unit := do
  drained
  command #["-j1","-M1536","--run",(workspace/"tools/research/RealSourceStudy.lean").toString,
    "prepare-auditor",(base/"runtime-key-build").toString,(base/"runtime-key-auditor-source").toString,
    (base/"runtime-key-auditor-build").toString,(base/"runtime-key-auditor-settings.json").toString]
  let sha ← hash (base/"runtime-key-build/StudyMain")
  let installation := base/"runtime-key-prefix"
  write (base/"runtime-key-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (base/"runtime-key-build/StudyMain").toString),("sha256",toJson sha)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let root := base/"runtime-key-cells-result"
  let original := base/"real-source-search-read-input.json"
  let originalHash ← hash original
  let mut probes := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      probes := probes.push (Json.mkObj [
        ("originalInput",Json.mkObj [("path",toJson original.toString),("sha256",toJson originalHash)]),
        ("runtime",Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson sha)]),
        ("pluginRoot",toJson (installation/"share/eggshell/codex-plugin").toString),
        ("topic",toJson topic),("destination",toJson (root/s!"topic-{topic}-chat-{repetition}").toString),
        ("captureReply",toJson false)])
  write (base/"runtime-key-cells.json") (Json.mkObj [("output",toJson root.toString),("probes",toJson probes)])
def sealAuditor : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  command #["-j1","-M1536","--run",audit,"inspect",(base/"runtime-key-auditor-build").toString,(study/"auditor-closure.json").toString]
  command #["-j1","-M1536","--run",audit,"common-sources",(base/"runtime-key-build").toString,
    (base/"runtime-key-auditor-build").toString,(study/"auditor-sources.json").toString]
def collectProbe : IO Unit := do
  drained
  let parent ← read (base/"runtime-identity-parent1-result/report.json")
  let actual ← read (base/"runtime-key-probe1-result/report.json")
  check (parent.getObjValD "mode" == toJson "parent" && actual.getObjValD "mode" == toJson "factored")
    "actual key comparison did not run"
  write (study/"identity-controls.json") (Json.mkObj [("parent",parent),("candidate",actual),
    ("parentProbeSha256",toJson (← hash (base/"runtime-identity-build/StudyMain"))),
    ("parentGuard",← read (base/"runtime-identity-parent1.guard.json")),
    ("candidateGuard",← read (base/"runtime-key-probe1.guard.json")),
    ("candidateBuildGuard",← read (base/"runtime-key-build1.guard.json")),
    ("parentProbeBuildGuard",← read (base/"runtime-identity-build1.guard.json")),
    ("runtimeSha256",toJson (← hash (base/"runtime-key-build/StudyMain"))),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def retireProbe : IO Unit := do
  drained
  let evidence ← read (study/"identity-controls.json")
  let path := base/"runtime-identity-build/StudyMain"
  check (evidence.getObjValD "parentProbeSha256" == toJson (← hash path)) "old identity probe differs"
  let ps ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (!ps.stdout.contains path.toString) "old identity probe is active"
  write (study/"retired-probe.json") (Json.mkObj [("path",toJson path.toString),
    ("sha256",evidence.getObjValD "parentProbeSha256"),("bytes",toJson (← path.metadata).byteSize.toNat),
    ("sourcesInputsCurrentRuntimeAndParentsRetained",toJson true),("archived",toJson false)])
  IO.FS.removeFile path
def recoverStoppedOwner : IO Unit := do
  drained
  let stopped ← read (base/"parallel-capacity-801.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "previous owner has not drained"
  let known ← IO.ofExcept (stopped.getObjValAs? (Array Json) "peakProcesses")
  let dataRoot := base/"real-source-search-read-trial-result/data"
  let mut paths := #[dataRoot/"publisher/endpoint.json",dataRoot/"publisher/operations.json",dataRoot/"daemon.json"]
  for entry in ← (dataRoot/"numerical").readDir do
    if ← (entry.path/"endpoint.json").pathExists then paths := paths.push (entry.path/"endpoint.json")
  let mut removed := #[]
  for path in paths do
    let value ← read path
    let pid ← IO.ofExcept (value.getObjValAs? Nat "pid")
    check (known.any (fun row => row.getObjValD "pid" == toJson pid)) "endpoint is not from the stopped owned run"
    let process ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","stat="]}
    check (process.exitCode != 0 || process.stdout.trimAscii.toString.startsWith "Z" ||
      process.stdout.trimAscii.toString.startsWith "X") "endpoint still has a live process"
    let before ← hash path
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("pid",toJson pid),("sha256",toJson before)])
    check ((← hash path) == before) "endpoint changed during owned recovery"
    IO.FS.removeFile path
  let failed := base/"runtime-key-cells-result"
  let progress ← read (failed/"progress.json")
  let rows ← IO.ofExcept progress.getArr?
  check (rows.size == 1 && (rows[0]?.getD Json.null).getObjValD "error" == toJson "a publisher already owns this study scope")
    "preserve any actual delivery attempt"
  write (study/"preflight-recovery.json") (Json.mkObj [("guard",← read (base/"runtime-key-cells1.guard.json")),
    ("progress",progress),("removedOwnedDeadEndpoints",toJson removed),("sourceAndProjectCacheRetained",toJson true),
    ("actualDeliveryStarted",toJson false),("archived",toJson false)])
  IO.FS.removeDirAll failed
def setup (action tag : String) : IO Unit := do
  drained
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh runtime guard required"
  let args ← match action with
    | "build" | "auditor" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,
      (base/(if action == "build" then "runtime-key-settings.json" else "runtime-key-auditor-settings.json")).toString]
    | "probe" => pure #[(base/"runtime-key-build/StudyMain").toString,"runtime-identity-check","factored",(base/(tag++"-result")).toString]
    | "install" => pure #[(base/"runtime-key-auditor-build/StudyMain").toString,"install-prefix",(base/"runtime-key-install.json").toString]
    | "cells" => do
      let audit ← read (study/"auditor-sources.json")
      check (audit.getObjValD "commonSourcesUnchanged" == toJson true && audit.getObjValD "allProductCorePresent" == toJson true &&
        audit.getObjValD "productSha256" == toJson (← hash (base/"runtime-key-build/StudyMain")) &&
        audit.getObjValD "auditorSha256" == toJson (← hash (base/"runtime-key-auditor-build/StudyMain"))) "incoherent real-source auditor"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/"runtime-key-auditor-build/StudyMain").toString,"cells",(base/"runtime-key-cells.json").toString]
    | _ => throw (IO.userError "unknown runtime step")
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["freeze"] => freezeSource
  | ["seal"] => sealRuntime
  | ["prepare-auditor"] => prepareAuditor
  | ["seal-auditor"] => sealAuditor
  | ["collect-probe"] => collectProbe
  | ["retire-probe"] => retireProbe
  | ["recover-stopped-owner"] => recoverStoppedOwner
  | ["setup",action,tag] => setup action tag
  | _ => throw (IO.userError "prepare|freeze|seal|prepare-auditor|seal-auditor|setup")
end Eggshell.Research.RuntimeIdentityStudy
def main := Eggshell.Research.RuntimeIdentityStudy.main
