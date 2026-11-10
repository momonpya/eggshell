import tools.research.StudyLocal
open Lean StudyLocal

def trial := base/"winner-width-runtime"
def selectedBuild := base/"current-six/stable-source-rows/build"
def selected := base/"current-six/fixed-sequence/cohort/prefix"
def source := trial/"source"
def build := trial/"build"
def installation := trial/"prefix"
def records := project/"docs/candidates/winner-width/runtime"
def entry := "tools.research.OwnedSelectionRuntime"
def order : Array String := #["a-first","b-first","b-second","a-second"]

def clean (tag : String) : IO Json := do
  let value ← finished tag
  check (value.getObjValD "guardTriggered" == toJson false && value.getObjValD "reason" == Json.null)
    "supervisor did not finish normally"
  return value

partial def checkLinks (path retired : System.FilePath) : IO Nat := do
  let stat ← path.symlinkMetadata
  if stat.type == .dir then
    let mut count := 0
    for entry in ← path.readDir do count := count+(← checkLinks entry.path retired)
    return count
  let target ← IO.FS.realPath path
  check (!target.toString.startsWith (retired.toString++"/")) "an active compiler input points into the retired component"
  return 1

partial def removeOwned (path : System.FilePath) : IO (Nat × Nat) := do
  let stat ← path.symlinkMetadata
  if stat.type == .dir then
    let mut files := 0
    let mut bytes := 0
    for entry in ← path.readDir do
      let current ← removeOwned entry.path
      files := files+current.1
      bytes := bytes+current.2
    IO.FS.removeDir path
    return (files,bytes)
  IO.FS.removeFile path
  return (1,if stat.type == .file then stat.byteSize.toNat else 0)

