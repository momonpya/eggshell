import tools.research.StudyLocal
open Lean StudyLocal
namespace LLVMReadStudy
def productRoot := base/"practical-runtime/stable-storage-read"
def root := base/"practical-runtime/stable-storage-read-llvm"
def records := project/"docs/practical-runtime/stable-storage-read-llvm"
def preparationTag := "stable-storage-read-llvm-prepare-complete-input"
def guard (tag : String) (args : Array String) : IO Unit := do
  StudyLocal.guard tag args
  let path := base/(tag++".guard-settings.json")
  write path ((← read path).setObjVal! "ownedPrefixes" (toJson #[root.toString,productRoot.toString]))
def buildSettings (area entry : String) : IO Json := do
  return (← read (productRoot/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/area).toString)
    |>.setObjVal! "parents" (toJson #[(productRoot/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (productRoot/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (productRoot/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (productRoot/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson ("tools.research."++entry))
    |>.setObjVal! "force" (toJson (#[] : Array String))
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh fixed-product LLVM check required"
  check ((← hash (productRoot/"build/StudyMain")) == "ed077918092c75ac1a2416b157cb37f1186a387314455febf3f010c03e5f5817") "current product changed"
  check ((← read (project/"docs/candidates/stable-storage-read/product-after-cleanup.json")).getObjValD "consistent" == toJson true)
    "product closure must remain valid"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  IO.FS.createDirAll (root/"tmp")
  discard <| command "/bin/cp" #["-cR",(productRoot/"source").toString,(root/"source").toString]
  for (area,entry) in [("preparation-build","LLVMReadPreparation"),("readers-build","TenReaders")] do
    IO.FS.writeFile (root/"source/tools/research"/(entry++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(entry++".lean")))
    copyLocalArtifacts (productRoot/"build") (root/area)
    write (root/(area++"-settings.json")) (← buildSettings area entry)
  let original ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let seed ← read (base/"practical-runtime/cohort/study/seed-1/plan.json")
  write (root/"input.json") (Json.mkObj [("installation",← read (productRoot/"installation.json")),
    ("original",original.getObjValD "source"),("originalFiles",original.getObjValD "sourceFiles"),
    ("workspace",seed.getObjValD "workspace"),
    ("definitions",← read (base/"practical-runtime/interrupted-recovery/definitions.json")),
    ("preparedReference",Json.null),("activeReaders",toJson (3 : Nat)),("llvmReaders",toJson (3 : Nat)),
    ("registered",toJson true),("observeMaintenance",toJson false)])
  write (records/"plan.json") (Json.mkObj [("runtimeSha256",toJson (← hash (productRoot/"build/StudyMain"))),
    ("topics",toJson #[1,2,3]),("concurrentReaders",toJson (10 : Nat)),("waves",toJson (3 : Nat)),
    ("freshReaderDataRoot",toJson true),("sourceOnlyCopy",toJson true),("numericalHintsReused",toJson true),
    ("manualWarmDuringReads",toJson false),("generativeModelCalls",toJson (0 : Nat)),
    ("sourceSeedAccepted",toJson false),("adopted",toJson false)])
  guard "stable-storage-read-llvm-preparation-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"preparation-build-settings.json").toString]
def buildReaders : IO Unit := do
  idle
  discard <| finished "stable-storage-read-llvm-preparation-build"
  guard "stable-storage-read-llvm-readers-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"readers-build-settings.json").toString]
def audit : IO Unit := do
  idle
  discard <| finished "stable-storage-read-llvm-readers-build"
  for area in ["preparation-build","readers-build"] do
    for args in [#["inspect",(root/area).toString,(records/(area++"-native.json")).toString],
        #["subset-sources",(productRoot/"build").toString,(root/area).toString,
          (records/(area++"-sources.json")).toString,"Main","Eggshell.PluginHooks","Eggshell.FileSystem","Eggshell.SourceEvidence"]] do
      IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
        (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
def run (reading : Bool) : IO Unit := do
  idle
  for area in ["preparation-build","readers-build"] do
    check ((← read (records/(area++"-native.json"))).getObjValD "consistent" == toJson true &&
      (← read (records/(area++"-sources.json"))).getObjValD "nativeSubsetSourcesExact" == toJson true)
      "actual native controls must match the fixed product"
  if reading then
    discard <| finished preparationTag
    write (records/"frozen-before-delivery.json") (← read (root/"preparation/frozen-before-delivery.json"))
    check ((← read (records/"frozen-before-delivery.json")) ==
      (← read (project/"docs/candidates/terminal-intent/frozen-before-delivery.json"))) "LLVM denominator changed before delivery"
  let installation ← read (productRoot/"installation.json")
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let updates := #[("EGGSHELL_DATA_ROOT",some (root/(if reading then "ten-readers/data" else "preparation/data")).toString),
    ("TMPDIR",some (root/"tmp").toString)]
  let environment := environment.filter (fun row => !updates.any (·.1 == row.1))++updates
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := environment.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  let name := if reading then "readers" else "prepare-complete-input"
  let args := if reading then #[(root/"readers-build/StudyMain").toString,(root/"input.json").toString,
      (root/"preparation/llvm.egg").toString,(records/"frozen-before-delivery.json").toString,(root/"ten-readers").toString]
    else #[(root/"preparation-build/StudyMain").toString,(root/"input.json").toString,(root/"preparation").toString]
  guard ("stable-storage-read-llvm-"++name) (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    name,(records/(name++".stdout")).toString,(records/(name++".stderr")).toString,"/usr/bin/env"]++
    unset.flatMap (fun key => #["-u",key])++assigned++args)
def completeInput : IO Unit := do
  idle
  let rejected ← read (base/"stable-storage-read-llvm-prepare.guard.json")
  check (rejected.getObjValD "state" == toJson "finished" && rejected.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "rejected preparation is not terminal"
  check (!(← (root/"preparation").pathExists)) "input rejection must precede DB and runtime operations"
  write (records/"preparation-input-rejection.json") (Json.mkObj [("guard",rejected),
    ("input",← read (root/"input.json")),("stderr",toJson (← IO.FS.readFile (records/"prepare.stderr"))),
    ("productChanged",toJson false),("actualHookCalls",toJson (0 : Nat)),("sourceOperations",toJson (0 : Nat))])
  write (root/"input.json") ((← read (root/"input.json"))
    |>.setObjVal! "preparedReference" Json.null
    |>.setObjVal! "activeReaders" (toJson (3 : Nat))
    |>.setObjVal! "llvmReaders" (toJson (3 : Nat))
    |>.setObjVal! "observeMaintenance" (toJson false))
def retain : IO Unit := do
  idle
  discard <| finished "stable-storage-read-llvm-readers"
  write (records/"input.json") (← read (root/"input.json"))
  for name in ["prepared","frontend-stop","publisher-stop"] do
    write (records/("preparation-"++name++".json")) (← read (root/"preparation"/(name++".json")))
  write (records/"warm.json") (← read (root/"preparation/warm/stdout"))
  write (records/"warm-timing.json") (← read (root/"preparation/warm/record.json"))
  IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/TerminalIntentStudy.lean").toString,"retain-readers-at",root.toString,records.toString,
    "stable-storage-read-llvm-readers"])
  IO.FS.createDirAll (records/"responses")
  let mut calls := #[]
  for session in ← (root/"ten-readers/calls").readDir do
    for call in ← session.path.readDir do
      if (← call.path.symlinkMetadata).type != .dir || !(← (call.path/"registration.json").pathExists) then continue
      let digest ← hash (call.path/"stdout")
      let retained := records/"responses"/(digest++".json")
      unless ← retained.pathExists do IO.FS.writeBinFile retained (← IO.FS.readBinFile (call.path/"stdout"))
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("request",← read (call.path/"stdin")),("timing",← read (call.path/"record.json")),
        ("registration",← read (call.path/"registration.json")),("stdout",toJson retained.toString),
        ("stderr",toJson (← IO.FS.readFile (call.path/"stderr")))])
  check (calls.size == 90) "all thirty fresh-reader lifecycles required"
  write (records/"registered-calls.json") (toJson calls)
  IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/AutomaticPublicationStudy.lean").toString,"audit-callbacks",
    (records/"registered-calls.json").toString,(records/"hook-callbacks.json").toString])
