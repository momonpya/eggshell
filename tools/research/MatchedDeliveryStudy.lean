import tools.research.StudyLocal
open Lean StudyLocal
namespace MatchedDeliveryStudy
def parent := base/"practical-runtime/source-snapshot"
def root := base/"practical-runtime/matched-delivery"
def records := project/"docs/candidates/matched-delivery"
def audit (args : Array String) : IO Unit := do
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args)
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh matched-envelope comparison required"
  check ((← hash (parent/"build/StudyMain")) == "720e64d9daf08a8c8f5e716b8cb877bc378253ba51fb43738dc33e05c1b6c534")
    "retain the current product; no rollback or ranking change"
  let historic ← read (project/"docs/candidates/record-boundary/hook-plan.json")
  check (historic.getObjValD "handoffChars" == toJson (500000 : Nat)) "older complete-delivery envelope changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  copyLocalArtifacts (parent/"build") (root/"build")
  for name in ["LLVMProjectChecks","MatchedDeliveryChecks"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  let actions := (← IO.FS.readFile (project/"tools/research/LLVMProjectChecks.lean")).splitOn "\ndef main :"
  check (actions.length == 2) "single-case harness entry boundary changed"
  IO.FS.writeFile (root/"source/tools/research/LLVMProjectActions.lean") actions[0]!
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (parent/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.MatchedDeliveryChecks")
  write (root/"settings.json") settings
  let before ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let previous ← read (parent/"installation.json")
  let mut cases := #[]
  for cap in [500000,120000] do
    let label := toString cap
    let data := root/label
    let destination := records/label
    IO.FS.createDirAll destination
    IO.FS.createDirAll (root/"commands"/label)
    let environment : Array (String × Option String) ← IO.ofExcept (previous.getObjValAs? _ "environment")
    let updates := #[("EGGSHELL_PREFIX",some (parent/"prefix").toString),
      ("PLUGIN_ROOT",some (parent/"prefix/plugins/eggshell").toString),
      ("EGGSHELL_DATA_ROOT",some (data/"client").toString),("CODEX_HOME",some (data/"codex").toString),
      ("TMPDIR",some (root/"scratch"/label).toString),("EGGSHELL_TRACE_SELECTOR_INPUT",none),("EGGSHELL_TRACE_SELECTION_RANGES",none)]
    let environment := environment.filter (fun field => !updates.any (·.1 == field.1))++updates
    let installation := previous.setObjVal! "handoffChars" (toJson cap)
      |>.setObjVal! "environment" (toJson environment)
    let plan := Json.mkObj [("installation",installation),("original",before.getObjValD "source"),
      ("originalFiles",before.getObjValD "sourceFiles"),
      ("definitions",toJson (base/"practical-runtime/interrupted-recovery/definitions.json").toString),
      ("workspace",toJson "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"),
      ("root",toJson data.toString),("records",toJson destination.toString)]
    let plan := if cap == 120000 then plan.setObjVal! "project" (toJson (root/"500000/llvm.egg").toString) else plan
    let input := root/(label++"-plan.json")
    write input plan
    write (destination/"plan.json") plan
    cases := cases.push (Json.mkObj [("plan",toJson input.toString),("environment",toJson environment),
      ("workspace",toJson "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"),
      ("commands",toJson (root/"commands"/label).toString)])
  write (root/"input.json") (Json.mkObj [("observer",toJson (root/"build/StudyMain").toString),("cases",toJson cases)])
  write (records/"plan.json") (Json.mkObj [
    ("runtime",toJson (← hash (parent/"build/StudyMain"))),("caps",toJson #[500000,120000]),
    ("samePhysicalProjectAndSource",toJson true),("sameQuestionsModelRankingAuthority",toJson true),
    ("actualRegisteredHooks",toJson true),("freshClientsPerCap",toJson (6 : Nat)),
    ("freezeBothBeforeAnyWarmOrQuery",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false),("reason",toJson "the older 100% trial used 500000; later trials silently compared 120000")])
  guard "matched-delivery-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def capture : IO Unit := do
  idle
  discard <| finished "matched-delivery-build"
  audit #["inspect",(root/"build").toString,(records/"native.json").toString]
  audit #["common-sources",(parent/"build").toString,(root/"build").toString,(records/"sources.json").toString]
  guard "matched-delivery-capture" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    (root/"build/StudyMain").toString,"prepare",(root/"input.json").toString]
def rebuild : IO Unit := do
  idle
  let stopped ← read (base/"matched-delivery-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only correct the stopped harness entrypoint"
  write (records/"build-refusal.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"build/tools_research_MatchedDeliveryChecks-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"build/tools_research_MatchedDeliveryChecks-lean.stderr"))),
    ("correction",toJson "import the single-case actions without its second main entry"),
    ("productChanged",toJson false),("modelOrHookStarted",toJson false)])
  let actions := (← IO.FS.readFile (project/"tools/research/LLVMProjectChecks.lean")).splitOn "\ndef main :"
  check (actions.length == 2) "single-case harness entry boundary changed"
  IO.FS.writeFile (root/"source/tools/research/LLVMProjectActions.lean") actions[0]!
  IO.FS.writeFile (root/"source/tools/research/MatchedDeliveryChecks.lean")
    (← IO.FS.readFile (project/"tools/research/MatchedDeliveryChecks.lean"))
  guard "matched-delivery-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def captureChecked : IO Unit := do
  idle
  discard <| finished "matched-delivery-checked-build"
  audit #["inspect",(root/"build").toString,(records/"native.json").toString]
  audit #["common-sources",(parent/"build").toString,(root/"build").toString,(records/"sources.json").toString]
  guard "matched-delivery-capture" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    (root/"build/StudyMain").toString,"prepare",(root/"input.json").toString]
