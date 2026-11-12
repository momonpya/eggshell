import tools.research.StudyLocal
open Lean StudyLocal
namespace PreparationRecoveryStudy
def parent := base/"practical-runtime/project-hook-write"
def root := base/"practical-runtime/preparation-recovery"
def records := project/"docs/candidates/preparation-recovery"
def changes := #["PreparationService","PublicationService","PublicationClient","ProjectGateway",
  "ProjectGatewayPeer","ProjectReadWire","ProjectRead","PublicationWire"]
def additions := #["ProjectReadSnapshot"]
def mixedBuild := "snapshot-mixed-build"
def mixedStem := "snapshot-"
def retirementBuild := "pin-checked-build"
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh preparation recovery candidate required"
  check ((← hash (parent/"build/StudyMain")) == "d3496cae522875b41910e393492be4eef4bb55cfbc9c2498abe57a24366d2f56") "recovery parent changed"
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
    ("durablePreparationRecovery",toJson true),("queryRankingChanged",toJson false),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
def build (tag : String) : IO Unit := do
  idle
  let mut patch := ""
  for name in changes++additions do
    let path := "Eggshell/"++name++".lean"
    let original := if additions.contains name then "/dev/null" else (parent/"source"/path).toString
    let label := if additions.contains name then "/dev/null" else "a/"++path
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L",label,"-L","b/"++path,
      original,(root/"source"/path).toString]}
    check (result.exitCode ≤ 1) "cannot retain recovery source change"
    patch := patch++result.stdout
  IO.FS.writeFile (records/"candidate.patch") patch
  guard ("preparation-recovery-"++tag) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def reject (tag moduleName : String) : IO Unit := do
  idle
  let previous ← read (base/("preparation-recovery-"++tag++".guard.json"))
  check (previous.getObjValD "state" == toJson "finished" && previous.getObjValD "exitCode" != toJson (0 : Nat) &&
    previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "preserve a drained rejected build"
  write (records/(tag++"-rejection.json")) (Json.mkObj [("guard",previous),
    ("diagnostic",toJson (← IO.FS.readFile (root/"build"/(moduleName.replace "." "_"++"-lean.stdout")))),
    ("patchSha256",toJson (← hash (records/"candidate.patch")))])
def audit (tag : String) (stem : String := "snapshot-") : IO Unit := do
  idle
  discard <| finished ("preparation-recovery-"++tag)
  let claims ← (changes++additions).mapM fun name => do
    let path := root/"source/Eggshell"/(name++".lean")
    return "@"++(← hash path)++":"++path.toString
  for args in [#["inspect",(root/"build").toString,(records/(stem++"native.json")).toString],
      #["compare-sources",(parent/"build").toString,(root/"build").toString,(records/(stem++"sources.json")).toString]++
        changes.map ("Eggshell."++·)++additions.map ("+Eggshell."++·)++claims] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
def install : IO Unit := do
  idle
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/TerminalIntentStudy.lean").toString,"install-at",root.toString,parent.toString,
    records.toString,"native.json"]
def prepareMixed (productTag : String := "retained-snapshot-build") : IO Unit := do
  idle
  discard <| finished ("preparation-recovery-"++productTag)
  IO.FS.writeFile (root/"source/tools/research/MixedChatChecks.lean")
    (← IO.FS.readFile (project/"tools/research/MixedChatChecks.lean"))
  copyLocalArtifacts (root/"build") (root/mixedBuild)
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/mixedBuild).toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.MixedChatChecks")
  write (root/"mixed-settings.json") settings
  guard ("preparation-recovery-"++mixedBuild) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"mixed-settings.json").toString]
