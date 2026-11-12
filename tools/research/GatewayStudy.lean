import tools.research.StudyLocal
open Lean StudyLocal
namespace GatewayStudy
def parent := base/"practical-runtime/context-clear"
def root := base/"practical-runtime/project-gateway"
def records := project/"docs/candidates/project-gateway"
def guard (suffix : String) (args : Array String) : IO Unit := do
  StudyLocal.guard ("project-gateway-"++suffix) args
  let path := base/("project-gateway-"++suffix++".guard-settings.json")
  write path ((← read path).setObjVal! "ownedPrefixes" (toJson #[root.toString]))
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh isolated project gateway required"
  check ((← hash (parent/"build/StudyMain")) == "5d37ec1454fe36e1247e0488646d70886312c5a701638c102fe691fdc83a352d")
    "fixed parent changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  copyLocalArtifacts (parent/"build") (root/"build")
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.StudyMain")
    |>.setObjVal! "force" (toJson (#[] : Array String))
  write (root/"settings.json") settings
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("clientProjectFilesystemRequired",toJson false),("remoteAdministrationExposed",toJson false),
    ("transport",toJson "bounded frames over an operator-authenticated process channel"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def recordPatch : IO Unit := do
  let mut patches := ""
  for name in ["Eggshell/ProjectPublication.lean","Eggshell/PublicationClient.lean","Eggshell/PublicationService.lean","Main.lean"] do
    let delta ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/"++name,"-L","b/"++name,
      (parent/"source"/name).toString,(root/"source"/name).toString]}
    check (delta.exitCode ≤ 1) "cannot record gateway source change"
    patches := patches++delta.stdout
  for module in ["Eggshell/ProjectGateway.lean","Eggshell/ProjectGatewayPeer.lean"] do
    let delta ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","/dev/null","-L","b/"++module,
      "/dev/null",(root/"source"/module).toString]}
    check (delta.exitCode == 1) "gateway module absent"
    patches := patches++delta.stdout
  IO.FS.writeFile (records/"candidate.patch") patches

def build : IO Unit := do
  idle
  recordPatch
  if !(← (base/"project-gateway-build.guard-settings.json").pathExists) then
    guard "build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
  else check (!(← (base/"project-gateway-build.guard.json").pathExists)) "do not change a started native build"

def prepareChecks : IO Unit := do
  idle
  discard <| finished "project-gateway-api-build"
  check ((← read (records/"native.json")).getObjValD "consistent" == toJson true &&
    (← read (records/"sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "native product source audit must pass first"
  check (!(← (root/"checks-build").pathExists)) "fresh gateway test build required"
  IO.FS.writeFile (root/"source/tools/research/GatewayChecks.lean")
    (← IO.FS.readFile (project/"tools/research/GatewayChecks.lean"))
  copyLocalArtifacts (root/"build") (root/"checks-build")
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"checks-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.GatewayChecks")
  write (root/"checks-settings.json") settings
  guard "checks-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"checks-settings.json").toString]

def retryChecks (priorTag nextTag : String) : IO Unit := do
  idle
  let prior ← read (base/("project-gateway-"++priorTag++".guard.json"))
  check (prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    prior.getObjValD "exitCode" != toJson (0 : Nat)) "test compiler must be terminal and rejected"
  write (records/(priorTag++"-rejection.json")) (Json.mkObj [("guard",prior),
    ("output",toJson (← IO.FS.readFile (root/"checks-build/tools_research_GatewayChecks-lean.stdout"))),
    ("sourceSha256",toJson (← hash (root/"source/tools/research/GatewayChecks.lean"))),
    ("nativeProductChanged",toJson false),("actualHookCalls",toJson (0 : Nat))])
  IO.FS.writeFile (root/"source/tools/research/GatewayChecks.lean")
    (← IO.FS.readFile (project/"tools/research/GatewayChecks.lean"))
  guard nextTag #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"checks-settings.json").toString]

def auditChecks : IO Unit := do
  idle
  discard <| finished "project-gateway-checks-native-build"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for args in [#["inspect",(root/"checks-build").toString,(records/"checks-native.json").toString],
      #["subset-sources",(root/"build").toString,(root/"checks-build").toString,
        (records/"checks-sources.json").toString,"Main","Eggshell.ProjectGatewayPeer","Eggshell.ProjectPublication"]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString]++args))

