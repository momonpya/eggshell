import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def evidence := project / "docs/candidates/prepared-bindings"
private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def replace (text old updated : String) : IO String := do
  check ((text.splitOn old).length == 2) "exactly one unchanged prepared binding boundary required"
  return text.replace old updated

/-- The two-arm preparation writes temporary derived data before the hooks.
Reserve that space at startup; keep the continuous 2 GiB stop floor unchanged. -/
private def trialSpaceReport : IO Json := do
  let measured ← IO.Process.output {cmd := "/bin/df",args := #["-Pk",root.toString]}
  check (measured.exitCode == 0) "cannot inspect comparison storage"
  let some row := ((measured.stdout.splitOn "\n").filter (! ·.isEmpty)).getLast? |
    throw (IO.userError "comparison storage has no capacity row")
  let fields := (row.splitOn " ").filter (! ·.isEmpty)
  let some available := fields[3]?.bind String.toNat? |
    throw (IO.userError "comparison storage has no available KiB")
  return Json.mkObj [("directory",toJson root.toString),("availableKiB",toJson available),
    ("setupMinimumFreeKiB",toJson (3145728 : Nat)),("continuousMinFreeKiB",toJson (2097152 : Nat)),
    ("ready",toJson (decide (available ≥ 3145728))),("answeringModelCalls",toJson (0 : Nat))]

private def requireTrialSpace : IO Unit := do
  let report ← trialSpaceReport
  check (report.getObjValD "ready" == toJson true)
    ("paired preparation requires startup headroom; no build or DB preparation started: " ++ report.compress)

private def prepareBuild (core parent : System.FilePath) (label mainModule record : String) : IO Unit := do
  if label == "prepared-bindings-trial" || label.startsWith "source-prepare-" then requireTrialSpace
  let prior ← read (parent / "build.json")
  let settings := prior.getObjValD "settings"
  let mut objects ← IO.ofExcept ((← read (.mk (← IO.ofExcept (settings.getObjValAs? String "objectModules")))).getObj?)
  for entry in ← IO.ofExcept (prior.getObjValAs? (Array Json) "modules") do
    objects := objects.insert (← IO.ofExcept (entry.getObjValAs? String "object")) (entry.getObjValD "module")
  let map := root / (label ++ "-objects.json")
  IO.FS.writeFile map (Json.obj objects).pretty
  let plan := settings.setObjVal! "core" (toJson core.toString)
    |>.setObjVal! "project" (toJson project.toString)
    |>.setObjVal! "baselineCore" (toJson (root / "query-cache-baseline-core").toString)
    |>.setObjVal! "baselineResponse" (toJson (parent / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent / "Main.o").toString)
    |>.setObjVal! "objectModules" (toJson map.toString)
    |>.setObjVal! "mainModule" (toJson mainModule)
    |>.setObjVal! "output" (toJson (root / (label ++ "-build")).toString)
  IO.FS.writeFile (root / (label ++ "-build.settings.json")) plan.pretty
  IO.FS.writeFile (root / (label ++ "-build.guard-settings.json")) (Json.mkObj [
    ("record",toJson (evidence / record).toString),("cwd",toJson project.toString),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
      "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,(root / (label ++ "-build.settings.json")).toString])]).pretty

private def patch (path : System.FilePath) (edit : String → IO String) : IO Unit := do
  let before ← IO.FS.readFile path
  IO.FS.writeFile path (← edit before)

private def finished (name : String) : IO Unit := do
  let guard ← read (evidence / name)
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) && guard.getObjValD "guardTriggered" == toJson false)
    "finish the guarded native phase before using or deleting its output"

private def prepareRun (label guardFile : String) (arguments : Array String) (environment : Array String := #[]) : IO Unit := do
  if label == "prepared-bindings-trial" then requireTrialSpace
  let audited ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
    args := #["-M1024","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
      (root / "cached-usage-runtime-build").toString,(root / (label ++ "-build")).toString,
      (evidence / (label ++ "-native-closure.json")).toString]}
  check (audited.exitCode == 0) "prepared binding native inputs differ"
  let command := #["/usr/bin/env","LEAN_NUM_THREADS=1"] ++ environment ++
    #[(root / (label ++ "-build/StudyMain")).toString] ++ arguments
  IO.FS.writeFile (root / (label ++ ".guard-settings.json")) (Json.mkObj [
    ("record",toJson (evidence / guardFile).toString),("cwd",toJson project.toString),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("command",toJson command)]).pretty

