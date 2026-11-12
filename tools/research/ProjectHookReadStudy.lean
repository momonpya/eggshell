import tools.research.StudyLocal
open Lean StudyLocal
namespace ProjectHookReadStudy
def parent := base/"practical-runtime/project-read-service"
def root := base/"practical-runtime/project-hook-read"
def records := project/"docs/candidates/project-hook-read"
def changed := #["Config","PluginModel","PluginHooks","PluginCli","Worker","ProjectGatewayPeer","ProjectReadWire","ProjectRead","PublicationWire"]
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh isolated hook/read candidate required"
  check ((← hash (parent/"build/StudyMain")) == "a6f2160da0215366cb16367dfec21e8093dc4330537a799de7aa9698cf8fc680") "fixed shared-read parent changed"
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
    ("capturedPerTurnReadScope",toJson true),("remoteAdviceHasNoCompletionAuthority",toJson true)])
def patch : IO Unit := do
  let mut text := ""
  for moduleName in changed do
    let name := "Eggshell/"++moduleName++".lean"
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/"++name,"-L","b/"++name,
      (parent/"source"/name).toString,(root/"source"/name).toString]}
    check (result.exitCode ≤ 1) "cannot retain actual hook/read patch"
    text := text++result.stdout
  let name := "Eggshell/ProjectHookRead.lean"
  let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","/dev/null","-L","b/"++name,
    "/dev/null",(root/"source"/name).toString]}
  check (result.exitCode == 1) "missing hook/read module"
  IO.FS.writeFile (records/"candidate.patch") (text++result.stdout)
def build (tag : String) : IO Unit := do
  idle
  patch
  guard ("project-hook-read-"++tag) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def audit (tag stem : String) : IO Unit := do
  idle
  discard <| finished ("project-hook-read-"++tag)
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  let mut claims := #[]
  for name in changed.push "ProjectHookRead" do
    let path := root/"source/Eggshell"/(name++".lean")
    claims := claims.push ("@"++(← hash path)++":"++path.toString)
  for args in [#["inspect",(root/"build").toString,(records/(stem++"native.json")).toString],
      #["compare-sources",(parent/"build").toString,(root/"build").toString,(records/(stem++"sources.json")).toString]++
      changed.map ("Eggshell."++·)++#["+Eggshell.ProjectHookRead"]++claims] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString]++args))
def reject (tag moduleName : String) : IO Unit := do
  idle
  let rejected ← read (base/("project-hook-read-"++tag++".guard.json"))
  check (rejected.getObjValD "state" == toJson "finished" && rejected.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    rejected.getObjValD "exitCode" != toJson (0 : Nat)) "terminal rejected stage required"
  write (records/(tag++"-rejection.json")) (Json.mkObj [("guard",rejected),
    ("diagnostic",toJson (← IO.FS.readFile (root/"build"/(moduleName.replace "." "_"++"-lean.stdout")))),
    ("patchSha256",toJson (← hash (records/"candidate.patch")))])
def install : IO Unit := do
  idle
  discard <| finished "project-hook-read-native-build"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/TerminalIntentStudy.lean").toString,"install-at",root.toString,
    parent.toString,records.toString,"native.json"]
def prepareChecks : IO Unit := do
  idle
  discard <| finished "project-hook-read-native-build"
  for name in ["ProjectHookReadChecks","ProjectReadFixture"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  copyLocalArtifacts (root/"build") (root/"checks-build")
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"checks-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.ProjectHookReadChecks")
  write (root/"checks-settings.json") settings
  guard "project-hook-read-checks-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"checks-settings.json").toString]
def retryChecks (prior next : String) : IO Unit := do
  idle
  let failed ← read (base/("project-hook-read-"++prior++".guard.json"))
  check (failed.getObjValD "state" == toJson "finished" && failed.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    failed.getObjValD "exitCode" != toJson (0 : Nat)) "preserve terminal observer rejection before retry"
  let errorOutput ← if ← (records/(prior++".stderr")).pathExists then
      IO.FS.readFile (records/(prior++".stderr")) else pure ""
  write (records/(prior++"-rejection.json")) (Json.mkObj [("guard",failed),
    ("diagnostic",toJson (← IO.FS.readFile (root/"checks-build/tools_research_ProjectHookReadChecks-lean.stdout"))),
    ("stderr",toJson errorOutput),
    ("sourceSha256",toJson (← hash (root/"source/tools/research/ProjectHookReadChecks.lean")))])
  for name in ["ProjectReadFixture","ProjectHookReadChecks"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  guard ("project-hook-read-"++next) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"checks-settings.json").toString]