def captureReady : IO Unit := do
  idle
  let stopped ← read (base/"matched-delivery-capture.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only correct the stopped pre-capture filesystem setup"
  write (records/"capture-setup-refusal.json") (Json.mkObj [("guard",stopped),
    ("error",toJson "missing commands/500000 parent; outer TMPDIR also created the not-yet-captured case root"),
    ("modelOrHookStarted",toJson false),("databaseCreated",toJson false)])
  let input ← read (root/"input.json")
  let mut cases := #[]
  for cap in [500000,120000] do
    let label := toString cap
    let data := root/label
    if ← data.pathExists then
      let children ← data.readDir
      let some child := children[0]? | throw (IO.userError "unexpected empty partial case root")
      check (children.size == 1 && child.fileName == "tmp" && (← (data/"tmp").readDir).isEmpty)
        "refuse to discard any captured data"
      IO.FS.removeDir (data/"tmp")
      IO.FS.removeDir data
    IO.FS.createDirAll (root/"commands"/label)
    let path := root/(label++"-plan.json")
    let plan ← read path
    let installation := plan.getObjValD "installation"
    let environment : Array (String × Option String) ← IO.ofExcept (installation.getObjValAs? _ "environment")
    let environment := environment.filter (·.1 != "TMPDIR")++#[("TMPDIR",some (root/"scratch"/label).toString)]
    let plan := plan.setObjVal! "installation" (installation.setObjVal! "environment" (toJson environment))
    write path plan
    write (records/label/"plan.json") plan
    let rows : Array Json ← IO.ofExcept (input.getObjValAs? _ "cases")
    let some item := rows.find? (fun row => row.getObjValD "plan" == toJson path.toString) |
      throw (IO.userError "matched case changed its native plan")
    cases := cases.push (item.setObjVal! "environment" (toJson environment))
  write (root/"input.json") (input.setObjVal! "cases" (toJson cases))
  guard "matched-delivery-ready-capture" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    (root/"build/StudyMain").toString,"prepare",(root/"input.json").toString]
