import tools.research.StudyLocal
open Lean StudyLocal
def trial := base/"routing-leaf-image"
def selected := base/"current-six/stable-source-rows/build"
def source := trial/"source"
def build := trial/"build"
def records := project/"docs/candidates/routing-leaf-image"
def entry := "tools.research.PreparedRoutingLeafChecks"
def clean (tag : String) : IO Json := do
  let result ← finished tag
  check (result.getObjValD "guardTriggered" == toJson false && result.getObjValD "reason" == Json.null)
    "guard did not finish normally"
  return result
def main (args : List String) : IO Unit := do
  if args == ["setup"] then
    idle
    check (!(← trial.pathExists)) "fresh component trial required"
    check ((← hash (selected/"StudyMain")) == "dd53c89bc450b66b58dd57d104ccbc82f32ca6345fa9666125e7feb03017000e")
      "selected source changed"
    IO.FS.createDirAll records
    materialize selected source build entry "routing-leaf-settings.json"
    for name in ["PreparedRoutingLeaf","PreparedRoutingLeafChecks","PreparedRoutingObserver"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean"))
        (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    write (records/"plan.json") (Json.mkObj [("parentSha256",toJson "dd53c89bc450b66b58dd57d104ccbc82f32ca6345fa9666125e7feb03017000e"),
      ("question",toJson "does reusing checked typed routing leaf data remove repeated decoding above the existing page cache?"),
      ("scope",toJson "native component only;no product integration;no answering model;no whole-graph request-time expansion"),
      ("preparation",toJson "one bounded full routing-leaf probe,at most1024pages and30seconds;reported separately;not a publication-delta implementation"),
      ("comparison",toJson "up to1024uniformly spaced node IDs;original complete arcs/order/bytes/pages/flag;three predeclared AB/BA/AB pairs"),
      ("imageAllowanceBytes",toJson (8*1024*1024 : Nat)),("aggregateLimitBytes",toJson (5000000000 : Nat)),
      ("maxLocalClients",toJson (16 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  else if args.head? == some "build" then
    let [_,label] := args | throw (IO.userError "build <attempt>")
    idle
    for name in ["PreparedRoutingLeaf","PreparedRoutingLeafChecks","PreparedRoutingObserver"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean"))
        (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    let tag := "routing-leaf-build-"++label
    guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"routing-leaf-settings.json").toString]
    write (records/"current-build.json") (Json.mkObj [("tag",toJson tag)])
  else if args == ["audit"] then
    discard <| clean (← IO.ofExcept ((← read (records/"current-build.json")).getObjValAs? String "tag"))
    guard "routing-leaf-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/PreparedRoutingLeafStudy.lean").toString,"audit-worker"]
  else if args == ["audit-worker"] then
    let call := fun params => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++params)
    discard <| call #["inspect",build.toString,(records/"native.json").toString]
    discard <| call #["compare-sources",selected.toString,build.toString,(records/"sources.json").toString,
      "+tools.research.PreparedRoutingLeaf"]
  else if args == ["audit-component"] then
    let original ← read (records/"sources.json")
    check (original.getObjValD "directSourceChanges" == toJson (#[] : Array String) &&
      original.getObjValD "changedSourcesAndLiteralInputs" == toJson (#[] : Array String) &&
      original.getObjValD "added" == toJson (#["tools.research.PreparedRoutingLeaf"] : Array String) &&
      original.getObjValD "candidateRuntimeSha256" == toJson (← hash (build/"StudyMain")) &&
      (← read (records/"native.json")).getObjValD "consistent" == toJson true)
      "the component contains an unexpected source or native change"
    guard "routing-leaf-component-audit" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString,"component-sources",
      selected.toString,build.toString,(records/"component-sources.json").toString,
      "Eggshell.DB.PageMap","Eggshell.DB.Wire","Eggshell.SynapseIndex",
      "Eggshell.SynapticTopologyStore","Eggshell.SynapticRoutingStore"]
    write (records/"runtime.json") (Json.mkObj [("runtimeSha256",toJson (← hash (build/"StudyMain"))),
      ("parentSha256",toJson (← hash (selected/"StudyMain"))),("componentOnlyNotFullProductClosure",toJson true)])
  else if args == ["run"] then
    discard <| clean "routing-leaf-component-audit"
    let input ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
    let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
    let assigned := environment.filterMap fun (key,value) => value.map (key++"="++·)
    let database ← IO.ofExcept (input.getObjValAs? String "project")
    check ((← read (records/"runtime.json")).getObjValD "runtimeSha256" ==
      toJson (← hash (build/"StudyMain"))) "native source audit has a different binary"
    guard "routing-leaf-component" (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assigned++
      #[(build/"StudyMain").toString,database,(trial/"run").toString])
  else if args.head? == some "audit-observer" then
    let label := args[1]?.getD "observer"
    check (label.toList.all (fun c => c.isAlphanum || c == '-')) "invalid audit label"
    discard <| clean (← IO.ofExcept ((← read (records/"current-build.json")).getObjValAs? String "tag"))
    let tag := "routing-leaf-"++label++"-audit"
    guard tag #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/PreparedRoutingLeafStudy.lean").toString,"audit-observer-worker",label]
    write (records/"current-audit.json") (Json.mkObj [("tag",toJson tag),("label",toJson label)])
  else if args.head? == some "audit-observer-worker" then
    let label := args[1]?.getD "observer"
    let call := fun params => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++params)
    discard <| call #["inspect",build.toString,(records/("native-"++label++".json")).toString]
    discard <| call #["component-sources",selected.toString,build.toString,(records/("component-sources-"++label++".json")).toString,
      "Eggshell.DB.PageMap","Eggshell.DB.Wire","Eggshell.SynapseIndex",
      "Eggshell.SynapticTopologyStore","Eggshell.SynapticRoutingStore"]
    let parentModules : Array Json ← IO.ofExcept ((← read (selected/"build.json")).getObjValAs? (Array Json) "modules")
    let modules : Array Json ← IO.ofExcept ((← read (build/"build.json")).getObjValAs? (Array Json) "modules")
    let extra := #["tools.research.PreparedRoutingLeaf","tools.research.PreparedRoutingObserver",entry]
    for row in modules do
      let name ← IO.ofExcept (row.getObjValAs? String "module")
      check (extra.contains name || parentModules.any (fun old => old.getObjValD "module" == toJson name))
        "undeclared native helper module"
    let mut witnesses := #[]
    for name in extra do
      let (text,literals) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (build/(name.replace "." "_"++".source"))))
      let path := project/(name.replace "." "/"++".lean")
      check (text == (← IO.FS.readFile path) && literals.isEmpty) "helper differs from its audited source"
      witnesses := witnesses.push (name,← hash path)
    write (records/("runtime-"++label++".json")) (Json.mkObj [("runtimeSha256",toJson (← hash (build/"StudyMain"))),
      ("parentSha256",toJson (← hash (selected/"StudyMain"))),("helperSources",toJson witnesses),
      ("componentOnlyNotFullProductClosure",toJson true)])
  else if args == ["run-full"] then
    discard <| clean "routing-leaf-observer-audit"
    let input ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
    let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
    let assigned := environment.filterMap fun (key,value) => value.map (key++"="++·)
    let database ← IO.ofExcept (input.getObjValAs? String "project")
    write (records/"full-population-plan.json") (Json.mkObj [
      ("reason",toJson "uniform1024node probe covers916of20796arcs;measure dense nodes before extrapolating"),
      ("nodeCap",toJson (65536 : Nat)),("order",toJson "AB/BA/AB"),
      ("sameSourceAndRowAlgorithm",toJson true),("componentOnly",toJson true),
      ("runtimeSha256",toJson (← hash (build/"StudyMain")))])
    guard "routing-leaf-full" (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assigned++
      #[(build/"StudyMain").toString,"full",database,(trial/"full").toString])
  else if args == ["prepare-late"] then
    discard <| clean "routing-leaf-observer-audit"
    let input ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let output := trial/"late-sampled"
    let config := output/"config.toml"
    let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
    let environment := environment.map fun (key,value) => (key,if key == "EGGSHELL_CONFIG" then some config.toString
      else if key == "EGGSHELL_TRACE_QUERY_STAGES" || key == "EGGSHELL_TRACE_SERVICE_PROFILE" then some "1" else value)
    let input := input.setObjVal! "output" (toJson output.toString) |>.setObjVal! "config" (toJson config.toString)
      |>.setObjVal! "environment" (toJson environment) |>.setObjVal! "diagnostic" (toJson true)
      |>.setObjVal! "counts" (toJson (#[(4 : Nat)]))
    let path := trial/"late-input.json"
    check (!(← path.pathExists)) "preserve the declared late diagnosis"
    write path input
    write (records/"late-plan.json") (Json.mkObj [("productSha256",input.getObjValD "runtimeSha256"),
      ("observerSha256",toJson (← hash (build/"StudyMain"))),("clients",toJson (4 : Nat)),
      ("delayFromPhaseObservationMs",toJson (2000 : Nat)),("sampleSeconds",toJson (3 : Nat)),
      ("sampleIntervalMs",toJson (5 : Nat)),("diagnosticInterferencePossible",toJson true),
      ("wholeHookCpuPercentages",toJson false),("performanceComparison",toJson false)])
    guard "routing-leaf-late" #[(build/"StudyMain").toString,"observe",path.toString]
  else if args == ["collect-full"] then
    let monitor ← clean "routing-leaf-full"
    write (records/"full-result.json") (Json.mkObj [("guard",monitor),
      ("runtimeSha256",toJson (← hash (build/"StudyMain"))),
      ("controls",← read (trial/"full/controls.json")),("report",← read (trial/"full/report.json"))])
  else if args == ["collect-late"] then
    let monitor ← read (base/"routing-leaf-late.guard.json")
    check (monitor.getObjValD "state" == toJson "finished" &&
      monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      monitor.getObjValD "guardTriggered" == toJson false && monitor.getObjValD "reason" == Json.null)
      "late observer is not terminal and drained"
    let normal := monitor.getObjValD "exitCode" == toJson (0 : Nat)
    let root := trial/"late-sampled"
    let input ← read (trial/"late-input.json")
    let report ← read (root/"report.json")
    let phases : Array Json ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
    check (phases.size == 1 && phases.all (fun phase => phase.getObjValD "passed" == toJson true))
      "late diagnosis lost body,semantic,synapse orACK"
    let sampling ← read (root/"sampling.json")
    check (sampling.getObjValD "sampleExitCode" == toJson (0 : Nat)) "late sample did not complete"
    for name in ["publisher-shutdown.json","frontend-shutdown.json"] do
      let stopped ← read (root/name)
      check (stopped.getObjValD "processExited" == toJson true &&
        stopped.getObjValD "endpointRemoved" == toJson true && stopped.getObjValD "daemonExitCode" == toJson (0 : Nat))
        "product service did not stop normally"
    if !normal then check (monitor.getObjValD "exitCode" == toJson (1 : Nat)) "unexpected observer failure"
    let began ← IO.ofExcept (sampling.getObjValAs? Nat "phaseObservedMs")
    let wall ← IO.ofExcept (phases[0]!.getObjValAs? Nat "wallMs")
    let dataRoot : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
    let mut profiles := #[]
    let mut actors := #[]
    for row in ← IO.ofExcept (phases[0]!.getObjValAs? (Array Json) "rows") do
      let id ← IO.ofExcept (row.getObjValAs? String "receipt")
      actors := actors.push (Json.mkObj [("client",row),("pages",← read (dataRoot/"receipts"/id/"request-pages.json"))])
    for entry in ← (dataRoot/"receipts").readDir do
      for name in #["source-plan-profile","source-views-profile","source-bindings-profile","server-envelope-profile"] do
        let path := entry.path/(name++".json")
        if !(← path.pathExists) then continue
        let value ← read path
        let observed ← IO.ofExcept (value.getObjValAs? Nat "observedMs")
        if began ≤ observed && observed ≤ began+wall+1000 then profiles := profiles.push value
    write (records/"late-result.json") (Json.mkObj [("guard",monitor),("report",report),
      ("sampling",sampling),("actors",toJson actors),("serviceProfiles",toJson profiles),
      ("normalObserverExit",toJson normal),("postWorkloadObserverFailure",toJson (!normal)),
      ("notNormalLatencyComparison",toJson true),
      ("profileSha256",toJson (← hash (root/"publisher-late.sample.txt"))),
      ("concurrentServiceRequestAttribution",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  else if args == ["prepare-observer-controls"] then
    let audited ← read (records/"current-audit.json")
    discard <| clean (← IO.ofExcept (audited.getObjValAs? String "tag"))
    let label ← IO.ofExcept (audited.getObjValAs? String "label")
    check ((← read (records/("runtime-"++label++".json"))).getObjValD "runtimeSha256" ==
      toJson (← hash (build/"StudyMain"))) "observer controls have unaudited native code"
    guard "routing-leaf-observer-controls" #[(build/"StudyMain").toString,"observer-controls",(trial/"observer-controls.json").toString]
  else if args == ["collect-observer-controls"] then
    let monitor ← clean "routing-leaf-observer-controls"
    write (records/"observer-controls.json") (Json.mkObj [("guard",monitor),
      ("runtimeSha256",toJson (← hash (build/"StudyMain"))),("checks",← read (trial/"observer-controls.json")),
      ("actualFourClientDiagnosticNotRetried",toJson true)])
  else if args == ["collect"] then
    let monitor ← clean "routing-leaf-component"
    write (records/"result.json") (Json.mkObj [("guard",monitor),
      ("runtimeSha256",toJson (← hash (build/"StudyMain"))),
      ("controls",← read (trial/"run/controls.json")),("report",← read (trial/"run/report.json"))])
  else throw (IO.userError "setup|build|audit|audit-worker|audit-component|run|collect|audit-observer|audit-observer-worker|run-full|prepare-late|collect-full|collect-late")
