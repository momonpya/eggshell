import tools.research.StudyLocal
open Lean StudyLocal
def trial := base/"winner-width"
def selected := base/"current-six/stable-source-rows/build"
def source := trial/"source"
def build := trial/"build"
def records := project/"docs/candidates/winner-width"
def entry := "tools.research.WinnerWidthChecks"
def clean (tag : String) : IO Json := do
  let result ← finished tag
  check (result.getObjValD "guardTriggered" == toJson false && result.getObjValD "reason" == Json.null)
    "guard did not finish normally"
  return result
def copySources : IO Unit := do
  for name in ["WinnerWidth","WinnerWidthChecks","PreparedRoutingObserver"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
def main (args : List String) : IO Unit := do
  if args == ["setup"] then
    idle
    check (!(← trial.pathExists)) "fresh width study required"
    check ((← hash (selected/"StudyMain")) == "dd53c89bc450b66b58dd57d104ccbc82f32ca6345fa9666125e7feb03017000e")
      "selected native product changed"
    IO.FS.createDirAll records
    materialize selected source build entry "winner-width-settings.json"
    copySources
    let late ← read (project/"docs/candidates/routing-leaf-image/late-result.json")
    let actors : Array Json ← IO.ofExcept (late.getObjValAs? (Array Json) "actors")
    let mut shapes := #[]
    let mut scale := 0
    for actor in actors do
      let id ← IO.ofExcept ((actor.getObjValD "client").getObjValAs? String "receipt")
      let path := base/"snapshot-scheduling/work/data/receipts"/id/"selection-plan.json"
      let value := (← read path).getObjValD "data"
      let current ← IO.ofExcept (value.getObjValAs? Nat "scale")
      scale := max scale current
      shapes := shapes.push (Json.mkObj [("receipt",toJson id),("receiptSha256",toJson (← hash path)),
        ("families",value.getObjValD "families"),("candidateUnits",value.getObjValD "candidateUnits"),
        ("scale",toJson current),("scaleBits",toJson (current.log2+1)),("limit",value.getObjValD "limit")])
    check (actors.size == 4 && scale > 0) "nonvacuous actual scalar context required"
    write (records/"scalar-context.json") (toJson shapes)
    write (trial/"input.json") (Json.mkObj [("output",toJson (trial/"run").toString),("scale",toJson scale)])
    write (records/"plan.json") (Json.mkObj [("classificationPreviousTurn",toJson "progress:shared page epochs and fixed-snapshot sixteen-client comparison"),
      ("reason",toJson "new late sample contains repeated lean_nat_pow under Tree.updated;old batch-winner saves only50ms and is not retried"),
      ("change",toJson "carry subtree width through the original point-update recursion;halve at each descent;compute the root width once per update batch"),
      ("proof",toJson "all preferences,depths,trees,indices,values,duplicate positions:complete Cache equality"),
      ("benchmark",toJson "synthetic sparse16,contiguous1024,all16384,duplicate1024,erase1024;three AB/BA/AB pairs;current scalar magnitude;retained common base"),
      ("actualSelectorReplay",toJson false),("wholeHookBenefitEstablished",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  else if args.head? == some "build" then
    let [_,label] := args | throw (IO.userError "build <attempt>")
    idle
    copySources
    let tag := "winner-width-build-"++label
    guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"winner-width-settings.json").toString]
    write (records/"current-build.json") (Json.mkObj [("tag",toJson tag)])
  else if args.head? == some "audit" then
    let label := args[1]?.getD "initial"
    discard <| clean (← IO.ofExcept ((← read (records/"current-build.json")).getObjValAs? String "tag"))
    let tag := if label == "initial" then "winner-width-audit" else "winner-width-audit-"++label
    guard tag #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/WinnerWidthStudy.lean").toString,"audit-worker",label]
    write (records/"current-audit.json") (Json.mkObj [("tag",toJson tag),("label",toJson label)])
  else if args.head? == some "audit-worker" then
    let label := args[1]?.getD "initial"
    let suffix := if label == "initial" then "" else "-"++label
    let call := fun params => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++params)
    discard <| call #["inspect",build.toString,(records/("native"++suffix++".json")).toString]
    discard <| call #["component-sources",selected.toString,build.toString,(records/("sources"++suffix++".json")).toString,
      "tools.StableWinnerIndex","tools.SelectionRating"]
    let parentModules : Array Json ← IO.ofExcept ((← read (selected/"build.json")).getObjValAs? (Array Json) "modules")
    let modules : Array Json ← IO.ofExcept ((← read (build/"build.json")).getObjValAs? (Array Json) "modules")
    let extra := #["tools.research.WinnerWidth","tools.research.PreparedRoutingObserver",entry]
    for row in modules do
      let name ← IO.ofExcept (row.getObjValAs? String "module")
      check (extra.contains name || parentModules.any (fun old => old.getObjValD "module" == toJson name))
        "undeclared width native helper"
    let mut witnesses := #[]
    for name in extra do
      let (text,literals) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (build/(name.replace "." "_"++".source"))))
      let path := project/(name.replace "." "/"++".lean")
      check (text == (← IO.FS.readFile path) && literals.isEmpty) "width helper differs from its native source"
      witnesses := witnesses.push (name,← hash path)
    write (records/("runtime"++suffix++".json")) (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
      ("parentSha256",toJson (← hash (selected/"StudyMain"))),("helperSources",toJson witnesses),
      ("componentOnly",toJson true)])
  else if args == ["run"] then
    discard <| clean "winner-width-audit"
    check ((← read (records/"runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain")))
      "runtime differs from its native audit"
    guard "winner-width-component" #[(build/"StudyMain").toString,(trial/"input.json").toString]
  else if args == ["preserve-invalid-timing"] then
    let monitor ← clean "winner-width-component"
    let value ← read (trial/"run/report.json")
    check (value.getObjValD "timedInputsReadAfterClock" != toJson true) "a corrected result cannot be called invalid"
    write (records/"invalid-timing-result.json") (Json.mkObj [("guard",monitor),("report",value),
      ("comparisonValid",toJson false),("reason",toJson "reference expression reused the precomputed oracle through common-subexpression elimination"),
      ("candidateRejectedOrAdoptedFromTheseTimes",toJson false)])
  else if args == ["run-barrier"] then
    discard <| clean "winner-width-audit-barrier"
    check ((← read (records/"runtime-barrier.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain")))
      "timing repair differs from its native audit"
    let input ← read (trial/"input.json")
    let path := trial/"barrier-input.json"
    write path (input.setObjVal! "output" (toJson (trial/"barrier-run").toString))
    write (records/"barrier-plan.json") (Json.mkObj [("sameScaleBasePatternsAndOrder",toJson true),
      ("repair",toJson "load the input cache and update list from an owned reference after the starting clock;do not time the precomputed oracle"),
      ("originalFailedMeasurementRetained",toJson "invalid-timing-result.json"),
      ("runtimeSha256",toJson (← hash (build/"StudyMain")))])
    guard "winner-width-barrier" #[(build/"StudyMain").toString,path.toString]
  else if args == ["collect-barrier"] then
    let monitor ← clean "winner-width-barrier"
    let value ← read (trial/"barrier-run/report.json")
    check (value.getObjValD "timedInputsReadAfterClock" == toJson true) "unguarded timing inputs"
    write (records/"barrier-result.json") (Json.mkObj [("guard",monitor),
      ("runtimeSha256",toJson (← hash (build/"StudyMain"))),("report",value)])
  else if args == ["collect"] then
    let monitor ← clean "winner-width-component"
    write (records/"result.json") (Json.mkObj [("guard",monitor),
      ("runtimeSha256",toJson (← hash (build/"StudyMain"))),("report",← read (trial/"run/report.json"))])
  else throw (IO.userError "setup|build|audit|audit-worker|run|collect")
