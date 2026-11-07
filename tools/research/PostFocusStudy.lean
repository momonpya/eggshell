import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace PostFocusStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := workspace/"docs/candidates/post-focus"
def output := base/"post-focus-profile-result"
def source := base/"post-focus-profile-source"
def build := base/"post-focus-profile-build"
def tag := "post-focus-profile1"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def drained : IO Unit := do
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!processes.contains "controller/StudyMain guard ") "another resource guard is active"
def guard (name : String) (arguments : Array String) : IO Unit := do
  check (!(← (base/(name++".guard-settings.json")).pathExists)) "retain previous guard"
  write (base/(name++".guard-settings.json")) (Json.mkObj [
    ("command",toJson arguments),("cwd",toJson workspace.toString),("record",toJson (base/(name++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def setup : IO Unit := do
  drained
  check (!(← folder.pathExists) && !(← output.pathExists)) "preserve prior post-focus observations"
  IO.FS.createDirAll folder
  write (folder/"plan.json") (Json.mkObj [
    ("runtimeSha256",toJson "ba2d1d30ec3ec83945c1dcb9c072534f6e29d101106aa137f971dd05a84442d6"),
    ("workload",toJson "one frozen LLVM topic2, same source and handoffChars500000 capacity condition"),
    ("purpose",toJson "existing phase timings, unchanged runtime; no full80 repetition or tuning"),
    ("priorSetupFailure",toJson "interpreted controller import exceeded768MiB before any service/search; native thin entry instead"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",(base/"local-completion-build").toString,
    source.toString,build.toString,"tools.research.PostFocusProbe",(base/"post-focus-profile-settings.json").toString]
  IO.FS.writeFile (source/"tools/research/PostFocusProbe.lean") (← IO.FS.readFile (workspace/"tools/research/PostFocusProbe.lean"))
  guard "post-focus-profile-build1" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"post-focus-profile-settings.json").toString]
  guard tag #["/usr/bin/env","LEAN_NUM_THREADS=1",(build/"StudyMain").toString,"profile"]
def collect (name : String) : IO Unit := do
  drained
  let g ← read (base/(name++".guard.json"))
  check (g.getObjValD "state" == toJson "finished" && g.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "profile is live"
  let log := fun suffix => do
    let path := base/(name++suffix)
    if ← path.pathExists then return toJson (← IO.FS.readFile path)
    return Json.null
  write (folder/(name++".json")) (Json.mkObj [("guard",g),("stdout",← log ".stdout"),("stderr",← log ".stderr")])
  if name == tag then
    write (folder/"profile.json") (Json.mkObj [("guard",g),("result",← read (output/"result.json")),
      ("records",← read (output/"records.json")),("shutdown",← read (output/"shutdown.json")),
      ("publisherShutdown",← read (output/"publisher-shutdown.json")),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def sealProduct (label : String := "") : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  let run := fun args => do discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",audit]++args)
  run #["inspect",build.toString,(folder/(label++"closure.json")).toString]
  run #["common-sources",(base/"local-completion-build").toString,build.toString,(folder/(label++"sources.json")).toString]
  let proof ← read (folder/(label++"sources.json"))
  check (proof.getObjValD "commonSourcesUnchanged" == toJson true && proof.getObjValD "allProductCorePresent" == toJson true)
    "profile supervisor changed the product core"
partial def missingSources (origin target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target
  for entry in ← origin.readDir do
    if ← entry.path.isDir then missingSources entry.path (target/entry.fileName)
    else if entry.fileName.endsWith ".lean" && !(← (target/entry.fileName).pathExists) then
      IO.FS.writeFile (target/entry.fileName) (← IO.FS.readFile entry.path)
def support : IO Unit := do
  drained
  let previous ← read (base/"post-focus-profile-build1.guard.json")
  check (previous.getObjValD "state" == toJson "finished" && previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "build is live"
  missingSources (base/"local-completion-auditor-source") source
  let path := base/"post-focus-profile-settings.json"
  let settings ← read path
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  write path (settings.setObjVal! "parents" (toJson (#[ (base/"local-completion-auditor-build").toString]++parents)))
  guard "post-focus-profile-build2" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,path.toString]
def prepareReplay : IO Unit := do
  drained
  let previous ← read (base/(tag++".guard.json"))
  check (previous.getObjValD "state" == toJson "finished" && previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "profile is live"
  IO.FS.writeFile (source/"tools/research/PostFocusProbe.lean") (← IO.FS.readFile (workspace/"tools/research/PostFocusProbe.lean"))
  guard "post-focus-profile-build3" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"post-focus-profile-settings.json").toString]
  guard "post-focus-capture1" #["/usr/bin/env","LEAN_NUM_THREADS=1",(build/"StudyMain").toString,"capture"]
  guard "post-focus-pure-replay1" #["/usr/bin/env","LEAN_NUM_THREADS=1",(build/"StudyMain").toString,"replay",
    (base/"post-focus-replay-result/selector-input.json").toString,(base/"post-focus-replay-result/pure.json").toString]
def preparePhases : IO Unit := do
  drained
  let previous ← read (base/"post-focus-pure-replay1.guard.json")
  check (previous.getObjValD "state" == toJson "finished" && previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "pure replay is live"
  IO.FS.writeFile (source/"tools/research/PostFocusProbe.lean") (← IO.FS.readFile (workspace/"tools/research/PostFocusProbe.lean"))
  guard "post-focus-profile-build4" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"post-focus-profile-settings.json").toString]
  guard "post-focus-phases1" #["/usr/bin/env","LEAN_NUM_THREADS=1",(build/"StudyMain").toString,"phases",
    (base/"post-focus-replay-result/selector-input.json").toString,(base/"post-focus-replay-result/phases.json").toString]
def compactRecords (records : Json) : IO Json := do
  let rows ← IO.ofExcept records.getArr?
  return toJson (rows.filter fun row => ["source-plan-profile.json","render-client-profile.json",
    "render-automatic-profile.json","provider-keyed-inputs.json","source-views-profile.json","operation-service.json",
    "search.json","search-phase-semantic.json","server-envelope-profile.json"].contains
      ((row.getObjValAs? String "name").toOption.getD ""))
def summarize : IO Unit := do
  drained
  let path := folder/"profile.json"
  let profile ← read path
  write path (profile.setObjVal! "records" (← compactRecords (profile.getObjValD "records")))
  let capture := base/"post-focus-replay-result"
  let records ← IO.ofExcept (← read (capture/"records.json")).getArr?
  let stagePrefix := "selection-selectionWitness-compiledSelected-"
  let parts : Array (Nat × Json) := records.filterMap fun row => do
    let name ← (row.getObjValAs? String "name").toOption
    if !name.startsWith stagePrefix || !name.endsWith ".json" then none else do
      let index ← ((name.drop stagePrefix.length).toString.dropEnd 5).toString.toNat?
      some (index,(row.getObjValD "record").getObjValD "data")
  let parts := parts.qsort (fun first second => first.1 < second.1)
  for index in [:parts.size] do
    check ((parts[index]?).map Prod.fst == some index) "compiled selection lost a diagnostic part"
  let chosen := parts.flatMap (fun part => part.2.getArr?.toOption.getD #[])
  let pureResult ← read (capture/"pure.json")
  check (!chosen.isEmpty && toJson chosen == pureResult.getObjValD "selected") "pure replay differs from the actual ordered selection"
  let problem := capture/"selector-input.json"
  let digest := ((← command "/usr/bin/shasum" #["-a","256",problem.toString]).splitOn " ").headD ""
  IO.FS.writeFile (folder/"selector-input.json") (← IO.FS.readFile problem)
  write (folder/"replay.json") (Json.mkObj [("inputSha256",toJson digest),
    ("captureResult",← read (capture/"result.json")),("captureGuard",← read (base/"post-focus-capture1.guard.json")),
    ("captureProfiles",← compactRecords (toJson records)),("pureResult",pureResult),
    ("pureGuard",← read (base/"post-focus-pure-replay1.guard.json")),("phases",← read (capture/"phases.json")),
    ("phasesGuard",← read (base/"post-focus-phases1.guard.json")),("orderedSelectionMatchesActualHook",toJson true),
    ("captureFailureIsNotDeliverySuccess",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def prepareMembership : IO Unit := do
  drained
  let previous ← read (base/"post-focus-phases1.guard.json")
  check (previous.getObjValD "state" == toJson "finished" && previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "phase replay is live"
  let target := base/"selection-membership-source"
  let native := base/"selection-membership-build"
  let settings := base/"selection-membership-settings.json"
  check (!(← target.pathExists) && !(← native.pathExists)) "preserve previous membership candidate"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",build.toString,
    target.toString,native.toString,"tools.research.PostFocusProbe",settings.toString]
  IO.FS.writeFile (target/"tools/research/PostFocusProbe.lean") (← IO.FS.readFile (workspace/"tools/research/PostFocusProbe.lean"))
  for name in ["WinnerUpdates","VerifiedWinnerCoverage"] do
    let patched ← IO.Process.output {cmd := "/usr/bin/patch",args := #["-s","-p1","-i",(folder/(name++".patch")).toString],cwd := some target}
    check (patched.exitCode == 0) ("frozen membership patch rejected: "++name)
  write (folder/"membership-plan.json") (Json.mkObj [("inputSha256",(← read (folder/"replay.json")).getObjValD "inputSha256"),
    ("change",toJson "carry certified selected-membership map through winner resolution and updates"),
    ("preserved",toJson "full ordered greedy selection, stable ties, singleton comparison, weights, costs, source/certification domain"),
    ("comparison",toJson "three paired native runs; AB,BA,AB; all3038actual selected ordinals exact"),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  guard "selection-membership-build1" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,settings.toString]
  guard "selection-membership-comparison1" #["/usr/bin/env","LEAN_NUM_THREADS=1",(native/"StudyMain").toString,"comparison",
    (folder/"selector-input.json").toString,(base/"selection-membership-comparison.json").toString]
def sealMembership : IO Unit := do
  drained
  let native := base/"selection-membership-build"
  let target := base/"selection-membership-source"
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  let run := fun args => do discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",audit]++args)
  run #["inspect",native.toString,(folder/"membership-closure.json").toString]
  run #["compare-sources",build.toString,native.toString,(folder/"membership-sources.json").toString,
    "tools.WinnerUpdates","tools.VerifiedWinnerCoverage"]
  for name in ["WinnerUpdates","VerifiedWinnerCoverage"] do
    let relative := "tools/"++name++".lean"
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (source/relative).toString,(target/relative).toString]}
    check (result.exitCode == 1) "expected membership patch missing"
    IO.FS.writeFile (folder/(name++".patch")) result.stdout
def collectMembership : IO Unit := do
  drained
  let g ← read (base/"selection-membership-comparison1.guard.json")
  check (g.getObjValD "state" == toJson "finished" && g.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "comparison still runs"
  let report ← read (base/"selection-membership-comparison.json")
  let rows ← IO.ofExcept (report.getObjValAs? (Array Json) "rows")
  check (g.getObjValD "exitCode" == toJson (0 : Nat) && report.getObjValD "completed" == toJson true && rows.size == 6 &&
    rows.all (fun row => row.getObjValD "orderedSelectionEqual" == toJson true)) "membership native comparison failed"
  write (folder/"membership-comparison.json") (Json.mkObj [("guard",g),("report",report),("adopted",toJson false),
    ("inputSha256",(← read (folder/"replay.json")).getObjValD "inputSha256"),
    ("sources",(← read (folder/"membership-sources.json")).getObjValD "candidateRuntimeSha256")])
def cleanup : IO Unit := do
  drained
  check ((← read (folder/"membership-comparison.json")).getObjValD "adopted" == toJson false) "retain unaudited comparison"
  let record := folder/"cleanup.json"
  check (!(← record.pathExists)) "preserve cleanup evidence"
  let data := base/"real-source-search-read-trial-result/data"
  let mut removed : Array String := #[]
  for root in [output,base/"post-focus-replay-result"] do
    for name in ["shutdown.json","publisher-shutdown.json"] do
      let stopped ← read (root/name)
      check (stopped.getObjValD "processExited" == toJson true && stopped.getObjValD "daemonExitCode" == toJson (0 : Nat)) "retain live profile data"
    let session ← read (root/"session.json")
    check (session.getObjValD "data" == toJson data.toString) "profile left its private data scope"
    let name ← IO.ofExcept (session.getObjValAs? String "session")
    check (name.startsWith "post-focus-" && name.length == 75 && name.toList.all (fun c => c.isAlphanum || c == '-')) "session escaped profile scope"
    let sessions := data/"sessions"/name
    if ← sessions.pathExists then
      IO.FS.removeDirAll sessions
      removed := removed.push sessions.toString
    let receipts ← IO.ofExcept (← read (root/"receipts.json")).getArr?
    for id in receipts do
      let id ← IO.ofExcept id.getStr?
      check (id.length == 64 && id.toList.all Char.isAlphanum) "receipt escaped profile scope"
      let path := data/"receipts"/id
      if ← path.pathExists then
        IO.FS.removeDirAll path
        removed := removed.push path.toString
  IO.FS.removeDirAll output
  removed := removed.push output.toString
  let capture := base/"post-focus-replay-result"
  for entry in ← capture.readDir do
    -- Current component executable names this tiny expected-selection file.
    -- Keep it until the normal runtime replaces that entry.
    if entry.fileName == "pure.json" then continue
    if ← entry.path.isDir then IO.FS.removeDirAll entry.path else IO.FS.removeFile entry.path
    removed := removed.push entry.path.toString
  let executable := build/"StudyMain"
  let expected := (← read (folder/"phases-sources.json")).getObjValD "auditorSha256"
  let digest := ((← command "/usr/bin/shasum" #["-a","256",executable.toString]).splitOn " ").headD ""
  check (expected == toJson digest) "retain changed profile executable"
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!processes.contains executable.toString) "profile process remains live"
  let bytes := (← executable.metadata).byteSize.toNat
  IO.FS.removeFile executable
  removed := removed.push executable.toString
  write record (Json.mkObj [("removed",toJson removed),("retiredExecutableSha256",toJson digest),
    ("retiredExecutableBytes",toJson bytes),("currentCandidateOriginalsProjectCacheModelsNativeSourcesObjectsInterfacesRetained",toJson true),
    ("minimalExpectedSelectionRetainedForCurrentEntry",toJson true),("archived",toJson false)])
def product : IO Unit := do
  drained
  let comparison ← read (folder/"membership-comparison.json")
  check ((comparison.getObjValD "report").getObjValD "completed" == toJson true) "component gate required"
  let native := base/"selection-membership-build"
  let target := base/"selection-membership-source"
  let executable := native/"StudyMain"
  let digest := ((← command "/usr/bin/shasum" #["-a","256",executable.toString]).splitOn " ").headD ""
  check (comparison.getObjValD "sources" == toJson digest) "component executable changed"
  let transition := folder/"membership-component-retirement.json"
  check (!(← transition.pathExists)) "retain previous product transition"
  let record := Json.mkObj [("sha256",toJson digest),("path",toJson executable.toString),
    ("bytes",toJson (← executable.metadata).byteSize.toNat),("completed",toJson false),("archived",toJson false)]
  write transition record
  IO.FS.removeFile executable
  write transition (record.setObjVal! "completed" (toJson true))
  let entry := "tools/research/ReplayReadinessChecks.lean"
  IO.FS.writeFile (target/entry) (← IO.FS.readFile (base/"local-completion-source"/entry))
  missingSources (base/"local-completion-source") target
  let settings := base/"selection-membership-settings.json"
  write settings ((← read settings).setObjVal! "mainModule" (toJson "tools.research.ReplayReadinessChecks"))
  let oldExpected := base/"post-focus-replay-result"
  if ← oldExpected.pathExists then IO.FS.removeDirAll oldExpected
  guard "selection-membership-runtime1" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,settings.toString]
def supportRuntime : IO Unit := do
  drained
  let previous ← read (base/"selection-membership-runtime1.guard.json")
  check (previous.getObjValD "state" == toJson "finished" && previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "runtime build is live"
  missingSources (base/"local-completion-source") (base/"selection-membership-source")
  guard "selection-membership-runtime2" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"selection-membership-settings.json").toString]
def sealRuntime : IO Unit := do
  drained
  let native := base/"selection-membership-build"
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  let run := fun args => do discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",audit]++args)
  run #["inspect",native.toString,(folder/"membership-runtime-closure.json").toString]
  run #["compare-sources",(base/"local-completion-build").toString,native.toString,(folder/"membership-runtime-sources.json").toString,
    "tools.WinnerUpdates","tools.VerifiedWinnerCoverage"]
  let entry := "tools/research/ReplayReadinessChecks.lean"
  check ((← IO.FS.readFile (base/"selection-membership-source"/entry)) == (← IO.FS.readFile (base/"local-completion-source"/entry))) "runtime entry changed"
def prepareActual : IO Unit := do
  drained
  check ((← read (folder/"membership-runtime-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "normal runtime must be sealed"
  let destination := workspace/"docs/candidates/selection-membership"
  IO.FS.createDirAll destination
  let target := base/"selection-membership-auditor-source"
  let native := base/"selection-membership-auditor-build"
  let settings := base/"selection-membership-auditor-settings.json"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",(workspace/"tools/research/RealSourceStudy.lean").toString,
    "prepare-auditor",(base/"selection-membership-build").toString,target.toString,native.toString,settings.toString]
  missingSources (base/"local-completion-auditor-source") target
  IO.FS.writeFile (target/"tools/research/RealDeliveryProbe.lean") (← IO.FS.readFile (workspace/"tools/research/RealDeliveryProbe.lean"))
  guard "selection-membership-auditor-build1" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,settings.toString]
  let runtime := base/"selection-membership-build/StudyMain"
  let digest := ((← command "/usr/bin/shasum" #["-a","256",runtime.toString]).splitOn " ").headD ""
  let installation := base/"selection-membership-prefix"
  write (base/"selection-membership-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson runtime.toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  guard "selection-membership-install1" #[(native/"StudyMain").toString,"install-prefix",(base/"selection-membership-install.json").toString]
  let original := base/"real-source-search-read-input.json"
  let originalHash := ((← command "/usr/bin/shasum" #["-a","256",original.toString]).splitOn " ").headD ""
  let result := base/"selection-membership-cells-result"
  let mut probes := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      probes := probes.push (Json.mkObj [
        ("originalInput",Json.mkObj [("path",toJson original.toString),("sha256",toJson originalHash)]),
        ("runtime",Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)]),
        ("pluginRoot",toJson (installation/"share/eggshell/codex-plugin").toString),("topic",toJson topic),
        ("destination",toJson (result/s!"topic-{topic}-chat-{repetition}").toString),
        ("requireSharedKeyedImage",toJson true),("captureReply",toJson false)])
  write (base/"selection-membership-cells.json") (Json.mkObj [("output",toJson result.toString),("probes",toJson probes)])
  guard "selection-membership-cells1" #["/usr/bin/env","LEAN_NUM_THREADS=1",(native/"StudyMain").toString,
    "cells",(base/"selection-membership-cells.json").toString]
def sealActual : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/selection-membership"
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  let native := base/"selection-membership-auditor-build"
  let run := fun args => do discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",audit]++args)
  run #["inspect",native.toString,(destination/"auditor-closure.json").toString]
  run #["common-sources",(base/"selection-membership-build").toString,native.toString,(destination/"auditor-sources.json").toString]
  let sources ← read (destination/"auditor-sources.json")
  check (sources.getObjValD "commonSourcesUnchanged" == toJson true && sources.getObjValD "allProductCorePresent" == toJson true) "actual hook auditor changed the core"
def main (args : List String) : IO Unit := match args with
  | ["setup"] => setup
  | ["seal"] => sealProduct
  | ["seal-replay"] => sealProduct "replay-"
  | ["support"] => support
  | ["prepare-replay"] => prepareReplay
  | ["prepare-phases"] => preparePhases
  | ["seal-phases"] => sealProduct "phases-"
  | ["summarize"] => summarize
  | ["prepare-membership"] => prepareMembership
  | ["seal-membership"] => sealMembership
  | ["collect-membership"] => collectMembership
  | ["cleanup"] => cleanup
  | ["product"] => product
  | ["seal-runtime"] => sealRuntime
  | ["support-runtime"] => supportRuntime
  | ["prepare-actual"] => prepareActual
  | ["seal-actual"] => sealActual
  | ["collect",name] => collect name
  | _ => throw (IO.userError "setup/collect required")
end PostFocusStudy
def main := PostFocusStudy.main