private def refineDelta (core : System.FilePath) : IO Unit := do
  patch (core / "Eggshell/SynapseIndex.lean") fun text => do
    let text ← replace text "def prepareBinding (writer : PageMap.Writer) (fact : Fact) : IO Unit := do\n"
      "structure BindingChange where\n  source : Range\n  publication : Nat\n  deriving ToJson,FromJson\n\ndef bindingChangeName (source : Range) := \"binding-change:\" ++ contentKey source\n\n/-- A producer-owned point dependency, committed with the exact posting changes.\nThe counter is the existing transaction revision, not a format version. -/\ndef touchBinding (writer : PageMap.Writer) (source : Range) : IO Unit :=\n  writer.put (bindingChangeName source) (some ((toJson\n    (⟨source,writer.base.head.revision+1⟩ : BindingChange)).compress.toUTF8))\n\ndef bindingChange? (snapshot : PageMap.Snapshot) (source : Range) : IO (Option BindingChange) := do\n  let some bytes ← snapshot.get (bindingChangeName source) | return none\n  let change ← decode (α := BindingChange) bytes\n  unless change.source == source && 0 < change.publication && change.publication ≤ snapshot.head.revision do\n    throw (IO.userError \"prepared binding change differs from its exact range or publication\")\n  return some change\n\ndef prepareBinding (writer : PageMap.Writer) (fact : Fact) : IO Unit := do\n"
    let text ← replace text
      "    let _ ← putImmutable writer (bindingName read.source stored.fact) (← checkedBytes stored)\n"
      "    let inserted ← putImmutable writer (bindingName read.source stored.fact) (← checkedBytes stored)\n    if inserted || (← writer.get (bindingChangeName read.source)).isNone then touchBinding writer read.source\n"
    replace text "    writer.put (bindingName read.source (contentKey fact)) none\n"
      "    writer.put (bindingName read.source (contentKey fact)) none\n    touchBinding writer read.source\n"
  patch (core / "Eggshell/PublicationService.lean") fun text =>
    replace text "    let namespaceKey := (toJson (scope.scope,CanonicalSource.Shared.key path metadata)).compress\n"
      "    let namespaceKey := scope.scope\n"
  IO.FS.writeFile (core / "tools/PreparedBindingCache.lean") (← IO.FS.readFile (project / "tools/PreparedBindingCache.lean"))

private def savePatches (core : System.FilePath) : IO Unit := do
  let baseline := root / "query-cache-baseline-core"
  for name in ["SynapseIndex.lean","SynapticBindings.lean","CanonicalSourcePrepared.lean","PublicationService.lean","PublicationWire.lean"] do
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",(baseline / "Eggshell" / name).toString,(core / "Eggshell" / name).toString]}
    check (diff.exitCode == 1) "prepared binding candidate difference missing"
    IO.FS.writeFile (evidence / (name ++ ".patch")) diff.stdout

