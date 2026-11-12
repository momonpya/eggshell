import tools.research.StudyLocal
open Lean StudyLocal
namespace ProjectReadStudy
def parent := base/"practical-runtime/project-gateway"
def root := base/"practical-runtime/project-read-service"
def records := project/"docs/candidates/project-read-service"
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh shared read candidate required"
  check ((← hash (parent/"build/StudyMain")) == "e7f3c8b69da8429b69514a43dbc9ee3607743a01fa596502270cbde0e8b71fe7") "fixed parent changed"
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
  write (root/"settings.json") settings
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("remoteAdviceCannotCompleteWork",toJson true),("existingSharedReaderCoordinator",toJson true)])
def patch : IO Unit := do
  let mut body := ""
  for name in ["Eggshell/PublicationService.lean","Eggshell/PublicationClient.lean","Eggshell/PublicationWire.lean",
      "Eggshell/ProjectGateway.lean","Eggshell/ProjectGatewayPeer.lean","Eggshell/SynapseRecommend.lean",
      "Eggshell/SynapticTransport.lean","Eggshell/SynapseTransport.lean"] do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/"++name,"-L","b/"++name,
      (parent/"source"/name).toString,(root/"source"/name).toString]}
    check (result.exitCode ≤ 1) "cannot retain shared read patch"
    body := body++result.stdout
  for name in ["Eggshell/ProjectReadWire.lean","Eggshell/ProjectRead.lean"] do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","/dev/null","-L","b/"++name,
      "/dev/null",(root/"source"/name).toString]}
    check (result.exitCode == 1) "missing shared read module"
    body := body++result.stdout
  IO.FS.writeFile (records/"candidate.patch") body
def build (tag : String) : IO Unit := do
  idle
  patch
  StudyLocal.guard ("project-read-"++tag) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def retry (prior next moduleName : String) : IO Unit := do
  idle
  let guard ← read (base/("project-read-"++prior++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    guard.getObjValD "exitCode" != toJson (0 : Nat)) "preserve a terminal rejected build before retry"
  write (records/(prior++"-rejection.json")) (Json.mkObj [("guard",guard),
    ("patchSha256",toJson (← hash (records/"candidate.patch"))),
    ("diagnostic",toJson (← IO.FS.readFile (root/"build"/(moduleName.replace "." "_"++"-lean.stdout")))),
    ("actualQueries",toJson (0 : Nat))])
  build next
def audit (tag stem : String) : IO Unit := do
  idle
  discard <| finished ("project-read-"++tag)
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  let mut claims := #[]
  for name in ["SynapseRecommend","SynapticTransport","SynapseTransport"] do
    let path := root/"source/Eggshell"/(name++".lean")
    claims := claims.push ("@"++(← hash path)++":"++path.toString)
  for args in [#["inspect",(root/"build").toString,(records/(stem++"native.json")).toString],
      #["compare-sources",(parent/"build").toString,(root/"build").toString,(records/(stem++"sources.json")).toString,
        "Eggshell.PublicationClient","Eggshell.PublicationService","Eggshell.PublicationWire",
        "Eggshell.ProjectGateway","Eggshell.ProjectGatewayPeer","Eggshell.SynapseRecommend",
        "Eggshell.SynapticTransport","Eggshell.SynapseTransport","+Eggshell.ProjectRead","+Eggshell.ProjectReadWire"]++claims] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString]++args))
def install : IO Unit := do
  idle
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/TerminalIntentStudy.lean").toString,"install-at",root.toString,
    (base/"practical-runtime/context-clear").toString,records.toString,"native.json"]
def prepareChecks (buildName tag : String) : IO Unit := do
  idle
  discard <| finished "project-read-empty-checked-build"
  check (!(← (root/buildName).pathExists)) "fresh shared read observer required"
  for name in ["ProjectReadChecks","ProjectReadFixture","SourceBlocks"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  copyLocalArtifacts (root/"build") (root/buildName)
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/buildName).toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.ProjectReadChecks")
  write (root/(buildName++"-settings.json")) settings
  StudyLocal.guard ("project-read-"++tag) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/(buildName++"-settings.json")).toString]