def auditMixed : IO Unit := do
  idle
  discard <| finished ("preparation-recovery-"++mixedBuild)
  for args in [#["inspect",(root/mixedBuild).toString,(records/(mixedStem++"mixed-native.json")).toString],
      #["common-sources",(root/"build").toString,(root/mixedBuild).toString,(records/(mixedStem++"mixed-sources.json")).toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
def runMixed (tag mode : String) : IO Unit := do
  idle
  check (["service","service-growth"].contains mode) "unknown recovery workload"
  let checked ← read (records/(mixedStem++"mixed-sources.json"))
  let installation ← read (root/"installation.json")
  check (checked.getObjValD "commonSourcesUnchanged" == toJson true &&
    checked.getObjValD "allProductCorePresent" == toJson true &&
    checked.getObjValD "productSha256" == toJson (← hash (root/"build/StudyMain")) &&
    checked.getObjValD "productSha256" == (installation.getObjValD "runtime").getObjValD "sha256" &&
    checked.getObjValD "auditorSha256" == toJson (← hash (root/mixedBuild/"StudyMain"))) "recovery product/observer mismatch"
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let env := env.filter (·.1 != "EGGSHELL_DATA_ROOT") |>.push ("EGGSHELL_DATA_ROOT",some (root/tag/"data").toString)
  let unsets := env.filterMap fun (key,value) => if value.isNone then some key else none
  let values := env.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  guard ("preparation-recovery-"++tag) (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "preparation-recovery",(records/(tag++".stdout")).toString,(records/(tag++".stderr")).toString,"/usr/bin/env"]++
    unsets.flatMap (fun key => #["-u",key])++values++#[(root/mixedBuild/"StudyMain").toString,mode,
      (root/"installation.json").toString,(root/tag).toString])
