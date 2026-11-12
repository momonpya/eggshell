import tools.research.StudyLocal
open Lean StudyLocal
namespace ProjectHookWriteStudy
def parent := base/"practical-runtime/project-hook-read"
def root := base/"practical-runtime/project-hook-write"
def records := project/"docs/candidates/project-hook-write"
def changed := #["Config","PluginModel","PluginHooks","PluginCli","Worker","ProjectGateway","ProjectGatewayPeer",
  "ProjectHookRead","PublicationWire","NativePublication","PluginProjectContext","SynapseLive","ProjectPublication","PublicationService"]
def added := #["ProcessGroup","ProjectIngress"]
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh isolated shared-hook writer required"
  check ((← hash (parent/"build/StudyMain")) == "7bc72da7ca0be0507aabe6401f3a50b52b1fecb5a6515c179294a6b0bed163d1") "shared-hook parent changed"
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
    ("typedLocalAndProjectDestinations",toJson true),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
def patch : IO Unit := do
  let mut body := ""
  for name in changed++added do
    let path := "Eggshell/"++name++".lean"
    let origin := if added.contains name then "/dev/null" else (parent/"source"/path).toString
    let label := if added.contains name then "/dev/null" else "a/"++path
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L",label,"-L","b/"++path,
      origin,(root/"source"/path).toString]}
    check (result.exitCode ≤ 1) "cannot retain exact shared writer source change"
    body := body++result.stdout
  IO.FS.writeFile (records/"candidate.patch") body
def build (tag : String) : IO Unit := do
  idle
  patch
  guard ("project-hook-write-"++tag) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def interrupted (tag : String) : IO Unit := do
  idle
  let previous ← read (base/("project-hook-write-"++tag++".guard.json"))
  let guardPid ← IO.ofExcept (previous.getObjValAs? Nat "guardPid")
  let childPid ← IO.ofExcept (previous.getObjValAs? Nat "childPid")
  let owned ← IO.ofExcept (previous.getObjValAs? (Array Nat) "ownedPids")
  let pids := (#[guardPid,childPid]++owned).toList.eraseDups.toArray
  for pid in pids do
    let result ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid=,ppid=,command="]}
    check (result.exitCode != 0 && result.stdout.trimAscii.isEmpty) "interrupted guard or descendant remains live"
  write (records/(tag++"-interrupted.json")) (Json.mkObj [("previousGuard",previous),
    ("checkedAbsentPids",toJson pids),("checkedAtMs",toJson (← IO.monoMsNow)),
    ("patchSha256",toJson (← hash (records/"candidate.patch"))),
    ("state",toJson "externally-interrupted"),("passed",toJson false)])
def reject (tag moduleName : String) : IO Unit := do
  idle
  let failed ← read (base/("project-hook-write-"++tag++".guard.json"))
  check (failed.getObjValD "state" == toJson "finished" && failed.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    failed.getObjValD "exitCode" != toJson (0 : Nat)) "terminal rejected build required"
  write (records/(tag++"-rejection.json")) (Json.mkObj [("guard",failed),
    ("diagnostic",toJson (← IO.FS.readFile (root/"build"/(moduleName.replace "." "_"++"-lean.stdout")))),
    ("patchSha256",toJson (← hash (records/"candidate.patch")))])
def audit (tag stem : String) : IO Unit := do
  idle
  discard <| finished ("project-hook-write-"++tag)
  let mut claims := #[]
  for name in changed++added do
    let path := root/"source/Eggshell"/(name++".lean")
    claims := claims.push ("@"++(← hash path)++":"++path.toString)
  for args in [#["inspect",(root/"build").toString,(records/(stem++"native.json")).toString],
      #["compare-sources",(parent/"build").toString,(root/"build").toString,(records/(stem++"sources.json")).toString]++
      changed.map ("Eggshell."++·)++added.map ("+Eggshell."++·)++claims] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
def install : IO Unit := do
  idle
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/TerminalIntentStudy.lean").toString,"install-at",root.toString,
    parent.toString,records.toString,"native.json"]
