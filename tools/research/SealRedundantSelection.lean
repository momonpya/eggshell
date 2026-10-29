import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def finished (path : System.FilePath) : IO Unit := do
  let value ← read path
  unless value.getObjValD "state" == toJson "finished" && value.getObjValD "exitCode" == toJson (0 : Nat) &&
      value.getObjValD "guardTriggered" == toJson false && value.getObjValD "error" == Json.null &&
      value.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "exclusive execution is not finished successfully")

def main (args : List String) : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let output := project / "docs/candidates/zero-gain-cleanup"
  if args == ["closure"] then
    let settings ← read (root / "zero-gain-cleanup-closure-final.guard-settings.json")
    let record ← IO.ofExcept (settings.getObjValAs? String "record")
    finished (.mk record)
    let closure ← read (root / "zero-gain-cleanup-closure.json")
    unless (closure.getObjValD "repairedBuild").getObjValD "consistent" == toJson true &&
        (closure.getObjValD "staleBuild").getObjValD "consistent" == toJson false do
      throw (IO.userError "native audit did not check positive and negative inputs")
    unless !(← (output / "native-closure.json").pathExists) do throw (IO.userError "preserve previous closure audit")
    IO.FS.writeFile (output / "native-closure.json") closure.pretty
    IO.FS.writeFile (output / "native-closure.guard.json")
      (← IO.FS.readFile (.mk record))
    IO.FS.writeFile (output / "native-closure-limited.guard.json")
      (← IO.FS.readFile (root / "zero-gain-cleanup-closure-after-retirement.guard.json"))
    let decision ← read (output / "decision.json")
    IO.FS.writeFile (output / "decision.json") (decision.setObjVal! "nativeClosurePending" (toJson false)).pretty
    return
  unless args.isEmpty && !(← output.pathExists) do throw (IO.userError "preserve previous selection audit")
  finished (root / "zero-gain-cleanup-run.guard.json")
  let settings ← read (root / "zero-gain-cleanup-build.guard-settings.json")
  let guard ← IO.ofExcept (settings.getObjValAs? String "record")
  finished (.mk guard)
  let report ← read (root / "zero-gain-cleanup.json")
  unless report.getObjValD "freedAtoms" == toJson (#[] : Array Nat) &&
      report.getObjValD "beforeCost" == report.getObjValD "afterCost" &&
      report.getObjValD "newOffersAfterRefill" == toJson (#[] : Array Nat) do
    throw (IO.userError "negative stopping condition was not met")
  let source : String × Array (String × String) ← IO.ofExcept (fromJson? (← read
    (root / "zero-gain-cleanup-build/tools_research_RedundantSelectionAudit.source")))
  unless source.1 == (← IO.FS.readFile (project / "tools/research/RedundantSelectionAudit.lean")) do
    throw (IO.userError "diagnostic source changed after its native trial")
  let executable := root / "zero-gain-cleanup-build/StudyMain"
  let processes ← IO.Process.output {cmd := "/bin/ps", args := #["-axo", "command="]}
  unless processes.exitCode == 0 && (processes.stdout.splitOn executable.toString).length == 1 &&
      (← executable.symlinkMetadata).type == .file do throw (IO.userError "keep a live or linked executable")
  let digest ← IO.Process.output {cmd := "/usr/bin/shasum", args := #["-a", "256", executable.toString]}
  unless digest.exitCode == 0 do throw (IO.userError "executable digest failed")
  IO.FS.createDirAll output
  IO.FS.writeFile (output / "result.json") report.pretty
  IO.FS.writeFile (output / "run.guard.json") (← IO.FS.readFile (root / "zero-gain-cleanup-run.guard.json"))
  IO.FS.writeFile (output / "build.guard.json") (← IO.FS.readFile (.mk guard))
  IO.FS.writeFile (output / "decision.json") (Json.mkObj [("adopted", toJson false),
    ("hypothesis", toJson "redundant selected offers retain unneeded physical cost"),
    ("capacityRecovered", toJson false), ("nativeClosurePending", toJson true),
    ("productionChanged", toJson false), ("answeringModelCalls", toJson (0 : Nat)),
    ("actualHookCalls", toJson (0 : Nat)), ("goalAchieved", toJson false)]).pretty
  IO.FS.writeFile (output / "retired.json") (Json.mkObj [("path", toJson executable.toString),
    ("sha256", toJson (digest.stdout.splitOn " ").head!), ("bytes", toJson (← executable.symlinkMetadata).byteSize.toNat),
    ("databasesModelsSourcesObjectsAndInterfacesRetained", toJson true), ("archiveCreated", toJson false)]).pretty
  IO.FS.removeFile executable
  IO.println "Sealed zero-capacity result and deleted its ended executable; no DB or warm was created"
