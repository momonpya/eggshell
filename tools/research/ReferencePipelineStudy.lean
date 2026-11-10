import tools.research.StudyLocal
open Lean StudyLocal
namespace ReferencePipelineStudy
def root := base/"reference-pipeline"
def records := project/"docs/candidates/reference-pipeline"
def parent := base/"canonical-decoder-runtime"
def source := root/"source"
def build := root/"build"
def installation := root/"prefix"
def dataRoot := root/"data"
def order : Array String := #["a-first","b-first","b-second","a-second"]
def driver := project/"tools/research/ReferencePipelineStudy.lean"
def clean (tag : String) : IO Json := do
  let record ← finished ("reference-pipeline-"++tag)
  check (record.getObjValD "guardTriggered" == toJson false && record.getObjValD "reason" == Json.null) "resource stop"
  return record
def guarded (tag : String) (args : Array String) := guard ("reference-pipeline-"++tag) args
def metadata (tag action : String) := guarded tag #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
  (compiler/"bin/lean").toString,"-j1","-M1536","--run",driver.toString,action]
def extractSection (text first last : String) : IO String := do
  check ((text.splitOn first).length == 2) "unique section start required"
  let tail := (text.splitOn first)[1]!
  check ((tail.splitOn last).length == 2) "unique section end required"
  return first++(tail.splitOn last)[0]!
def replace (text before after : String) : IO String := do
  check ((text.splitOn before).length == 2) "checked source boundary changed"
  return text.replace before after

def hexadecimal (text : String) : Option Nat := text.toList.foldlM (fun n c => do
  let digit ← if '0' ≤ c && c ≤ '9' then some (c.toNat-'0'.toNat)
    else if 'a' ≤ c && c ≤ 'f' then some (c.toNat-'a'.toNat+10) else none
  return n*16+digit) 0

