import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace RemainingSourceStudy
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := project/"docs/candidates/remaining-source"
def check (b : Bool) (s : String) : IO Unit := unless b do throw (IO.userError s)
def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= (IO.ofExcept ∘ Json.parse)
def write (p : System.FilePath) (v : Json) : IO Unit := IO.FS.writeFile p v.compress
def command (cmd : String) (args : Array String) : IO String := do
  let r ← IO.Process.output {cmd,args,cwd := some project}
  check (r.exitCode == 0) (r.stdout++r.stderr)
  return r.stdout
def hash (p : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",p.toString]).splitOn " ").headD ""
def idle : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.trimAscii.toString.startsWith ((base/"controller/StudyMain").toString++" guard ") ||
    row.trimAscii.toString.startsWith ((base/"resource-budget-guard-build/StudyMain").toString++" "))) "resource guard is live"
def component := base/"remaining-source-component-build"
def prepareComponent : IO Unit := do
  idle
  check (!(← component.pathExists) && !(← (base/"remaining-source-component-source").pathExists)) "fresh exact-subtraction component required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"score-prepare-runtime-build").toString,(base/"remaining-source-component-source").toString,component.toString,
    "tools.research.RemainingSourceChecks",(base/"remaining-source-component-settings.json").toString]
  for name in ["RemainingSource","RemainingSourceChecks"] do
    IO.FS.writeFile (base/"remaining-source-component-source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  IO.FS.createDirAll folder
  let proof ← command (compiler/"bin/lean").toString #["-j1","-M768","-DwarningAsError=true",
    (project/"tools/research/RemainingSource.lean").toString]
  check (!proof.contains "sorryAx") "remaining-source proof uses an admitted statement"
  write (folder/"proofs.json") (Json.mkObj [("kernelChecked",toJson true),("axioms",toJson proof),
    ("sourceSha256",toJson (← hash (project/"tools/research/RemainingSource.lean")))])
  write (folder/"plan.json") (Json.mkObj [("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("referenceRuntimeSha256",toJson (← hash (base/"score-prepare-runtime-build/StudyMain"))),
    ("change",toJson "exact original-source subtraction: empty history is identity; indexed acknowledged keys and one content identity per file"),
    ("unchanged",toJson "row/plan equality, row order, complete/no-refill decisions, rank, candidate domain, quality/byte budget, authority, workers and 30s deadline"),
    ("gates",toJson #["kernel equality and actual-source component","full matching native runtime","six actual hooks","4/16 then changed80","matched inclusive-token/quality adoption gate"])])

def setupComponent (mode tag : String) : IO Unit := do
  idle
  check (tag.startsWith "remaining-source-component-") "component tag escaped scope"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve prior component attempt"
  let args ← match mode with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"remaining-source-component-settings.json").toString]
    | "run" => do
      let witness ← read (folder/"component-witness.json")
      check (witness.getObjValD "runtimeSha256" == toJson (← hash (component/"StudyMain"))) "component changed after source audit"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/"real-source-search-read-trial-result/data").toString,
        (component/"StudyMain").toString,(base/"remaining-source-component-result.json").toString]
    | _ => throw (IO.userError "build or run required")
  write path (Json.mkObj [("command",toJson args),("cwd",toJson project.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def auditComponent : IO Unit := do
  idle
  let guard ← read (base/"remaining-source-component-build2.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "component builder has not succeeded and drained"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",component.toString,
    (folder/"component-closure.json").toString]
  let mut inputs := #[]
  for name in ["RemainingSource","RemainingSourceChecks"] do
    let witness ← IO.ofExcept (fromJson? (← read (component/("tools_research_"++name++".source"))) :
      Except String (String × Array (String × String)))
    let path := project/"tools/research"/(name++".lean")
    check (witness.1 == (← IO.FS.readFile path)) "actual component source differs from repository"
    inputs := inputs.push (name,← hash path)
  write (folder/"component-witness.json") (Json.mkObj [("runtimeSha256",toJson (← hash (component/"StudyMain"))),
    ("nativeSourcesMatchRepository",toJson true),("sources",toJson inputs),("componentOnlyNotFullProduct",toJson true)])

def collectComponent : IO Unit := do
  idle
  let guard ← read (base/"remaining-source-component-run1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "component has not completed and drained"
  let report ← read (base/"remaining-source-component-result.json")
  check (report.getObjValD "allExact" == toJson true && report.getObjValD "originalSourceUnchanged" == toJson true)
    "component changed original source or subtraction result"
  write (folder/"component.json") (Json.mkObj [("guard",guard),("report",report),("adopted",toJson false)])

def prepareRuntime : IO Unit := do
  idle
  check (((← read (folder/"component.json")).getObjValD "report").getObjValD "allExact" == toJson true)
    "exact actual-source component required"
  let source := base/"remaining-source-source"
  let build := base/"remaining-source-runtime-build"
  check (!(← source.pathExists) && !(← build.pathExists)) "fresh isolated normal runtime required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"score-prepare-runtime-build").toString,source.toString,build.toString,
    "tools.research.ReplayReadinessChecks",(base/"remaining-source-settings.json").toString]
  IO.FS.writeFile (source/"tools/research/RemainingSource.lean")
    (← IO.FS.readFile (project/"tools/research/RemainingSource.lean"))
  let path := source/"Eggshell/Handoff.lean"
  let before ← IO.FS.readFile path
  let importAnchor := "public import tools.ExactMemo\n"
  let keysAnchor := "deliveredGraphs := keys.eraseDups,"
  check ((before.splitOn importAnchor).length == 2 && (before.splitOn keysAnchor).length == 2)
    "actual source reconciliation consumer changed"
  IO.FS.writeFile path (before.replace importAnchor (importAnchor++"public import tools.research.RemainingSource\n")
    |>.replace keysAnchor "deliveredGraphs := Research.DeliveryKeys.distinct keys,")
  write (folder/"runtime-plan.json") (Json.mkObj [("parentRuntimeSha256",toJson (← hash (base/"score-prepare-runtime-build/StudyMain"))),
    ("changes",toJson #["proof-rewritten exact source subtraction","final delivered keys use the existing definitionally-equal compiled stable uniqueness"]),
    ("newScoreOrSelectionRules",toJson false),("newCacheOrQueue",toJson false),("adopted",toJson false)])

def setupRuntime : IO Unit := do
  idle
  let settings := base/"remaining-source-runtime-build.guard-settings.json"
  check (!(← settings.pathExists) && !(← (folder/"runtime.json").pathExists)) "preserve existing or validated build"
  write settings (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"remaining-source-settings.json").toString]),
    ("cwd",toJson project.toString),("record",toJson (base/"remaining-source-runtime-build.guard.json").toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def auditRuntime : IO Unit := do
  idle
  let build := base/"remaining-source-runtime-build"
  let guard ← read (base/"remaining-source-runtime-build.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "actual normal build has not succeeded and drained"
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",build.toString,(folder/"native-closure.json").toString],
      #["compare-sources",(base/"score-prepare-runtime-build").toString,build.toString,
        (folder/"native-sources.json").toString,"Eggshell.Handoff","+tools.research.RemainingSource"]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "unexpected normal-source change"
  write (folder/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
    ("guard",guard),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def hexadecimal (value : String) : Option Nat := value.toList.foldlM (fun n c => do
  let digit ← if '0' ≤ c && c ≤ '9' then some (c.toNat-'0'.toNat)
    else if 'a' ≤ c && c ≤ 'f' then some (c.toNat-'a'.toNat+10) else none
  return n*16+digit) 0
def auditRewrite : IO Unit := do
  idle
  let object := base/"remaining-source-runtime-build/Eggshell_Handoff.o"
  let columns := fun (line : String) => (line.replace "\t" " ").splitOn " " |>.filter (! ·.isEmpty)
  let symbols := ((← command "/usr/bin/nm" #["-gU",object.toString]).splitOn "\n").filterMap fun row => do
    let fields := columns row
    return (← hexadecimal (← fields[0]?),← fields[2]?)
  let relocations := ((← command "/usr/bin/otool" #["-rv",object.toString]).splitOn "\n").filterMap fun row => do
    let fields := columns row
    if !fields.contains "BR26" then none else some (← hexadecimal (← fields[0]?),← fields.getLast?)
  let mut results := #[]
  for (caller,target) in [("_l_Eggshell_Plugin_DeliveryPart_remaining","_l_Eggshell_Synapses_CanonicalSource_Delivery_remainingSource"),
      ("_l_Eggshell_Plugin_Handoff_reconcileDelivery","_l_Eggshell_Research_DeliveryKeys_distinctCompiled")] do
    let some start := symbols.find? (·.2 == caller) | throw (IO.userError ("actual caller absent: "++caller))
    let some last := (symbols.filter (fun row => start.1 < row.1)).mergeSort (fun a b => a.1 ≤ b.1) |>.head? |
      throw (IO.userError "caller symbol boundary absent")
    let calls := relocations.filter fun row => start.1 ≤ row.1 && row.1 < last.1
    check (calls.any (·.2 == target)) ("proven implementation is disconnected: "++target)
    results := results.push (Json.mkObj [("caller",toJson caller),("target",toJson target),("calls",toJson calls)])
  write (folder/"native-rewrite.json") (Json.mkObj [("objectSha256",toJson (← hash object)),
    ("consumers",toJson results),("bothCompiledPathsPresent",toJson true)])

partial def copyMissing (fromDir toDir : System.FilePath) : IO Unit := do
  IO.FS.createDirAll toDir
  for entry in ← fromDir.readDir do
    if entry.fileName == ".lake" then continue
    if (← entry.path.symlinkMetadata).type == .dir then copyMissing entry.path (toDir/entry.fileName)
    else if entry.fileName.endsWith ".lean" && !(← (toDir/entry.fileName).pathExists) then
      IO.FS.writeFile (toDir/entry.fileName) (← IO.FS.readFile entry.path)
def prepareAuditor : IO Unit := do
  idle
  check ((← read (folder/"native-rewrite.json")).getObjValD "bothCompiledPathsPresent" == toJson true)
    "actual native consumer check required"
  let destination := base/"remaining-source-auditor-source"
  check (!(← destination.pathExists)) "fresh actual-hook auditor required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"score-prepare-auditor-build").toString,destination.toString,(base/"remaining-source-auditor-build").toString,
    "tools.research.ScorePrepareControls",(base/"remaining-source-auditor-settings.json").toString]
  let source := base/"remaining-source-source"
  for relative in ["Eggshell","tools","tests"] do copyMissing (source/relative) (destination/relative)
  for relative in ["Eggshell/Handoff.lean","tools/research/RemainingSource.lean"] do
    IO.FS.writeFile (destination/relative) (← IO.FS.readFile (source/relative))
  let frozen ← IO.ofExcept (fromJson? (← read (base/"score-prepare-auditor-build/tools_research_ScorePrepareControls.source")) :
    Except String (String × Array (String × String)))
  IO.FS.writeFile (destination/"tools/research/ScorePrepareControls.lean") frozen.1

def setupAuditor : IO Unit := do
  idle
  let path := base/"remaining-source-auditor-build.guard-settings.json"
  check (!(← path.pathExists) && !(← (folder/"auditor-sources.json").pathExists)) "preserve existing or validated auditor"
  write path (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"remaining-source-auditor-settings.json").toString]),
    ("cwd",toJson project.toString),("record",toJson (base/"remaining-source-auditor-build.guard.json").toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def auditAuditor : IO Unit := do
  idle
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  let auditor := base/"remaining-source-auditor-build"
  for args in [#["inspect",auditor.toString,(folder/"auditor-closure.json").toString],
    #["common-sources",(base/"remaining-source-runtime-build").toString,auditor.toString,(folder/"auditor-sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let found ← read (folder/"auditor-sources.json")
  check (found.getObjValD "allProductCorePresent" == toJson true && found.getObjValD "commonSourcesUnchanged" == toJson true)
    "actual-hook auditor omitted or changed product core"

def prepareDelivery : IO Unit := do
  idle
  let gate ← read (folder/"auditor-sources.json")
  check (gate.getObjValD "allProductCorePresent" == toJson true && gate.getObjValD "commonSourcesUnchanged" == toJson true)
    "actual matching hook auditor required"
  let installation := base/"remaining-source-prefix"
  let runtime := base/"remaining-source-runtime-build/StudyMain"
  let digest ← hash runtime
  write (base/"remaining-source-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson runtime.toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let previous ← read (base/"score-prepare-cells.json")
  let output := base/"remaining-source-cells-result"
  let probes ← IO.ofExcept (previous.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let name := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName.get!
    return probe.setObjVal! "destination" (toJson (output/name).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  write (base/"remaining-source-cells.json") (previous.setObjVal! "output" (toJson output.toString)|>.setObjVal! "probes" (toJson probes))

def setupDelivery (mode : String) : IO Unit := do
  idle
  check (["install","cells"].contains mode) "install or cells required"
  let tag := "remaining-source-"++mode++"1"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve existing actual-hook attempt"
  write path (Json.mkObj [("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
      (base/"remaining-source-auditor-build/StudyMain").toString,
      (if mode == "install" then "install-prefix" else "cells"),(base/("remaining-source-"++mode++".json")).toString]),
    ("cwd",toJson project.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def sealInstalled : IO Unit := do
  idle
  let binary := base/"remaining-source-prefix/libexec/eggshell"
  let runtime := base/"remaining-source-runtime-build/StudyMain"
  let digest ← hash runtime
  check ((← hash binary) == digest) "installed runtime differs from the checked product"
  let temporary := binary.withExtension "shared"
  check (!(← temporary.pathExists)) "temporary installed link exists"
  discard <| command "/bin/ln" #[runtime.toString,temporary.toString]
  IO.FS.rename temporary binary
  write (folder/"installed-runtime.json") (Json.mkObj [("sha256",toJson digest),("sameImmutableInode",toJson true)])

def cleanupComponentAndCells : IO Unit := do
  idle
  let evidence ← read (folder/"delivery-cells.json")
  check (evidence.getObjValD "actualDeliveryAllSixPassed" == toJson true &&
    (evidence.getObjValD "guard").getObjValD "ownedPids" == toJson (#[] : Array Nat)) "completed delivery evidence required"
  check (((← read (folder/"component.json")).getObjValD "report").getObjValD "allExact" == toJson true)
    "retain the original-source component evidence"
  for entry in ← base.readDir do
    let response := entry.path/"runtime.rsp"
    if entry.path != component && (← response.pathExists) then
      check (!(← IO.FS.readFile response).contains (component.toString++"/")) "another native build depends on this component"
  let mut targets := #[component,base/"remaining-source-component-source",base/"remaining-source-component-result.json"]
  let data := base/"real-source-search-read-trial-result/data"
  for topic in [1:4] do
    for repetition in [:2] do
      let cell := base/"remaining-source-cells-result"/s!"topic-{topic}-chat-{repetition}"
      let id ← IO.ofExcept ((← read (cell/"receipt.json")).getObjValAs? String "id")
      let requestFile ← IO.ofExcept ((← read (cell/"audit-input.json")).getObjValAs? String "request")
      check (requestFile == (cell/"hook/stdin").toString) "delivery request escaped checked cell"
      let session ← IO.ofExcept ((← read (.mk requestFile)).getObjValAs? String "session_id")
      check (id.length == 64 && id.toList.all Char.isAlphanum && session.startsWith "real-source-" && session.length == 76)
        "delivery cleanup escaped its generated scope"
      targets := targets++#[data/"receipts"/id,data/"sessions"/session,cell/"receipt.json"]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "remaining-source-" &&
      (entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr") &&
      !entry.fileName.contains "capacity" then targets := targets.push entry.path
  let record := Json.mkObj [("removed",toJson (targets.map (·.toString))),
    ("currentRuntimeAuditorParentOriginalDbProjectCacheModelAndBodiesRetained",toJson true),("archived",toJson false)]
  write (folder/"component-cells-cleanup.json") (record.setObjVal! "completed" (toJson false))
  for path in targets do if ← path.pathExists then
    if ← path.isDir then IO.FS.removeDirAll path else IO.FS.removeFile path
  write (folder/"component-cells-cleanup.json") (record.setObjVal! "completed" (toJson true))

/-- Use the already audited thin client. This is a bounded CPU diagnostic,
not another unchanged eighty-client gate or an adoption measurement. -/
def prepareCpu (tag : String := "cpu2") : IO Unit := do
  idle
  check (tag == "cpu2") "fixed fresh CPU diagnostic required"
  let rejected ← read (base/"remaining-source-cpu.guard.json")
  check (rejected.getObjValD "state" == toJson "finished" && rejected.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "preserve the rejected-before-load invocation"
  write (folder/"cpu-rejected-before-load.json") (Json.mkObj [("guard",rejected),
    ("stderr",toJson (← IO.FS.readFile (base/"remaining-source-cpu.stderr"))),
    ("reason",toJson "thin client accepts four-client diagnosis only; sixteen was rejected before service/model/client start"),
    ("loadStarted",toJson false)])
  let destination := base/("remaining-source-"++tag++"-result")
  let inputPath := base/("remaining-source-"++tag++"-input.json")
  check (!(← destination.pathExists) && !(← inputPath.pathExists)) "preserve the previous CPU diagnostic"
  let capacity ← read (folder/"capacity-sources.json")
  check (capacity.getObjValD "commonSourcesUnchanged" == toJson true &&
    capacity.getObjValD "auditorSha256" == toJson (← hash (base/"remaining-source-capacity-build/StudyMain")))
    "actual matching thin client required"
  let input ← read (base/"remaining-source-capacity-small-input.json")
  let environment ← IO.ofExcept (input.getObjValAs? (Array (String × Option String)) "environment")
  let environment := (environment.filter (·.1 != "EGGSHELL_TRACE_SERVICE_PROFILE")).map
    (fun (name,value) => (name,if name == "EGGSHELL_CONFIG" then some (destination/"config.toml").toString else value))
    |>.push ("EGGSHELL_TRACE_SERVICE_PROFILE",some "1")
  write inputPath (input.setObjVal! "output" (toJson destination.toString)
    |>.setObjVal! "config" (toJson (destination/"config.toml").toString)
    |>.setObjVal! "environment" (toJson environment)|>.setObjVal! "counts" (toJson (#[(4 : Nat)]))
    |>.setObjVal! "diagnostic" (toJson true)|>.setObjVal! "gate" Json.null)
  let unset := environment.toList.flatMap fun (name,value) => if value.isNone then ["-u",name] else []
  let args := #["/usr/bin/env"]++unset.toArray++#["LEAN_NUM_THREADS=1"]++
    environment.filterMap (fun (name,value) => value.map (fun value => name++"="++value))++
    #[(base/"remaining-source-capacity-build/StudyMain").toString,inputPath.toString]
  write (base/("remaining-source-"++tag++".guard-settings.json")) (Json.mkObj [("command",toJson args),
    ("cwd",toJson project.toString),("record",toJson (base/("remaining-source-"++tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))])
  write (folder/"cpu-plan.json") (Json.mkObj [("sameProductAndBodies",toJson true),("clients",toJson (4 : Nat)),
    ("observerMayAffectTimings",toJson true),("adoptionOrUnchangedEightyRetry",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("inputSha256",toJson (← hash inputPath))])

def sampleCpu : IO Unit := do
  let destination := base/"remaining-source-cpu2-result"
  let marker := destination/"phase-4/initializations.json"
  let guardPath := base/"remaining-source-cpu2.guard.json"
  let first ← IO.monoMsNow
  repeat
    let guard ← read guardPath
    check (guard.getObjValD "state" == toJson "running") "CPU diagnostic is not live"
    if ← marker.pathExists then break
    check ((← IO.monoMsNow)-first < 60000) "four-client wave did not start within the diagnostic bound"
    IO.sleep 100
  let endpoint ← read (base/"real-source-search-read-trial-result/data/publisher/endpoint.json")
  let pid ← IO.ofExcept (endpoint.getObjValAs? Nat "pid")
  let expected := (base/"remaining-source-prefix/libexec/eggshell").toString
  let actual ← command "/bin/ps" #["-p",toString pid,"-o","comm="]
  check (actual.trimAscii.toString == expected) "sampling target is another product"
  IO.sleep 1000
  let output := destination/"cpu-sample.txt"
  let result ← IO.Process.output {cmd := "/usr/bin/sample",args := #[toString pid,"4","10","-mayDie","-file",output.toString]}
  let digest ← if ← output.pathExists then hash output else pure ""
  write (folder/"cpu-sampler.json") (Json.mkObj [("pid",toJson pid),("product",toJson expected),
    ("exitCode",toJson result.exitCode.toNat),("stdout",toJson result.stdout),("stderr",toJson result.stderr),
    ("output",toJson output.toString),("observerAffectsTimings",toJson true),
    ("outputSha256",toJson digest)])

def cleanupCpu : IO Unit := do
  idle
  let evidence ← read (folder/"cpu-profile.json")
  let guard := evidence.getObjValD "guard"
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "CPU diagnostic has not succeeded and drained"
  let pid := evidence.getObjValD "publisherPid"
  let sampler ← read (folder/"cpu-sampler.json")
  check (sampler.getObjValD "pid" == pid && sampler.getObjValD "exitCode" == toJson (0 : Nat)) "actual sampling failed"
  let destination := base/"remaining-source-cpu2-result"
  let raw := destination/"cpu-sample.txt"
  check (sampler.getObjValD "outputSha256" == toJson (← hash raw)) "raw CPU sample changed"
  let lines := (← IO.FS.readFile raw).splitOn "\n"
  let collapsed := ((lines.dropWhile (! ·.startsWith "Sort by top of stack, same collapsed")).drop 1).take 50
  let mut anchors : Array Json := #[]
  for i in [:lines.length] do
    let line := lines[i]!
    if line.contains "basePieceAccept_spec__0" || line.contains "RegisterMix_instDecidableValid" then
      anchors := anchors.push (Json.mkObj [("line",toJson (i+1)),("text",toJson ((lines.drop (i-5)).take 7))])
  write (folder/"cpu-observation.json") (Json.mkObj [("sampler",sampler),("collapsedTopStacks",toJson collapsed),
    ("selectedCallPaths",toJson anchors),("observedNotCausalProofOrCpuPercent",toJson true),
    ("productRuntimeSha256",toJson (← hash (base/"remaining-source-runtime-build/StudyMain")))])
  let data := base/"real-source-search-read-trial-result/data"
  let mut targets : Array System.FilePath := #[]
  let primes ← IO.ofExcept (← read (destination/"prime.json")).getArr?
  let clients := ((evidence.getObjValD "report").getObjValD "phases").getArr?.toOption.getD #[]
    |>.flatMap fun phase => (phase.getObjValD "rows").getArr?.toOption.getD #[]
  for row in primes++clients do
    let id ← IO.ofExcept (row.getObjValAs? String "receipt")
    let session ← IO.ofExcept (row.getObjValAs? String "session")
    check (id.length == 64 && id.toList.all Char.isAlphanum && session.startsWith "capacity-" && session.length == 73)
      "CPU diagnostic cleanup escaped its scope"
    targets := targets++#[data/"receipts"/id,data/"sessions"/session]
  for row in (evidence.getObjValD "profiles").getArr?.toOption.getD #[] do
    let id ← IO.ofExcept (row.getObjValAs? String "receiptDirectory")
    check (id.length == 64 && id.toList.all Char.isAlphanum) "CPU profile receipt escaped scope"
    let path := data/"receipts"/id
    if targets.contains path || !(← path.pathExists) then continue
    for entry in ← path.readDir do
      check (entry.fileName.endsWith ".json" && (← read entry.path).getObjValD "pid" == pid)
        "profile directory contains another owner's data"
    targets := targets.push path
  targets := targets++#[destination,base/"remaining-source-cpu-result"]
  for name in ["remaining-source-cpu","remaining-source-cpu2"] do
    for extension in ["stdout","stderr"] do targets := targets.push (base/(name++"."++extension))
  let record := Json.mkObj [("removed",toJson (targets.map (·.toString))),
    ("originalProjectCacheModelProductAndComparisonBodiesRetained",toJson true),("archived",toJson false)]
  write (folder/"cpu-cleanup.json") (record.setObjVal! "completed" (toJson false))
  for path in targets do if ← path.pathExists then
    if ← path.isDir then IO.FS.removeDirAll path else IO.FS.removeFile path
  write (folder/"cpu-cleanup.json") (record.setObjVal! "completed" (toJson true))

def cleanupLogs : IO Unit := do
  idle
  for name in ["cpu-cleanup.json","component-cells-cleanup.json","retired-capacity-helper.json"] do
    check ((← read (folder/name)).getObjValD "completed" == toJson true) "finish owned-data cleanup first"
  let original := base/"real-source-search-read-trial-result/work.egg"
  let retainedInputs := #[base/"remaining-source-runtime-build/StudyMain",base/"remaining-source-auditor-build/StudyMain",
    base/"score-prepare-runtime-build/StudyMain",original/"head",
    original/"2a1ab5766ac89060c477ae3fc9683c9492574ff843d134c01b53d9697a27359e.pages"]
  let before ← retainedInputs.mapM fun path => do return (path.toString,← hash path)
  let mut targets := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "remaining-source-" &&
      (entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr") then
      targets := targets.push (entry.path,(← entry.path.metadata).byteSize.toNat,← hash entry.path)
  for (path,_,_) in targets do IO.FS.removeFile path
  let after ← retainedInputs.mapM fun path => do return (path.toString,← hash path)
  check (before == after) "cleanup changed a current binary or original source"
  write (folder/"raw-logs-cleanup.json") (Json.mkObj [("removed",toJson (targets.map fun (path,bytes,digest) =>
    Json.mkObj [("path",toJson path.toString),("bytes",toJson bytes),("sha256",toJson digest)])),
    ("protectedSha256",toJson after),("unchanged",toJson true),("archived",toJson false)])

def retireCapturedWarnings : IO Unit := do
  idle
  let mut summaries := #[]
  let mut paths : Array System.FilePath := #[]
  for mode in ["small","80"] do
    let path := folder/("capacity-"++mode++"-stderr.txt")
    let lines := ((← IO.FS.readFile path).splitOn "\n").filter (! ·.isEmpty)
    let counts := lines.foldl (fun (counts : Std.HashMap String Nat) line =>
      counts.insert line (counts[line]?.getD 0+1)) {}
    summaries := summaries.push (Json.mkObj [("mode",toJson mode),("sha256",toJson (← hash path)),
      ("nonemptyLines",toJson lines.length),("messages",toJson (counts.toArray.qsort (fun a b => a.1 < b.1)))])
    paths := paths.push path
  write (folder/"capacity-warnings.json") (Json.mkObj [("runs",toJson summaries),("repeatedRawLogsRemoved",toJson true),
    ("allDistinctMessagesAndCountsRetained",toJson true),("archived",toJson false)])
  for path in paths do IO.FS.removeFile path
end RemainingSourceStudy
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare-component"] => RemainingSourceStudy.prepareComponent
  | ["setup-component",mode,tag] => RemainingSourceStudy.setupComponent mode tag
  | ["audit-component"] => RemainingSourceStudy.auditComponent
  | ["collect-component"] => RemainingSourceStudy.collectComponent
  | ["prepare-runtime"] => RemainingSourceStudy.prepareRuntime
  | ["setup-runtime"] => RemainingSourceStudy.setupRuntime
  | ["audit-runtime"] => RemainingSourceStudy.auditRuntime
  | ["audit-rewrite"] => RemainingSourceStudy.auditRewrite
  | ["prepare-auditor"] => RemainingSourceStudy.prepareAuditor
  | ["setup-auditor"] => RemainingSourceStudy.setupAuditor
  | ["audit-auditor"] => RemainingSourceStudy.auditAuditor
  | ["prepare-delivery"] => RemainingSourceStudy.prepareDelivery
  | ["setup-delivery",mode] => RemainingSourceStudy.setupDelivery mode
  | ["seal-installed"] => RemainingSourceStudy.sealInstalled
  | ["cleanup-component-cells"] => RemainingSourceStudy.cleanupComponentAndCells
  | ["prepare-cpu"] => RemainingSourceStudy.prepareCpu
  | ["sample-cpu"] => RemainingSourceStudy.sampleCpu
  | ["cleanup-cpu"] => RemainingSourceStudy.cleanupCpu
  | ["cleanup-logs"] => RemainingSourceStudy.cleanupLogs
  | ["retire-captured-warnings"] => RemainingSourceStudy.retireCapturedWarnings
  | _ => throw (IO.userError "component action required")
