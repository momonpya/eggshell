import tools.research.StudyLocal
open Lean StudyLocal
namespace RuntimeStudy
def selected := base/"current-six/stable-source-rows/build"
def build := base/"register-rounds/build"
def records := project/"docs/candidates/register-rounds"
def root := base/"register-rounds-runtime"
def src := root/"source"
def out := root/"build"
def installation := root/"prefix"
def logs := project/"docs/candidates/register-rounds/runtime"
def parentPrefix := base/"current-six/fixed-sequence/cohort/prefix"
def order : Array String := #["a-first","b-first","b-second","a-second"]
def observerSource := root/"observer-source"
def observerBuild := root/"observer-build"
def clean (tag : String) : IO Json := do
  let value ← finished tag
  check (value.getObjValD "guardTriggered" == toJson false && value.getObjValD "reason" == Json.null)
    "supervisor did not finish normally"
  return value
def boundCore (path : System.FilePath) : IO String :=
  command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/RegisterRoundsStudy.lean").toString,"runtime-source",path.toString]

def helperCache : IO Unit := do
  IO.FS.createDirAll (out/"lib/tools/research")
  for suffix in ["o","source","dependencies"] do
    let name := "tools_research_RegisterRounds."++suffix
    IO.FS.writeBinFile (out/name) (← IO.FS.readBinFile (build/name))
  for file in ← (build/"lib/tools/research").readDir do
    if file.fileName.startsWith "RegisterRounds." then
      IO.FS.writeBinFile (out/"lib/tools/research"/file.fileName) (← IO.FS.readBinFile file.path)

partial def removeOwned (path : System.FilePath) : IO (Nat × Nat) := do
  let stat ← path.symlinkMetadata
  if stat.type == .dir then
    let mut total := (0,0)
    for child in ← path.readDir do
      let deleted ← removeOwned child.path
      total := (total.1+deleted.1,total.2+deleted.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if stat.type == .file then stat.byteSize.toNat else 0)

partial def checkRetiredLinks (path retired : System.FilePath) : IO Nat := do
  let actual ← IO.FS.realPath path
  check (!actual.toString.startsWith (retired.toString++"/")) "active compiler input points into the old component"
  if (← path.symlinkMetadata).type == .dir then
    let mut total := 0
    for child in ← path.readDir do total := total+(← checkRetiredLinks child.path retired)
    return total
  return 1

