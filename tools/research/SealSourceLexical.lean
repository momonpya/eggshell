import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def root : System.FilePath := study / "shared-snapshot"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def output : System.FilePath := project / "docs/candidates/source-lexical"

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def finished (path : System.FilePath) : IO Unit := do
  let guard ← read path
  unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "error" == Json.null && guard.getObjValD "guardTriggered" == toJson false &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "wait for successful exclusive guard completion")

private def buildFinished (label : String) : IO Unit := do
  let settings ← read (root / System.FilePath.mk (label ++ "-build.guard-settings.json"))
  finished (.mk (← IO.ofExcept (settings.getObjValAs? String "record")))

private def objects (directory : System.FilePath) : IO (Array String) := do
  let mut values := #[]
  for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
    unless line.trimAscii.isEmpty do values := values.push (← IO.ofExcept (Json.parse line >>= Json.getStr?))
  return values

private def source? (paths : Array String) (name : String) : IO (Option (String × Array (String × String))) := do
  let some path := paths.find? (·.endsWith ("/Eggshell_" ++ name ++ ".o")) | return none
  some <$> IO.ofExcept (fromJson? (← read ((System.FilePath.mk path).withExtension "source")))

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

private partial def size (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return metadata.byteSize.toNat
  let mut bytes := 0
  for entry in ← path.readDir do bytes := bytes+(← size entry.path)
  return bytes

private partial def retiredSeedData (path : System.FilePath) : IO (Array System.FilePath) := do
  if !(← path.pathExists) || (← path.symlinkMetadata).type != .dir then return #[]
  let mut targets := #[]
  for entry in ← path.readDir do
    let kind := (← entry.path.symlinkMetadata).type
    if kind == .symlink then continue
    if entry.fileName.endsWith ".egg" ||
        (kind == .dir && ["data","private","recall-data","recovery-data"].contains entry.fileName) then
      targets := targets.push entry.path
    else if kind == .dir && !["account","models","lib","build",".git"].contains entry.fileName then
      targets := targets ++ (← retiredSeedData entry.path)
  return targets

def main (args : List String) : IO Unit := do
  IO.FS.createDirAll output
  if args == ["retire-earlier-seeds"] then
    unless !(← (output / "retired-earlier-seeds.json").pathExists) do throw (IO.userError "preserve earlier-seed retirement")
    let base := study.parent.get!
    let earlier := base / "bounded-source-replies-20261028"
    let prior := base / "source-complete-seed-20261028"
    let scopes := #[earlier / "origin-seed",earlier / "reference-hook-seed",earlier / "scope-hook-seed",
      prior / "study",prior / "seed-ready",prior / "native-gate"]
    let executables := #[earlier / "origin-prefix/libexec/eggshell",earlier / "reference-hook-prefix/libexec/eggshell",
      earlier / "scope-hook-prefix/libexec/eggshell",prior / "prefix/libexec/eggshell",prior / "controller/StudyMain"]
    let active ← read (study / "active-seed.json")
    unless active.getObjValD "acquisition" == toJson (study / "study/seed-2").toString &&
        (← (study / "study/seed-2/work.egg").pathExists) &&
        (← (root / "fact-deferred-runtime-build/StudyMain").pathExists) do throw (IO.userError "current seed/runtime not preserved")
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    unless processes.exitCode == 0 && (scopes ++ executables).all (fun target =>
        (processes.stdout.splitOn target.toString).length == 1) do throw (IO.userError "earlier experiment is still live")
    let currentRuntime ← IO.FS.realPath (study / "prefix/libexec/eggshell")
    unless !executables.contains currentRuntime do throw (IO.userError "current runtime aliases an earlier executable")
    for entry in ← (study / "prefix/share/eggshell/minilm").readDir do
      if (← entry.path.symlinkMetadata).type == .symlink then
        let actual ← IO.FS.realPath entry.path
        unless !actual.toString.startsWith (earlier.toString ++ "/") &&
            !actual.toString.startsWith (prior.toString ++ "/") do throw (IO.userError "current model still aliases an earlier experiment")
    let mut targets := #[]
    for scope in scopes do targets := targets ++ (← retiredSeedData scope)
    for target in executables do
      if ← target.pathExists then
        let kind ← IO.Process.output {cmd := "/usr/bin/file",args := #[target.toString]}
        unless kind.exitCode == 0 && (kind.stdout.splitOn "Mach-O").length == 2 do throw (IO.userError "old executable identity differs")
        targets := targets.push target
    let rows ← targets.mapM fun target => return (target.toString,← size target)
    let report := Json.mkObj [("targets",toJson rows),("archiveCreated",toJson false),
      ("logicalBytes",toJson (rows.foldl (fun total row => total+row.2) 0)),
      ("currentSeedRuntimeControllerAndModelsRetained",toJson true),
      ("rawRpcUsageReportsSourcesAndNativeDependencyTreesRetained",toJson true)]
    IO.FS.writeFile (output / "retired-earlier-seeds.json") (report.setObjVal! "completed" (toJson false)).pretty
    for target in targets do remove target
    IO.FS.writeFile (output / "retired-earlier-seeds.json") (report.setObjVal! "completed" (toJson true)).pretty
    IO.println "Deleted retired earlier seed DB/cache and standalone executables; current seed and models retained"
    return
  if args == ["capture-integration"] then
    unless !(← (output / "pending-integration.patch").pathExists) do throw (IO.userError "preserve integration capture")
    let parent ← objects (root / "fact-deferred-runtime-build")
    let mut patch := ""
    for name in ["Warm","Worker","FederatedSearch","ContractAudit"] do
      let file := root / "core/Eggshell" / System.FilePath.mk (name ++ ".lean")
      let current ← IO.FS.readFile file
      let prior ← match ← source? parent name with
        | some previous => pure previous.1
        | none =>
          unless name == "ContractAudit" do throw (IO.userError "integration parent source is unavailable")
          -- ContractAudit is not linked into Main. Reconstruct only the two
          -- exact dependency assertions edited in this isolated candidate.
          pure (current.replace
            "#[``Eggshell.SourceLexical.open?, ``Eggshell.LexicalAdvice.posting,"
            "#[``Eggshell.RetrievalResearch.Index.open?, ``Eggshell.LexicalAdvice.posting,"
            |>.replace "#[``Eggshell.SourceLexical.OwnerWitness.check?, ``Eggshell.SourceDelta.documents]"
              "#[``Eggshell.LexicalReads.OwnerWitness.check?, ``Eggshell.SourceDelta.documents]")
      let before := root / System.FilePath.mk ("source-lexical-pending-" ++ name ++ ".lean")
      IO.FS.writeFile before prior
      let difference ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/" ++ name ++ ".lean",
        "--label","b/Eggshell/" ++ name ++ ".lean",before.toString,file.toString]}
      unless difference.exitCode == 1 do throw (IO.userError "pending integration difference missing")
      patch := patch ++ difference.stdout
      IO.FS.removeFile before
    IO.FS.writeFile (output / "pending-integration.patch") patch
    let settings ← read (root / "source-lexical-integration-build.guard-settings.json")
    let guard ← read (.mk (← IO.ofExcept (settings.getObjValAs? String "record")))
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "reason" == toJson "disk-space" &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "integration stop is not confirmed terminal")
    IO.FS.writeFile (output / "integration-build.guard.json") guard.pretty
    IO.FS.writeFile (output / "integration-status.json") (Json.mkObj [
      ("compiledAndExecutedOrdinaryRuntime",toJson false),("stopReason",toJson "disk-space"),
      ("sourceLexicalFixtureVerifiedSeparately",toJson true),("adopted",toJson false),
      ("currentValidatedRuntimeRetained",toJson true),("contractAuditParentReconstructedFromExactEdits",toJson true)]).pretty
    IO.println "Captured pending ordinary integration separately from the tested lexical component"
    return
  if args == ["prepare-closure"] then
    buildFinished "source-lexical"
    unless !(← (output / "native-closure.json").pathExists) && !(← (output / "native-closure.guard.json").pathExists) do
      throw (IO.userError "preserve prior native closure evidence")
    IO.FS.writeFile (root / "source-lexical-closure.guard-settings.json") (Json.mkObj [
      ("record",toJson (output / "native-closure.guard.json").toString),("cwd",toJson project.toString),
      -- This command reads sealed JSON/object metadata and writes one small
      -- report. It starts no build, DB, provider or model. Their 2 GiB floor
      -- remains in their own settings and is not changed here.
      ("ownedPrefixes",toJson #[root.toString]),("minFreeKiB",toJson (0 : Nat)),("limitRssKiB",toJson (3670016 : Nat)),
      ("command",toJson #["/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
        (project / "tools/research/StudyBuildClosureAudit.lean").toString,(root / "cached-usage-runtime-build").toString,
        (root / "source-lexical-build").toString,(output / "native-closure.json").toString])]).pretty
    IO.println "Prepared actual linked-native dependency audit"
    return
  if args == ["retire-verified-copies"] then
    unless !(← (output / "retired-verified-copies.json").pathExists) do throw (IO.userError "preserve copy retirement record")
    let original := study / "r0/stage1/history/source.egg"
    let copies := #[study / "seed-ready/ready.egg",study / "initial-history/source.egg"]
    let executables := #[root / "pages-checks",study / "drain-controller-build/StudyMain"]
    let targets := copies ++ executables
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    unless processes.exitCode == 0 && targets.all (fun target =>
        (processes.stdout.splitOn target.toString).length == 1) && (← original.pathExists) &&
        (← (study / "controller-build/StudyMain").pathExists) &&
        (← (root / "fact-deferred-runtime-build/StudyMain").pathExists) do
      throw (IO.userError "preserve active runtime, controller and fixed source")
    let mut hashes : Array (String × String) := #[]
    for name in ["head","d6ff6dad444913158edfc86f2a3bd24212835619ec78e5d4da0e3afe1789a812.pages"] do
      let expected ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(original / name).toString]}
      unless expected.exitCode == 0 do throw (IO.userError "retained original digest failed")
      let value := (expected.stdout.splitOn " ").headD ""
      hashes := hashes.push (name,value)
      for target in copies do
        let actual ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(target / name).toString]}
        unless actual.exitCode == 0 && (actual.stdout.splitOn " ").headD "" == value do
          throw (IO.userError "retirement copy differs from the retained original bytes")
    for target in executables do
      let kind ← IO.Process.output {cmd := "/usr/bin/file",args := #[target.toString]}
      unless kind.exitCode == 0 && (kind.stdout.splitOn "Mach-O").length == 2 do
        throw (IO.userError "explicit ended executable differs")
    let rows ← targets.mapM fun target => return (target.toString,← size target)
    let report := Json.mkObj [("targets",toJson rows),("exactOriginalDigests",toJson hashes),
      ("retainedFixedSource",toJson original.toString),("logicalBytes",toJson (rows.foldl (fun n row => n+row.2) 0)),
      ("archiveCreated",toJson false),("activeSeedModelsCurrentRuntimeControllerAndNativeMetadataRetained",toJson true)]
    IO.FS.writeFile (output / "retired-verified-copies.json") (report.setObjVal! "completed" (toJson false)).pretty
    for target in targets do remove target
    IO.FS.writeFile (output / "retired-verified-copies.json") (report.setObjVal! "completed" (toJson true)).pretty
    IO.println "Deleted byte-identical unused DB copies and ended executables; no archive"
    return
  if args == ["retire-unused-experiments"] then
    unless !(← (output / "retired-unused-experiments.json").pathExists) do throw (IO.userError "preserve prior retirement record")
    let active ← read (study / "active-seed.json")
    unless active.getObjValD "acquisition" == toJson (study / "study/seed-2").toString &&
        (← (study / "study/seed-1/failure.json").pathExists) &&
        (← (study / "study/seed-1/usage.json").pathExists) &&
        (← (root / "fact-deferred-runtime-build/StudyMain").pathExists) do
      throw (IO.userError "active seed and retained failed-seed accounting are not established")
    let targets := #[study / "study/seed-1/data",study / "study/seed-1/input.egg",
      study / "study/seed-1/output.egg",study / "study/seed-1/work.egg",study / "study/seed-1/work.egg.guard",
      root / "dependency-checked-runtime-build/StudyMain",study / "shared-recipe-trial-build/StudyMain"]
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    unless processes.exitCode == 0 && targets.all (fun target =>
        (processes.stdout.splitOn target.toString).length == 1) do throw (IO.userError "retirement target still has a live process")
    let mut rows : Array (String × Nat) := #[]
    for target in targets do
      if ← target.pathExists then rows := rows.push (target.toString,← size target)
    let report := Json.mkObj [("targets",toJson rows),("archiveCreated",toJson false),
      ("logicalBytes",toJson (rows.foldl (fun total row => total+row.2) 0)),
      ("failedSeedUsageAndRawRpcRetained",toJson true),("activeSeedModelCurrentRuntimeAndNativeMetadataRetained",toJson true)]
    IO.FS.writeFile (output / "retired-unused-experiments.json") (report.setObjVal! "completed" (toJson false)).pretty
    for target in targets do if ← target.pathExists then remove target
    IO.FS.writeFile (output / "retired-unused-experiments.json") (report.setObjVal! "completed" (toJson true)).pretty
    IO.println "Deleted abandoned seed DB/cache and two superseded executables; retained usage, RPC and current seed"
    return
  if args == ["retire-old-runtimes"] then
    unless !(← (output / "retired-old-runtimes.json").pathExists) &&
        (← (root / "fact-deferred-runtime-build/StudyMain").pathExists) do
      throw (IO.userError "preserve the current checked runtime and previous retirement record")
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    unless processes.exitCode == 0 do throw (IO.userError "cannot inspect old runtime ownership")
    let targets := #[("consumed-feedback-runtime","55e764074995659970417ddfa9c52874ccd9e91219e355a20d49620421c4c33b"),
      ("maintenance-runtime","b876b4b68159225c299187348121bd0751b487b0ad1116d48f9a232e8d1fd443")]
    let mut rows : Array (String × Nat) := #[]
    for (label,expected) in targets do
      let target := root / System.FilePath.mk (label ++ "-build/StudyMain")
      unless (processes.stdout.splitOn target.toString).length == 1 &&
          (← (target.parent.get! / "runtime.rsp").pathExists) &&
          (← (target.parent.get! / "build.json").pathExists) do
        throw (IO.userError "old runtime is live or its native metadata is not retained")
      let checked ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",target.toString]}
      unless checked.exitCode == 0 && (checked.stdout.splitOn " ").headD "" == expected do
        throw (IO.userError "old runtime identity differs from the explicit retirement list")
      rows := rows.push (target.toString,(← target.metadata).byteSize.toNat)
    for (target,_) in rows do IO.FS.removeFile (.mk target)
    IO.FS.writeFile (output / "retired-old-runtimes.json") (Json.mkObj [
      ("completed",toJson true),("targets",toJson rows),("archiveCreated",toJson false),
      ("logicalBytes",toJson (rows.foldl (fun total row => total+row.2) 0)),
      ("originalSeedModelCurrentRuntimeAndNativeMetadataRetained",toJson true)]).pretty
    IO.println "Deleted two ended superseded runtimes; kept current runtime, original data and native dependency metadata"
    return
  if args == ["prepare-fixture"] then
    buildFinished "source-lexical"
    unless !(← (root / "source-lexical-fixture").pathExists) && !(← (output / "fixture.guard.json").pathExists) do
      throw (IO.userError "preserve prior fixture and guard")
    let settings := Json.mkObj [
      ("record",toJson (output / "fixture.guard.json").toString),
      ("cwd",toJson project.toString),("ownedPrefixes",toJson #[root.toString]),
      ("minFreeKiB",toJson (2097152 : Nat)),("limitRssKiB",toJson (3670016 : Nat)),
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT=" ++ (root / "source-lexical-fixture/private").toString,
        (root / "source-lexical-build/StudyMain").toString,(root / "source-lexical-fixture").toString])]
    IO.FS.writeFile (root / "source-lexical-fixture.guard-settings.json") settings.pretty
    IO.println "Prepared bounded model-free source lexical fixture"
    return
  if args == ["retire"] then
    finished (output / "fixture.guard.json")
    unless (← (output / "decision.json").pathExists) && !(← (output / "retired.json").pathExists) do
      throw (IO.userError "seal source lexical evidence before retiring its fixture")
    let targets := #[root / "source-lexical-fixture",root / "source-lexical-build/StudyMain"]
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    unless processes.exitCode == 0 && targets.all (fun target =>
        (processes.stdout.splitOn target.toString).length == 1) do throw (IO.userError "fixture still has a live process")
    for target in targets do if ← target.pathExists then remove target
    IO.FS.writeFile (output / "retired.json") (Json.mkObj [
      ("completed",toJson true),("targets",toJson (targets.map System.FilePath.toString)),
      ("archiveCreated",toJson false),("originalSeedModelsAndRuntimeRetained",toJson true),
      ("candidateSourcesObjectsAndInterfacesRetained",toJson true)]).pretty
    IO.println "Deleted ended lexical fixture DB, helper executable and caches; no archive"
    return
  unless args == ["seal"] && !(← (output / "decision.json").pathExists) do
    throw (IO.userError "SealSourceLexical prepare-fixture|seal|retire")
  finished (output / "fixture.guard.json")
  finished (output / "native-closure.guard.json")
  buildFinished "source-lexical"
  let report ← read (root / "source-lexical-fixture/result.json")
  for name in ["allFullOrdersEqualPlaintext","oldPinsUnchanged","retryIdempotent","abortedPublicationInvisible",
      "unknownAndWrongPolicyRejected","readsCreateNoCacheOrSourceWrite","projectsIsolated"] do
    unless report.getObjValD name == toJson true do throw (IO.userError "source lexical fixture did not preserve its contract")
  unless report.getObjValD "derivedLexicalWarmCalls" == toJson (0 : Nat) &&
      report.getObjValD "answeringModelCalls" == toJson (0 : Nat) do throw (IO.userError "fixture called a provider or derivative warm")
  let closure ← read (output / "native-closure.json")
  unless (closure.getObjValD "repairedBuild").getObjValD "consistent" == toJson true &&
      (closure.getObjValD "staleBuild").getObjValD "consistent" == toJson false do
    throw (IO.userError "native source dependency audit failed")
  let actual ← objects (root / "source-lexical-build")
  let parent ← objects (root / "fact-deferred-runtime-build")
  let mut patch := ""
  for name in ["SourceLexicalPolicy","SourceLexical","GraphStore","LexicalReads","LexicalAdvice"] do
    let source := root / "core/Eggshell" / System.FilePath.mk (name ++ ".lean")
    let some compiled ← source? actual name | throw (IO.userError "candidate was not actually linked")
    unless compiled.1 == (← IO.FS.readFile source) do throw (IO.userError "source changed after native audit")
    for (relative,bytes) in compiled.2 do
      unless (← IO.FS.readFile (source.parent.get! / System.FilePath.mk relative)) == bytes do
        throw (IO.userError "native included policy changed")
    let before := root / System.FilePath.mk ("source-lexical-parent-" ++ name ++ ".lean")
    let previous ← source? parent name
    IO.FS.writeFile before (previous.map Prod.fst |>.getD "")
    let difference ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/" ++ name ++ ".lean",
      "--label","b/Eggshell/" ++ name ++ ".lean",before.toString,source.toString]}
    unless difference.exitCode == 1 do throw (IO.userError "candidate difference missing")
    patch := patch ++ difference.stdout
    IO.FS.removeFile before
  IO.FS.writeFile (output / "candidate.patch") patch
  IO.FS.writeFile (output / "fixtures.json") report.pretty
  IO.FS.writeFile (output / "proofs-and-boundaries.stdout")
    (← IO.FS.readFile (root / "source-lexical-build/tools_research_SourceLexicalAudit-lean.stdout"))
  let mut guards := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "source-lexical-build-" && entry.fileName.endsWith ".guard.json" then
      guards := guards.push (← read entry.path)
  IO.FS.writeFile (output / "build-guards.json") (toJson guards).pretty
  IO.FS.writeFile (output / "decision.json") (Json.mkObj [
    ("adopted",toJson false),("publicationLexicalMatchesPlaintext",toJson true),
    ("newEvidenceAvailableWithoutDerivedWarm",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("actualHookCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),
    ("eightyUserSustainedLoadMeasured",toJson false),("synapseVectorTailHandled",toJson false),
    ("goalAchieved",toJson false)]).pretty
  IO.println "Sealed source-published lexical evidence; no product adoption"
