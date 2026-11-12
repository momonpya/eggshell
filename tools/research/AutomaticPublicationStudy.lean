import tools.research.StudyLocal
open Lean StudyLocal
namespace AutomaticPublicationStudy
def productRoot := base/"practical-runtime/terminal-closure"
def root := base/"practical-runtime/automatic-publication"
def records := project/"docs/practical-runtime/automatic-publication"
def guard (tag : String) (args : Array String) : IO Unit := do
  StudyLocal.guard tag args
  let path := base/(tag++".guard-settings.json")
  write path ((← read path).setObjVal! "ownedPrefixes" (toJson #[root.toString,productRoot.toString]))

def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh automatic publication trial required"
  check ((← hash (productRoot/"build/StudyMain")) == "302ead2043af3ba3764668652f5543cdf330ca0dae16ac27784b7536ab116338") "fixed product changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(productRoot/"source").toString,(root/"source").toString]
  for name in ["AutomaticPublicationChecks","AutomaticPublicationMain"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  copyLocalArtifacts (productRoot/"build") (root/"build")
  let settings := (← read (productRoot/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(productRoot/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (productRoot/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (productRoot/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (productRoot/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.AutomaticPublicationMain")
    |>.setObjVal! "force" (toJson (#[] : Array String))
  write (root/"build-settings.json") settings
  write (records/"plan.json") (Json.mkObj [("runtimeSha256",toJson (← hash (productRoot/"build/StudyMain"))),
    ("projects",toJson (2 : Nat)),("ownersPerProject",toJson (4 : Nat)),("baselineWriters",toJson (4 : Nat)),
    ("incrementalWaves",toJson (3 : Nat)),("concurrentWriters",toJson (4 : Nat)),("concurrentReaders",toJson (10 : Nat)),
    ("freshReaderWaves",toJson (4 : Nat)),("maxSimultaneousClients",toJson (14 : Nat)),
    ("manualWarmCalls",toJson (0 : Nat)),("manualKeepCalls",toJson (0 : Nat)),
    ("emptyInitialDatabases",toJson true),("readOnlyReadinessProbe",toJson true),
    ("freezeOriginalsBeforeDelivery",toJson true),("answeringModelCalls",toJson (0 : Nat)),("productChanges",toJson (0 : Nat)),
    ("adopted",toJson false)])
  guard "automatic-publication-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]

def audit : IO Unit := do
  idle
  discard <| finished "automatic-publication-build"
  for args in [#["inspect",(root/"build").toString,(records/"native.json").toString],
      #["subset-sources",(productRoot/"build").toString,(root/"build").toString,
        (records/"sources.json").toString,"Main","Eggshell.PluginHooks","Eggshell.PublicationService",
        "Eggshell.PreparationRegistry","Eggshell.Warm","Eggshell.PreparedInputs"]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))

def run : IO Unit := do
  idle
  check ((← read (records/"native.json")).getObjValD "consistent" == toJson true &&
    (← read (records/"sources.json")).getObjValD "nativeSubsetSourcesExact" == toJson true) "native consumer must match the fixed product"
  let installation ← read (productRoot/"installation.json")
  write (root/"installation.json") installation
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let updates := #[("EGGSHELL_DATA_ROOT",some (root/"run/data").toString),("TMPDIR",some (root/"tmp").toString)]
  IO.FS.createDirAll (root/"tmp")
  let environment := environment.filter (fun row => !updates.any (·.1 == row.1))++updates
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := environment.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  guard "automatic-publication-flow" (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "automatic-publication",(records/"flow.stdout").toString,(records/"flow.stderr").toString,"/usr/bin/env"]++
    unset.flatMap (fun key => #["-u",key])++assigned++#[(root/"build/StudyMain").toString,
      "check",(root/"installation.json").toString,(root/"run").toString])

/-- Metadata for this synthetic fixture's declared filenames, not a product
parser or a command/output recognition rule. -/
def expectedPath (line : String) : Except String String := do
  let some symbol := (line.splitOn " ")[1]? | throw "fixture source field has no identifier"
  let [group,"SUPPORT",wave,slot,kind] := symbol.splitOn "_" | throw "unexpected fixture identifier"
  unless kind == "BASE" || kind == "DETAIL" do throw "unexpected fixture field"
  return s!"src/{group}_{wave}_{slot}.cpp"

/-- Inspect the product's rendered SOURCE/CODE envelope, not tool syntax.
The original row must occur inside the block carrying its own file identity;
an unrelated path or a saved-position-only entry does not count. -/
def sourceBlockContains (body path fingerprint original : String) : Bool :=
  ((body.splitOn "\nSOURCE ").drop 1).any fun block => Id.run do
    let header := (block.splitOn "\n").headD ""
    let .ok source := Json.parse header | return false
    if source.getObjValD "relative" != toJson path || source.getObjValD "fingerprint" != toJson fingerprint then
      return false
    let some code := ((block.splitOn "\nCODE\n").drop 1).head? | return false
    return (code.splitOn "\n").any fun row =>
      match row.splitOn "\t" with
      | number :: pieces => number.toNat?.isSome && "\t".intercalate pieces == original
      | _ => false

def sourceBlockAudit (queries fingerprints output : String) : IO Unit := do
  idle
  check (!(← (System.FilePath.mk output).pathExists)) "retain the first source-block audit"
  let sourceData ← read (.mk fingerprints)
  let sources : Array Json ← match sourceData.getArr? with
    | .ok values => pure values
    | .error _ => IO.ofExcept (sourceData.getObjValAs? (Array Json) "fingerprints")
  let values ← IO.ofExcept ((← read (.mk queries)).getArr?)
  let mut rows := #[]
  let mut eligible := 0
  let mut delivered := 0
  for query in values do
    let bodyPath : String ← IO.ofExcept (query.getObjValAs? _ "body")
    let body ← IO.FS.readFile (.mk bodyPath)
    let required : Array String ← IO.ofExcept (query.getObjValAs? _ "required")
    let mut missing := #[]
    for line in required do
      let path ← IO.ofExcept (expectedPath line)
      let some source := sources.find? (·.getObjValD "path" == toJson path) |
        throw (IO.userError "native source fingerprint missing from block audit")
      let fingerprint : String ← IO.ofExcept ((source.getObjValD "content").getObjValAs? _ "root")
      if !sourceBlockContains body path fingerprint line then missing := missing.push line
    eligible := eligible+required.size
    delivered := delivered+required.size-missing.size
    rows := rows.push (Json.mkObj [("session",query.getObjValD "session"),("eligible",toJson required.size),
      ("boundOriginalRows",toJson (required.size-missing.size)),("missing",toJson missing)])
  write (.mk output) (Json.mkObj [("queries",toJson rows),("eligibleFields",toJson eligible),
    ("rowsInsideMatchingSourceBlocks",toJson delivered),("ok",toJson (delivered == eligible))])
  check (delivered == eligible && eligible > 0) "an original row lacks its own delivered source block"

def callbackAudit (input output : String) : IO Unit := do
  idle
  check (!(← (System.FilePath.mk output).pathExists)) "retain the first callback audit"
  let calls ← IO.ofExcept ((← read (.mk input)).getArr?)
  let mut incomplete := #[]
  let mut events : Array (String × Array Nat) := #[]
  for call in calls do
    let event : String ← IO.ofExcept ((call.getObjValD "request").getObjValAs? _ "hook_event_name")
    let elapsed : Nat ← IO.ofExcept ((call.getObjValD "timing").getObjValAs? _ "elapsedMs")
    let path : String ← IO.ofExcept (call.getObjValAs? _ "stdout")
    let body ← IO.FS.readFile (.mk path)
    if body.contains "EGGSHELL SEARCH INCOMPLETE" ||
        (call.getObjValD "timing").getObjValD "exitCode" != toJson (0 : Nat) ||
        call.getObjValD "stderr" != toJson "" then incomplete := incomplete.push call
    let values := (events.find? (·.1 == event)).map (·.2) |>.getD #[]
    events := (events.filter (·.1 != event)).push (event,values.push elapsed)
  let rows := events.map fun (event,values) => Id.run do
    let sorted := values.qsort (· < ·)
    return Json.mkObj [("event",toJson event),("count",toJson sorted.size),
      ("p50Ms",toJson sorted[(sorted.size*50+99)/100-1]!),
      ("p95Ms",toJson sorted[(sorted.size*95+99)/100-1]!),
      ("maxMs",toJson sorted[sorted.size-1]!)]
  write (.mk output) (Json.mkObj [("calls",toJson calls.size),("events",toJson rows),
    ("failedOrIncompleteCallbacks",toJson incomplete),
    ("fixtureOnlyNotProductionP99",toJson true)])
  check (incomplete.isEmpty && calls.size > 0) "callback audit found an incomplete or failed actual response"

def retainAt (root records : System.FilePath) (monitor : Json)
    (sourceFingerprints : Array Json) (productChanges : Nat) : IO Unit := do
  let area := root/"run"
  for entry in ← area.readDir do
    if (← entry.path.symlinkMetadata).type == .file && entry.fileName.endsWith ".json" then
      write (records/entry.fileName) (← read entry.path)
  write (records/"flow.guard.json") monitor
  IO.FS.createDirAll (records/"responses")
  IO.FS.createDirAll (records/"bodies")
  let mut calls := #[]
  let mut queries := #[]
  let mut eligible := 0
  let mut delivered := 0
  let mut attributed := 0
  let mut semantic := 0
  let mut warnings := #[]
  for session in ← (area/"calls").readDir do
    if (← session.path.symlinkMetadata).type != .dir then continue
    for call in ← session.path.readDir do
      if (← call.path.symlinkMetadata).type != .dir || !(← (call.path/"registration.json").pathExists) then continue
      let output := call.path/"stdout"
      let digest ← hash output
      let retained := records/"responses"/(digest++".json")
      unless ← retained.pathExists do IO.FS.writeBinFile retained (← IO.FS.readBinFile output)
      let timing ← read (call.path/"record.json")
      check (timing.getObjValD "stdoutSha256" == toJson digest) "actual hook output changed before retention"
      let stderr ← IO.FS.readFile (call.path/"stderr")
      unless stderr.isEmpty do warnings := warnings.push (session.fileName,call.fileName,stderr)
      let request ← read (call.path/"stdin")
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("request",request),("timing",timing),("stdout",toJson retained.toString),
        ("stderr",toJson stderr),("registration",← read (call.path/"registration.json"))])
      unless session.fileName.startsWith "automatic-reader-" && call.fileName == "prompt" do continue
      let ["automatic","reader",kind,wave,_] := session.fileName.splitOn "-" |
        throw (IO.userError "unexpected reader fixture session")
      let prompt : String ← IO.ofExcept (request.getObjValAs? _ "prompt")
      let group := if prompt.contains "ALPHA_SUPPORT" then "ALPHA" else "BETA"
      let frozen ← IO.ofExcept ((← read (area/s!"frozen-{wave}-{kind}.json")).getArr?)
      let some expected := frozen.find? (·.getObjValD "group" == toJson group) | throw (IO.userError "reader has no frozen source evidence")
      check (expected.getObjValD "sourceVerifiedBeforeDelivery" == toJson true) "source was not frozen before query admission"
      let required : Array String ← IO.ofExcept (expected.getObjValAs? _ "required")
      let reply ← read output
      let body : String ← IO.ofExcept ((reply.getObjValD "hookSpecificOutput").getObjValAs? _ "additionalContext")
      let bodyFile := session.path/"body.txt"
      check ((← IO.FS.readFile bodyFile) == body) "actual callback and audited body differ"
      let bodyDigest ← hash bodyFile
      let bodyRetained := records/"bodies"/(bodyDigest++".txt")
      unless ← bodyRetained.pathExists do IO.FS.writeFile bodyRetained body
      let missing := required.filter (!body.contains ·)
      let mut withSource := 0
      for line in required do
        let path ← IO.ofExcept (expectedPath line)
        let some source := sourceFingerprints.find? (·.getObjValD "path" == toJson path) |
          throw (IO.userError "native source fingerprints must be inspected before retention")
        let fingerprint : String ← IO.ofExcept ((source.getObjValD "content").getObjValAs? _ "root")
        if body.contains line && body.contains path && body.contains fingerprint then
          withSource := withSource+1
      eligible := eligible+required.size
      delivered := delivered+required.size-missing.size
      attributed := attributed+withSource
      let state ← read (area/"data/sessions"/session.fileName/"state.json")
      let search := state.getObjValD "lastSearch"
      if search.getObjValD "semantic" == toJson "completed" then semantic := semantic+1
      let privateFiles := area/"data/sessions"/session.fileName
      check ((← (privateFiles/"closed").readDir).size == 1) "reader closure was not retained"
      for closed in ← (privateFiles/"closed").readDir do
        check ((← read closed.path).getObjValD "write" == Json.null) "reader acquired a publication target"
      check (!(← (privateFiles/"observed-files").pathExists)) "readonly reader retained source file capture"
      for name in ["deferred","checkpoints","terminal-intents"] do
        if ← (privateFiles/name).pathExists then
          check ((← (privateFiles/name).readDir).isEmpty) "readonly reader retained source publication work"
      queries := queries.push (Json.mkObj [("session",toJson session.fileName),("kind",toJson kind),
        ("wave",toJson wave),("group",toJson group),("required",toJson required),
        ("missing",toJson missing),("attributedFields",toJson withSource),("search",search),
        ("body",toJson bodyRetained.toString),("bodySha256",toJson bodyDigest),
        ("stdout",toJson retained.toString),("stdoutSha256",toJson digest),("timing",timing)])
  check (queries.size == 70 && semantic == 70 && delivered == eligible) "independent delivery audit did not pass every query"
  write (records/"registered-calls.json") (toJson calls)
  write (records/"queries.json") (toJson queries)
  write (records/"client-warnings.json") (toJson warnings)
  let mut failedReceipts := #[]
  for receipt in ← (area/"data/receipts").readDir do
    if (← receipt.path.symlinkMetadata).type != .dir || !(← (receipt.path/"failure.json").pathExists) then continue
    let mut stages := #[]
    for name in ["request","ingress","dispatch","failure","published","returned"] do
      if ← (receipt.path/(name++".json")).pathExists then
        stages := stages.push (name,← read (receipt.path/(name++".json")))
    failedReceipts := failedReceipts.push (Json.mkObj [("receipt",toJson receipt.fileName),("stages",toJson stages)])
  write (records/"failed-receipts.json") (toJson failedReceipts)
  let result ← read (records/"result.json")
  let waves ← IO.ofExcept (result.getObjValAs? (Array Json) "waves")
  let summary := Json.mkObj [("runtime",result.getObjValD "runtime"),("projects",toJson (2 : Nat)),
    ("queries",toJson queries.size),("semanticCompleted",toJson semantic),("eligibleFields",toJson eligible),
    ("deliveredFields",toJson delivered),("fieldsWithPathAndFingerprint",toJson attributed),
    ("freshQueryWaveMs",toJson (waves.map (·.getObjValD "freshMs"))),
    ("overlapWaveMs",toJson (waves.extract 1 waves.size |>.map (·.getObjValD "overlapMs"))),
    ("automaticPreparation",toJson (waves.map fun row => Json.mkObj [("wave",row.getObjValD "wave"),
      ("alphaMs",(row.getObjValD "alphaPreparation").getObjValD "elapsedMs"),
      ("betaMs",(row.getObjValD "betaPreparation").getObjValD "elapsedMs")])),
    ("manualWarmCalls",toJson (0 : Nat)),("manualKeepCalls",toJson (0 : Nat)),
    ("maxSimultaneousClients",toJson (14 : Nat)),("clientWarnings",toJson warnings.size),
    ("failedReceipts",toJson failedReceipts.size),
    ("serviceStderr",toJson (← IO.FS.readFile (records/"flow.stderr"))),
    ("peakRssKiB",monitor.getObjValD "sampledPeakRssKiB"),("answeringModelCalls",toJson (0 : Nat)),
    ("productChanges",toJson productChanges),("adopted",toJson false),
    ("fingerprintAlgorithm",toJson "SourceEvidence.fingerprint: length-bound BLAKE3 page chain"),
    ("allHookCallbacksClean",toJson warnings.isEmpty)]
  write (records/"summary.json") summary
  IO.println summary.compress

def retain : IO Unit := do
  idle
  let monitor ← finished "automatic-publication-flow"
  let sourceFingerprints ← IO.ofExcept ((← read (records/"postmortem.json")).getObjValAs? (Array Json) "fingerprints")
  retainAt root records monitor sourceFingerprints 0

def retainOther (root records tag fingerprints changes : String) : IO Unit := do
  idle
  let monitor ← finished tag
  let values ← IO.ofExcept ((← read (.mk fingerprints)).getArr?)
  let some count := changes.toNat? | throw (IO.userError "invalid product change count")
  retainAt (.mk root) (.mk records) monitor values count

def preparePostmortem : IO Unit := do
  idle
  discard <| finished "automatic-publication-flow"
  check ((← read (records/"summary.json")).getObjValD "clientWarnings" == toJson (1 : Nat)) "preserve the observed hook warning first"
  IO.FS.writeFile (root/"source/tools/research/AutomaticPublicationAudit.lean")
    (← IO.FS.readFile (project/"tools/research/AutomaticPublicationAudit.lean"))
  copyLocalArtifacts (productRoot/"build") (root/"audit-build")
  let settings := (← read (root/"build-settings.json"))
    |>.setObjVal! "output" (toJson (root/"audit-build").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.AutomaticPublicationAudit")
  write (root/"audit-build-settings.json") settings
  guard "automatic-publication-audit-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"audit-build-settings.json").toString]

def postmortem : IO Unit := do
  idle
  discard <| finished "automatic-publication-audit-build"
  IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(root/"audit-build").toString,
    (records/"postmortem-native.json").toString])
  guard "automatic-publication-postmortem" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(root/"run/data").toString,
    (root/"audit-build/StudyMain").toString,"audit",(root/"run").toString,
    (records/"postmortem.json").toString,(root/"atomic-replacement-probe").toString]

def correctFingerprintAudit : IO Unit := do
  idle
  discard <| finished "automatic-publication-postmortem"
  let postmortem ← read (records/"postmortem.json")
  let fingerprints ← IO.ofExcept (postmortem.getObjValAs? (Array Json) "fingerprints")
  let queries ← IO.ofExcept ((← read (records/"queries.json")).getArr?)
  let mut checked := #[]
  let mut count := 0
  for query in queries do
    let bodyName : String ← IO.ofExcept (query.getObjValAs? _ "body")
    let body ← IO.FS.readFile (.mk bodyName)
    let required : Array String ← IO.ofExcept (query.getObjValAs? _ "required")
    let mut attributed := 0
    for line in required do
      let path ← IO.ofExcept (expectedPath line)
      let some source := fingerprints.find? (·.getObjValD "path" == toJson path) |
        throw (IO.userError "source fingerprint was not independently inspected")
      let fingerprint : String ← IO.ofExcept ((source.getObjValD "content").getObjValAs? _ "root")
      if body.contains line && body.contains path && body.contains fingerprint then attributed := attributed+1
    count := count+attributed
    checked := checked.push (query.setObjVal! "attributedFields" (toJson attributed))
  let initial ← read (records/"summary.json")
  let final := initial.setObjVal! "fieldsWithPathAndFingerprint" (toJson count)
    |>.setObjVal! "fingerprintAlgorithm" (toJson "SourceEvidence.fingerprint: length-bound BLAKE3 page chain")
    |>.setObjVal! "allHookCallbacksClean" (toJson false)
  write (records/"checked-queries.json") (toJson checked)
  write (records/"checked-summary.json") final
  write (records/"audit-correction.json") (Json.mkObj [("originalAuditRetained",toJson true),
    ("reason",toJson "the first attribution audit compared source fingerprints to SHA-256; the product uses a length-bound BLAKE3 page chain"),
    ("nativeFingerprintInspection",toJson (records/"postmortem.json").toString),
    ("experimentReplayed",toJson false),("productChanged",toJson false)])
  IO.println final.compress

partial def files (path : System.FilePath) : IO (Array System.FilePath) := do
  if (← path.symlinkMetadata).type != .dir then return #[path]
  let mut result := #[]
  for entry in ← path.readDir do result := result++(← files entry.path)
  return result

partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,metadata.byteSize.toNat)
  let mut total := (1,0)
  for entry in ← path.readDir do
    let next ← remove entry.path
    total := (total.1+next.1,total.2+next.2)
  IO.FS.removeDir path
  return total

def retireArtifacts (records productRoot : System.FilePath) (targets : Array System.FilePath) : IO Unit := do
  idle
  check (!(← (records/"retired.json").pathExists)) "retain the first cleanup record"
  let retiredPath := fun (text : String) => targets.any fun target =>
    text == target.toString || text.startsWith (target.toString++"/")
  let builds := #[productRoot/"build",base/"practical-runtime/terminal-closure/build",base/"practical-runtime/terminal-intent/build",
    base/"practical-runtime/terminal-capture/build",base/"practical-runtime/readonly-save/build",
    base/"practical-runtime/block-seek/build",base/"practical-runtime/build",
    base/"practical-runtime/independent-maintenance/build",base/"practical-runtime/coordinated-warm/build",
    base/"canonical-decoder-runtime/build"]
  let protectedRuntimes ← builds.mapM fun directory => do pure (directory/"StudyMain",← hash (directory/"StudyMain"))
  for directory in builds do
    for line in (← IO.FS.readFile (directory/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      if path.isAbsolute then check (!retiredPath (← IO.FS.realPath path).toString) "live native input is a cleanup target"
    for path in ← files (directory/"lib") do
      if (← path.symlinkMetadata).type == .symlink then
        check (!retiredPath (← IO.FS.realPath path).toString) "live interface is a cleanup target"
  check (!retiredPath (← IO.FS.realPath (productRoot/"prefix/share/eggshell/minilm")).toString) "model is a cleanup target"
  let original ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let source : String ← IO.ofExcept (original.getObjValAs? _ "source")
  let originalFiles : Array (String × String) ← IO.ofExcept (original.getObjValAs? _ "sourceFiles")
  for (name,digest) in originalFiles do check ((← hash (System.FilePath.mk source/name)) == digest) "original source changed"
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any fun line => targets.any (fun target => line.contains target.toString))
    "cleanup target still belongs to a process"
  let mut removed := (0,0)
  for path in targets do
    if !(← path.pathExists) then continue
    let next ← remove path
    removed := (removed.1+next.1,removed.2+next.2)
  for (path,digest) in protectedRuntimes do check ((← hash path) == digest) "protected runtime changed"
  for (name,digest) in originalFiles do check ((← hash (System.FilePath.mk source/name)) == digest) "original changed during cleanup"
  for entry in ← records.readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
      if (← entry.path.metadata).byteSize == 0 then IO.FS.removeFile entry.path
  write (records/"retired.json") (Json.mkObj [("files",toJson removed.1),("logicalBytes",toJson removed.2),
    ("archiveCreated",toJson false),("sourceAndRuntimeHashesUnchanged",toJson true),
    ("nativeInputsAndInterfacesOutsideRetiredTargets",toJson true)])
  IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(productRoot/"build").toString,
    (records/"product-after-cleanup.json").toString])

def checkRetainedQueries (path : System.FilePath) : IO Unit := do
  for query in ← IO.ofExcept ((← read path).getArr?) do
    for (field,digest) in [("body","bodySha256"),("stdout","stdoutSha256")] do
      let path : String ← IO.ofExcept (query.getObjValAs? _ field)
      check (toJson (← hash (.mk path)) == query.getObjValD digest) "retained callback bytes changed"

def retire : IO Unit := do
  idle
  for tag in ["build","flow","audit-build","postmortem"] do
    write (records/(tag++".guard.json")) (← finished ("automatic-publication-"++tag))
  let summary ← read (records/"checked-summary.json")
  check (summary.getObjValD "fieldsWithPathAndFingerprint" == toJson (640 : Nat) &&
    summary.getObjValD "allHookCallbacksClean" == toJson false) "retain delivery and callback failure separately"
  let receipt := "fb1d84810c55f1ec7f40422f3d16262e91ce787e239205ea3f348bc204e2cf98"
  let mut stages := #[]
  for name in ["request","ingress","dispatch","failure","published"] do
    stages := stages.push (name,← read (root/"run/data/receipts"/receipt/(name++".json")))
  write (records/"failed-pre-receipt.json") (Json.mkObj [("receipt",toJson receipt),("stages",toJson stages)])
  checkRetainedQueries (records/"checked-queries.json")
  retireArtifacts records productRoot #[root/"run",root/"source",root/"build",root/"audit-build",root/"tmp",root/"atomic-replacement-probe"]

def retireProduct (location evidence : String) (tags : List String) : IO Unit := do
  idle
  let root : System.FilePath := .mk location
  let records : System.FilePath := .mk evidence
  check (root.isAbsolute && root.toString.startsWith (base.toString++"/practical-runtime/")) "candidate cleanup escaped experiment scope"
  check (!tags.isEmpty) "all candidate stages must have terminal evidence"
  for tag in tags do write (records/(tag++".guard.json")) (← finished tag)
  let summary ← read (records/"summary.json")
  check (summary.getObjValD "fieldsWithPathAndFingerprint" == summary.getObjValD "eligibleFields") "retained attribution failed"
  check ((← read (records/"source-blocks.json")).getObjValD "ok" == toJson true) "source-block audit must precede cleanup"
  checkRetainedQueries (records/"queries.json")
  retireArtifacts records root #[root/"run",root/"checks",root/"checks-build",root/"tmp",root/"helper-lib",root/"launcher.lean",root/"laws.lean"]

def retireTrial (location evidence product : String) (tags : List String) : IO Unit := do
  idle
  let root : System.FilePath := .mk location
  let records : System.FilePath := .mk evidence
  let productRoot : System.FilePath := .mk product
  check (root.isAbsolute && root.toString.startsWith (base.toString++"/practical-runtime/") &&
    !productRoot.toString.startsWith (root.toString++"/") && productRoot != root &&
    !records.toString.startsWith (root.toString++"/")) "trial cleanup overlaps its product or retained evidence"
  check (!tags.isEmpty) "all trial stages need terminal evidence"
  for tag in tags do write (records/(tag++".guard.json")) (← finished tag)
  check ((← read (records/"hook-callbacks.json")).getObjValD "failedOrIncompleteCallbacks" == toJson (#[] : Array Json))
    "retain and resolve failed actual callbacks before trial cleanup"
  for call in ← IO.ofExcept ((← read (records/"registered-calls.json")).getArr?) do
    let path : String ← IO.ofExcept (call.getObjValAs? _ "stdout")
    check (toJson (← hash (.mk path)) == (call.getObjValD "timing").getObjValD "stdoutSha256") "retained actual stdout changed"
  -- Check every actual child, rather than treating this metadata controller's
  -- own root argument as a live native executable. No product may depend on a
  -- child. Removing the final empty directory cannot erase a new arrival.
  let targets := (← root.readDir).map (·.path)
  retireArtifacts records productRoot targets
  IO.FS.removeDir root
  let retained ← read (records/"retired.json")
  let count : Nat ← IO.ofExcept (retained.getObjValAs? _ "files")
  write (records/"retired.json") (retained.setObjVal! "files" (toJson (count+1))
    |>.setObjVal! "trialDirectoryRemoved" (toJson true))
end AutomaticPublicationStudy
def main : List String → IO Unit
  | ["prepare"] => AutomaticPublicationStudy.prepare
  | ["audit"] => AutomaticPublicationStudy.audit
  | ["run"] => AutomaticPublicationStudy.run
  | ["retain"] => AutomaticPublicationStudy.retain
  | ["retain-at",root,records,tag,fingerprints,changes] =>
      AutomaticPublicationStudy.retainOther root records tag fingerprints changes
  | ["audit-source-blocks",queries,fingerprints,output] =>
      AutomaticPublicationStudy.sourceBlockAudit queries fingerprints output
  | ["audit-callbacks",input,output] => AutomaticPublicationStudy.callbackAudit input output
  | ["prepare-postmortem"] => AutomaticPublicationStudy.preparePostmortem
  | ["postmortem"] => AutomaticPublicationStudy.postmortem
  | ["correct-fingerprint-audit"] => AutomaticPublicationStudy.correctFingerprintAudit
  | ["retire"] => AutomaticPublicationStudy.retire
  | "retire-product-at" :: root :: records :: tags => AutomaticPublicationStudy.retireProduct root records tags
  | "retire-trial-at" :: root :: records :: product :: tags => AutomaticPublicationStudy.retireTrial root records product tags
  | _ => throw (IO.userError "AutomaticPublicationStudy prepare|audit|run")
