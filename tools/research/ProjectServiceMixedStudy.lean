import tools.research.StudyLocal
open Lean StudyLocal
namespace ProjectServiceMixedStudy
def product := base/"practical-runtime/project-hook-write"
def root := product/"mixed-clients"
def records := project/"docs/candidates/project-service-mixed"
def runtimeSha := "d3496cae522875b41910e393492be4eef4bb55cfbc9c2498abe57a24366d2f56"
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh mixed service workload required"
  check ((← hash (product/"build/StudyMain")) == runtimeSha) "mixed service product changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(product/"source").toString,(root/"source").toString]
  IO.FS.writeFile (root/"source/tools/research/MixedChatChecks.lean")
    (← IO.FS.readFile (project/"tools/research/MixedChatChecks.lean"))
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
  write (root/"settings.json") settings
  write (records/"plan.json") (Json.mkObj [("productSha256",toJson runtimeSha),
    ("projectDBs",toJson (2 : Nat)),("ownersPerProject",toJson (4 : Nat)),
    ("baselineWriterTurns",toJson (9 : Nat)),("baselineNativeObservations",toJson (27 : Nat)),
    ("interruptedWriters",toJson (2 : Nat)),("overlappingReaders",toJson (8 : Nat)),
    ("overlappingWriters",toJson (4 : Nat)),("optionalGrowthTurns",toJson (16 : Nat)),
    ("lateAndDuplicateEvents",toJson true),("projectSwitchBeforeLateEvents",toJson true),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  guard "project-service-mixed-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def audit (tag : String := "build") : IO Unit := do
  idle
  discard <| finished ("project-service-mixed-"++tag)
  for args in [#["inspect",(root/"build").toString,(records/"native.json").toString],
      #["common-sources",(product/"build").toString,(root/"build").toString,(records/"sources.json").toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
def run (tag mode : String) : IO Unit := do
  idle
  check (["service","service-growth"].contains mode) "unknown mixed service workload"
  let audited ← read (records/"sources.json")
  check (audited.getObjValD "allProductCorePresent" == toJson true &&
    audited.getObjValD "commonSourcesUnchanged" == toJson true &&
    audited.getObjValD "productSha256" == toJson (← hash (product/"build/StudyMain")) &&
    audited.getObjValD "productSha256" == toJson runtimeSha &&
    audited.getObjValD "auditorSha256" == toJson (← hash (root/"build/StudyMain"))) "mixed product/observer mismatch"
  let env : Array (String × Option String) ← IO.ofExcept (fromJson?
    ((← read (product/"installation.json")).getObjValD "environment"))
  let env := env.filter (·.1 != "EGGSHELL_DATA_ROOT") |>.push ("EGGSHELL_DATA_ROOT",some (root/tag/"data").toString)
  let unsets := env.filterMap fun (key,value) => if value.isNone then some key else none
  let values := env.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  guard ("project-service-mixed-"++tag) (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "project-service-mixed",(records/(tag++".stdout")).toString,(records/(tag++".stderr")).toString,"/usr/bin/env"]++
    unsets.flatMap (fun key => #["-u",key])++values++#[(root/"build/StudyMain").toString,mode,
      (product/"installation.json").toString,(root/tag).toString])
def inspect (tag : String) (prepared : Bool := false) : IO Unit := do
  idle
  let previous ← read (base/("project-service-mixed-"++tag++".guard.json"))
  check (previous.getObjValD "state" == toJson "finished" &&
    previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "mixed workload has not drained"
  let env : Array (String × Option String) ← IO.ofExcept (fromJson?
    ((← read (product/"installation.json")).getObjValD "environment"))
  let env := env.filter (·.1 != "EGGSHELL_DATA_ROOT") |>.push ("EGGSHELL_DATA_ROOT",some (root/tag/"data").toString)
  let unsets := env.filterMap fun (key,value) => if value.isNone then some key else none
  let values := env.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  let label := if prepared then "prepared-inspect" else "inspect"
  guard ("project-service-mixed-"++tag++"-"++label) (#["/usr/bin/env"]++
    unsets.flatMap (fun key => #["-u",key])++values++#[(root/"build/StudyMain").toString,
      if prepared then "inspect-prepared" else "inspect",
      (root/tag).toString,(records/(tag++"-"++label++".json")).toString])
def prepareProbe (tag : String := "probe-build") : IO Unit := do
  idle
  discard <| finished "project-service-mixed-overlapping-inspect"
  IO.FS.writeFile (root/"source/tools/research/MixedChatChecks.lean")
    (← IO.FS.readFile (project/"tools/research/MixedChatChecks.lean"))
  guard ("project-service-mixed-"++tag) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def retainFailure (tag : String) : IO Unit := do
  idle
  let previous ← read (base/("project-service-mixed-"++tag++".guard.json"))
  check (previous.getObjValD "state" == toJson "finished" && previous.getObjValD "exitCode" != toJson (0 : Nat) &&
    previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "preserve a drained mixed failure"
  let run := root/tag
  let mut calls := #[]
  for session in ← (run/"calls").readDir do
    for call in ← session.path.readDir do
      if !(← (call.path/"record.json").pathExists) then continue
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("record",← read (call.path/"record.json")),("input",toJson (← IO.FS.readFile (call.path/"stdin"))),
        ("stdout",toJson (← IO.FS.readFile (call.path/"stdout"))),
        ("stderr",toJson (← IO.FS.readFile (call.path/"stderr")))])
  let mut metadata := #[]
  for name in ["failure","declared-turns","baseline-inventory","baseline-ready","baseline-required",
      "baseline-readers","mixed-wave","paused","before-restart-inventory",
      "before-restart-frontend-stop","before-restart-client-publisher-stop","before-restart-publisher-stop",
      "final-frontend-stop","final-client-publisher-stop","final-publisher-stop"] do
    if ← (run/(name++".json")).pathExists then metadata := metadata.push (name,← read (run/(name++".json")))
  write (records/(tag++"-rejection.json")) (Json.mkObj [("guard",previous),("calls",toJson calls),
    ("metadata",toJson metadata),("observer",← read (records/"sources.json")),
    ("fixtureSource",← read (root/"build/tools_research_MixedChatChecks.source"))])
def describe (tag : String) : IO Unit := do
  let run := root/tag
  let declared ← IO.ofExcept ((← read (run/"declared-turns.json")).getArr?)
  let first ← IO.ofExcept ((declared[0]!.getObjValD "item").getObjValAs? String "session")
  let pending ← read (run/"data/sessions"/first/"pending.json")
  let frame := (pending.getObjValD "remoteFrame").getObjValD "payload"
  IO.println (Json.mkObj [("session",toJson first),("turn",pending.getObjValD "turnId"),
    ("write",pending.getObjValD "write"),("serviceWriter",(pending.getObjValD "service").getObjValD "write"),
    ("capturedWriter",(frame.getObjValD "descriptor").getObjValD "write"),
    ("capturedCut",(frame.getObjValD "boundary").getObjValD "projects")]).compress
  for name in ["baseline-readers","mixed-wave"] do
    let value ← read (run/(name++".json"))
    IO.println (Json.mkObj [("stage",toJson name),("elapsedMs",value.getObjValD "elapsedMs"),
      ("succeeded",value.getObjValD "readerProcessesSucceeded")]).compress
  let postmortem ← read (records/(tag++"-postmortem.json"))
  let counts := postmortem.getObjValD "inventory"
  IO.println (Json.mkObj [("nativeObservations",toJson ((counts.getObjValD "native").getArr?.toOption.getD #[]).size),
    ("answers",toJson ((counts.getObjValD "answers").getArr?.toOption.getD #[]).size),
    ("timed",counts.getObjValD "timedObservations"),("originalsUnchanged",postmortem.getObjValD "originalsUnchanged")]).compress
end ProjectServiceMixedStudy
def main : List String → IO Unit
  | ["prepare"] => ProjectServiceMixedStudy.prepare
  | ["audit"] => ProjectServiceMixedStudy.audit
  | ["audit",tag] => ProjectServiceMixedStudy.audit tag
  | ["run",tag,mode] => ProjectServiceMixedStudy.run tag mode
  | ["inspect",tag] => ProjectServiceMixedStudy.inspect tag
  | ["inspect-prepared",tag] => ProjectServiceMixedStudy.inspect tag true
  | ["prepare-probe"] => ProjectServiceMixedStudy.prepareProbe
  | ["prepare-probe",tag] => ProjectServiceMixedStudy.prepareProbe tag
  | ["retain-failure",tag] => ProjectServiceMixedStudy.retainFailure tag
  | ["describe",tag] => ProjectServiceMixedStudy.describe tag
  | _ => throw (IO.userError "ProjectServiceMixedStudy prepare|audit|run TAG service|service-growth")
