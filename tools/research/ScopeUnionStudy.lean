import tools.research.StudyLocal
open Lean StudyLocal
namespace ScopeUnionStudy
def parent := base/"practical-runtime/source-snapshot"
def root := base/"practical-runtime/scope-union-probe"
def records := project/"docs/candidates/scope-union"
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh original-scope probe required"
  check ((← hash (parent/"build/StudyMain")) == "720e64d9daf08a8c8f5e716b8cb877bc378253ba51fb43738dc33e05c1b6c534")
    "fixed native parent changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  copyLocalArtifacts (parent/"build") (root/"build")
  IO.FS.writeFile (root/"source/tools/research/ScopeUnionProbe.lean")
    (← IO.FS.readFile (project/"tools/research/ScopeUnionProbe.lean"))
  let configuration := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (parent/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.ScopeUnionProbe")
  write (root/"settings.json") configuration
  let original ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let previous ← read (project/"docs/candidates/source-snapshot/llvm/before-delivery.json")
  let diagnosticPath := project/"docs/candidates/source-plan-contract/diagnostics.json"
  let diagnostic ← read diagnosticPath
  let domain := diagnostic.getObjValD "signals/diagnostic/domain.json"
  let plan := Json.mkObj [("source",original.getObjValD "source"),("sourceFiles",original.getObjValD "sourceFiles"),
    ("owners",domain.getObjValD "hydrated"),("expectedHead",previous.getObjValD "originalHead"),
    ("diagnostic",toJson diagnosticPath.toString),
    ("evidence",toJson (project/"docs/candidates/source-plan-contract/llvm.json").toString),
    ("output",toJson (records/"result.json").toString)]
  write (root/"plan.json") plan
  write (records/"plan.json") (plan.setObjVal! "hypothesis"
    (toJson "owner-local published extents may miss optional scopes only visible after canonical rows are joined")
    |>.setObjVal! "unchanged" (toJson #["all original offers and order","costs","weights","bounds","model","authority","source bytes"])
    |>.setObjVal! "stopRule" (toJson "one fixed topic-1 native audit; no new DB/cache/query; no fitting widths, ranking or graph bonuses"))
  guard "scope-union-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def run (buildTag : String := "scope-union-build") : IO Unit := do
  idle
  discard <| finished buildTag
  for args in [#["inspect",(root/"build").toString,(records/"native.json").toString],
      #["common-sources",(parent/"build").toString,(root/"build").toString,(records/"sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args)
  guard "scope-union-audit" #["/usr/bin/env","-u","LEAN_NUM_THREADS",(root/"build/StudyMain").toString,(root/"plan.json").toString]
def rebuild : IO Unit := do
  idle
  let stopped ← read (base/"scope-union-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only correct the stopped native probe"
  write (records/"build-refusal.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"build/tools_research_ScopeUnionProbe-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"build/tools_research_ScopeUnionProbe-lean.stderr"))),
    ("productChanged",toJson false),("modelOrQueryCalled",toJson false)])
  IO.FS.writeFile (root/"source/tools/research/ScopeUnionProbe.lean")
    (← IO.FS.readFile (project/"tools/research/ScopeUnionProbe.lean"))
  guard "scope-union-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def exchangeBuild : IO Unit := do
  idle
  discard <| finished "scope-union-audit"
  let result ← read (records/"result.json")
  check (result.getObjValD "before" == result.getObjValD "after" &&
    result.getObjValD "selectedNewScopes" == toJson (#[] : Array Nat)) "scope alternative probe changed its fixed outcome"
  for name in ["CoverageExchange","CoverageExchangeProbe"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  copyLocalArtifacts (root/"build") (root/"exchange-build")
  let configuration := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"exchange-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString,(parent/"build").toString])
    |>.setObjVal! "mainModule" (toJson "tools.research.CoverageExchangeProbe")
  write (root/"exchange-settings.json") configuration
  write (records/"exchange-plan.json") (Json.mkObj [
    ("purpose",toJson "distinguish greedy packing loss from unchanged proxy-objective loss"),
    ("search",toJson "one exhaustive remove-one/add-one pass, maximizing the original exact integer benefit"),
    ("unchanged",toJson #["offers","scope units","costs","weights","budgets","actual input"]),
    ("certificate",toJson "independent complete cost/benefit recomputation and strict objective improvement"),
    ("labels",toJson "opened only after search and certification; no runtime or model adoption from this audit")])
  guard "scope-union-exchange-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"exchange-settings.json").toString]
def exchangeRebuild : IO Unit := do
  idle
  let stopped ← read (base/"scope-union-exchange-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only correct the stopped exchange elaboration"
  write (records/"exchange-build-refusal.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"exchange-build/tools_research_CoverageExchange-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"exchange-build/tools_research_CoverageExchange-lean.stderr"))),
    ("modelOrQueryCalled",toJson false),("productChanged",toJson false)])
  for name in ["CoverageExchange","CoverageExchangeProbe"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  guard "scope-union-exchange-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"exchange-settings.json").toString]
def exchangeVerifyBuild : IO Unit := do
  idle
  let completed ← finished "scope-union-exchange-audit"
  write (records/"exchange-timing-attempt.json") (Json.mkObj [("guard",completed),
    ("rawReport",← read (records/"exchange.json")),
    ("executedSource",← read (root/"exchange-build/tools_research_CoverageExchangeProbe.source")),
    ("timingAccepted",toJson false),("reason",toJson "pure search was not forced between IO clock reads")])
  for name in ["CoverageExchange","CoverageExchangeProbe"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  guard "scope-union-exchange-verified-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"exchange-settings.json").toString]
def exchangeKernelBuild : IO Unit := do
  idle
  let stopped ← read (base/"scope-union-exchange-verified-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only correct the stopped certificate elaboration"
  write (records/"exchange-certificate-refusal.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"exchange-build/tools_research_CoverageExchange-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"exchange-build/tools_research_CoverageExchange-lean.stderr"))),
    ("modelOrQueryCalled",toJson false),("productChanged",toJson false)])
  IO.FS.writeFile (root/"source/tools/research/CoverageExchange.lean")
    (← IO.FS.readFile (project/"tools/research/CoverageExchange.lean"))
  guard "scope-union-exchange-kernel-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"exchange-settings.json").toString]
