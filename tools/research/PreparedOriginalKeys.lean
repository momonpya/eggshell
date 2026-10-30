import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def root : System.FilePath := study / "shared-snapshot"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def candidate : System.FilePath := root / "prepared-original-keys-core"
private def evidence : System.FilePath := project / "docs/candidates/prepared-original-keys"

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def replaceOnce (text old updated : String) : IO String := do
  check ((text.splitOn old).length == 2) "candidate refinement did not match exactly once"
  return text.replace old updated

private def finished (path : System.FilePath) : IO Unit := do
  let record ← read path
  check (record.getObjValD "state" == toJson "finished" && record.getObjValD "exitCode" == toJson (0 : Nat) &&
    record.getObjValD "ownedPids" == toJson (#[] : Array Nat) && record.getObjValD "guardTriggered" == toJson false)
    "successful exclusive completion required"

private def entries (path : System.FilePath) : IO (Array System.FilePath) := do
  if !(← path.pathExists) then return #[]
  return (← path.readDir).map (·.path)

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

private def summarize (blocks : Bool := false) : IO Unit := do
  let saved := if blocks then project / "docs/candidates/service-block-cache" else evidence
  finished (saved / "trial.guard.json")
  let records := saved / "trial"
  let result ← read (records / "result.json")
  check (result.getObjValD "allBodiesUnchanged" == toJson true &&
    result.getObjValD "originalSourcesUnchanged" == toJson true) "paired actual output or source changed"
  let trials ← IO.ofExcept (result.getObjValAs? (Array Json) "results")
  check (trials.size == 12) "all predetermined twelve actual hooks required"
  let mut measurements := #[]
  let mut sessions := #[]
  for trial in trials do
    let arm ← IO.ofExcept (trial.getObjValAs? String "arm")
    let repetition ← IO.ofExcept (trial.getObjValAs? Nat "repetition")
    let topic ← IO.ofExcept (trial.getObjValAs? Nat "topic")
    let session := s!"keys-{arm}-{repetition}-{topic}"
    let mut matching := #[]
    for receipt in ← entries (records / arm / "receipts") do
      let request := (← read (receipt / "request.json")).getObjValD "data"
      if request.getObjValD "session" == toJson session &&
          request.getObjValD "event" == toJson "UserPromptSubmit" then matching := matching.push receipt
    check (matching.size == 1) "exactly one actual prompt receipt per paired cell required"
    let receipt := matching[0]!
    let observed := fun name => do
      IO.ofExcept ((← read (receipt / name)).getObjValAs? Nat "observedMs")
    let data := fun name => do pure ((← read (receipt / name)).getObjValD "data")
    let mut numericMs := 0
    let mut focusEnd := 0
    let mut numerical := #[]
    for path in ← entries receipt do
      unless path.fileName.get!.startsWith "numerical-" do continue
      let value ← read path
      let detail := value.getObjValD "data"
      check (detail.getObjValD "status" == toJson "completed") "paired numerical stage did not complete"
      let elapsed ← IO.ofExcept (detail.getObjValAs? Nat "elapsedMs")
      let purpose := (detail.getObjValD "corpus").getObjValD "purpose"
      if purpose == toJson "focus" then focusEnd ← IO.ofExcept (value.getObjValAs? Nat "observedMs")
      numericMs := numericMs + elapsed
      numerical := numerical.push (Json.mkObj [("purpose",purpose),("elapsedMs",toJson elapsed)])
    let domain ← observed "delivery-domain.json"
    let selected ← observed "selection-plan.json"
    check (numerical.size == 2 && focusEnd > 0 && domain ≥ focusEnd && selected ≥ domain)
      "ordered observation boundaries and two numerical stages required"
    let delivery ← data "synaptic-delivery.json"
    let selection ← data "selection-plan.json"
    let measured := trial.setObjVal! "receipt" (toJson receipt.fileName)
      |>.setObjVal! "numerical" (Json.arr numerical)
      |>.setObjVal! "numericalElapsedSumMs" (toJson numericMs)
      |>.setObjVal! "focusObservedToDomainObservedMs" (toJson (domain-focusEnd))
      |>.setObjVal! "domainObservedToSelectionObservedMs" (toJson (selected-domain))
      |>.setObjVal! "bindingRequests" (delivery.getObjValD "bindingRequests")
      |>.setObjVal! "bindingBytes" (delivery.getObjValD "bindingBytes")
      |>.setObjVal! "completed" (delivery.getObjValD "completed")
      |>.setObjVal! "canonicalReuse" (← data "canonical-source-reuse.json")
      |>.setObjVal! "candidateUnits" (selection.getObjValD "candidateUnits")
    let measured ← if blocks then do
        let run := records / arm / s!"rep-{repetition}"
        let before ← read (if topic == 1 then run / "service-before.json" else
          run / s!"topic-{topic-1}/service-after.json")
        let after ← read (run / s!"topic-{topic}/service-after.json")
        let prior := (before.getObjValD "preparedSources").getObjValD "pages"
        let current := (after.getObjValD "preparedSources").getObjValD "pages"
        let oldMisses ← IO.ofExcept (prior.getObjValAs? Nat "misses")
        let newMisses ← IO.ofExcept (current.getObjValAs? Nat "misses")
        check (newMisses ≥ oldMisses) "shared page counters restarted during an arm"
        pure (measured.setObjVal! "sharedPageMisses" (toJson (newMisses-oldMisses))
          |>.setObjVal! "sharedPagesAfter" current
          |>.setObjVal! "preparedSourceLoads" ((after.getObjValD "preparedSources").getObjValD "loads"))
      else pure measured
    measurements := measurements.push measured
    let directory := root / (if blocks then "service-block-cache-trial" else "prepared-original-keys-trial") / arm / "data/sessions" / session
    let pending ← read (directory / "pending.json")
    let deferred ← entries (directory / "deferred")
    let checkpoints ← entries (directory / "checkpoints")
    let shutdown ← read (records / arm / s!"rep-{repetition}/topic-{topic}/shutdown.json")
    check (shutdown.getObjValD "acknowledged" == toJson true &&
      shutdown.getObjValD "processExited" == toJson true && shutdown.getObjValD "daemonExitCode" == toJson (0 : Nat))
      "session shutdown not confirmed"
    let mut pendingFields := []
    for key in ["closed","turnId","tools","sources","inFlight","finalMessage"] do
      pendingFields := pendingFields ++ [(key,pending.getObjValD key)]
    check (pending.getObjValD "tools" == toJson (#[] : Array Json) &&
      pending.getObjValD "inFlight" == toJson (#[] : Array Json) && deferred.isEmpty && checkpoints.isEmpty)
      "seal queued original work before retiring trial"
    sessions := sessions.push (Json.mkObj [("session",toJson session),("shutdown",shutdown),
      ("pending",Json.mkObj pendingFields),("deferredEntries",toJson deferred.size),
      ("checkpointEntries",toJson checkpoints.size)])
  IO.FS.writeFile (saved / "latency-summary.json") (Json.mkObj [
    ("rows",Json.arr measurements),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false),
    ("scope",toJson "Two actual first-prompt hooks per topic and arm. Observation gaps include IO, computation and receipt serialization, not per-function CPU time. Not answering-model first/second rounds, token improvement, p99 or eighty-user sustained load.")]).pretty
  IO.FS.writeFile (saved / "lifecycle.json") (Json.mkObj [("sessions",Json.arr sessions),
    ("observedTerminalWarning",if blocks then Json.null else
      toJson "Eggshell retained queued work: timed out waiting for keys-baseline-1-2/state.guard"),
    ("interpretation",toJson (if blocks then
      "Final queues and process exits only; this does not prove the absence of historical transient contention. No turnStop or answer generation was performed." else
      "A state-lock timeout was observed. Final deferred/checkpoint directories are empty, pending prompt turns have no tools/in-flight outputs, every session acknowledged exit zero and the guard has no surviving processes. This is not a correction or a proof of the transient lock's cause; no turnStop or answer generation was performed.")),
    ("originalSourcesUnchanged",toJson true)]).pretty
  IO.println "Sealed twelve paired hooks, phase gaps and final empty-output queue metadata; no adoption claim"

def main (args : List String) : IO Unit := do
  if args == ["retire-profile-executables"] then
    let saved := project / "docs/candidates/source-service-profile"
    finished (saved / "trial.guard.json")
    finished (saved / "reuse.guard.json")
    let measured ← read (saved / "reuse/result.json")
    check (measured.getObjValD "originalSourceUnchanged" == toJson true &&
      !(← (saved / "retired-executables.json").pathExists)) "seal the finished service profiles before deleting executables"
    let targets := #[root / "source-service-profile-build/StudyMain",root / "source-cache-reuse-build/StudyMain",
      root / "prepared-original-keys-build/StudyMain"]
    let mut bytes := 0
    for path in targets do
      let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t",path.toString]}
      check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "a retired measured executable is still open"
      bytes := bytes+(← path.symlinkMetadata).byteSize.toNat
    let record := Json.mkObj [("targets",toJson targets),("logicalBytes",toJson bytes),
      ("archiveCreated",toJson false),("originalSourceModelControlRuntimeAndNativeInputsRetained",toJson true),
      ("preparedReadonlyControlFixtureForImminentBlockCacheComparisonRetained",toJson true)]
    IO.FS.writeFile (saved / "retired-executables.json") (record.setObjVal! "completed" (toJson false)).pretty
    for path in targets do IO.FS.removeFile path
    IO.FS.writeFile (saved / "retired-executables.json") (record.setObjVal! "completed" (toJson true)).pretty
    IO.println "Deleted three completed helper/unadopted executables; retained only the next comparison's prepared source fixture"
    return
  if args == ["summarize"] then return ← summarize
  if args == ["summarize-cache"] then return ← summarize true
  if args == ["retire-cache-trial"] then
    let saved := project / "docs/candidates/service-block-cache"
    finished (saved / "trial.guard.json")
    finished (project / "docs/candidates/source-service-profile/trial.guard.json")
    finished (project / "docs/candidates/source-service-profile/reuse.guard.json")
    check ((← (saved / "latency-summary.json").pathExists) && (← (saved / "lifecycle.json").pathExists) &&
      !(← (saved / "retired-trial.json").pathExists)) "seal actual paired cache hooks before deleting their fixtures"
    let targets := #[root / "service-block-cache-trial",root / "source-service-profile",
      root / "service-block-cache-trial-build/StudyMain"]
    for path in targets do
      let args := if (← path.symlinkMetadata).type == .dir then #["-t","+D",path.toString] else #["-t",path.toString]
      let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args}
      check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "measured cache fixture is still open"
    let report := Json.mkObj [("targets",toJson targets),("archiveCreated",toJson false),
      ("originalSourceJournalModelControlCandidateAndNativeInputsRetained",toJson true)]
    IO.FS.writeFile (saved / "retired-trial.json") (report.setObjVal! "completed" (toJson false)).pretty
    for path in targets do remove path
    IO.FS.writeFile (saved / "retired-trial.json") (report.setObjVal! "completed" (toJson true)).pretty
    IO.println "Deleted finished profile and cache-trial DB/cache/install and the helper executable; no archive"
    return
  if args == ["retire"] then
    finished (evidence / "trial.guard.json")
    check ((← (evidence / "latency-summary.json").pathExists) && (← (evidence / "lifecycle.json").pathExists) &&
      !(← (evidence / "retired.json").pathExists)) "seal measurements and retained-queue warning before retirement"
    let targets := #[root / "prepared-original-keys-trial",root / "prepared-original-keys-trial-build/StudyMain"]
    for path in targets do
      let arguments := if (← path.symlinkMetadata).type == .dir then #["-t","+D",path.toString] else #["-t",path.toString]
      let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := arguments}
      check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "paired native trial still open"
    let report := Json.mkObj [("targets",toJson targets),("archiveCreated",toJson false),
      ("originalSourceJournalModelControlCandidateAndNativeDependencyInputsRetained",toJson true)]
    IO.FS.writeFile (evidence / "retired.json") (report.setObjVal! "completed" (toJson false)).pretty
    for path in targets do remove path
    IO.FS.writeFile (evidence / "retired.json") (report.setObjVal! "completed" (toJson true)).pretty
    IO.println "Deleted completed paired DB/cache/install and helper executable; no archive"
    return
  if args == ["prepare-trial-build"] || args == ["prepare-profile-build"] || args == ["prepare-reuse-build"] ||
      args == ["prepare-cache-trial-build"] then
    let blocks := args == ["prepare-cache-trial-build"]
    let reuse := args == ["prepare-reuse-build"]
    let profile := !blocks && args != ["prepare-trial-build"]
    let saved := if blocks then project / "docs/candidates/service-block-cache" else
      if profile then project / "docs/candidates/source-service-profile" else evidence
    IO.FS.createDirAll saved
    let guard ← read ((if blocks then saved else evidence) / "build.guard.json")
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "candidate runtime must finish before linking trial"
    let parent := root / (if blocks then "service-block-cache-build" else if reuse then "source-service-profile-build" else "prepared-original-keys-build")
    let build ← read (parent / "build.json")
    let prior := build.getObjValD "settings"
    let mut modules ← IO.ofExcept ((← read (.mk (← IO.ofExcept (prior.getObjValAs? String "objectModules")))).getObj?)
    for entry in ← IO.ofExcept (build.getObjValAs? (Array Json) "modules") do
      modules := modules.insert (← IO.ofExcept (entry.getObjValAs? String "object")) (entry.getObjValD "module")
    let label := if blocks then "service-block-cache-trial" else if reuse then "source-cache-reuse" else
      if profile then "source-service-profile" else "prepared-original-keys-trial"
    let map := root / (label ++ "-objects.json")
    IO.FS.writeFile map (Json.obj modules).pretty
    let settings := prior.setObjVal! "objectModules" (toJson map.toString)
      |>.setObjVal! "baselineResponse" (toJson (parent / "runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (parent / "Main.o").toString)
      |>.setObjVal! "output" (toJson (root / (label ++ "-build")).toString)
      |>.setObjVal! "mainModule" (toJson "tools.research.PreparedOriginalKeysTrial")
    let library := (if blocks then root / "service-block-cache-core" else candidate) / ".lake/build/lib/lean"
    check ((← library.symlinkMetadata).type == .symlink) "candidate interface link missing"
    IO.FS.removeFile library
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(parent / "lib").toString,library.toString]}
    check (linked.exitCode == 0) "cannot reuse consistent candidate interfaces"
    IO.FS.writeFile (root / (label ++ "-build.settings.json")) settings.pretty
    IO.FS.writeFile (root / (label ++ "-build.guard-settings.json")) (Json.mkObj [
      ("record",toJson (saved / (if reuse then "reuse-build.guard.json" else "trial-build.guard.json")).toString),("cwd",toJson project.toString),
      ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1", "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
        "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,(root / (label ++ "-build.settings.json")).toString])]).pretty
    unless profile || blocks do
      let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",(root / "query-cache-baseline-core/Eggshell/Handoff.lean").toString,
        (candidate / "Eggshell/Handoff.lean").toString]}
      check (patch.exitCode == 1) "candidate patch absent"
      IO.FS.writeFile (evidence / "core.patch") patch.stdout
    IO.println (if profile then "Prepared unchanged-runtime data-side CPU diagnosis" else
      "Prepared paired fixed-source actual hook harness; two fresh repetitions per topic and arm")
    return
  if args == ["prepare-trial"] || args == ["prepare-profile"] || args == ["prepare-reuse"] ||
      args == ["prepare-cache-trial"] then
    let blocks := args == ["prepare-cache-trial"]
    let reuse := args == ["prepare-reuse"]
    let profile := !blocks && args != ["prepare-trial"]
    let saved := if blocks then project / "docs/candidates/service-block-cache" else
      if profile then project / "docs/candidates/source-service-profile" else evidence
    let label := if blocks then "service-block-cache-trial" else if reuse then "source-cache-reuse" else
      if profile then "source-service-profile" else "prepared-original-keys-trial"
    let guard ← read (saved / (if reuse then "reuse-build.guard.json" else "trial-build.guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "trial native build must finish before use"
    let audited ← IO.Process.output {
      cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
      args := #["-M1024","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
        (root / "cached-usage-runtime-build").toString,(root / (label ++ "-build")).toString,
        (saved / (if reuse then "reuse-native-closure.json" else "trial-native-closure.json")).toString]}
    check (audited.exitCode == 0) "paired native harness dependencies differ"
    IO.FS.writeFile (root / (label ++ ".guard-settings.json")) (Json.mkObj [
      ("record",toJson (saved / (if reuse then "reuse.guard.json" else "trial.guard.json")).toString),("cwd",toJson project.toString),
      ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("command",toJson (#["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT=" ++ (root / label / "data").toString,
        (root / (label ++ "-build/StudyMain")).toString] ++
        (if blocks then #["block-cache"] else if reuse then #["reuse-service"] else if profile then #["profile-service"] else #[])))]).pretty
    IO.println "Prepared guarded paired actual hooks without answering models or adoption claims"
    return
  check (args == ["prepare"] && !(← candidate.pathExists)) "fresh explicit original-key candidate required"
  IO.FS.createDirAll evidence
  let baseline := root / "query-cache-baseline-build"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "query-cache-baseline-core").toString,candidate.toString]}
  check (copied.exitCode == 0) "cannot isolate exact query-only baseline sources"
  IO.FS.writeFile (candidate / "tools/PreparedIdentity.lean") (← IO.FS.readFile (project / "tools/PreparedIdentity.lean"))
  let path := candidate / "Eggshell/Handoff.lean"
  let mut text ← IO.FS.readFile path
  text ← replaceOnce text "public import tools.PointBuckets\n"
    "public import tools.PointBuckets\npublic import tools.PreparedIdentity\n"
  text ← replaceOnce text
    "def prepareCached (familyIndex : Nat) (family : Family) : List UnitPlan × List (Nat × Nat) := Id.run do\n"
    "def prepareCachedUsing (rowKey : Synapses.CanonicalSource.Key → String)\n    (familyIndex : Nat) (family : Family) : List UnitPlan × List (Nat × Nat) := Id.run do\n"
  text ← replaceOnce text
    "owner := some family.owner.relation,keys := shared.keys,text := \"\",shared := some shared\n"
    "owner := some family.owner.relation\n      keys := (if shared.plan.isEmpty then [] else [shared.plan]) ++ shared.rows.toList.map (fun row => rowKey row.key)\n      text := \"\",shared := some shared\n"
  text ← replaceOnce text "theorem shared_source_unit_has_no_control"
    "def prepareCached (familyIndex : Nat) (family : Family) : List UnitPlan × List (Nat × Nat) :=\n  prepareCachedUsing Synapses.CanonicalSource.Delivery.rowKey familyIndex family\n\ntheorem shared_source_unit_has_no_control"
  text ← replaceOnce text
    "def prepare (familyIndex : Nat) (family : Family) : List UnitPlan × List (Nat × Nat) := Id.run do\n"
    "def prepareUsing (rowKey : Synapses.CanonicalSource.Key → String)\n    (familyIndex : Nat) (family : Family) : List UnitPlan × List (Nat × Nat) := Id.run do\n"
  text ← replaceOnce text "let records := prepareCached familyIndex family\n"
    "let records := prepareCachedUsing rowKey familyIndex family\n"
  let prepared := "def prepare (familyIndex : Nat) (family : Family) : List UnitPlan × List (Nat × Nat) :=\n" ++
    "  prepareUsing Synapses.CanonicalSource.Delivery.rowKey familyIndex family\n\n" ++
    "def prepareFamilies (families : List Family) :=\n  families.zipIdx.map fun (family,index) => prepare index family\n\n" ++
    "def prepareFamiliesCached (families : List Family) :=\n" ++
    "  let files := (families.flatMap fun family => family.cached.toList.map (fun row => row.key.file)).toArray\n" ++
    "  let identities := PreparedIdentity.prepare (fun file : Synapses.File => Synapses.Index.contentKey file) files\n" ++
    "  let rowKey := fun key : Synapses.CanonicalSource.Key =>\n" ++
    "    \"c:\" ++ PreparedIdentity.get identities key.file ++ \":\" ++ toString key.line\n" ++
    "  families.zipIdx.map fun (family,index) => prepareUsing rowKey index family\n\n" ++
    "@[csimp] theorem prepare_families_compiled : @prepareFamilies = @prepareFamiliesCached := by\n" ++
    "  funext families\n  unfold prepareFamilies prepareFamiliesCached\n  dsimp only\n" ++
    "  have same : (λ key : Synapses.CanonicalSource.Key =>\n" ++
    "      \"c:\" ++ PreparedIdentity.get (PreparedIdentity.prepare\n" ++
    "        (fun file : Synapses.File => Synapses.Index.contentKey file)\n" ++
    "        (families.flatMap fun family => family.cached.toList.map (fun row => row.key.file)).toArray) key.file ++\n" ++
    "      \":\" ++ toString key.line) = Synapses.CanonicalSource.Delivery.rowKey := by\n" ++
    "    funext key\n    rw [PreparedIdentity.get_exact]\n    rfl\n" ++
    "  rw [same]\n  rfl\n\n"
  text ← replaceOnce text "def join (prior next : TransportSlice) : Option TransportSlice := do\n"
    (prepared ++ "def join (prior next : TransportSlice) : Option TransportSlice := do\n")
  text ← replaceOnce text "let prepared := families.zipIdx.map fun (family,index) => prepare index family\n"
    "let prepared := prepareFamilies families\n"
  IO.FS.writeFile path text
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",(root / "query-cache-baseline-core/Eggshell/Handoff.lean").toString,path.toString]}
  check (patch.exitCode == 1) "candidate Handoff patch missing"
  IO.FS.writeFile (evidence / "core.patch") patch.stdout
  let library := candidate / ".lake/build/lib/lean"
  check ((← library.symlinkMetadata).type == .symlink) "baseline interface link required"
  IO.FS.removeFile library
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(baseline / "lib").toString,library.toString]}
  check (linked.exitCode == 0) "cannot reuse baseline interfaces"
  let build ← read (baseline / "build.json")
  let prior := build.getObjValD "settings"
  let mut modules ← IO.ofExcept ((← read (.mk (← IO.ofExcept (prior.getObjValAs? String "objectModules")))).getObj?)
  for entry in ← IO.ofExcept (build.getObjValAs? (Array Json) "modules") do
    modules := modules.insert (← IO.ofExcept (entry.getObjValAs? String "object")) (entry.getObjValD "module")
  let label := "prepared-original-keys"
  let map := root / (label ++ "-objects.json")
  IO.FS.writeFile map (Json.obj modules).pretty
  let settings := prior.setObjVal! "core" (toJson candidate.toString)
    |>.setObjVal! "project" (toJson project.toString)
    |>.setObjVal! "baselineCore" (toJson (root / "query-cache-baseline-core").toString)
    |>.setObjVal! "objectModules" (toJson map.toString)
    |>.setObjVal! "baselineResponse" (toJson (baseline / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (baseline / "Main.o").toString)
    |>.setObjVal! "output" (toJson (root / (label ++ "-build")).toString)
  IO.FS.writeFile (root / (label ++ "-build.settings.json")) settings.pretty
  IO.FS.writeFile (root / (label ++ "-build.guard-settings.json")) (Json.mkObj [
    ("record",toJson (evidence / "build.guard.json").toString),("cwd",toJson project.toString),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1", "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
      "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,(root / (label ++ "-build.settings.json")).toString])]).pretty
  IO.println "Prepared isolated whole-family file identity reuse; source DB and baseline implementation unchanged"
