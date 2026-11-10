import tools.research.StudyLocal
open Lean StudyLocal
namespace OwnerReachStudy
def parentBuild := base/"register-rounds-runtime/build"
def parentPrefix := base/"register-rounds-runtime/prefix"
def root := base/"owner-reach-runtime"
def source := root/"source"
def build := root/"build"
def installation := root/"prefix"
def records := project/"docs/candidates/owned-buckets/runtime"
def order : Array String := #["a-first","b-first","b-second","a-second"]
def clean (tag : String) : IO Json := do
  let monitor ← finished tag
  check (monitor.getObjValD "reason" == Json.null && monitor.getObjValD "guardTriggered" == toJson false)
    "guard did not finish normally"
  return monitor
def cleanBuild : IO Json := do
  let path := records/"current-build.json"
  let tag ← if ← path.pathExists then IO.ofExcept ((← read path).getStr?) else pure "owner-reach-runtime-build"
  clean tag
partial def removeOwned (path : System.FilePath) : IO (Nat × Nat) := do
  let stat ← path.symlinkMetadata
  if stat.type == .dir then
    let mut total := (0,0)
    for entry in ← path.readDir do
      let deleted ← removeOwned entry.path
      total := (total.1+deleted.1,total.2+deleted.2)
    IO.FS.removeDir path
    return total
  IO.FS.removeFile path
  return (1,if stat.type == .file then stat.byteSize.toNat else 0)
partial def retainedLinks (path : System.FilePath) (retired : Array System.FilePath) : IO Nat := do
  let actual ← IO.FS.realPath path
  check (!(retired.any fun old => actual.toString.startsWith (old.toString++"/"))) "active input points into retired source"
  if (← path.symlinkMetadata).type == .dir then
    let mut total := 0
    for entry in ← path.readDir do total := total+(← retainedLinks entry.path retired)
    return total
  return 1
def replaceCount (text before after : String) (expected : Nat) : IO String := do
  check ((text.splitOn before).length == expected+1) ("unexpected binding count: "++before)
  return text.replace before after
def boundSource (original : String) : IO String := do
  let proof ← IO.FS.readFile (project/"tools/research/OwnerReachConnection.lean")
  let start := "namespace Eggshell.Plugin.SharedRangeAdapter.ReachBuilder\n"
  let stop := "end Eggshell.Plugin.SharedRangeAdapter.ReachBuilder"
  check ((proof.splitOn start).length == 2 && (proof.splitOn stop).length == 2) "ambiguous checked connection"
  let inner := ((proof.splitOn start)[1]!.splitOn stop)[0]!
  let inner := inner ++ "\n@[csimp] theorem index_compiled : @referenceIndex = @exclusiveIndex := index_exact\n"
  let text ← replaceCount original "public import tools.research.SelectionReceipt\n"
    "public import tools.research.SelectionReceipt\npublic import tools.research.BucketView\n" 1
  let marker := "/-- Every member has a complete original binding. Choose among its original\n"
  let text ← replaceCount text marker ("namespace ReachBuilder\n"++inner++"end ReachBuilder\n\n"++marker) 1
  let text ← replaceCount text "let reach := ownerReach keys shapes"
    "let reach := ReachBuilder.referenceIndex keys shapes" 3
  replaceCount text "let choices := memberChoices keys shapes reach member"
    "let choices := ReachBuilder.fromIndex keys shapes reach member" 3