def retainMixed (tag : String) : IO Unit := do
  idle
  let guard ← read (base/("preparation-recovery-"++tag++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "mixed recovery workload has not drained"
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
  for entry in ← run.readDir do
    if entry.fileName.endsWith ".json" then metadata := metadata.push (entry.fileName,← read entry.path)
  write (records/(tag++"-records.json")) (Json.mkObj [("guard",guard),("calls",toJson calls),
    ("metadata",toJson metadata),("observer",← read (records/(mixedStem++"mixed-sources.json"))),
    ("fixtureSource",← read (root/mixedBuild/"tools_research_MixedChatChecks.source"))])
def sealRecoveryOnly : IO Unit := do
  idle
  let mut before := #[]
  for name in ["native","sources","installation","mixed-native","mixed-sources"] do
    before := before.push (name,← read (records/(name++".json")))
  write (records/"recovery-only-build.json") (Json.mkObj [("artifacts",toJson before),
    ("patch",toJson (← IO.FS.readFile (records/"candidate.patch")))])
def refreshInstall : IO Unit := do
  idle
  check ((← IO.FS.realPath (root/"prefix/libexec/eggshell")) == (← IO.FS.realPath (root/"build/StudyMain"))) "wrong isolated runtime"
  let previous ← read (root/"installation.json")
  let runtime := previous.getObjValD "runtime" |>.setObjVal! "sha256" (toJson (← hash (root/"build/StudyMain")))
  let next := previous.setObjVal! "runtime" runtime
  write (root/"installation.json") next
  write (records/"snapshot-installation.json") next
def proof : IO Unit := do
  let path := project/"tools/research/PreparedProjectReadAudit.lean"
  let result ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768","-DwarningAsError=true",path.toString]
    env := #[("LEAN_PATH",some (root/"build/lib").toString)]}
  write (records/"proofs.json") (Json.mkObj [("exitCode",toJson result.exitCode.toNat),
    ("sourceSha256",toJson (← hash path)),("stdout",toJson result.stdout),("stderr",toJson result.stderr)])
  check (result.exitCode == 0 && result.stderr.isEmpty && !result.stdout.contains "sorryAx" &&
    !result.stdout.contains "Lean.trustCompiler" && !result.stdout.contains "Lean.ofReduceBool") "prepared-read proof/effect audit failed"
def summarize (tag : String) : IO Unit := do
  idle
  let guard ← finished ("preparation-recovery-"++tag)
  let run := root/tag
  let result ← read (run/"result.json")
  let array := fun (value : Json) => IO.ofExcept value.getArr?
  let nat := fun (value : Json) => IO.ofExcept (fromJson? (α := Nat) value)
  let mut readers := #[]
  let mut gates := #[]
  for name in ["baseline-readers","mixed-wave","final-readers"] do
    let report ← read (run/(name++".json"))
    readers := readers++(← array (report.getObjValD (if name == "mixed-wave" then "readers" else "rows")))
    gates := gates.push (name,report.getObjValD "elapsedMs")
  let waves ← array (result.getObjValD "growthWaves")
  for index in [:waves.size] do
    let report ← read (run/s!"growth-traffic-{index}.json")
    readers := readers++(← array (report.getObjValD "readers"))
    gates := gates.push (s!"growth-{index}",report.getObjValD "elapsedMs")
  if !waves.isEmpty then
    let report ← read (run/"growth-final-readers.json")
    readers := readers++(← array (report.getObjValD "rows"))
    gates := gates.push ("growth-final",report.getObjValD "elapsedMs")
  let mut required := 0
  let mut delivered := 0
  let mut freshRequired := 0
  let mut semanticCompleted := 0
  for row in readers do
    let wanted ← array (row.getObjValD "required")
    check ((← array (row.getObjValD "missing")).isEmpty) "summary found missing visible original evidence"
    required := required+wanted.size
    delivered := delivered+(← nat (row.getObjValD "delivered"))
    if row.getObjValD "freshContext" == toJson true then freshRequired := freshRequired+wanted.size
    if row.getObjValD "semantic" == toJson "completed" then semanticCompleted := semanticCompleted+1
  let kept ← read (records/(tag++"-records.json"))
  let calls ← array (kept.getObjValD "calls")
  let mut maxHook := 0
  let mut hooks := 0
  for row in calls do
    let record := row.getObjValD "record"
    check (row.getObjValD "stderr" == toJson "" && record.getObjValD "exitCode" == toJson (0 : Nat))
      "summary found a failed or noisy native hook"
    let label ← IO.ofExcept (row.getObjValAs? String "label")
    unless label.endsWith "-actual" do
      hooks := hooks+1
      maxHook := max maxHook (← nat (record.getObjValD "elapsedMs"))
  check (required == delivered) "summary delivery totals disagree"
  write (records/(tag++"-summary.json")) (Json.mkObj [("runtime",result.getObjValD "runtime"),
    ("queries",toJson readers.size),("requiredAppearances",toJson required),("deliveredAppearances",toJson delivered),
    ("freshContextRequiredAppearances",toJson freshRequired),("semanticCompleted",toJson semanticCompleted),
    ("gatesMs",toJson gates),("nativeCommands",toJson calls.size),("nativeHooks",toJson hooks),("maxHookMs",toJson maxHook),
    ("guard",guard),("workload",result),("scope",toJson "small scripted native lifecycle fixture"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def prepareRetirement : IO Unit := do
  idle
  discard <| finished "preparation-recovery-admitted"
  IO.FS.writeFile (root/"source/tools/research/PreparedPinRetirementChecks.lean")
    (← IO.FS.readFile (project/"tools/research/PreparedPinRetirementChecks.lean"))
  copyLocalArtifacts (root/"build") (root/retirementBuild)
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/retirementBuild).toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.PreparedPinRetirementChecks")
  write (root/"pin-settings.json") settings
  guard ("preparation-recovery-"++retirementBuild) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"pin-settings.json").toString]
def auditRetirement : IO Unit := do
  idle
  discard <| finished ("preparation-recovery-"++retirementBuild)
  for args in [#["inspect",(root/retirementBuild).toString,(records/"pin-checked-native.json").toString],
      #["common-sources",(root/"build").toString,(root/retirementBuild).toString,(records/"pin-checked-sources.json").toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
def runRetirement : IO Unit := do
  idle
  discard <| finished "preparation-recovery-admitted"
  let checked ← read (records/"pin-checked-sources.json")
  check (checked.getObjValD "commonSourcesUnchanged" == toJson true &&
    checked.getObjValD "allProductCorePresent" == toJson true &&
    checked.getObjValD "productSha256" == toJson (← hash (root/"build/StudyMain")) &&
    checked.getObjValD "auditorSha256" == toJson (← hash (root/retirementBuild/"StudyMain"))) "retirement observer binding changed"
  guard "preparation-recovery-pin-retirement" #[(root/retirementBuild/"StudyMain").toString,"check",
    (root/"admitted").toString,(records/"pin-retirement.json").toString]
def retainAll : IO Unit := do
  idle
  let retirement ← finished "preparation-recovery-pin-retirement"
  let failure ← read (base/"preparation-recovery-growing.guard.json")
  check (failure.getObjValD "state" == toJson "finished" &&
    failure.getObjValD "guardTriggered" == toJson true && failure.getObjValD "reason" == toJson "aggregate-rss" &&
    failure.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "retain the actual growth resource rejection"
  let run := root/"growing"
  let mut beforeGrowth := #[]
  for name in ["baseline-readers","mixed-wave","final-readers","final-inventory"] do
    beforeGrowth := beforeGrowth.push (name,← read (run/(name++".json")))
  write (records/"growing-rejection.json") (Json.mkObj [("guard",failure),
    ("lastCompletedStages",toJson beforeGrowth),("completedGrowthWaves",toJson (0 : Nat)),
    ("normalServiceShutdown",toJson false),("unchangedRetryPerformed",toJson false),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  write (records/"pin-retirement.guard.json") retirement
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "preparation-recovery-" && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "unfinished recovery guard cannot be sealed"
      guards := guards.push (entry.fileName,value)
  write (records/"guard-records.json") (toJson guards)
  let paths := #[parent/"mixed-clients",root/"recovered",root/"admitted",root/"growing",root/"mixed-build",
    root/mixedBuild,root/"pin-build",root/retirementBuild,root/"tmp"]
  write (records/"cleanup-plan.json") (toJson (paths.map (·.toString)))
end PreparationRecoveryStudy
def main : List String → IO Unit
  | ["prepare"] => PreparationRecoveryStudy.prepare
  | ["build",tag] => PreparationRecoveryStudy.build tag
  | ["reject",tag,moduleName] => PreparationRecoveryStudy.reject tag moduleName
  | ["audit",tag] => PreparationRecoveryStudy.audit tag
  | ["install"] => PreparationRecoveryStudy.install
  | ["seal-recovery-only"] => PreparationRecoveryStudy.sealRecoveryOnly
  | ["refresh-install"] => PreparationRecoveryStudy.refreshInstall
  | ["proof"] => PreparationRecoveryStudy.proof
  | ["prepare-mixed"] => PreparationRecoveryStudy.prepareMixed
  | ["prepare-mixed",productTag] => PreparationRecoveryStudy.prepareMixed productTag
  | ["audit-mixed"] => PreparationRecoveryStudy.auditMixed
  | ["run-mixed",tag,mode] => PreparationRecoveryStudy.runMixed tag mode
  | ["retain-mixed",tag] => PreparationRecoveryStudy.retainMixed tag
  | ["summarize",tag] => PreparationRecoveryStudy.summarize tag
  | ["prepare-retirement"] => PreparationRecoveryStudy.prepareRetirement
  | ["audit-retirement"] => PreparationRecoveryStudy.auditRetirement
  | ["run-retirement"] => PreparationRecoveryStudy.runRetirement
  | ["seal"] => PreparationRecoveryStudy.retainAll
  | _ => throw (IO.userError "PreparationRecoveryStudy prepare|build TAG|audit TAG|install")
