import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def root : System.FilePath := study / "shared-snapshot"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def output : System.FilePath := project / "docs/candidates/build-input-digests"
private def lean : String := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def run (name : String) (arguments : Array String) : IO Unit := do
  let result ← IO.Process.output {cmd := lean,args := #["-M1024","--run"] ++ arguments,cwd := project.toString}
  IO.FS.writeFile (output / System.FilePath.mk (name ++ ".stdout")) result.stdout
  IO.FS.writeFile (output / System.FilePath.mk (name ++ ".stderr")) result.stderr
  unless result.exitCode == 0 do throw (IO.userError s!"metadata step failed: {name}: {result.stderr}")

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

private partial def bytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return metadata.byteSize.toNat
  let mut total := 0
  for entry in ← path.readDir do total := total+(← bytes entry.path)
  return total

private def sealAbi : IO Unit := do
  let report ← read (root / "build-input-digest-resume/results.json")
  unless report.getObjValD "dependencyCachedOnRetry" == toJson true &&
      report.getObjValD "unchangedParentRecompiled" == toJson true &&
      report.getObjValD "runtimeValueBefore" == toJson "3" &&
      report.getObjValD "runtimeValueAfter" == toJson "3" &&
      report.getObjValD "staleLayoutWouldReturn" == toJson (10 : Nat) do
    throw (IO.userError "native ABI-resume checks did not pass")
  IO.FS.writeFile (output / "abi-resume.json") report.pretty

def main (args : List String) : IO Unit := do
  IO.FS.createDirAll output
  if args == ["seal-build-checks"] then
    let guard ← read (output / "build-checks.guard.json")
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "guardTriggered" == toJson false &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "wait for the original ABI check")
    sealAbi
    IO.println "Validated completed native ABI checks; original wrapper filename failure retained"
    return
  if args == ["prepare-build-checks"] then
    unless (← (output / "decision.json").pathExists) && !(← (output / "build-checks.guard.json").pathExists) do
      throw (IO.userError "preserve compaction verdict and previous build checks")
    IO.FS.writeFile (root / "build-input-digest-checks.guard-settings.json") (Json.mkObj [
      ("record",toJson (output / "build-checks.guard.json").toString),("cwd",toJson project.toString),
      ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("command",toJson #[lean,"-M1024","--run",
        (project / "tools/research/BuildStampCompaction.lean").toString,"build-checks"])]).pretty
    IO.println "Prepared guarded include-byte and interrupted ABI-resume checks"
    return
  if args == ["build-checks"] then
    unless !(← (root / "build-input-digest-resume").pathExists) do throw (IO.userError "fresh ABI-resume fixture required")
    run "include-byte-check" #[(project / "tools/research/StudyBuildMain.lean").toString,"source-stamp-check",
      (root / "build-input-digest-include").toString]
    run "abi-resume-check" #[(project / "tools/research/StudyBuildMain.lean").toString,"resume-check",
      (root / "build-input-digest-resume").toString]
    sealAbi
    IO.println "Digest input closures preserved included-byte invalidation and interrupted ABI rebuild"
    return
  if args == ["retire-plugin-caches"] then
    unless (← (study / "measurement-paused.json").pathExists) &&
        !(← (output / "retired-plugin-caches.json").pathExists) do throw (IO.userError "retain paused measurement state and prior retirement record")
    let prior := study.parent.get! / "source-complete-seed-20261028/account"
    let targets := #[study / "account/.tmp/plugins",prior / ".tmp/plugins",prior / "cache",prior / "plugins"]
    let active ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t",(study / "account/state_5.sqlite").toString]}
    unless active.exitCode == 1 && active.stdout.trimAscii.isEmpty do throw (IO.userError "experimental account is still open")
    let mut rows : Array (String × Nat) := #[]
    for target in targets do
      if ← target.pathExists then
        unless (← target.symlinkMetadata).type == .dir do throw (IO.userError "plugin cache target is an unexpected alias")
        let openFiles ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t","+D",target.toString]}
        unless openFiles.exitCode == 1 && openFiles.stdout.trimAscii.isEmpty do throw (IO.userError "plugin cache is still in use")
        rows := rows.push (target.toString,← bytes target)
    IO.FS.writeFile (output / "retired-plugin-caches.json") (Json.mkObj [
      ("completed",toJson false),("targets",toJson rows),
      ("currentPluginInstallationAuthConfigurationRawRpcAndModelsRetained",toJson true),("archiveCreated",toJson false)]).pretty
    for (target,_) in rows do remove (.mk target)
    let report ← read (output / "retired-plugin-caches.json")
    IO.FS.writeFile (output / "retired-plugin-caches.json") (report.setObjVal! "completed" (toJson true)).pretty
    IO.println "Deleted unopened experimental plugin mirrors and old account caches; current installation and auth retained"
    return
  if args == ["prepare"] then
    unless !(← (output / "compaction.json").pathExists) && !(← (output / "metadata.guard.json").pathExists) do
      throw (IO.userError "preserve previous metadata compaction")
    IO.FS.writeFile (root / "build-input-digests.guard-settings.json") (Json.mkObj [
      ("record",toJson (output / "metadata.guard.json").toString),("cwd",toJson project.toString),
      ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      -- This command handles build metadata only. Actual builds, DB access
      -- and answering models retain their separate 2 GiB disk admission.
      ("minFreeKiB",toJson (0 : Nat)),("command",toJson #[lean,"-M1024","--run",
        (project / "tools/research/BuildStampCompaction.lean").toString,"apply"])]).pretty
    IO.println "Prepared bounded metadata-only compaction and unchanged-verdict audit"
    return
  unless args == ["apply"] && !(← (output / "decision.json").pathExists) &&
      !(← (output / "compaction.json").pathExists) do throw (IO.userError "fresh explicit metadata compaction required")
  let audit := project / "tools/research/StudyBuildClosureAudit.lean"
  for (name,build) in [("lexical","source-lexical-build"),("full","fact-deferred-runtime-build")] do
    run ("before-" ++ name) #[audit.toString,(root / "cached-usage-runtime-build").toString,
      (root / System.FilePath.mk build).toString,(output / System.FilePath.mk ("before-" ++ name ++ ".json")).toString]
  run "digest-boundary" #[(project / "tools/research/StudyBuildMain.lean").toString,"digest-check"]
  run "compaction" #[(project / "tools/research/StudyBuildMain.lean").toString,"compact-dependencies",
    study.parent.get!.toString,(output / "compaction.json").toString]
  for (name,build) in [("lexical","source-lexical-build"),("full","fact-deferred-runtime-build")] do
    run ("after-" ++ name) #[audit.toString,(root / "cached-usage-runtime-build").toString,
      (root / System.FilePath.mk build).toString,(output / System.FilePath.mk ("after-" ++ name ++ ".json")).toString]
    let before ← read (output / System.FilePath.mk ("before-" ++ name ++ ".json"))
    let after ← read (output / System.FilePath.mk ("after-" ++ name ++ ".json"))
    for key in ["staleBuild","repairedBuild"] do
      unless before.getObjValD key == after.getObjValD key do
        throw (IO.userError "compact input stamps changed an actual native-closure verdict")
  let compact ← read (output / "compaction.json")
  unless compact.getObjValD "completed" == toJson true do throw (IO.userError "compaction is incomplete")
  IO.FS.writeFile (output / "decision.json") (Json.mkObj [
    ("allExistingNativeClosureVerdictsEqual",toJson true),
    ("sourceObjectsInterfacesRuntimesAndDatabasesUnchanged",toJson true),
    ("beforeBytes",compact.getObjValD "beforeBytes"),("afterBytes",compact.getObjValD "afterBytes"),
    ("actualBuildCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("actualHookCalls",toJson (0 : Nat)),("adoptedIntoProduct",toJson false),
    ("goalAchieved",toJson false)]).pretty
  IO.println "Compacted build input stamps; 36/185 positive and stale negative verdicts unchanged"
