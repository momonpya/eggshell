import tools.research.ArtifactHash
import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser

open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def digest (path : System.FilePath) : IO String := Eggshell.Research.ArtifactHash.hex path
private partial def removeTree (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do removeTree entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let target := project / "docs/candidates/read-catalog"
  let replay ← read (root / "seed-2-ack-projection.json")
  check (replay.getObjValD "exactReferenceFactsAndStatus" == toJson true &&
    replay.getObjValD "inputUnchanged" == toJson true) "complete replay comparison is required"
  let checks ← read (root / "read-catalog-native/results.json")
  check (checks.getObjValD "concurrentCompilations" == toJson (1 : Nat) &&
    checks.getObjValD "unrelatedPublicationOldCompilations" == toJson (0 : Nat)) "native checks are incomplete"
  let mut guards := #[]
  for name in ["read-catalog-compile9","seed-2-ack-projection","read-catalog-checks-compile2","read-catalog-checks"] do
    let guard ← read (root / (name ++ ".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "native process not successfully terminal"
    guards := guards.push guard
  let preservedBindings ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs?
    (Array (String × String)) "verifiedOriginalFilesAndRuntimes")
  for (path,sha) in preservedBindings do check ((← digest (.mk path)) == sha) "protected original changed"
  let negative ← read (root / "seed-2-read-catalog.guard.json")
  check (negative.getObjValD "exitCode" == toJson (143 : Nat)) "keep the stopped negative attempt"
  let sample := root / "read-catalog-replay.sample"
  let sampleSha ← digest sample
  let stacks := ((← IO.FS.readFile sample).splitOn "\n").filter (fun line =>
    (line.splitOn "l_Eggshell_Synapses_ReadCatalog_compile").length > 1 ||
    (line.splitOn "l_Eggshell_Synapses_ReadCatalog_getLocked").length > 1 ||
    (line.splitOn "l_Eggshell_Synapses_Journal_storedReadsAt").length > 1) |>.take 8
  let write := fun (name : String) (value : Json) => do
    let path := target / name
    if ← path.pathExists then
      check ((← read path) == value) "previous evidence differs"
    else IO.FS.writeFile path value.pretty
  write "replay.json" replay
  write "checks.json" checks
  write "resources.json" (toJson guards)
  write "negative-attempt.json" (Json.mkObj [
    ("guard",negative),("runtimeSha256",toJson "930667e5a52a6c5af16dc5b6c8f664ca80f9fb25394bf39f74cae556128b585f"),
    ("readCatalogSourceSha256",toJson "6a905d0e3b081700cdc78802e85f3e5402189e9431357798493940826cc78502"),
    ("completedReferenceComparison",toJson false),("stoppedForRegression",toJson true),
    ("sampleSha256",toJson sampleSha),("selectedSampleLines",toJson stacks),
    ("sampleIsFullTimeBreakdown",toJson false),("adopted",toJson false)])
  write "negative-shared-projection.json" (Json.mkObj [
    ("result",← read (root / "seed-2-read-projection.json")),
    ("guard",← read (root / "seed-2-read-projection.guard.json")),
    ("runtimeSha256",toJson "4e706b6f42088acf9338ad74a021973e9778495e5f84e95c6fc09595e5a74fe4"),
    ("sourceSha256",toJson "b80b708fe3b78f648d477f7625bbe1effe46471706a9b59ae157905fbc7c08e2"),
    ("rejectedForLatencyRegression",toJson true),("adopted",toJson false)])
  let mut compilationGuards := #[]
  for name in ["read-catalog-compile","read-catalog-compile2","read-catalog-compile3","read-catalog-compile4",
      "read-catalog-compile5","read-catalog-compile6","read-catalog-compile7","read-catalog-compile8",
      "read-catalog-checks-compile"] do
    compilationGuards := compilationGuards.push (← read (root / (name ++ ".guard.json")))
  write "build-attempts.json" (toJson compilationGuards)
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/Eggshell/SynapseJournal.lean",
    "-L","b/Eggshell/SynapseJournal.lean",(root / "core/Eggshell/SynapseJournal.lean").toString,
    (root / "read-catalog-core/Eggshell/SynapseJournal.lean").toString]}
  check (patch.exitCode == 1) "expected one isolated journal overlay"
  IO.FS.writeFile (target / "journal.patch") patch.stdout
  check ((← digest (target / "ReadCatalog.lean")) == (← digest (root / "read-catalog-core/Eggshell/ReadCatalog.lean")))
    "review source differs from measured source"
  let manifest := Json.mkObj [
    ("replayRuntimeSha256",toJson (← digest (root / "read-catalog-build/StudyMain"))),
    ("checksRuntimeSha256",toJson (← digest (root / "read-catalog-checks-build/StudyMain"))),
    ("readCatalogSourceSha256",toJson (← digest (target / "ReadCatalog.lean"))),
    ("journalOverlaySha256",toJson (← digest (target / "journal.patch"))),
    ("verifiedOriginalFilesAndRuntimes",toJson preservedBindings),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),
    ("publicationServiceIntegrated",toJson false),("adopted",toJson false)]
  write "manifest.json" manifest
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0) "cannot inspect cleanup ownership"
  let mut deleted := #[]
  let mut bytes := 0
  for name in ["read-audit-build/StudyMain","storage-audit-build/StudyMain","replay-audit-build/StudyMain"] do
    let path := root / name
    if !(← path.pathExists) then continue
    check (!(processes.stdout.splitOn "\n").any (fun line => line.startsWith path.toString)) "ended helper is still live"
    let size := (← path.metadata).byteSize
    deleted := deleted.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson (← digest path)),("bytes",toJson size)])
    bytes := bytes+size
    IO.FS.removeFile path
  IO.FS.removeFile sample
  let secondSample := root / "read-projection-replay.sample"
  if ← secondSample.pathExists then
    write "second-sample.json" (Json.mkObj [("sha256",toJson (← digest secondSample)),
      ("sampleIsFullTimeBreakdown",toJson false)])
    IO.FS.removeFile secondSample
  check ((processes.stdout.splitOn (root / "read-catalog-checks-build/StudyMain").toString).length == 1) "native fixture still has a reader"
  removeTree (root / "read-catalog-native")
  for suffix in ["stdout","stderr"] do
    for name in ["read-catalog-compile","read-catalog-compile2","read-catalog-compile3","read-catalog-compile4",
        "read-catalog-compile5","read-catalog-compile6","read-catalog-compile7","read-catalog-compile8","read-catalog-compile9",
        "read-catalog-checks-compile","read-catalog-checks-compile2","read-catalog-checks","seed-2-read-catalog","seed-2-read-projection",
        "seed-2-ack-projection","read-catalog-sample","read-projection-sample"] do
      let path := root / (name ++ "." ++ suffix)
      if ← path.pathExists then IO.FS.removeFile path
  let progress := root / "seed-2-ack-projection.json.progress.json"
  if ← progress.pathExists then IO.FS.removeFile progress
  for (path,sha) in preservedBindings do check ((← digest (.mk path)) == sha) "cleanup changed protected original"
  write "cleanup.json" (Json.mkObj [("deletedExecutables",toJson deleted),("deletedExecutableBytes",toJson bytes),
    ("earlyExecutableCleanup",← read (root / "read-audit-executable-cleanup.json")),
    ("endedNativeFixtureRemoved",toJson true),("fullCpuSampleAndEndedLogsRemoved",toJson true),
    ("nativeObjectsAndInterfacesPreserved",toJson true),("protectedOriginalsUnchanged",toJson true),
    ("archiveCreated",toJson false)])
  IO.println "Read-catalog evidence retained; ended helpers, test DB and full logs removed."