def auditChecks (tag stem : String) : IO Unit := do
  idle
  discard <| finished ("project-hook-read-"++tag)
  for args in [#["inspect",(root/"checks-build").toString,(records/(stem++"checks-native.json")).toString],
      #["common-sources",(root/"build").toString,(root/"checks-build").toString,(records/(stem++"checks-sources.json")).toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
def runChecks (tag mode stem : String) : IO Unit := do
  idle
  let checked ← read (records/(stem++"checks-sources.json"))
  check (checked.getObjValD "commonSourcesUnchanged" == toJson true &&
    checked.getObjValD "productSha256" == toJson (← hash (root/"build/StudyMain")) &&
    checked.getObjValD "auditorSha256" == toJson (← hash (root/"checks-build/StudyMain"))) "native observer does not use exact product core"
  check (["checks","hooks"].contains mode) "known native workload required"
  if mode == "checks" then check (!(← (root/"run").pathExists)) "fresh hook workload required"
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? ((← read (root/"installation.json")).getObjValD "environment"))
  let env := env.filter (·.1 != "EGGSHELL_DATA_ROOT") |>.push ("EGGSHELL_DATA_ROOT",some (root/"run/client-data").toString)
  let unsets := env.filterMap fun (key,value) => if value.isNone then some key else none
  let values := env.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  guard ("project-hook-read-"++tag) (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "project-hook-read",(records/(tag++".stdout")).toString,(records/(tag++".stderr")).toString,"/usr/bin/env"]++
    unsets.flatMap (fun key => #["-u",key])++values++#[(root/"checks-build/StudyMain").toString,mode,
      (root/"installation.json").toString,(root/"run").toString]++if mode == "hooks" then #[tag] else #[])
def proof : IO Unit := do
  idle
  let source := project/"tools/research/ProjectHookReadAudit.lean"
  let result ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768","-DwarningAsError=true",source.toString],
    env := #[("LEAN_PATH",some (root/"build/lib").toString)]}
  write (records/"proofs.json") (Json.mkObj [("exitCode",toJson result.exitCode.toNat),
    ("sourceSha256",toJson (← hash source)),("stdout",toJson result.stdout),("stderr",toJson result.stderr)])
  check (result.exitCode == 0 && result.stderr.isEmpty && !result.stdout.contains "sorryAx" &&
    !result.stdout.contains "Lean.ofReduceBool" && !result.stdout.contains "Lean.trustCompiler") "remote-hook law/dependency audit failed"