def main (args : List String) : IO Unit := do
  let core := root / "prepared-bindings-core"
  if args == ["check-trial-space"] then
    IO.println (← trialSpaceReport).pretty
    return
  if args == ["seal-storage-stop"] then
    let guard ← read (evidence / "storage-setup-stopped.guard.json")
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "reason" == toJson "disk-space" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      !(← (evidence / "trial/progress.json").pathExists)) "seal only the terminal pre-hook disk stop"
    let frozen ← IO.ofExcept ((← read (evidence / "trial/frozen-before-delivery.json")).getArr?)
    let some first := frozen[0]? | throw (IO.userError "frozen source specification missing")
    let specification := first.getObjValD "specification"
    let common ← IO.ofExcept (specification.getObjValAs? String "source")
    let files : Array (String × String) ← IO.ofExcept (specification.getObjValAs? _ "files")
    let mut sources := #[]
    for directory in #[System.FilePath.mk common,root / "prepared-bindings-trial/baseline/work.egg",
        root / "prepared-bindings-trial/candidate/work.egg"] do
      for (name,digest) in files do
        check (!name.contains '/' && name != "." && name != "..") "invalid frozen source file"
        let hashed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(directory / name).toString]}
        check (hashed.exitCode == 0 && (hashed.stdout.splitOn " ").headD "" == digest)
          "a guarded preparation changed original source bytes"
      sources := sources.push directory
    let baseline := evidence / "trial/baseline"
    let control ← read (project / "docs/candidates/service-block-cache/publisher-runtime-baseline.json")
    let prepared ← read (baseline / "prepared-source.json")
    let completed := (prepared.getObjValD "preparerGeneration" == control.getObjValD "generation") &&
      (← read (baseline / "prepare/record.json")).getObjValD "exitCode" == toJson (0 : Nat) &&
      (← read (baseline / "warm/record.json")).getObjValD "exitCode" == toJson (0 : Nat)
    IO.FS.writeFile (evidence / "storage-stop-audit.json") (Json.mkObj [
      ("originalSourcesUnchanged",toJson sources),("baselineOwnPreparationAndWarmCompleted",toJson completed),
      ("candidatePreparationCompleted",toJson false),("actualHookCalls",toJson (0 : Nat)),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
    let fixture := root / "prepared-bindings-trial"
    let binaries := #[root / "prepared-bindings-trial-build/StudyMain",root / "source-prepare-candidate-build/StudyMain"]
    for path in #[fixture] ++ binaries do
      let options := if (← path.symlinkMetadata).type == .dir then #["-t","+D",path.toString] else #["-t",path.toString]
      let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := options}
      check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "stopped experimental input remains open"
    IO.FS.removeDirAll fixture
    for binary in binaries do IO.FS.removeFile binary
    IO.FS.writeFile (evidence / "retired-storage-stop.json") (Json.mkObj [
      ("targets",toJson (#[fixture] ++ binaries)),("completed",toJson true),("archiveCreated",toJson false),
      ("originalSourcesModelsControlCandidateAndNativeInputsRetained",toJson true)]).pretty
    return
  if args == ["retire-mixed-preparation"] then
    let guard ← read (evidence / "trial.guard.json")
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (143 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      !(← (evidence / "trial/progress.json").pathExists)) "only the intentionally stopped pre-hook setup may be retired"
    let frozen ← IO.ofExcept ((← read (evidence / "trial/frozen-before-delivery.json")).getArr?)
    let some first := frozen[0]? | throw (IO.userError "frozen common source missing")
    let specification := first.getObjValD "specification"
    let common ← IO.ofExcept (specification.getObjValAs? String "source")
    let files : Array (String × String) ← IO.ofExcept (specification.getObjValAs? _ "files")
    for (name,digest) in files do
      check (!name.contains '/' && name != "." && name != "..") "invalid common source file name"
      let hashed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(System.FilePath.mk common / name).toString]}
      check (hashed.exitCode == 0 && (hashed.stdout.splitOn " ").headD "" == digest) "the common original source changed"
    let fixture := root / "prepared-bindings-trial"
    let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t","+D",fixture.toString]}
    check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "stopped mixed setup remains open"
    IO.FS.writeFile (evidence / "trial/PreparedOriginalKeysTrial.source")
      (← IO.FS.readFile (root / "prepared-bindings-trial-build/tools_research_PreparedOriginalKeysTrial.source"))
    IO.FS.rename (evidence / "trial") (evidence / "mixed-preparation-rejected")
    for (before,after) in [("trial.guard.json","mixed-preparation-rejected.guard.json"),
        ("trial-build.guard.json","mixed-preparation-build.guard.json"),
        ("prepared-bindings-trial-native-closure.json","mixed-preparation-native-closure.json")] do
      IO.FS.rename (evidence / before) (evidence / after)
    IO.FS.removeDirAll fixture
    IO.FS.writeFile (evidence / "retired-mixed-preparation.json") (Json.mkObj [
      ("target",toJson fixture),("completed",toJson true),("archiveCreated",toJson false),
      ("intentionalStop",toJson "candidate producer was preparing the baseline arm"),
      ("originalSourceUnchanged",toJson true),("actualHookCalls",toJson (0 : Nat)),
      ("answeringModelCalls",toJson (0 : Nat))]).pretty
    return
  if let [mode,arm] := args then
    check (["prepare-source-build","seal-source","retire-source"].contains mode &&
      ["baseline","candidate"].contains arm) "known source preparer phase and explicit arm required"
    let parent := root / (if arm == "baseline" then "query-cache-baseline-build" else "prepared-bindings-build")
    let selectedCore := if arm == "baseline" then root / "query-cache-baseline-core" else core
    let label := "source-prepare-" ++ arm
    if mode == "retire-source" then
      let records := evidence / "trial" / arm
      check ((← read (records / "prepare/record.json")).getObjValD "exitCode" == toJson (0 : Nat))
        "the per-arm source preparation must finish before its helper is retired"
      let runtimes ← IO.ofExcept ((← read (evidence / "runtime-descriptors.json")).getArr?)
      let some expected := runtimes.find? (fun row => row.getObjValD "arm" == toJson arm) |
        throw (IO.userError "the frozen per-arm runtime is missing")
      check ((← read (records / "prepared-source.json")).getObjValD "preparerGeneration" ==
        (expected.getObjValD "runtime").getObjValD "generation") "per-arm preparation generation differs"
      let descriptor ← read (evidence / (label ++ ".json"))
      let binary := root / (label ++ "-build/StudyMain")
      let hashed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",binary.toString]}
      check (hashed.exitCode == 0 && descriptor.getObjValD "sha256" == toJson ((hashed.stdout.splitOn " ").headD ""))
        "the completed source preparer executable changed"
      let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t",binary.toString]}
      check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty &&
        !(← (evidence / (label ++ "-retired.json")).pathExists)) "source preparer is still open or already retired"
      IO.FS.removeFile binary
      IO.FS.writeFile (evidence / (label ++ "-retired.json")) (Json.mkObj [
        ("target",toJson binary),("completed",toJson true),("archiveCreated",toJson false)]).pretty
      return
    if mode == "prepare-source-build" then
      prepareBuild selectedCore parent label "tools.research.SourcePrepare" (label ++ "-build.guard.json")
      return
    finished (label ++ "-build.guard.json")
    let audited ← IO.Process.output {
      cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
      args := #["-M1024","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
        (root / "cached-usage-runtime-build").toString,(root / (label ++ "-build")).toString,
        (evidence / (label ++ "-native-closure.json")).toString]}
    check (audited.exitCode == 0) "per-arm source preparer module closure differs"
    let binary := root / (label ++ "-build/StudyMain")
    let hashed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",binary.toString]}
    check (hashed.exitCode == 0 && !(← (evidence / (label ++ ".json")).pathExists)) "preserve frozen source preparer descriptor"
    let descriptor := Json.mkObj [("binary",toJson binary.toString),
      ("sha256",toJson ((hashed.stdout.splitOn " ").headD ""))]
    IO.FS.writeFile (evidence / (label ++ ".json")) descriptor.pretty
    if (← (evidence / "source-prepare-baseline.json").pathExists) &&
        (← (evidence / "source-prepare-candidate.json").pathExists) then
      check (!(← (evidence / "source-preparers.json").pathExists)) "preserve frozen per-arm preparers"
      let mut rows := #[]
      for name in ["baseline","candidate"] do
        rows := rows.push (Json.mkObj [("arm",toJson name),("preparer",← read (evidence / ("source-prepare-" ++ name ++ ".json")))])
      IO.FS.writeFile (evidence / "source-preparers.json") (Json.arr rows).pretty
    return
  if args == ["retire-previous-candidate"] || args == ["retire-previous-runtime"] then
    let legacy := args == ["retire-previous-runtime"]
    let old := project / (if legacy then "docs/candidates/deferred-quotation/actual-hook.guard.json" else
      "docs/candidates/service-block-cache/trial.guard.json")
    let guard ← read old
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      (← (evidence / "audit.json").pathExists)) "complete the previous comparison and the replacement candidate checks"
    let binary := root / (if legacy then "fact-deferred-runtime-build/StudyMain" else "service-block-cache-build/StudyMain")
    let retirement := evidence / (if legacy then "retired-previous-runtime.json" else "retired-previous-candidate.json")
    let hashed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",binary.toString]}
    check (hashed.exitCode == 0 && (hashed.stdout.splitOn " ").headD "" == (if legacy then
      "62d637b79abb480ac2bc9c6853d621dc57d92c87a1bd9de31985aeb985357b3b" else
      "f9c6d9340b72a761dcfcbf2d1ff58b4519fed66bc2cb56217233b3d6a0ce6c23")) "previous unadopted executable changed"
    let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t",binary.toString]}
    check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "previous candidate is still open"
    check (!(← retirement.pathExists)) "preserve completed retirement"
    IO.FS.removeFile binary
    IO.FS.writeFile retirement (Json.mkObj [
      ("target",toJson binary),("completed",toJson true),("archiveCreated",toJson false),
      ("currentControlCandidateOriginalsModelsAndNativeInputsRetained",toJson true)]).pretty
    return
  if args == ["retire-snapshot-only"] then
    let previous := evidence / "snapshot-only"
    let guard ← read (previous / "audit-before-delta.guard.json")
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) && (← (previous / "audit.json").pathExists))
      "seal the discarded snapshot-only prototype before retirement"
    let fixture := root / "prepared-bindings-audit"
    let binary := root / "prepared-bindings-audit-build/StudyMain"
    for path in [fixture,binary] do
      let options := if (← path.symlinkMetadata).type == .dir then #["-t","+D",path.toString] else #["-t",path.toString]
      let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := options}
      check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "old prototype fixture or helper is still open"
    IO.FS.removeDirAll fixture
    IO.FS.removeFile binary
    IO.FS.writeFile (previous / "retired.json") (Json.mkObj [
      ("targets",toJson #[fixture,binary]),("completed",toJson true),("archiveCreated",toJson false)]).pretty
    return
  if args == ["refine-delta"] then
    finished "build.guard.json"
    finished "audit.guard.json"
    refineDelta core
    savePatches core
    return
  if args == ["prepare-audit-run"] then
    finished "audit-build.guard.json"
    prepareRun "prepared-bindings-audit" "audit.guard.json" #[(root / "prepared-bindings-audit").toString]
    return
  if args == ["seal-audit"] then
    finished "audit.guard.json"
    let fixture := root / "prepared-bindings-audit"
    let binary := root / "prepared-bindings-audit-build/StudyMain"
    IO.FS.writeFile (evidence / "audit.json") (← IO.FS.readFile (fixture / "result.json"))
    for path in [fixture,binary] do
      let options := if (← path.symlinkMetadata).type == .dir then #["-t","+D",path.toString] else #["-t",path.toString]
      let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := options}
      check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "audited fixture or helper is still open"
    IO.FS.removeDirAll fixture
    IO.FS.removeFile binary
    IO.FS.writeFile (evidence / "retired-audit.json") (Json.mkObj [
      ("targets",toJson #[fixture,binary]),("completed",toJson true),("archiveCreated",toJson false)]).pretty
    return
  if args == ["prepare-runtime-run"] then
    finished "runtime-build.guard.json"
    prepareRun "prepared-bindings-runtime" "runtime.guard.json"
      #[(root / "prepared-bindings-build/StudyMain").toString,(evidence / "publisher-runtime-candidate.json").toString]
    return
  if args == ["seal-runtime"] then
    finished "runtime.guard.json"
    let control ← read (project / "docs/candidates/service-block-cache/publisher-runtime-baseline.json")
    let candidate ← read (evidence / "publisher-runtime-candidate.json")
    for descriptor in [control,candidate] do
      let binary ← IO.ofExcept (descriptor.getObjValAs? String "binary")
      let hashed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",binary]}
      check (hashed.exitCode == 0 && descriptor.getObjValD "sha256" == toJson ((hashed.stdout.splitOn " ").headD ""))
        "audited runtime changed after its independent protocol descriptor"
    check (!(← (evidence / "runtime-descriptors.json").pathExists)) "preserve frozen publisher descriptors"
    IO.FS.writeFile (evidence / "runtime-descriptors.json") (toJson #[
      Json.mkObj [("arm",toJson "baseline"),("runtime",control)],
      Json.mkObj [("arm",toJson "candidate"),("runtime",candidate)]]).pretty
    let binary := root / "prepared-bindings-runtime-build/StudyMain"
    let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t",binary.toString]}
    check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "protocol helper is still open"
    IO.FS.removeFile binary
    IO.FS.writeFile (evidence / "retired-runtime.json") (Json.mkObj [
      ("target",toJson binary),("completed",toJson true),("archiveCreated",toJson false)]).pretty
    return
  if args == ["prepare-trial-run"] then
    finished "trial-build.guard.json"
    prepareRun "prepared-bindings-trial" "trial.guard.json" #["bindings-cache"]
      #["EGGSHELL_DATA_ROOT=" ++ (root / "prepared-bindings-trial/data").toString]
    return
  if args == ["prepare-audit-build"] || args == ["prepare-runtime-build"] || args == ["prepare-trial-build"] then
    finished "build.guard.json"
    let library := core / ".lake/build/lib/lean"
    check ((← library.symlinkMetadata).type == .symlink) "prepared binding library link missing"
    IO.FS.removeFile library
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(root / "prepared-bindings-build/lib").toString,library.toString]}
    check (linked.exitCode == 0) "cannot bind the candidate's audited interfaces"
    let (label,mainModule,record) := if args == ["prepare-runtime-build"] then
      ("prepared-bindings-runtime","tools.research.PublisherRuntime","runtime-build.guard.json") else
      if args == ["prepare-trial-build"] then
        ("prepared-bindings-trial","tools.research.PreparedOriginalKeysTrial","trial-build.guard.json") else
        ("prepared-bindings-audit","tools.research.PreparedBindingsAudit","audit-build.guard.json")
    prepareBuild core (root / "prepared-bindings-build") label mainModule record
    return
  check (args.isEmpty && !(← core.pathExists)) "fresh isolated prepared binding candidate required"
  IO.FS.createDirAll evidence
  let baseline := root / "query-cache-baseline-core"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",baseline.toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate the exact readonly baseline"
  for name in ["ByteBudgetCache.lean","PreparedBindingCache.lean"] do
    IO.FS.writeFile (core / "tools" / name) (← IO.FS.readFile (project / "tools" / name))
  patch (core / "Eggshell/SynapticBindings.lean") fun text => do
    let text ← replace text
      "def lookup (reader : Index.Reader) (source : Range) (allowed : Std.HashSet String)\n    (deadline : Nat) (byteLimit : Nat := 8*1024*1024) :\n    IO (Lookup reader.manifest.source.identity allowed source) := do\n"
      "def rawLookup (reader : Index.Reader) (source : Range) (deadline byteLimit : Nat) : IO Scan := do\n"
    let text ← replace text "  let mut origins := #[]\n"
      "  return found\n\ndef checked (reader : Index.Reader) (source : Range) (allowed : Std.HashSet String)\n    (found : Scan) : Lookup reader.manifest.source.identity allowed source := Id.run do\n  let mut origins := #[]\n"
    let text ← replace text "structure Resolved where\n"
      "def lookup (reader : Index.Reader) (source : Range) (allowed : Std.HashSet String)\n    (deadline : Nat) (byteLimit : Nat := 8*1024*1024) :\n    IO (Lookup reader.manifest.source.identity allowed source) := do\n  return checked reader source allowed (← rawLookup reader source deadline byteLimit)\n\nstructure Resolved where\n"
    let text ← replace text
      "def resolve (reader : Index.Reader) (wanted : Array Range) (allowed : Std.HashSet String)\n    (deadline : Nat) : IO Resolved := do\n"
      "def resolveUsing (reader : Index.Reader) (wanted : Array Range) (allowed : Std.HashSet String)\n    (deadline : Nat) (pull : Range → Nat → IO Scan) : IO Resolved := do\n"
    let text ← replace text
      "    let found ← lookup reader source allowed deadline (32*1024*1024-result.bytes)\n"
      "    let found := checked reader source allowed (← pull source (32*1024*1024-result.bytes))\n"
    replace text "end Eggshell.Synapses.IndexedBindings\n"
      "def resolve (reader : Index.Reader) (wanted : Array Range) (allowed : Std.HashSet String)\n    (deadline : Nat) : IO Resolved :=\n  resolveUsing reader wanted allowed deadline (fun source byteLimit => rawLookup reader source deadline byteLimit)\n\nend Eggshell.Synapses.IndexedBindings\n"
  patch (core / "Eggshell/CanonicalSourcePrepared.lean") fun text => do
    let text ← replace text "public import Std.Sync.Mutex\n" "public import Std.Sync.Mutex\npublic import tools.PreparedBindingCache\n"
    let text ← replace text
      "def capacity : Nat := 512*1024*1024-ObservedRecordView.geometryCapacity-PageMap.SharedPageCache.capacity\n"
      "def capacity : Nat := 512*1024*1024-ObservedRecordView.geometryCapacity-PageMap.SharedPageCache.capacity-IndexedBindings.Prepared.capacity\n"
    let text ← replace text "  pages : PageMap.PagePool\n" "  pages : PageMap.PagePool\n  bindings : IndexedBindings.Prepared.Pool\n"
    let text ← replace text
      "def Pool.new : IO Pool := return ⟨← Std.Mutex.new {},← Std.Mutex.new #[],← PageMap.PagePool.new⟩\n"
      "def Pool.new : IO Pool := return ⟨← Std.Mutex.new {},← Std.Mutex.new #[],← PageMap.PagePool.new,← IndexedBindings.Prepared.Pool.new⟩\n"
    let text ← replace text "  for task in ← pool.tasks.atomically get do IO.cancel task\n"
      "  pool.bindings.close\n  for task in ← pool.tasks.atomically get do IO.cancel task\n"
    let text ← replace text "  let pages ← pool.pages.stats\n" "  let pages ← pool.pages.stats\n  let bindings ← pool.bindings.stats\n"
    replace text "(\"capacity\",toJson capacity),(\"pages\",pages)" "(\"capacity\",toJson capacity),(\"pages\",pages),(\"bindings\",bindings)"
  patch (core / "Eggshell/PublicationService.lean") fun text =>
    replace text "    let result ← IndexedBindings.resolve original wanted (Std.HashSet.ofArray allowed) deadline\n"
      "    let namespaceKey := (toJson (scope.scope,CanonicalSource.Shared.key path metadata)).compress\n    let result ← server.prepared.bindings.resolve namespaceKey original wanted (Std.HashSet.ofArray allowed) deadline\n"
  patch (core / "Eggshell/PublicationWire.lean") fun text =>
    replace text "  (include_str \"CanonicalSourcePrepared.lean\").toUTF8,(include_str \"DaemonWire.lean\").toUTF8,\n"
      "  (include_str \"CanonicalSourcePrepared.lean\").toUTF8,(include_str \"DaemonWire.lean\").toUTF8,\n  (include_str \"SynapticBindings.lean\").toUTF8,\n  (include_str \"../tools/PreparedBindingCache.lean\").toUTF8,(include_str \"../tools/ByteBudgetCache.lean\").toUTF8,\n"
  refineDelta core
  savePatches core
  prepareBuild core (root / "query-cache-baseline-build") "prepared-bindings" "Main" "build.guard.json"
  IO.println "Isolated publication-scoped decoded bindings; admission still checks every request's owners"