def prepareChecks (buildName tag productTag : String) : IO Unit := do
  idle
  discard <| finished ("project-hook-write-"++productTag)
  IO.FS.writeFile (root/"source/tools/research/ProjectHookWriteChecks.lean")
    (← IO.FS.readFile (project/"tools/research/ProjectHookWriteChecks.lean"))
  copyLocalArtifacts (root/"build") (root/buildName)
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/buildName).toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.ProjectHookWriteChecks")
  write (root/(buildName++"-settings.json")) settings
  guard ("project-hook-write-"++tag) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/(buildName++"-settings.json")).toString]
def auditChecks (buildName tag stem : String) : IO Unit := do
  idle
  discard <| finished ("project-hook-write-"++tag)
  for args in [#["inspect",(root/buildName).toString,(records/(stem++"checks-native.json")).toString],
      #["common-sources",(root/"build").toString,(root/buildName).toString,(records/(stem++"checks-sources.json")).toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
def runChecks (buildName tag stem : String) (mode : String := "checks") (origin : Option String := none) : IO Unit := do
  idle
  let checked ← read (records/(stem++"checks-sources.json"))
  check (checked.getObjValD "commonSourcesUnchanged" == toJson true &&
    checked.getObjValD "productSha256" == toJson (← hash (root/"build/StudyMain")) &&
    checked.getObjValD "auditorSha256" == toJson (← hash (root/buildName/"StudyMain"))) "native product/observer source mismatch"
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? ((← read (root/"installation.json")).getObjValD "environment"))
  let unsets := env.filterMap fun (key,value) => if value.isNone then some key else none
  let values := env.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  guard ("project-hook-write-"++tag) (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "project-hook-write",(records/(tag++".stdout")).toString,(records/(tag++".stderr")).toString,"/usr/bin/env"]++
    unsets.flatMap (fun key => #["-u",key])++values++#[(root/buildName/"StudyMain").toString,mode,
      (root/"installation.json").toString,(root/(origin.getD tag)).toString])
def refreshInstall (stem : String) : IO Unit := do
  idle
  check ((← IO.FS.realPath (root/"prefix/libexec/eggshell")) == (← IO.FS.realPath (root/"build/StudyMain")))
    "isolated installation does not use the native candidate"
  let previous ← read (root/"installation.json")
  let runtime := previous.getObjValD "runtime" |>.setObjVal! "sha256" (toJson (← hash (root/"build/StudyMain")))
  let updated := previous.setObjVal! "runtime" runtime
  write (root/"installation.json") updated
  write (records/(stem++"installation.json")) updated
def rejectRun (tag stem : String) : IO Unit := do
  idle
  let failed ← read (base/("project-hook-write-"++tag++".guard.json"))
  check (failed.getObjValD "state" == toJson "finished" && failed.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    failed.getObjValD "exitCode" != toJson (0 : Nat)) "preserve a terminal native rejection"
  let run := root/tag
  let mut calls := #[]
  for session in ← (run/"calls").readDir do
    for call in ← session.path.readDir do
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("record",← read (call.path/"record.json")),("input",toJson (← IO.FS.readFile (call.path/"stdin"))),
        ("stdout",toJson (← IO.FS.readFile (call.path/"stdout"))),
        ("stderr",toJson (← IO.FS.readFile (call.path/"stderr")))])
  write (records/(tag++"-rejection.json")) (Json.mkObj [("guard",failed),("calls",toJson calls),
    ("stderr",toJson (← IO.FS.readFile (records/(tag++".stderr")))),
    ("observer",← read (records/(stem++"checks-sources.json"))),("installation",← read (root/"installation.json"))])
