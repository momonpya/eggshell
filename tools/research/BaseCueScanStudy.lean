import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace BaseCueScanStudy
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := project/"docs/candidates/base-cue-scan"
def build := base/"base-cue-scan-build"
def source := base/"base-cue-scan-source"
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some project}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def idle : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.trimAscii.toString.startsWith ((base/"controller/StudyMain").toString++" guard ") ||
    row.trimAscii.toString.startsWith ((base/"resource-budget-guard-build/StudyMain").toString++" "))) "resource guard is live"

def prepare : IO Unit := do
  idle
  check (!(← build.pathExists) && !(← source.pathExists)) "fresh model-free base-cue component required"
  check ((← hash (base/"remaining-source-runtime-build/StudyMain")) ==
    "0b0bbca86b0f235fac032089b40d48e12e24d12343a460767dcaab933f030175") "actual parent changed"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"remaining-source-runtime-build").toString,source.toString,build.toString,
    "tools.research.BaseCueScanChecks",(base/"base-cue-scan-settings.json").toString]
  for name in ["SelectorFixture","BaseCueScanChecks"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  IO.FS.createDirAll folder
  write (folder/"plan.json") (Json.mkObj [("parentRuntimeSha256",toJson (← hash (base/"remaining-source-runtime-build/StudyMain"))),
    ("fixtureSha256",toJson (← hash (base/"selection-profile-inputs/selector-fixture.json"))),
    ("changes",toJson "component only: reconstruct the same three saved queries; compare family scan to start-range nomination with unchanged final predicate"),
    ("controls",toJson #["ordered IDs and duplicate positions","zero/reversed pieces and intervals","overlap/gap boundaries","AB/BA/AB timings"]),
    ("newProductOrHookCalls",toJson (0 : Nat)),("modelCalls",toJson (0 : Nat)),
    ("fullClosureOrAdoptionClaim",toJson false),("adopted",toJson false)])

def setup (mode tag : String) : IO Unit := do
  idle
  check (tag.startsWith ("base-cue-scan-"++mode)) "component tag escaped scope"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve the earlier component attempt"
  let args ← match mode with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"base-cue-scan-settings.json").toString]
    | "run" => do
      check ((← read (folder/"witness.json")).getObjValD "runtimeSha256" == toJson (← hash (build/"StudyMain")))
        "component differs from the audited native source"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1", "EGGSHELL_DATA_ROOT="++(base/"real-source-search-read-trial-result/data").toString,
        (build/"StudyMain").toString,(base/"real-source-search-read-trial-result/work.egg").toString,
        (base/"selection-profile-inputs/selector-fixture.json").toString,(base/"base-cue-scan-result.json").toString]
    | _ => throw (IO.userError "component build or run required")
  write path (Json.mkObj [("command",toJson args),("cwd",toJson project.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def audit : IO Unit := do
  idle
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",build.toString,(folder/"native-closure.json").toString],
    #["component-sources",(base/"remaining-source-runtime-build").toString,build.toString,
      (folder/"native-sources.json").toString,"Eggshell.Handoff","tools.research.PreparedSourceView",
      "tools.PreparedCueIndex","tools.PointBuckets"]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let common ← read (folder/"native-sources.json")
  check (common.getObjValD "commonSourcesUnchanged" == toJson true && common.getObjValD "requiredModulesPresent" == toJson true)
    "actual native core changed in the component"
  let mut inputs := #[]
  for name in ["SelectorFixture","BaseCueScanChecks"] do
    let value : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/("tools_research_"++name++".source"))))
    let path := project/"tools/research"/(name++".lean")
    check (value.1 == (← IO.FS.readFile path)) "native component entry differs from the repository"
    inputs := inputs.push (name,← hash path)
  write (folder/"witness.json") (Json.mkObj [("runtimeSha256",toJson (← hash (build/"StudyMain"))),
    ("nativeSourcesMatchRepository",toJson true),("inputs",toJson inputs),("componentOnly",toJson true)])

def retry : IO Unit := do
  idle
  let guard ← read (base/"base-cue-scan-build1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" != toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) && !(← (folder/"witness.json").pathExists))
    "preserve a successful or live component"
  write (folder/"build1-rejection.json") (Json.mkObj [("guard",guard),
    ("stderr",toJson (← IO.FS.readFile (base/"base-cue-scan-build1.stderr"))),
    ("componentOrProductExecuted",toJson false)])
  for name in ["SelectorFixture","BaseCueScanChecks"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))

