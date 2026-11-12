import tools.research.StudyLocal
open Lean StudyLocal
namespace LLVMProjectStudy
def runtime := base/"practical-runtime/source-snapshot"
def root := runtime/"llvm"
def records := project/"docs/candidates/source-snapshot/llvm"
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists) && !(← (runtime/"llvm-build").pathExists))
    "fresh real-corpus audit required"
  check ((← hash (runtime/"build/StudyMain")) == "720e64d9daf08a8c8f5e716b8cb877bc378253ba51fb43738dc33e05c1b6c534")
    "fixed snapshot candidate changed"
  IO.FS.createDirAll records
  IO.FS.writeFile (runtime/"source/tools/research/LLVMProjectChecks.lean")
    (← IO.FS.readFile (project/"tools/research/LLVMProjectChecks.lean"))
  copyLocalArtifacts (runtime/"build") (runtime/"llvm-build")
  let installation := (← read (runtime/"installation.json"))
    |>.setObjVal! "handoffChars" (toJson (120000 : Nat))
  let before ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let plan := Json.mkObj [("installation",installation),("original",before.getObjValD "source"),
    ("originalFiles",before.getObjValD "sourceFiles"),
    ("definitions",toJson (base/"practical-runtime/interrupted-recovery/definitions.json").toString),
    ("workspace",toJson "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"),
    ("root",toJson root.toString),("records",toJson records.toString)]
  write (runtime/"llvm-plan.json") plan
  write (records/"plan.json") (plan.setObjVal! "adopted" (toJson false)
    |>.setObjVal! "answeringModelCalls" (toJson (0 : Nat))
    |>.setObjVal! "freezeFirst" (toJson true))
  let settings := (← read (runtime/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (runtime/"llvm-build").toString)
    |>.setObjVal! "parents" (toJson #[(runtime/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (runtime/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (runtime/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (runtime/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.LLVMProjectChecks")
  write (runtime/"llvm-settings.json") settings
  guard "llvm-project-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(runtime/"llvm-settings.json").toString]
def audit (arguments : Array String) : IO Unit := do
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
def checkedBuild : IO Unit := do
  idle
  let stopped ← read (base/"llvm-project-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only correct the stopped observer elaboration"
  write (records/"build-rejection.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (runtime/"llvm-build/tools_research_LLVMProjectChecks-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (runtime/"llvm-build/tools_research_LLVMProjectChecks-lean.stderr"))),
    ("productChanged",toJson false),("databaseOrModelStarted",toJson false)])
  IO.FS.writeFile (runtime/"source/tools/research/LLVMProjectChecks.lean")
    (← IO.FS.readFile (project/"tools/research/LLVMProjectChecks.lean"))
  guard "llvm-project-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(runtime/"llvm-settings.json").toString]
def completeBuild : IO Unit := do
  idle
  discard <| finished "llvm-project-checked-build"
  let comparison ← read (records/"sources.json")
  check (comparison.getObjValD "allProductCorePresent" == toJson false) "retain the incomplete observer source audit"
  write (records/"observer-rejection.json") (Json.mkObj [("native",← read (records/"native.json")),
    ("comparison",comparison),("reason",toJson "observer imported only its local reader functions; include Main and ContractAudit to bind every product core module"),
    ("productChanged",toJson false),("databaseOrModelStarted",toJson false)])
  for name in ["native.json","sources.json"] do IO.FS.removeFile (records/name)
  IO.FS.writeFile (runtime/"source/tools/research/LLVMProjectChecks.lean")
    (← IO.FS.readFile (project/"tools/research/LLVMProjectChecks.lean"))
  guard "llvm-project-complete-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(runtime/"llvm-settings.json").toString]
def capture : IO Unit := do
  idle
  write (records/"build.guard.json") (← finished "llvm-project-complete-build")
  audit #["inspect",(runtime/"llvm-build").toString,(records/"native.json").toString]
  audit #["common-sources",(runtime/"build").toString,(runtime/"llvm-build").toString,(records/"sources.json").toString]
  guard "llvm-project-capture" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_PREFIX="++(runtime/"prefix").toString,
    "EGGSHELL_DATA_ROOT="++(root/"client").toString,
    (runtime/"llvm-build/StudyMain").toString,"prepare",(runtime/"llvm-plan.json").toString]
