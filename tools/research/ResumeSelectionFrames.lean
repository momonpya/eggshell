import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.StudyHistory
open Lean Eggshell Eggshell.Research
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot/selection-frames-trial/candidate"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/selection-witness/frames/hooks/candidate"
  check (!(← (records / "ready.json").pathExists) && !(← (records / "resume.json").pathExists)) "preserve completed preparation"
  let manifest := study / "r0/stage1/history/history.json"
  let (_,snapshot) ← StudyHistory.verify ⟨manifest.toString,← ArtifactHash.hex manifest⟩
  let database := root / "work.egg"
  check ((← StudyRuntime.files database) == snapshot.sourceFiles) "partial preparation changed its source"
  for family in snapshot.privateFamilies do
    check ((← StudyRuntime.files (root / "data/read-cache" / snapshot.database / "synapses" / family.name)) == family.files)
      "partial preparation changed private source history"
  let descriptor ← read (records.parent.get! / "candidate-runtime.json")
  let runtime : StudyRuntime.PublisherRuntime ← IO.ofExcept (descriptor.getObjValAs? _ "runtime")
  let binary := root / "prefix/libexec/eggshell"
  check ((← ArtifactHash.hex binary) == runtime.sha256 && runtime.generation == (← Plugin.Publication.generation))
    "resumed preparation changed its runtime"
  let env := #[("EGGSHELL_PREFIX",some (root / "prefix").toString),
    ("EGGSHELL_DATA_ROOT",some (root / "data").toString),("EGGSHELL_CONFIG",some (root / "prepare.toml").toString),
    ("EGGSHELL_PROFILE",some "work"),("TMPDIR",some (study / "tmp").toString),("LEAN_NUM_THREADS",some "1"),
    ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
    ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
  let publisher ← StudyRuntime.startPublisher binary (root / "data") env (recoverDead := true) (expectedRuntime := some runtime)
  try
    let warmed ← StudyCommand.run binary.toString #["egg","warm","work"] env
      "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project" "" (records / "resume-warm") 240000
    check (warmed.exitCode == 0) "resumed warm failed"
  finally StudyRuntime.stopManaged publisher (records / "resume-shutdown.json")
  check ((← StudyRuntime.files database) == snapshot.sourceFiles) "resumed warm changed its source"
  IO.FS.writeFile (records / "ready.json") (Json.mkObj [("sourceFiles",toJson snapshot.sourceFiles),
    ("arm",toJson "candidate"),("runtime",toJson runtime)]).pretty
  IO.FS.writeFile (records / "resume.json") (Json.mkObj [("reason",toJson "User resumed after explicit pause; continue derived warm only after validating original source and private families."),
    ("forkRepeated",toJson false),("changedSource",toJson false),("modelCalls",toJson (0 : Nat))]).pretty