def correctAuditName : IO Unit := do
  idle
  check (!(← (folder/"witness.json").pathExists)) "preserve the validated component"
  let report ← read (folder/"native-sources.json")
  check (report.getObjValD "changedCommonModules" == toJson (#[] : Array String) &&
    report.getObjValD "missingRequiredModules" == toJson #["Eggshell.PreparedSourceView"])
    "only the observed module-name correction is authorized here"
  for name in ["native-closure","native-sources"] do
    let target := folder/(name++"-initial.json")
    check (!(← target.pathExists)) "preserve earlier audit evidence"
    IO.FS.rename (folder/(name++".json")) target

def collect : IO Unit := do
  idle
  let guard ← read (base/"base-cue-scan-run1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "component has not passed and drained"
  let report ← read (base/"base-cue-scan-result.json")
  let queries ← IO.ofExcept (report.getObjValAs? (Array Json) "queries")
  check (queries.size == 3 && report.getObjValD "originalSourceUnchanged" == toJson true &&
    queries.all (fun row => (row.getObjValD "structure").getObjValD "allOrderedIdsExact" == toJson true))
    "all actual source queries and exact IDs required"
  write (folder/"component.json") (Json.mkObj [("report",report),("guard",guard),
    ("indexConstructionTimersNotForcedAndNotUsable",toJson true),("adopted",toJson false)])

def prepareDirect : IO Unit := do
  idle
  check ((← read (folder/"component.json")).getObjValD "adopted" == toJson false) "measured component required"
  let target := base/"base-cue-direct-source"
  check (!(← target.pathExists) && !(← (base/"base-cue-direct-build").pathExists)) "fresh unchanged-selector diagnostic required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",build.toString,
    target.toString,(base/"base-cue-direct-build").toString,"tools.research.BaseCueDirectChecks",
    (base/"base-cue-direct-settings.json").toString]
  IO.FS.writeFile (target/"tools/research/BaseCueDirectChecks.lean")
    (← IO.FS.readFile (project/"tools/research/BaseCueDirectChecks.lean"))
  write (folder/"direct-plan.json") (Json.mkObj [("clients",toJson (#[(4 : Nat),16])),
    ("parentProductUnchanged",toJson true),("sourceAndQueriesSharedOnce",toJson true),
    ("purpose",toJson "isolate unchanged native selectView CPU/concurrency from source preparation, numerical RPC and transport"),
    ("fullHookOrEightyRetry",toJson false),("modelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def setupDirect (mode : String) (attempt : Nat := 1) : IO Unit := do
  idle
  let tag := "base-cue-direct-"++mode++toString attempt
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve the previous direct diagnostic"
  let args ← match mode with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"base-cue-direct-settings.json").toString]
    | "run" => do
      check ((← read (folder/"direct-witness.json")).getObjValD "runtimeSha256" ==
        toJson (← hash (base/"base-cue-direct-build/StudyMain"))) "actual diagnostic differs from native witness"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT="++(base/"real-source-search-read-trial-result/data").toString,
        (base/"base-cue-direct-build/StudyMain").toString,(base/"real-source-search-read-trial-result/work.egg").toString,
        (base/"selection-profile-inputs/selector-fixture.json").toString,(base/"base-cue-direct-result").toString]
    | _ => throw (IO.userError "direct build or run required")
  write path (Json.mkObj [("command",toJson args),("cwd",toJson project.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def auditDirect : IO Unit := do
  idle
  let target := base/"base-cue-direct-build"
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",target.toString,(folder/"direct-closure.json").toString],
    #["component-sources",(base/"remaining-source-runtime-build").toString,target.toString,
      (folder/"direct-sources.json").toString,"Eggshell.Handoff","tools.research.PreparedSourceView",
      "tools.PreparedCueIndex","tools.PointBuckets"]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let mut inputs := #[]
  for name in ["SelectorFixture","BaseCueDirectChecks"] do
    let witness : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (target/("tools_research_"++name++".source"))))
    let path := project/"tools/research"/(name++".lean")
    check (witness.1 == (← IO.FS.readFile path)) "actual direct control source differs from repository"
    inputs := inputs.push (name,← hash path)
  write (folder/"direct-witness.json") (Json.mkObj [("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("nativeSourcesMatchRepository",toJson true),("inputs",toJson inputs),("componentOnly",toJson true)])

def retryDirect : IO Unit := do
  idle
  let guard ← read (base/"base-cue-direct-build1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" != toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) && !(← (folder/"direct-witness.json").pathExists))
    "preserve successful or live direct runtime"
  write (folder/"direct-build1-rejection.json") (Json.mkObj [("guard",guard),
    ("stderr",toJson (← IO.FS.readFile (base/"base-cue-direct-build1.stderr"))),
    ("componentOrProductExecuted",toJson false)])
  IO.FS.writeFile (base/"base-cue-direct-source/tools/research/BaseCueDirectChecks.lean")
    (← IO.FS.readFile (project/"tools/research/BaseCueDirectChecks.lean"))

def collectDirect : IO Unit := do
  idle
  let guard ← read (base/"base-cue-direct-run1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "direct selector did not finish and drain"
  let report ← read (base/"base-cue-direct-result/report.json")
  check (report.getObjValD "allChoicesExact" == toJson true && report.getObjValD "originalSourceUnchanged" == toJson true)
    "direct selector changed source or choices"
  write (folder/"direct.json") (Json.mkObj [("guard",guard),("report",report),
    ("equalityScope",toJson "sourceKeys and generic selected unit IDs; not all ServiceChoice metadata fields"),
    ("adopted",toJson false)])

def setupProof (attempt : Nat := 1) : IO Unit := do
  idle
  let tag := "base-cue-proof"++toString attempt
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve existing proof attempt"
  write path (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
      (project/"tools/research/BaseCueScanStudy.lean").toString,(if attempt == 1 then "prove" else "prove-retry")]),("cwd",toJson project.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

partial def inheritInterfaces (fromDir toDir : System.FilePath) : IO Unit := do
  IO.FS.createDirAll toDir
  for entry in ← fromDir.readDir do
    if !(← entry.path.pathExists) then continue
    if ← entry.path.isDir then inheritInterfaces entry.path (toDir/entry.fileName)
    else if !(← (toDir/entry.fileName).pathExists) then
      discard <| command "/bin/ln" #["-s",(← IO.FS.realPath entry.path).toString,(toDir/entry.fileName).toString]

def prove (retry : Bool := false) : IO Unit := do
  let proofRoot := base/"base-cue-proof-lib"
  check (!(← (folder/"proofs.json").pathExists)) "preserve validated proofs"
  if retry then
    let prior ← read (base/"base-cue-proof1.guard.json")
    check (prior.getObjValD "state" == toJson "finished" && prior.getObjValD "exitCode" != toJson (0 : Nat) &&
      prior.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous proof task is live or successful"
    write (folder/"proof1-rejection.json") (Json.mkObj [("guard",prior),
      ("stderr",toJson (← IO.FS.readFile (base/"base-cue-proof1.stderr"))),
      ("reason",toJson "the shared tools package needs one interface root; use read-only links, not writes into validated inputs")])
  else check (!(← proofRoot.pathExists)) "fresh proof output required"
  let measured : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/"tools_research_BaseCueScanChecks.source")))
  check (measured.1 == (← IO.FS.readFile (project/"tools/research/BaseCueScanChecks.lean")))
    "agreement must refer to the source of the measured native function"
  IO.FS.createDirAll (proofRoot/"tools/research")
  inheritInterfaces (build/"lib") proofRoot
  let general := project/"tools/research/ContainedCueIndex.lean"
  let agreement := project/"tools/research/ContainedCueAgreement.lean"
  let generalOutput ← command "/usr/bin/env" #["LEAN_PATH="++proofRoot.toString,
    (compiler/"bin/lean").toString,"-j1","-M768","-DwarningAsError=true","-o",
    (proofRoot/"tools/research/ContainedCueIndex.olean").toString,general.toString]
  let linkedOutput ← command "/usr/bin/env" #["LEAN_PATH="++proofRoot.toString,
    (compiler/"bin/lean").toString,"-j1","-M1536","-DwarningAsError=true",agreement.toString]
  check (!generalOutput.contains "sorryAx" && !linkedOutput.contains "sorryAx") "admitted equality is not allowed"
  write (folder/"proofs.json") (Json.mkObj [("generalAxioms",toJson generalOutput),("nativeAgreementAxioms",toJson linkedOutput),
    ("generalSourceSha256",toJson (← hash general)),("agreementSourceSha256",toJson (← hash agreement)),
    ("measuredNativeSourceSha256",toJson (← hash (project/"tools/research/BaseCueScanChecks.lean"))),
    ("exactFunctionMeasuredByNativeComponent",toJson true),("arbitraryWidthAndMalformedIntervals",toJson true),
    ("productIntegrationOrAdoptionClaim",toJson false)])

def cleanup : IO Unit := do
  idle
  for name in ["component.json","direct.json","proofs.json"] do
    check (← (folder/name).pathExists) "capture all terminal evidence before cleanup"
  let guards ← #["base-cue-scan-run1","base-cue-direct-run1","base-cue-proof2"].mapM fun name => do
    let guard ← read (base/(name++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "component is still live or failed"
    return guard
  let roots := #[build,base/"base-cue-direct-build"]
  for entry in ← base.readDir do
    if roots.contains entry.path then continue
    let response := entry.path/"runtime.rsp"
    if ← response.pathExists then
      let text ← IO.FS.readFile response
      check (!(roots.any fun root => text.contains (root.toString++"/")))
        "a retained native program depends on the ended component"
  let original := base/"real-source-search-read-trial-result/work.egg"
  let retained := #[base/"remaining-source-runtime-build/StudyMain",base/"remaining-source-auditor-build/StudyMain",
    base/"score-prepare-runtime-build/StudyMain",original/"head",
    original/"2a1ab5766ac89060c477ae3fc9683c9492574ff843d134c01b53d9697a27359e.pages"]
  let before ← retained.mapM fun path => do return (path.toString,← hash path)
  let mut paths := roots++#[source,base/"base-cue-direct-source",base/"base-cue-direct-result",
    base/"base-cue-scan-result.json",base/"base-cue-proof-lib"]
  for entry in ← base.readDir do
    if ["base-cue-scan-","base-cue-direct-","base-cue-proof"].any (fun pattern => entry.fileName.startsWith pattern) &&
      (entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr") then paths := paths.push entry.path
  let record := Json.mkObj [("removed",toJson (paths.map (·.toString))),("terminalGuards",toJson guards),
    ("currentProductAuditorParentOriginalProjectCacheModelAndBodiesRetained",toJson true),
    ("archived",toJson false)]
  write (folder/"cleanup.json") (record.setObjVal! "completed" (toJson false))
  for path in paths do if ← path.pathExists then
    if (← path.symlinkMetadata).type == .dir then IO.FS.removeDirAll path else IO.FS.removeFile path
  let after ← retained.mapM fun path => do return (path.toString,← hash path)
  check (before == after) "cleanup changed a current product or original source"
  write (folder/"cleanup.json") (record.setObjVal! "completed" (toJson true)
    |>.setObjVal! "retainedSha256" (toJson after)|>.setObjVal! "retainedUnchanged" (toJson true))
end BaseCueScanStudy
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => BaseCueScanStudy.prepare
  | ["setup",mode,tag] => BaseCueScanStudy.setup mode tag
  | ["audit"] => BaseCueScanStudy.audit
  | ["retry"] => BaseCueScanStudy.retry
  | ["correct-audit-name"] => BaseCueScanStudy.correctAuditName
  | ["collect"] => BaseCueScanStudy.collect
  | ["prepare-direct"] => BaseCueScanStudy.prepareDirect
  | ["setup-direct",mode] => BaseCueScanStudy.setupDirect mode
  | ["setup-direct",mode,attempt] => do
      let some attempt := attempt.toNat? | throw (IO.userError "positive attempt required")
      BaseCueScanStudy.setupDirect mode attempt
  | ["audit-direct"] => BaseCueScanStudy.auditDirect
  | ["retry-direct"] => BaseCueScanStudy.retryDirect
  | ["collect-direct"] => BaseCueScanStudy.collectDirect
  | ["setup-proof"] => BaseCueScanStudy.setupProof
  | ["setup-proof",attempt] => do
      let some attempt := attempt.toNat? | throw (IO.userError "positive attempt required")
      BaseCueScanStudy.setupProof attempt
  | ["prove"] => BaseCueScanStudy.prove
  | ["prove-retry"] => BaseCueScanStudy.prove true
  | ["cleanup"] => BaseCueScanStudy.cleanup
  | _ => throw (IO.userError "base cue scan prepare/setup/audit/collect required")