def refactorProof (label : String) : IO Unit := do
  discard <| cleanBuild
  check (!label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-')) "fresh proof label required"
  let original ← IO.FS.readFile (parentBuild.parent.get!/"source/Eggshell/Handoff.lean")
  let mut proof := "module\npublic import Eggshell.Handoff\n@[expose] public section\nopen Lean\nnamespace Eggshell.Plugin.SharedRangeAdapter\n"
  for (name,stop) in [("plan","\ndef fit ("),("selectPrepared","\ndef viewPieces ("),
      ("selectView","/-- A generic-only query needs no service-owned original row.")] do
    let marker := "\ndef "++name++" ("
    check ((original.splitOn marker).length == 2) "ambiguous old selector"
    let tail := (original.splitOn marker)[1]!
    check ((tail.splitOn stop).length > 1) "old selector boundary missing"
    let body := (tail.splitOn stop)[0]!
    proof := proof++"\nnoncomputable def "++name++"Before ("++body++"\n"++
      "theorem "++name++"_refactor : @"++name++" = @"++name++"Before := by rfl\n"++
      "#print axioms "++name++"_refactor\n"
  proof := proof++"\nend Eggshell.Plugin.SharedRangeAdapter\n"
  let path := root/("ConsumerRefactor-"++label++".lean")
  check (!(← path.pathExists)) "preserve previous proof source"
  IO.FS.writeFile path proof
  write (records/("refactor-plan-"++label++".json")) (Json.mkObj [("sourceSha256",toJson (← hash path)),
    ("oldSourceSha256",toJson (← hash (parentBuild.parent.get!/"source/Eggshell/Handoff.lean"))),
    ("candidateSha256",toJson (← hash (build/"StudyMain")))])
  let tag := "owner-reach-refactor-proof-"++label
  guard tag #["/usr/bin/env","LEAN_PATH="++(build/"lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M2500","-DwarningAsError=true",path.toString]
  write (records/"current-refactor.json") (toJson tag)
def hexadecimal (text : String) : Option Nat :=
  text.toList.foldlM (fun n c => do
    let digit ← if '0' ≤ c && c ≤ '9' then some (c.toNat-'0'.toNat)
      else if 'a' ≤ c && c ≤ 'f' then some (c.toNat-'a'.toNat+10) else none
    return n*16+digit) 0
def symbolAt (symbols : Array (Nat × String)) (address : Nat) : Option String := Id.run do
  let mut lo := 0
  let mut hi := symbols.size
  while lo < hi do
    let mid := (lo+hi)/2
    if symbols[mid]!.1 ≤ address then lo := mid+1 else hi := mid
  return if lo == 0 then none else (symbols[lo-1]?).map Prod.snd
def nativeBinding (symbolsText : String) : IO Unit := do
  let object := build/"Eggshell_Handoff.o"
  let columns := fun (line : String) => (line.replace "\t" " ").splitOn " " |>.filter (! ·.isEmpty)
  let symbols := (symbolsText.splitOn "\n").filterMap (fun row => do
    let fields := columns row
    if fields[1]? != some "T" && fields[1]? != some "t" then none else do
      return (← hexadecimal (← fields[0]?),← fields[2]?)) |>.toArray
  let raw ← command "/usr/bin/otool" #["-rv",object.toString]
  let reference := "_l_Eggshell_Plugin_SharedRangeAdapter_ownerReach"
  let oldIndex := "_l_Eggshell_Plugin_SharedRangeAdapter_ReachBuilder_referenceIndex"
  let collector := "_l_Eggshell_Plugin_SharedRangeAdapter_ReachBuilder_collectWith"
  let mapper := "_l_Std_DHashMap_Internal_Raw_u2080_map___at___00Eggshell_Plugin_SharedRangeAdapter_ReachBuilder_exclusiveLookup_spec__1"
  let relocations := (raw.splitOn "\n").filterMap fun row => do
    let fields := columns row
    let target ← fields.getLast?
    if !fields.contains "BR26" || ![reference,oldIndex,collector,mapper].contains target then none else do
      return (← hexadecimal (← fields[0]?),target)
  let mut graph : Std.HashMap String (Array String) := {}
  let mut referenceCalls := #[]
  let entries := ["plan","selectPrepared","selectView"].map ("_l_Eggshell_Plugin_SharedRangeAdapter_"++·)
  let mut constructionCalls := #[]
  for (address,target) in relocations do
    let some caller := symbolAt symbols address | throw (IO.userError "native branch owner missing")
    graph := graph.alter caller (fun old => some (old.getD #[] |>.push target))
    check (target != oldIndex || caller == oldIndex++"___boxed")
      "an actual native caller bypasses the compiler substitution"
    if target == reference then
      check (caller.startsWith "_l_Eggshell_Plugin_SharedRangeAdapter_ReachBuilder_referenceLookup" ||
        caller.startsWith oldIndex || caller == reference++"___boxed")
        "operational caller still constructs reference owner buckets"
      referenceCalls := referenceCalls.push (caller,address)
    if target == collector then
      check (entries.contains caller || caller == collector++"___boxed" ||
        caller.startsWith "_l_Eggshell_Plugin_SharedRangeAdapter_ReachBuilder_exclusiveLookup" ||
        caller.startsWith "_l_Eggshell_Plugin_SharedRangeAdapter_ReachBuilder_exclusiveIndex")
        "collector unexpectedly invoked in a member traversal or unrelated operational helper"
      constructionCalls := constructionCalls.push (caller,address)
  let mut paths := #[]
  for entry in entries do
    let calls := graph[entry]?.getD #[]
    check (calls.count collector == 1 && calls.count mapper == 1)
      "index construction must occur in the selector entry, outside member traversal"
    paths := paths.push (entry,calls)
  write (records/"native-binding.json") (Json.mkObj [("objectSha256",toJson (← hash object)),
    ("consumerBranchPaths",toJson paths),("referenceCallsOnlyInReferenceHelpers",toJson referenceCalls),
    ("constructionCalls",toJson constructionCalls),("indexConstructedInEachSelectorEntry",toJson true),
    ("constructionInlinedAtEntry",toJson true),("runtimeSha256",toJson (← hash (build/"StudyMain")))])
def setup : IO Unit := do
  idle
  check ((← hash (parentBuild/"StudyMain")) == "1153215e50e63191a46b1f80a34d8c2c0d056478b30b81e5c22958d2c1a8c965")
    "audited parent changed"
  check (!(← root.pathExists)) "fresh isolated runtime required"
  IO.FS.createDirAll records
  materialize parentBuild source build "tools.research.OwnedSelectionRuntime" "owner-reach-runtime-settings.json"
  for name in ["OwnedBuckets","BucketView"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  let path := source/"Eggshell/Handoff.lean"
  let original ← IO.FS.readFile path
  IO.FS.writeFile path (← boundSource original)
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",
    (parentBuild.parent.get!/"source/Eggshell/Handoff.lean").toString,path.toString]}
  check (diff.exitCode == 1) "expected explicit consumer patch"
  IO.FS.writeFile (records/"handoff.patch") diff.stdout
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parentBuild/"StudyMain"))),
    ("comparisonOrder",toJson order),("countsPerArm",toJson (#[(4 : Nat),16])),
    ("treatment",toJson "complete ordered owner-bucket lookup equivalence;prepare each bucket once;compiler substitution registered before three actual consumers"),
    ("resourceLimits",toJson "unchanged:4358524KiB RSS;2097152KiB free disk"),
    ("unchanged",toJson "snapshot,questions,canonical bodies,model,ranking,ties,synapses,Exact,pools,locks,deadlines,ACK,harness,envelope"),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
def audit (label : String) : IO Unit := do
  discard <| cleanBuild
  discard <| clean (← IO.ofExcept ((← read (records/"current-refactor.json")).getStr?))
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",build.toString,(records/("native-"++label++".json")).toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"compare-sources",parentBuild.toString,build.toString,
    (records/("sources-"++label++".json")).toString,"Eggshell.Handoff","+tools.research.OwnedBuckets","+tools.research.BucketView"]
  check ((← read (parentBuild/"tools_research_OwnedSelectionRuntime.source")) ==
    (← read (build/"tools_research_OwnedSelectionRuntime.source"))) "entry or embedded literals changed"
  let (text,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/"Eggshell_Handoff.source")))
  check (text == (← boundSource (← IO.FS.readFile (parentBuild.parent.get!/"source/Eggshell/Handoff.lean"))) && literals.isEmpty)
    "actual consumer differs from the checked transformation"
  let output ← IO.FS.readFile (build/"Eggshell_Handoff-lean.stdout")
  check (!output.contains "sorryAx") "unclosed consumer proof"
  IO.FS.writeFile (records/"axioms.txt") output
  let symbols ← command "/usr/bin/nm" #["-n",(build/"Eggshell_Handoff.o").toString]
  check (symbols.contains "ReachBuilder_exclusiveIndex" && symbols.contains "ReachBuilder_collectWith")
    "new native constructor absent"
  IO.FS.writeFile (records/"consumer-symbols.txt") symbols
  nativeBinding symbols
  write (records/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
    ("parentSha256",toJson (← hash (parentBuild/"StudyMain"))),("adopted",toJson false)])
