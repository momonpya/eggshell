import tools.research.StudyLocal
open Lean StudyLocal
namespace CanonicalCodecStudy
def root := base/"canonical-codec"
def records := project/"docs/candidates/canonical-codec"
def source := root/"source"
def build := root/"build"
def runtimeRoot := base/"canonical-decoder-runtime"
def runtimeSource := runtimeRoot/"source"
def runtimeBuild := runtimeRoot/"build"
def runtimeRecords := records/"runtime"
def runtimePrefix := runtimeRoot/"prefix"
def runtimeData := runtimeRoot/"data"
def parentBuild := base/"register-rounds-runtime/build"
def parentPrefix := base/"register-rounds-runtime/prefix"
def parentData := base/"snapshot-scheduling/work/data"
def order : Array String := #["a-first","b-first","b-second","a-second"]

def clean (name : String) : IO Json := do
  let monitor ← finished name
  check (monitor.getObjValD "guardTriggered" == toJson false && monitor.getObjValD "reason" == Json.null) "supervisor did not finish normally"
  return monitor

def hexadecimal (text : String) : Option Nat :=
  text.toList.foldlM (fun n c => do
    let digit ← if '0' ≤ c && c ≤ '9' then some (c.toNat-'0'.toNat)
      else if 'a' ≤ c && c ≤ 'f' then some (c.toNat-'a'.toNat+10) else none
    return n*16+digit) 0

