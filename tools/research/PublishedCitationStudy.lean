import tools.research.StudyLocal
open Lean StudyLocal
namespace PublishedCitationStudy
def root := base/"published-citations"
def records := project/"docs/candidates/published-citations"
def parent := base/"canonical-decoder-runtime"
def source := root/"source"
def build := root/"build"
def runtimeRoot := base/"published-citation-runtime"
def runtimeSource := runtimeRoot/"source"
def runtimeBuild := runtimeRoot/"build"
def runtimeRecords := records/"runtime/flat-wire"
def runtimePrefix := runtimeRoot/"prefix"
def runtimeData := runtimeRoot/"data"
def helperSource (name : String) : System.FilePath :=
  if name == "PreparedCitationCoordinates" then records/(name++".lean")
  else project/"tools/research"/(name++".lean")
def clean (label : String) : IO Json := do
  let value ← finished ("published-citations-"++label)
  check (value.getObjValD "guardTriggered" == toJson false && value.getObjValD "reason" == Json.null) "resource stop"
  return value
def guarded (label : String) := guard ("published-citations-"++label)
def driver := project/"tools/research/PublishedCitationStudy.lean"
def metadata (label action : String) := guarded label #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
  (compiler/"bin/lean").toString,"-j1","-M1536","--run",driver.toString,action]
def replace (text before after : String) : IO String := do
  check ((text.splitOn before).length == 2) "unique source boundary required"
  return text.replace before after
def extractSection (text first last : String) : IO String := do
  check ((text.splitOn first).length == 2) "unique start required"
  let tail := (text.splitOn first)[1]!
  check ((tail.splitOn last).length == 2) "unique end required"
  return first++(tail.splitOn last)[0]!

def proofOutput (stem : String) : IO String := do
  let path := runtimeBuild/(stem++"-lean.stdout")
  if ← path.pathExists then return ← IO.FS.readFile path
  check ((← read (runtimeBuild/(stem++".source"))) == (← read (build/(stem++".source"))) &&
    (← hash (runtimeBuild/(stem++".o"))) == (← hash (build/(stem++".o"))))
    "reused proof object differs from checked component"
  return ← IO.FS.readFile (build/(stem++"-lean.stdout"))

def originalBlock (text : String) := extractSection text "/-- A locator in historical prose" "def structureContextRanges"

def citationModule (text : String) : IO String := do
  let block ← originalBlock text
  let old ← extractSection block "def nativeReadRows (source : String)" "/-- A long interpretation"
  let header ← extractSection old "def nativeReadRows (source : String)" "  let rows := (contextRecordSpans source layout).toArray\n"
  let helper := "def nativeReadRowsUsing (rows : Array (ContextSpan source))\n"++
    "    (plans : List (String × Nat × Nat)) (records : List SourceEvidence.Record) :\n"++
    "    List (ContextSpan source × Nat) := Id.run do\n"
  let factored ← replace old header helper
  let factored ← replace factored "  let rows := (contextRecordSpans source layout).toArray\n" ""
  let factored ← replace factored "in nativeReadPrefix work do" "in plans do"
  let wrapper := header.replace ":= Id.run do\n" ":=\n"++
    "  nativeReadRowsUsing (contextRecordSpans source layout).toArray (nativeReadPrefix work) records\n\n"
  let body := (old.drop header.length).toString.trimAsciiEnd.toString
  let proof := "theorem native_read_rows_factored (source : String) (layout : Option (DecodedLayout source))\n"++
    "    (work : String) (records : List SourceEvidence.Record) :\n"++
    "    nativeReadRows source layout work records = (Id.run do\n"++
    ("\n".intercalate ((body.splitOn "\n").map ("    "++·)))++") := rfl\n\n"
  let block ← replace block old (factored++wrapper++proof)
  return "module\npublic import Eggshell.OriginalStructure\npublic import Eggshell.Matcher\npublic import Eggshell.SourceEvidence\n@[expose] public section\nnamespace Eggshell.Plugin\nopen Lean\n\n"++block++
    "\n#print axioms native_read_rows_factored\nend Eggshell.Plugin\n"

def viewSource (text : String) : IO String := do
  let text ← replace text "public import Eggshell.OriginalPresentation\n"
    "public import Eggshell.OriginalPresentation\npublic import tools.research.PublishedCitations\n"
  let text ← replace text "  recipes : Nat\n" "  recipes : Nat\n  citations : String\n"
  let fields := "  prices : Array Plugin.OriginalRecordPrice.Stored\n  deriving ToJson, FromJson"
  check ((text.splitOn fields).length == 3) "geometry and view fields changed"
  let text := text.replace fields "  prices : Array Plugin.OriginalRecordPrice.Stored\n  citations : Plugin.PublishedCitations.Metadata\n  deriving ToJson, FromJson"
  let text ← replace text "def make (database : String)" "def citationKey (digest : String) : String := \"observed-view:citations:\" ++ digest\n\ndef make (database : String)"
  let before := "  return ⟨⟨database,document.owner,document.work,ObservationContext.originalSubject document.work raw,\n    document.occurrences,characters.size,blocks.size,spans.size⟩,spans,blocks,\n      spans.map (Plugin.OriginalRecordPrice.prepare ⟨characters,rfl⟩)⟩"
  let after := "  let citations := Plugin.PublishedCitations.metadata raw document.workText\n"++
    "  let citationDigest := Sha256.hex (toJson citations).compress.toUTF8\n"++
    "  return ⟨⟨database,document.owner,document.work,ObservationContext.originalSubject document.work raw,\n"++
    "    document.occurrences,characters.size,blocks.size,spans.size,citationDigest⟩,spans,blocks,\n"++
    "      spans.map (Plugin.OriginalRecordPrice.prepare ⟨characters,rfl⟩),citations⟩"
  let text ← replace text before after
  let stage := "  let citationBytes := (toJson view.citations).compress.toUTF8\n"++
    "  unless citationBytes.size ≤ 32*1024*1024 do throw (IO.userError \"published citation geometry exceeds owner bound\")\n"++
    "  let name := citationKey view.header.citations\n"++
    "  let pinned ← writer.snapshot\n"++
    "  if (← pinned.get name).isSome then\n"++
    "    unless (← pinned.readPayload name) == citationBytes do throw (IO.userError \"conflicting published citation geometry\")\n"++
    "  else Persistence.Store.putPayload writer name citationBytes\n"
  let text ← replace text "  for index in [:view.blocks.size] do\n" (stage++"  for index in [:view.blocks.size] do\n")
  let load := "  unless digest header.citations do throw (IO.userError \"invalid published citation reference\")\n"++
    "  let name := citationKey header.citations\n"++
    "  let descriptor ← index.get name\n"++
    "  unless descriptor.isSome && (← IO.ofExcept (PageMap.payloadSize descriptor)) ≤ 32*1024*1024 do\n"++
    "    throw (IO.userError \"missing or oversized published citation geometry\")\n"++
    "  let citationBytes ← index.readPayload name\n"++
    "  unless Sha256.hex citationBytes == header.citations do throw (IO.userError \"published citation digest changed\")\n"++
    "  let citations ← ObservedRecords.decode (α := Plugin.PublishedCitations.Metadata) citationBytes\n"++
    "  if let some coordinates := citations.coordinates then\n"++
    "    unless coordinates.stored.characters == header.characters do throw (IO.userError \"citation geometry crossed original scalar\")\n"++
    "  return some ⟨header,spans,prices,citations⟩"
  let text ← replace text "  return some ⟨header,spans,prices⟩" load
  replace text "  return some ⟨header,geometry.spans,blocks,geometry.prices⟩"
    "  return some ⟨header,geometry.spans,blocks,geometry.prices,geometry.citations⟩"