def proof : IO Unit := do
  idle
  discard <| finished "project-hook-write-native-registered"
  let path := project/"tools/research/ProjectHookWriteAudit.lean"
  let result ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768","-DwarningAsError=true",path.toString],
    env := #[("LEAN_PATH",some (root/"build/lib").toString)]}
  write (records/"proofs.json") (Json.mkObj [("exitCode",toJson result.exitCode.toNat),
    ("sourceSha256",toJson (← hash path)),("stdout",toJson result.stdout),("stderr",toJson result.stderr)])
  check (result.exitCode == 0 && result.stderr.isEmpty && !result.stdout.contains "sorryAx" &&
    !result.stdout.contains "Lean.ofReduceBool" && !result.stdout.contains "Lean.trustCompiler") "project-hook proof/caller audit failed"
def retain : IO Unit := do
  idle
  let guard ← finished "project-hook-write-native-registered"
  check ((← read (records/"proofs.json")).getObjValD "exitCode" == toJson (0 : Nat)) "successful project-hook proof audit required"
  let run := root/"native-registered"
  let names := #["result","required-before-delivery","publication","preparation-postmortem",
    "ALPHA-synapses","BETA-synapses","originals-before-queries","replies",
    "wave-0","wave-1","wave-2","wave-3",
    "restart-frontend-stop","restart-local-publisher-stop","restart-backend-stop",
    "final-frontend-stop","final-local-publisher-stop","final-backend-stop"]
  for name in names do write (records/(name++".json")) (← read (run/(name++".json")))
  write (records/"missing-empty-owner-inputs.json") (← read (root/"native-final/preparation-postmortem.json"))
  let replies ← IO.ofExcept ((← read (run/"replies.json")).getArr?)
  let required ← IO.ofExcept ((← read (run/"required-before-delivery.json")).getArr?)
  let mut visible := 0
  let mut fresh := 0
  let mut largest := 0
  for row in replies do
    let index ← IO.ofExcept (row.getObjValAs? Nat "client")
    let wave ← IO.ofExcept (row.getObjValAs? Nat "wave")
    let session := if wave == 3 && index%4 == 0 then s!"late-reader-{index}" else s!"native-reader-{index}"
    let stdout ← IO.FS.readFile (run/"calls"/session/s!"prompt-{wave}"/"stdout")
    let parsed ← IO.ofExcept (Json.parse stdout)
    let body := ((parsed.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
    check (row.getObjValD "body" == toJson body) "retained context differs from the actual callback"
    visible := visible+(← IO.ofExcept (row.getObjValAs? Nat "required"))
    for item in required do
      if body.contains (← IO.ofExcept (item.getObjValAs? String "text")) then fresh := fresh+1
    largest := max largest body.utf8ByteSize
  let mut calls := #[]
  for session in ← (run/"calls").readDir do
    for call in ← session.path.readDir do
      let record ← read (call.path/"record.json")
      let stdout ← IO.FS.readFile (call.path/"stdout")
      let stderr ← IO.FS.readFile (call.path/"stderr")
      check (record.getObjValD "exitCode" == toJson (0 : Nat) && stderr.isEmpty &&
        !stdout.contains "Local memory search is busy or unavailable") "failed or incomplete actual native command"
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("record",record),("input",toJson (← IO.FS.readFile (call.path/"stdin"))),
        ("stdout",toJson stdout),("stderr",toJson stderr)])
  write (records/"native-calls.json") (toJson calls)
  let fixture := "tools_research_ProjectHookWriteChecks.source"
  write (records/"fixture-sources.json") (Json.mkObj [
    ("successfulNativeRun",← read (root/"checks-registered-build"/fixture)),
    ("failedBeforeEmptyOwnerFix",← read (root/"checks-final-build"/fixture)),
    ("nativePreparationPostmortem",← read (root/"checks-postmortem-build"/fixture))])
  write (records/"guards.json") (Json.mkObj [("runtime",← finished "project-hook-write-registration-build"),
    ("observer",← finished "project-hook-write-checks-registered-build"),("nativeRun",guard),
    ("postmortem",← finished "project-hook-write-preparation-audit")])
  write (records/"summary.json") (Json.mkObj [("productSha256",toJson (← hash (root/"build/StudyMain"))),
    ("queries",toJson replies.size),("uniqueRequiredFields",toJson required.size),
    ("verifiedVisibleAppearances",toJson visible),("newBodyAppearances",toJson fresh),
    ("largestBodyBytes",toJson largest),("nativeCommandsIncludingHooks",toJson calls.size),
    ("peakRssKiB",guard.getObjValD "sampledPeakRssKiB"),("adopted",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("actualRemoteHostTested",toJson false)])
def retire : IO Unit := do
  idle
  discard <| finished "project-hook-write-native-registered"
  check ((← read (records/"summary.json")).getObjValD "productSha256" == toJson (← hash (root/"build/StudyMain")))
    "retain current executed evidence before cleanup"
  let targets := #["native","native-advisory","native-final","native-registered","checks-build",
    "checks-advisory-build","checks-final-build","checks-postmortem-build","checks-registered-build",
    "helper-lib","launcher.lean"].map (fun (name : String) => root/name)
  let cleanup := records/"cleanup"
  IO.FS.createDirAll cleanup
  write (cleanup/"plan.json") (toJson (targets.map (·.toString)))
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/AutomaticPublicationStudy.lean").toString,"retire-artifacts-at",root.toString,
    cleanup.toString,(cleanup/"plan.json").toString]
  IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(root/"build").toString,
    (records/"post-cleanup-native.json").toString])
