import tools.research.StudyLocal
open Lean StudyLocal
namespace CursorCodecStudy
def root := base/"cursor-codec"
def source := root/"source"
def build := root/"build"
def parent := base/"canonical-decoder-runtime"
def records := project/"docs/candidates/cursor-codec"
def bindingRoot := base/"cursor-binding"
def bindingSource := bindingRoot/"source"
def bindingBuild := bindingRoot/"build"
def pageRoot := base/"cursor-readers-component"
def pageSourceRoot := pageRoot/"source"
def pageBuild := pageRoot/"build"
def runtimeRoot := base/"cursor-reader-runtime"
def runtimeSource := runtimeRoot/"source"
def runtimeBuild := runtimeRoot/"build"
def runtimePrefix := runtimeRoot/"prefix"
def runtimeData := runtimeRoot/"data"
def runtimeRecords := records/"runtime"
def clean (label : String) : IO Json := do
  let monitor ← finished ("cursor-codec-"++label)
  check (monitor.getObjValD "guardTriggered" == toJson false && monitor.getObjValD "reason" == Json.null) "resource stop"
  return monitor
def guarded (label : String) := guard ("cursor-codec-"++label)
def driver := project/"tools/research/CursorCodecStudy.lean"
def metadata (label action : String) := guarded label #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
  (compiler/"bin/lean").toString,"-j1","-M1536","--run",driver.toString,action]
def pageSource : IO String := do
  let original ← IO.FS.readFile (parent/"source/Eggshell/DB/PageMap.lean")
  let marker := "def Snapshot.load (snapshot : Snapshot)"
  check ((original.splitOn marker).length == 2) "original load boundary changed"
  let tail := (original.splitOn marker)[1]!
  let stop := "/-- The last fence not greater than the key"
  check ((tail.splitOn stop).length == 2) "original load end changed"
  let body := "def load (snapshot : Snapshot)"++(tail.splitOn stop)[0]!
  let library ← IO.FS.readFile (project/"tools/research/CursorPage.lean")
  let final := "end Eggshell.DB.PageMap.CursorReader"
  check ((library.splitOn final).length == 2) "cursor page namespace changed"
  return library.replace final (body++
    "theorem load_exact (snapshot : Snapshot) (ref : Ref) : load snapshot ref = snapshot.load ref := by\n"++
    "  unfold load Snapshot.load\n"++
    "  rw [show decode = Eggshell.DB.PageMap.decode from funext fun bytes =>\n"++
    "    (decode_exact bytes).trans (CanonicalDecoder.decode_without_encode_exact bytes)]\n  rfl\n\n"++
    "@[csimp] theorem compiled_load : @Snapshot.load = @load := by\n"++
    "  funext snapshot ref\n  exact (load_exact snapshot ref).symm\n\n"++
    "#print axioms load_exact\n"++final)
def replace (text before after : String) : IO String := do
  check ((text.splitOn before).length == 2) "unique reader source boundary required"
  return text.replace before after
def scanSource (original : String) : IO String := do
  let original ← replace original "public import Eggshell.SynapticBindings\n"
    "public import Eggshell.SynapticBindings\npublic import tools.research.CursorBinding\npublic import tools.research.CursorPage\n"
  replace original "      let stored ← Index.decodeBinding bytes\n" "      let stored ← CursorBinding.decode bytes\n"
def wireSource (original : String) : IO String := do
  let marker := "  (include_str \"../tools/research/BindingPageScan.lean\").toUTF8,\n"
  replace original marker (marker++
    "  (include_str \"../tools/research/CursorCodec.lean\").toUTF8,\n"++
    "  (include_str \"../tools/research/CursorBinding.lean\").toUTF8,\n"++
    "  (include_str \"../tools/research/CursorPage.lean\").toUTF8,\n")

