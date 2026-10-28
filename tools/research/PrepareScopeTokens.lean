import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean

private def frozen := "/Users/ovm/.codex/experiments/eggshell/source-complete-seed-20261028"
private def candidate := "/Users/ovm/.codex/experiments/eggshell/bounded-source-replies-20261028/scope-hook-prefix"
private def study := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def controller := frozen ++ "/controller/StudyMain"
private def workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"

private def run (cmd : String) (args : Array String) (env : Array (String × Option String) := #[]) : IO String := do
  let result ← IO.Process.output {cmd,args,env,cwd := some workspace}
  unless result.exitCode == 0 do throw (IO.userError s!"{cmd}: {result.stderr}\n{result.stdout}")
  return result.stdout

private def save (name : String) (value : Json) : IO Unit := do
  let path := System.FilePath.mk study / name
  unless !(← path.pathExists) do throw (IO.userError "preserve previous measurement files")
  IO.FS.writeFile path (value.pretty ++ "\n")

private def environment : Array (String × Option String) := #[
  ("CODEX_HOME",some (study ++ "/account")),("TMPDIR",some (study ++ "/tmp")),
  ("EGGSHELL_PREFIX",some (study ++ "/prefix")),("PLUGIN_ROOT",some (study ++ "/prefix/plugins/eggshell")),
  ("HF_HUB_OFFLINE",some "1"),("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),
  ("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
  ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]

private def setupRoot (root : System.FilePath) : IO Unit := do
  IO.FS.createDirAll (root / "account")
  IO.FS.createDirAll (root / "tmp")
  IO.FS.createDirAll (root / "controller")
  let _ ← run "/bin/chmod" #["700",(root / "account").toString]
  let _ ← run "/bin/cp" #["-cR",candidate,(root / "prefix").toString]
  let _ ← run "/bin/cp" #["-cR",frozen ++ "/prompts",(root / "prompts").toString]
  let _ ← run "/bin/cp" #[frozen ++ "/controller/build.json",(root / "controller/build.json").toString]
  let _ ← run "/bin/ln" #["-s",frozen ++ "/account/auth.json",(root / "account/auth.json").toString]
  -- Hook trust is reacquired for the exact newly installed native plugin.
  let original ← IO.FS.readFile (System.FilePath.mk frozen / "account/config.toml")
  let mut lines := #[]
  let mut skip := false
  for line in original.splitOn "\n" do
    if line.startsWith "[" then skip := line.startsWith "[hooks.state."
    unless skip do lines := lines.push line
  IO.FS.writeFile (root / "account/config.toml") ((String.intercalate "\n" lines.toList).replace frozen study)
  -- The provider source is emitted by the frozen executable; large model files stay shared.
  let support := root / "prefix/share/eggshell/minilm"
  for name in #["embedding.py","fastembed-0.8.0.model-ready"] do
    IO.FS.removeFile (support / name)
  let _ ← run "/bin/ln" #["-s","/Users/ovm/.codex/experiments/eggshell/numerical-owned-20261024/prefix/share/eggshell/minilm/fastembed-0.8.0.model-ready",(support / "fastembed-0.8.0.model-ready").toString]
  pure ()

def main : IO Unit := do
  let root := System.FilePath.mk study
  if !(← root.pathExists) then setupRoot root
  -- Retry only metadata setup before any gate, database or charged call exists.
  for name in #["install.json","native-gate","study","seed-1.plan.json"] do
    unless !(← (root / name).pathExists) do throw (IO.userError "preserve initialized study")
  let installed ← run (study ++ "/prefix/libexec/eggshell") #["install","codex"] environment
  save "install.json" (Json.mkObj [("result",toJson installed),("answeringModelCalls",toJson (0 : Nat))])
  save "discovery.settings.json" (Json.mkObj [
    ("command",toJson #["/Users/ovm/.nodebrew/current/bin/codex","--strict-config","-c","features.remote_plugin=false","app-server","--listen","stdio://"]),
    ("cwd",toJson workspace),("environment",toJson environment),("output",toJson (study ++ "/discovery")),
    ("timeoutMs",toJson (60000 : Nat)),("responseBytes",toJson (33554432 : Nat)),
    ("transcriptBytes",toJson (268435456 : Nat))])
  let _ ← run controller #["probe",study ++ "/discovery.settings.json"] environment
  let _ ← run controller #["bootstrap","trust-hooks",study] environment
  let _ ← run controller #["bootstrap","seed-input",study] environment
  save "native-gate.settings.json" (Json.mkObj [
    ("cwd",toJson workspace),("ownedPrefixes",toJson #[study]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (study ++ "/native-gate.guard.json")),
    ("command",toJson #[controller,"seed-checks-generic",study ++ "/native-gate-input.json",study ++ "/native-gate"])])
  save "measurement-contract.json" (Json.mkObj [
    ("candidateSha256",toJson "b86fb5240f0a381c05a842b3bb81284ddc9cc30b5baf787b0a633b3efc220207"),
    ("model",toJson "gpt-5.6-luna"),("effort",toJson "xhigh"),
    ("stages",toJson #[1,2,3,4,5,6]),("repetitions",toJson (2 : Nat)),
    ("freshControl",toJson "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/fresh-baseline-reuse.json"),
    ("freshIsHistorical",toJson true),("sameGenerationHarness",toJson false),
    ("causalAdoptionComparison",toJson false),("inclusiveAccounting",toJson true),
    ("seedTokensSeparate",toJson true),("selectionRule",toJson "all r0 and r1 cells, including failures")])
  IO.println study