def indexSource (text : String) : IO String := do
  let marker := "    (include_str \"ObservedRecordView.lean\").toUTF8,\n"
  replace text marker (marker++"    (include_str \"CitationCoordinates.lean\").toUTF8,\n"++
    "    (include_str \"Matcher.lean\").toUTF8,\n"++
    "    (include_str \"../tools/research/PreparedCitationCoordinates.lean\").toUTF8,\n"++
    "    (include_str \"../tools/research/PreparedCitationLinks.lean\").toUTF8,\n"++
    "    (include_str \"../tools/research/PublishedCitations.lean\").toUTF8,\n")

def handoffSource (text : String) : IO String := do
  let block ← originalBlock text
  let text ← replace text block ""
  let text ← replace text "public import Eggshell.SourcePlan\n"
    "public import Eggshell.SourcePlan\npublic import tools.research.PublishedCitations\n"
  let before ← extractSection text "    let referenced := if evidence.isSome then [] else focusDomain.filterMap fun item =>\n"
    "    let referencedEvidence := referenced.map"
  let after := "    let citationGeometry : Std.HashMap String Synapses.ObservedRecordView.Geometry :=\n"++
    "      ((focusBatch.map (·.palette.records)).getD #[]).foldl (fun found rows =>\n"++
    "        rows.foldl (fun found (owner,geometry) => match geometry with\n"++
    "          | none => found | some geometry => found.insert owner geometry) found) {}\n"++
    "    let parentInputs : PreparedCitationLinks.Parser × Nat := parents.foldl (fun (parser,cached) (priority,work,text) =>\n"++
    "      let original := nominationRanking[priority]?.bind fun relation => nominatedOwners.find? (·.relation == relation)\n"++
    "      let geometry := original.bind fun owner => citationGeometry[Persistence.selectionKey owner.relation]?\n"++
    "      let (links,hit) := match geometry with\n"++
    "        | some geometry => if geometry.header.work == Persistence.selectionKey work then\n"++
    "            (geometry.citations.links,1) else (PreparedCitationLinks.prepare text,0)\n"++
    "        | none => (PreparedCitationLinks.prepare text,0)\n"++
    "      (parser.insert priority (text,links),cached+hit)) ({},0)\n"++
    "    let parentParser := parentInputs.1\n"++
    "    let referenced ← if evidence.isSome then pure [] else focusDomain.filterMapM fun item => do\n"++
    "      let admitted := parents.filterMap fun (rank,work,text) =>\n"++
    "        if (sourceIncidence.neighborhood [work]).any (·.work == item.owner.work) then\n"++
    "          some (rank,text) else none\n"++
    "      if admitted.isEmpty then return none\n"++
    "      let found ← match citationGeometry[Persistence.selectionKey item.owner.relation]? with\n"++
    "        | none => pure (rankedCitedObservationCoordinates admitted item.owner item.provenance)\n"++
    "        | some geometry => do\n"++
    "          unless geometry.header.owner == Persistence.selectionKey item.owner.relation &&\n"++
    "              geometry.header.work == Persistence.selectionKey item.owner.work do\n"++
    "            throw (IO.userError \"published citations crossed their admitted Work\")\n"++
    "          IO.ofExcept (PublishedCitations.queryUsing parentParser.parse geometry.citations.coordinates item.owner item.provenance admitted)\n"++
    "      return found.map fun (priority,positions,ranks,ranges) => (item.owner.relation,priority,positions,ranks,ranges)\n"++
    "    Receipt.observe renderReceipt \"published-citation-reuse\" (Json.mkObj [\n"++
    "      (\"admitted\",toJson focusDomain.length),(\"prepared\",toJson (focusDomain.countP fun item =>\n"++
    "        citationGeometry.contains (Persistence.selectionKey item.owner.relation))),\n"++
    "      (\"parents\",toJson parents.length),(\"preparedParents\",toJson parentInputs.2),(\"geometry\",toJson citationGeometry.size)])\n"
  replace text before after