def run (captureTag : String := "matched-delivery-capture") : IO Unit := do
  idle
  discard <| finished captureTag
  let before ← read (records/"500000/before-delivery.json")
  let after ← read (records/"120000/before-delivery.json")
  let a ← IO.ofExcept (before.getObjValAs? (Array Json) "topics")
  let b ← IO.ofExcept (after.getObjValAs? (Array Json) "topics")
  check (a.map (·.getObjValD "frozen") == b.map (·.getObjValD "frozen") &&
    before.getObjValD "capturedHead" == after.getObjValD "capturedHead" &&
    before.getObjValD "sourceFiles" == after.getObjValD "sourceFiles") "matched source or pre-query requirements differ"
  write (records/"fixed-inputs.json") (Json.mkObj [("sameHeadAndOriginalBytes",toJson true),
    ("sameFrozenObligations",toJson true),("caps",toJson #[500000,120000]),("productChanged",toJson false)])
  guard "matched-delivery-hooks" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    (root/"build/StudyMain").toString,"run",(root/"input.json").toString]
def resumeWarm : IO Unit := do
  idle
  let stopped ← read (base/"matched-delivery-hooks.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "guardTriggered" == toJson false && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "only resume the drained pre-query preparation failure"
  let warm ← read (records/"500000/warm.json")
  check (warm.getObjValD "exitCode" == toJson (1 : Nat) && warm.getObjValD "stderr" ==
    toJson "egg: explicit warm lost its preparation claim\n" &&
    !(← (records/"500000/queries.json").pathExists) && !(← (root/"500000/calls").pathExists) &&
    !(← (records/"120000/warm.json").pathExists)) "do not restart a completed query or discard a different failure"
  write (records/"initial-warm-refusal.json") (Json.mkObj [("guard",stopped),("warm",warm),
    ("stdout",toJson (← IO.FS.readFile (root/"commands/500000/run/stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"commands/500000/run/stderr"))),
    ("queriesStarted",toJson false),("changedProductOrInputs",toJson false),
    ("action",toJson "retain the first preparation failure and resume unchanged explicit warm on the same captured project")])
  IO.FS.rename (root/"commands/500000/run") (root/"commands/500000/initial-run")
  IO.FS.rename (root/"500000/commands/shared-warm") (root/"500000/commands/initial-shared-warm")
  IO.FS.rename (records/"500000/warm.json") (records/"500000/initial-warm.json")
  IO.FS.rename (records/"500000/host-stop.json") (records/"500000/initial-host-stop.json")
  guard "matched-delivery-prepared-hooks" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    (root/"build/StudyMain").toString,"run",(root/"input.json").toString]
partial def textFiles (path : System.FilePath) (relative : String := "") : IO (Array (String × System.FilePath)) := do
  let mut result := #[]
  for entry in ← path.readDir do
    let name := if relative.isEmpty then entry.fileName else relative++"/"++entry.fileName
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then result := result++(← textFiles entry.path name)
    else
      check (info.type == .file) "retain only regular observation files"
      result := result.push (name,entry.path)
  return result
partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let counts ← remove entry.path
    total := (total.1+counts.1,total.2+counts.2)
  IO.FS.removeDir path
  return total
def compactBodies : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← (records/"bodies.json").pathExists))
    "compact only finished bodies already preserved in the callback evidence"
  let evidence ← read (records/"callbacks.json")
  let paths : Array (String × String) ← IO.ofExcept (evidence.getObjValAs? _ "paths")
  let blobs : Array (String × String) ← IO.ofExcept (evidence.getObjValAs? _ "utf8ContentsBySha256")
  let mut references := #[]
  let mut redundant := #[]
  for cap in [500000,120000] do
    let label := toString cap
    let queries ← IO.ofExcept ((← read (records/label/"queries.json")).getArr?)
    for query in queries do
      let pass ← IO.ofExcept (query.getObjValAs? Nat "pass")
      let topic ← IO.ofExcept (query.getObjValAs? Nat "topic")
      let session ← IO.ofExcept (query.getObjValAs? String "session")
      let stdout := label++"/calls/"++session++"/prompt/stdout"
      let some location := paths.find? (·.1 == stdout) | throw (IO.userError "actual callback stdout is not preserved")
      let some blob := blobs.find? (·.1 == location.2) | throw (IO.userError "callback stdout content is missing")
      let reply ← IO.ofExcept (Json.parse blob.2)
      let path := records/label/s!"pass-{pass}-topic-{topic}.txt"
      check ((reply.getObjValD "hookSpecificOutput").getObjValD "additionalContext" == toJson (← IO.FS.readFile path) &&
        toJson (← hash path) == query.getObjValD "bodySha256") "do not retire an unmatched original body"
      references := references.push (Json.mkObj [("cap",toJson cap),("pass",toJson pass),("topic",toJson topic),
        ("callbackStdout",toJson stdout),("callbackStdoutSha256",toJson location.2),
        ("jsonField",toJson "hookSpecificOutput.additionalContext"),("bodySha256",query.getObjValD "bodySha256")])
      redundant := redundant.push path
  write (records/"bodies.json") (Json.mkObj [("references",toJson references),
    ("losslessBodiesInCallbackStdout",toJson true),("redundantTextFilesRemoved",toJson redundant.size)])
  for path in redundant do IO.FS.removeFile path
def finish (tag : String := "matched-delivery-hooks") : IO Unit := do
  idle
  let completed ← finished tag
  let before ← read (records/"500000/before-delivery.json")
  let topics ← IO.ofExcept (before.getObjValAs? (Array Json) "topics")
  let some firstTopic := topics[0]? | throw (IO.userError "missing frozen source inventory")
  let captured ← IO.ofExcept ((firstTopic.getObjValD "specification").getObjValAs? String "source")
  let sourceFiles : Array (String × String) ← IO.ofExcept (before.getObjValAs? _ "sourceFiles")
  let plan ← read (root/"500000-plan.json")
  let original ← IO.ofExcept (plan.getObjValAs? String "original")
  let originalFiles : Array (String × String) ← IO.ofExcept (plan.getObjValAs? _ "originalFiles")
  for (name,digest) in sourceFiles do
    check ((← hash (System.FilePath.mk captured/name)) == digest) "captured source changed after delivery"
  for (name,digest) in originalFiles do
    check ((← hash (System.FilePath.mk original/name)) == digest) "original source changed after delivery"
  let mut cells := #[]
  let mut observations := #[]
  for cap in [500000,120000] do
    let label := toString cap
    let queries ← IO.ofExcept ((← read (records/label/"queries.json")).getArr?)
    check (queries.size == 6) "matched comparison must keep all six cells per envelope"
    for query in queries do
      let pass ← IO.ofExcept (query.getObjValAs? Nat "pass")
      let topic ← IO.ofExcept (query.getObjValAs? Nat "topic")
      let session ← IO.ofExcept (query.getObjValAs? String "session")
      let bodyPath := records/label/s!"pass-{pass}-topic-{topic}.txt"
      let body ← IO.FS.readFile bodyPath
      check (toJson (← hash bodyPath) == query.getObjValD "bodySha256") "delivered body hash changed"
      let callback := root/label/"calls"/session/"prompt"
      let reply ← IO.ofExcept (Json.parse (← IO.FS.readFile (callback/"stdout")))
      check ((reply.getObjValD "hookSpecificOutput").getObjValD "additionalContext" == toJson body)
        "audit body differs from the actual registered hook stdout"
      for event in ["start","prompt","stop"] do
        let record ← read (root/label/"calls"/session/event/"record.json")
        check (record.getObjValD "exitCode" == toJson (0 : Nat) &&
          (← IO.FS.readFile (root/label/"calls"/session/event/"stderr")).isEmpty &&
          toJson (← hash (root/label/"calls"/session/event/"stdout")) == record.getObjValD "stdoutSha256")
          "retain a callback failure instead of counting it as success"
      cells := cells.push (Json.mkObj [("cap",toJson cap),("pass",toJson pass),("topic",toJson topic),
        ("elapsedMs",query.getObjValD "elapsedMs"),("bodyCharacters",toJson body.length),
        ("bodyBytes",query.getObjValD "bodyBytes"),("bodySha256",query.getObjValD "bodySha256"),
        ("semantic",query.getObjValD "semantic"),("delivery",(query.getObjValD "assessment").getObjValD "availableDelivery")])
    for name in ["host","client-publisher","frontend"] do
      let report ← read (records/label/(name++"-stop.json"))
      check (report.getObjValD "processExited" == toJson true && report.getObjValD "endpointRemoved" == toJson true &&
        report.getObjValD "daemonExitCode" == toJson (0 : Nat)) "a matched service did not stop normally"
    for path in [root/label/"calls",root/label/"commands"] do
      observations := observations++(← textFiles path (label++"/"++path.fileName.getD ""))
  observations := observations++(← textFiles (root/"commands") "commands")
  let mut blobs : Array (String × String) := #[]
  let mut paths : Array (String × String) := #[]
  for (name,path) in observations do
    let digest ← hash path
    let value ← IO.FS.readFile path
    if let some old := blobs.find? (·.1 == digest) then check (old.2 == value) "observation digest collision"
    else blobs := blobs.push (digest,value)
    paths := paths.push (name,digest)
  let evidence := Json.mkObj [("paths",toJson paths),("utf8ContentsBySha256",toJson blobs),
    ("lossless",toJson true),("guard",completed)]
  check (!(← (records/"callbacks.json").pathExists)) "preserve matched callback evidence"
  write (records/"callbacks.json") evidence
  check ((← read (records/"callbacks.json")) == evidence) "callback evidence round trip differs"
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "matched-delivery-" && entry.fileName.endsWith ".guard.json" then
      let report ← read entry.path
      check (report.getObjValD "state" == toJson "finished" && report.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "matched comparison still owns work"
      guards := guards.push (entry.fileName,report)
  write (records/"guards.json") (toJson guards)
  write (records/"comparison.json") (Json.mkObj [("cells",toJson cells),
    ("originalAndCapturedBytesUnchanged",toJson true),("samePhysicalProject",toJson true),
    ("onlyDeliveryEnvelopeDiffers",toJson true),("historicalCap",toJson (500000 : Nat)),
    ("currentProductChanged",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("tokenEffectMeasured",toJson false),("acceptedSeed",toJson false),("adopted",toJson false)])
  let inputs : Array (String × String) ← IO.ofExcept
    (fromJson? (← read (project/"docs/candidates/source-snapshot/protected-native-inputs.json")))
  check (inputs.size == 355 && !(inputs.any fun (path,_) => path.startsWith (root.toString++"/")))
    "retirement overlaps a protected native input"
  for (path,digest) in inputs do check ((← hash (.mk path)) == digest) "protected input changed before retirement"
  let removed ← remove root
  for (path,digest) in inputs do check ((← hash (.mk path)) == digest) "retirement changed a protected input"
  write (records/"retired.json") (Json.mkObj [("files",toJson removed.1),("logicalBytes",toJson removed.2),
    ("archiveCreated",toJson false),("protectedNativeInputsUnchanged",toJson inputs.size),
    ("currentProductChanged",toJson false),("adopted",toJson false)])
  audit #["inspect",(parent/"build").toString,(records/"parent-after-retirement.json").toString]
  compactBodies
end MatchedDeliveryStudy
def main : List String → IO Unit
  | ["prepare"] => MatchedDeliveryStudy.prepare
  | ["capture"] => MatchedDeliveryStudy.capture
  | ["rebuild"] => MatchedDeliveryStudy.rebuild
  | ["capture-checked"] => MatchedDeliveryStudy.captureChecked
  | ["capture-ready"] => MatchedDeliveryStudy.captureReady
  | ["run"] => MatchedDeliveryStudy.run
  | ["run-ready"] => MatchedDeliveryStudy.run "matched-delivery-ready-capture"
  | ["resume-warm"] => MatchedDeliveryStudy.resumeWarm
  | ["finish"] => MatchedDeliveryStudy.finish
  | ["finish-resumed"] => MatchedDeliveryStudy.finish "matched-delivery-prepared-hooks"
  | ["compact-bodies"] => MatchedDeliveryStudy.compactBodies
  | ["check"] => pure ()
  | _ => throw (IO.userError "MatchedDeliveryStudy prepare|capture|run")
