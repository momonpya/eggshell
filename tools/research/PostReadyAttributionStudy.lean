import tools.research.StudyLocal
open Lean StudyLocal
namespace PostReadyStudy
def root := base/"post-ready-attribution"
def records := project/"docs/candidates/post-ready-attribution"
def installation := base/"register-rounds-runtime/prefix"
def runtime := installation/"libexec/eggshell"
def dataRoot := base/"snapshot-scheduling/work/data"
def tag := "post-ready-attribution"
def observerSource := root/"observer-source"
def observerBuild := root/"observer-build"
def cleanAt (name : String) : IO Json := do
  let monitor ← finished name
  check (monitor.getObjValD "guardTriggered" == toJson false && monitor.getObjValD "reason" == Json.null)
    "diagnostic guard did not finish normally"
  return monitor
def clean := cleanAt tag
def receipts : IO (Array String) := do
  let path := dataRoot/"receipts"
  if !(← path.pathExists) then return #[]
  return (← path.readDir).map (·.fileName)
def setup : IO Unit := do
  idle
  check (!(← root.pathExists)) "fresh diagnostic root required"
  check (!(← (records/"result.json").pathExists)) "a collected diagnostic cannot be overwritten"
  let expected := "1153215e50e63191a46b1f80a34d8c2c0d056478b30b81e5c22958d2c1a8c965"
  check ((← hash runtime) == expected) "audited current runtime changed"
  let (compiled,_) : String × Array (String × String) ← IO.ofExcept
    (fromJson? (← read (base/"register-rounds-runtime/build/Eggshell_Handoff.source")))
  check (compiled == (← IO.FS.readFile (base/"register-rounds-runtime/source/Eggshell/Handoff.lean")))
    "diagnostic source is not the actual native source"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  write (root/"receipts-before.json") (toJson (← receipts))
  let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
  check (original.getObjValD "data" == toJson dataRoot.toString) "isolated fixture scope changed"
  let output := root/"run"
  let config := output/"config.toml"
  let plugin := installation/"share/eggshell/codex-plugin"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
  let controlled := #["EGGSHELL_PREFIX","PLUGIN_ROOT","EGGSHELL_CONFIG","EGGSHELL_TRACE_QUERY_STAGES",
    "EGGSHELL_TRACE_SERVICE_PROFILE","EGGSHELL_TRACE_ACTOR_HEAP","EGGSHELL_TRACE_ALLOCATOR",
    "EGGSHELL_TRACE_SELECTION_RANGES","EGGSHELL_TRACE_SELECTOR_INPUT","EGGSHELL_HANDOFF_TRACE"]
  let environment := environment.filter (fun row => !controlled.contains row.1) ++ #[
    ("EGGSHELL_PREFIX",some installation.toString),("PLUGIN_ROOT",some plugin.toString),("EGGSHELL_CONFIG",some config.toString),
    ("EGGSHELL_TRACE_QUERY_STAGES",some "1"),("EGGSHELL_TRACE_SERVICE_PROFILE",some "1"),
    ("EGGSHELL_TRACE_ACTOR_HEAP",none),("EGGSHELL_TRACE_ALLOCATOR",none),
    ("EGGSHELL_TRACE_SELECTION_RANGES",none),("EGGSHELL_TRACE_SELECTOR_INPUT",none),
    ("EGGSHELL_HANDOFF_TRACE",some (root/"handoff-trace.txt").toString)]
  let input := original.setObjVal! "output" (toJson output.toString) |>.setObjVal! "config" (toJson config.toString)
    |>.setObjVal! "runtime" (toJson runtime.toString) |>.setObjVal! "runtimeSha256" (toJson expected)
    |>.setObjVal! "plugin" (toJson plugin.toString) |>.setObjVal! "environment" (toJson environment)
    |>.setObjVal! "counts" (toJson (#[(4 : Nat)])) |>.setObjVal! "diagnostic" (toJson true)
  write (root/"input.json") input
  write (records/"plan.json") (Json.mkObj [("classificationPreviousTurn",toJson "progress:actual range-index connection proved and measured;6.366% descriptive improvement does not meet few-second16-client target"),
    ("runtimeSha256",toJson expected),("productChanges",toJson (0 : Nat)),("newBuild",toJson false),
    ("workload",toJson "three sequential canonical primes then four parallel native hooks"),
    ("observation",toJson "existing relative handoff trace plus scalar service profiles;heap and selection-input/range capture disabled"),
    ("unresolved",toJson "existing source preparation about100ms and selection about1400ms do not explain4654-4837ms after ready"),
    ("knownTracingGap",toJson "single-source indexedDiscovery does not forward the existing onStage callback"),
    ("notPerformanceComparison",toJson true),("interferencePossible",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false)])
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
  guard tag (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++
    #[runtime.toString,"owned-selection-capacity",(root/"input.json").toString])
def collectAt (early : Bool) (transport := false) : IO Unit := do
  let name := if transport then "transport-source-sample" else if early then "early-source-sample" else tag
  let output := root/(if transport then "transport-run" else if early then "early-run" else "run")
  let inputName := if transport then "transport-input.json" else if early then "early-input.json" else "input.json"
  let traceName := if transport then "transport-handoff-trace.txt" else if early then "early-handoff-trace.txt" else "handoff-trace.txt"
  let beforeName := if transport then "receipts-before-transport.json" else if early then "receipts-before-early.json" else "receipts-before.json"
  let resultName := if transport then "transport-result.json" else if early then "early-result.json" else "result.json"
  let monitor ← cleanAt name
  let input ← read (root/inputName)
  let report ← read (output/"report.json")
  let phase ← read (output/"phase-4/result.json")
  check (phase.getObjValD "passed" == toJson true) "diagnostic native wave failed"
  let primes : Array Json ← IO.ofExcept (fromJson? (← read (output/"prime.json")))
  let rows : Array Json ← IO.ofExcept (phase.getObjValAs? (Array Json) "rows")
  let clients := primes++rows
  check (clients.size == 7 && clients.all (fun row =>
    row.getObjValD "success" == toJson true && row.getObjValD "bodyByteEqual" == toJson true &&
      row.getObjValD "acknowledged" == toJson true)) "all seven canonical bodies and ACK required"
  let origin : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let expected : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (file,digest) in expected do check ((← hash (origin/file)) == digest) "original source file changed"
  let mut windows := #[]
  let mut actors := #[]
  for client in clients do
    let id ← IO.ofExcept (client.getObjValAs? String "receipt")
    let directory := dataRoot/"receipts"/id
    let published := (← read (directory/"published.json")).getObjValD "data"
    let first ← IO.ofExcept (published.getObjValAs? Nat "startedMs")
    let last ← IO.ofExcept (published.getObjValAs? Nat "flushedMs")
    windows := windows.push (id,first,last)
    let mut fields := [("client",client),("startedMs",toJson first),("flushedMs",toJson last)]
    for name in ["request-pages","operation-service","search"] do
      let path := directory/(name++".json")
      if ← path.pathExists then fields := fields++[(name,← read path)]
    actors := actors.push (Json.mkObj fields)
  let before : Array String ← IO.ofExcept (fromJson? (← read (root/beforeName)))
  let created := (← receipts).filter (!before.contains ·)
  let mut profiles := #[]
  for id in created do
    for file in ← (dataRoot/"receipts"/id).readDir do
      if !file.fileName.endsWith "-profile.json" then continue
      profiles := profiles.push (← read file.path)
  let text ← IO.FS.readFile (root/traceName)
  check (!text.isEmpty) "existing handoff trace is missing"
  IO.FS.writeFile (records/traceName) text
  let mut sampling := Json.null
  if early then
    sampling ← read (output/"sampling.json")
    check (sampling.getObjValD "sampleExitCode" == toJson (0 : Nat)) "early native sample failed"
    IO.FS.writeFile (records/(if transport then "transport-source.sample.txt" else "early-source.sample.txt"))
      (← IO.FS.readFile (output/"publisher-late.sample.txt"))
  write (records/resultName) (Json.mkObj [("input",input),("guard",monitor),("report",report),
    ("primes",toJson primes),("actors",toJson actors),("clientWindows",toJson windows),("serviceProfiles",toJson profiles),
    ("createdReceipts",toJson created),("sourceFilesUnchanged",toJson true),
    ("productSha256Unchanged",toJson ((← hash runtime) == "1153215e50e63191a46b1f80a34d8c2c0d056478b30b81e5c22958d2c1a8c965")),
    ("traceSha256",toJson (← hash (root/traceName))),("sampling",sampling),
    ("concurrentProfilesAttributedToIndividualRequests",toJson false),
    ("notPerformanceComparison",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
partial def removeOwned (path : System.FilePath) : IO (Nat × Nat) := do
  let stat ← path.symlinkMetadata
  if stat.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let count ← removeOwned entry.path
      total := (total.1+count.1,total.2+count.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if stat.type == .file then stat.byteSize.toNat else 0)

partial def retainedLinks (path : System.FilePath) : IO Nat := do
  let actual ← IO.FS.realPath path
  check (!(actual.toString.startsWith (root.toString++"/"))) "active input depends on the completed observer"
  if (← path.symlinkMetadata).type == .dir then
    let mut count := 0
    for entry in ← path.readDir do count := count+(← retainedLinks entry.path)
    return count
  return 1

def retire : IO Unit := do
  idle
  check (!(← (records/"retired.json").pathExists)) "preserve completed retirement evidence"
  for (name,file) in [(tag,"result.json"),("early-source-sample","early-result.json"),
      ("transport-source-sample","transport-result.json")] do
    discard <| cleanAt name
    let result ← read (records/file)
    check (result.getObjValD "sourceFilesUnchanged" == toJson true &&
      result.getObjValD "productSha256Unchanged" == toJson true) "collect every source check before retirement"
    let actors : Array Json ← IO.ofExcept (result.getObjValAs? (Array Json) "actors")
    check (actors.size == 7) "all seven successful native clients must be collected"
  for file in #[dataRoot/"publisher/endpoint.json",dataRoot/"publisher/operations.json",dataRoot/"daemon.json"] do
    check (!(← file.pathExists)) "service endpoint still needs recovery"
  let kept := #[runtime,base/"current-six/stable-source-rows/build/StudyMain",
    base/"current-six/fixed-sequence/controller-build/StudyMain",base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",
    base/"byte-pages-prefix/libexec/eggshell",base/"snapshot-scheduling/work/work.egg/head"] ++
    (#[1,2,3].map fun n => base/"snapshot-scheduling/diagnostic"/("topic-"++toString n)/"body.txt")
  let hashes ← kept.mapM hash
  let input ← read (root/"input.json")
  let origin : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let sources : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (name,digest) in sources do check ((← hash (origin/name)) == digest) "protected original source changed"
  let mut checked := 0
  for directory in #[base/"register-rounds-runtime/build/lib",base/"current-six/stable-source-rows/build/lib",
      base/"current-six/fixed-sequence/preparation-closure-build/lib",base/"study-local-lib"] do
    if ← directory.pathExists then checked := checked+(← retainedLinks directory)
  let mut monitors := #[]
  let mut guardFiles := #[]
  for file in ← base.readDir do
    if !file.fileName.endsWith ".guard.json" || !(["post-ready-attribution.","early-source-observer-",
        "early-source-sample.","transport-source-observer-","transport-marker-observer-","transport-source-sample."].any
        (fun start => file.fileName.startsWith start)) then continue
    let monitor ← read file.path
    check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "observer guard still owns children"
    monitors := monitors.push (file.fileName,monitor)
    guardFiles := guardFiles.push file.path
    let settings := base/(file.fileName.replace ".guard.json" ".guard-settings.json")
    if ← settings.pathExists then guardFiles := guardFiles.push settings
  write (records/"resources.json") (toJson monitors)
  IO.FS.writeFile (records/"ObserverDefault.lean") (← IO.FS.readFile (root/"ObserverDefault.lean"))
  write (records/"observer-build.json") (← read (observerBuild/"build.json"))
  let mut deleted := #[]
  -- These three directories belong only to the model-free performance fixture;
  -- the source DB is its sibling work.egg and the project read-cache is kept.
  for path in #[dataRoot/"sessions",dataRoot/"confirmed-delivery",dataRoot/"receipts",root] ++ guardFiles ++
      #[base/"early-source-sample-settings.json"] do
    check (← path.pathExists) "owned retirement target disappeared"
    let count ← removeOwned path
    deleted := deleted.push (path.toString,count.1,count.2)
  check ((← kept.mapM hash) == hashes) "protected runtime, head or canonical body changed"
  for (name,digest) in sources do check ((← hash (origin/name)) == digest) "protected source changed during cleanup"
  write (records/"retired.json") (Json.mkObj [("deleted",toJson deleted),
    ("protectedInputs",toJson (kept.zip hashes)),("protectedSources",toJson sources),
    ("activeCompilerInputsChecked",toJson checked),("protectedHashesUnchanged",toJson true),
    ("projectReadCacheAndModelRetained",toJson true),("archiveCreated",toJson false)])
def main (args : List String) : IO Unit := do
  match args with
  | ["setup"] => setup
  | ["collect"] => collectAt false
  | ["early-collect"] => collectAt true
  | ["transport-collect"] => collectAt true true
  | ["retire"] => retire
  | _ => throw (IO.userError "setup | collect | early-collect | transport-collect | retire")
end PostReadyStudy
def main := PostReadyStudy.main