def exchangeRun (buildTag : String := "scope-union-exchange-build") (verified : Bool := false) : IO Unit := do
  idle
  discard <| finished buildTag
  let label := if verified then "exchange-verified" else "exchange"
  for args in [#["inspect",(root/"exchange-build").toString,(records/(label++"-native.json")).toString],
      #["common-sources",(parent/"build").toString,(root/"exchange-build").toString,(records/(label++"-sources.json")).toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args)
  guard (if verified then "scope-union-exchange-verified-audit" else "scope-union-exchange-audit") #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    (root/"exchange-build/StudyMain").toString,
    (project/"docs/candidates/source-plan-contract/diagnostics.json").toString,
    (project/"docs/candidates/source-plan-contract/llvm.json").toString,
    (records/(label++".json")).toString]
partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let counts ← remove entry.path
    total := (total.1+counts.1,total.2+counts.2)
  IO.FS.removeDir path
  return total
def finish : IO Unit := do
  idle
  discard <| finished "scope-union-exchange-verified-audit"
  let result ← read (records/"result.json")
  let exchange ← read (records/"exchange-verified.json")
  check (result.getObjValD "sourceHashesBeforeAndAfter" == toJson true &&
    result.getObjValD "baselineActualNodesReproduced" == toJson true &&
    result.getObjValD "before" == result.getObjValD "after" &&
    exchange.getObjValD "independentUpperBoundCertified" == toJson true &&
    exchange.getObjValD "proposal" == Json.null && exchange.getObjValD "before" == exchange.getObjValD "after")
    "the closed hypotheses changed their fixed findings"
  let stdout ← IO.FS.readFile (root/"exchange-build/tools_research_CoverageExchangeProbe-lean.stdout")
  let stderr ← IO.FS.readFile (root/"exchange-build/tools_research_CoverageExchangeProbe-lean.stderr")
  check (stderr.isEmpty && stdout.contains "all_exchanges_bounded" && !stdout.contains "sorryAx" &&
    !stdout.contains "Lean.trustCompiler" && !stdout.contains "Lean.ofReduceBool") "exchange certificate proof audit failed"
  let oldRecords := project/"docs/candidates/record-boundary/Eggshell/CanonicalSourceRecords.lean"
  let currentRecords := parent/"source/Eggshell/CanonicalSourceRecords.lean"
  check ((← IO.FS.readFile oldRecords) == (← IO.FS.readFile currentRecords)) "record boundary producer differs from the earlier pass"
  let history ← read (project/"docs/candidates/record-boundary/native-result.json")
  let current ← read (project/"docs/candidates/source-plan-contract/llvm.json")
  let comparison := Json.mkObj [("olderHead",((history.getObjValD "source").getObjValD "ancestry").getObjValD "source"),
    ("currentHead",(current.getObjValD "llvm/before-delivery.json").getObjValD "originalHead"),
    ("recordProducerByteIdentical",toJson true),("recordProducerSha256",toJson (← hash currentRecords)),
    ("sameSeedComparison",toJson false),("regressionEstablished",toJson false)]
  let mut stages := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "scope-union-" && entry.fileName.endsWith ".guard.json" then
      let report ← read entry.path
      check (report.getObjValD "state" == toJson "finished" && report.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "probe still owns running work"
      stages := stages.push (entry.fileName,report)
  let mut evidence := [("historicalComparison",comparison),("guards",toJson (stages.qsort fun a b => a.1 < b.1)),
    ("proofs",Json.mkObj [("stdout",toJson stdout),("stderr",toJson stderr),
      ("standardAxiomsOnly",toJson true)]),
    ("scopeExecutedSource",← read (root/"build/tools_research_ScopeUnionProbe.source")),
    ("exchangeExecutedSource",← read (root/"exchange-build/tools_research_CoverageExchange.source")),
    ("exchangeProbeExecutedSource",← read (root/"exchange-build/tools_research_CoverageExchangeProbe.source"))]
  let mut retiredEvidence := #[]
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".json" && !["plan.json","result.json","exchange-plan.json","exchange-verified.json"].contains entry.fileName then
      evidence := evidence++[(entry.fileName,← read entry.path)]
      retiredEvidence := retiredEvidence.push entry.path
  let packed := Json.mkObj evidence
  check (!(← (records/"audit.json").pathExists)) "preserve compact probe evidence"
  write (records/"audit.json") packed
  check ((← read (records/"audit.json")) == packed) "compact evidence round trip differs"
  let inputs : Array (String × String) ← IO.ofExcept
    (fromJson? (← read (project/"docs/candidates/source-snapshot/protected-native-inputs.json")))
  check (inputs.size == 355 && !(inputs.any fun (path,_) => path.startsWith (root.toString++"/")))
    "probe retirement overlaps protected native inputs"
  for (path,digest) in inputs do check ((← hash (.mk path)) == digest) "protected input changed before retirement"
  let removed ← remove root
  for path in retiredEvidence do discard <| remove path
  for (path,digest) in inputs do check ((← hash (.mk path)) == digest) "retirement changed a protected input"
  write (records/"retired.json") (Json.mkObj [("files",toJson removed.1),("logicalBytes",toJson removed.2),
    ("archiveCreated",toJson false),("protectedNativeInputsUnchanged",toJson inputs.size),
    ("newDatabaseOrCache",toJson false),("currentProductChanged",toJson false),("adopted",toJson false)])
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(parent/"build").toString,
    (records/"parent-after-retirement.json").toString]
end ScopeUnionStudy
def main : List String → IO Unit
  | ["prepare"] => ScopeUnionStudy.prepare
  | ["run"] => ScopeUnionStudy.run
  | ["run-checked"] => ScopeUnionStudy.run "scope-union-checked-build"
  | ["rebuild"] => ScopeUnionStudy.rebuild
  | ["exchange-build"] => ScopeUnionStudy.exchangeBuild
  | ["exchange-run"] => ScopeUnionStudy.exchangeRun
  | ["exchange-rebuild"] => ScopeUnionStudy.exchangeRebuild
  | ["exchange-run-checked"] => ScopeUnionStudy.exchangeRun "scope-union-exchange-checked-build"
  | ["exchange-verify-build"] => ScopeUnionStudy.exchangeVerifyBuild
  | ["exchange-verified-run"] => ScopeUnionStudy.exchangeRun "scope-union-exchange-verified-build" true
  | ["exchange-kernel-build"] => ScopeUnionStudy.exchangeKernelBuild
  | ["exchange-kernel-run"] => ScopeUnionStudy.exchangeRun "scope-union-exchange-kernel-build" true
  | ["finish"] => ScopeUnionStudy.finish
  | _ => throw (IO.userError "ScopeUnionStudy prepare|run|rebuild")