def main (args : List String) : IO Unit := do
  if args == ["setup"] then
    idle
    discard <| clean "register-rounds-component-packed"
    check ((← read (records/"retired-unused.json")).getObjValD "state" == toJson "finished")
      "finish the planned space recovery first"
    check (!(← root.pathExists)) "fresh isolated runtime required"
    check ((← hash (selected/"StudyMain")) == "dd53c89bc450b66b58dd57d104ccbc82f32ca6345fa9666125e7feb03017000e")
      "selected product changed"
    IO.FS.createDirAll logs
    materialize selected src out "tools.research.OwnedSelectionRuntime" "register-rounds-runtime-settings.json"
    let helper := project/"tools/research/RegisterRounds.lean"
    let sealed ← read (records/"runtime-packed.json")
    let expected : Array (String × String) ← IO.ofExcept (fromJson? (sealed.getObjValD "helperSources"))
    check (expected.contains ("tools.research.RegisterRounds",← hash helper)) "proved native helper changed"
    IO.FS.writeFile (src/"tools/research/RegisterRounds.lean") (← IO.FS.readFile helper)
    let path := src/"Eggshell/Blake3.lean"
    IO.FS.writeFile path (← boundCore path)
    helperCache
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",(selected.parent.get!/"source/Eggshell/Blake3.lean").toString,path.toString]}
    check (diff.exitCode == 1) "one explicit core change required"
    IO.FS.writeFile (logs/"core.patch") diff.stdout
    IO.FS.writeFile (logs/"axioms.txt") (← IO.FS.readFile (build/"tools_research_RegisterRounds-lean.stdout"))
    write (logs/"plan.json") (Json.mkObj [("comparison",toJson order),("countsPerArm",toJson (#[(4 : Nat),16])),
      ("preflight",toJson "three canonical topic bodies plus four concurrent real hooks before measured waves"),
      ("changedCoreModules",toJson #["Eggshell.Blake3"]),("addedModule",toJson "tools.research.RegisterRounds"),
      ("treatment",toJson "proved compiler binding to direct fixed-lane seven-round compression;all hash bytes preserved"),
      ("unchanged",toJson "WorkGraph,ranking,Exact,three synapse edges,models,prompts,source bodies,ACK,deadlines,resource limits,pools,caches,locks"),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  else if args == ["build"] then
    guard "register-rounds-runtime-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"register-rounds-runtime-settings.json").toString]
  else if args == ["audit"] then
    discard <| clean "register-rounds-runtime-build"
    guard "register-rounds-runtime-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/RegisterRoundsRuntimeStudy.lean").toString,"audit-worker"]
  else if args == ["audit-worker"] then
    let call := fun parameters => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++parameters)
    discard <| call #["inspect",out.toString,(logs/"native.json").toString]
    discard <| call #["compare-sources",selected.toString,out.toString,(logs/"sources.json").toString,
      "Eggshell.Blake3","+tools.research.RegisterRounds"]
    check ((← read (selected/"tools_research_OwnedSelectionRuntime.source")) ==
      (← read (out/"tools_research_OwnedSelectionRuntime.source"))) "entry or embedded literals changed"
    let (helper,literals) : String × Array (String × String) ← IO.ofExcept
      (fromJson? (← read (out/"tools_research_RegisterRounds.source")))
    check (helper == (← IO.FS.readFile (project/"tools/research/RegisterRounds.lean")) && literals.isEmpty)
      "native helper is not the reviewed proof"
    let (actual,embedded) : String × Array (String × String) ← IO.ofExcept
      (fromJson? (← read (out/"Eggshell_Blake3.source")))
    check (actual == (← boundCore (selected.parent.get!/"source/Eggshell/Blake3.lean")) && embedded.isEmpty)
      "core changed beyond the proved binding"
    let symbols ← command "/usr/bin/nm" #["-u",(out/"Eggshell_Blake3.o").toString]
    check (symbols.contains "RegisterRounds_optimized") "actual compressor does not call the candidate"
    IO.FS.writeFile (logs/"consumer-symbols.txt") symbols
    write (logs/"runtime.json") (Json.mkObj [("candidateSha256",toJson (← hash (out/"StudyMain"))),
      ("parentSha256",toJson (← hash (selected/"StudyMain"))),("entrySourceAndLiteralsUnchanged",toJson true),
      ("declaredCoreAndHelperExactlyMatch",toJson true),("adopted",toJson false)])
  else if args == ["install"] then
    discard <| clean "register-rounds-runtime-audit"
    check (!(← installation.pathExists)) "fresh installation required"
    let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let oldPlugin : System.FilePath := .mk (← IO.ofExcept (original.getObjValAs? String "plugin"))
    let plugin := installation/"share/eggshell/codex-plugin"
    IO.FS.createDirAll (installation/"libexec")
    IO.FS.createDirAll (plugin/"bin")
    discard <| command "/bin/ln" #["-s",(out/"StudyMain").toString,(installation/"libexec/eggshell").toString]
    discard <| command "/bin/ln" #["-s",(parentPrefix/"share/eggshell/minilm").toString,(installation/"share/eggshell/minilm").toString]
    for name in ["egg","eggshelld"] do
      let launcher ← IO.FS.readFile (oldPlugin/"bin"/name)
      check (launcher.contains parentPrefix.toString) "different launcher boundary"
      IO.FS.writeFile (plugin/"bin"/name) (launcher.replace parentPrefix.toString installation.toString)
      discard <| command "/bin/chmod" #["755",(plugin/"bin"/name).toString]
    check ((← IO.FS.realPath (parentPrefix/"share/eggshell/minilm")) ==
      (← IO.FS.realPath (installation/"share/eggshell/minilm"))) "model assets changed"
  else if args == ["retire-component"] then
    idle
    discard <| clean "register-rounds-runtime-audit"
    check (!(← (logs/"retired-component.json").pathExists)) "preserve retirement record"
    let old := base/"register-rounds"
    let mut checked := 0
    for path in #[selected/"lib",out/"lib",base/"study-local-lib"] do
      checked := checked+(← checkRetiredLinks path old)
    let response ← IO.FS.readFile (out/"runtime.rsp")
    check (!response.contains (old.toString++"/")) "actual product still links the component"
    let kept := #[selected/"StudyMain",out/"StudyMain",base/"current-six/fixed-sequence/controller-build/StudyMain",
      base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",base/"byte-pages-prefix/libexec/eggshell"]
    let digests ← kept.mapM hash
    let mut removed := #[]
    for name in ["source","build","run","run-packed"] do
      let target := old/name
      check ((← target.symlinkMetadata).type == .dir) "retired component root must be owned"
      let result ← removeOwned target
      removed := removed.push (target.toString,result.1,result.2)
    check ((← kept.mapM hash) == digests) "protected executable changed"
    write (logs/"retired-component.json") (Json.mkObj [("deleted",toJson removed),
      ("activeCompilerInputsChecked",toJson checked),("retainedInputs",toJson (kept.zip digests)),
      ("protectedHashesUnchanged",toJson true),("archiveCreated",toJson false)])
  else if args == ["observer-setup"] then
    idle
    let prior ← read (project/"docs/candidates/routing-leaf-image/runtime-observer-fixed.json")
    let helpers : Array (String × String) ← IO.ofExcept (fromJson? (prior.getObjValD "helperSources"))
    check (helpers.contains ("tools.research.PreparedRoutingObserver",← hash (project/"tools/research/PreparedRoutingObserver.lean")))
      "observer differs from its native child-lifecycle controls"
    check (toJson (← hash (out/"StudyMain")) == (← read (logs/"runtime.json")).getObjValD "candidateSha256")
      "full product candidate changed"
    materialize out observerSource observerBuild "tools.research.RequestPhaseSample" "register-rounds-observer-settings.json"
    IO.FS.writeFile (observerSource/"tools/research/PreparedRoutingObserver.lean")
      (← IO.FS.readFile (project/"tools/research/PreparedRoutingObserver.lean"))
    write (logs/"profile-plan.json") (Json.mkObj [("reason",toJson "previous turn made verified progress:11.190% lower sixteen-client wall time;remaining execution is not explained by2-10ms admission waits"),
      ("productSha256",toJson (← hash (out/"StudyMain"))),("sampleSeconds",toJson (3 : Nat)),
      ("phaseDelayMs",toJson (2000 : Nat)),("clientCount",toJson (4 : Nat)),
      ("observation",toJson "one late owned-publisher CPU sample;small query-stage timestamps enabled;canonical bodies and ACK required"),
      ("unchanged",toJson "product source,model,ranking,three synapses,Exact,source snapshot,deadline,resource limits"),
      ("interferencePossible",toJson true),("performanceComparison",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guard "register-rounds-observer-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"register-rounds-observer-settings.json").toString]
  else if args == ["observer-audit"] then
    discard <| clean "register-rounds-observer-build"
    guard "register-rounds-observer-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/RegisterRoundsRuntimeStudy.lean").toString,"observer-audit-worker"]
  else if args == ["observer-audit-worker"] then
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",observerBuild.toString,(logs/"profile-observer-native.json").toString]
    let names := #["tools.research.PreparedRoutingObserver","tools.research.RequestPhaseSample"]
    let modules : Array Json ← IO.ofExcept ((← read (observerBuild/"build.json")).getObjValAs? (Array Json) "modules")
    check (modules.size == names.size && modules.all (fun row => names.contains ((row.getObjValAs? String "module").toOption.getD "")))
      "observer unexpectedly links a product implementation"
    let mut witnesses := #[]
    for name in names do
      let (text,literals) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (observerBuild/(name.replace "." "_"++".source"))))
      let path := project/(name.replace "." "/"++".lean")
      check (text == (← IO.FS.readFile path) && literals.isEmpty) "native observer source changed"
      witnesses := witnesses.push (name,← hash path)
    write (logs/"profile-observer.json") (Json.mkObj [("sha256",toJson (← hash (observerBuild/"StudyMain"))),
      ("helperSources",toJson witnesses),("productSourceChanged",toJson false)])
  else if args.head? == some "prepare" then
    let [_,label] := args | throw (IO.userError "prepare <preflight|declared arm>")
    discard <| clean "register-rounds-runtime-audit"
    let profiling := label == "profile"
    if profiling then discard <| clean "register-rounds-observer-audit"
    let preflight := label == "preflight" || profiling
    let position ← if preflight then pure 0 else do
      let some n := order.findIdx? (· == label) | throw (IO.userError "undeclared arm")
      pure n
    if !preflight then
      let previous := if position == 0 then "preflight" else order[position-1]!
      discard <| clean ("register-rounds-runtime-"++previous)
      check ((← read (logs/(previous++".json"))).getObjValD "passed" == toJson true) "previous stage did not pass"
    let candidate := preflight || label.startsWith "b"
    let chosen := if candidate then installation else parentPrefix
    let runtime := chosen/"libexec/eggshell"
    let declared ← read (logs/"runtime.json")
    let digest := declared.getObjValD (if candidate then "candidateSha256" else "parentSha256")
    check (digest == toJson (← hash runtime)) "sealed runtime changed"
    let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let output := root/label
    let config := output/"config.toml"
    let plugin ← if candidate then pure (installation/"share/eggshell/codex-plugin").toString
      else IO.ofExcept (original.getObjValAs? String "plugin")
    let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
    let environment := environment.map fun (key,value) => (key,match key with
      | "EGGSHELL_PREFIX" => some chosen.toString | "PLUGIN_ROOT" => some plugin
      | "EGGSHELL_CONFIG" => some config.toString
      | "EGGSHELL_TRACE_QUERY_STAGES" => if profiling then some "1" else value
      | _ => value)
    let input := original.setObjVal! "output" (toJson output.toString)
      |>.setObjVal! "config" (toJson config.toString) |>.setObjVal! "environment" (toJson environment)
      |>.setObjVal! "runtime" (toJson runtime.toString) |>.setObjVal! "runtimeSha256" digest
      |>.setObjVal! "plugin" (toJson plugin)
    let input := if preflight then input.setObjVal! "counts" (toJson (#[(4 : Nat)]))
      |>.setObjVal! "diagnostic" (toJson true) else input
    let path := root/(label++"-input.json")
    check (!(← path.pathExists)) "preserve previous arm"
    write path input
    let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
    let operation ← if profiling then do
      let observer := observerBuild/"StudyMain"
      check ((← read (logs/"profile-observer.json")).getObjValD "sha256" == toJson (← hash observer)) "observer executable changed"
      pure #[observer.toString,path.toString]
    else pure #[runtime.toString,"owned-selection-capacity",path.toString]
    guard ("register-rounds-runtime-"++label) (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++operation)
  else if args.head? == some "collect" then
    let [_,label] := args | throw (IO.userError "collect <label>")
    let monitor ← clean ("register-rounds-runtime-"++label)
    check (!(← (logs/(label++".json")).pathExists)) "preserve collected result"
    let report ← read (root/label/"report.json")
    let input ← read (root/(label++"-input.json"))
    let sourceRoot : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
    let expected : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
    for (file,digest) in expected do check ((← hash (sourceRoot/file)) == digest) "source changed"
    check (report.getObjValD "allPhasesPassed" == toJson true ||
      ((label == "preflight" || label == "profile") &&
        (← read (root/label/"phase-4/result.json")).getObjValD "passed" == toJson true)) "workload failed"
    write (logs/(label++".json")) (Json.mkObj [("guard",monitor),("report",report),("passed",toJson true),
      ("sourceFilesUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    if label == "profile" then
      let sampling ← read (root/label/"sampling.json")
      check (sampling.getObjValD "sampleExitCode" == toJson (0 : Nat)) "native CPU sample failed"
      let phases : Array Json ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
      check (phases.size == 1 && phases[0]!.getObjValD "passed" == toJson true) "diagnostic wave failed"
      let dataRoot : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
      let mut actors := #[]
      for client in ← IO.ofExcept (phases[0]!.getObjValAs? (Array Json) "rows") do
        let id ← IO.ofExcept (client.getObjValAs? String "receipt")
        let pages ← read (dataRoot/"receipts"/id/"request-pages.json")
        let operation ← read (dataRoot/"receipts"/id/"operation-service.json")
        check (pages.getObjValD "pid" == sampling.getObjValD "pid" &&
          operation.getObjValD "pid" == sampling.getObjValD "pid") "stage record belongs to a different publisher"
        let stages : Array (String × Nat) ← IO.ofExcept (fromJson? ((pages.getObjValD "data").getObjValD "queryStages"))
        check (stages.size > 1) "query-stage observation is empty"
        for i in [:stages.size-1] do check (stages[i]!.2 ≤ stages[i+1]!.2) "query-stage clock decreased"
        let mut intervals := #[]
        for (name,began) in stages do
          if !name.endsWith ":start" then continue
          let prefixName := (name.dropEnd 6).toString
          if let some (_,ended) := stages.find? (·.1 == prefixName++":end") then
            check (began ≤ ended) "query-stage interval decreased"
            intervals := intervals.push (prefixName,ended-began)
        let some (_,executeEnd) := stages.find? (·.1 == "execute:end") | throw (IO.userError "missing execute end")
        let op := operation.getObjValD "data"
        let finished ← IO.ofExcept (op.getObjValAs? Nat "finishedAt")
        check (executeEnd ≤ finished) "operation finished before its execution"
        let ready := (op.getObjValAs? Nat "readyMs").toOption
        let work ← IO.ofExcept (op.getObjValAs? Nat "workMs")
        actors := actors.push (Json.mkObj [("client",client),("pages",pages),("operation",operation),
          ("intervalMs",toJson intervals),("postExecuteReplyMs",toJson (finished-executeEnd)),
          ("afterReadyOperationMs",toJson (ready.map (work-·)))])
      write (logs/"profile-result.json") (Json.mkObj [("sampling",sampling),("actors",toJson actors),
        ("report",report),("guard",monitor),("sourceFilesUnchanged",toJson true),
        ("sampleSha256",toJson (← hash (root/label/"publisher-late.sample.txt"))),
        ("performanceComparison",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  else if args.head? == some "retire-arm" then
    let [_,label] := args | throw (IO.userError "retire-arm <collected label>")
    idle
    discard <| clean ("register-rounds-runtime-"++label)
    check (!(← (logs/(label++"-retired.json")).pathExists)) "preserve retirement evidence"
    let value ← read (logs/(label++".json"))
    check (value.getObjValD "passed" == toJson true) "retain unsuccessful state for diagnosis"
    let phases : Array Json ← IO.ofExcept (fromJson? ((value.getObjValD "report").getObjValD "phases"))
    let mut clients : Array Json ← IO.ofExcept (fromJson? (← read (root/label/"prime.json")))
    for phase in phases do clients := clients++(← IO.ofExcept (phase.getObjValAs? (Array Json) "rows"))
    let dataRoot := base/"snapshot-scheduling/work/data"
    let kept := #[selected/"StudyMain",out/"StudyMain",base/"snapshot-scheduling/work/work.egg/head"]
    let hashes ← kept.mapM hash
    let mut deleted := #[]
    for client in clients do
      let session ← IO.ofExcept (client.getObjValAs? String "session")
      let receipt ← IO.ofExcept (client.getObjValAs? String "receipt")
      let hex := fun (text : String) => text.length == 64 && text.toList.all (fun c =>
        ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))
      check (session.startsWith "capacity-" && hex ((session.drop 9).toString) && hex receipt &&
        client.getObjValD "success" == toJson true && client.getObjValD "acknowledged" == toJson true)
        "only this study's successful acknowledged clients may be retired"
      let path := dataRoot/"sessions"/session
      let state ← read (path/"state.json")
      let confirmed := state.getObjValD "confirmedDelivery"
      check (confirmed.getObjValD "session" == toJson session) "delivery ledger belongs to another session"
      let authority ← IO.ofExcept ((confirmed.getObjValD "head").getObjValAs? String "authority")
      let context := (authority.drop "confirmed-delivery:".length).toString
      check (authority == "confirmed-delivery:"++context && hex context) "invalid owned ledger authority"
      for target in #[path,dataRoot/"confirmed-delivery"/context,dataRoot/"receipts"/receipt] do
        check ((← target.symlinkMetadata).type == .dir) "retired root must be owned"
        let removed ← removeOwned target
        deleted := deleted.push (target.toString,removed.1,removed.2)
    check ((← kept.mapM hash) == hashes) "protected inputs changed"
    write (logs/(label++"-retired.json")) (Json.mkObj [("clients",toJson clients.size),("deleted",toJson deleted),
      ("protectedInputs",toJson (kept.zip hashes)),("protectedHashesUnchanged",toJson true),("archiveCreated",toJson false)])
  else if args == ["report"] then
    idle
    for tag in ["build","audit"] do
      write (logs/(tag++".guard.json")) (← clean ("register-rounds-runtime-"++tag))
    let mut rows := #[]
    let mut parentTimes := #[]
    let mut candidateTimes := #[]
    let invariant := fun (input : Json) => Json.mkObj
      (["project","sourceFiles","workspace","data","topics","handoffChars","counts","diagnostic"].map
        fun key => (key,input.getObjValD key))
    let common ← read (root/"a-first-input.json")
    let commonEnvironment : Array (String × Option String) ← IO.ofExcept (fromJson? (common.getObjValD "environment"))
    let fixedEnvironment := fun (environment : Array (String × Option String)) =>
      environment.filter fun row => !["EGGSHELL_PREFIX","PLUGIN_ROOT","EGGSHELL_CONFIG"].contains row.1
    for label in order do
      let input ← read (root/(label++"-input.json"))
      let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
      check (invariant input == invariant common && fixedEnvironment environment == fixedEnvironment commonEnvironment)
        "snapshot,questions,canonical bodies,harness settings or non-treatment environment changed between arms"
      let value ← read (logs/(label++".json"))
      check (value.getObjValD "passed" == toJson true && value.getObjValD "sourceFilesUnchanged" == toJson true)
        "only a completed fixed arm may be compared"
      let phases : Array Json ← IO.ofExcept (fromJson? ((value.getObjValD "report").getObjValD "phases"))
      let some wave := phases.find? (fun phase => phase.getObjValD "clients" == toJson (16 : Nat)) |
        throw (IO.userError "sixteen-client wave missing")
      let elapsed ← IO.ofExcept (wave.getObjValAs? Nat "wallMs")
      if label.startsWith "b" then candidateTimes := candidateTimes.push elapsed
      else parentTimes := parentTimes.push elapsed
      rows := rows.push (Json.mkObj [("label",toJson label),("recordSha256",toJson (← hash (logs/(label++".json")))),
        ("inputSha256",toJson (← hash (root/(label++"-input.json")))),
        ("phases",toJson (phases.map fun phase => Json.mkObj [("clients",phase.getObjValD "clients"),
          ("wallMs",phase.getObjValD "wallMs"),("passed",phase.getObjValD "passed")])),
        ("sampledPeakRssKiB",(value.getObjValD "guard").getObjValD "sampledPeakRssKiB")])
    check (parentTimes.size == 2 && candidateTimes.size == 2) "equal completed counts required"
    let a := parentTimes.foldl Nat.add 0
    let b := candidateTimes.foldl Nat.add 0
    check (a > 0) "nonzero reference clock required"
    write (logs/"comparison.json") (Json.mkObj [("order",toJson order),("arms",toJson rows),
      ("parent16WallMs",toJson parentTimes),("candidate16WallMs",toJson candidateTimes),
      ("descriptiveMeanLatencyReductionPercent",toJson (100.0*(Float.ofNat a-Float.ofNat b)/Float.ofNat a)),
      ("fewSecond16ClientTargetMet",toJson (candidateTimes.all (· ≤ 5000))),
      ("p99Established",toJson false),("eightyConcurrentTest",toJson false),
      ("snapshotQuestionsBodiesAndHarnessSettingsMatch",toJson true),
      ("inclusiveTokenOrQualityBenefitEstablished",toJson false),("answeringModelCalls",toJson (0 : Nat)),
      ("adopted",toJson false)])
  else if args == ["retire-observed-components"] then
    idle
    discard <| clean "register-rounds-runtime-profile"
    discard <| clean "owned-buckets-component"
    check ((← (logs/"profile-retired.json").pathExists) &&
      !(← (logs/"retired-observed-components.json").pathExists)) "retire owned profile states and preserve cleanup evidence"
    let component := (← read (project/"docs/candidates/owned-buckets/component.json")).getObjValD "guard"
    check (component.getObjValD "exitCode" == toJson (0 : Nat))
      "component result is not collected"
    let targets := #[observerSource,observerBuild,base/"owned-buckets/source",base/"owned-buckets/build",base/"owned-buckets/run"]
    let mut checked := 0
    for target in targets do
      for library in #[selected/"lib",out/"lib",base/"study-local-lib"] do
        checked := checked+(← checkRetiredLinks library target)
      let response ← IO.FS.readFile (out/"runtime.rsp")
      check (!response.contains (target.toString++"/")) "current runtime links a retired component"
    let kept := #[selected/"StudyMain",out/"StudyMain",base/"current-six/fixed-sequence/controller-build/StudyMain",
      base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",base/"byte-pages-prefix/libexec/eggshell",
      base/"snapshot-scheduling/work/work.egg/head"]
    let hashes ← kept.mapM hash
    let mut metadata := [("input",← read (root/"profile-input.json"))]
    for file in ← (root/"profile").readDir do
      if (← file.path.symlinkMetadata).type == .file && file.fileName.endsWith ".json" &&
          !["report.json","progress.json","sampling.json"].contains file.fileName then
        metadata := metadata++[(file.fileName,← read file.path)]
    write (logs/"profile-metadata.json") (Json.mkObj metadata)
    let mut removed := #[]
    for target in targets do
      check ((← target.symlinkMetadata).type == .dir) "retired component root must be owned"
      let deleted ← removeOwned target
      removed := removed.push (target.toString,deleted.1,deleted.2)
    for file in ← (root/"profile").readDir do
      if ["publisher-late.sample.txt","sampling.json"].contains file.fileName then continue
      let deleted ← removeOwned file.path
      removed := removed.push (file.path.toString,deleted.1,deleted.2)
    check ((← kept.mapM hash) == hashes) "protected runtime or head changed"
    write (logs/"retired-observed-components.json") (Json.mkObj [("deleted",toJson removed),
      ("activeCompilerInputsChecked",toJson checked),("protectedInputs",toJson (kept.zip hashes)),
      ("protectedHashesUnchanged",toJson true),("archiveCreated",toJson false),
      ("currentRawCpuSampleKept",toJson true),("componentResultsAndProofSourcesKept",toJson true)])
  else if args == ["retire-outputs"] then
    idle
    check ((← (logs/"comparison.json").pathExists) && !(← (logs/"retired-outputs.json").pathExists))
      "finish the comparison and preserve its retirement record"
    let kept := #[selected/"StudyMain",out/"StudyMain",base/"snapshot-scheduling/work/work.egg/head"]
    let hashes ← kept.mapM hash
    let mut removed := #[]
    for label in #["preflight"]++order do
      discard <| clean ("register-rounds-runtime-"++label)
      check ((← (logs/(label++"-retired.json")).pathExists) &&
        (← read (logs/(label++".json"))).getObjValD "passed" == toJson true)
        "retire acknowledged session states before duplicate outputs"
      let path := root/label
      let mut metadata := [("input",← read (root/(label++"-input.json")))]
      for file in ← path.readDir do
        if (← file.path.symlinkMetadata).type == .file && file.fileName.endsWith ".json" &&
            !["progress.json","report.json"].contains file.fileName then
          metadata := metadata++[(file.fileName,← read file.path)]
      write (logs/(label++"-metadata.json")) (Json.mkObj metadata)
      check ((← path.symlinkMetadata).type == .dir) "retired output root must be owned"
      let result ← removeOwned path
      removed := removed.push (path.toString,result.1,result.2)
    check ((← kept.mapM hash) == hashes) "protected runtime or head changed"
    write (logs/"retired-outputs.json") (Json.mkObj [("deleted",toJson removed),
      ("protectedInputs",toJson (kept.zip hashes)),("protectedHashesUnchanged",toJson true),
      ("scalarPrimesCacheAndShutdownMetadataKept",toJson true),("archiveCreated",toJson false),
      ("duplicateNativeHookPayloadsRetired",toJson true)])
  else throw (IO.userError "setup|build|audit|install|prepare|collect")
end RuntimeStudy
def main := RuntimeStudy.main
