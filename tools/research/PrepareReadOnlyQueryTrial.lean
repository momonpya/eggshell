import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def root : System.FilePath := study / "shared-snapshot"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def output : System.FilePath := project / "docs/candidates/query-cache-llvm"

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def finished (path : System.FilePath) : IO Unit := do
  let record ← read path
  check (record.getObjValD "state" == toJson "finished" && record.getObjValD "exitCode" == toJson (0 : Nat) &&
    record.getObjValD "ownedPids" == toJson (#[] : Array Nat) && record.getObjValD "guardTriggered" == toJson false)
    "wait for successful exclusive completion"

private def copy (source target : System.FilePath) : IO Unit := do
  check (!(← target.pathExists)) "preserve copied native evidence"
  IO.FS.createDirAll target.parent.get!
  IO.FS.writeFile target (← IO.FS.readFile source)

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def main (args : List String) : IO Unit := do
  let trial := root / "readonly-query-llvm"
  if args == ["seal-profile"] then
    finished (output / "readonly-query-profile.guard.json")
    let profile := output / "profile"
    let result ← read (profile / "result.json")
    check (result.getObjValD "sourceUnchanged" == toJson true &&
      result.getObjValD "bodyUnchanged" == toJson true) "sample changed frozen source or actual body"
    for entry in ← (trial / "data/receipts").readDir do
      let request ← read (entry.path / "request.json")
      if (request.getObjValD "data").getObjValD "session" != toJson "readonly-query-cpu-profile-2" then continue
      for file in ← entry.path.readDir do
        if file.fileName.endsWith ".json" then copy file.path (profile / "receipts" / entry.fileName / file.fileName)
    for entry in ← root.readDir do
      if entry.fileName.startsWith "readonly-query-profile-build-" && entry.fileName.endsWith ".guard.json" then
        copy entry.path (profile / "build-attempts" / entry.fileName)
    IO.println "Sealed unchanged-runtime CPU samples, actual receipts and failed build attempts"
    return
  if args == ["summarize-latency"] then
    finished (output / "actual-native.guard.json")
    let mut rows := #[]
    for topic in [1,2,3] do
      let mut matched : Array System.FilePath := #[]
      for entry in ← (output / "records/receipts").readDir do
        let request ← read (entry.path / "request.json")
        let data := request.getObjValD "data"
        if data.getObjValD "session" == toJson s!"readonly-candidate-{topic}" &&
            data.getObjValD "event" == toJson "UserPromptSubmit" then
          matched := matched.push entry.path
      check (matched.size == 1) "one sealed actual prompt receipt per topic required"
      let receipt := matched[0]!
      let observed := fun name => do
        let value ← read (receipt / name)
        IO.ofExcept (value.getObjValAs? Nat "observedMs")
      let data := fun name => do
        pure ((← read (receipt / name)).getObjValD "data")
      let mut numerical := #[]
      let mut focusEnd := 0
      let mut previousEnd := 0
      let mut numericalMs := 0
      for entry in ← receipt.readDir do
        unless entry.fileName.startsWith "numerical-" do continue
        let value ← read entry.path
        let counts := value.getObjValD "data"
        let purpose := (counts.getObjValD "corpus").getObjValD "purpose"
        let endMs ← IO.ofExcept (value.getObjValAs? Nat "observedMs")
        let elapsed ← IO.ofExcept (counts.getObjValAs? Nat "elapsedMs")
        check (counts.getObjValD "status" == toJson "completed") "both numerical stages must complete"
        if purpose == toJson "focus" then focusEnd := endMs
        if purpose == toJson "keyed-discovery" then previousEnd := endMs
        numericalMs := numericalMs + elapsed
        let counters := counts.getObjValD "counters"
        numerical := numerical.push (Json.mkObj [("purpose",purpose),("elapsedMs",toJson elapsed),
          ("observedMs",toJson endMs),("scoreMs",counters.getObjValD "scoreMs"),
          ("projectionReadMsWithinScore",counters.getObjValD "projectionReadMsWithinScore"),
          ("encoder",counters.getObjValD "encoder")])
      check (numerical.size == 2 && previousEnd > 0 && focusEnd > previousEnd)
        "sequential discovery/focus receipts required"
      let domain ← observed "delivery-domain.json"
      let selected ← observed "selection-plan.json"
      check (domain ≥ focusEnd && selected ≥ domain) "ordered observation boundaries required"
      let delivery ← data "synaptic-delivery.json"
      let selection ← data "selection-plan.json"
      let prompt ← read (output / "records/candidate" / s!"topic-{topic}/UserPromptSubmit/record.json")
      rows := rows.push (Json.mkObj [("topic",toJson topic),("receipt",toJson receipt.fileName),
        ("hookRecord",prompt),("numerical",Json.arr numerical),("numericalElapsedSumMs",toJson numericalMs),
        ("focusObservedToDomainObservedMs",toJson (domain-focusEnd)),
        ("domainObservedToSelectionObservedMs",toJson (selected-domain)),
        ("bindingRequests",delivery.getObjValD "bindingRequests"),("bindingBytes",delivery.getObjValD "bindingBytes"),
        ("canonicalReuse", ← data "canonical-source-reuse.json"),
        ("candidateUnits",selection.getObjValD "candidateUnits"),
        ("selectedUnits",toJson ((← IO.ofExcept (selection.getObjValAs? (Array Json) "selected")).size))])
    let result := Json.mkObj [("rows",Json.arr rows),("answeringModelCalls",toJson (0 : Nat)),
      ("scope",toJson "Existing sealed real hooks only. Observation gaps include IO, computation and receipt serialization; they are not per-function CPU profiles. Nested numerical counters must not be added to their enclosing stage."),
      ("database",toJson "Eggshell custom database; no SQLite/PostgreSQL substitution"),
      ("adopted",toJson false)]
    IO.FS.writeFile (output / "latency-summary.json") result.pretty
    IO.println result.compress
    return
  if args == ["summarize-support"] then
    finished (output / "missing-support-audit.guard.json")
    let report ← read (output / "missing-support.json")
    let mut summary := #[]
    for entry in ← IO.ofExcept (report.getObjValAs? (Array Json) "rows") do
      let mut fields := []
      for key in ["topic","names","missing","partial","readCount","readsCoverWholeObligation",
          "supportCount","supportsCoverWholeObligation","coquotedCount","consumedCount","usedCount","supportAnswersInActualBody"] do
        fields := fields ++ [(key,entry.getObjValD key)]
      let mut bases : Std.HashMap String Nat := {}
      for support in ← IO.ofExcept (entry.getObjValAs? (Array Json) "supports") do
        let key := (support.getObjValD "basis").compress
        bases := bases.insert key (bases[key]?.getD 0+1)
      summary := summary.push (Json.mkObj (fields ++ [("supportBases",toJson bases.toArray)]))
    let result := Json.mkObj [("rows",Json.arr summary),("sharedFacts",report.getObjValD "sharedFacts"),
      ("usageFacts",report.getObjValD "usageFacts"),("sourceUnchanged",report.getObjValD "sourceUnchanged")]
    IO.FS.writeFile (output / "support-summary.json") result.pretty
    IO.println result.compress
    return
  if args == ["seal"] then
    finished (output / "actual-native.guard.json")
    check (!(← (output / "records").pathExists)) "preserve readonly native reports"
    let saved := output / "records"
    for name in ["result.json","frozen-before-delivery.json","history-input.json","prepared-source.json","publisher-shutdown.json"] do
      copy (trial / name) (saved / name)
    for name in ["record.json","stdin","stdout","stderr"] do copy (trial / "warm" / name) (saved / "warm" / name)
    for arm in ["baseline","candidate"] do
      copy (trial / arm / "readonly.toml") (saved / arm / "readonly.toml")
      for topic in [1,2,3] do
        let source := trial / arm / s!"topic-{topic}"
        let target := saved / arm / s!"topic-{topic}"
        for name in ["audit.json","audit-input.json","body.txt","shutdown.json"] do copy (source / name) (target / name)
        for event in ["SessionStart","UserPromptSubmit"] do
          for name in ["record.json","stdin","stdout","stderr"] do copy (source / event / name) (target / event / name)
        copy (trial / "data/sessions" / s!"readonly-{arm}-{topic}/state.json") (target / "state.json")
    for receipt in ← (trial / "data/receipts").readDir do
      for entry in ← receipt.path.readDir do
        if entry.fileName.endsWith ".json" then copy entry.path (saved / "receipts" / receipt.fileName / entry.fileName)
    IO.FS.writeFile (output / "decision.json") (Json.mkObj [
      ("readonlyQueryInitializationRecovered",toJson true),("llvmRequiredDeliveryTargetMet",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),
      ("eightyUserSustainedLoadMeasured",toJson false),("adopted",toJson false),("goalAchieved",toJson false)]).pretty
    IO.println "Sealed all six readonly native topic bodies and frozen obligations; no token/adoption claim"
    return
  if args == ["prepare-support"] || args == ["prepare-profile"] then
    let profile := args == ["prepare-profile"]
    let label := if profile then "readonly-query-profile" else "missing-support-audit"
    let settings ← read (root / (label ++ "-build.guard-settings.json"))
    let record := System.FilePath.mk (← IO.ofExcept (settings.getObjValAs? String "record"))
    finished record
    copy record (output / (label ++ "-build.guard.json"))
    let audited ← IO.Process.output {
      cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
      args := #["-M1024","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
        (root / "cached-usage-runtime-build").toString,(root / (label ++ "-build")).toString,
        (output / (label ++ "-native-closure.json")).toString]}
    check (audited.exitCode == 0) "offline support audit native closure differs"
    let command := #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ (trial / "data").toString,
        (root / (label ++ "-build/StudyMain")).toString] ++
        if profile then #[] else #[trial.toString,(output / "missing-support.json").toString]
    IO.FS.writeFile (root / (label ++ ".guard-settings.json")) (Json.mkObj [
      ("record",toJson (output / (label ++ ".guard.json")).toString),("cwd",toJson project.toString),
      ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("command",toJson command)]).pretty
    IO.println "Prepared unchanged-source diagnosis without selector or model changes"
    return
  if args == ["retire"] then
    finished (output / "actual-native.guard.json")
    finished (output / "missing-support-audit.guard.json")
    finished (output / "readonly-query-profile.guard.json")
    let support ← read (output / "missing-support.json")
    let profile ← read (output / "profile/result.json")
    check (support.getObjValD "sourceUnchanged" == toJson true && (← (output / "records/result.json").pathExists) &&
      profile.getObjValD "sourceUnchanged" == toJson true && profile.getObjValD "bodyUnchanged" == toJson true &&
      (← (output / "profile/receipts").pathExists) &&
      !(← (output / "retired.json").pathExists)) "seal ongoing diagnostic before retirement"
    let targets := #[trial,root / "readonly-query-trial-build/StudyMain",root / "missing-support-audit-build/StudyMain",
      root / "readonly-query-profile-build/StudyMain"]
    for path in targets do
      let arguments := if (← path.symlinkMetadata).type == .dir then #["-t","+D",path.toString] else #["-t",path.toString]
      let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := arguments}
      check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "native trial still open"
    let report := Json.mkObj [("targets",toJson targets),("archiveCreated",toJson false),
      ("originalSourceJournalModelCurrentRuntimeAndDependencyInputsRetained",toJson true)]
    IO.FS.writeFile (output / "retired.json") (report.setObjVal! "completed" (toJson false)).pretty
    for path in targets do remove path
    IO.FS.writeFile (output / "retired.json") (report.setObjVal! "completed" (toJson true)).pretty
    IO.println "Deleted finished readonly fixture DB/cache/install and helper executables; no archives"
    return
  check (args == ["prepare"]) "explicit readonly trial preparation required"
  IO.FS.createDirAll output
  check (!(← trial.pathExists) && !(← (output / "actual-native.guard.json").pathExists)) "preserve readonly trial"
  for label in ["query-cache-baseline","readonly-query-trial"] do
    let settings ← read (root / (label ++ "-build.guard-settings.json"))
    let record ← read (.mk (← IO.ofExcept (settings.getObjValAs? String "record")))
    check (record.getObjValD "state" == toJson "finished" && record.getObjValD "exitCode" == toJson (0 : Nat) &&
      record.getObjValD "ownedPids" == toJson (#[] : Array Nat) && record.getObjValD "guardTriggered" == toJson false)
      "wait for checked native build completion"
    IO.FS.writeFile (output / (label ++ "-build.guard.json")) record.pretty
    let audited ← IO.Process.output {
      cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
      args := #["-M1024","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
        (root / "cached-usage-runtime-build").toString,(root / (label ++ "-build")).toString,
        (output / (label ++ "-native-closure.json")).toString]}
    check (audited.exitCode == 0) s!"native object closure failed: {label}: {audited.stderr}"
  IO.FS.writeFile (root / "readonly-query-llvm.guard-settings.json") (Json.mkObj [
    ("record",toJson (output / "actual-native.guard.json").toString),("cwd",toJson project.toString),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ (trial / "data").toString,
      (root / "readonly-query-trial-build/StudyMain").toString,(root / "query-cache-baseline-build/StudyMain").toString,trial.toString])]).pretty
  IO.println "Prepared guarded matched readonly topic hooks on the fixed LLVM source; answering models remain disabled"