def retain : IO Unit := do
  idle
  check ((← read (records/"proofs.json")).getObjValD "exitCode" == toJson (0 : Nat)) "successful remote-hook proof audit required"
  let guard ← finished "project-hook-read-hooks-checked"
  let runtime ← finished "project-hook-read-native-build"
  let run := root/"run"
  let names := #["required-before-delivery","originals-before","queries","result","frontend-stop","publisher-stop",
    "hooks-checked-results","hooks-checked-wave-0","hooks-checked-wave-1","hooks-checked-wave-2",
    "hooks-checked-frontend-stop","hooks-checked-publisher-stop"]
  for name in names do write (records/(name++".json")) (← read (run/(name++".json")))
  write (records/"cancellation.json") (← read (run/"hooks-checked/cancellation.json"))
  write (records/"initial-cancellation.json") (← read (run/"cancellation.json"))
  write (records/"explicit-warm.json") (← read (run/"explicit-warm/stdout"))
  let required ← IO.ofExcept ((← read (run/"required-before-delivery.json")).getArr?)
  let replies ← IO.ofExcept ((← read (run/"hooks-checked-results.json")).getArr?)
  let mut visibleCount := 0
  let mut newCount := 0
  let mut largest := 0
  for row in replies do
    let session := "hooks-checked-reader-"++toString (← IO.ofExcept (row.getObjValAs? Nat "client"))
    let wave ← IO.ofExcept (row.getObjValAs? Nat "wave")
    let raw ← IO.FS.readFile (run/"hook-calls"/session/s!"prompt-{wave}"/"stdout")
    let actual ← IO.ofExcept (Json.parse raw)
    let body := ((actual.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
    check (row.getObjValD "body" == toJson body) "retained body differs from actual callback stdout"
    check (((row.getObjValD "state").getObjValD "confirmedDelivery") != Json.null) "remote callback has no confirmed projection"
    visibleCount := visibleCount+(← IO.ofExcept (row.getObjValAs? Nat "required"))
    for item in required do
      if body.contains (← IO.ofExcept (item.getObjValAs? String "text")) then newCount := newCount+1
    largest := max largest body.utf8ByteSize
  let mut calls := #[]
  for baseName in ["calls","hook-calls"] do
    for session in ← (run/baseName).readDir do
      for call in ← session.path.readDir do
        let record ← read (call.path/"record.json")
        let input ← IO.FS.readFile (call.path/"stdin")
        let output ← IO.FS.readFile (call.path/"stdout")
        let error ← IO.FS.readFile (call.path/"stderr")
        check (record.getObjValD "exitCode" == toJson (0 : Nat) && error.isEmpty) "failed callback/native source command"
        calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
          ("input",toJson input),("stdout",toJson output),("stderr",toJson error),("record",record)])
  write (records/"native-calls.json") (toJson calls)
  write (records/"guards.json") (Json.mkObj [("runtime",runtime),("hooks",guard),
    ("observer",← finished "project-hook-read-checks-paths-build")])
  write (records/"fixture-sources.json") (toJson (← #["ProjectReadFixture","ProjectHookReadChecks","SourceBlocks"].mapM fun name => do
    let path := project/"tools/research"/(name++".lean")
    check ((← IO.FS.readFile path) == (← IO.FS.readFile (root/"source/tools/research"/(name++".lean")))) "executed fixture source changed"
    return (name,← hash path)))
  write (records/"summary.json") (Json.mkObj [("productSha256",toJson (← hash (root/"build/StudyMain"))),
    ("hookQueries",toJson replies.size),("uniqueRequiredFields",toJson required.size),
    ("verifiedVisibleAppearances",toJson visibleCount),("newBodyAppearances",toJson newCount),
    ("largestHookBodyBytes",toJson largest),("nativeCommandsIncludingHooks",toJson calls.size),
    ("hookPeakRssKiB",guard.getObjValD "sampledPeakRssKiB"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false),("actualRemoteHostTested",toJson false)])
def retire : IO Unit := do
  idle
  discard <| finished "project-hook-read-hooks-checked"
  discard <| finished "project-hook-read-legacy-build"
  write (records/"cli-guard.json") (← finished "project-hook-read-cli-checked")
  check ((← read (records/"summary.json")).getObjValD "productSha256" == toJson (← hash (root/"build/StudyMain")))
    "retain current executed fixture evidence before cleanup"
  let cleanup := records/"cleanup"
  IO.FS.createDirAll cleanup
  write (cleanup/"plan.json") (toJson (#[root/"run",root/"checks-build",root/"helper-lib",root/"launcher.lean"].map (·.toString)))
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/AutomaticPublicationStudy.lean").toString,"retire-artifacts-at",root.toString,
    cleanup.toString,(cleanup/"plan.json").toString]
  IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(root/"build").toString,
    (records/"post-cleanup-native.json").toString])