def capture (label : String) : IO Unit := do
  let monitor ← clean label
  let input ← read (runtimeRoot/(label++"-input.json"))
  let output := runtimeRoot/label
  let report ← read (output/"report.json")
  let preflight := label == "preflight"
  check (report.getObjValD "allPhasesPassed" == toJson true || (preflight &&
    (← read (output/"phase-4/result.json")).getObjValD "passed" == toJson true)) "native waves failed"
  let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (name,digest) in files do check ((← hash (database/name)) == digest) "original source changed"
  let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let mut clients : Array Json ← IO.ofExcept (fromJson? (← read (output/"prime.json")))
  let phases : Array Json ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
  for phase in phases do clients := clients++(← IO.ofExcept (phase.getObjValAs? (Array Json) "rows"))
  check (clients.size == (if preflight then 7 else 23) && clients.all (fun row =>
    row.getObjValD "success" == toJson true && row.getObjValD "bodyByteEqual" == toJson true &&
    row.getObjValD "acknowledged" == toJson true)) "canonical bodies and ACKs required"
  let mut requests := #[]
  for client in clients do
    let id ← IO.ofExcept (client.getObjValAs? String "receipt")
    let mut fields := [("client",client)]
    for name in ["request-pages","operation-service"] do
      let path := data/"receipts"/id/(name++".json")
      if ← path.pathExists then fields := fields++[(name,← read path)]
    requests := requests.push (Json.mkObj fields)
  let mut fields := [("input",input),("guard",monitor),("report",report),("clients",toJson requests),
    ("warm",← read (output/"warm/stdout")),("warmRecord",← read (output/"warm/record.json")),
    ("passed",toJson true),("allOriginalFilesUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  for name in ["cache-stats-prime","cache-stats-phase-4","cache-stats-phase-16","frontend-shutdown","publisher-shutdown"] do
    let path := output/(name++".json")
    if ← path.pathExists then fields := fields++[(name,← read path)]
  check (!(← (runtimeRecords/(label++".json")).pathExists)) "preserve collected trial"
  write (runtimeRecords/(label++".json")) (Json.mkObj fields)

/-- Preserve a failed declared arm; a completed stdout is not a completed ACK.
This collector cannot turn failure into a passing comparison. -/
def captureFailed (label : String) : IO Unit := do
  idle
  let monitor ← read (base/("cursor-codec-"++label++".guard.json"))
  check (monitor.getObjValD "state" == toJson "finished" &&
    monitor.getObjValD "exitCode" == toJson (1 : Nat) &&
    monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    monitor.getObjValD "guardTriggered" == toJson false) "expected drained failed arm"
  let input ← read (runtimeRoot/(label++"-input.json"))
  let output := runtimeRoot/label
  let phases : Array Json ← IO.ofExcept (fromJson? (← read (output/"progress.json")))
  check (phases.any (fun phase => phase.getObjValD "passed" == toJson false)) "failure record has no failed phase"
  let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (name,digest) in files do check ((← hash (database/name)) == digest) "original source changed"
  let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let topics ← IO.ofExcept (input.getObjValAs? (Array Json) "topics")
  let mut clients : Array Json ← IO.ofExcept (fromJson? (← read (output/"prime.json")))
  for phase in phases do clients := clients++(← IO.ofExcept (phase.getObjValAs? (Array Json) "rows"))
  let mut observations := #[]
  for client in clients do
    let id ← IO.ofExcept (client.getObjValAs? String "receipt")
    let mut fields := [("client",client)]
    for name in ["published","ack","capacity-client-error","request-pages","operation-service","dispatch","transport","search"] do
      let path := data/"receipts"/id/(name++".json")
      if ← path.pathExists then
        let record ← read path
        -- Keep timing and integrity, not a second copy of half-megabyte output.
        let record ← if name == "published" then do
          let dataFields ← IO.ofExcept ((record.getObjValD "data").getObj?)
          pure (record.setObjVal! "data" (Json.mkObj (dataFields.toList.filter (·.1 != "output"))))
          else pure record
        fields := fields++[(name,record)]
    if client.getObjValD "success" != toJson true then
      let topic ← IO.ofExcept (client.getObjValAs? Nat "topic")
      let some expected := topics.find? (fun item => item.getObjValD "topic" == toJson topic) |
        throw (IO.userError "failed client's fixed topic is missing")
      let count ← IO.ofExcept ((phases.find? (fun phase => (phase.getObjValD "rows").getArr?.toOption.getD #[] |>.contains client)).getD Json.null |>.getObjValAs? Nat "clients")
      let index ← IO.ofExcept (client.getObjValAs? Nat "client")
      let stdout := output/s!"phase-{count}/client-{index}/stdout"
      let json ← read stdout
      let actual ← IO.ofExcept ((json.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
      let canonical ← IO.FS.readFile (.mk (← IO.ofExcept (expected.getObjValAs? String "body")))
      fields := fields++[("observedStdout",Json.mkObj [("bytes",toJson actual.utf8ByteSize),
        ("bodyByteEqual",toJson (actual == canonical)),("stdoutSha256",toJson (← hash stdout)),
        ("notAnAcknowledgedSuccess",toJson true)])]
      let session ← IO.ofExcept (client.getObjValAs? String "session")
      let state ← read (data/"sessions"/session/"state.json")
      fields := fields++[("finalSession",Json.mkObj [("epoch",state.getObjValD "epoch"),
        ("offers",state.getObjValD "offers"),("confirmedDelivery",state.getObjValD "confirmedDelivery"),
        ("notAServerReplyTimestamp",toJson true)])]
    observations := observations.push (Json.mkObj fields)
  let mut fields := [("input",input),("guard",monitor),("phases",toJson phases),("clients",toJson observations),
    ("allOriginalFilesUnchanged",toJson true),("passed",toJson false),("comparisonStopped",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  for name in ["cache-stats-prime","cache-stats-phase-4","cache-stats-phase-16","frontend-shutdown","publisher-shutdown"] do
    let path := output/(name++".json")
    if ← path.pathExists then fields := fields++[(name,← read path)]
  check (!(← (runtimeRecords/(label++"-failed.json")).pathExists)) "preserve failed trial"
  write (runtimeRecords/(label++"-failed.json")) (Json.mkObj fields)

partial def removeOwned (path : System.FilePath) : IO (Nat × Nat) := do
  let stat ← path.symlinkMetadata
  if stat.type == .dir then
    let mut count := (0,0)
    for entry in ← path.readDir do
      let next ← removeOwned entry.path
      count := (count.1+next.1,count.2+next.2)
    IO.FS.removeDir path
    return count
  IO.FS.removeFile path
  return (1,if stat.type == .file then stat.byteSize.toNat else 0)

def retireArm (label : String) (failed : Bool := false) : IO Unit := do
  idle
  if failed then
    let monitor ← read (base/("cursor-codec-"++label++".guard.json"))
    check (monitor.getObjValD "state" == toJson "finished" &&
      monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "failed guard has not drained"
  else discard <| clean label
  let record ← read (runtimeRecords/(label++(if failed then "-failed.json" else ".json")))
  check (record.getObjValD "passed" == toJson (!failed)) "collect trial before cleanup"
  let data : System.FilePath := .mk (← IO.ofExcept ((record.getObjValD "input").getObjValAs? String "data"))
  check (data == runtimeData || data == parent/"data") "cleanup escaped current private fixtures"
  for path in #[data/"publisher/endpoint.json",data/"publisher/operations.json",data/"daemon.json"] do
    check (!(← path.pathExists)) "service endpoint remains"
  let paths := #[runtimeBuild/"StudyMain",parent/"build/StudyMain",base/"snapshot-scheduling/work/work.egg/head"] ++
    (#[1,2,3].map fun n => base/"snapshot-scheduling/diagnostic"/("topic-"++toString n)/"body.txt")
  let hashes ← paths.mapM hash
  let mut deleted := #[]
  for path in #[runtimeRoot/label,data/"sessions",data/"confirmed-delivery",data/"receipts"] do
    if ← path.pathExists then
      let count ← removeOwned path
      deleted := deleted.push (path.toString,count.1,count.2)
  check ((← paths.mapM hash) == hashes) "cleanup changed protected runtime, head or body"
  write (runtimeRecords/(label++"-retired.json")) (Json.mkObj [("deleted",toJson deleted),
    ("protectedHashesUnchanged",toJson true),("archive",toJson false)])

def obsoleteRoots := #[root,bindingRoot,pageRoot,runtimeRoot,base/"ack-path-diagnosis"]
def retainedPath (path : System.FilePath) : IO Unit := do
  let actual ← IO.FS.realPath path
  check (!(obsoleteRoots.any (fun root => actual.toString.startsWith (root.toString++"/"))))
    "active native/compiler input depends on obsolete candidate"
partial def retainedTree (path : System.FilePath) : IO Nat := do
  retainedPath path
  if (← path.symlinkMetadata).type == .dir then
    let mut count := 0
    for entry in ← path.readDir do count := count+(← retainedTree entry.path)
    return count
  return 1

/-- The failed original arm stops this candidate comparison. Preserve its small
proof/source/result witnesses, then remove the unadopted runtime and copies. -/
def retire : IO Unit := do
  idle
  check (!(← (records/"retired.json").pathExists)) "preserve retirement record"
  check ((← read (runtimeRecords/"a-first-failed.json")).getObjValD "comparisonStopped" == toJson true) "declared comparison was not stopped"
  for label in ["preflight","a-first"] do
    check ((← read (runtimeRecords/(label++"-retired.json"))).getObjValD "protectedHashesUnchanged" == toJson true) "trial raw state still live"
  let diagnosis := (← read (records/"ack-diagnosis/observed.json")).getObjValD "input"
  check (← (records/"ack-diagnosis/cursor-observed.json").pathExists) "collect candidate diagnostic first"
  check (diagnosis.getObjValD "runtime" == toJson (parent/"prefix/libexec/eggshell").toString &&
    diagnosis.getObjValD "data" == toJson (parent/"data").toString) "ACK diagnosis still uses candidate runtime or cache"
  for data in #[parent/"data",runtimeData] do
    for file in #["publisher/endpoint.json","publisher/operations.json","daemon.json"] do
      check (!(← (data/file).pathExists)) "service endpoint remains before retirement"
  let liveBuilds := #[parent/"build",base/"register-rounds-runtime/build",
    base/"current-six/stable-source-rows/build",base/"current-six/fixed-sequence/controller-build",
    base/"current-six/fixed-sequence/preparation-closure-build"]
  let protectedPaths := (liveBuilds.map (·/"StudyMain"))++#[base/"byte-pages-prefix/libexec/eggshell",
    base/"snapshot-scheduling/work/work.egg/head"]++
    (#[1,2,3].map fun n => base/"snapshot-scheduling/diagnostic"/("topic-"++toString n)/"body.txt")
  let hashes ← protectedPaths.mapM hash
  let mut checked := 0
  for live in liveBuilds do
    for line in (← IO.FS.readFile (live/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let object : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      for path in #[object,object.withExtension "source",object.withExtension "dependencies"] do
        if ← path.pathExists then retainedPath path; checked := checked+1
    if ← (live/"lib").pathExists then checked := checked+(← retainedTree (live/"lib"))
  checked := checked+(← retainedTree (base/"study-local-lib"))
  let original : System.FilePath := .mk (← IO.ofExcept (diagnosis.getObjValAs? String "project"))
  let originals : Array (String × String) ← IO.ofExcept (fromJson? (diagnosis.getObjValD "sourceFiles"))
  for (file,digest) in originals do check ((← hash (original/file)) == digest) "source changed before cleanup"
  let mut monitors := #[]
  let mut guardFiles := #[]
  for file in ← base.readDir do
    if !(file.fileName.startsWith "cursor-codec-" || file.fileName.startsWith "ack-path-") || !file.fileName.endsWith ".guard.json" then continue
    let monitor ← read file.path
    check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "candidate still owns a process"
    monitors := monitors.push (file.fileName,monitor)
    guardFiles := guardFiles.push file.path
    let settings := base/(file.fileName.replace ".guard.json" ".guard-settings.json")
    if ← settings.pathExists then guardFiles := guardFiles.push settings
  write (records/"resources.json") (toJson monitors)
  let builds ← obsoleteRoots.mapM fun root => do
    return (root.toString,← read (root/"build/build.json"))
  write (records/"builds.json") (toJson builds)
  write (records/"ack-diagnosis/cursor-observer-build.json") (← read (base/"ack-path-diagnosis/cursor-build/build.json"))
  for name in #["cursor-codec-settings.json","cursor-binding-settings.json","cursor-readers-settings.json",
      "cursor-reader-runtime-settings.json","ack-path-settings.json","ack-path-cursor-settings.json"] do
    let path := base/name
    if ← path.pathExists then guardFiles := guardFiles.push path
  let mut deleted := #[]
  for path in obsoleteRoots++guardFiles++#[parent/"data/sessions",parent/"data/confirmed-delivery",parent/"data/receipts"] do
    if !(← path.pathExists) then continue
    let count ← removeOwned path
    deleted := deleted.push (path.toString,count.1,count.2)
  check ((← protectedPaths.mapM hash) == hashes) "cleanup changed protected native inputs"
  for (file,digest) in originals do check ((← hash (original/file)) == digest) "source changed during cleanup"
  write (records/"retired.json") (Json.mkObj [("deleted",toJson deleted),("activeNativeCompilerInputsChecked",toJson checked),
    ("protected",toJson (protectedPaths.zip hashes)),("originalSourceUnchanged",toJson true),
    ("archive",toJson false),("endedExperimentCannotBeResumed",toJson true)])

def hexadecimal (value : String) : Option Nat :=
  value.toList.foldlM (fun n c => do
    let digit ← if '0' ≤ c && c ≤ '9' then some (c.toNat-'0'.toNat)
      else if 'a' ≤ c && c ≤ 'f' then some (c.toNat-'a'.toNat+10) else none
    return n*16+digit) 0

def nativeCalls : IO Unit := do
  idle
  discard <| clean "runtime-audit"
  let object := runtimeBuild/"tools_research_BindingPageScan.o"
  let columns := fun (line : String) => (line.replace "\t" " ").splitOn " " |>.filter (!·.isEmpty)
  let symbols := ((← command "/usr/bin/nm" #["-n",object.toString]).splitOn "\n").filterMap (fun row => do
    let fields := columns row
    unless fields[1]? == some "T" || fields[1]? == some "t" do none
    return (← hexadecimal (← fields[0]?),← fields[2]?))
  let mut calls := #[]
  let mut binding := false
  let mut page := false
  for row in (← command "/usr/bin/otool" #["-rv",object.toString]).splitOn "\n" do
    let fields := columns row
    let some target := fields.getLast? | continue
    unless fields.contains "BR26" && ["CursorBinding_decode","PageMap_CursorReader_load",
        "Index_decodeBinding","Index_CanonicalDecoder_decodeWithoutEncode","PageMap_Snapshot_load"].any (fun name => target.contains name) do continue
    let some address := fields[0]?.bind hexadecimal | throw (IO.userError "native branch lacks address")
    let some caller := (symbols.takeWhile (·.1 ≤ address)).getLast?.map Prod.snd | throw (IO.userError "native branch owner missing")
    if caller.contains "BindingPageScan_scanAt" then
      check (!(target.contains "Index_decodeBinding" || target.contains "Index_CanonicalDecoder_decodeWithoutEncode" ||
        target.contains "PageMap_Snapshot_load")) "hot original scan still calls a list decoder"
      binding := binding || target.contains "CursorBinding_decode"
      page := page || target.contains "PageMap_CursorReader_load"
    calls := calls.push (caller,target,address)
  check (binding && page) "hot original scan lacks both direct readers"
  write (runtimeRecords/"native-calls.json") (Json.mkObj [("calls",toJson calls),("hotBindingAndPageReaders",toJson true),
    ("objectSha256",toJson (← hash object)),("runtimeSha256",toJson (← hash (runtimeBuild/"StudyMain"))),
    ("notAFullCCompilerProof",toJson true)])
def main (args : List String) : IO Unit := do
  match args with
  | ["native-calls"] => nativeCalls
  | ["capture",label] => capture label
  | ["capture-failed",label] => captureFailed label
  | ["retire-arm",label] => retireArm label
  | ["retire-failed",label] => retireArm label true
  | ["retire"] => retire
  | ["post-retirement-check"] => do
    check (← (records/"retired.json").pathExists) "retirement record required"
    metadata "post-retirement" "post-retirement-worker"
  | ["post-retirement-worker"] => do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(parent/"build").toString,
      (records/"parent-after-retirement.json").toString]
  | ["finish-retirement"] => do
    write (records/"post-retirement-guard.json") (← clean "post-retirement")
    for ending in [".guard.json",".guard-settings.json"] do
      IO.FS.removeFile (base/("cursor-codec-post-retirement"++ending))
  | ["install"] => do
    discard <| clean "runtime-audit"
    metadata "install" "install-worker"
  | ["install-worker"] => do
    check (!(← runtimePrefix.pathExists) && !(← runtimeData.pathExists)) "fresh candidate prefix/cache required"
    let plugin := runtimePrefix/"share/eggshell/codex-plugin"
    IO.FS.createDirAll (runtimePrefix/"libexec")
    IO.FS.createDirAll (plugin/"bin")
    discard <| command "/bin/ln" #["-s",(runtimeBuild/"StudyMain").toString,(runtimePrefix/"libexec/eggshell").toString]
    discard <| command "/bin/ln" #["-s",(parent/"prefix/share/eggshell/minilm").toString,(runtimePrefix/"share/eggshell/minilm").toString]
    for name in ["egg","eggshelld"] do
      let original ← IO.FS.readFile (parent/"prefix/share/eggshell/codex-plugin/bin"/name)
      check (original.contains (parent/"prefix").toString) "launcher boundary changed"
      IO.FS.writeFile (plugin/"bin"/name) (original.replace (parent/"prefix").toString runtimePrefix.toString)
      discard <| command "/bin/chmod" #["755",(plugin/"bin"/name).toString]
    IO.FS.createDirAll runtimeData
    discard <| command "/bin/cp" #["-c","-R",(parent/"data/read-cache").toString,(runtimeData/"read-cache").toString]
    check ((← IO.FS.realPath (runtimeData/"read-cache")) != (← IO.FS.realPath (parent/"data/read-cache"))) "candidate cache aliases parent"
  | ["prepare",label] => do
    discard <| clean "install"
    let order := #["a-first","b-first","b-second","a-second"]
    let preflight := label == "preflight"
    if !preflight then
      let some position := order.findIdx? (· == label) | throw (IO.userError "undeclared comparison arm")
      let prior := if position == 0 then "preflight" else order[position-1]!
      discard <| clean prior
      check ((← read (runtimeRecords/(prior++".json"))).getObjValD "passed" == toJson true) "collect preceding arm first"
    let candidate := preflight || label.startsWith "b"
    let installation := if candidate then runtimePrefix else parent/"prefix"
    let data := if candidate then runtimeData else parent/"data"
    let executable := installation/"libexec/eggshell"
    let expected := (← read (runtimeRecords/"runtime.json")).getObjValD (if candidate then "sha256" else "parentSha256")
    check (expected == toJson (← hash executable)) "audited runtime changed"
    let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let output := runtimeRoot/label
    let config := output/"config.toml"
    let plugin := installation/"share/eggshell/codex-plugin"
    let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
    let environment := (environment.filter (·.1 != "EGGSHELL_HANDOFF_TRACE")).map (fun (key,value) => (key,match key with
      | "EGGSHELL_PREFIX" => some installation.toString | "PLUGIN_ROOT" => some plugin.toString
      | "EGGSHELL_DATA_ROOT" => some data.toString | "EGGSHELL_CONFIG" => some config.toString | _ => value)) ++ #[("EGGSHELL_HANDOFF_TRACE",none)]
    let input := original.setObjVal! "output" (toJson output.toString) |>.setObjVal! "config" (toJson config.toString)
      |>.setObjVal! "environment" (toJson environment) |>.setObjVal! "runtime" (toJson executable.toString)
      |>.setObjVal! "runtimeSha256" expected |>.setObjVal! "plugin" (toJson plugin.toString) |>.setObjVal! "data" (toJson data.toString)
    let input := if preflight then input.setObjVal! "counts" (toJson (#[(4 : Nat)])) |>.setObjVal! "diagnostic" (toJson true) else input
    let path := runtimeRoot/(label++"-input.json")
    check (!(← path.pathExists)) "preserve trial input"
    write path input
    let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
    guarded label (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++#[executable.toString,"owned-selection-capacity",path.toString])
  | ["runtime-setup"] => do
    idle
    discard <| clean "measure-pages"
    check ((← read (records/"readers-run.json")).getObjValD "allOriginalFilesUnchanged" == toJson true) "collect page component first"
    IO.FS.createDirAll runtimeRecords
    materialize (parent/"build") runtimeSource runtimeBuild "tools.research.OwnedSelectionRuntime" "cursor-reader-runtime-settings.json"
    for name in ["CursorCodec","CursorBinding"] do
      IO.FS.writeFile (runtimeSource/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    IO.FS.writeFile (runtimeSource/"tools/research/CursorPage.lean") (← pageSource)
    IO.FS.writeFile (runtimeSource/"tools/research/BindingPageScan.lean")
      (← scanSource (← IO.FS.readFile (parent/"source/tools/research/BindingPageScan.lean")))
    IO.FS.writeFile (runtimeSource/"Eggshell/PublicationWire.lean")
      (← wireSource (← IO.FS.readFile (parent/"source/Eggshell/PublicationWire.lean")))
    check (!(← runtimeBuild.pathExists)) "fresh runtime compiler cache required"
    discard <| command "/bin/cp" #["-c","-R",pageBuild.toString,runtimeBuild.toString]
    guarded "runtime-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"cursor-reader-runtime-settings.json").toString]
  | ["runtime-audit"] => do
    discard <| clean "runtime-build"
    metadata "runtime-audit" "runtime-audit-worker"
  | ["runtime-audit-worker"] => do
    let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,
      "inspect",runtimeBuild.toString,(runtimeRecords/"native.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,
      "compare-sources",(parent/"build").toString,runtimeBuild.toString,(runtimeRecords/"sources.json").toString,
      "tools.research.BindingPageScan","Eggshell.PublicationWire","+tools.research.CursorCodec",
      "+tools.research.CursorBinding","+tools.research.CursorPage"]
    let scanner ← scanSource (← IO.FS.readFile (parent/"source/tools/research/BindingPageScan.lean"))
    let protocol ← wireSource (← IO.FS.readFile (parent/"source/Eggshell/PublicationWire.lean"))
    for (name,path,expected) in [
        ("tools_research_BindingPageScan","tools/research/BindingPageScan.lean",scanner),
        ("Eggshell_PublicationWire","Eggshell/PublicationWire.lean",protocol)] do
      let (actual,_) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (runtimeBuild/(name++".source"))))
      check (actual == expected) "actual reader consumer differs from reviewed transform"
      let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0",(parent/"source"/path).toString,(runtimeSource/path).toString]}
      check (diff.exitCode == 1) "expected explicit reader patch"
      IO.FS.writeFile (runtimeRecords/(name++".patch")) diff.stdout
    for name in ["CursorCodec","CursorBinding","CursorPage"] do
      let (actual,_) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (runtimeBuild/("tools_research_"++name++".source"))))
      let expected ← if name == "CursorPage" then pageSource else IO.FS.readFile (project/"tools/research"/(name++".lean"))
      let actualHash ← hash (runtimeBuild/("tools_research_"++name++".o"))
      let expectedHash ← hash (pageBuild/("tools_research_"++name++".o"))
      check (actual == expected && actualHash == expectedHash) "runtime reader differs from proved native component"
    for name in ["Eggshell_DB_PageMap","Eggshell_SynapseIndex","tools_research_OwnedSelectionRuntime"] do
      let actual ← read (runtimeBuild/(name++".source"))
      let expected ← read (parent/"build"/(name++".source"))
      check (actual == expected) "source producer or harness changed"
    write (runtimeRecords/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (runtimeBuild/"StudyMain"))),
      ("parentSha256",toJson (← hash (parent/"build/StudyMain"))),("adopted",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("sourceProducerUnchanged",toJson true)])
  | ["page-audit"] => do
    discard <| clean "pages-ready"
    metadata "page-audit" "page-audit-worker"
  | ["page-audit-worker"] => do
    let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,
      "inspect",pageBuild.toString,(records/"page-native.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,
      "component-sources",(parent/"build").toString,pageBuild.toString,(records/"page-sources.json").toString,
      "Eggshell.DB.PageMap","Eggshell.SynapseIndex","tools.research.BindingValueCodec","Eggshell.DB.Wire","tools.research.CanonicalCodec"]
    let mut axioms := ""
    for name in ["CursorCodec","CursorBinding","CursorPage","CursorBindingChecks"] do
      let (actual,literals) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (pageBuild/("tools_research_"++name++".source"))))
      let expected ← if name == "CursorPage" then pageSource else IO.FS.readFile (project/"tools/research"/(name++".lean"))
      check (literals.isEmpty && actual == expected) "page native source mismatch"
      if name != "CursorBindingChecks" then
        axioms := axioms++(← IO.FS.readFile (pageBuild/("tools_research_"++name++"-lean.stdout")))
      if name == "CursorPage" then IO.FS.writeFile (records/"CursorPage.lean") actual
    check (!axioms.contains "sorryAx") "unclosed reader proof"
    IO.FS.writeFile (records/"reader-axioms.txt") axioms
    write (records/"page-runtime.json") (Json.mkObj [("sha256",toJson (← hash (pageBuild/"StudyMain"))),
      ("parentSha256",toJson (← hash (parent/"build/StudyMain"))),("productChanges",toJson (0 : Nat)),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["measure-pages"] => do
    discard <| clean "page-audit"
    check ((← read (records/"page-runtime.json")).getObjValD "sha256" == toJson (← hash (pageBuild/"StudyMain"))) "page component changed"
    let input ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
    guarded "measure-pages" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(parent/"data").toString,
      (pageBuild/"StudyMain").toString,database.toString,(records/"readers-component.json").toString]
  | ["collect-pages"] => do
    let monitor ← clean "measure-pages"
    let result ← read (records/"readers-component.json")
    check (result.getObjValD "allEqual" == toJson true && result.getObjValD "sourceUnchanged" == toJson true) "page comparison failed"
    let input ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
    let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
    for (name,digest) in files do check ((← hash (database/name)) == digest) "reader component changed original bytes"
    write (records/"readers-run.json") (Json.mkObj [("guard",monitor),("sourceFiles",toJson files),
      ("allOriginalFilesUnchanged",toJson true),("adopted",toJson false)])
  | ["page-setup"] => do
    idle
    discard <| clean "measure-bindings"
    check ((← read (records/"binding-run.json")).getObjValD "allOriginalFilesUnchanged" == toJson true) "collect binding-only stage"
    let mut sourceWitness := #[]
    for name in ["CursorCodec","CursorBinding","CursorBindingChecks"] do
      sourceWitness := sourceWitness.push (name,← read (bindingBuild/("tools_research_"++name++".source")))
    write (records/"binding-tested-source.json") (toJson sourceWitness)
    materialize (parent/"build") pageSourceRoot pageBuild "tools.research.CursorBindingChecks" "cursor-readers-settings.json"
    for name in ["CursorCodec","CursorBinding","CursorBindingChecks"] do
      IO.FS.writeFile (pageSourceRoot/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    IO.FS.writeFile (pageSourceRoot/"tools/research/CursorPage.lean") (← pageSource)
    copyLocalArtifacts (parent/"build") pageBuild
    guarded "pages-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"cursor-readers-settings.json").toString]
  | ["page-rebuild",label] => do
    idle
    for name in ["CursorCodec","CursorBinding","CursorBindingChecks"] do
      IO.FS.writeFile (pageSourceRoot/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    IO.FS.writeFile (pageSourceRoot/"tools/research/CursorPage.lean") (← pageSource)
    guarded label #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"cursor-readers-settings.json").toString]
  | ["binding-audit"] => do
    discard <| clean "binding-closed"
    metadata "binding-audit" "binding-audit-worker"
  | ["binding-audit-worker"] => do
    let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,
      "inspect",bindingBuild.toString,(records/"binding-native.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,
      "component-sources",(parent/"build").toString,bindingBuild.toString,(records/"binding-sources.json").toString,
      "Eggshell.SynapseIndex","tools.research.BindingValueCodec","Eggshell.DB.Wire","tools.research.CanonicalCodec"]
    for name in ["CursorCodec","CursorBinding","CursorBindingChecks"] do
      let (actual,literals) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (bindingBuild/("tools_research_"++name++".source"))))
      check (literals.isEmpty && actual == (← IO.FS.readFile (project/"tools/research"/(name++".lean")))) "binding native source mismatch"
    check ((← hash (bindingBuild/"tools_research_CursorCodec.o")) == (← hash (build/"tools_research_CursorCodec.o")))
      "binding component did not reuse proved cursor object"
    let axioms := (← IO.FS.readFile (records/"primitive-axioms.txt"))++
      (← IO.FS.readFile (bindingBuild/"tools_research_CursorBinding-lean.stdout"))
    check (!axioms.contains "sorryAx") "unclosed binding proof"
    IO.FS.writeFile (records/"binding-axioms.txt") axioms
    write (records/"binding-runtime.json") (Json.mkObj [("sha256",toJson (← hash (bindingBuild/"StudyMain"))),
      ("parentSha256",toJson (← hash (parent/"build/StudyMain"))),("productChanges",toJson (0 : Nat)),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["measure-bindings"] => do
    discard <| clean "binding-audit"
    check ((← read (records/"binding-runtime.json")).getObjValD "sha256" == toJson (← hash (bindingBuild/"StudyMain"))) "binding component changed"
    let input ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
    let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
    for (name,digest) in files do check ((← hash (database/name)) == digest) "original source changed before decoder comparison"
    guarded "measure-bindings" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(parent/"data").toString,
      (bindingBuild/"StudyMain").toString,database.toString,(records/"binding-component.json").toString]
  | ["collect-bindings"] => do
    let monitor ← clean "measure-bindings"
    let result ← read (records/"binding-component.json")
    check (result.getObjValD "allEqual" == toJson true && result.getObjValD "sourceUnchanged" == toJson true) "binding comparison failed"
    let input ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
    let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
    for (name,digest) in files do check ((← hash (database/name)) == digest) "decoder component changed original source bytes"
    write (records/"binding-run.json") (Json.mkObj [("guard",monitor),("sourceFiles",toJson files),
      ("allOriginalFilesUnchanged",toJson true),("adopted",toJson false)])
  | ["binding-setup"] => do
    discard <| clean "controls"
    materialize (parent/"build") bindingSource bindingBuild "tools.research.CursorBindingChecks" "cursor-binding-settings.json"
    for name in ["CursorCodec","CursorBinding","CursorBindingChecks"] do
      IO.FS.writeFile (bindingSource/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    copyLocalArtifacts build bindingBuild
    guarded "binding-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"cursor-binding-settings.json").toString]
  | ["binding-rebuild",label] => do
    idle
    for name in ["CursorCodec","CursorBinding","CursorBindingChecks"] do
      IO.FS.writeFile (bindingSource/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    guarded label #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"cursor-binding-settings.json").toString]
  | ["audit-primitives"] => do
    discard <| clean "payload"
    metadata "audit-primitives" "audit-primitives-worker"
  | ["audit-primitives-worker"] => do
    let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,
      "inspect",build.toString,(records/"primitive-native.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,
      "component-sources",(parent/"build").toString,build.toString,(records/"primitive-sources.json").toString,
      "Eggshell.DB.Wire","tools.research.CanonicalCodec"]
    for name in ["CursorCodec","CursorCodecChecks"] do
      let (actual,literals) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (build/("tools_research_"++name++".source"))))
      check (literals.isEmpty && actual == (← IO.FS.readFile (project/"tools/research"/(name++".lean")))) "primitive native source mismatch"
    let axioms ← IO.FS.readFile (build/"tools_research_CursorCodec-lean.stdout")
    check (!axioms.contains "sorryAx") "unclosed cursor proof"
    IO.FS.writeFile (records/"primitive-axioms.txt") axioms
    write (records/"primitive-runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
      ("productChanges",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
  | ["controls"] => do
    discard <| clean "audit-primitives"
    check ((← read (records/"primitive-runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "primitive runtime changed"
    guarded "controls" #[(build/"StudyMain").toString,(records/"primitive-controls.json").toString]
  | ["setup"] => do
    idle
    check (!(← root.pathExists) && !(← records.pathExists)) "fresh cursor experiment required"
    check ((← hash (parent/"build/StudyMain")) == "7cc1432d2d3931a26d60e3e614807545e3f6b522737838bdabc1b1c626e657ab") "current parent changed"
    IO.FS.createDirAll records
    materialize (parent/"build") source build "tools.research.CursorCodecChecks" "cursor-codec-settings.json"
    for name in ["CursorCodec","CursorCodecChecks"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    guarded "build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"cursor-codec-settings.json").toString]
  | ["rebuild",label] => do
    idle
    for name in ["CursorCodec","CursorCodecChecks"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    guarded label #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"cursor-codec-settings.json").toString]
  | _ => throw (IO.userError "cursor-codec-study setup|rebuild LABEL")
end CursorCodecStudy
def main := CursorCodecStudy.main