def install : IO Unit := do
  discard <| clean (← IO.ofExcept ((← read (records/"current-audit.json")).getStr?))
  check (!(← installation.pathExists)) "fresh installation required"
  let plugin := installation/"share/eggshell/codex-plugin"
  IO.FS.createDirAll (installation/"libexec")
  IO.FS.createDirAll (plugin/"bin")
  discard <| command "/bin/ln" #["-s",(build/"StudyMain").toString,(installation/"libexec/eggshell").toString]
  discard <| command "/bin/ln" #["-s",(parentPrefix/"share/eggshell/minilm").toString,(installation/"share/eggshell/minilm").toString]
  for name in ["egg","eggshelld"] do
    let original ← IO.FS.readFile (parentPrefix/"share/eggshell/codex-plugin/bin"/name)
    check (original.contains parentPrefix.toString) "launcher boundary changed"
    IO.FS.writeFile (plugin/"bin"/name) (original.replace parentPrefix.toString installation.toString)
    discard <| command "/bin/chmod" #["755",(plugin/"bin"/name).toString]
def attempt (label : String) : IO String := do
  let path := records/(label++"-attempt.json")
  if ← path.pathExists then IO.ofExcept ((← read path).getStr?) else pure label
def retireFinished (label : String) : IO Unit := do
  idle
  let actual ← attempt label
  discard <| clean ("owner-reach-runtime-"++actual)
  check (!(← (records/(label++"-retired.json")).pathExists)) "preserve retirement evidence"
  let result ← read (records/(label++".json"))
  check (result.getObjValD "passed" == toJson true) "only collected successful states can be retired"
  let output := root/actual
  let phases : Array Json ← IO.ofExcept (fromJson? ((result.getObjValD "report").getObjValD "phases"))
  let mut clients : Array Json ← IO.ofExcept (fromJson? (← read (output/"prime.json")))
  for phase in phases do clients := clients++(← IO.ofExcept (phase.getObjValAs? (Array Json) "rows"))
  let input ← read (root/(actual++"-input.json"))
  let dataRoot : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let kept := #[parentBuild/"StudyMain",build/"StudyMain",base/"snapshot-scheduling/work/work.egg/head"]
  let hashes ← kept.mapM hash
  let hex := fun (text : String) => text.length == 64 && text.toList.all (fun c =>
    ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))
  let mut deleted := #[]
  for client in clients do
    let session ← IO.ofExcept (client.getObjValAs? String "session")
    let receipt ← IO.ofExcept (client.getObjValAs? String "receipt")
    check (session.startsWith "capacity-" && hex ((session.drop 9).toString) && hex receipt &&
      client.getObjValD "success" == toJson true && client.getObjValD "acknowledged" == toJson true)
      "only successful acknowledged owned clients may be retired"
    let path := dataRoot/"sessions"/session
    let confirmed := (← read (path/"state.json")).getObjValD "confirmedDelivery"
    check (confirmed.getObjValD "session" == toJson session) "foreign ledger"
    let authority ← IO.ofExcept ((confirmed.getObjValD "head").getObjValAs? String "authority")
    let context := (authority.drop "confirmed-delivery:".length).toString
    check (authority == "confirmed-delivery:"++context && hex context) "invalid owned authority"
    for target in #[path,dataRoot/"confirmed-delivery"/context,dataRoot/"receipts"/receipt] do
      check ((← target.symlinkMetadata).type == .dir) "retired root must be owned"
      let count ← removeOwned target
      deleted := deleted.push (target.toString,count.1,count.2)
  let mut metadata := [("input",input)]
  for file in ← output.readDir do
    if (← file.path.symlinkMetadata).type == .file && file.fileName.endsWith ".json" &&
        !["report.json","progress.json"].contains file.fileName then
      metadata := metadata++[(file.fileName,← read file.path)]
  write (records/(label++"-metadata.json")) (Json.mkObj metadata)
  let count ← removeOwned output
  deleted := deleted.push (output.toString,count.1,count.2)
  check ((← kept.mapM hash) == hashes) "protected runtime or head changed"
  write (records/(label++"-retired.json")) (Json.mkObj [("clients",toJson clients.size),("deleted",toJson deleted),
    ("protectedInputs",toJson (kept.zip hashes)),("protectedHashesUnchanged",toJson true),("archiveCreated",toJson false)])