def runChecks : IO Unit := do
  idle
  discard <| finished "project-gateway-checks-native-build"
  check ((← read (records/"checks-sources.json")).getObjValD "nativeSubsetSourcesExact" == toJson true)
    "gateway fixture must use the exact product core"
  check (!(← (root/"run").pathExists)) "fresh native gateway workload required"
  guard "boundaries" #["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "gateway-checks",(records/"boundaries.stdout").toString,(records/"boundaries.stderr").toString,
    "/usr/bin/env","EGGSHELL_DATA_ROOT="++(root/"run/client-data").toString,
    (root/"checks-build/StudyMain").toString,"checks",(root/"build/StudyMain").toString,(root/"run").toString]

def proofAudit : IO Unit := do
  idle
  discard <| finished "project-gateway-boundaries"
  check (!(← (records/"proofs.json").pathExists)) "retain the first successful proof audit"
  let source := project/"tools/research/GatewayAudit.lean"
  let result ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString,
    args := #["-j1","-M768",source.toString],
    env := #[("LEAN_PATH",some (root/"build/lib").toString)]}
  write (records/"proofs.json") (Json.mkObj [("exitCode",toJson result.exitCode.toNat),
    ("sourceSha256",toJson (← hash source)),("stdout",toJson result.stdout),("stderr",toJson result.stderr)])
  check (result.exitCode == 0 && result.stderr.isEmpty && !result.stdout.contains "sorryAx" &&
    !result.stdout.contains "Lean.trustCompiler" && !result.stdout.contains "Lean.ofReduceBool")
    "gateway laws/dependency audit failed"

def retain : IO Unit := do
  idle
  let runtime ← finished "project-gateway-api-build"
  let compiler ← finished "project-gateway-checks-native-build"
  let boundaries ← finished "project-gateway-boundaries"
  check ((← read (records/"proofs.json")).getObjValD "exitCode" == toJson (0 : Nat)) "proof audit required"
  check ((← IO.FS.readFile (root/"source/tools/research/GatewayChecks.lean")) ==
    (← IO.FS.readFile (project/"tools/research/GatewayChecks.lean"))) "executed gateway fixture source changed"
  for name in ["result","before-restart","first-ack","lost-ack-durable","concurrent-originals",
      "adversarial","public-descriptor","first-publisher-stop","final-publisher-stop"] do
    write (records/(name++".json")) (← read (root/"run"/(name++".json")))
  write (records/"guards.json") (Json.mkObj [("runtime",runtime),("compiler",compiler),("boundaries",boundaries)])
  write (records/"fixture.json") (Json.mkObj [("path",toJson "tools/research/GatewayChecks.lean"),
    ("sha256",toJson (← hash (project/"tools/research/GatewayChecks.lean"))),
    ("productSha256",toJson (← hash (root/"build/StudyMain"))),
    ("fixtureSha256",toJson (← hash (root/"checks-build/StudyMain")))])

def retire : IO Unit := do
  idle
  discard <| finished "project-gateway-boundaries"
  let expected ← IO.ofExcept ((← read (records/"fixture.json")).getObjValAs? String "productSha256")
  check ((← hash (root/"build/StudyMain")) == expected) "preserve the tested isolated product"
  let targets := #[root/"run",root/"checks-build"]
  let cleanup := records/"cleanup"
  IO.FS.createDirAll cleanup
  write (cleanup/"plan.json") (toJson (targets.map (·.toString)))
  discard <| command (StudyLocal.compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/AutomaticPublicationStudy.lean").toString,"retire-artifacts-at",parent.toString,
    cleanup.toString,(cleanup/"plan.json").toString]
  let mut rejected := #[]
  for name in ["rejected-source.patch","checked-rejected-source.patch","pipe-rejected-source.patch"] do
    let path := records/name
    rejected := rejected.push (name,← hash path)
    IO.FS.removeFile path
  write (records/"retired-rejected-sources.json") (toJson rejected)
  check ((← hash (root/"build/StudyMain")) == expected) "isolated product changed during cleanup"
  IO.println (← command (StudyLocal.compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(root/"build").toString,
    (records/"post-cleanup-native.json").toString])
end GatewayStudy
def main : List String → IO Unit
  | ["prepare"] => GatewayStudy.prepare
  | ["build"] => GatewayStudy.build
  | ["prepare-checks"] => GatewayStudy.prepareChecks
  | ["retry-checks",prior,next] => GatewayStudy.retryChecks prior next
  | ["audit-checks"] => GatewayStudy.auditChecks
  | ["run-checks"] => GatewayStudy.runChecks
  | ["proof-audit"] => GatewayStudy.proofAudit
  | ["retain"] => GatewayStudy.retain
  | ["retire"] => GatewayStudy.retire
  | _ => throw (IO.userError "GatewayStudy prepare|build|prepare-checks|retry-checks PRIOR NEXT|audit-checks|run-checks|proof-audit|retain|retire")