def auditChecks (buildName tag stem : String) : IO Unit := do
  idle
  discard <| finished ("project-read-"++tag)
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for args in [#["inspect",(root/buildName).toString,(records/(stem++"checks-native.json")).toString],
      #["common-sources",(root/"build").toString,(root/buildName).toString,(records/(stem++"checks-sources.json")).toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString]++args))
def runChecks (buildName tag runName stem mode : String) : IO Unit := do
  idle
  check ((← read (records/(stem++"checks-sources.json"))).getObjValD "commonSourcesUnchanged" == toJson true)
    "observer must use unchanged product core"
  let checked ← read (records/(stem++"checks-sources.json"))
  check (checked.getObjValD "productSha256" == toJson (← hash (root/"build/StudyMain")) &&
    checked.getObjValD "auditorSha256" == toJson (← hash (root/buildName/"StudyMain"))) "query binaries changed after the source audit"
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? ((← read (root/"installation.json")).getObjValD "environment"))
  check (["checks","fresh"].contains mode) "known native workload required"
  if mode == "checks" then check (!(← (root/runName).pathExists)) "fresh source/query fixture root required"
  else discard <| finished "project-read-queries-final"
  let client := if mode == "fresh" then "fresh-client-data" else "client-data"
  let updates := #[("EGGSHELL_DATA_ROOT",some (root/runName/client).toString)]
  let env := env.filter (fun row => !updates.any (·.1 == row.1))++updates
  let unsets := env.filterMap fun (key,value) => if value.isNone then some key else none
  let values := env.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  StudyLocal.guard ("project-read-"++tag) (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "project-read",(records/(stem++"queries.stdout")).toString,(records/(stem++"queries.stderr")).toString,"/usr/bin/env"]++
    unsets.flatMap (fun key => #["-u",key])++values++#[(root/buildName/"StudyMain").toString,
      mode,(root/"installation.json").toString,(root/runName).toString])
def refreshInstall (stem : String) : IO Unit := do
  idle
  discard <| finished "project-read-empty-checked-build"
  check ((← IO.FS.realPath (root/"prefix/libexec/eggshell")) == (← IO.FS.realPath (root/"build/StudyMain")))
    "isolated installation no longer points to its native product"
  let previous ← read (root/"installation.json")
  let runtime := previous.getObjValD "runtime" |>.setObjVal! "sha256" (toJson (← hash (root/"build/StudyMain")))
  let updated := previous.setObjVal! "runtime" runtime
  write (root/"installation.json") updated
  write (records/(stem++"installation.json")) updated
def proof : IO Unit := do
  idle
  let source := project/"tools/research/ProjectReadAudit.lean"
  let checked ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString,args := #["-j1","-M768","-DwarningAsError=true",source.toString],
    env := #[("LEAN_PATH",some (root/"build/lib").toString)] }
  write (records/"proofs.json") (Json.mkObj [("exitCode",toJson checked.exitCode.toNat),
    ("sourceSha256",toJson (← hash source)),("stdout",toJson checked.stdout),("stderr",toJson checked.stderr)])
  check (checked.exitCode == 0 && checked.stderr.isEmpty && !checked.stdout.contains "sorryAx" &&
    !checked.stdout.contains "Lean.ofReduceBool" && !checked.stdout.contains "Lean.trustCompiler") "read proofs/dependency audit failed"