def prepare (label : String) : IO Unit := do
  discard <| clean (← IO.ofExcept ((← read (records/"current-audit.json")).getStr?))
  let preflight := label == "preflight"
  if !preflight then
    let some index := order.findIdx? (· == label) | throw (IO.userError "undeclared arm")
    let prior := if index == 0 then "preflight" else order[index-1]!
    discard <| clean ("owner-reach-runtime-"++(← attempt prior))
    check ((← read (records/(prior++".json"))).getObjValD "passed" == toJson true) "previous arm failed"
  let candidate := preflight || label.startsWith "b"
  let chosen := if candidate then installation else parentPrefix
  let runtime := chosen/"libexec/eggshell"
  let digest := (← read (records/"runtime.json")).getObjValD (if candidate then "sha256" else "parentSha256")
  check (digest == toJson (← hash runtime)) "audited runtime changed"
  let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
  let actual ← attempt label
  let output := root/actual
  let config := output/"config.toml"
  let plugin := chosen/"share/eggshell/codex-plugin"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
  let environment := environment.map fun (key,value) => (key,match key with
    | "EGGSHELL_PREFIX" => some chosen.toString | "PLUGIN_ROOT" => some plugin.toString
    | "EGGSHELL_CONFIG" => some config.toString | _ => value)
  let input := original.setObjVal! "output" (toJson output.toString) |>.setObjVal! "config" (toJson config.toString)
    |>.setObjVal! "environment" (toJson environment) |>.setObjVal! "runtime" (toJson runtime.toString)
    |>.setObjVal! "runtimeSha256" digest |>.setObjVal! "plugin" (toJson plugin.toString)
  let input := if preflight then input.setObjVal! "counts" (toJson (#[(4 : Nat)]))
    |>.setObjVal! "diagnostic" (toJson true) else input
  let path := root/(actual++"-input.json")
  check (!(← path.pathExists)) "preserve previous arm"
  write path input
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
  guard ("owner-reach-runtime-"++actual) (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++
    #[runtime.toString,"owned-selection-capacity",path.toString])
def collect (label : String) : IO Unit := do
  let actual ← attempt label
  let monitor ← clean ("owner-reach-runtime-"++actual)
  let report ← read (root/actual/"report.json")
  let input ← read (root/(actual++"-input.json"))
  let origin : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let expected : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (file,digest) in expected do check ((← hash (origin/file)) == digest) "original source publication changed"
  check (report.getObjValD "allPhasesPassed" == toJson true || (label == "preflight" &&
    (← read (root/actual/"phase-4/result.json")).getObjValD "passed" == toJson true)) "actual workload failed"
  write (records/(label++".json")) (Json.mkObj [("guard",monitor),("report",report),("passed",toJson true),
    ("sourceFilesUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def compare : IO Unit := do
  idle
  check (!(← (records/"comparison.json").pathExists)) "preserve completed comparison"
  let invariant := fun (input : Json) => Json.mkObj
    (["project","sourceFiles","workspace","data","topics","handoffChars","counts","diagnostic"].map
      fun key => (key,input.getObjValD key))
  let fixedEnv := fun (environment : Array (String × Option String)) =>
    environment.filter fun row => !["EGGSHELL_PREFIX","PLUGIN_ROOT","EGGSHELL_CONFIG"].contains row.1
  let common ← read (root/((← attempt "a-first")++"-input.json"))
  let originalEnv : Array (String × Option String) ← IO.ofExcept (fromJson? (common.getObjValD "environment"))
  let mut rows := #[]
  let mut before := #[]
  let mut after := #[]
  for label in order do
    let actual ← attempt label
    discard <| clean ("owner-reach-runtime-"++actual)
    let input ← read (root/(actual++"-input.json"))
    let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
    check (invariant common == invariant input && fixedEnv originalEnv == fixedEnv environment)
      "snapshot,questions,canonical bodies,harness or non-treatment environment changed"
    let result ← read (records/(label++".json"))
    check (result.getObjValD "passed" == toJson true) "completed fixed arm required"
    let phases : Array Json ← IO.ofExcept (fromJson? ((result.getObjValD "report").getObjValD "phases"))
    let some phase := phases.find? (fun phase => phase.getObjValD "clients" == toJson (16 : Nat)) |
      throw (IO.userError "sixteen-client wave missing")
    let elapsed ← IO.ofExcept (phase.getObjValAs? Nat "wallMs")
    if label.startsWith "b" then after := after.push elapsed else before := before.push elapsed
    rows := rows.push (Json.mkObj [("arm",toJson label),("phases",toJson (phases.map fun phase => Json.mkObj
      (["clients","wallMs","semanticCompleted","synapsesCompleted","allBodiesByteEqual","passed"].map
        fun key => (key,phase.getObjValD key)))),
      ("peakRssKiB",(result.getObjValD "guard").getObjValD "sampledPeakRssKiB"),
      ("recordSha256",toJson (← hash (records/(label++".json")))),
      ("attempt",toJson actual),("inputSha256",toJson (← hash (root/(actual++"-input.json"))))])
  check (before.size == 2 && after.size == 2) "equal predeclared counts required"
  let a := before.foldl Nat.add 0
  let b := after.foldl Nat.add 0
  check (a > 0) "nonzero reference clock required"
  let rejection ← if ← (records/"aborted-comparison.json").pathExists then
    read (records/"aborted-comparison.json") else pure Json.null
  write (records/"comparison.json") (Json.mkObj [("order",toJson order),("arms",toJson rows),
    ("parent16WallMs",toJson before),("candidate16WallMs",toJson after),
    ("descriptiveMeanLatencyReductionPercent",toJson (100.0*(Float.ofNat a-Float.ofNat b)/Float.ofNat a)),
    ("fewSecond16ClientTargetMet",toJson (after.all (· ≤ 5000))),
    ("p99Established",toJson false),("eightyConcurrentTest",toJson false),
    ("inclusiveTokenOrQualityBenefitEstablished",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("separateAbortedComparison",rejection),("successfulPilotArmsPooled",toJson false),
    ("adopted",toJson false)])
def retireGenerated : IO Unit := do
  idle
  check ((← read (records/"comparison.json")).getObjValD "adopted" == toJson false &&
    !(← (records/"retired-generated.json").pathExists)) "finish comparison and preserve retirement evidence"
  for label in #["preflight"]++order do
    check (← (records/(label++"-retired.json")).pathExists) "retire acknowledged arm states first"
    discard <| clean ("owner-reach-runtime-"++(← attempt label))
  let dataRoot := base/"snapshot-scheduling/work/data"
  for path in #[dataRoot/"publisher/endpoint.json",dataRoot/"publisher/operations.json",dataRoot/"daemon.json"] do
    check (!(← path.pathExists)) "a live or stale service still needs recovery"
  let targets := #[installation,source,build,base/"owner-reach-proof"]
  let mut checked := 0
  for directory in #[parentBuild/"lib",base/"current-six/stable-source-rows/build/lib",
      base/"current-six/fixed-sequence/preparation-closure-build/lib",base/"study-local-lib"] do
    if ← directory.pathExists then checked := checked+(← retainedLinks directory targets)
  let kept := #[parentBuild/"StudyMain",base/"current-six/stable-source-rows/build/StudyMain",
    base/"current-six/fixed-sequence/controller-build/StudyMain",base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",
    base/"byte-pages-prefix/libexec/eggshell",base/"snapshot-scheduling/work/work.egg/head"]
  let hashes ← kept.mapM hash
  let mut monitors := #[]
  for tag in ["owner-reach-runtime-build","owner-reach-runtime-build-data","owner-reach-refactor-proof",
      "owner-reach-refactor-proof-lean","owner-reach-refactor-proof-data","owner-reach-runtime-audit",
      "owner-reach-runtime-audit-bound","owner-reach-runtime-audit-code","owner-reach-runtime-audit-data",
      "owner-reach-runtime-b-second","owner-reach-runtime-a-first-after-space"] do
    let value ← read (base/(tag++".guard.json"))
    check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "unfinished intermediate stage"
    monitors := monitors.push (tag,value)
  write (records/"intermediate-guards.json") (toJson monitors)
  let mut deleted := #[]
  for path in targets do
    let count ← removeOwned path
    deleted := deleted.push (path.toString,count.1,count.2)
  -- This private root belongs only to model-free capacity trials. The source
  -- DB is its sibling work.egg; current project read-cache is retained.
  for name in ["sessions","confirmed-delivery","receipts"] do
    let path := dataRoot/name
    check ((← path.symlinkMetadata).type == .dir) "trial-state root must be owned"
    let count ← removeOwned path
    deleted := deleted.push (path.toString,count.1,count.2)
  for label in ["b-second","a-first-after-space"] do
    let path := root/label
    if ← path.pathExists then
      let count ← removeOwned path
      deleted := deleted.push (path.toString,count.1,count.2)
  for file in ← root.readDir do
    if file.fileName.startsWith "ConsumerRefactor" || file.fileName.endsWith ".stderr" then
      let count ← removeOwned file.path
      deleted := deleted.push (file.path.toString,count.1,count.2)
  let mut rawSymbols := #[]
  for name in ["consumer-symbols.txt","function-consumer-symbols.txt"] do
    let path := records/name
    rawSymbols := rawSymbols.push (name,← hash path)
    let count ← removeOwned path
    deleted := deleted.push (path.toString,count.1,count.2)
  check ((← kept.mapM hash) == hashes) "protected runtime or source head changed"
  write (records/"retired-generated.json") (Json.mkObj [("deleted",toJson deleted),
    ("activeCompilerInputsChecked",toJson checked),("protectedInputs",toJson (kept.zip hashes)),
    ("rawSymbolDigests",toJson rawSymbols),("protectedHashesUnchanged",toJson true),
    ("projectReadCacheRetained",toJson true),("archiveCreated",toJson false)])
def main (args : List String) : IO Unit := do
  match args with
  | ["setup"] => setup
  | ["build",label] => do
      check (!label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-')) "fresh build label required"
      let tag := "owner-reach-runtime-build-"++label
      guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (project/"tools/research/StudyBuildMain.lean").toString,(base/"owner-reach-runtime-settings.json").toString]
      write (records/"current-build.json") (toJson tag)
  | ["refactor-proof",label] => refactorProof label
  | ["audit",label] => do
      check (!label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-')) "fresh audit label required"
      let tag := "owner-reach-runtime-audit-"++label
      guard tag #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
        (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/OwnerReachRuntimeStudy.lean").toString,"audit-worker",label]
      write (records/"current-audit.json") (toJson tag)
  | ["audit-worker",label] => audit label
  | ["install"] => install
  | ["prepare",label] => prepare label
  | ["collect",label] => collect label
  | ["retire",label] => retireFinished label
  | ["compare"] => compare
  | ["retire-generated"] => retireGenerated
  | _ => throw (IO.userError "setup | build <label> | refactor-proof <label> | audit <label> | install | prepare <arm> | collect <arm> | retire <arm> | compare | retire-generated")
end OwnerReachStudy
def main := OwnerReachStudy.main