def nativeCalls : IO Unit := do
  let object := build/"Eggshell_Handoff.o"
  let fields := fun (line : String) => (line.replace "\t" " ").splitOn " " |>.filter (!·.isEmpty)
  let symbols := ((← command "/usr/bin/nm" #["-n",object.toString]).splitOn "\n").filterMap (fun row => do
    let columns := fields row
    if columns[1]? != some "T" && columns[1]? != some "t" then none else do
      return (← hexadecimal (← columns[0]?),← columns[2]?))
  let mut calls := #[]
  for row in (← command "/usr/bin/otool" #["-rv",object.toString]).splitOn "\n" do
    let columns := fields row
    let some target := columns.getLast? | continue
    if !columns.contains "BR26" || !["ParallelProjection_alongside","refocusObservedNeighborhoodUsing","rankedCitedObservationCoordinates"].any (fun pattern => target.contains pattern) then continue
    let some address := columns[0]?.bind hexadecimal | throw (IO.userError "native call has no address")
    let some (_,caller) := (symbols.takeWhile (·.1 ≤ address)).getLast? | throw (IO.userError "native call owner missing")
    calls := calls.push (caller,target,address)
  check (calls.any fun (caller,target,_) => caller.contains "indexedDiscoveryUsing" && target.contains "ParallelProjection_alongside") "actual discovery does not call pipeline"
  for target in ["refocusObservedNeighborhoodUsing","rankedCitedObservationCoordinates"] do
    check (calls.any fun (caller,callee,_) => caller.contains "indexedDiscoveryUsing" && callee.contains target) "projected closure lost original expression"
  write (records/"native-calls.json") (Json.mkObj [("objectSha256",toJson (← hash object)),("calls",toJson calls),
    ("actualDiscoveryCallsPipeline",toJson true),("originalPureExpressionsPresent",toJson true),("notAFullCCompilerProof",toJson true)])

def transformed (text : String) : IO String := do
  let focus ← extractSection text "    let observedNeighborhood := indexedFocus.bind fun focused =>\n" "    if let some neighborhood := observedNeighborhood then\n"
  let references ← extractSection text "    let parents := nominationRanking.zipIdx.filterMap" "    let referencedEvidence := referenced.map"
  let transport ← extractSection text "    trace \"synaptic owners\"\n" "    trace \"synaptic built\"\n"
  let expression := focus.drop "    let observedNeighborhood := ".length |>.toString.trimAscii.toString
  let expression := "\n".intercalate ((expression.splitOn "\n").zipIdx.map (fun (line,index) =>
    "          "++(if index == 0 then line else (line.drop 4).toString)))
  let projection := "    let (synaptic,projections) ← Research.ParallelProjection.alongside\n"++
    "      (Research.ParallelProjection.paired\n        (fun _ =>\n"++expression++")\n"++
    "        (fun _ => Id.run do\n"++("\n".intercalate (references.splitOn "\n" |>.map fun line => if line.isEmpty then "" else "      "++line))++
    "          return referenced)) advisoryDeadline (do\n"++
    ("\n".intercalate (transport.splitOn "\n" |>.map fun line => if line.isEmpty then "" else "  "++line))++
    "      return synaptic)\n    trace \"synaptic built\"\n    let observedNeighborhood := projections.1\n"
  let text ← replace text transport ""
  let text ← replace text "    trace \"synaptic built\"\n" ""
  let text ← replace text references "    let referenced := projections.2\n"
  let text ← replace text focus projection
  let marker := "public import Eggshell.SourcePlan\n"
  check (text.contains marker) "pool dependency import boundary missing"
  replace text marker (marker++"public import tools.research.ParallelProjection\n")

def capture (label : String) : IO Unit := do
  let monitor ← clean label
  let input ← read (root/(label++"-input.json"))
  let output := root/label
  let report ← read (output/"report.json")
  let preflight := label == "preflight"
  check (report.getObjValD "allPhasesPassed" == toJson true || (preflight &&
    (← read (output/"phase-4/result.json")).getObjValD "passed" == toJson true)) "native wave failed"
  let original : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let originals : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (file,digest) in originals do check ((← hash (original/file)) == digest) "original source changed"
  let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let primes : Array Json ← IO.ofExcept (fromJson? (← read (output/"prime.json")))
  let mut clients := primes
  let phases : Array Json ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
  for phase in phases do clients := clients++(← IO.ofExcept (phase.getObjValAs? (Array Json) "rows"))
  check (clients.size == (if preflight then 7 else 23) && clients.all (fun client =>
    client.getObjValD "success" == toJson true && client.getObjValD "bodyByteEqual" == toJson true &&
    client.getObjValD "acknowledged" == toJson true)) "all canonical bodies and ACK required"
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
    ("passed",toJson true),("sourceFilesUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  for name in ["cache-stats-prime","cache-stats-phase-4","cache-stats-phase-16","frontend-shutdown","publisher-shutdown"] do
    let file := output/(name++".json")
    if ← file.pathExists then fields := fields++[(name,← read file)]
  check (!(← (records/(label++".json")).pathExists)) "preserve captured arm"
  write (records/(label++".json")) (Json.mkObj fields)

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

def retireArm (label : String) : IO Unit := do
  idle
  discard <| clean label
  let record ← read (records/(label++".json"))
  check (record.getObjValD "passed" == toJson true) "collect arm before retirement"
  let data : System.FilePath := .mk (← IO.ofExcept ((record.getObjValD "input").getObjValAs? String "data"))
  check (data == dataRoot || data == parent/"data") "retirement escaped fixture data roots"
  for file in #[data/"publisher/endpoint.json",data/"publisher/operations.json",data/"daemon.json"] do
    check (!(← file.pathExists)) "service endpoint remains"
  let protectedPaths := #[build/"StudyMain",parent/"build/StudyMain",base/"snapshot-scheduling/work/work.egg/head"] ++
    (#[1,2,3].map fun n => base/"snapshot-scheduling/diagnostic"/("topic-"++toString n)/"body.txt")
  let hashes ← protectedPaths.mapM hash
  let mut retired := #[]
  for path in #[root/label,data/"sessions",data/"confirmed-delivery",data/"receipts"] do
    if ← path.pathExists then
      let count ← removeOwned path
      retired := retired.push (path.toString,count.1,count.2)
  check ((← protectedPaths.mapM hash) == hashes) "retirement changed protected runtime or source"
  write (records/(label++"-retired.json")) (Json.mkObj [("removed",toJson retired),("protectedHashesUnchanged",toJson true),("archive",toJson false)])

def compare : IO Unit := do
  idle
  check (!(← (records/"comparison.json").pathExists)) "preserve completed comparison"
  let fixed := fun (input : Json) => Json.mkObj (["project","sourceFiles","workspace","topics","handoffChars","counts","diagnostic"].map
    fun key => (key,input.getObjValD key))
  let fixedEnv := fun (rows : Array (String × Option String)) => rows.filter fun row =>
    !["EGGSHELL_PREFIX","PLUGIN_ROOT","EGGSHELL_CONFIG","EGGSHELL_DATA_ROOT"].contains row.1
  let original := (← read (records/"a-first.json")).getObjValD "input"
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
  let mut arms := #[]
  let mut before : Array Nat := #[]
  let mut after : Array Nat := #[]
  for label in order do
    discard <| clean label
    let result ← read (records/(label++".json"))
    let input := result.getObjValD "input"
    let actualEnv : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
    check (fixed input == fixed original && fixedEnv actualEnv == fixedEnv env) "unmatched comparison inputs"
    let candidate := label.startsWith "b"
    check (input.getObjValD "data" == toJson (if candidate then dataRoot else parent/"data").toString) "producer cache scope changed"
    let expected := (← read (records/"runtime.json")).getObjValD (if candidate then "sha256" else "parentSha256")
    check (input.getObjValD "runtimeSha256" == expected) "unmatched executable"
    let phases : Array Json ← IO.ofExcept ((result.getObjValD "report").getObjValAs? (Array Json) "phases")
    let some small := phases.find? (fun phase => phase.getObjValD "clients" == toJson (4 : Nat)) | throw (IO.userError "missing four-client wave")
    let some large := phases.find? (fun phase => phase.getObjValD "clients" == toJson (16 : Nat)) | throw (IO.userError "missing sixteen-client wave")
    let elapsed ← IO.ofExcept (large.getObjValAs? Nat "wallMs")
    if candidate then after := after.push elapsed else before := before.push elapsed
    arms := arms.push (Json.mkObj [("arm",toJson label),("wall4Ms",small.getObjValD "wallMs"),("wall16Ms",toJson elapsed),
      ("peakRssKiB",(result.getObjValD "guard").getObjValD "sampledPeakRssKiB")])
  let mean := fun (values : Array Nat) => (values.foldl (·+·) 0).toFloat/values.size.toFloat
  write (records/"comparison.json") (Json.mkObj [("order",toJson order),("arms",toJson arms),
    ("parentMean16Ms",toJson (mean before)),("candidateMean16Ms",toJson (mean after)),
    ("descriptiveImprovementPercent",toJson (100*(mean before-mean after)/mean before)),
    ("canonicalBodiesAndAcknowledgements",toJson (99 : Nat)),("measuredSemanticAndSynapticCompletions",toJson (84 : Nat)),
    ("sameSnapshotAndSource",toJson true),("statisticalOrP99Claim",toJson false),("fewSecondsAt16Achieved",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

partial def retainedLinks (path : System.FilePath) : IO Nat := do
  let actual ← IO.FS.realPath path
  check (!(actual.toString.startsWith (root.toString++"/"))) "active compiler input depends on retired experiment"
  if (← path.symlinkMetadata).type == .dir then
    let mut count := 0
    for entry in ← path.readDir do count := count+(← retainedLinks entry.path)
    return count
  return 1

def retire : IO Unit := do
  idle
  check (!(← (records/"retired.json").pathExists)) "preserve completed retirement"
  let result ← read (records/"comparison.json")
  check (result.getObjValD "adopted" == toJson false) "only retire unadopted experiment"
  for label in #["preflight"]++order do
    discard <| clean label
    check ((← read (records/(label++"-retired.json"))).getObjValD "protectedHashesUnchanged" == toJson true) "retire each captured arm first"
  for data in #[dataRoot,parent/"data"] do
    for file in #[data/"publisher/endpoint.json",data/"publisher/operations.json",data/"daemon.json"] do
      check (!(← file.pathExists)) "service endpoint remains"
  let protectedPaths := #[parent/"build/StudyMain",base/"register-rounds-runtime/build/StudyMain",
    base/"current-six/stable-source-rows/build/StudyMain",base/"current-six/fixed-sequence/controller-build/StudyMain",
    base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",base/"byte-pages-prefix/libexec/eggshell",
    base/"snapshot-scheduling/work/work.egg/head"] ++
    (#[1,2,3].map fun n => base/"snapshot-scheduling/diagnostic"/("topic-"++toString n)/"body.txt")
  let hashes ← protectedPaths.mapM hash
  let sourceInput := (← read (records/"a-first.json")).getObjValD "input"
  let original : System.FilePath := .mk (← IO.ofExcept (sourceInput.getObjValAs? String "project"))
  let originals : Array (String × String) ← IO.ofExcept (fromJson? (sourceInput.getObjValD "sourceFiles"))
  for (file,digest) in originals do check ((← hash (original/file)) == digest) "original source changed before retirement"
  let mut checked := 0
  for folder in #[parent/"build/lib",base/"register-rounds-runtime/build/lib",base/"current-six/stable-source-rows/build/lib",
      base/"current-six/fixed-sequence/preparation-closure-build/lib",base/"study-local-lib"] do
    if ← folder.pathExists then checked := checked+(← retainedLinks folder)
  let mut monitors := #[]
  let mut guardFiles := #[]
  for file in ← base.readDir do
    if !file.fileName.startsWith "reference-pipeline-" || !file.fileName.endsWith ".guard.json" then continue
    let monitor ← read file.path
    check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "experiment still owns a process"
    monitors := monitors.push (file.fileName,monitor)
    guardFiles := guardFiles.push file.path
    let settings := base/(file.fileName.replace ".guard.json" ".guard-settings.json")
    if ← settings.pathExists then guardFiles := guardFiles.push settings
  write (records/"resources.json") (toJson monitors)
  write (records/"runtime-build.json") (← read (build/"build.json"))
  write (records/"controls-build.json") (← read (root/"checks-build/build.json"))
  let mut deleted := #[]
  for path in #[root]++guardFiles++#[base/"reference-pipeline-settings.json",base/"reference-pipeline-checks-settings.json"] do
    check (← path.pathExists) "retirement target disappeared"
    let count ← removeOwned path
    deleted := deleted.push (path.toString,count.1,count.2)
  check ((← protectedPaths.mapM hash) == hashes) "retirement changed protected source or executable"
  for (file,digest) in originals do check ((← hash (original/file)) == digest) "original source changed during retirement"
  write (records/"retired.json") (Json.mkObj [("deleted",toJson deleted),("activeCompilerInputsChecked",toJson checked),
    ("protected",toJson (protectedPaths.zip hashes)),("originalSourceUnchanged",toJson true),("archive",toJson false),
    ("endedExperimentCannotBeResumed",toJson true),("parentRuntimeRetained",toJson true)])

def main (args : List String) : IO Unit := do
  match args with
  | ["refresh"] => do
    idle
    check (!(← (base/"reference-pipeline-build.guard.json").pathExists)) "refresh only before native build starts"
    IO.FS.writeFile (source/"Eggshell/Handoff.lean") (← transformed (← IO.FS.readFile (parent/"source/Eggshell/Handoff.lean")))
  | ["setup"] | ["connect"] => do
    let mode := args.head!
    idle
    if mode == "setup" then
      check (!(← root.pathExists) && !(← records.pathExists)) "fresh isolated study required"
    else
      check (!(← (records/"plan.json").pathExists) && !(← (base/"reference-pipeline-build.guard-settings.json").pathExists)) "connect only resumes metadata setup before any build"
    check ((← hash (parent/"build/StudyMain")) == "7cc1432d2d3931a26d60e3e614807545e3f6b522737838bdabc1b1c626e657ab") "audited parent changed"
    IO.FS.createDirAll records
    if mode == "setup" then materialize (parent/"build") source build "tools.research.OwnedSelectionRuntime" "reference-pipeline-settings.json"
    let path := source/"Eggshell/Handoff.lean"
    check ((← IO.FS.readFile path) == (← IO.FS.readFile (parent/"source/Eggshell/Handoff.lean"))) "only untouched materialization may be connected"
    IO.FS.writeFile path (← transformed (← IO.FS.readFile path))
    IO.FS.writeFile (source/"tools/research/ParallelProjection.lean") (← IO.FS.readFile (project/"tools/research/ParallelProjection.lean"))
    write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
      ("hypothesis",toJson "overlap pure neighborhood/ref-citation projection with independent synaptic transport IO, not selector-only pooling"),
      ("pureExpressionsUnchanged",toJson true),("ownedJoinBeforeBatchRelease",toJson true),
      ("graphBudgetFormulaUnchangedButClockObservationEarlier",toJson true),
      ("order",toJson order),("counts",toJson (#[(4 : Nat),16])),
      ("sameSnapshotQueriesBodyEnvelope",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guarded "build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"reference-pipeline-settings.json").toString]
  | ["audit"] => do
    discard <| clean "build"
    metadata "audit" "audit-worker"
  | ["audit-worker"] => do
    let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"inspect",build.toString,(records/"native.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"compare-sources",
      (parent/"build").toString,build.toString,(records/"sources.json").toString,"Eggshell.Handoff","+tools.research.ParallelProjection"]
    check ((← read (parent/"build/tools_research_OwnedSelectionRuntime.source")) ==
      (← read (build/"tools_research_OwnedSelectionRuntime.source"))) "native workload changed"
    let (actual,_) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/"Eggshell_Handoff.source")))
    check (actual == (← transformed (← IO.FS.readFile (parent/"source/Eggshell/Handoff.lean")))) "actual pipeline differs from transformation"
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0",(parent/"source/Eggshell/Handoff.lean").toString,(source/"Eggshell/Handoff.lean").toString]}
    check (diff.exitCode == 1) "expected pipeline patch"
    IO.FS.writeFile (records/"Handoff.patch") diff.stdout
    IO.FS.writeFile (records/"axioms.txt") (← IO.FS.readFile (build/"tools_research_ParallelProjection-lean.stdout"))
    write (records/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
      ("parentSha256",toJson (← hash (parent/"build/StudyMain"))),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    nativeCalls
  | ["controls-setup"] => do
    idle
    materialize (parent/"build") (root/"checks-source") (root/"checks-build") "tools.research.ParallelProjectionChecks" "reference-pipeline-checks-settings.json"
    IO.FS.writeFile (root/"checks-source/tools/research/ParallelProjection.lean") (← IO.FS.readFile (project/"tools/research/ParallelProjection.lean"))
    guarded "controls-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"reference-pipeline-checks-settings.json").toString]
  | ["controls"] => do
    discard <| clean "controls-build-fixed"
    let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"inspect",(root/"checks-build").toString,(records/"controls-native.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"component-sources",build.toString,
      (root/"checks-build").toString,(records/"controls-sources.json").toString,"Eggshell.TaskDeadline","tools.research.ParallelProjection","tools.research.LocalCompletion"]
    for name in ["ParallelProjection","ParallelProjectionChecks"] do
      let (actual,literals) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (root/"checks-build"/("tools_research_"++name++".source"))))
      check (literals.isEmpty && actual == (← IO.FS.readFile (project/"tools/research"/(name++".lean")))) "native lifecycle control source changed"
    guarded "controls" #[(root/"checks-build/StudyMain").toString,(records/"controls.json").toString]
  | ["controls-build-fixed"] => do
    idle
    IO.FS.writeFile (root/"checks-source/tools/research/ParallelProjectionChecks.lean") (← IO.FS.readFile (project/"tools/research/ParallelProjectionChecks.lean"))
    guarded "controls-build-fixed" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"reference-pipeline-checks-settings.json").toString]
  | ["install"] => do
    discard <| clean "audit"
    discard <| clean "controls"
    metadata "install" "install-worker"
  | ["install-worker"] => do
    let plugin := installation/"share/eggshell/codex-plugin"
    IO.FS.createDirAll (installation/"libexec")
    IO.FS.createDirAll (plugin/"bin")
    discard <| command "/bin/ln" #["-s",(build/"StudyMain").toString,(installation/"libexec/eggshell").toString]
    discard <| command "/bin/ln" #["-s",(parent/"prefix/share/eggshell/minilm").toString,(installation/"share/eggshell/minilm").toString]
    for name in ["egg","eggshelld"] do
      let original ← IO.FS.readFile (parent/"prefix/share/eggshell/codex-plugin/bin"/name)
      check (original.contains (parent/"prefix").toString) "launcher boundary changed"
      IO.FS.writeFile (plugin/"bin"/name) (original.replace (parent/"prefix").toString installation.toString)
      discard <| command "/bin/chmod" #["755",(plugin/"bin"/name).toString]
    IO.FS.createDirAll dataRoot
    discard <| command "/bin/cp" #["-c","-R",(parent/"data/read-cache").toString,(dataRoot/"read-cache").toString]
    check ((← IO.FS.realPath (dataRoot/"read-cache")) != (← IO.FS.realPath (parent/"data/read-cache"))) "cache aliases parent"
  | ["prepare",label] => do
    discard <| clean "install"
    let preflight := label == "preflight"
    if !preflight then
      let some position := order.findIdx? (· == label) | throw (IO.userError "undeclared arm")
      let prior := if position == 0 then "preflight" else order[position-1]!
      discard <| clean prior
      check ((← read (records/(prior++".json"))).getObjValD "passed" == toJson true) "previous arm not collected"
    let candidate := preflight || label.startsWith "b"
    let chosen := if candidate then installation else parent/"prefix"
    let data := if candidate then dataRoot else parent/"data"
    let executable := chosen/"libexec/eggshell"
    let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let output := root/label
    let config := output/"config.toml"
    let plugin := chosen/"share/eggshell/codex-plugin"
    let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
    let environment := (environment.filter (·.1 != "EGGSHELL_HANDOFF_TRACE")).map (fun (key,value) => (key,match key with
      | "EGGSHELL_PREFIX" => some chosen.toString | "PLUGIN_ROOT" => some plugin.toString
      | "EGGSHELL_DATA_ROOT" => some data.toString | "EGGSHELL_CONFIG" => some config.toString | _ => value)) ++ #[("EGGSHELL_HANDOFF_TRACE",none)]
    let input := original.setObjVal! "output" (toJson output.toString) |>.setObjVal! "config" (toJson config.toString)
      |>.setObjVal! "environment" (toJson environment) |>.setObjVal! "runtime" (toJson executable.toString)
      |>.setObjVal! "runtimeSha256" (toJson (← hash executable)) |>.setObjVal! "plugin" (toJson plugin.toString) |>.setObjVal! "data" (toJson data.toString)
    let input := if preflight then input.setObjVal! "counts" (toJson (#[(4 : Nat)])) |>.setObjVal! "diagnostic" (toJson true) else input
    let path := root/(label++"-input.json")
    check (!(← path.pathExists)) "preserve completed input"
    write path input
    let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
    guarded label (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++#[executable.toString,"owned-selection-capacity",path.toString])
  | ["capture",label] => capture label
  | ["retire-arm",label] => retireArm label
  | ["compare"] => compare
  | ["retire"] => retire
  | ["post-retirement-check"] => do
    check (← (records/"retired.json").pathExists) "retirement record required"
    metadata "post-retirement" "post-retirement-worker"
  | ["post-retirement-worker"] => do
    check (!(← root.pathExists)) "ended experiment still exists"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(parent/"build").toString,(records/"native-after-retirement.json").toString]
  | ["finish-retirement"] => do
    idle
    write (records/"post-retirement-guard.json") (← clean "post-retirement")
    for suffix in [".guard.json",".guard-settings.json"] do
      IO.FS.removeFile (base/("reference-pipeline-post-retirement"++suffix))
  | _ => throw (IO.userError "reference-pipeline-study setup|audit|controls-setup|controls|install|prepare LABEL|capture LABEL")
end ReferencePipelineStudy
def main := ReferencePipelineStudy.main