def retain : IO Unit := do
  idle
  let first ← finished "project-read-queries-final"
  let fresh ← finished "project-read-fresh-queries"
  check ((← read (records/"proofs.json")).getObjValD "exitCode" == toJson (0 : Nat)) "successful proof audit required"
  let run := root/"run-final"
  for name in ["result","queries","required-before-delivery","originals-before","frontend-stop","publisher-stop",
      "fresh-result","fresh-queries","fresh-publisher-stop"] do
    write (records/(name++".json")) (← read (run/(name++".json")))
  let rows ← IO.ofExcept ((← read (run/"queries.json")).getArr?)
  let later ← IO.ofExcept ((← read (run/"fresh-queries.json")).getArr?)
  let required ← IO.ofExcept ((← read (run/"required-before-delivery.json")).getArr?)
  let mut count := 0
  let mut largest := 0
  let mut longest := 0
  for row in rows++later do
    let response := row.getObjValD "response"
    let advice := response.getObjValD "advice"
    check (advice.getObjValD "synapticComplete" == toJson true &&
      (advice.getObjValD "search").getObjValD "semantic" == toJson "completed") "retained query was not semantically/synaptically complete"
    count := count+(← IO.ofExcept (row.getObjValAs? Nat "required"))
    let text ← IO.ofExcept (advice.getObjValAs? String "text")
    largest := max largest text.utf8ByteSize
    longest := max longest ((row.getObjValAs? Nat "elapsedMs").toOption.getD 0)
  let mut calls := #[]
  let mut hooks := 0
  let mut pending := 0
  for session in ← (run/"calls").readDir do
    for call in ← session.path.readDir do
      let timing ← read (call.path/"record.json")
      let input ← IO.FS.readFile (call.path/"stdin")
      let output ← IO.FS.readFile (call.path/"stdout")
      let error ← IO.FS.readFile (call.path/"stderr")
      check (timing.getObjValD "exitCode" == toJson (0 : Nat) && error.isEmpty) "fixture hook/source command failed"
      if let .ok parsed := Json.parse input then
        if (parsed.getObjValAs? String "hook_event_name").isOk then
          hooks := hooks+1
          if output.contains "Local memory search is busy or unavailable" then pending := pending+1
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("input",toJson input),("stdout",toJson output),("stderr",toJson error),("timing",timing)])
  write (records/"native-calls.json") (toJson calls)
  write (records/"explicit-warm.json") (← read (run/"explicit-warm/stdout"))
  write (records/"guards.json") (Json.mkObj [("queries",first),("fresh",fresh),
    ("runtime",← finished "project-read-empty-checked-build"),
    ("initialObserver",← finished "project-read-checks-empty-build"),("freshObserver",← finished "project-read-checks-fresh-build")])
  write (records/"fixture-sources.json") (toJson (← #["ProjectReadChecks","ProjectReadFixture","SourceBlocks"].mapM fun name => do
    let file := project/"tools/research"/(name++".lean")
    check ((← IO.FS.readFile file) == (← IO.FS.readFile (root/"source/tools/research"/(name++".lean")))) "fresh observer source changed"
    return (name,← hash file)))
  write (records/"summary.json") (Json.mkObj [("queries",toJson (rows.size+later.size)),
    ("uniqueRequiredFields",toJson required.size),("verifiedRequiredAppearances",toJson count),
    ("largestBodyBytes",toJson largest),("initialQueryMaximumMs",toJson longest),
    ("nativeCallbacks",toJson hooks),("nativeCommandsIncludingHooks",toJson calls.size),("incompleteCallbacks",toJson pending),
    ("productSha256",toJson (← hash (root/"build/StudyMain"))),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),("actualRemoteHostTested",toJson false)])
def retire : IO Unit := do
  idle
  discard <| finished "project-read-queries-final"
  discard <| finished "project-read-fresh-queries"
  let current ← hash (root/"build/StudyMain")
  check ((← read (records/"summary.json")).getObjValD "productSha256" == toJson current) "retain final observations before cleanup"
  let cleanup := records/"cleanup"
  IO.FS.createDirAll cleanup
  write (cleanup/"plan.json") (toJson (#[root/"run",root/"run-traced",root/"run-final",root/"checks-build",
    root/"checks-traced-build",root/"checks-empty-build",root/"checks-fresh-build",root/"helper-lib",root/"launcher.lean"].map (·.toString)))
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/AutomaticPublicationStudy.lean").toString,"retire-artifacts-at",root.toString,
    cleanup.toString,(cleanup/"plan.json").toString]
  check ((← hash (root/"build/StudyMain")) == current) "cleanup changed the final product"
  IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(root/"build").toString,
    (records/"post-cleanup-native.json").toString])
end ProjectReadStudy
def main : List String → IO Unit
  | ["prepare"] => ProjectReadStudy.prepare
  | ["build",tag] => ProjectReadStudy.build tag
  | ["retry",prior,next,moduleName] => ProjectReadStudy.retry prior next moduleName
  | ["audit",tag,stem] => ProjectReadStudy.audit tag stem
  | ["install"] => ProjectReadStudy.install
  | ["prepare-checks",build,tag] => ProjectReadStudy.prepareChecks build tag
  | ["audit-checks",build,tag,stem] => ProjectReadStudy.auditChecks build tag stem
  | ["run-checks",build,tag,run,stem] => ProjectReadStudy.runChecks build tag run stem "checks"
  | ["run-fresh",build,tag,run,stem] => ProjectReadStudy.runChecks build tag run stem "fresh"
  | ["refresh-install",stem] => ProjectReadStudy.refreshInstall stem
  | ["proof"] => ProjectReadStudy.proof
  | ["retain"] => ProjectReadStudy.retain
  | ["retire"] => ProjectReadStudy.retire
  | _ => throw (IO.userError "ProjectReadStudy prepare|build TAG|retry PRIOR NEXT MODULE|audit TAG STEM|install|prepare-checks BUILD TAG|audit-checks BUILD TAG STEM|run-checks BUILD TAG ROOT STEM|run-fresh BUILD TAG ROOT STEM|refresh-install STEM|proof|retain|retire")
