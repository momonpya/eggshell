import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace EncodeBatchStudy
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := project/"docs/candidates/encode-batch"
def source := base/"encode-batch-source"
def build := base/"encode-batch-build"
def check (b : Bool) (s : String) : IO Unit := unless b do throw (IO.userError s)
def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= (IO.ofExcept ∘ Json.parse)
def write (p : System.FilePath) (v : Json) : IO Unit := IO.FS.writeFile p v.compress
def command (cmd : String) (args : Array String) : IO String := do
  let r ← IO.Process.output {cmd,args,cwd := some project}
  check (r.exitCode == 0) (r.stdout++r.stderr)
  return r.stdout
def hash (p : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",p.toString]).splitOn " ").headD ""
def idle : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any (fun row => row.trimAscii.toString.startsWith ((base/"controller/StudyMain").toString++" guard "))))
    "a resource guard is still live"
def prepare : IO Unit := do
  idle
  check (!(← source.pathExists) && !(← build.pathExists) && !(← folder.pathExists)) "fresh diagnostic required"
  check ((← hash (base/"draft-units-runtime-build/StudyMain")) ==
    "a42f084e4d17ddb3d7ddd36d3bc0db144b2f753850e5ac0157eabc14151700d3") "sealed parent changed"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"draft-units-runtime-build").toString,source.toString,build.toString,
    "tools.research.EncodeBatchProbe",(base/"encode-batch-settings.json").toString]
  for name in ["EncodeBatchLayout","EncodeBatchProbe"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  IO.FS.createDirAll folder
  write (folder/"plan.json") (Json.mkObj [("diagnosticOnly",toJson true),("adopted",toJson false),
    ("purpose",toJson "test numerical invariance before implementing cross-request microbatch admission"),
    ("fixedInputs",toJson "existing seventeen complete multilingual/long-text shared-model requests"),
    ("reference",toJson "all seventeen original boundaries must match existing reference SHA before batching"),
    ("layouts",toJson (#[2,4,8,16] : Array Nat)),("repetitions",toJson (1 : Nat)),
    ("scope",toJson "pure numerical input concatenation only; no persistence, project cache or authority change"),
    ("guardRssKiB",toJson (3670016 : Nat)),("guardMinFreeKiB",toJson (2097152 : Nat)),
    ("modelProcesses",toJson (1 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
def setup (mode tag : String) : IO Unit := do
  idle
  check (tag.startsWith "encode-batch-") "diagnostic tag escaped scope"
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "preserve diagnostic attempt"
  let args ← match mode with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (project/"tools/research/StudyBuildMain.lean").toString,(base/"encode-batch-settings.json").toString]
    | "run" => do
        check ((← read (folder/"native-closure.json")).getObjValD "consistent" == toJson true) "seal native closure first"
        pure #["/usr/bin/env","LEAN_NUM_THREADS=1","HF_HUB_OFFLINE=1","OMP_NUM_THREADS=1",
          "OPENBLAS_NUM_THREADS=1","MKL_NUM_THREADS=1","TOKENIZERS_PARALLELISM=false",
          (build/"StudyMain").toString,(base/(tag++"-result")).toString]
    | _ => throw (IO.userError "unknown diagnostic mode")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson project.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def sealNative : IO Unit := do
  idle
  if !(← (folder/"native-closure.json").pathExists) then
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",build.toString,
      (folder/"native-closure.json").toString]
  check ((← read (folder/"native-closure.json")).getObjValD "consistent" == toJson true) "native closure mismatch"
  let witnesses ← #["EncodeBatchLayout","EncodeBatchProbe"].mapM fun name => do
    let bytes ← IO.FS.readFile (build/("tools_research_"++name++".source"))
    let stamp ← IO.ofExcept (Json.parse bytes >>= Json.getArr?)
    check (stamp[0]? == some (toJson (← IO.FS.readFile (project/"tools/research"/(name++".lean")))))
      "numerical diagnostic source differs from native witness"
    pure (name,← hash (project/"tools/research"/(name++".lean")))
  let sameKernel := (← IO.FS.readFile (source/"runtime/shared_embedding.py")) ==
    (← IO.FS.readFile (base/"draft-units-source/runtime/shared_embedding.py"))
  write (folder/"native-sources.json") (Json.mkObj [("diagnosticOnly",toJson true),
    ("sources",toJson witnesses),("runtimeSha256",toJson (← hash (build/"StudyMain"))),
    ("kernelSourceSha256",toJson (← hash (source/"runtime/shared_embedding.py"))),
    ("kernelSameAsParent",toJson sameKernel)])
def collect (tag : String) : IO Unit := do
  idle
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "diagnostic owner still live"
  let report ← read (base/(tag++"-result")/"report.json")
  let stopped ← read (base/(tag++"-result")/"shutdown.json")
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && stopped.getObjValD "readerJoined" == toJson true)
    "numerical diagnostic failed or did not stop"
  write (folder/"numerical-layouts.json") (Json.mkObj [("guard",guard),("report",report),("shutdown",stopped)])
def collectBuild (tag : String) : IO Unit := do
  idle
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "build owner still live"
  write (folder/(tag++".json")) (Json.mkObj [("guard",guard),
    ("outputStreamedToTool",toJson true),
    ("failure",toJson (if tag == "encode-batch-build1" then "Lean rejected reserved identifier local before native link"
      else if tag == "encode-batch-build2" then "Lean rejected List(Array) flatten and unavailable Except.isError before native link"
      else ""))])
def refreshUnbuilt : IO Unit := do
  idle
  check (!(← (build/"StudyMain").pathExists) && !(← (folder/"native-sources.json").pathExists))
    "never mutate a verified diagnostic"
  for name in ["EncodeBatchLayout","EncodeBatchProbe"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
def proofs : IO Unit := do
  let result ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768","-DwarningAsError=true",(project/"tools/research/EncodeBatchLayout.lean").toString]
    cwd := some project}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  check (!result.stdout.contains "sorryAx") "batch layout used an unproved claim"
  write (folder/"proofs.json") (Json.mkObj [("passed",toJson true),("output",toJson result.stdout),
    ("layoutSha256",toJson (← hash (project/"tools/research/EncodeBatchLayout.lean")))])
partial def removeTree (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut result := (0,0)
    for entry in ← path.readDir do
      let (files,bytes) ← removeTree entry.path
      result := (result.1+files,result.2+bytes)
    IO.FS.removeDir path
    return result
  check (metadata.type == .file || metadata.type == .symlink) "diagnostic contains a special file"
  IO.FS.removeFile path
  return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)
def retire : IO Unit := do
  idle
  let stopped := (← read (folder/"numerical-layouts.json")).getObjValD "shutdown"
  check (stopped.getObjValD "readerJoined" == toJson true)
    "collect the stopped diagnostic first"
  check (!(← (folder/"retired.json").pathExists)) "diagnostic already retired"
  for owner in ["draft-units-runtime-build","draft-units-auditor-build","deferred-audit-build"] do
    let response ← IO.FS.readFile (base/owner/"runtime.rsp")
    check (!response.contains build.toString && !response.contains source.toString) "diagnostic still supplies current native inputs"
  let paths := #[source,build,base/"encode-batch-numeric1-result"]
  let current := base/"draft-units-runtime-build/StudyMain"
  let parentDigest ← hash current
  let mut result := (0,0)
  for path in paths do
    let removed ← removeTree path
    result := (result.1+removed.1,result.2+removed.2)
  for entry in ← base.readDir do
    if entry.fileName.startsWith "encode-batch-" &&
        [".guard.json",".guard-settings.json",".stdout",".stderr"].any (entry.fileName.endsWith ·) then
      IO.FS.removeFile entry.path
  check ((← hash current) == parentDigest) "current runtime changed during diagnostic retirement"
  write (folder/"retired.json") (Json.mkObj [("archived",toJson false),("removedFiles",toJson result.1),
    ("removedLogicalBytes",toJson result.2),("currentRuntimeSha256",toJson parentDigest),
    ("currentDbProjectCacheModelsAndNativeInputsRetained",toJson true)])
end EncodeBatchStudy
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => EncodeBatchStudy.prepare
  | ["setup",mode,tag] => EncodeBatchStudy.setup mode tag
  | ["seal"] => EncodeBatchStudy.sealNative
  | ["collect",tag] => EncodeBatchStudy.collect tag
  | ["collect-build",tag] => EncodeBatchStudy.collectBuild tag
  | ["refresh-unbuilt"] => EncodeBatchStudy.refreshUnbuilt
  | ["proofs"] => EncodeBatchStudy.proofs
  | ["retire"] => EncodeBatchStudy.retire
  | _ => throw (IO.userError "prepare/setup/seal/collect required")
