import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser

open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)
private def sha (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal final replay artifact"
  return (result.stdout.splitOn " ").head!
private partial def removeTree (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do removeTree entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let target := project / "docs/candidates/replay-cursor"
  let write := fun (name : String) (value : Json) => do
    let path := target / name
    if ← path.pathExists then check ((← read path) == value) "existing replay evidence differs"
    else IO.FS.writeFile path value.pretty
  let replay ← read (root / "seed-2-replay-cursor.json")
  check (replay.getObjValD "exactReferenceFactsAndStatus" == toJson true && replay.getObjValD "inputUnchanged" == toJson true)
    "complete exact native replay is required"
  let native ← read (root / "replay-preparation-native/results.json")
  check (native.getObjValD "nativeWorkerExit" == toJson (0 : Nat) && native.getObjValD "readyWarmJournalComplete" == toJson true)
    "normal native index worker did not pass"
  let worker ← read (root / "replay-worker-resume/results.json")
  check (worker.getObjValD "complete" == toJson true && worker.getObjValD "originalHeadsUnchanged" == toJson true)
    "actual acquisition did not finish through the native worker"
  let mut resources := #[]
  for name in ["seed-2-replay-cursor","replay-preparation-native","replay-worker-observed2"] do
    let guard ← read (root / (name ++ ".guard.json"))
    check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "native job is not terminal and successful"
    resources := resources.push guard
  write "replay.json" replay
  write "native.json" native
  write "worker.json" worker
  write "resources.json" (toJson resources)
  write "worker-input.json" (← read (root / "replay-worker-resume/input-heads.json"))
  write "negative-worker-attempts.json" (Json.mkObj [
    ("initialFailure",← read (root / "replay-worker-resume3.guard.json")),
    ("initialProgress",← read (root / "replay-worker-resume/failed-progress.json")),
    ("initialStderr",toJson (← IO.FS.readFile (root / "replay-worker-resume3.stderr"))),
    ("initialErrorResponseRetained",toJson false),
    ("initialFailureRootCauseEstablished",toJson false),
    ("capacityStop",← read (root / "replay-worker-observed.guard.json")),
    ("successfulRunReusedClone",toJson true),
    ("successfulElapsedIsControlledLatencyComparison",toJson false),
    ("adopted",toJson false)])
  let preserved : Array (String × String) ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,digest) in preserved do check ((← sha (.mk path)) == digest) "protected original changed"
  let mut patches := #[]
  for moduleName in ["SynapseJournal","StoredReadLookup","Warm","Worker"] do
    let name := "Eggshell/" ++ moduleName ++ ".lean"
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/" ++ name,"-L","b/" ++ name,
      (root / "read-catalog-core" / name).toString,(root / "read-preparation-core" / name).toString]}
    check (patch.exitCode == 1) "expected an exact isolated source overlay"
    let destination := target / (moduleName ++ ".patch")
    IO.FS.writeFile destination patch.stdout
    patches := patches.push (moduleName,← sha destination)
  check ((← sha (target / "ReplayPreparation.lean")) == (← sha (root / "read-preparation-core/Eggshell/ReplayPreparation.lean")))
    "reviewed private continuation differs from native source"
  write "manifest.json" (Json.mkObj [("cursorRuntimeSha256",toJson (← sha (root / "replay-cursor-build/StudyMain"))),
    ("integrationRuntimeSha256",toJson (← sha (root / "replay-preparation-checks-build/StudyMain"))),
    ("cursorKernelInputStampSha256",toJson (← sha (root / "replay-cursor-build/Eggshell_SynapseJournal.source"))),
    ("integrationKernelInputStampSha256",toJson (← sha (root / "replay-preparation-checks-build/Eggshell_SynapseJournal.source"))),
    ("patches",toJson patches),("verifiedOriginalFilesAndRuntimes",toJson preserved),
    ("normalPrivateWorkerIntegrated",toJson true),("sharedServiceIntegrated",toJson false),
    ("cursorCrashDurable",toJson false),("unrelatedPublicationReuseImplemented",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),("adopted",toJson false)])
  let fields := ["count","logicalBytes","protectedRealTargets","activeObjectInputs","beforeFreeSpace","afterFreeSpace",
    "objectsSourcesDatabasesAndSymlinksUnchanged","onlyUnlinkedObjectsWithoutLiveInterfaces","archiveCreated","completed"]
  for kind in ["interface","object"] do
    let receipt := root / ("replay-cursor-" ++ kind ++ "-cleanup.json")
    let cleanup ← read receipt
    write (kind ++ "-cleanup.json") ((Json.mkObj (fields.filterMap fun name =>
      (cleanup.getObjVal? name).toOption.map (name,·))).setObjVal!
      "fullReceiptSha256" (toJson (← sha receipt)))
  write "capacity-cleanup.json" (← read (root / "replay-cursor-capacity-cleanup.json"))
  write "retired-runtime.json" (← read (root / "read-catalog-replay-executable-cleanup.json"))
  let mut builds := #[]
  for name in ["replay-cursor-compile","replay-cursor-compile2","replay-cursor-compile3",
      "replay-preparation-compile","replay-preparation-compile2","replay-preparation-compile3",
      "replay-preparation-compile4","replay-preparation-compile5","replay-worker-resume","replay-worker-resume2"] do
    builds := builds.push (← read (root / (name ++ ".guard.json")))
  write "build-attempts.json" (toJson builds)
  let live ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (live.exitCode == 0 && !(live.stdout.splitOn "\n").any (fun command =>
    command.startsWith (root / "replay-preparation-checks-build/StudyMain").toString)) "a native fixture is still active"
  removeTree (root / "replay-preparation-native")
  removeTree (root / "replay-worker-resume")
  let progress := root / "seed-2-replay-cursor.json.progress.json"
  if ← progress.pathExists then IO.FS.removeFile progress
  for suffix in ["stdout","stderr"] do
    for name in ["replay-cursor-compile","replay-cursor-compile2","replay-cursor-compile3","seed-2-replay-cursor",
      "replay-preparation-compile","replay-preparation-compile2","replay-preparation-compile3",
      "replay-preparation-compile4","replay-preparation-compile5","replay-preparation-native",
      "replay-worker-resume","replay-worker-resume2","replay-worker-resume3",
      "replay-worker-observed","replay-worker-observed2"] do
      let path := root / (name ++ "." ++ suffix)
      if ← path.pathExists then IO.FS.removeFile path
  let generator := project / "tools/research/PrepareReplayCursor.lean"
  if ← generator.pathExists then IO.FS.removeFile generator
  for kind in ["interface","object"] do
    IO.FS.removeFile (root / ("replay-cursor-" ++ kind ++ "-cleanup.json"))
  for (path,digest) in preserved do check ((← sha (.mk path)) == digest) "cleanup changed a protected original"
  write "cleanup.json" (Json.mkObj [("endedNativeFixturesRemoved",toJson true),("fullLogsAndOneOffGeneratorRemoved",toJson true),
    ("originalsUnchanged",toJson true),("archiveCreated",toJson false)])
  IO.println "Replay cursor, native worker, privacy boundary and cleanup evidence collected."
