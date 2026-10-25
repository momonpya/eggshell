import Eggshell.Sha256
import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean Eggshell

private def check (b : Bool) (message : String) : IO Unit :=
  unless b do throw (IO.userError message)

private def command (binary : String) (arguments : Array String) : IO Unit := do
  let result ← IO.Process.output {cmd := binary,args := arguments}
  check (result.exitCode == 0) s!"fixture setup failed: {result.stderr}"

private def checkpoint (source target : System.FilePath) : IO Json := do
  let report := target.parent.get! / (target.fileName.get! ++ ".input-files.json")
  command "/Users/ovm/.codex/experiments/eggshell/lean-study-20261025/controller/StudyMain"
    #["runtime","checkpoint",source.toString,target.toString,report.toString]
  IO.ofExcept (Json.parse (← IO.FS.readFile report))

private def warm (root : System.FilePath) (runtime : String) (name : String) : IO Json := do
  let started ← IO.monoMsNow
  let installRoot := ((System.FilePath.mk runtime).parent.get!).parent.get!
  let result ← IO.Process.output {
    cmd := runtime,args := #["egg","warm","work"],
    cwd := some "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project",
    env := #[("EGGSHELL_PREFIX",some installRoot.toString),("EGGSHELL_CONFIG",some (root / "config.toml").toString),
      ("EGGSHELL_DATA_ROOT",some (root / "data").toString),("EGGSHELL_PROFILE",some "work"),
      ("HF_HUB_OFFLINE",some "1"),("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),
      ("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
      ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]}
  IO.FS.writeFile (root / (name ++ ".stdout")) result.stdout
  IO.FS.writeFile (root / (name ++ ".stderr")) result.stderr
  let record := Json.mkObj [("runtime",toJson runtime),("exitCode",toJson result.exitCode.toNat),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("stdoutSha256",toJson (Sha256.hex result.stdout.toUTF8)),
    ("result",(Json.parse result.stdout).toOption.getD .null),("stderr",toJson result.stderr)]
  IO.FS.writeFile (root / (name ++ ".json")) (record.pretty ++ "\n")
  return record

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "SnapshotWarmTrialMain NEW-DIRECTORY")
  let root := System.FilePath.mk output
  check (root.isAbsolute && !(← root.pathExists)) "new absolute trial directory required"
  IO.FS.createDir root
  let study := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/lean-study-20261025"
  let candidate := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/snapshot-refresh-20261025"
  let parent := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/canonical-delta-20261025"
  command "/bin/cp" #["-cR",(parent / "prefix").toString,(candidate / "prefix").toString]
  command "/bin/cp" #["-c",(candidate / "build/StudyMain").toString,(candidate / "prefix/libexec/eggshell").toString]
  let source := study / "study/seed-1/output.egg"
  let originalData := study / "study/seed-1/data"
  let identity := "598eaf74d652cc4a53c29329c001efa87595b9472daf93466d75975e11968fc6"
  let mut snapshots : Array Json := #[]
  let mut journals : Array Json := #[]
  for arm in #["current","candidate"] do
    let target := root / arm
    IO.FS.createDir target
    snapshots := snapshots.push (← checkpoint source (target / "work.egg"))
    let events := target / "data/read-cache" / identity / "synapses/events"
    IO.FS.createDirAll events.parent.get!
    journals := journals.push (← checkpoint (originalData / "read-cache" / identity / "synapses/events") events)
    let runtime := ((if arm == "current" then parent else candidate) / "prefix/libexec/eggshell").toString
    IO.FS.writeFile (target / "config.toml") ("default = \"work\"\nsemantic_matcher = " ++
      (toJson #[runtime,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
      (toJson (target / "work.egg").toString).compress ++
      "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  check (snapshots[0]! == snapshots[1]! && journals[0]! == journals[1]!) "unmatched source or native event inputs"
  let old ← warm (root / "current") (parent / "prefix/libexec/eggshell").toString "first-warm"
  let first ← warm (root / "candidate") (candidate / "prefix/libexec/eggshell").toString "first-warm"
  let second ← warm (root / "candidate") (candidate / "prefix/libexec/eggshell").toString "repeat-warm"
  let audited ← IO.Process.output {
    cmd := (study / "recovery-controller/StudyMain").toString,
    args := #["audit-copy",(root / "candidate").toString,(study / "study/seed-1").toString,
      (root / "candidate/source-audit.json").toString],
    env := #[("EGGSHELL_DATA_ROOT",some (root / "candidate/data").toString),("LEAN_NUM_THREADS",some "1")]}
  let report := Json.mkObj [("current",old),("candidate",first),("candidateRepeat",second),
    ("inputPublication",snapshots[0]!),("inputEvents",journals[0]!),
    ("matchedSourceAndEvents",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("sourceAuditExitCode",toJson audited.exitCode.toNat),("sourceAuditStderr",toJson audited.stderr),
    ("productionAdoption",toJson false),("tokenImprovementMeasured",toJson false)]
  IO.FS.writeFile (root / "result.json") (report.pretty ++ "\n")
  check ((old.getObjValAs? Nat "exitCode").toOption == some 1 &&
    (old.getObjValAs? String "stderr").toOption.any (·.contains "source changed before window-owner preparation"))
    "current runtime did not reproduce the fixed failure"
  check ((first.getObjValAs? Nat "exitCode").toOption == some 0 &&
    (second.getObjValAs? Nat "exitCode").toOption == some 0) "candidate warm failed"
  check (audited.exitCode == 0) "candidate lost source facts or native provenance"