def run : IO Unit := do
  idle
  write (records/"capture.guard.json") (← finished "llvm-project-capture")
  let installation := (← read (runtime/"llvm-plan.json")).getObjValD "installation"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let updates := #[("EGGSHELL_DATA_ROOT",some (root/"client").toString),("TMPDIR",some (root/"tmp").toString)]
  let environment := environment.filter (fun row => !updates.any (·.1 == row.1))++updates
  let unsets := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let values := environment.filterMap fun (key,value) => value.map (fun item => key++"="++item)
  guard "llvm-project-run" (#["/usr/bin/env"]++unsets.flatMap (fun key => #["-u",key])++values++
    #[(runtime/"llvm-build/StudyMain").toString,"run",(runtime/"llvm-plan.json").toString])
def prepareDiagnostic : IO Unit := do
  idle
  write (records/"run.guard.json") (← finished "llvm-project-run")
  let result ← read (records/"result.json")
  check (result.getObjValD "allSixReachTarget" == toJson false) "only diagnose the actual recorded delivery miss"
  write (records/"executed-observer-source.json") (← read (runtime/"llvm-build/tools_research_LLVMProjectChecks.source"))
  IO.FS.writeFile (runtime/"source/tools/research/LLVMProjectChecks.lean")
    (← IO.FS.readFile (project/"tools/research/LLVMProjectChecks.lean"))
  copyLocalArtifacts (runtime/"llvm-build") (runtime/"llvm-diagnostic-build")
  let settings := (← read (runtime/"llvm-build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (runtime/"llvm-diagnostic-build").toString)
    |>.setObjVal! "parents" (toJson #[(runtime/"llvm-build").toString])
    |>.setObjVal! "baselineResponse" (toJson (runtime/"llvm-build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (runtime/"llvm-build/tools_research_LLVMProjectChecks.o").toString)
    |>.setObjVal! "objectModules" (toJson (runtime/"llvm-build/object-mapping.json").toString)
  write (runtime/"llvm-diagnostic-settings.json") settings
  guard "llvm-project-diagnostic-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(runtime/"llvm-diagnostic-settings.json").toString]
def diagnostic : IO Unit := do
  idle
  write (records/"diagnostic-build.guard.json") (← finished "llvm-project-diagnostic-build")
  audit #["inspect",(runtime/"llvm-diagnostic-build").toString,(records/"diagnostic-native.json").toString]
  audit #["common-sources",(runtime/"build").toString,(runtime/"llvm-diagnostic-build").toString,
    (records/"diagnostic-sources.json").toString]
  guard "llvm-project-diagnostic" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_PREFIX="++(runtime/"prefix").toString,"EGGSHELL_DATA_ROOT="++(root/"host").toString,
    "EGGSHELL_TRACE_SELECTION_RANGES=1",(runtime/"llvm-diagnostic-build/StudyMain").toString,
    "diagnose",(runtime/"llvm-plan.json").toString]
def explain : IO Unit := do
  idle
  write (records/"diagnostic.guard.json") (← finished "llvm-project-diagnostic")
  let validation ← read (records/"diagnostic/validation.json")
  check (validation.getObjValD "sameOrdinaryBody" == toJson true) "diagnostic does not explain the ordinary body"
  let result ← read (records/"result.json")
  let queries ← IO.ofExcept ((result.getObjValD "queries").getArr?)
  let some query := queries[0]? | throw (IO.userError "ordinary first query absent")
  let missing : Array (Array String) ← IO.ofExcept
    (((query.getObjValD "assessment").getObjValD "availableDelivery").getObjValAs? _ "missing")
  let before ← read (records/"before-delivery.json")
  let topics ← IO.ofExcept ((before.getObjValD "topics").getArr?)
  let some topic := topics[0]? | throw (IO.userError "frozen first topic absent")
  let units ← IO.ofExcept ((topic.getObjValD "frozen").getObjValAs? (Array Json) "units")
  let selection ← read (records/"diagnostic/selection.json")
  let bindings ← IO.ofExcept (selection.getObjValAs? (Array Json) "bindingAudit")
  let chosen : Array Nat ← IO.ofExcept (selection.getObjValAs? _ "selected")
  let mut losses := #[]
  for unit in units do
    let names : Array String ← IO.ofExcept (unit.getObjValAs? _ "names")
    unless names.any (fun name => missing.any (·.contains name)) do continue
    let alternatives : Array (Array Json) ← IO.ofExcept (unit.getObjValAs? _ "alternatives")
    let mut observations := #[]
    for binding in bindings do
      let source := binding.getObjValD "source"
      let some first := (source.getObjValAs? Nat "first").toOption | continue
      let some last := (source.getObjValAs? Nat "last").toOption | continue
      let relevant := alternatives.any fun parts => parts.any fun wanted =>
        source.getObjValD "subject" == wanted.getObjValD "subject" &&
        (wanted.getObjValAs? Nat "first").toOption.any (· ≤ last) &&
        (wanted.getObjValAs? Nat "last").toOption.any (first ≤ ·)
      unless relevant do continue
      let choices : Array (Array Nat) ← IO.ofExcept (binding.getObjValAs? _ "alternatives")
      let available := choices.any (fun choice => !choice.isEmpty)
      let delivered := choices.any (fun choice => !choice.isEmpty && choice.all chosen.contains)
      observations := observations.push (Json.mkObj [("source",source),("owners",binding.getObjValD "owners"),
        ("candidateAlternatives",toJson choices),("availableUnit",toJson available),("selectedUnit",toJson delivered),
        ("firstObservedLoss",toJson (if available && !delivered then "selection" else "not-established-by-this-binding"))])
    losses := losses.push (Json.mkObj [("names",toJson names),("bindings",toJson observations),
      ("noBindingDoesNotProveCandidateAbsence",toJson true)])
  let domain ← read (records/"diagnostic/domain.json")
  write (records/"diagnostic/explanation.json") (Json.mkObj [("validation",validation),
    ("families",selection.getObjValD "families"),("candidateUnits",selection.getObjValD "candidateUnits"),
    ("selectedUnits",toJson chosen.size),("nominated",domain.getObjValD "nominated"),
    ("focusRanking",domain.getObjValD "focusRanking"),("hydrated",domain.getObjValD "hydrated"),
    ("synapticComplete",domain.getObjValD "synapticComplete"),("missingBindings",toJson losses),
    ("afterDeliveryDiagnosticOnly",toJson true),("oraclePassedToProduct",toJson false)])
def retain : IO Unit := do
  idle
  discard <| finished "llvm-project-run"
  discard <| finished "llvm-project-diagnostic"
  let before ← read (records/"before-delivery.json")
  let result ← read (records/"result.json")
  let queries ← IO.ofExcept (result.getObjValAs? (Array Json) "queries")
  check (queries.size == 6) "six actual fresh-chat audits are required"
  let mut eligible := 0
  let mut delivered := 0
  let mut calls := #[]
  for query in queries do
    let assessment := (query.getObjValD "assessment").getObjValD "availableDelivery"
    eligible := eligible+(← IO.ofExcept (assessment.getObjValAs? Nat "eligible"))
    delivered := delivered+(← IO.ofExcept (assessment.getObjValAs? Nat "delivered"))
    let session ← IO.ofExcept (query.getObjValAs? String "session")
    for label in ["start","prompt","stop"] do
      let directory := root/"calls"/session/label
      calls := calls.push (Json.mkObj [("session",toJson session),("event",toJson label),
        ("record",← read (directory/"record.json")),("registration",← read (directory/"registration.json")),
        ("input",toJson (← IO.FS.readFile (directory/"stdin"))),
        ("stdout",toJson (← IO.FS.readFile (directory/"stdout"))),("stderr",toJson (← IO.FS.readFile (directory/"stderr")))])
  check (calls.all (fun row => (row.getObjValD "record").getObjValD "exitCode" == toJson (0 : Nat) &&
    row.getObjValD "stderr" == toJson "")) "an installed hook failed or wrote stderr"
  write (records/"callbacks.json") (toJson calls)
  let warm ← read (records/"warm.json")
  let warmOutput ← IO.ofExcept (warm.getObjValAs? String "stdout" >>= Json.parse)
  let warmDatabases ← IO.ofExcept (warmOutput.getObjValAs? (Array Json) "databases")
  let some database := warmDatabases[0]? | throw (IO.userError "warm omitted its database")
  let warmSources ← IO.ofExcept (database.getObjValAs? (Array Json) "sources")
  let some prepared := warmSources[0]? | throw (IO.userError "warm omitted its original source")
  let after := prepared.getObjValD "after"
  check (warm.getObjValD "exitCode" == toJson (0 : Nat) &&
    (after.getObjValD "discovery").getObjValD "missing" == toJson (0 : Nat) &&
    (after.getObjValD "focus").getObjValD "missing" == toJson (0 : Nat)) "numerical warm has incomplete coverage"
  let source := root/"llvm.egg/owners/0/source.egg"
  let original ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let originalDirectory : System.FilePath := .mk (← IO.ofExcept (original.getObjValAs? String "source"))
  let originalFiles : Array (String × String) ← IO.ofExcept (original.getObjValAs? _ "sourceFiles")
  let capturedFiles : Array (String × String) ← IO.ofExcept (before.getObjValAs? _ "sourceFiles")
  for (name,expected) in originalFiles do
    check ((← hash (originalDirectory/name)) == expected) "protected source original changed"
  for (name,expected) in capturedFiles do
    check ((← hash (source/name)) == expected && originalFiles.contains (name,expected))
      "captured source bytes differ from the original or changed during preparation/delivery"
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "llvm-project-" && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "a real LLVM audit stage remains live"
      guards := guards.push (entry.fileName,value)
  write (records/"guards.json") (toJson guards)
  let diagnosticSource ← read (runtime/"llvm-diagnostic-build/tools_research_LLVMProjectChecks.source")
  write (records/"diagnostic-observer-source.json") diagnosticSource
  write (records/"summary.json") (Json.mkObj [("requiredAppearances",toJson eligible),("deliveredAppearances",toJson delivered),
    ("queries",toJson queries),("allSixReachTarget",result.getObjValD "allSixReachTarget"),
    ("actualHooks",toJson calls.size),("allHooksSucceeded",toJson true),
    ("sourceOriginalAndCapturedBytesUnchanged",toJson true),("ordinaryBudgetChars",toJson (120000 : Nat)),
    ("warmElapsedMs",warm.getObjValD "elapsedMs"),("discoveryCoverage",after.getObjValD "discovery"),
    ("focusCoverage",after.getObjValD "focus"),("sameBodiesAcrossFreshPasses",toJson
      ((Array.range 3).all fun i => (queries[i]?.getD Json.null).getObjValD "bodySha256" ==
        (queries[i+3]?.getD Json.null).getObjValD "bodySha256")),
    ("answeringModelCalls",toJson (0 : Nat)),("acceptedSeed",toJson false),("adopted",toJson false)])
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
def cleanup : IO Unit := do
  idle
  let summary ← read (records/"summary.json")
  check (summary.getObjValD "allSixReachTarget" == toJson false &&
    summary.getObjValD "sourceOriginalAndCapturedBytesUnchanged" == toJson true &&
    summary.getObjValD "sameBodiesAcrossFreshPasses" == toJson true &&
    summary.getObjValD "actualHooks" == toJson (18 : Nat)) "retain the complete negative real-corpus result first"
  let explanation ← read (records/"diagnostic/explanation.json")
  check ((explanation.getObjValD "validation").getObjValD "sameOrdinaryBody" == toJson true)
    "retain only a diagnostic bound to the ordinary actual body"
  let targets := #[root,runtime/"llvm-build",runtime/"llvm-diagnostic-build",
    runtime/"source/tools/research/LLVMProjectChecks.lean"]
  let inputs : Array (String × String) ← IO.ofExcept
    (fromJson? (← read (project/"docs/candidates/source-snapshot/protected-native-inputs.json")))
  check (targets.all fun target => !(inputs.any fun (path,_) =>
    path == target.toString || path.startsWith (target.toString++"/"))) "cleanup overlaps an active product input"
  let response ← IO.FS.readFile (runtime/"build/runtime.rsp")
  for target in targets do
    check (!(response.splitOn "\n").any (·.contains target.toString)) "current product links an ended observer"
  for (path,expected) in inputs do check ((← hash (.mk path)) == expected) "active native input changed before cleanup"
  let plan ← read (runtime/"llvm-plan.json")
  let original : System.FilePath := .mk (← IO.ofExcept (plan.getObjValAs? String "original"))
  let originalFiles : Array (String × String) ← IO.ofExcept (plan.getObjValAs? _ "originalFiles")
  for (name,expected) in originalFiles do check ((← hash (original/name)) == expected) "protected original changed"
  let mut files := 0
  let mut logicalBytes := 0
  for target in targets do
    let counts ← remove target
    files := files+counts.1
    logicalBytes := logicalBytes+counts.2
  for (path,expected) in inputs do check ((← hash (.mk path)) == expected) "cleanup changed an active native input"
  for (name,expected) in originalFiles do check ((← hash (original/name)) == expected) "cleanup changed the protected original"
  let mut duplicates := #[]
  for (discarded,kept) in [("pass-1-topic-1.txt","pass-0-topic-1.txt"),
      ("pass-1-topic-2.txt","pass-0-topic-2.txt"),("pass-1-topic-3.txt","pass-0-topic-3.txt"),
      ("diagnostic/body.txt","pass-0-topic-1.txt")] do
    check ((← IO.FS.readBinFile (records/discarded)) == (← IO.FS.readBinFile (records/kept)))
      "duplicate actual body differs"
    IO.FS.removeFile (records/discarded)
    duplicates := duplicates.push (discarded,kept)
  let guards : Array (String × Json) ← IO.ofExcept (fromJson? (← read (records/"guards.json")))
  for (name,stage) in [("build","complete-build"),("capture","capture"),("run","run"),
      ("diagnostic-build","diagnostic-build"),("diagnostic","diagnostic")] do
    let path := records/(name++".guard.json")
    let some (_,kept) := guards.find? (·.1 == "llvm-project-"++stage++".guard.json") |
      throw (IO.userError "consolidated guard is missing")
    check ((← read path) == kept) "consolidated guard differs"
    IO.FS.removeFile path
  IO.FS.removeFile (records/"warm.sample")
  write (records/"cleanup.json") (Json.mkObj [("targets",toJson targets),("files",toJson files),
    ("logicalBytes",toJson logicalBytes),("duplicateBodies",toJson duplicates),
    ("protectedNativeHashesBeforeAndAfter",toJson inputs.size),("protectedOriginalFiles",toJson originalFiles),
    ("sourceAndActiveProductRetained",toJson true),("archiveCreated",toJson false)])
  audit #["inspect",(runtime/"build").toString,(records/"product-after-cleanup.json").toString]
def serializeBodies : IO Unit := do
  idle
  let queries ← IO.ofExcept ((← read (records/"queries.json")).getArr?)
  let mut bodies := #[]
  for index in [:3] do
    let name := s!"pass-0-topic-{index+1}.txt"
    let bytes ← IO.FS.readBinFile (records/name)
    let some body := String.fromUTF8? bytes | throw (IO.userError "actual body is not UTF-8")
    let digest ← hash (records/name)
    check (toJson digest == (queries[index]?.getD Json.null).getObjValD "bodySha256")
      "actual body differs from its native receipt"
    bodies := bodies.push (Json.mkObj [("topic",toJson (index+1)),("sha256",toJson digest),
      ("utf8Bytes",toJson bytes.size),("body",toJson body),("formerPath",toJson name)])
  write (records/"bodies.json") (toJson bodies)
  let stored ← IO.ofExcept ((← read (records/"bodies.json")).getArr?)
  check (stored == bodies) "body serialization changed its recorded fields"
  for row in stored do
    let name ← IO.ofExcept (row.getObjValAs? String "formerPath")
    let body ← IO.ofExcept (row.getObjValAs? String "body")
    check (body.toUTF8 == (← IO.FS.readBinFile (records/name))) "body serialization changed original bytes"
    IO.FS.removeFile (records/name)
  let receipt ← read (records/"cleanup.json")
  write (records/"cleanup.json") (receipt.setObjVal! "bodyTextRepresentation"
    (Json.mkObj [("path",toJson "bodies.json"),("decodedUtf8BytesVerifiedExactly",toJson true),
      ("reason",toJson "retain original tabs and empty numbered lines without editing observed text for source whitespace checks")]))
end LLVMProjectStudy
def main : List String → IO Unit
  | ["prepare"] => LLVMProjectStudy.prepare
  | ["checked-build"] => LLVMProjectStudy.checkedBuild
  | ["complete-build"] => LLVMProjectStudy.completeBuild
  | ["capture"] => LLVMProjectStudy.capture
  | ["run"] => LLVMProjectStudy.run
  | ["prepare-diagnostic"] => LLVMProjectStudy.prepareDiagnostic
  | ["diagnostic"] => LLVMProjectStudy.diagnostic
  | ["explain"] => LLVMProjectStudy.explain
  | ["retain"] => LLVMProjectStudy.retain
  | ["cleanup"] => LLVMProjectStudy.cleanup
  | ["serialize-bodies"] => LLVMProjectStudy.serializeBodies
  | _ => throw (IO.userError "LLVMProjectStudy prepare|capture|run")