def capture (label : String) : IO Unit := do
  let monitor ← clean label
  let input ← read (runtimeRoot/(label++"-input.json"))
  let output := runtimeRoot/label
  let report ← read (output/"report.json")
  let preflight := label.endsWith "preflight"
  check (report.getObjValD "allPhasesPassed" == toJson true || (preflight &&
    (← read (output/"phase-4/result.json")).getObjValD "passed" == toJson true)) "native waves failed"
  let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (file,digest) in files do check ((← hash (database/file)) == digest) "original source changed"
  let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let mut clients : Array Json ← IO.ofExcept (fromJson? (← read (output/"prime.json")))
  let phases : Array Json ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
  for phase in phases do clients := clients++(← IO.ofExcept (phase.getObjValAs? (Array Json) "rows"))
  check (clients.size == (if preflight then 7 else 23) && clients.all (fun client =>
    client.getObjValD "success" == toJson true && client.getObjValD "bodyByteEqual" == toJson true &&
    client.getObjValD "acknowledged" == toJson true)) "all canonical bodies and acknowledgements required"
  let candidate := preflight || label.startsWith "b"
  let mut requests := #[]
  for client in clients do
    let id ← IO.ofExcept (client.getObjValAs? String "receipt")
    let folder := data/"receipts"/id
    let mut fields := [("client",client)]
    for name in ["request-pages","operation-service","published-citation-reuse"] do
      let file := folder/(name++".json")
      if ← file.pathExists then fields := fields++[(name,← read file)]
    if candidate then
      let use ← read (folder/"published-citation-reuse.json")
      let use := use.getObjValD "data"
      check (use.getObjValD "prepared" == use.getObjValD "admitted" &&
        use.getObjValD "preparedParents" == use.getObjValD "parents") "published inputs still reparse an original or parent"
    requests := requests.push (Json.mkObj fields)
  let mut fields := [("input",input),("guard",monitor),("report",report),("clients",toJson requests),
    ("warm",← read (output/"warm/stdout")),("warmRecord",← read (output/"warm/record.json")),
    ("allPublishedCoordinatesUsed",toJson candidate),("passed",toJson true),("allOriginalFilesUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  for name in ["cache-stats-prime","cache-stats-phase-4","cache-stats-phase-16","frontend-shutdown","publisher-shutdown"] do
    let file := output/(name++".json")
    if ← file.pathExists then fields := fields++[(name,← read file)]
  check (!(← (runtimeRecords/(label++".json")).pathExists)) "preserve captured trial"
  write (runtimeRecords/(label++".json")) (Json.mkObj fields)

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

partial def independentOf (path forbidden : System.FilePath) : IO Nat := do
  let actual ← IO.FS.realPath path
  check (!(actual.toString.startsWith (forbidden.toString++"/"))) "retained compiler input points at obsolete diagnostic build"
  if (← path.symlinkMetadata).type == .dir then
    let mut count := 0
    for entry in ← path.readDir do count := count+(← independentOf entry.path forbidden)
    return count
  return 1

def retireArm (label : String) : IO Unit := do
  idle
  discard <| clean label
  let record ← read (runtimeRecords/(label++".json"))
  check (record.getObjValD "passed" == toJson true) "capture trial before retirement"
  let data : System.FilePath := .mk (← IO.ofExcept ((record.getObjValD "input").getObjValAs? String "data"))
  check (data == runtimeData || data == parent/"data") "retirement escaped private fixture roots"
  for file in #[data/"publisher/endpoint.json",data/"publisher/operations.json",data/"daemon.json"] do
    check (!(← file.pathExists)) "service endpoint remains"
  let protectedPaths := #[runtimeBuild/"StudyMain",parent/"build/StudyMain",base/"snapshot-scheduling/work/work.egg/head"] ++
    (#[1,2,3].map fun n => base/"snapshot-scheduling/diagnostic"/("topic-"++toString n)/"body.txt")
  let hashes ← protectedPaths.mapM hash
  let mut deleted := #[]
  for path in #[runtimeRoot/label,data/"sessions",data/"confirmed-delivery",data/"receipts"] do
    if ← path.pathExists then
      let count ← removeOwned path
      deleted := deleted.push (path.toString,count.1,count.2)
  check ((← protectedPaths.mapM hash) == hashes) "retirement changed protected runtime or source"
  write (runtimeRecords/(label++"-retired.json")) (Json.mkObj [("deleted",toJson deleted),
    ("protectedHashesUnchanged",toJson true),("archive",toJson false)])

def compare : IO Unit := do
  idle
  check (!(← (runtimeRecords/"comparison.json").pathExists)) "preserve completed comparison"
  let fixed := fun (input : Json) => Json.mkObj (["project","sourceFiles","workspace","topics","handoffChars","counts","diagnostic"].map
    fun key => (key,input.getObjValD key))
  let fixedEnv := fun (rows : Array (String × Option String)) => rows.filter fun row =>
    !["EGGSHELL_PREFIX","PLUGIN_ROOT","EGGSHELL_CONFIG","EGGSHELL_DATA_ROOT"].contains row.1
  let original := (← read (runtimeRecords/"a-first.json")).getObjValD "input"
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
  let mut arms := #[]
  let mut before : Array Nat := #[]
  let mut after : Array Nat := #[]
  for label in #["a-first","b-first","b-second","a-second"] do
    discard <| clean label
    let result ← read (runtimeRecords/(label++".json"))
    let input := result.getObjValD "input"
    let actualEnv : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
    check (result.getObjValD "passed" == toJson true && fixed input == fixed original && fixedEnv actualEnv == fixedEnv env)
      "unmatched or failed comparison arm"
    let candidate := label.startsWith "b"
    check (input.getObjValD "data" == toJson (if candidate then runtimeData else parent/"data").toString) "producer cache scope changed"
    let expected := (← read (runtimeRecords/"runtime.json")).getObjValD (if candidate then "sha256" else "parentSha256")
    check (input.getObjValD "runtimeSha256" == expected) "unmatched executable"
    let phases : Array Json ← IO.ofExcept ((result.getObjValD "report").getObjValAs? (Array Json) "phases")
    let some small := phases.find? (fun phase => phase.getObjValD "clients" == toJson (4 : Nat)) | throw (IO.userError "missing four-client wave")
    let some large := phases.find? (fun phase => phase.getObjValD "clients" == toJson (16 : Nat)) | throw (IO.userError "missing sixteen-client wave")
    let elapsed ← IO.ofExcept (large.getObjValAs? Nat "wallMs")
    if candidate then after := after.push elapsed else before := before.push elapsed
    arms := arms.push (Json.mkObj [("arm",toJson label),("wall4Ms",small.getObjValD "wallMs"),("wall16Ms",toJson elapsed),
      ("peakRssKiB",(result.getObjValD "guard").getObjValD "sampledPeakRssKiB")])
  let mean := fun (values : Array Nat) => (values.foldl (·+·) 0).toFloat/values.size.toFloat
  write (runtimeRecords/"comparison.json") (Json.mkObj [("order",toJson #["a-first","b-first","b-second","a-second"]),("arms",toJson arms),
    ("parentMean16Ms",toJson (mean before)),("candidateMean16Ms",toJson (mean after)),
    ("descriptiveImprovementPercent",toJson (100*(mean before-mean after)/mean before)),
    ("canonicalBodiesAndAcknowledgements",toJson (99 : Nat)),("measuredSemanticAndSynapticCompletions",toJson (84 : Nat)),
    ("sameSnapshotAndSource",toJson true),("statisticalOrP99Claim",toJson false),
    ("allCandidateWavesWithin5Seconds",toJson (after.all (· ≤ 5000))),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenQualityAdoptionComparisons",toJson (0 : Nat)),("adopted",toJson false)])

def captureStopped : IO Unit := do
  idle
  let monitor ← read (base/"published-citations-b-first.guard.json")
  check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "exitCode" == toJson (137 : Nat) &&
    monitor.getObjValD "reason" == toJson "aggregate-rss" && monitor.getObjValD "guardTriggered" == toJson true &&
    monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "expected drained RSS stop"
  let input ← read (runtimeRoot/"b-first-input.json")
  check (input.getObjValD "runtimeSha256" == toJson (← hash (runtimeBuild/"StudyMain"))) "stopped runtime changed"
  let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (name,digest) in files do check ((← hash (database/name)) == digest) "stopped trial changed source"
  let output := runtimeRoot/"b-first"
  let prime ← read (output/"prime.json")
  let progress ← read (output/"progress.json")
  let mut completed := #[]
  for entry in ← (output/"phase-16").readDir do
    let file := entry.path/"result.json"
    if ← file.pathExists then completed := completed.push (← read file)
  let mut receiptData := #[]
  for entry in ← (runtimeData/"receipts").readDir do
    let mut fields := [("receipt",toJson entry.fileName)]
    for name in ["request-pages","operation-service","published-citation-reuse","search","synaptic-delivery","prepared-window-focus","canonical-source-reuse","prepared-inputs-turn"] do
      let file := entry.path/(name++".json")
      if ← file.pathExists then fields := fields++[(name,← read file)]
    if fields.length > 1 then receiptData := receiptData.push (Json.mkObj fields)
  let peak : Array Json ← IO.ofExcept (monitor.getObjValAs? (Array Json) "peakProcesses")
  for row in peak do
    let pid ← IO.ofExcept (row.getObjValAs? Nat "pid")
    let state ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid=,comm="]}
    check (state.exitCode == 1 && state.stdout.trimAscii.toString.isEmpty) "sampled stopped process still exists; inspect before cleanup"
  check (!(← (runtimeRecords/"b-first-stopped.json").pathExists)) "preserve stopped trial"
  write (runtimeRecords/"b-first-stopped.json") (Json.mkObj [("input",input),("guard",monitor),("prime",prime),
    ("completedPhases",progress),("partial16CompletedClients",toJson completed),("receipts",toJson receiptData),
    ("warm",← read (output/"warm/record.json")),("warmStdout",toJson (← IO.FS.readFile (output/"warm/stdout"))),
    ("cacheStatsAfter4",← read (output/"cache-stats-phase-4.json")),("originalFilesUnchanged",toJson true),
    ("sampledProcessesAbsent",toJson true),("whole16WaveCompleted",toJson false),("passed",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  write (runtimeRecords/"decision.json") (Json.mkObj [("decision",toJson "reject current published metadata representation at unchanged resource limit"),
    ("completedParentArms",toJson #["a-first"]),("stoppedCandidateArm",toJson "b-first"),
    ("unrunArms",toJson #["b-second","a-second"]),("paired16ImprovementPercent",Json.null),
    ("retrySameLoad",toJson false),("raiseResourceLimit",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("tokenQualityAdoptionComparisons",toJson (0 : Nat)),("adopted",toJson false)])

def retireStopped : IO Unit := do
  idle
  check (!(← (runtimeRecords/"retired.json").pathExists)) "preserve completed retirement"
  let stopped ← read (runtimeRecords/"b-first-stopped.json")
  check (stopped.getObjValD "sampledProcessesAbsent" == toJson true) "collect stopped trial first"
  let decision ← read (runtimeRecords/"decision.json")
  check (decision.getObjValD "adopted" == toJson false) "only retire unadopted trial"
  let protectedPaths := #[parent/"build/StudyMain",base/"register-rounds-runtime/build/StudyMain",
    base/"current-six/stable-source-rows/build/StudyMain",base/"current-six/fixed-sequence/controller-build/StudyMain",
    base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",base/"byte-pages-prefix/libexec/eggshell",
    base/"snapshot-scheduling/work/work.egg/head"] ++
    (#[1,2,3].map fun n => base/"snapshot-scheduling/diagnostic"/("topic-"++toString n)/"body.txt")
  let hashes ← protectedPaths.mapM hash
  let mut retained := 0
  for live in #[parent/"build/lib",base/"register-rounds-runtime/build/lib",base/"current-six/stable-source-rows/build/lib",
      base/"current-six/fixed-sequence/preparation-closure-build/lib",base/"study-local-lib"] do
    if ← live.pathExists then
      for obsolete in #[root,runtimeRoot] do retained := retained+(← independentOf live obsolete)
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "published-citations-" && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "owned experiment guard has not drained"
      guards := guards.push (entry.fileName,value)
  write (runtimeRecords/"resources.json") (toJson guards)
  let mut deleted := #[]
  for path in #[root,runtimeRoot] do
    let count ← removeOwned path
    deleted := deleted.push (path.toString,count.1,count.2)
  check ((← protectedPaths.mapM hash) == hashes) "retirement changed current runtime or originals"
  write (runtimeRecords/"retired.json") (Json.mkObj [("deleted",toJson deleted),("protectedHashesUnchanged",toJson true),
    ("retainedCompilerInputsChecked",toJson retained),("archive",toJson false),
    ("rejectedRuntimeReopenable",toJson false),("currentProjectCacheAndModelsKept",toJson true)])

def main (args : List String) : IO Unit := do
  match args with
  | ["compare"] => compare
  | ["verify-isolation"] => do
    idle
    check ((← hash (records/"PreparedCitationCoordinates.lean")) ==
      "9b783103dfa91ebd9cf924792cecc36a9b4d6623ff4b53a352c1341d052bad54") "preserved proved coordinate variant changed"
    discard <| command "/usr/bin/git" #["diff","--exit-code","--","tools/research/PreparedCitationCoordinates.lean","Eggshell"]
    let mut files := #[]
    for name in ["PreparedCitationCoordinates","PreparedCitationLinks","PublishedCitations","PublishedCitationChecks"] do
      let path := helperSource name
      files := files.push (name,path.toString,← hash path)
    write (runtimeRecords/"preserved-sources.json") (Json.mkObj [("sources",toJson files),
      ("existingCoordinateHelperRestored",toJson true),("corePatchAdopted",toJson false),
      ("variantUsedOnlyInMaterializedCandidate",toJson true),("retiredRuntimeReopenable",toJson false)])
  | ["capture-stopped"] => captureStopped
  | ["retire-stopped"] => retireStopped
  | ["verify-retirement"] => do
    check ((← read (runtimeRecords/"retired.json")).getObjValD "protectedHashesUnchanged" == toJson true) "retirement incomplete"
    guarded "verify-retirement" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(parent/"build").toString,
      (runtimeRecords/"parent-native-after-retirement.json").toString]
  | ["collect-retirement"] => do
    let monitor ← clean "verify-retirement"
    let native ← read (runtimeRecords/"parent-native-after-retirement.json")
    check (native.getObjValD "consistent" == toJson true) "retirement broke current native closure"
    let mut files := 0
    let mut bytes := 0
    for name in ["failed-retired","flat-preflight-retired","a-first-retired","retired"] do
      let rows : Array (String × Nat × Nat) ← IO.ofExcept (fromJson? ((← read (runtimeRecords/(name++".json"))).getObjValD "deleted"))
      for (_,count,size) in rows do
        files := files+count
        bytes := bytes+size
    write (runtimeRecords/"retirement-run.json") (Json.mkObj [("guard",monitor),("native",native),
      ("deletedEntries",toJson files),("deletedLogicalBytes",toJson bytes),("archive",toJson false),
      ("currentRuntimeSha256",toJson (← hash (parent/"build/StudyMain"))),("adopted",toJson false)])
  | ["capture-failed-preflight"] => do
    idle
    let monitor ← read (base/"published-citations-preflight.guard.json")
    check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "exitCode" == toJson (1 : Nat) &&
      monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat) && monitor.getObjValD "guardTriggered" == toJson false &&
      monitor.getObjValD "reason" == Json.null) "expected drained query-budget failure"
    let input ← read (runtimeRoot/"preflight-input.json")
    check (input.getObjValD "runtimeSha256" == toJson (← hash (runtimeBuild/"StudyMain"))) "failed runtime changed before capture"
    let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
    let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
    for (name,digest) in files do check ((← hash (database/name)) == digest) "failed preflight changed original source"
    let output := runtimeRoot/"preflight"
    let client ← read (output/"prime/client-0/result.json")
    let receipt ← IO.ofExcept (client.getObjValAs? String "receipt")
    let mut details := #[]
    for entry in ← (runtimeData/"receipts"/receipt).readDir do
      if entry.fileName.endsWith ".json" then details := details.push (entry.fileName,← read entry.path)
    let destination := records/"runtime/preflight-failed.json"
    check (!(← destination.pathExists)) "preserve failed trial"
    write destination (Json.mkObj [("input",input),("guard",monitor),("client",client),("receipt",toJson details),
      ("warm",← read (output/"warm/record.json")),("warmStdout",toJson (← IO.FS.readFile (output/"warm/stdout"))),
      ("stdout",toJson (← IO.FS.readFile (output/"prime/client-0/stdout"))),
      ("publisherShutdown",← read (output/"publisher-shutdown.json")),("frontendShutdown",← read (output/"frontend-shutdown.json")),
      ("budget",← read (records/"runtime/budget.json")),("originalFilesUnchanged",toJson true),
      ("failure",toJson "original view exceeds unchanged 128 MiB query budget"),
      ("answeringModelCalls",toJson (0 : Nat)),("passed",toJson false),("adopted",toJson false)])
  | ["audit","flat"] => do
    discard <| clean "packed-closed"
    guarded "audit-flat" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",driver.toString,"audit-worker","flat"]
  | ["audit-worker","flat"] => do
    let destination := records/"flat-wire-component"
    IO.FS.createDirAll destination
    let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"inspect",build.toString,(destination/"native.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"component-sources",(parent/"build").toString,
      build.toString,(destination/"sources.json").toString,"Eggshell.OriginalStructure","Eggshell.Matcher","Eggshell.SourceEvidence","Eggshell.GraphStore","Eggshell.CanonicalSourceCache"]
    let mut proofs := (← IO.FS.readFile (build/"Eggshell_CitationCoordinates-lean.stdout"))
    for name in ["PreparedCitationCoordinates","PreparedCitationLinks","PublishedCitations","PublishedCitationChecks"] do
      let (actual,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/("tools_research_"++name++".source"))))
      check (literals.isEmpty && actual == (← IO.FS.readFile (helperSource name))) "flat wire native helper mismatch"
      proofs := proofs++(← IO.FS.readFile (build/("tools_research_"++name++"-lean.stdout")))
    check (!proofs.contains "sorryAx") "unclosed flat wire proof"
    IO.FS.writeFile (destination/"axioms.txt") proofs
    write (destination/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["measure","flat"] => do
    discard <| clean "audit-flat"
    guarded "measure-flat" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(parent/"data").toString,
      (build/"StudyMain").toString,(base/"snapshot-scheduling/work/work.egg").toString,(records/"flat-wire-component/component.json").toString]
  | ["collect","flat"] => do
    let monitor ← clean "measure-flat"
    let destination := records/"flat-wire-component"
    let result ← read (destination/"component.json")
    check (result.getObjValD "allResultsEqual" == toJson true && result.getObjValD "controls" == toJson (198 : Nat)) "flat coordinate controls failed"
    check ((← read (destination/"runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "component changed"
    let input ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
    let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
    for (file,digest) in files do check ((← hash (database/file)) == digest) "component changed original source"
    write (destination/"component-run.json") (Json.mkObj [("guard",monitor),("sourceFiles",toJson files),
      ("allOriginalFilesUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["runtime-refresh"] => do
    idle
    discard <| clean "measure-flat"
    check (← (records/"runtime/preflight-failed.json").pathExists) "capture failed trial before replacement"
    IO.FS.createDirAll runtimeRecords
    for name in ["PublishedCitations","PreparedCitationCoordinates","PreparedCitationLinks"] do
      IO.FS.writeFile (runtimeSource/"tools/research"/(name++".lean")) (← IO.FS.readFile (helperSource name))
    guarded "runtime-packed" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"published-citation-runtime-settings.json").toString]
  | ["runtime-audit","flat"] => do
    discard <| clean "runtime-packed"
    metadata "runtime-packed-audit" "runtime-audit-worker"
  | ["retire-failed"] => do
    idle
    discard <| clean "runtime-packed-audit"
    let failure ← read (records/"runtime/preflight-failed.json")
    check (failure.getObjValD "passed" == toJson false && failure.getObjValD "originalFilesUnchanged" == toJson true)
      "retain failed preflight before cleanup"
    for file in #[runtimeData/"publisher/endpoint.json",runtimeData/"publisher/operations.json",runtimeData/"daemon.json"] do
      check (!(← file.pathExists)) "failed service remains"
    let protectedPaths := #[runtimeBuild/"StudyMain",parent/"build/StudyMain",base/"snapshot-scheduling/work/work.egg/head"]
    let hashes ← protectedPaths.mapM hash
    let mut retained := 0
    for live in #[runtimeBuild/"lib",parent/"build/lib",build/"lib",base/"study-local-lib"] do
      for obsolete in #[runtimeRoot/"budget-source",runtimeRoot/"budget-build"] do
        retained := retained+(← independentOf live obsolete)
    let mut removed := #[]
    for path in #[runtimeRoot/"preflight",runtimeData/"sessions",runtimeData/"confirmed-delivery",runtimeData/"receipts",runtimeData/"read-cache",
        runtimeRoot/"budget-source",runtimeRoot/"budget-build"] do
      if ← path.pathExists then
        let count ← removeOwned path
        removed := removed.push (path.toString,count.1,count.2)
    discard <| command "/bin/cp" #["-c","-R",(parent/"data/read-cache").toString,(runtimeData/"read-cache").toString]
    check ((← protectedPaths.mapM hash) == hashes) "cleanup changed protected files"
    write (runtimeRecords/"failed-retired.json") (Json.mkObj [("deleted",toJson removed),("archive",toJson false),
      ("protectedHashesUnchanged",toJson true),("retainedCompilerInputsChecked",toJson retained),("freshIsolatedCacheClone",toJson true)])
  | ["budget-setup"] => do
    idle
    materialize runtimeBuild (runtimeRoot/"budget-source") (runtimeRoot/"budget-build") "tools.research.PublishedCitationBudget" "published-citation-budget-settings.json"
    guarded "budget-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"published-citation-budget-settings.json").toString]
  | ["budget-audit"] => do
    discard <| clean "budget-build"
    metadata "budget-audit" "budget-audit-worker"
  | ["budget-audit-worker"] => do
    let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
    let target := runtimeRoot/"budget-build"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"inspect",target.toString,(runtimeRecords/"budget-native.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"component-sources",runtimeBuild.toString,target.toString,
      (runtimeRecords/"budget-sources.json").toString,"Eggshell.ObservedRecordView","Eggshell.CanonicalSourceCache","tools.research.PublishedCitations"]
  | ["budget-measure"] => do
    discard <| clean "budget-audit"
    guarded "budget-measure" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++runtimeData.toString,
      (runtimeRoot/"budget-build/StudyMain").toString,(base/"snapshot-scheduling/work/work.egg").toString,(runtimeRecords/"budget.json").toString]
  | ["capture",label] => capture label
  | ["retire-arm",label] => retireArm label
  | ["audit","links"] => do
    discard <| clean "links-checked"
    guarded "audit-links" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",driver.toString,"audit-worker","links"]
  | ["audit-worker","links"] => do
    let destination := records/"links"
    IO.FS.createDirAll destination
    let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"inspect",build.toString,(destination/"native.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"component-sources",(parent/"build").toString,
      build.toString,(destination/"sources.json").toString,"Eggshell.OriginalStructure","Eggshell.Matcher","Eggshell.SourceEvidence","Eggshell.GraphStore","Eggshell.CanonicalSourceCache"]
    let (actual,_) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/"Eggshell_CitationCoordinates.source")))
    check (actual == (← citationModule (← IO.FS.readFile (parent/"source/Eggshell/Handoff.lean")))) "actual lower layer differs from original definitions"
    let mut proofs := (← IO.FS.readFile (build/"Eggshell_CitationCoordinates-lean.stdout"))
    for name in ["PreparedCitationCoordinates","PreparedCitationLinks","PublishedCitations","PublishedCitationChecks"] do
      let (actual,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/("tools_research_"++name++".source"))))
      check (literals.isEmpty && actual == (← IO.FS.readFile (helperSource name))) "new native helper differs from checked source"
      proofs := proofs++(← IO.FS.readFile (build/("tools_research_"++name++"-lean.stdout")))
    check (!proofs.contains "sorryAx") "unclosed linked proof"
    IO.FS.writeFile (destination/"axioms.txt") proofs
    write (destination/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
      ("componentOnly",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["measure","links"] => do
    discard <| clean "audit-links"
    check ((← read (records/"links/runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "audited component changed"
    guarded "measure-links" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(parent/"data").toString,
      (build/"StudyMain").toString,(base/"snapshot-scheduling/work/work.egg").toString,(records/"links/component.json").toString]
  | ["collect","links"] => do
    let monitor ← clean "measure-links"
    let result ← read (records/"links/component.json")
    check (result.getObjValD "allResultsEqual" == toJson true && (← IO.ofExcept (result.getObjValAs? Nat "positiveOwners")) > 0) "real positive equality required"
    let input ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
    let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
    for (file,digest) in files do check ((← hash (database/file)) == digest) "original source changed"
    write (records/"links/component-run.json") (Json.mkObj [("guard",monitor),("sourceFiles",toJson files),
      ("allOriginalFilesUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["runtime-setup"] => do
    idle
    discard <| clean "measure-links"
    check ((← read (records/"links/component-run.json")).getObjValD "allOriginalFilesUnchanged" == toJson true) "collect component first"
    IO.FS.createDirAll runtimeRecords
    materialize (parent/"build") runtimeSource runtimeBuild "tools.research.OwnedSelectionRuntime" "published-citation-runtime-settings.json"
    for name in ["PublishedCitations","PreparedCitationCoordinates","PreparedCitationLinks"] do
      IO.FS.writeFile (runtimeSource/"tools/research"/(name++".lean")) (← IO.FS.readFile (helperSource name))
    IO.FS.writeFile (runtimeSource/"Eggshell/CitationCoordinates.lean") (← citationModule (← IO.FS.readFile (parent/"source/Eggshell/Handoff.lean")))
    for (name,transform) in [("Handoff",handoffSource),("ObservedRecordView",viewSource),("SynapseIndex",indexSource)] do
      let path := runtimeSource/"Eggshell"/(name++".lean")
      IO.FS.writeFile path (← transform (← IO.FS.readFile path))
    copyLocalArtifacts build runtimeBuild
    write (runtimeRecords/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
      ("component",← read (records/"links/component.json")),("directChanges",toJson #["Eggshell.Handoff","Eggshell.ObservedRecordView","Eggshell.SynapseIndex"]),
      ("added",toJson #["Eggshell.CitationCoordinates","tools.research.PreparedCitationCoordinates","tools.research.PreparedCitationLinks","tools.research.PublishedCitations"]),
      ("atomicWithOriginalGeometry",toJson true),("existingImageCapacityAccountsNewMetadata",toJson true),
      ("preservesPrivateQuestionAndFederatedProvenance",toJson true),("newCacheOrPool",toJson false),
      ("originalExpressionsRelocatedNotDeleted",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guarded "runtime-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"published-citation-runtime-settings.json").toString]
  | ["runtime-audit"] => do
    discard <| clean "runtime-build"
    metadata "runtime-audit" "runtime-audit-worker"
  | ["runtime-audit-worker"] => do
    let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"inspect",runtimeBuild.toString,(runtimeRecords/"native.json").toString]
    let matcher := runtimeSource/"Eggshell/Matcher.lean"
    let claim := "@"++(← hash matcher)++":"++matcher.toString
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"compare-sources",(parent/"build").toString,
      runtimeBuild.toString,(runtimeRecords/"sources.json").toString,"Eggshell.Handoff","Eggshell.ObservedRecordView","Eggshell.SynapseIndex",
      "+Eggshell.CitationCoordinates","+tools.research.PreparedCitationCoordinates","+tools.research.PreparedCitationLinks","+tools.research.PublishedCitations",claim]
    for (name,transform) in [("Handoff",handoffSource),("ObservedRecordView",viewSource),("SynapseIndex",indexSource)] do
      let (actual,_) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (runtimeBuild/("Eggshell_"++name++".source"))))
      check (actual == (← transform (← IO.FS.readFile (parent/"source/Eggshell"/(name++".lean"))))) "actual consumer differs from reviewed transformation"
      let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0",(parent/"source/Eggshell"/(name++".lean")).toString,(runtimeSource/"Eggshell"/(name++".lean")).toString]}
      check (diff.exitCode == 1) "expected explicit producer/consumer patch"
      IO.FS.writeFile (runtimeRecords/(name++".patch")) diff.stdout
    check ((← read (parent/"build/tools_research_OwnedSelectionRuntime.source")) ==
      (← read (runtimeBuild/"tools_research_OwnedSelectionRuntime.source"))) "native capacity harness changed"
    let (actual,_) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (runtimeBuild/"Eggshell_CitationCoordinates.source")))
    check (actual == (← citationModule (← IO.FS.readFile (parent/"source/Eggshell/Handoff.lean")))) "relocated citation definitions changed"
    let mut proofs ← proofOutput "Eggshell_CitationCoordinates"
    for name in ["PreparedCitationCoordinates","PreparedCitationLinks","PublishedCitations"] do
      let (actual,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (runtimeBuild/("tools_research_"++name++".source"))))
      check (literals.isEmpty && actual == (← IO.FS.readFile (helperSource name))) "product helper differs from proved source"
      proofs := proofs++(← proofOutput ("tools_research_"++name))
    check (!proofs.contains "sorryAx") "unclosed actual product proof"
    IO.FS.writeFile (runtimeRecords/"axioms.txt") proofs
    write (runtimeRecords/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (runtimeBuild/"StudyMain"))),
      ("parentSha256",toJson (← hash (parent/"build/StudyMain"))),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["install"] => do
    discard <| clean "runtime-audit"
    metadata "install" "install-worker"
  | ["install-worker"] => do
    check (!(← runtimePrefix.pathExists) && !(← runtimeData.pathExists)) "fresh installation/cache required"
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
    check ((← IO.FS.realPath (runtimeData/"read-cache")) != (← IO.FS.realPath (parent/"data/read-cache"))) "cache aliases parent"
  | ["prepare",label] => do
    discard <| clean "install"
    let order := #["a-first","b-first","b-second","a-second"]
    let preflight := label.endsWith "preflight"
    if !preflight then
      let some position := order.findIdx? (· == label) | throw (IO.userError "undeclared comparison arm")
      let prior := if position == 0 then "flat-preflight" else order[position-1]!
      discard <| clean prior
      check ((← read (runtimeRecords/(prior++".json"))).getObjValD "passed" == toJson true) "collect previous arm first"
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
    check (!(← path.pathExists)) "preserve existing trial"
    write path input
    let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
    guarded label (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++#[executable.toString,"owned-selection-capacity",path.toString])
  | ["refresh"] => do
    idle
    check (!(← (base/"published-citations-build.guard.json").pathExists)) "refresh only before build"
    IO.FS.writeFile (source/"Eggshell/CitationCoordinates.lean") (← citationModule (← IO.FS.readFile (parent/"source/Eggshell/Handoff.lean")))
  | ["setup"] => do
    idle
    check (!(← root.pathExists) && !(← records.pathExists)) "fresh component required"
    check ((← hash (parent/"build/StudyMain")) == "7cc1432d2d3931a26d60e3e614807545e3f6b522737838bdabc1b1c626e657ab") "protected parent changed"
    IO.FS.createDirAll records
    materialize (parent/"build") source build "tools.research.PublishedCitationChecks" "published-citations-settings.json"
    IO.FS.writeFile (source/"Eggshell/CitationCoordinates.lean") (← citationModule (← IO.FS.readFile (parent/"source/Eggshell/Handoff.lean")))
    for name in ["PublishedCitations","PreparedCitationCoordinates"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (helperSource name))
    write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
      ("hypothesis",toJson "publish original row coordinates and static read plans in existing original views; keep question/rank and federated provenance dynamic"),
      ("reuseExistingCitationProof",toJson true),("oldComponentOnlyHadNoCompletedParents",toJson true),
      ("allParentComponentIsNotQuestionNomination",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guarded "build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"published-citations-settings.json").toString]
  | ["rebuild",label] => do
    idle
    for name in ["PublishedCitations","PreparedCitationCoordinates","PreparedCitationLinks","PublishedCitationChecks"] do
      IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (helperSource name))
    guarded label #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"published-citations-settings.json").toString]
  | ["audit"] => do
    discard <| clean "proof-closed"
    metadata "audit" "audit-worker"
  | ["audit-worker"] => do
    let inspector := project/"tools/research/StudyBuildClosureAudit.lean"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"inspect",build.toString,(records/"native.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",inspector.toString,"component-sources",(parent/"build").toString,
      build.toString,(records/"sources.json").toString,"Eggshell.OriginalStructure","Eggshell.Matcher","Eggshell.SourceEvidence","Eggshell.GraphStore","Eggshell.CanonicalSourceCache"]
    let (actual,_) : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/"Eggshell_CitationCoordinates.source")))
    check (actual == (← citationModule (← IO.FS.readFile (parent/"source/Eggshell/Handoff.lean")))) "actual lower layer differs from original definitions and factored proof"
    IO.FS.writeFile (records/"CitationCoordinates.lean") actual
    let mut proofs := (← IO.FS.readFile (build/"Eggshell_CitationCoordinates-lean.stdout"))
    for name in ["PreparedCitationCoordinates","PublishedCitations","PublishedCitationChecks"] do
      let (actual,literals) : String × Array (String × String) ← IO.ofExcept
        (fromJson? (← read (build/("tools_research_"++name++".source"))))
      check (literals.isEmpty && actual == (← IO.FS.readFile (helperSource name))) "new native helper differs from checked source"
      proofs := proofs++(← IO.FS.readFile (build/("tools_research_"++name++"-lean.stdout")))
    check (!proofs.contains "sorryAx") "unclosed production proof"
    IO.FS.writeFile (records/"axioms.txt") proofs
    write (records/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
      ("componentOnly",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | ["measure"] => do
    discard <| clean "audit"
    check ((← read (records/"runtime.json")).getObjValD "sha256" == toJson (← hash (build/"StudyMain"))) "native component changed"
    let input ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
    let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
    for (file,digest) in files do check ((← hash (database/file)) == digest) "original source changed before component"
    guarded "measure" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(parent/"data").toString,
      (build/"StudyMain").toString,database.toString,(records/"component.json").toString]
  | ["collect"] => do
    let guard ← clean "measure"
    let component ← read (records/"component.json")
    let positives ← IO.ofExcept (component.getObjValAs? Nat "positiveOwners")
    check (positives > 0 && component.getObjValD "allResultsEqual" == toJson true) "positive real citation equality required"
    let input ← read (base/"snapshot-scheduling/capacity-16-input.json")
    let database : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
    let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
    for (file,digest) in files do check ((← hash (database/file)) == digest) "component changed original files"
    write (records/"component-run.json") (Json.mkObj [("guard",guard),("sourceFiles",toJson files),
      ("allOriginalFilesUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  | _ => throw (IO.userError "published-citations-study setup|rebuild LABEL")
end PublishedCitationStudy
def main := PublishedCitationStudy.main