def nativeCalls : IO Unit := do
  idle
  discard <| clean "canonical-decoder-runtime-audit"
  check (!(← (runtimeRecords/"native-calls.json").pathExists)) "preserve native call evidence"
  let columns := fun (line : String) => (line.replace "\t" " ").splitOn " " |>.filter (!·.isEmpty)
  let mut reports := #[]
  for (name,hot,old,fresh) in [
      ("Eggshell_DB_PageMap","Eggshell_DB_PageMap_Snapshot_load","_l_Eggshell_DB_PageMap_decode","_l_Eggshell_DB_Wire_Codec_payload___redArg"),
      ("tools_research_BindingPageScan","Eggshell_Synapses_BindingPageScan_scanAt","_l_Eggshell_Synapses_Index_decodeBinding","_l_Eggshell_Synapses_Index_CanonicalDecoder_decodeWithoutEncode")] do
    let object := runtimeBuild/(name++".o")
    let symbols := ((← command "/usr/bin/nm" #["-n",object.toString]).splitOn "\n").filterMap (fun row => do
      let fields := columns row
      if fields[1]? != some "T" && fields[1]? != some "t" then none else do
        return (← hexadecimal (← fields[0]?),← fields[2]?)) |>.toArray
    let mut calls := #[]
    for row in (← command "/usr/bin/otool" #["-rv",object.toString]).splitOn "\n" do
      let fields := columns row
      let some target := fields.getLast? | continue
      if !fields.contains "BR26" || ![old,fresh].contains target then continue
      let some address := fields[0]?.bind hexadecimal | throw (IO.userError "native branch has no address")
      let caller := (symbols.toList.takeWhile (·.1 ≤ address)).getLast?.map Prod.snd
      let some caller := caller | throw (IO.userError "native branch owner missing")
      check (!(caller.contains hot && target == old)) "actual reader still calls the re-encoding decoder"
      calls := calls.push (caller,target,address)
    check (calls.any (fun (caller,target,_) => caller.contains hot && target == fresh)) "actual reader lacks the new decoder call"
    reports := reports.push (Json.mkObj [("module",toJson name),("objectSha256",toJson (← hash object)),("calls",toJson calls)])
  write (runtimeRecords/"native-calls.json") (Json.mkObj [("actualReadConsumersUseNewDecoder",toJson true),
    ("pagePayloadInlinedIntoSnapshotLoad",toJson true),("reports",toJson reports),
    ("notAFullCCompilerProof",toJson true),("runtimeSha256",toJson (← hash (runtimeBuild/"StudyMain")))])

def checkedReplace (text before after : String) : IO String := do
  check ((text.splitOn before).length == 2) "checked consumer boundary changed"
  return text.replace before after

def pageSource (original : String) : IO String := do
  let library ← IO.FS.readFile (project/"tools/research/CanonicalPageCodec.lean")
  let body := ((library.splitOn "namespace Eggshell.DB.PageMap\n")[1]!.splitOn "end Eggshell.DB.PageMap")[0]!
  let original ← checkedReplace original "public import Eggshell.DB.Wire\n"
    "public import Eggshell.DB.Wire\npublic import tools.research.CanonicalCodec\n"
  let binding := "\nnamespace CanonicalDecoder\n"++body++
    "\n@[csimp] theorem decode_compiled : @decode = @decodeWithoutEncode := by\n  funext bytes\n  exact (decode_without_encode_exact bytes).symm\nend CanonicalDecoder\n\n"
  checkedReplace original "theorem page_codec_roundtrip" (binding++"theorem page_codec_roundtrip")

def indexSource (original : String) : IO String := do
  let library ← IO.FS.readFile (project/"tools/research/CanonicalBindingDecode.lean")
  let body := ((library.splitOn "namespace Eggshell.Synapses.Index\n")[1]!.splitOn "end Eggshell.Synapses.Index")[0]!
  let original ← checkedReplace original "public import tools.research.BindingValueCodec\n"
    "public import tools.research.BindingValueCodec\npublic import tools.research.CanonicalBindings\nimport all Init.System.IO\nimport all Init.System.ST\n"
  let binding := "\nnamespace CanonicalDecoder\n"++body++
    "\n@[csimp] theorem decode_compiled : @decodeBinding = @decodeWithoutEncode := by\n  funext bytes\n  exact (decode_without_encode_exact bytes).symm\nend CanonicalDecoder\n\n"
  checkedReplace original "def prepareBinding (writer" (binding++"def prepareBinding (writer")

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
  check (!(actual.toString.startsWith (root.toString++"/"))) "active compiler input depends on the completed component"
  if (← path.symlinkMetadata).type == .dir then
    let mut count := 0
    for entry in ← path.readDir do count := count+(← retainedLinks entry.path)
    return count
  return 1

def retire : IO Unit := do
  idle
  check (!(← (records/"retired.json").pathExists)) "preserve completed retirement evidence"
  check ((← read (runtimeRecords/"comparison.json")).getObjValD "adopted" == toJson false) "collect comparison first"
  for label in #["preflight"]++order do
    discard <| clean ("canonical-decoder-"++label)
    let metadata ← read (runtimeRecords/(label++"-metadata.json"))
    let clients : Array Json ← IO.ofExcept (metadata.getObjValAs? (Array Json) "clients")
    check (clients.all (fun row => (row.getObjValD "client").getObjValD "acknowledged" == toJson true)) "unacknowledged owned client"
    let warm := runtimeRoot/label/"warm/stdout"
    check ((← hash warm) == (← IO.ofExcept ((metadata.getObjValD "warm").getObjValAs? String "stdoutSha256"))) "warm receipt changed"
    write (runtimeRecords/(label++"-warm.json")) (← read warm)
  for dataRoot in #[parentData,runtimeData] do
    for file in #[dataRoot/"publisher/endpoint.json",dataRoot/"publisher/operations.json",dataRoot/"daemon.json"] do
      check (!(← file.pathExists)) "service endpoint still needs recovery"
  let kept := #[parentBuild/"StudyMain",runtimeBuild/"StudyMain",base/"current-six/stable-source-rows/build/StudyMain",
    base/"current-six/fixed-sequence/controller-build/StudyMain",base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",
    base/"byte-pages-prefix/libexec/eggshell",base/"snapshot-scheduling/work/work.egg/head"] ++
      (#[1,2,3].map fun n => base/"snapshot-scheduling/diagnostic"/("topic-"++toString n)/"body.txt")
  let hashes ← kept.mapM hash
  let input := (← read (runtimeRecords/"preflight.json")).getObjValD "input"
  let origin : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let originals : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (name,digest) in originals do check ((← hash (origin/name)) == digest) "protected original changed"
  let response ← IO.FS.readFile (runtimeBuild/"runtime.rsp")
  check (!response.contains (root.toString++"/")) "active native response references the completed component"
  let mut checked := 0
  for directory in #[runtimeBuild/"lib",parentBuild/"lib",base/"current-six/stable-source-rows/build/lib",
      base/"current-six/fixed-sequence/preparation-closure-build/lib",base/"study-local-lib"] do
    if ← directory.pathExists then checked := checked+(← retainedLinks directory)
  let mut monitors := #[]
  let mut guardFiles := #[]
  for file in ← base.readDir do
    if !file.fileName.endsWith ".guard.json" ||
        !(file.fileName.startsWith "canonical-codec-" || file.fileName.startsWith "canonical-decoder-") then continue
    let monitor ← read file.path
    check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "uncompleted study stage"
    monitors := monitors.push (file.fileName,monitor)
    guardFiles := guardFiles.push file.path
    let settings := base/(file.fileName.replace ".guard.json" ".guard-settings.json")
    if ← settings.pathExists then guardFiles := guardFiles.push settings
  write (records/"resources.json") (toJson monitors)
  write (records/"component-build.json") (← read (build/"build.json"))
  let mut deleted := #[]
  let targets := #[root] ++ (#["preflight"]++order).map (fun (label : String) => runtimeRoot/label) ++
    #[parentData,runtimeData].flatMap (fun dataRoot => #[dataRoot/"sessions",dataRoot/"confirmed-delivery",dataRoot/"receipts"]) ++
    guardFiles ++ #[base/"canonical-codec-settings.json"]
  for path in targets do
    check (← path.pathExists) "owned retirement target disappeared"
    let count ← removeOwned path
    deleted := deleted.push (path.toString,count.1,count.2)
  -- These copied prototype modules are absent from the runtime response and
  -- are not dependencies of any actual linked module.
  for name in ["CanonicalPageCodec","CanonicalBindingDecode","CanonicalCodecBench"] do
    let stem := "tools_research_"++name
    check (!response.contains (runtimeBuild/(stem++".o")).toString) "prototype remains linked"
    for line in response.splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      if !(← path.withExtension "dependencies" |>.pathExists) then continue
      let deps : Array (String × String) ← IO.ofExcept (fromJson? (← read (path.withExtension "dependencies")))
      check (!(deps.any (·.1 == "tools.research."++name))) "prototype is an active transitive input"
    let folder := runtimeBuild/"lib/tools/research"
    for file in ← runtimeBuild.readDir do
      if file.fileName.startsWith (stem++".") || file.fileName.startsWith (stem++"-") then
        let count ← removeOwned file.path
        deleted := deleted.push (file.path.toString,count.1,count.2)
    for file in ← folder.readDir do
      if file.fileName.startsWith (name++".") then
        let count ← removeOwned file.path
        deleted := deleted.push (file.path.toString,count.1,count.2)
  check ((← kept.mapM hash) == hashes) "protected runtime, original head or canonical body changed"
  for (name,digest) in originals do check ((← hash (origin/name)) == digest) "original source changed during cleanup"
  write (records/"retired.json") (Json.mkObj [("deleted",toJson deleted),("protectedInputs",toJson (kept.zip hashes)),
    ("protectedOriginals",toJson originals),("protectedHashesUnchanged",toJson true),("activeCompilerInputsChecked",toJson checked),
    ("currentCandidateSourceBuildCacheAndModelRetained",toJson true),("parentReadCacheRetained",toJson true),
    ("archiveCreated",toJson false)])
def main (args : List String) : IO Unit := do
  match args with
  | ["refresh-patches"] => do
    idle
    check ((← read (runtimeRecords/"sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "source comparison missing"
    for (name,generate) in [("Eggshell/DB/PageMap",pageSource),("Eggshell/SynapseIndex",indexSource)] do
      let original := parentBuild.parent.get!/"source"/(name++".lean")
      let candidate := runtimeSource/(name++".lean")
      check ((← IO.FS.readFile candidate) == (← generate (← IO.FS.readFile original))) "consumer source changed"
      let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0",original.toString,candidate.toString]}
      check (patch.exitCode == 1) "expected decoder source patch"
      IO.FS.writeFile (runtimeRecords/(name.replace "/" "_"++".patch")) patch.stdout
  | ["finish"] => do
    idle
    let monitor ← clean "canonical-decoder-post-retirement"
    check ((← read (runtimeRecords/"native-after-retirement.json")).getObjValD "consistent" == toJson true) "retained native closure is incomplete"
    check (!(← (runtimeRecords/"post-retirement-guard.json").pathExists)) "preserve final resource record"
    write (runtimeRecords/"post-retirement-guard.json") monitor
    for name in ["canonical-decoder-post-retirement.guard.json","canonical-decoder-post-retirement.guard-settings.json"] do
      IO.FS.removeFile (base/name)
  | ["post-retirement-audit"] => do
    check ((← read (records/"retired.json")).getObjValD "protectedHashesUnchanged" == toJson true) "retire ended trials first"
    guard "canonical-decoder-post-retirement" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",runtimeBuild.toString,
      (runtimeRecords/"native-after-retirement.json").toString]
  | ["retire"] => retire
  | ["capture",label] => do
    discard <| clean ("canonical-decoder-"++label)
    let path := runtimeRecords/(label++"-metadata.json")
    check (!(← path.pathExists)) "collect receipts once before retiring them"
    let result ← read (runtimeRecords/(label++".json"))
    let input := result.getObjValD "input"
    let output := runtimeRoot/label
    let dataRoot : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
    let primes : Array Json ← IO.ofExcept (fromJson? (← read (output/"prime.json")))
    check (primes.size == 3 && primes.all (fun row => row.getObjValD "success" == toJson true &&
      row.getObjValD "bodyByteEqual" == toJson true && row.getObjValD "acknowledged" == toJson true)) "all three primes and ACK required"
    let phases : Array Json ← IO.ofExcept ((result.getObjValD "report").getObjValAs? (Array Json) "phases")
    let mut clients := primes
    for phase in phases do clients := clients++(← IO.ofExcept (phase.getObjValAs? (Array Json) "rows"))
    let mut requests := #[]
    for client in clients do
      let id ← IO.ofExcept (client.getObjValAs? String "receipt")
      let directory := dataRoot/"receipts"/id
      let mut fields := [("client",client)]
      for name in ["request-pages","operation-service"] do
        let file := directory/(name++".json")
        if ← file.pathExists then fields := fields++[(name,← read file)]
      requests := requests.push (Json.mkObj fields)
    let mut fields := [("clients",toJson requests),("warm",← read (output/"warm/record.json"))]
    for name in ["cache-stats-prime","cache-stats-phase-4","cache-stats-phase-16","frontend-shutdown","publisher-shutdown"] do
      let file := output/(name++".json")
      if ← file.pathExists then fields := fields++[(name,← read file)]
    write path (Json.mkObj fields)
  | ["compare"] => do
    idle
    check (!(← (runtimeRecords/"comparison.json").pathExists)) "preserve completed comparison"
    let invariant := fun (input : Json) => Json.mkObj (["project","sourceFiles","workspace","topics","handoffChars","counts","diagnostic"].map
      fun key => (key,input.getObjValD key))
    let fixedEnv := fun (rows : Array (String × Option String)) => rows.filter fun row =>
      !["EGGSHELL_PREFIX","PLUGIN_ROOT","EGGSHELL_CONFIG","EGGSHELL_DATA_ROOT"].contains row.1
    let original := (← read (runtimeRecords/"a-first.json")).getObjValD "input"
    let originalEnv : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
    let mut arms := #[]
    let mut before := #[]
    let mut after := #[]
    for label in order do
      discard <| clean ("canonical-decoder-"++label)
      let result ← read (runtimeRecords/(label++".json"))
      let input := result.getObjValD "input"
      let env : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
      check (invariant input == invariant original && fixedEnv env == fixedEnv originalEnv) "matched snapshot, queries or fixed environment changed"
      let candidate := label.startsWith "b"
      check (input.getObjValD "data" == toJson (if candidate then runtimeData else parentData).toString) "producer cache separation changed"
      check (result.getObjValD "passed" == toJson true) "all arms must pass"
      let phases : Array Json ← IO.ofExcept ((result.getObjValD "report").getObjValAs? (Array Json) "phases")
      let some small := phases.find? (fun row => row.getObjValD "clients" == toJson (4 : Nat)) | throw (IO.userError "four-client wave missing")
      let some wave := phases.find? (fun row => row.getObjValD "clients" == toJson (16 : Nat)) | throw (IO.userError "sixteen-client wave missing")
      let elapsed ← IO.ofExcept (wave.getObjValAs? Nat "wallMs")
      if candidate then after := after.push elapsed else before := before.push elapsed
      arms := arms.push (Json.mkObj [("arm",toJson label),("wall4",small.getObjValD "wallMs"),("wall16",toJson elapsed),
        ("peakRssKiB",(result.getObjValD "guard").getObjValD "sampledPeakRssKiB")])
    let mean := fun (rows : Array Nat) => (rows.foldl (·+·) 0).toFloat/rows.size.toFloat
    write (runtimeRecords/"comparison.json") (Json.mkObj [("order",toJson order),("arms",toJson arms),
      ("parentMean16Ms",toJson (mean before)),("candidateMean16Ms",toJson (mean after)),
      ("descriptiveImprovementPercent",toJson (100*(mean before-mean after)/mean before)),
      ("sameSourceSnapshotQuestionsEnvelope",toJson true),("isolatedCompleteProducerCaches",toJson true),
      ("statisticalOrP99Claim",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["native-calls"] => nativeCalls
  | ["runtime-audit"] => do
    discard <| clean "canonical-decoder-runtime-build"
    guard "canonical-decoder-runtime-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/CanonicalCodecStudy.lean").toString,"runtime-audit-worker"]
  | ["runtime-audit-worker"] => do
    let inspector := (project/"tools/research/StudyBuildClosureAudit.lean").toString
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector,"inspect",runtimeBuild.toString,(runtimeRecords/"native.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector,"compare-sources",parentBuild.toString,
      runtimeBuild.toString,(runtimeRecords/"sources.json").toString,"Eggshell.DB.PageMap","Eggshell.SynapseIndex",
      "+tools.research.CanonicalCodec","+tools.research.CanonicalBindings"]
    check ((← read (parentBuild/"tools_research_OwnedSelectionRuntime.source")) ==
      (← read (runtimeBuild/"tools_research_OwnedSelectionRuntime.source"))) "native workload entry changed"
    let mut axioms := ""
    for (name,generate) in [("Eggshell/DB/PageMap",pageSource),("Eggshell/SynapseIndex",indexSource)] do
      let (text,_) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (runtimeBuild/(name.replace "/" "_"++".source"))))
      check (text == (← generate (← IO.FS.readFile (parentBuild.parent.get!/"source"/(name++".lean"))))) "actual decoder connection differs from the proved transformation"
      axioms := axioms++(← IO.FS.readFile (runtimeBuild/(name.replace "/" "_"++"-lean.stdout")))
      let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0",
        (parentBuild.parent.get!/"source"/(name++".lean")).toString,(runtimeSource/(name++".lean")).toString]}
      check (diff.exitCode == 1) "expected one explicit decoder connection patch"
      IO.FS.writeFile (runtimeRecords/(name.replace "/" "_"++".patch")) diff.stdout
    check (!axioms.contains "sorryAx") "actual consumer proof is unclosed"
    IO.FS.writeFile (runtimeRecords/"axioms.txt") axioms
    write (runtimeRecords/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (runtimeBuild/"StudyMain"))),
      ("parentSha256",toJson (← hash (parentBuild/"StudyMain"))),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["install"] => do
    discard <| clean "canonical-decoder-runtime-audit"
    check ((← read (runtimeRecords/"native-calls.json")).getObjValD "actualReadConsumersUseNewDecoder" == toJson true) "native consumer call audit missing"
    guard "canonical-decoder-install" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/CanonicalCodecStudy.lean").toString,"install-worker"]
  | ["install-worker"] => do
    check (!(← runtimePrefix.pathExists) && !(← runtimeData.pathExists)) "fresh isolated installation and cache fork required"
    let before ← hash (base/"snapshot-scheduling/work/work.egg/head")
    let plugin := runtimePrefix/"share/eggshell/codex-plugin"
    IO.FS.createDirAll (runtimePrefix/"libexec")
    IO.FS.createDirAll (plugin/"bin")
    discard <| command "/bin/ln" #["-s",(runtimeBuild/"StudyMain").toString,(runtimePrefix/"libexec/eggshell").toString]
    discard <| command "/bin/ln" #["-s",(parentPrefix/"share/eggshell/minilm").toString,(runtimePrefix/"share/eggshell/minilm").toString]
    for name in ["egg","eggshelld"] do
      let original ← IO.FS.readFile (parentPrefix/"share/eggshell/codex-plugin/bin"/name)
      check (original.contains parentPrefix.toString) "launcher boundary changed"
      IO.FS.writeFile (plugin/"bin"/name) (original.replace parentPrefix.toString runtimePrefix.toString)
      discard <| command "/bin/chmod" #["755",(plugin/"bin"/name).toString]
    IO.FS.createDirAll runtimeData
    -- APFS clone creates distinct mutable files. Candidate producer identities
    -- must never rebuild the parent's prepared project in place.
    discard <| command "/bin/cp" #["-c","-R",(parentData/"read-cache").toString,(runtimeData/"read-cache").toString]
    check ((← IO.FS.realPath (runtimeData/"read-cache")) != (← IO.FS.realPath (parentData/"read-cache"))) "cache fork aliases the parent"
    check ((← hash (base/"snapshot-scheduling/work/work.egg/head")) == before) "source head changed during installation"
    write (runtimeRecords/"installation.json") (Json.mkObj [("parentData",toJson parentData.toString),("candidateData",toJson runtimeData.toString),
      ("isolatedPreparedCache",toJson true),("sameOriginalProject",toJson true),("newSeedOrModelCalls",toJson false),
      ("comparisonOrder",toJson order),("countsPerArm",toJson (#[(4 : Nat),16])),("adopted",toJson false)])
  | ["prepare",label] => do
    discard <| clean "canonical-decoder-install"
    let preflight := label == "preflight"
    if !preflight then
      let some position := order.findIdx? (· == label) | throw (IO.userError "undeclared comparison arm")
      let prior := if position == 0 then "preflight" else order[position-1]!
      discard <| clean ("canonical-decoder-"++prior)
      check ((← read (runtimeRecords/(prior++".json"))).getObjValD "passed" == toJson true) "previous collected arm failed"
    let candidate := preflight || label.startsWith "b"
    let chosen := if candidate then runtimePrefix else parentPrefix
    let dataRoot := if candidate then runtimeData else parentData
    let executable := chosen/"libexec/eggshell"
    let digest := (← read (runtimeRecords/"runtime.json")).getObjValD (if candidate then "sha256" else "parentSha256")
    check (digest == toJson (← hash executable)) "audited runtime changed"
    let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let output := runtimeRoot/label
    let config := output/"config.toml"
    let plugin := chosen/"share/eggshell/codex-plugin"
    let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
    let environment := (environment.filter (·.1 != "EGGSHELL_HANDOFF_TRACE")).map (fun (key,value) => (key,match key with
      | "EGGSHELL_PREFIX" => some chosen.toString | "PLUGIN_ROOT" => some plugin.toString
      | "EGGSHELL_DATA_ROOT" => some dataRoot.toString | "EGGSHELL_CONFIG" => some config.toString | _ => value)) ++ #[ ("EGGSHELL_HANDOFF_TRACE",none) ]
    let input := original.setObjVal! "output" (toJson output.toString) |>.setObjVal! "config" (toJson config.toString)
      |>.setObjVal! "environment" (toJson environment) |>.setObjVal! "runtime" (toJson executable.toString)
      |>.setObjVal! "runtimeSha256" digest |>.setObjVal! "plugin" (toJson plugin.toString) |>.setObjVal! "data" (toJson dataRoot.toString)
    let input := if preflight then input.setObjVal! "counts" (toJson (#[(4 : Nat)])) |>.setObjVal! "diagnostic" (toJson true) else input
    let path := runtimeRoot/(label++"-input.json")
    check (!(← path.pathExists)) "preserve prior arm"
    write path input
    let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
    guard ("canonical-decoder-"++label) (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++
      #[executable.toString,"owned-selection-capacity",path.toString])
  | ["collect",label] => do
    let monitor ← clean ("canonical-decoder-"++label)
    let report ← read (runtimeRoot/label/"report.json")
    let input ← read (runtimeRoot/(label++"-input.json"))
    let origin : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
    let sources : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
    for (file,digest) in sources do check ((← hash (origin/file)) == digest) "original publication changed"
    check (report.getObjValD "allPhasesPassed" == toJson true || (label == "preflight" &&
      (← read (runtimeRoot/label/"phase-4/result.json")).getObjValD "passed" == toJson true)) "native workload failed"
    write (runtimeRecords/(label++".json")) (Json.mkObj [("input",input),("guard",monitor),("report",report),("passed",toJson true),
      ("sourceFilesUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["runtime-setup"] => do
    idle
    let monitor ← finished "canonical-codec-native"
    check (monitor.getObjValD "guardTriggered" == toJson false && monitor.getObjValD "reason" == Json.null) "native component did not finish normally"
    let component ← read (records/"component.json")
    check (component.getObjValD "controls" == toJson (1234 : Nat)) "real input/error controls missing"
    IO.FS.createDirAll runtimeRecords
    materialize (base/"register-rounds-runtime/build") runtimeSource runtimeBuild "tools.research.OwnedSelectionRuntime" "canonical-decoder-runtime-settings.json"
    for name in ["CanonicalCodec","CanonicalBindings"] do
      IO.FS.writeFile (runtimeSource/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    let originalPage ← IO.FS.readFile (runtimeSource/"Eggshell/DB/PageMap.lean")
    let originalIndex ← IO.FS.readFile (runtimeSource/"Eggshell/SynapseIndex.lean")
    IO.FS.writeFile (runtimeSource/"Eggshell/DB/PageMap.lean") (← pageSource originalPage)
    IO.FS.writeFile (runtimeSource/"Eggshell/SynapseIndex.lean") (← indexSource originalIndex)
    copyLocalArtifacts build runtimeBuild
    write (runtimeRecords/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (base/"register-rounds-runtime/build/StudyMain"))),
      ("component",component),("directProductChanges",toJson #["Eggshell.DB.PageMap","Eggshell.SynapseIndex"]),
      ("added",toJson #["tools.research.CanonicalCodec","tools.research.CanonicalBindings"]),
      ("preservesErrorsAndAllInputBytes",toJson true),("manualVersionOrDataFormatChange",toJson false),
      ("modelRankAuthorityPoolChanges",toJson false),("requiresActualHookAndCapacityValidation",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guard "canonical-decoder-runtime-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"canonical-decoder-runtime-settings.json").toString]
  | ["native-audit"] => do
    discard <| finished "canonical-codec-bench-build"
    guard "canonical-codec-native-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/CanonicalCodecStudy.lean").toString,"native-audit-worker"]
  | ["native-audit-worker"] => do
    let inspector := (project/"tools/research/StudyBuildClosureAudit.lean").toString
    for (target,name) in [(base/"register-rounds-runtime/build","parent-native.json"),(build,"component-native.json")] do
      discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector,"inspect",target.toString,(records/name).toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector,"component-sources",
      (base/"register-rounds-runtime/build").toString,build.toString,(records/"common-source.json").toString,
      "Eggshell.DB.Wire","Eggshell.DB.PageMap","Eggshell.SynapseIndex","tools.research.BindingValueCodec"]
    let mut sources := #[]
    for name in ["CanonicalCodec","CanonicalBindings","CanonicalPageCodec","CanonicalBindingDecode","CanonicalCodecBench"] do
      let (text,literals) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (build/("tools_research_"++name++".source"))))
      check (literals.isEmpty && text == (← IO.FS.readFile (project/"tools/research"/(name++".lean")))) "component source differs from the checked proposal"
      sources := sources.push (name,← hash (project/"tools/research"/(name++".lean")))
    let mut axioms := ""
    for name in ["CanonicalCodec","CanonicalBindings","CanonicalPageCodec","CanonicalBindingDecode"] do
      axioms := axioms++(← IO.FS.readFile (build/("tools_research_"++name++"-lean.stdout")))
    check (!axioms.contains "sorryAx" && !axioms.isEmpty) "successful native proof compilation must have no sorry"
    IO.FS.writeFile (records/"axioms.txt") axioms
    write (records/"native-validation.json") (Json.mkObj [("runtimeSha256",toJson (← hash (build/"StudyMain"))),
      ("checkedSources",toJson sources),("newProductBuild",toJson false),("productSourceChanges",toJson (0 : Nat)),
      ("componentOnly",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["measure"] => do
    let audit ← finished "canonical-codec-native-audit"
    check (audit.getObjValD "guardTriggered" == toJson false && audit.getObjValD "reason" == Json.null) "native audit failed"
    let validation ← read (records/"native-validation.json")
    check (validation.getObjValD "runtimeSha256" == toJson (← hash (build/"StudyMain"))) "audited native component changed"
    guard "canonical-codec-native" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(base/"snapshot-scheduling/work/data").toString,
      (build/"StudyMain").toString,(base/"snapshot-scheduling/work/work.egg").toString,(records/"component.json").toString]
  | ["native-setup"] => do
    idle
    discard <| finished "canonical-codec-complete-bytes"
    materialize (base/"register-rounds-runtime/build") source build "tools.research.CanonicalCodecBench" "canonical-codec-settings.json"
    for name in ["CanonicalCodec","CanonicalBindings","CanonicalPageCodec","CanonicalBindingDecode"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    guard "canonical-codec-native-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"canonical-codec-settings.json").toString]
  | ["native-build",label] => do
    idle
    for name in ["CanonicalCodec","CanonicalBindings","CanonicalPageCodec","CanonicalBindingDecode","CanonicalCodecBench"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
    guard ("canonical-codec-"++label) #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"canonical-codec-settings.json").toString]
  | ["setup"] => do
    idle
    check (!(← root.pathExists)) "fresh isolated proof required"
    check (!(← (records/"plan.json").pathExists)) "completed study records are immutable"
    IO.FS.createDirAll root
    IO.FS.createDirAll records
    write (records/"plan.json") (Json.mkObj [("previousTurn",toJson "progress:post-ready stage and native stack evidence"),
      ("parentSha256",toJson (← hash (base/"register-rounds-runtime/build/StudyMain"))),
      ("hypothesis",toJson "prove successful actual wire decoding is canonical before removing redundant re-encoding"),
      ("rankAuthorityCachePoolChanges",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guard "canonical-codec-proof" #["/usr/bin/env","LEAN_PATH="++(base/"register-rounds-runtime/build/lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","-DwarningAsError=true",
      "-o",(root/"CanonicalCodec.olean").toString,(project/"tools/research/CanonicalCodec.lean").toString]
  | ["proof",label] => do
    check (← root.pathExists) "retired proof cannot be resumed"
    check (!(← (records/(label++".txt")).pathExists)) "preserve collected proof output"
    guard ("canonical-codec-"++label) #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/CanonicalCodecStudy.lean").toString,"proof-worker",label]
  | ["proof-worker",label] => do
    let result ← IO.Process.output {
      cmd := (compiler/"bin/lean").toString
      args := #["-j1","-M1536","-DwarningAsError=true","-o",(root/"CanonicalCodec.olean").toString,
        (project/"tools/research/CanonicalCodec.lean").toString]
      env := #[("LEAN_PATH",some (base/"register-rounds-runtime/build/lib").toString)]}
    IO.FS.writeFile (records/(label++".txt")) (result.stdout++result.stderr)
    check (result.exitCode == 0) (result.stdout++result.stderr)
  | _ => throw (IO.userError "setup")
end CanonicalCodecStudy
def main := CanonicalCodecStudy.main
