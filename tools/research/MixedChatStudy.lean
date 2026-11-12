import tools.research.StudyLocal
import tools.research.SourceBlocks
import Std.Data.HashMap
open Lean StudyLocal

/- Native lifecycle fixture control. Product changes remain isolated; completed
one-off compiler/retention repairs live in their recorded git revision. -/
namespace MixedChatStudy
def product := base/"practical-runtime/context-clear"
def root := base/"practical-runtime/shared-owner-lifecycle"
def records := project/"docs/practical-runtime/shared-owner-lifecycle"
def runtimeHash := "5d37ec1454fe36e1247e0488646d70886312c5a701638c102fe691fdc83a352d"
def guard (suffix : String) (args : Array String) : IO Unit := do
  StudyLocal.guard ("shared-owner-"++suffix) args
  let path := base/("shared-owner-"++suffix++".guard-settings.json")
  write path ((← read path).setObjVal! "ownedPrefixes" (toJson #[root.toString,product.toString]))

def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh isolated same-owner trial required"
  check ((← hash (product/"build/StudyMain")) == runtimeHash) "fixed product changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  IO.FS.createDirAll (root/"tmp")
  discard <| command "/bin/cp" #["-cR",(product/"source").toString,(root/"source").toString]
  let mut fixtures := #[]
  for name in ["MixedChatChecks","SourceBlocks"] do
    let file := project/"tools/research"/(name++".lean")
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean")) (← IO.FS.readFile file)
    fixtures := fixtures.push (name,← hash file)
  copyLocalArtifacts (product/"build") (root/"build")
  let settings := (← read (product/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(product/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (product/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (product/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (product/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.MixedChatChecks")
    |>.setObjVal! "force" (toJson (#[] : Array String))
  write (root/"settings.json") settings
  write (root/"installation.json") (← read (product/"installation.json"))
  write (records/"plan.json") (Json.mkObj [("productSha256",toJson runtimeHash),("fixtures",toJson fixtures),
    ("projects",toJson (2 : Nat)),("physicalOwnersPerProject",toJson (4 : Nat)),
    ("allWritersUseSlot",toJson (0 : Nat)),("writerSessions",toJson (4 : Nat)),
    ("writerTurns",toJson (25 : Nat)),("observations",toJson (75 : Nat)),
    ("growthWaves",toJson (4 : Nat)),("queries",toJson (72 : Nat)),
    ("maximumConcurrentClients",toJson (14 : Nat)),("readerContextFromActualRepliesOnly",toJson true),
    ("manualWarmCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("productChanged",toJson false),("adopted",toJson false)])
  guard "build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]

def audit : IO Unit := do
  idle
  discard <| finished "shared-owner-build"
  for args in [#["inspect",(root/"build").toString,(records/"native.json").toString],
      #["common-sources",(product/"build").toString,(root/"build").toString,(records/"sources.json").toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
  let fixtures : Array (String × String) ← IO.ofExcept ((← read (records/"plan.json")).getObjValAs? _ "fixtures")
  for (name,expected) in fixtures do
    let witness ← read (root/"build"/("tools_research_"++name++".source"))
    let (source,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? witness)
    let file := root/"source/tools/research"/(name++".lean")
    check (source == (← IO.FS.readFile file) && (← hash file) == expected && literals.isEmpty)
      "executed native fixture differs from its predeclared source"

def run : IO Unit := do
  idle
  check ((← read (records/"native.json")).getObjValD "consistent" == toJson true &&
    (← read (records/"sources.json")).getObjValD "commonSourcesUnchanged" == toJson true) "native audit required"
  check ((← hash (product/"build/StudyMain")) == runtimeHash) "product changed after fixture audit"
  let installation ← read (root/"installation.json")
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let updates := #[("EGGSHELL_DATA_ROOT",some (root/"run/data").toString),("TMPDIR",some (root/"tmp").toString)]
  let environment := environment.filter (fun row => !updates.any (·.1 == row.1))++updates
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := environment.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  guard "run" (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "same-owner",(records/"flow.stdout").toString,(records/"flow.stderr").toString,"/usr/bin/env"]++
    unset.flatMap (fun key => #["-u",key])++assigned++#[(root/"build/StudyMain").toString,"shared-owner",
      (root/"installation.json").toString,(root/"run").toString])

def prepareFresh : IO Unit := do
  idle
  discard <| finished "shared-owner-run"
  check (!(← (root/"fresh-source").pathExists)) "fresh grown-DB observer build required"
  discard <| command "/bin/cp" #["-cR",(root/"source").toString,(root/"fresh-source").toString]
  let file := project/"tools/research/MixedChatChecks.lean"
  IO.FS.writeFile (root/"fresh-source/tools/research/MixedChatChecks.lean") (← IO.FS.readFile file)
  copyLocalArtifacts (root/"build") (root/"fresh-build")
  let settings := (← read (root/"settings.json"))
    |>.setObjVal! "project" (toJson (root/"fresh-source").toString)
    |>.setObjVal! "core" (toJson (root/"fresh-source").toString)
    |>.setObjVal! "output" (toJson (root/"fresh-build").toString)
  write (root/"fresh-settings.json") settings
  write (records/"fresh-plan.json") (Json.mkObj [("queries",toJson (10 : Nat)),("initialClientDataRootEmpty",toJson true),
    ("sourceSha256",toJson (← hash file)),("productSha256",toJson runtimeHash),("modelCalls",toJson (0 : Nat)),
    ("manualWarmCalls",toJson (0 : Nat)),("sameCompletedProjectSnapshots",toJson true)])
  guard "fresh-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"fresh-settings.json").toString]

def fresh : IO Unit := do
  idle
  discard <| finished "shared-owner-fresh-checked-build"
  for args in [#["inspect",(root/"fresh-build").toString,(records/"fresh-native.json").toString],
      #["common-sources",(product/"build").toString,(root/"fresh-build").toString,(records/"fresh-sources.json").toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
  let (source,literals) : String × Array (String × String) ← IO.ofExcept
    (fromJson? (← read (root/"fresh-build/tools_research_MixedChatChecks.source")))
  check (source == (← IO.FS.readFile (root/"fresh-source/tools/research/MixedChatChecks.lean")) && literals.isEmpty &&
    toJson (← hash (root/"fresh-source/tools/research/MixedChatChecks.lean")) ==
      (← read (records/"fresh-checked-source.json"))) "fresh observer source differs"
  let installation ← read (root/"installation.json")
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let updates := #[("EGGSHELL_DATA_ROOT",some (root/"run/fresh-data").toString),("TMPDIR",some (root/"tmp").toString)]
  let environment := environment.filter (fun row => !updates.any (·.1 == row.1))++updates
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := environment.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  guard "fresh-run" (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "grown-fresh",(records/"fresh-flow.stdout").toString,(records/"fresh-flow.stderr").toString,"/usr/bin/env"]++
    unset.flatMap (fun key => #["-u",key])++assigned++#[(root/"fresh-build/StudyMain").toString,"fresh-grown",
      (root/"installation.json").toString,(root/"run").toString])

def repairFreshBuild : IO Unit := do
  idle
  let prior ← read (base/"shared-owner-fresh-build.guard.json")
  check (prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "fresh observer compiler is not terminal"
  write (records/"fresh-compiler-rejection.json") (Json.mkObj [("guard",prior),
    ("output",toJson (← IO.FS.readFile (root/"fresh-build/tools_research_MixedChatChecks-lean.stdout"))),
    ("actualHookCalls",toJson (0 : Nat))])
  let file := project/"tools/research/MixedChatChecks.lean"
  IO.FS.writeFile (root/"fresh-source/tools/research/MixedChatChecks.lean") (← IO.FS.readFile file)
  write (records/"fresh-checked-source.json") (toJson (← hash file))
  guard "fresh-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"fresh-settings.json").toString]

/-- Collect even a failed native run before changing anything. A successful
summary additionally requires the independently reconstructed visible context. -/
def retain : IO Unit := do
  idle
  let monitor ← read (base/"shared-owner-run.guard.json")
  check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "same-owner traffic is not terminal"
  let freshMonitor ← read (base/"shared-owner-fresh-run.guard.json")
  check (freshMonitor.getObjValD "state" == toJson "finished" &&
    freshMonitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "fresh grown-DB traffic is not terminal"
  let area := root/"run"
  for entry in ← area.readDir do
    if (← entry.path.symlinkMetadata).type == .file && entry.fileName.endsWith ".json" then
      write (records/entry.fileName) (← read entry.path)
  write (records/"flow.guard.json") monitor
  write (records/"fresh-flow.guard.json") freshMonitor
  IO.FS.createDirAll (records/"responses")
  let mut calls := #[]
  for session in ← (area/"calls").readDir do
    for call in ← session.path.readDir do
      if (← call.path.symlinkMetadata).type != .dir || !(← (call.path/"registration.json").pathExists) then continue
      let digest ← hash (call.path/"stdout")
      let output := records/"responses"/(digest++".json")
      unless ← output.pathExists do IO.FS.writeBinFile output (← IO.FS.readBinFile (call.path/"stdout"))
      let timing ← read (call.path/"record.json")
      check (timing.getObjValD "stdoutSha256" == toJson digest) "actual callback changed before retention"
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("request",← read (call.path/"stdin")),("timing",timing),("stdout",toJson output.toString),
        ("stderr",toJson (← IO.FS.readFile (call.path/"stderr"))),("registration",← read (call.path/"registration.json"))])
  write (records/"registered-calls.json") (toJson calls)
  let mut failures := #[]
  for data in [area/"data",area/"fresh-data"] do
    if !(← (data/"receipts").pathExists) then continue
    for receipt in ← (data/"receipts").readDir do
      if (← receipt.path.symlinkMetadata).type == .dir && (← (receipt.path/"failure.json").pathExists) then
        failures := failures.push (Json.mkObj [("dataRoot",toJson data.toString),("receipt",toJson receipt.fileName),
          ("failure",← read (receipt.path/"failure.json"))])
  write (records/"failed-receipts.json") (toJson failures)
  if monitor.getObjValD "exitCode" != toJson (0 : Nat) then
    IO.println "Failed native fixture retained; no product adoption or success claim."
    return
  discard <| finished "shared-owner-run"
  if freshMonitor.getObjValD "exitCode" != toJson (0 : Nat) then
    IO.println "Growth passed, but fresh grown-DB queries failed; retain both outcomes separately."
    return
  discard <| finished "shared-owner-fresh-run"
  check (failures.isEmpty) "a native receipt failed during same-owner traffic"
  if !(← (records/"hook-callbacks.json").pathExists) then
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
      (project/"tools/research/AutomaticPublicationStudy.lean").toString,"audit-callbacks",
      (records/"registered-calls.json").toString,(records/"hook-callbacks.json").toString]
  let phases := #[("read-0","baseline-readers","rows"),("read-1","mixed-wave","readers"),
    ("read-2","final-readers","rows")]++(Array.range 4).map (fun n => (s!"read-growth-{n}",s!"growth-traffic-{n}","readers"))++
    #[("read-growth-final","growth-final-readers","rows"),("fresh-grown","fresh-grown-readers","rows")]
  let mut visible : Std.HashMap String String := {}
  let mut queries := #[]
  let mut eligible := 0
  let textHash := fun (text : String) => do
    let path := records/"text-audit.tmp"
    IO.FS.writeFile path text
    let result ← hash path
    IO.FS.removeFile path
    return result
  for (turn,label,field) in phases do
    for row in ← IO.ofExcept ((← read (records/(label++".json"))).getObjValAs? (Array Json) field) do
      let session : String ← IO.ofExcept (row.getObjValAs? _ "session")
      let some call := calls.find? (fun call => call.getObjValD "session" == toJson session &&
        call.getObjValD "label" == toJson (turn++"-prompt")) | throw (IO.userError "query has no retained callback")
      let output : String ← IO.ofExcept (call.getObjValAs? _ "stdout")
      let encoded := ((← read (.mk output)).getObjValD "hookSpecificOutput").getObjValD "additionalContext"
      let body ← match encoded with
        | .null => pure ""
        | .str text => pure text
        | _ => throw (IO.userError "hook context is not text")
      let before := if row.getObjValD "freshContext" == toJson true then "" else visible[session]?.getD ""
      let after := before++"\n"++body
      let capture ← read (area/"calls"/session/(turn++"-body.json"))
      check (capture.getObjValD "body" == toJson body &&
        capture.getObjValD "previousVisibleSha256" == toJson (← textHash before) &&
        capture.getObjValD "visibleSha256" == toJson (← textHash after)) "visible model context differs from returned bodies"
      let required ← IO.ofExcept (row.getObjValAs? (Array Json) "required")
      for needed in required do
        let value := fun field => IO.ofExcept (needed.getObjValAs? String field)
        check (Eggshell.Research.SourceBlocks.contains after (← value "path") (← value "fingerprint") (← value "text"))
          "independent same-owner evidence audit found missing original text"
      check (row.getObjValD "missing" == toJson (#[] : Array Json)) "native delivery auditor disagrees"
      eligible := eligible+required.size
      visible := visible.insert session after
      queries := queries.push (row.setObjVal! "stdout" (toJson output))
  check (queries.size == 82) "all predeclared same-owner and fresh grown-DB requests required"
  write (records/"queries.json") (toJson queries)
  let final ← read (records/"growth-inventory-3.json")
  let answers : Array String ← IO.ofExcept (final.getObjValAs? _ "answers")
  let frozen : Array Json ← IO.ofExcept ((← read (records/"fresh-grown-frozen.json")).getArr?)
  check (final.getObjValD "observations" == toJson (75 : Nat) && answers.size == 25 && frozen.size == 50 &&
    (← read (records/"fresh-grown-result.json")).getObjValD "originalsUnchanged" == toJson true)
    "same-owner durable inventory or fresh read-only cut is incomplete"
  write (records/"summary.json") (Json.mkObj [("productSha256",toJson runtimeHash),("productChanged",toJson false),
    ("queries",toJson queries.size),("eligibleFields",toJson eligible),("deliveredFields",toJson eligible),
    ("nativeObservations",final.getObjValD "observations"),("timedObservations",final.getObjValD "timedObservations"),
    ("withoutVerifiedInterval",final.getObjValD "withoutVerifiedInterval"),("answers",toJson answers.size),
    ("frozenSourceFields",toJson frozen.size),("freshQueries",toJson (10 : Nat)),
    ("peakRssKiB",monitor.getObjValD "sampledPeakRssKiB"),
    ("freshPeakRssKiB",freshMonitor.getObjValD "sampledPeakRssKiB"),("adopted",toJson false)])

def retire : IO Unit := do
  idle
  check ((← read (records/"summary.json")).getObjValD "queries" == toJson (82 : Nat)) "retain all verified requests first"
  let mut fixtures := #[]
  for (label,build,source) in [("growth",root/"build",root/"source"),("fresh",root/"fresh-build",root/"fresh-source")] do
    for name in ["MixedChatChecks","SourceBlocks"] do
      let file := source/"tools/research"/(name++".lean")
      let encoded ← read (build/("tools_research_"++name++".source"))
      let (text,_) : String × Array (String × String) ← IO.ofExcept (fromJson? encoded)
      check (text == (← IO.FS.readFile file)) "native fixture changed before cleanup"
      fixtures := fixtures.push (Json.mkObj [("stage",toJson label),("module",toJson name),
        ("sha256",toJson (← hash file)),("nativeSourceWitness",encoded)])
  write (records/"fixture-sources.json") (toJson fixtures)
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/AutomaticPublicationStudy.lean").toString,"retire-trial-at",root.toString,records.toString,
    product.toString,"shared-owner-build","shared-owner-run","shared-owner-fresh-checked-build","shared-owner-fresh-run"]
end MixedChatStudy
def main : List String → IO Unit
  | ["prepare"] => MixedChatStudy.prepare
  | ["audit"] => MixedChatStudy.audit
  | ["run"] => MixedChatStudy.run
  | ["prepare-fresh"] => MixedChatStudy.prepareFresh
  | ["fresh"] => MixedChatStudy.fresh
  | ["repair-fresh-build"] => MixedChatStudy.repairFreshBuild
  | ["retain"] => MixedChatStudy.retain
  | ["retire"] => MixedChatStudy.retire
  | _ => throw (IO.userError "MixedChatStudy prepare|audit|run|retain|retire")
