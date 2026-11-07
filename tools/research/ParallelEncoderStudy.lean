import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.ParallelEncoderStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def source := base/"parallel-encoder-source"
def target := base/"parallel-encoder-build"
def study := workspace/"docs/candidates/parallel-encoder"
def auditorSource := base/"parallel-encoder-auditor-source"
def auditor := base/"parallel-encoder-auditor-build"
def installation := base/"parallel-encoder-prefix"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO Unit := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot identify frozen numerical executable"
  return (result.stdout.splitOn " ").headD ""
def drained : IO Unit := do
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (!(result.stdout.splitOn "\n").any (·.contains "controller/StudyMain guard ")) "native guard is active"
  for entry in ← base.readDir do
    if (entry.fileName.startsWith "local-batch-" || entry.fileName.startsWith "parallel-encoder-") &&
        entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "previous owner has not drained"
def prepare : IO Unit := do
  drained
  let native ← read (workspace/"docs/candidates/local-batch/delivery-cells.json")
  check (native.getObjValD "actualDeliveryAllSixPassed" == toJson true &&
    native.getObjValD "allParentBodiesByteEqual" == toJson true) "complete the parent delivery audit first"
  check (!(← source.pathExists) && !(← target.pathExists)) "fresh isolated encoder candidate required"
  IO.FS.createDirAll study
  command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"local-batch-build").toString,source.toString,target.toString,"tools.research.ReplayReadinessChecks",
    (base/"parallel-encoder-settings.json").toString]
  for name in ["EncoderPool","NumericalParallelControls"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (workspace/"tools/research"/(name++".lean")))
  write (study/"pool-preflight.json") (← read (base/"encoder-pool-preflight/report.json"))
def refresh : IO Unit := do
  drained
  for name in ["EncoderPool","NumericalParallelControls"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (workspace/"tools/research"/(name++".lean")))
  let unused := source/"tools/research/EncoderPoolControls.lean"
  if ← unused.pathExists then IO.FS.removeFile unused
def sealRuntime : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit,"inspect",target.toString,
    (study/"native-closure.json").toString]
  command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit,"compare-sources",
    (base/"local-batch-build").toString,target.toString,(study/"native-sources.json").toString,
    "Eggshell.Numerical","Eggshell.ContractAudit","+tools.research.EncoderPool","+tools.research.NumericalParallelControls"]
  for relative in ["Eggshell/Numerical.lean","Eggshell/ContractAudit.lean","tools/research/ReplayReadinessChecks.lean"] do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/"local-batch-source"/relative).toString,(source/relative).toString]}
    check (result.exitCode == 1) "declared encoder patch missing"
    IO.FS.writeFile (study/(relative.replace "/" "_"++".patch")) result.stdout
def freezeSource : IO Unit := do
  drained
  for relative in ["Eggshell/Numerical.lean","Eggshell/ContractAudit.lean","tools/research/ReplayReadinessChecks.lean"] do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/"local-batch-source"/relative).toString,(source/relative).toString]}
    check (result.exitCode == 1) "declared encoder patch missing"
    IO.FS.writeFile (study/(relative.replace "/" "_"++".patch")) result.stdout
def collectControls : IO Unit := do
  drained
  let report ← read (base/"parallel-encoder-controls1-result/report.json")
  check (report.getObjValD "allPassed" == toJson true &&
    (report.getObjValD "warmWave").getObjValD "differentModelIntervalsOverlap" == toJson true)
    "actual MiniLM overlap and exact vector comparisons required"
  write (study/"controls.json") (Json.mkObj [("actualModel",report),
    ("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("guard",← read (base/"parallel-encoder-controls1.guard.json")),
    ("ownershipPreflight",← read (base/"encoder-pool-preflight/report-idle.json")),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  let mut builds := #[]
  for index in [1:4] do
    builds := builds.push (← read (base/s!"parallel-encoder-build{index}.guard.json"))
  write (study/"builds.json") (toJson builds)
  IO.FS.writeFile (study/"build1-failure.txt") (← IO.FS.readFile (base/"parallel-encoder-build1.stderr"))
  IO.FS.writeFile (study/"build2-failure.txt") (← IO.FS.readFile (base/"parallel-encoder-build2.stderr"))
  IO.FS.writeFile (study/"controls-stderr.txt") (← IO.FS.readFile (base/"parallel-encoder-controls1.stderr"))
def prepareAuditor : IO Unit := do
  drained
  check ((← read (study/"controls.json")).getObjValD "runtimeSha256" == toJson (← hash (target/"StudyMain")))
    "actual model controls must bind this candidate"
  command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/RealSourceStudy.lean").toString,"prepare-auditor",target.toString,
    auditorSource.toString,auditor.toString,(base/"parallel-encoder-auditor-settings.json").toString]
  let sha ← hash (target/"StudyMain")
  write (base/"parallel-encoder-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (target/"StudyMain").toString),("sha256",toJson sha)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let original := base/"real-source-search-read-input.json"
  let root := base/"parallel-encoder-cells-result"
  let mut probes := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      probes := probes.push (Json.mkObj [
        ("originalInput",Json.mkObj [("path",toJson original.toString),("sha256",toJson (← hash original))]),
        ("runtime",Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson sha)]),
        ("pluginRoot",toJson (installation/"share/eggshell/codex-plugin").toString),
        ("topic",toJson topic),("destination",toJson (root/s!"topic-{topic}-chat-{repetition}").toString),
        ("captureReply",toJson false)])
  write (base/"parallel-encoder-cells.json") (Json.mkObj [("output",toJson root.toString),("probes",toJson probes)])
def sealAuditor : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit,"inspect",auditor.toString,
    (study/"auditor-closure.json").toString]
  command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit,"common-sources",target.toString,auditor.toString,
    (study/"auditor-sources.json").toString]
def setup (action tag : String) : IO Unit := do
  drained
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh guard identity required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"parallel-encoder-settings.json").toString]
    | "auditor" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"parallel-encoder-auditor-settings.json").toString]
    | "install" => pure #[(auditor/"StudyMain").toString,"install-prefix",(base/"parallel-encoder-install.json").toString]
    | "cells" => do
      let bound ← read (study/"auditor-sources.json")
      check (bound.getObjValD "commonSourcesUnchanged" == toJson true &&
        bound.getObjValD "allProductCorePresent" == toJson true &&
        bound.getObjValD "productSha256" == toJson (← hash (target/"StudyMain")) &&
        bound.getObjValD "auditorSha256" == toJson (← hash (auditor/"StudyMain"))) "candidate auditor is not coherent"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(auditor/"StudyMain").toString,"cells",(base/"parallel-encoder-cells.json").toString]
    | "controls" => do
      check ((← read (study/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
        "seal the compiled numerical source first"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/"parallel-encoder-controls-data").toString,
        "EGGSHELL_PREFIX="++(base/"local-batch-prefix").toString,
        "EGGSHELL_TRACE_NUMERICAL_STAGES=1",(target/"StudyMain").toString,
        "parallel-encoder-check",(base/(tag++"-result")).toString]
    | _ => throw (IO.userError "unsupported action")
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["refresh"] => refresh
  | ["seal"] => sealRuntime
  | ["freeze"] => freezeSource
  | ["collect-controls"] => collectControls
  | ["prepare-auditor"] => prepareAuditor
  | ["seal-auditor"] => sealAuditor
  | ["setup",action,tag] => setup action tag
  | _ => throw (IO.userError "prepare|setup build tag")
end Eggshell.Research.ParallelEncoderStudy
def main := Eggshell.Research.ParallelEncoderStudy.main
