import tools.research.StudyLocal
open Lean StudyLocal
namespace DeliveryCohortStudy
def parent := base/"practical-runtime/source-snapshot"
def root := base/"practical-runtime/complete-delivery-cohort"
def cohort := root/"cohort"
def records := project/"docs/practical-runtime/complete-delivery-cohort"
def executor := root/"build/StudyMain"
def finalizer := root/"finalizer-build/StudyMain"
def ready := cohort/"seed-ready-owned"
def checked : IO Unit := do
  check ((← hash (parent/"build/StudyMain")) == "720e64d9daf08a8c8f5e716b8cb877bc378253ba51fb43738dc33e05c1b6c534")
    "current product differs from the matched complete-delivery control"
def audit (args : Array String) : IO Unit := do
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args)
def prepare : IO Unit := do
  idle
  checked
  check (!(← root.pathExists) && !(← records.pathExists)) "a new current-product cohort is required"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  copyLocalArtifacts (parent/"build") (root/"build")
  let entry := root/"source/tools/research/StudyMain.lean"
  let pieces := (← IO.FS.readFile entry).splitOn "\ndef main (args : List String) : IO UInt32 := do\n"
  check (pieces.length == 2) "fixed product's observer entry changed"
  IO.FS.writeFile entry (pieces[0]!++"\ndef main (args : List String) : IO UInt32 := studyMain args\n")
  for relative in #["tools/research/StudyBuildMain.lean","docs/benchmarks/reseed-delivery-contract.json",
      "docs/benchmarks/llvm-three-topics.json","docs/benchmarks/readme-memory-facts.json"] do
    let target := root/"source"/relative
    IO.FS.createDirAll target.parent.get!
    IO.FS.writeFile target (← IO.FS.readFile (project/relative))
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (parent/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
  write (root/"settings.json") settings
  write (records/"plan.json") (Json.mkObj [
    ("runtimeSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("model",toJson "gpt-5.6-luna"),("effort",toJson "xhigh"),
    ("seedPromptSha256",toJson (← hash (base/"practical-runtime/cohort/prompts/topic-0.txt"))),
    ("order",toJson #["new empty-DB seed","1/1","1/2","1/3","2/1","2/2","2/3"]),
    ("controlEnvelope",toJson (120000 : Nat)),("candidateEnvelope",toJson (500000 : Nat)),
    ("nativeCompleteDeliveryIsNotTokenEvidence",toJson true),
    ("pilotRepetitionsPerCell",toJson (1 : Nat)),("adoptionMatchedRepetitionsPerCell",toJson (3 : Nat)),
    ("seedInclusiveTokenLimit",toJson (5000000 : Nat)),("seedTimeoutMs",toJson (900000 : Nat)),
    ("previousInterruptedSeedNotAccepted",toJson true),("limitsIncreased",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "complete-delivery-controller-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def bootstrap : IO Unit := do
  idle
  checked
  discard <| finished "complete-delivery-controller-build"
  audit #["inspect",(root/"build").toString,(records/"native.json").toString]
  audit #["common-sources",(parent/"build").toString,(root/"build").toString,(records/"sources.json").toString]
  let previous := base/"practical-runtime/cohort"
  let auth ← IO.FS.realPath (previous/"account/auth.json")
  discard <| command "/usr/bin/env" #["-u","LEAN_NUM_THREADS","EGGSHELL_STUDY_AUTH_FILE="++auth.toString,
    executor.toString,"bootstrap","prepare",cohort.toString,previous.toString,(parent/"prefix/libexec/eggshell").toString]
  -- Keep the actual current hook supervisor and launcher, rather than
  -- silently benchmarking the older full-runtime supervision path.
  for relative in ["bin/egg","bin/eggshelld","hooks/hooks.json",".codex-plugin/plugin.json"] do
    let source := parent/"prefix/plugins/eggshell"/relative
    let target := cohort/"prefix/plugins/eggshell"/relative
    IO.FS.writeFile target ((← IO.FS.readFile source).replace (parent/"prefix").toString (cohort/"prefix").toString)
    if relative.startsWith "bin/" then
      IO.setAccessRights target {user := {read := true,write := true,execution := true}}
  discard <| command "/bin/ln" #["-s",(← IO.FS.realPath (parent/"prefix/libexec/eggshell-hook")).toString,
    (cohort/"prefix/libexec/eggshell-hook").toString]
  let invoke := fun args => command "/usr/bin/env" (#["CODEX_HOME="++(cohort/"account").toString,
    "/Users/ovm/.nodebrew/current/bin/codex"]++args)
  IO.FS.writeFile (cohort/"marketplace-add.json")
    (← invoke #["plugin","marketplace","add",(cohort/"prefix").toString,"--json"])
  IO.FS.writeFile (cohort/"plugin-add.json") (← invoke #["plugin","add","eggshell@eggshell","--json"])
  let path := cohort/"discovery.input.json"
  let discovery ← read path
  let environment : Array (String × Option String) ← IO.ofExcept (discovery.getObjValAs? _ "environment")
  write path (discovery.setObjVal! "environment" (toJson (environment.filter (·.1 != "LEAN_NUM_THREADS")++
    #[("LEAN_NUM_THREADS",none)])))
  guard "complete-delivery-discovery" #["/usr/bin/env","-u","LEAN_NUM_THREADS",executor.toString,"probe",path.toString]
def gate : IO Unit := do
  idle
  checked
  let discovery ← finished "complete-delivery-discovery"
  discard <| command executor.toString #["bootstrap","trust-hooks",cohort.toString]
  discard <| command executor.toString #["bootstrap","seed-input",cohort.toString,"500000"]
  let path := cohort/"native-gate-input.json"
  let input ← read path
  let environment : Array (String × Option String) ← IO.ofExcept (input.getObjValAs? _ "environment")
  let environment := environment.filter (·.1 != "LEAN_NUM_THREADS")++#[("LEAN_NUM_THREADS",none)]
  write path (input.setObjVal! "environment" (toJson environment))
  write (records/"codex-discovery.json") (Json.mkObj [("guard",discovery),
    ("hooks",← read (cohort/"hooks-trusted.json")),("answeringModelCalls",toJson (0 : Nat))])
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let set := environment.filterMap fun (key,value) => value.map fun value => key++"="++value
  guard "complete-delivery-native-gate" (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++set++
    #[executor.toString,"seed-checks-generic",path.toString,(cohort/"native-gate").toString])
  let settings := base/"complete-delivery-native-gate.guard-settings.json"
  write settings ((← read settings).setObjVal! "record" (toJson (cohort/"native-gate.guard.json").toString))
def sealSeed : IO Unit := do
  idle
  checked
  let monitor ← read (cohort/"native-gate.guard.json")
  check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "exitCode" == toJson (0 : Nat) &&
    monitor.getObjValD "guardTriggered" == toJson false && monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "new current-product provenance gate has not succeeded and drained"
  discard <| command executor.toString #["bootstrap","seal-seed",cohort.toString]
  let settings := cohort/"seed-1.settings.json"
  write settings ((← read settings).setObjVal! "limitRssKiB" (toJson (4358524 : Nat)))
  write (records/"sealed-seed.json") (Json.mkObj [("runtimeSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("controllerSha256",toJson (← hash executor)),("seedPlanSha256",toJson (← hash (cohort/"seed-1.plan.json"))),
    ("limits",← read (cohort/"seed-1.limits.json")),("nativeGate",monitor),
    ("accepted",toJson false),("answeringModelCallsAtSealing",toJson (0 : Nat)),("adopted",toJson false)])
def rebuildGate : IO Unit := do
  idle
  checked
  let stopped ← read (cohort/"native-gate.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only correct the drained native gate"
  write (records/"initial-native-gate.json") (Json.mkObj [("guard",stopped),
    ("savedObservations",← read (cohort/"native-gate/result.json")),
    ("failure",toJson "native command pipes did not close: explicit warm auto-started a publisher retaining inherited stderr"),
    ("recoveredOwnedProcessGroups",toJson #[33221,33247,33324]),
    ("modelCalls",toJson (0 : Nat)),("productChanged",toJson false)])
  IO.FS.rename (cohort/"native-gate") (cohort/"initial-native-gate")
  IO.FS.rename (cohort/"native-gate.guard.json") (cohort/"initial-native-gate.guard.json")
  for name in ["StudySeedChecks","NativeSeedFinalize"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  guard "complete-delivery-owned-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def narrowGate : IO Unit := do
  idle
  let refused ← read (records/"owned-sources.json")
  check (refused.getObjValD "added" == toJson #["tools.research.StudyLaunchers"] &&
    refused.getObjValD "removed" == toJson (#[] : Array String)) "unexpected source-closure refusal"
  IO.FS.rename (records/"owned-sources.json") (records/"initial-owned-sources.json")
  IO.FS.rename (records/"owned-native.json") (records/"initial-owned-native.json")
  let marker := "/-- Freeze required DB-present source rows before a new chat's real hook runs."
  let previous := (← IO.FS.readFile (parent/"source/tools/research/StudySeedChecks.lean")).splitOn marker
  let edited := (← IO.FS.readFile (project/"tools/research/StudySeedChecks.lean")).splitOn marker
  check (previous.length == 2 && edited.length == 2) "native recall fixture boundary changed"
  -- Retain this fixed product's original admission/import prefix. The working
  -- checkout also has a later launcher-generator check, which is unrelated to
  -- owning preparation and does not describe this product's small supervisor.
  IO.FS.writeFile (root/"source/tools/research/StudySeedChecks.lean") (previous[0]!++marker++edited[1]!)
  guard "complete-delivery-owned-checks-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def ownedGate (tag : String := "complete-delivery-owned-build") : IO Unit := do
  idle
  checked
  discard <| finished tag
  audit #["inspect",(root/"build").toString,(records/"owned-native.json").toString]
  audit #["compare-sources",(parent/"build").toString,(root/"build").toString,(records/"owned-sources.json").toString,
    "tools.research.StudySeedChecks","tools.research.NativeSeedFinalize"]
  let path := cohort/"native-gate-input.json"
  let input ← read path
  let environment : Array (String × Option String) ← IO.ofExcept (input.getObjValAs? _ "environment")
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let set := environment.filterMap fun (key,value) => value.map fun value => key++"="++value
  guard "complete-delivery-owned-native-gate" (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++set++
    #[executor.toString,"seed-checks-generic",path.toString,(cohort/"native-gate").toString])
  let settings := base/"complete-delivery-owned-native-gate.guard-settings.json"
  write settings ((← read settings).setObjVal! "record" (toJson (cohort/"native-gate.guard.json").toString))
def finishSeed : IO Unit := do
  idle
  checked
  let monitor ← read (cohort/"seed-1.guard.json")
  let acquired := cohort/"study/seed-1"
  let result ← read (acquired/"result.json")
  check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "exitCode" == toJson (0 : Nat) &&
    monitor.getObjValD "guardTriggered" == toJson false && monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    result.getObjValD "completed" == toJson true &&
    (result.getObjValD "usage").getObjValD "finalUsageKnown" == toJson true)
    "a completed model turn and drained owned services are required before source finalization"
  write (records/"seed-generation.json") result
  write (records/"seed-generation-guard.json") monitor
  write (records/"seed-background-observations.json") (Json.mkObj [
    ("observedMessages",toJson #["bounded foreground numerical repair is pending","owned task cancelled",
      "retained unfinished source publication","timed out waiting for state.guard"]),
    ("completeStderrCaptured",toJson false),("countsKnown",toJson false),
    ("sourceAccepted",toJson false),("action",toJson "drain durable queued publication, finish preparation and audit every original before measuring model trials")])
  guard "complete-delivery-seed-finalize" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_DATA_ROOT="++(acquired/"data").toString,
    executor.toString,"seed-finalize",acquired.toString,(cohort/"seed-ready").toString]
def auditSeed : IO Unit := do
  idle
  discard <| finished "complete-delivery-seed-finalize-owned"
  let definitions := records/"task-definitions.json"
  check (!(← definitions.pathExists)) "freeze source requirements before inspecting delivery"
  IO.FS.writeFile definitions (← IO.FS.readFile (base.parent.get!/"task-definitions.json"))
  let acquired := cohort/"study/seed-1"
  guard "complete-delivery-seed-audit" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_DATA_ROOT="++(acquired/"data").toString,
    executor.toString,"seed-audit",acquired.toString,definitions.toString,
    (ready/"ready.egg").toString,(cohort/"seed-source-audit.json").toString]
def prepareFinalizer : IO Unit := do
  idle
  checked
  let stopped ← read (base/"complete-delivery-seed-finalize.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only correct the drained off-hook replay"
  let raw ← read (cohort/"seed-ready/finish-replay/step-0/stdout")
  check (raw.getObjValD "error" == toJson "DB synaptic index owner is busy") "a different replay failure needs diagnosis"
  write (records/"initial-finalization.json") (Json.mkObj [("guard",stopped),("reply",raw),
    ("queuedBefore",← read (cohort/"seed-ready/queued-before.json")),
    ("modelRepeated",toJson false),("productChanged",toJson false),
    ("correction",toJson "exclusive retained replay worker first; owned preparation service only for warm afterward")])
  let source := root/"finalizer-source"
  check (!(← source.pathExists) && !(← (root/"finalizer-build").pathExists)) "keep the sealed acquisition harness unchanged"
  discard <| command "/bin/cp" #["-cR",(root/"source").toString,source.toString]
  copyLocalArtifacts (root/"build") (root/"finalizer-build")
  for name in ["NativeSeedFinalize","StudyReadiness"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson source.toString)
    |>.setObjVal! "output" (toJson (root/"finalizer-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString,(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
  write (root/"finalizer-settings.json") settings
  guard "complete-delivery-finalizer-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"finalizer-settings.json").toString]
def runFinalizer : IO Unit := do
  idle
  checked
  discard <| finished "complete-delivery-finalizer-build"
  audit #["inspect",(root/"finalizer-build").toString,(records/"finalizer-native.json").toString]
  audit #["compare-sources",(root/"build").toString,(root/"finalizer-build").toString,(records/"finalizer-sources.json").toString,
    "tools.research.NativeSeedFinalize","tools.research.StudyReadiness"]
  let acquired := cohort/"study/seed-1"
  guard "complete-delivery-seed-finalize-owned" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_DATA_ROOT="++(acquired/"data").toString,
    finalizer.toString,"seed-finalize",acquired.toString,ready.toString]
def readSeed : IO Unit := do
  idle
  discard <| finished "complete-delivery-seed-audit"
  guard "complete-delivery-seed-read" #["/usr/bin/env","-u","LEAN_NUM_THREADS",executor.toString,"read-coverage",
    (ready/"ready.egg").toString,"/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project",
    (records/"task-definitions.json").toString,(cohort/"seed-read-coverage.json").toString]
def historySeed : IO Unit := do
  idle
  discard <| finished "complete-delivery-seed-read"
  guard "complete-delivery-seed-history" #["/usr/bin/env","-u","LEAN_NUM_THREADS",executor.toString,"history","freeze",
    (cohort/"study/seed-1/work.egg").toString,(cohort/"study/seed-1/data").toString,(cohort/"seed-history").toString]
def acceptSeed : IO Unit := do
  idle
  discard <| finished "complete-delivery-seed-read"
  let source ← read (cohort/"seed-source-audit.json")
  let coverage ← read (cohort/"seed-read-coverage.json")
  check (source.getObjValD "seedAccepted" == toJson true && source.getObjValD "nativeJournalComplete" == toJson true &&
    source.getObjValD "portableOriginsComplete" == toJson true && source.getObjValD "sourceFactsUnchanged" == toJson true &&
    coverage.getObjValD "publicationUnchanged" == toJson true &&
    coverage.getObjValD "conflictingCanonicalRows" == toJson (0 : Nat) &&
    coverage.getObjValD "payloadMismatches" == toJson (#[] : Array Json)) "do not accept incomplete native history"
  write (records/"seed-source-audit.json") source
  write (records/"seed-read-coverage.json") coverage
  write (records/"seed-readiness.json") (← read (ready/"view-readiness.json"))
  write (records/"accepted-seed.json") (Json.mkObj [("runtime",source.getObjValD "runtime"),
    ("seedAccepted",toJson true),("nativeStarts",source.getObjValD "nativeStarts"),
    ("nativeFinishes",source.getObjValD "nativeFinishes"),("originalDocuments",source.getObjValD "originalDocuments"),
    ("originalRows",source.getObjValD "originalRows"),("availability",source.getObjValD "availability"),
    ("seedUsage",(← read (records/"seed-generation.json")).getObjValD "usage"),
    ("sourceAuditReadHandoffBodies",source.getObjValD "handoffBodiesRead"),
    ("modelStagesCompleted",toJson (0 : Nat)),("adopted",toJson false)])
def prepareStages : IO Unit := do
  idle
  discard <| finished "complete-delivery-seed-finalize-owned"
  let mut witnesses := #[]
  for name in ["NativeSeedFinalize","StudyReadiness"] do
    witnesses := witnesses.push (name,← read (root/"finalizer-build"/("tools_research_"++name++".source")))
  write (records/"initial-finalizer-witnesses.json") (Json.mkObj [("sources",toJson witnesses),
    ("native",← read (records/"finalizer-native.json")),("comparison",← read (records/"finalizer-sources.json"))])
  for name in ["StudyPrepare","StudyHistory","StudyStages","StudyStageClose"] do
    IO.FS.writeFile (root/"finalizer-source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  let entry := root/"finalizer-source/tools/research/StudyMain.lean"
  let text ← IO.FS.readFile entry
  let prepare := "StudyStages.run input digest; return 0"
  let close := "StudyStageClose.run stage digest output; return 0"
  check ((text.splitOn prepare).length == 2 && (text.splitOn close).length == 2) "delegated preparation entry changed"
  IO.FS.writeFile entry (text.replace prepare "StudyStages.run input digest (some (← IO.appPath).toString); return 0"
    |>.replace close "StudyStageClose.run stage digest output (some (← IO.appPath).toString); return 0")
  guard "complete-delivery-preparation-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"finalizer-settings.json").toString]
def stagesReady : IO Unit := do
  idle
  checked
  discard <| finished "complete-delivery-preparation-build"
  audit #["inspect",(root/"finalizer-build").toString,(records/"preparation-native.json").toString]
  audit #["compare-sources",(root/"build").toString,(root/"finalizer-build").toString,(records/"preparation-sources.json").toString,
    "tools.research.NativeSeedFinalize","tools.research.StudyReadiness","tools.research.StudyPrepare",
    "tools.research.StudyHistory","tools.research.StudyStages","tools.research.StudyStageClose"]
  let core : Array (String × String) ← IO.ofExcept (fromJson? (← read (parent/"build/Main.dependencies")))
  let before ← read (records/"owned-sources.json")
  let after ← read (records/"preparation-sources.json")
  let first : Array String ← IO.ofExcept (before.getObjValAs? _ "changedSourcesAndLiteralInputs")
  let second : Array String ← IO.ofExcept (after.getObjValAs? _ "changedSourcesAndLiteralInputs")
  check ((first++second).all (fun name => !(core.any (·.1 == name))) &&
    before.getObjValD "added" == toJson (#[] : Array String) &&
    after.getObjValD "added" == toJson (#[] : Array String)) "an administrative change reached the actual Main dependency closure"
  write (records/"product-core.json") (Json.mkObj [("runtimeSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("mainDependencies",toJson core.size),("sourceOrLiteralChangesInMainClosure",toJson (#[] : Array String)),
    ("sealedAcquisitionHarnessChanged",toJson false),
    ("preparationControllerSha256",toJson (← hash finalizer)),("adopted",toJson false)])
  let settingsPath := base/"complete-delivery-seed-history.guard-settings.json"
  check (!(← (base/"complete-delivery-seed-history.guard.json").pathExists)) "history freeze has already started"
  let settings ← read settingsPath
  let args : Array String ← IO.ofExcept (settings.getObjValAs? _ "command")
  check (args[3]? == some executor.toString && args[4]? == some "history") "unexpected unexecuted history command"
  write settingsPath (settings.setObjVal! "command" (toJson (args.set! 3 finalizer.toString)))
def capacity : IO Unit := do
  idle
  let path := records/"seed-source-audit.json"
  let audit ← read path
  check (audit.getObjValD "seedAccepted" == toJson true && audit.getObjValD "handoffBodiesRead" == toJson (0 : Nat))
    "use independently frozen native evidence, never selected delivery labels"
  let topics ← IO.ofExcept (audit.getObjValAs? (Array Json) "availability")
  let mut bounds := #[]
  for topic in topics do
    let units ← IO.ofExcept ((topic.getObjValD "frozenEvidence").getObjValAs? (Array Json) "units")
    let mut chosen := #[]
    let mut characters := 0
    for unit in units do
      let alternatives ← IO.ofExcept (unit.getObjValAs? (Array Json) "alternatives")
      let mut best : Option (Nat × Json) := none
      for alternative in alternatives do
        -- File intervals are line numbers; only original-output intervals
        -- are character coordinates. Never compare their integer widths.
        let subject := alternative.getObjValD "subject"
        let .ok payload := subject.getObjVal? "original" | continue
        let original := payload.getObjValD "original"
        let size ← IO.ofExcept (original.getObjValAs? Nat "chars")
        let first ← IO.ofExcept (alternative.getObjValAs? Nat "first")
        let last ← IO.ofExcept (alternative.getObjValAs? Nat "last")
        check (0 < first && first ≤ last && last ≤ size) "invalid closed original-output character interval"
        let width := last+1-first
        if best.all (fun prior => width < prior.1) then best := some (width,alternative)
      let some (width,witness) := best | throw (IO.userError "no original-output alternative; do not invent a character bound")
      characters := characters+width
      chosen := chosen.push (Json.mkObj [("names",unit.getObjValD "names"),("originalRange",witness),
        ("characters",toJson width)])
    bounds := bounds.push (Json.mkObj [("topic",topic.getObjValD "topic"),("units",toJson units.size),
      ("rawCharacterUpperBoundWithoutSharing",toJson characters),("witnesses",toJson chosen)])
  write (records/"capacity.json") (Json.mkObj [("frozenSourceAuditSha256",toJson (← hash path)),
    ("bounds",toJson bounds),("diagnosticOnly",toJson true),("includesFramingOrPrerequisites",toJson false),
    ("feasibleProductPacketProven",toJson false),("labelsPassedToRuntime",toJson false),
    ("modelCalls",toJson (0 : Nat)),("adopted",toJson false)])
partial def commandEvidence (path : System.FilePath) (relative : String := "") : IO (Array (String × String)) := do
  let mut rows := #[]
  for entry in ← path.readDir do
    let name := if relative.isEmpty then entry.fileName else relative++"/"++entry.fileName
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then
      if !entry.fileName.endsWith ".egg" && !["data","recovery-data","recall-data","src","tmp"].contains entry.fileName then
        rows := rows++(← commandEvidence entry.path name)
    else if info.type == .file && (entry.fileName.endsWith ".json" ||
        ["stdin","stdout","stderr"].contains entry.fileName) then
      rows := rows.push (name,← IO.FS.readFile entry.path)
  return rows
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
def checkpoint : IO Unit := do
  idle
  checked
  discard <| finished "complete-delivery-seed-history"
  check (!(← (records/"retired-fixtures.json").pathExists)) "preserve the completed fixture checkpoint"
  let transcript := cohort/"study/seed-1/rpc/exchange.jsonl"
  let mut samples : Array (String × Nat) := #[]
  for line in (← IO.FS.readFile transcript).splitOn "\n" do
    if line.isEmpty then continue
    let row ← IO.ofExcept (Json.parse line)
    let message := row.getObjValD "message"
    if row.getObjValD "direction" != toJson "server" || message.getObjValD "method" != toJson "hook/completed" then continue
    let hook := (message.getObjValD "params").getObjValD "run"
    check (hook.getObjValD "status" == toJson "completed") "retain failed hooks in the checkpoint"
    samples := samples.push (← IO.ofExcept (hook.getObjValAs? String "eventName"),← IO.ofExcept (hook.getObjValAs? Nat "durationMs"))
  let mut timings := #[]
  for event in (samples.map (·.1)).toList.eraseDups do
    let values := (samples.filterMap fun (name,ms) => if name == event then some ms else none).qsort (· < ·)
    let count := values.size
    check (count > 0) "empty measured hook group"
    timings := timings.push (Json.mkObj [("event",toJson event),("count",toJson count),
      ("p95Ms",toJson values[((95*count+99)/100)-1]!),("maxMs",toJson values[count-1]!)])
  write (records/"seed-hook-timing.json") (Json.mkObj [("samples",toJson samples.size),("events",toJson timings),
    ("source",toJson "App Server hook/completed durationMs; host scheduling is included"),
    ("productionP99Proven",toJson false)])
  let mut witnesses := #[]
  for name in ["StudySeedChecks","NativeSeedFinalize","StudyMain"] do
    witnesses := witnesses.push (name,← read (root/"build"/("tools_research_"++name++".source")))
  write (records/"acquisition-witnesses.json") (toJson witnesses)
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "complete-delivery-" && entry.fileName.endsWith ".guard.json" then
      let report ← read entry.path
      check (report.getObjValD "state" == toJson "finished" && report.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "a cohort workload still owns processes"
      guards := guards.push (entry.fileName,report)
  write (records/"guards.json") (toJson guards)
  write (records/"native-gate.json") (← read (cohort/"native-gate/result.json"))
  write (records/"native-gate-recovery.json") (← read (cohort/"native-gate/recovery.json"))
  write (records/"native-gate-recall.json") (← read (cohort/"native-gate/recall-audit.json"))
  let mut evidence := #[]
  for name in ["initial-native-gate","native-gate","seed-ready"] do
    evidence := evidence.push (name,← commandEvidence (cohort/name))
  let packed := toJson evidence
  write (records/"fixture-commands.json") packed
  check ((← read (records/"fixture-commands.json")) == packed) "fixture command evidence round trip differs"
  let seed ← read (cohort/"seed-1.plan.json")
  let gate := seed.getObjValD "gate"
  let mut sealedGate : Array (System.FilePath × String) := #[]
  for field in ["report","guard","shutdown","recovery","publisherShutdown"] do
    let artifact := gate.getObjValD field
    sealedGate := sealedGate.push (System.FilePath.mk (← IO.ofExcept (artifact.getObjValAs? String "path")),
      ← IO.ofExcept (artifact.getObjValAs? String "sha256"))
  for (path,digest) in sealedGate do check ((← hash path) == digest) "sealed acquisition gate changed before fixture retirement"
  let mut removed := (0,0)
  for name in ["initial-native-gate","seed-ready"] do
    let count ← remove (cohort/name)
    removed := (removed.1+count.1,removed.2+count.2)
  for entry in ← (cohort/"native-gate").readDir do
    if sealedGate.any (·.1 == entry.path) then continue
    let count ← remove entry.path
    removed := (removed.1+count.1,removed.2+count.2)
  for (path,digest) in sealedGate do check ((← hash path) == digest) "fixture retirement changed a sealed model input"
  write (records/"retired-fixtures.json") (Json.mkObj [("files",toJson removed.1),("logicalBytes",toJson removed.2),
    ("archiveCreated",toJson false),("sealedGateUnchanged",toJson true),
    ("activeSeedHistoryAndRuntimeRetained",toJson true),("adopted",toJson false)])
end DeliveryCohortStudy
def main : List String → IO Unit
  | ["prepare"] => DeliveryCohortStudy.prepare
  | ["bootstrap"] => DeliveryCohortStudy.bootstrap
  | ["gate"] => DeliveryCohortStudy.gate
  | ["seal-seed"] => DeliveryCohortStudy.sealSeed
  | ["rebuild-gate"] => DeliveryCohortStudy.rebuildGate
  | ["owned-gate"] => DeliveryCohortStudy.ownedGate
  | ["narrow-gate"] => DeliveryCohortStudy.narrowGate
  | ["owned-gate-checked"] => DeliveryCohortStudy.ownedGate "complete-delivery-owned-checks-build"
  | ["finish-seed"] => DeliveryCohortStudy.finishSeed
  | ["audit-seed"] => DeliveryCohortStudy.auditSeed
  | ["prepare-finalizer"] => DeliveryCohortStudy.prepareFinalizer
  | ["run-finalizer"] => DeliveryCohortStudy.runFinalizer
  | ["read-seed"] => DeliveryCohortStudy.readSeed
  | ["history-seed"] => DeliveryCohortStudy.historySeed
  | ["accept-seed"] => DeliveryCohortStudy.acceptSeed
  | ["prepare-stages"] => DeliveryCohortStudy.prepareStages
  | ["stages-ready"] => DeliveryCohortStudy.stagesReady
  | ["capacity"] => DeliveryCohortStudy.capacity
  | ["checkpoint"] => DeliveryCohortStudy.checkpoint
  | _ => throw (IO.userError "DeliveryCohortStudy prepare|bootstrap|gate|seal-seed")