def main (args : List String) : IO Unit := do
  if args == ["setup"] then
    idle
    let component ← read (project/"docs/candidates/winner-width/barrier-result.json")
    check ((component.getObjValD "report").getObjValD "exactAllLeavesAndStableWinner" == toJson true)
      "corrected component comparison required"
    check ((← hash (selectedBuild/"StudyMain")) == "dd53c89bc450b66b58dd57d104ccbc82f32ca6345fa9666125e7feb03017000e")
      "selected product changed"
    check (!(← trial.pathExists)) "fresh isolated candidate required"
    IO.FS.createDirAll records
    materialize selectedBuild source build entry "winner-width-runtime-settings.json"
    for name in ["WinnerWidth","WinnerWidthReplacement"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean"))
        (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    let path := source/"tools/WinnerUpdates.lean"
    let original ← IO.FS.readFile path
    let binding := "\n@[csimp] theorem updateMany_width : @updateMany = @updateManyWidth := by\n  funext p depth capacity cache indices replacement\n  simp only [updateMany,updateManyWidth,StableWinnerIndex.Width.updated_exact]\n\n#print axioms updateMany_width\n"
    let marker := "public import tools.WinnerCache\n"
    let consumer := "\ntheorem updateMany_lookup"
    check ((original.splitOn marker).length == 2) "one original import boundary required"
    check ((original.splitOn consumer).length == 2) "one first consumer boundary required"
    IO.FS.writeFile path (original.replace marker (marker++"public import tools.research.WinnerWidthReplacement\n")
      |>.replace consumer (binding++consumer))
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",(selectedBuild.parent.get!/"source/tools/WinnerUpdates.lean").toString,path.toString]}
    check (diff.exitCode == 1) "expected one explicit product source change"
    IO.FS.writeFile (records/"core.patch") diff.stdout
    write (records/"plan.json") (Json.mkObj [("comparison",toJson order),
      ("countsPerArm",toJson (#[(4 : Nat),16])),("preflight",toJson "three canonical bodies before any measured wave"),
      ("treatment",toJson "proof-directed compiler replacement of the original sequential point-update fold;one width per fold"),
      ("preserved",toJson "ranking,ties,duplicate indices,WorkGraph,Exact,three advisory edges,source body,models,prompts,ACK,all deadline and resource limits"),
      ("poolChanged",toJson false),("newCacheOrLock",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  else if args.head? == some "build" then
    let label := args[1]?.getD "initial"
    let tag := if label == "initial" then "winner-width-runtime-build" else "winner-width-runtime-build-"++label
    guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"winner-width-runtime-settings.json").toString]
    write (records/"current-build.json") (Json.mkObj [("tag",toJson tag)])
  else if args == ["audit"] then
    discard <| clean (← IO.ofExcept ((← read (records/"current-build.json")).getObjValAs? String "tag"))
    guard "winner-width-runtime-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/WinnerWidthRuntimeStudy.lean").toString,"audit-worker"]
  else if args == ["audit-worker"] then
    let call := fun parameters => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++parameters)
    discard <| call #["inspect",build.toString,(records/"native.json").toString]
    discard <| call #["compare-sources",selectedBuild.toString,build.toString,(records/"sources.json").toString,
      "tools.WinnerUpdates","+tools.research.WinnerWidth","+tools.research.WinnerWidthReplacement"]
    let old ← read (selectedBuild/"tools_research_OwnedSelectionRuntime.source")
    let current ← read (build/"tools_research_OwnedSelectionRuntime.source")
    check (old == current) "entry source or embedded literals changed"
    let symbols ← command "/usr/bin/nm" #["-u",(build/"tools_WinnerUpdates.o").toString]
    check (symbols.contains "updateManyWidth" || symbols.contains "Width_updated")
      "same-module consumers did not compile to the new update"
    IO.FS.writeFile (records/"consumer-symbols.txt") symbols
    for name in ["WinnerWidth","WinnerWidthReplacement"] do
      let (text,literals) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (build/("tools_research_"++name++".source"))))
      check (text == (← IO.FS.readFile (project/"tools/research"/(name++".lean"))) && literals.isEmpty)
        "width helper differs from its reviewed source"
    write (records/"runtime.json") (Json.mkObj [("candidateSha256",toJson (← hash (build/"StudyMain"))),
      ("parentSha256",toJson (← hash (selectedBuild/"StudyMain"))),("entrySourceAndLiteralsUnchanged",toJson true),
      ("sourceAudit",toJson "sources.json"),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  else if args == ["install"] then
    discard <| clean "winner-width-runtime-audit"
    check (!(← installation.pathExists)) "fresh installation required"
    let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let oldPlugin : System.FilePath := .mk (← IO.ofExcept (original.getObjValAs? String "plugin"))
    let plugin := installation/"share/eggshell/codex-plugin"
    IO.FS.createDirAll (installation/"libexec")
    IO.FS.createDirAll (plugin/"bin")
    discard <| command "/bin/ln" #["-s",(build/"StudyMain").toString,(installation/"libexec/eggshell").toString]
    discard <| command "/bin/ln" #["-s",(selected/"share/eggshell/minilm").toString,(installation/"share/eggshell/minilm").toString]
    for name in ["egg","eggshelld"] do
      let text ← IO.FS.readFile (oldPlugin/"bin"/name)
      check (text.contains selected.toString) "different launcher boundary"
      IO.FS.writeFile (plugin/"bin"/name) (text.replace selected.toString installation.toString)
      discard <| command "/bin/chmod" #["755",(plugin/"bin"/name).toString]
    check ((← IO.FS.realPath (selected/"share/eggshell/minilm")) ==
      (← IO.FS.realPath (installation/"share/eggshell/minilm"))) "model assets differ"
  else if args == ["retire-component"] then
    idle
    discard <| clean "winner-width-runtime-audit"
    let old := base/"winner-width"
    let count ← checkLinks (selectedBuild/"lib") old
    let count := count+(← checkLinks (build/"lib") old)+(← checkLinks (base/"study-local-lib") old)
    let retained := #[selectedBuild/"StudyMain",build/"StudyMain",
      base/"current-six/fixed-sequence/controller-build/StudyMain",
      base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",
      base/"snapshot-scheduling/work/work.egg/head"]
    let digests ← retained.mapM hash
    let mut files := 0
    let mut bytes := 0
    for name in ["build","source"] do
      let path := old/name
      check ((← path.symlinkMetadata).type == .dir) "retired top must be an owned directory"
      let removed ← removeOwned path
      files := files+removed.1
      bytes := bytes+removed.2
    check ((← retained.mapM hash) == digests) "retained inputs changed during retirement"
    write (records/"retired-component.json") (Json.mkObj [("files",toJson files),("logicalBytes",toJson bytes),
      ("activeCompilerInputsChecked",toJson count),("retainedInputs",toJson (retained.zip digests)),
      ("retainedHashesUnchanged",toJson true),("archiveCreated",toJson false)])
  else if args.head? == some "prepare" then
    let [_,label] := args | throw (IO.userError "prepare <preflight|declared arm>")
    discard <| clean "winner-width-runtime-audit"
    let preflight := label == "preflight"
    let position ← if preflight then pure 0 else do
      let some position := order.findIdx? (· == label) | throw (IO.userError "undeclared arm")
      pure position
    if !preflight then
      let previous := if position == 0 then "preflight" else order[position-1]!
      discard <| clean ("winner-width-runtime-"++previous)
      check ((← read (records/(previous++".json"))).getObjValD "passed" == toJson true)
        "previous declared stage failed"
    let candidate := preflight || label.startsWith "b"
    let chosenPrefix := if candidate then installation else selected
    let declared ← read (records/"runtime.json")
    let runtime := chosenPrefix/"libexec/eggshell"
    let expected := declared.getObjValD (if candidate then "candidateSha256" else "parentSha256")
    check (expected == toJson (← hash runtime)) "sealed runtime changed"
    let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let output := trial/label
    let config := output/"config.toml"
    let plugin ← if candidate then pure (installation/"share/eggshell/codex-plugin").toString
      else IO.ofExcept (original.getObjValAs? String "plugin")
    let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
    let environment := environment.map fun (key,value) => (key,match key with
      | "EGGSHELL_PREFIX" => some chosenPrefix.toString
      | "PLUGIN_ROOT" => some plugin
      | "EGGSHELL_CONFIG" => some config.toString
      | _ => value)
    let input := original.setObjVal! "output" (toJson output.toString)
      |>.setObjVal! "config" (toJson config.toString) |>.setObjVal! "environment" (toJson environment)
      |>.setObjVal! "runtime" (toJson runtime.toString) |>.setObjVal! "runtimeSha256" expected
      |>.setObjVal! "plugin" (toJson plugin)
    let input := if preflight then input.setObjVal! "counts" (toJson (#[(4 : Nat)]))
      |>.setObjVal! "diagnostic" (toJson true) else input
    let path := trial/(label++"-input.json")
    check (!(← path.pathExists)) "preserve previous arm"
    write path input
    let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
    guard ("winner-width-runtime-"++label) (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++
      #[runtime.toString,"owned-selection-capacity",path.toString])
  else if args.head? == some "collect" then
    let [_,label] := args | throw (IO.userError "collect <label>")
    let monitor ← clean ("winner-width-runtime-"++label)
    check (!(← (records/(label++".json")).pathExists)) "preserve collected result"
    let report ← read (trial/label/"report.json")
    let sourceRoot : System.FilePath := .mk (← IO.ofExcept ((← read (trial/(label++"-input.json"))).getObjValAs? String "project"))
    let expected : Array (String × String) ← IO.ofExcept (fromJson? ((← read (trial/(label++"-input.json"))).getObjValD "sourceFiles"))
    for (file,digest) in expected do
      check ((← hash (sourceRoot/file)) == digest) "source changed during comparison"
    check (report.getObjValD "allPhasesPassed" == toJson true ||
      (label == "preflight" && (← read (trial/label/"phase-4/result.json")).getObjValD "passed" == toJson true))
      "workload failed"
    write (records/(label++".json")) (Json.mkObj [("guard",monitor),("report",report),
      ("passed",toJson true),("sourceFilesUnchanged",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  else if args.head? == some "retire-arm" then
    let [_,label] := args | throw (IO.userError "retire-arm <collected arm>")
    idle
    discard <| clean ("winner-width-runtime-"++label)
    let value ← read (records/(label++".json"))
    check (value.getObjValD "passed" == toJson true) "retain unsuccessful state for diagnosis"
    let phases : Array Json ← IO.ofExcept (fromJson? ((value.getObjValD "report").getObjValD "phases"))
    let mut clients : Array Json ← IO.ofExcept (fromJson? (← read (trial/label/"prime.json")))
    for phase in phases do
      clients := clients++(← IO.ofExcept (phase.getObjValAs? (Array Json) "rows"))
    let dataRoot := base/"snapshot-scheduling/work/data"
    let protectedPaths := #[selectedBuild/"StudyMain",build/"StudyMain",
      base/"current-six/fixed-sequence/controller-build/StudyMain",
      base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",
      base/"snapshot-scheduling/work/work.egg/head"]
    let before ← protectedPaths.mapM hash
    let mut retired := #[]
    for client in clients do
      let session ← IO.ofExcept (client.getObjValAs? String "session")
      let receipt ← IO.ofExcept (client.getObjValAs? String "receipt")
      let hex := fun (text : String) => text.length == 64 && text.toList.all (fun c =>
        ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))
      check (session.startsWith "capacity-" && hex ((session.drop 9).toString) && hex receipt &&
        client.getObjValD "success" == toJson true && client.getObjValD "acknowledged" == toJson true)
        "only this study's acknowledged native clients may be retired"
      let sessionPath := dataRoot/"sessions"/session
      let state ← read (sessionPath/"state.json")
      let confirmed := state.getObjValD "confirmedDelivery"
      check (confirmed.getObjValD "session" == toJson session) "delivery ledger belongs to another session"
      let authority ← IO.ofExcept ((confirmed.getObjValD "head").getObjValAs? String "authority")
      let context := (authority.drop "confirmed-delivery:".length).toString
      check (authority == "confirmed-delivery:"++context && hex context) "invalid session-owned ledger authority"
      for path in #[sessionPath,dataRoot/"confirmed-delivery"/context,dataRoot/"receipts"/receipt] do
        check ((← path.symlinkMetadata).type == .dir) "retired root must be an owned directory"
        let removed ← removeOwned path
        retired := retired.push (Json.mkObj [("path",toJson path.toString),
          ("files",toJson removed.1),("logicalBytes",toJson removed.2)])
    check ((← protectedPaths.mapM hash) == before) "protected inputs changed during retirement"
    write (records/(label++"-retired.json")) (Json.mkObj [("clients",toJson clients.size),
      ("roots",toJson retired),("retainedInputs",toJson (protectedPaths.zip before)),
      ("retainedHashesUnchanged",toJson true),("archiveCreated",toJson false)])
  else if args == ["report"] then
    idle
    let mut rows := #[]
    let mut parentTimes := #[]
    let mut candidateTimes := #[]
    for label in order do
      let value ← read (records/(label++".json"))
      check (value.getObjValD "passed" == toJson true &&
        value.getObjValD "sourceFilesUnchanged" == toJson true) "only a completed fixed arm may be compared"
      let phases : Array Json ← IO.ofExcept (fromJson? ((value.getObjValD "report").getObjValD "phases"))
      let some wave := phases.find? (fun row => row.getObjValD "clients" == toJson (16 : Nat)) |
        throw (IO.userError "sixteen-client wave missing")
      let elapsed ← IO.ofExcept (wave.getObjValAs? Nat "wallMs")
      if label.startsWith "b" then candidateTimes := candidateTimes.push elapsed
      else parentTimes := parentTimes.push elapsed
      rows := rows.push (Json.mkObj [("label",toJson label),
        ("recordSha256",toJson (← hash (records/(label++".json")))),
        ("phases",toJson (phases.map fun phase => Json.mkObj [("clients",phase.getObjValD "clients"),
          ("wallMs",phase.getObjValD "wallMs"),("passed",phase.getObjValD "passed")])) ,
        ("sampledPeakRssKiB",(value.getObjValD "guard").getObjValD "sampledPeakRssKiB")])
    check (parentTimes.size == 2 && candidateTimes.size == 2) "same-count completed comparison required"
    let parentTotal := parentTimes.foldl Nat.add 0
    let candidateTotal := candidateTimes.foldl Nat.add 0
    check (parentTotal > 0) "nonzero reference clock required"
    write (records/"comparison.json") (Json.mkObj [("order",toJson order),("arms",toJson rows),
      ("parent16WallMs",toJson parentTimes),("candidate16WallMs",toJson candidateTimes),
      ("descriptiveMeanLatencyReductionPercent",toJson
        (100.0*(Float.ofNat parentTotal-Float.ofNat candidateTotal)/Float.ofNat parentTotal)),
      ("fewSecond16ClientTargetMet",toJson (candidateTimes.all (· ≤ 5000))),
      ("p99Established",toJson false),("eightyConcurrentTest",toJson false),
      ("inclusiveTokenOrQualityBenefitEstablished",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  else if args == ["retire-runtime"] then
    idle
    discard <| clean "winner-width-runtime-a-second"
    check ((← read (records/"comparison.json")).getObjValD "adopted" == toJson false)
      "only this completed unadopted runtime may be retired"
    let count ← checkLinks (selectedBuild/"lib") trial
    let count := count+(← checkLinks (base/"study-local-lib") trial)
    let mut protectedPaths := #[selectedBuild/"StudyMain",
      base/"current-six/fixed-sequence/controller-build/StudyMain",
      base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",
      base/"byte-pages-prefix/libexec/eggshell"]
    let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let projectRoot : System.FilePath := .mk (← IO.ofExcept (original.getObjValAs? String "project"))
    let sourceFiles : Array (String × String) ← IO.ofExcept (fromJson? (original.getObjValD "sourceFiles"))
    for (name,_) in sourceFiles do protectedPaths := protectedPaths.push (projectRoot/name)
    let before ← protectedPaths.mapM hash
    let mut removed := #[]
    for path in #[build,source,installation] do
      check ((← path.symlinkMetadata).type == .dir) "retired runtime root must be owned"
      let result ← removeOwned path
      removed := removed.push (Json.mkObj [("path",toJson path.toString),
        ("files",toJson result.1),("logicalBytes",toJson result.2)])
    check ((← protectedPaths.mapM hash) == before) "retained runtime or source changed"
    write (records/"retired-runtime.json") (Json.mkObj [("removed",toJson removed),
      ("activeCompilerInputsChecked",toJson count),("retainedInputs",toJson (protectedPaths.zip before)),
      ("retainedHashesUnchanged",toJson true),("archiveCreated",toJson false)])
  else throw (IO.userError "setup|build|audit|audit-worker|install|prepare|collect")