def legacy : IO Unit := do
  idle
  discard <| finished "project-hook-read-hooks-checked"
  check ((← read (records/"summary.json")).getObjValD "productSha256" == toJson (← hash (root/"build/StudyMain")))
    "retain executed observer evidence before reusing its disposable build"
  let modules ← IO.ofExcept ((← read (root/"build/build.json")).getObjValAs? (Array Json) "modules")
  check (!(modules.any fun row => row.getObjValD "module" == toJson "tools.research.ProjectReadChecks"))
    "legacy fixture must not be a product-core input"
  IO.FS.writeFile (root/"source/tools/research/ProjectReadChecks.lean")
    (← IO.FS.readFile (project/"tools/research/ProjectReadChecks.lean"))
  write (records/"legacy-typecheck-rejection.json") (Json.mkObj [
    ("exitCode",toJson (134 : Nat)),("compilerHeapMiB",toJson (768 : Nat)),
    ("stderr",toJson "libc++abi: lean::memory_exception: excessive memory consumption detected at interpreter"),
    ("productChanged",toJson false),("nextCheck",toJson "native build with the established module settings and unchanged aggregate resource guard")])
  let settings := (← read (root/"checks-settings.json"))
    |>.setObjVal! "mainModule" (toJson "tools.research.ProjectReadChecks")
  write (root/"legacy-settings.json") settings
  guard "project-hook-read-legacy-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"legacy-settings.json").toString]
def cli (planOnly : Bool) : IO Unit := do
  if planOnly then
    idle
    guard "project-hook-read-cli-checked" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M768","--run",
      (project/"tools/research/ProjectHookReadStudy.lean").toString,"cli-run"]
    return
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? ((← read (root/"installation.json")).getObjValD "environment"))
  let updates := #[("EGGSHELL_CONFIG",some (root/"run/hooks-checked-remote-1-ALPHA.toml").toString),
    ("EGGSHELL_DATA_ROOT",some (root/"run/hooks-checked-client-data").toString),("CODEX_THREAD_ID",none)]
  let env := env.filter (fun row => !updates.any (·.1 == row.1))++updates
  let doctor ← IO.Process.output {
    cmd := (root/"build/StudyMain").toString,args := #["egg","doctor"],env }
  check (doctor.exitCode == 0 && doctor.stderr.isEmpty) "native remote-profile doctor failed"
  let parsed ← IO.ofExcept (Json.parse doctor.stdout)
  check (parsed.getObjValD "memory" == toJson "read-only" && parsed.getObjValD "remote_read" == toJson #["ALPHA"] &&
    parsed.getObjValD "databases" == toJson (#[] : Array Json)) "native doctor reports remote-only reads as disabled/local"
  let warm ← IO.Process.output {
    cmd := (root/"build/StudyMain").toString,args := #["egg","warm"],env }
  check (warm.exitCode != 0 && warm.stderr.contains "read_service preparation belongs to its data host")
    "native warm silently accepted an empty local read set"
  write (records/"cli-checks.json") (Json.mkObj [("doctor",parsed),("warmExit",toJson warm.exitCode.toNat),
    ("warmStdout",toJson warm.stdout),("warmStderr",toJson warm.stderr),
    ("productSha256",toJson (← hash (root/"build/StudyMain")))])
  write (records/"legacy-guard.json") (← finished "project-hook-read-legacy-build")
end ProjectHookReadStudy
def main : List String → IO Unit
  | ["prepare"] => ProjectHookReadStudy.prepare
  | ["build",tag] => ProjectHookReadStudy.build tag
  | ["audit",tag,stem] => ProjectHookReadStudy.audit tag stem
  | ["reject",tag,moduleName] => ProjectHookReadStudy.reject tag moduleName
  | ["install"] => ProjectHookReadStudy.install
  | ["prepare-checks"] => ProjectHookReadStudy.prepareChecks
  | ["retry-checks",prior,next] => ProjectHookReadStudy.retryChecks prior next
  | ["audit-checks",tag,stem] => ProjectHookReadStudy.auditChecks tag stem
  | ["run-checks",tag,mode,stem] => ProjectHookReadStudy.runChecks tag mode stem
  | ["proof"] => ProjectHookReadStudy.proof
  | ["retain"] => ProjectHookReadStudy.retain
  | ["retire"] => ProjectHookReadStudy.retire
  | ["legacy"] => ProjectHookReadStudy.legacy
  | ["cli-plan"] => ProjectHookReadStudy.cli true
  | ["cli-run"] => ProjectHookReadStudy.cli false
  | _ => throw (IO.userError "ProjectHookReadStudy prepare|build TAG|audit TAG STEM|reject TAG MODULE|install|prepare-checks|retry-checks PRIOR NEXT|audit-checks TAG STEM|run-checks TAG MODE STEM|proof|retain|retire")
