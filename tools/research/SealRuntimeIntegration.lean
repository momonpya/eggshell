import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def finished (path : System.FilePath) : IO Unit := do
  let guard ← read path
  unless guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "error" == Json.null &&
      guard.getObjValD "guardTriggered" == toJson false &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "exclusive execution has not finished successfully")

private def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum", args := #["-a", "256", path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "artifact digest failed")
  pure (result.stdout.splitOn " ").head!

private partial def size (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return metadata.byteSize.toNat
  let mut total := 0
  for entry in ← path.readDir do total := total + (← size entry.path)
  return total

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def main (args : List String) : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/runtime-integration"
  let trial := root / "maintenance-prepared-hook"
  if args == ["retire"] then
    unless (← (output / "decision.json").pathExists) && !(← (output / "retired.json").pathExists) do
      throw (IO.userError "seal delivery evidence before retiring its DB and caches")
    finished (output / "hook.guard.json")
    let targets := #[trial, root / "maintenance-hook-build/StudyMain", root / "prefix"]
    let processes ← IO.Process.output {cmd := "/bin/ps", args := #["-axo", "command="]}
    unless processes.exitCode == 0 && targets.all (fun path =>
        (processes.stdout.splitOn path.toString).length == 1) do
      throw (IO.userError "trial still has a live process")
    let originalModel := study / "prefix/share/eggshell/minilm"
    let modelLink := root / "prefix/share/eggshell/minilm"
    unless (← originalModel.pathExists) && (← modelLink.symlinkMetadata).type == .symlink &&
        (← IO.FS.realPath modelLink) == (← IO.FS.realPath originalModel) do
      throw (IO.userError "preserve the original numerical model")
    let mut rows := #[]
    for path in targets do
      if ← path.pathExists then rows := rows.push (path.toString, ← size path)
    let report := Json.mkObj [("targets", toJson rows),
      ("logicalBytes", toJson (rows.foldl (fun total row => total + row.2) 0)),
      ("archiveCreated", toJson false), ("originalSeedModelAndCheckedReferenceRetained", toJson true),
      ("candidateRuntimeNativeObjectsAndInterfacesRetained", toJson true)]
    IO.FS.writeFile (output / "retired.json") (report.setObjVal! "completed" (toJson false)).pretty
    for path in targets do if ← path.pathExists then remove path
    unless ← originalModel.pathExists do throw (IO.userError "original model was lost")
    IO.FS.writeFile (output / "retired.json") (report.setObjVal! "completed" (toJson true)).pretty
    IO.println "Deleted ended trial DB, caches, helper executable and temporary install; no archive"
    return
  unless args.isEmpty && !(← (output / "decision.json").pathExists) do
    throw (IO.userError "preserve prior runtime integration evidence")
  finished (output / "hook.guard.json")
  finished (output / "native-closure.guard.json")
  for label in ["maintenance-runtime", "maintenance-hook"] do
    let settings ← read (root / System.FilePath.mk (label ++ "-build.guard-settings.json"))
    let path ← IO.ofExcept (settings.getObjValAs? String "record")
    finished (.mk path)
    IO.FS.writeFile (output / System.FilePath.mk (label ++ "-build.guard.json")) (← IO.FS.readFile (.mk path))
  let closure ← read (output / "native-closure.json")
  unless (closure.getObjValD "repairedBuild").getObjValD "consistent" == toJson true &&
      (closure.getObjValD "staleBuild").getObjValD "consistent" == toJson false do
    throw (IO.userError "native closure audit is not a positive and negative check")
  let timing ← read (trial / "UserPromptSubmit/record.json")
  let elapsed ← IO.ofExcept (timing.getObjValAs? Nat "elapsedMs")
  unless timing.getObjValD "exitCode" == toJson (0 : Nat) && elapsed < 30000 do
    throw (IO.userError "actual prompt hook did not complete within thirty seconds")
  let mandatory ← read (trial / "mandatory-audit.json")
  unless mandatory.getObjValD "availableEvidence" == (← read (trial / "available-before-delivery.json")) do
    throw (IO.userError "available obligations changed after delivery")
  let runtimeHash ← digest (root / "maintenance-runtime-build/StudyMain")
  unless (← digest (root / "prefix/libexec/eggshell")) == runtimeHash do
    throw (IO.userError "executed install differs from the audited runtime")
  let body ← IO.FS.readFile (trial / "body.txt")
  let bodyEqual := body == (← IO.FS.readFile (project / "docs/candidates/source-knowledge/body.txt"))
  for (origin, target) in [
      ("body.txt", "body.txt"), ("history-input.json", "history-input.json"),
      ("available-before-delivery.json", "available-before-delivery.json"),
      ("cache-lifecycle.json", "cache-lifecycle.json"),
      ("supplement-publication.json", "supplement-publication.json"),
      ("usage-preparation.json", "usage-preparation.json"),
      ("mandatory-audit.json", "mandatory-audit.json"), ("audit.json", "audit.json"),
      ("warm/record.json", "warm.record.json"), ("warm/stdout", "warm.stdout"),
      ("SessionStart/record.json", "session-start.record.json"),
      ("UserPromptSubmit/record.json", "hook.record.json"),
      ("UserPromptSubmit/stdout", "hook.stdout"),
      ("shutdown.json", "shutdown.json"), ("publisher-shutdown.json", "publisher-shutdown.json")] do
    let destination := output / System.FilePath.mk target
    unless !(← destination.pathExists) do throw (IO.userError "preserve previous copied artifact")
    IO.FS.writeFile destination (← IO.FS.readFile (trial / System.FilePath.mk origin))
  IO.FS.writeFile (output / "decision.json") (Json.mkObj [
    ("adopted", toJson false), ("runtimeSha256", toJson runtimeHash),
    ("bodySha256", toJson (← digest (trial / "body.txt"))),
    ("bodyBytesEqualCheckedReference", toJson bodyEqual),
    ("availableDelivery", mandatory.getObjValD "availableDelivery"),
    ("hookElapsedMs", toJson elapsed), ("actualPromptSubmitHooks", toJson (1 : Nat)),
    ("actualSessionStartHooks", toJson (1 : Nat)), ("answeringModelCalls", toJson (0 : Nat)),
    ("tokenImprovementMeasured", toJson false), ("qualityComparisonMeasured", toJson false),
    ("eightyUserSustainedLoadMeasured", toJson false), ("goalAchieved", toJson false),
    ("components", toJson #["trace-cache", "maintenance-delta"])]).pretty
  IO.println "Sealed the actual fixed-snapshot hook, frozen obligations and audited candidate runtime"