def timings : IO Unit := do
  idle
  let calls ← IO.ofExcept ((← read (records/"native-calls.json")).getArr?)
  let mut rows := #[]
  for event in ["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","Stop"] do
    let mut elapsed : List Nat := []
    for call in calls do
      let input ← IO.ofExcept (call.getObjValAs? String "input")
      let parsed := (Json.parse input).toOption
      if parsed.any (fun input => input.getObjValD "hook_event_name" == toJson event) then
        elapsed := (← IO.ofExcept ((call.getObjValD "record").getObjValAs? Nat "elapsedMs"))::elapsed
    let sorted := (elapsed.mergeSort (· ≤ ·)).toArray
    check (!sorted.isEmpty) "missing native hook timing"
    rows := rows.push (Json.mkObj [("event",toJson event),("count",toJson sorted.size),
      ("minimumMs",toJson sorted[0]!),("medianMs",toJson sorted[sorted.size/2]!),
      ("maximumMs",toJson sorted[sorted.size-1]!)])
  write (records/"hook-timing.json") (Json.mkObj [("events",toJson rows),
    ("productionPercentiles",toJson false),("productSha256",(← read (records/"summary.json")).getObjValD "productSha256")])
end ProjectHookWriteStudy
def main : List String → IO Unit
  | ["prepare"] => ProjectHookWriteStudy.prepare
  | ["build",tag] => ProjectHookWriteStudy.build tag
  | ["interrupted",tag] => ProjectHookWriteStudy.interrupted tag
  | ["reject",tag,moduleName] => ProjectHookWriteStudy.reject tag moduleName
  | ["audit",tag,stem] => ProjectHookWriteStudy.audit tag stem
  | ["install"] => ProjectHookWriteStudy.install
  | ["prepare-checks",build,tag,productTag] => ProjectHookWriteStudy.prepareChecks build tag productTag
  | ["audit-checks",build,tag,stem] => ProjectHookWriteStudy.auditChecks build tag stem
  | ["run-checks",build,tag,stem] => ProjectHookWriteStudy.runChecks build tag stem
  | ["audit-preparation",build,tag,stem,origin] =>
    ProjectHookWriteStudy.runChecks build tag stem "audit-preparation" (some origin)
  | ["refresh-install",stem] => ProjectHookWriteStudy.refreshInstall stem
  | ["reject-run",tag,stem] => ProjectHookWriteStudy.rejectRun tag stem
  | ["proof"] => ProjectHookWriteStudy.proof
  | ["retain"] => ProjectHookWriteStudy.retain
  | ["retire"] => ProjectHookWriteStudy.retire
  | ["timings"] => ProjectHookWriteStudy.timings
  | _ => throw (IO.userError "ProjectHookWriteStudy prepare|build TAG|reject TAG MODULE|audit TAG STEM")