def stateWidth : IO Unit := do
  idle
  discard <| finished "stable-storage-read-llvm-readers"
  check (!(← (records/"control-state-width.json").pathExists)) "retain the first state-width census"
  let mut rows := #[]
  for session in ← (root/"ten-readers/data/sessions").readDir do
    if (← session.path.symlinkMetadata).type != .dir then continue
    let path := session.path/"state.json"
    if !(← path.pathExists) then continue
    let state ← read path
    let .obj fields := state | throw (IO.userError "invalid private state object")
    let sizes := fields.toArray.map fun (name,value) => Json.mkObj [
      ("field",toJson name),("jsonBytes",toJson value.compress.toUTF8.size)]
    let keys : Array String ← IO.ofExcept (state.getObjValAs? _ "deliveredGraphs")
    let last : String ← IO.ofExcept (state.getObjValAs? _ "lastHandoff")
    let body ← IO.FS.readFile (root/"ten-readers/calls"/session.fileName/"body.txt")
    check (last == body) "private lastHandoff differs from the actual retained body"
    rows := rows.push (Json.mkObj [("session",toJson session.fileName),("stateSha256",toJson (← hash path)),
      ("stateBytes",toJson (← path.metadata).byteSize.toNat),("fields",toJson sizes),
      ("lastHandoffDuplicatesActualBody",toJson true),("graphKeys",toJson keys.size),
      ("maxGraphKeyCharacters",toJson (keys.foldl (fun value key => max value key.length) 0))])
  check (rows.size == 30) "all fresh reader states required"
  write (records/"control-state-width.json") (Json.mkObj [("runtime",(← read (root/"input.json")).getObjValD "installation" |>.getObjValD "runtime"),
    ("rows",toJson rows),("measuredLatencyAttribution",toJson false),
    ("productChange",toJson false),("repairsRequireOwner",toJson true)])
def retire : IO Unit := do
  idle
  let tags := #["preparation-build","readers-build","prepare-complete-input","readers"]
  IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
    (project/"tools/research/AutomaticPublicationStudy.lean").toString,"retire-trial-at",root.toString,
    records.toString,productRoot.toString]++tags.map ("stable-storage-read-llvm-"++·)))
end LLVMReadStudy
def main : List String → IO Unit
  | ["prepare"] => LLVMReadStudy.prepare
  | ["build-readers"] => LLVMReadStudy.buildReaders
  | ["audit"] => LLVMReadStudy.audit
  | ["prepare-source"] => LLVMReadStudy.run false
  | ["complete-input"] => LLVMReadStudy.completeInput
  | ["readers"] => LLVMReadStudy.run true
  | ["retain"] => LLVMReadStudy.retain
  | ["state-width"] => LLVMReadStudy.stateWidth
  | ["retire"] => LLVMReadStudy.retire
  | _ => throw (IO.userError "LLVMReadStudy prepare|build-readers|audit|prepare-source|readers")
