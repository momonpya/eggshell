import tools.research.StudyLocal
open Lean StudyLocal
namespace HookCommandStudy
def parent := base/"practical-runtime/preparation-recovery"
def root := base/"practical-runtime/hook-command"
def records := project/"docs/candidates/hook-command"
def split (text first after : String) : IO (String × String × String) := do
  let [before,rest] := text.splitOn first | throw (IO.userError ("source anchor is not unique: "++first))
  let [body,tail] := rest.splitOn after | throw (IO.userError ("source end anchor is not unique: "++after))
  return (before,first++body,after++tail)
def remove (text first after : String) : IO String := do
  let (before,_,tail) ← split text first after
  return before++tail
def replace (text before after : String) : IO String := do
  let [first,last] := text.splitOn before | throw (IO.userError ("source replacement is not unique: "++before))
  return first++after++last
def changes := #["Daemon","PluginHooks","Handoff","ProcessGroup","Worker","PublicationWire","ContractAudit"]
def connectedChanges := changes.push "Install"
def additions := #["HookWire","HookCommand"]
def productBuildTag := "hook-command-checked-build"
def resetIncompletePreparation : IO Unit := do
  idle
  check (!(← (base/"hook-command-build.guard-settings.json").pathExists) &&
    !(← (root/"settings.json").pathExists) && (← records.readDir).isEmpty)
    "only an unstarted, unrecorded preparation may be reset"
  let entries ← root.readDir
  check (entries.map (·.fileName) == #["source"] &&
    (← root.symlinkMetadata).type == .dir && (← (root/"source").symlinkMetadata).type == .dir)
    "incomplete preparation contains unrelated files or links"
  IO.FS.removeDirAll (root/"source")
  IO.FS.removeDir root
  IO.FS.removeDir records
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh hook-command candidate required"
  check ((← hash (parent/"build/StudyMain")) == "29c0daeed8f2b1da83874b87add64cd0a29a93203c823ee227c8d2f46e1cfc0f") "hook-command parent changed"
  IO.FS.createDirAll records
  IO.FS.createDirAll root
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  let source := root/"source/Eggshell"
  let hooks ← IO.FS.readFile (source/"PluginHooks.lean")
  let handoff ← IO.FS.readFile (source/"Handoff.lean")
  let daemon ← IO.FS.readFile (source/"Daemon.lean")
  let worker ← IO.FS.readFile (source/"Worker.lean")
  let (_,helpers,_) ← split hooks "def requiredString" "def withSearchNotice"
  let (_,context,_) ← split handoff "def hookContext" "def hookDeny"
  let (_,notice,_) ← split handoff "def pendingSearch : Handoff := {\n  text := " "\n  reason :="
  let notice := (notice.drop "def pendingSearch : Handoff := {\n  text := ".length).toString
  IO.FS.writeFile (source/"HookWire.lean") ("module\npublic import Lean.Data.Json.Parser\npublic import Lean.Data.Json.FromToJson\n@[expose] public section\nnamespace Eggshell.Plugin\nopen Lean\n"++helpers++
    "def pendingSearchText : String := "++notice++"\n\n"++context++"end Eggshell.Plugin\n")
  IO.FS.writeFile (source/"PluginHooks.lean") (← remove hooks "def requiredString" "def withSearchNotice")
  let handoff ← replace handoff "public import Eggshell.SourcePlan" "public import Eggshell.HookWire\npublic import Eggshell.SourcePlan"
  let handoff ← replace handoff notice "pendingSearchText"
  IO.FS.writeFile (source/"Handoff.lean") (← remove handoff "def hookContext" "def hookDeny")
  let (_,reply,_) ← split daemon "def validHookOutput" "def hookRequest"
  let reply ← replace reply "pendingSearch.text" "pendingSearchText"
  let (_,rpc,_) ← split daemon "def boundedRpc" "def validHookOutput"
  let rpc ← replace rpc "def boundedRpc (kind : String)" "def boundedRpc (backend : System.FilePath) (kind : String)"
  let rpc ← replace rpc "cmd := (← IO.appPath).toString" "cmd := backend.toString"
  let rpc := rpc.replace "Worker.awaitUntil" "ProcessGroup.awaitUntil" |>.replace "Worker.killGroup" "ProcessGroup.kill"
  let (_,client,_) ← split daemon "def hookClient" "def awaitStopped"
  let client ← replace client "def hookClient (fast : Bool := false)" "def hookClient (backend : System.FilePath) (fast : Bool := false)"
  let client ← replace client "cmd := (← IO.appPath).toString" "cmd := backend.toString"
  let client ← replace client "boundedRpc \"receipt\"" "boundedRpc backend \"receipt\""
  let client := client.replace "Worker.awaitUntil" "ProcessGroup.awaitUntil" |>.replace "Worker.killGroup" "ProcessGroup.kill"
  IO.FS.writeFile (source/"HookCommand.lean") ("module\npublic import Eggshell.HookWire\npublic import Eggshell.Receipt\npublic import Eggshell.ProcessGroup\n@[expose] public section\nnamespace Eggshell.Plugin.Daemon\nopen Lean\n"++reply++
    "namespace Command\n"++rpc++client++"end Command\nend Eggshell.Plugin.Daemon\n")
  let daemon ← replace daemon "public import Eggshell.PluginCli" "public import Eggshell.HookCommand\npublic import Eggshell.PluginCli"
  let daemon ← remove daemon "def validHookOutput" "def hookRequest"
  let daemon ← split daemon "def boundedRpc" "def hookRequest" >>= fun (before,_,tail) =>
    pure (before++"def boundedRpc (kind : String) (input : Json) (deadline : Nat) : IO (Option String) := do\n"++
      "  Command.boundedRpc (← IO.appPath) kind input deadline\n\n"++tail)
  let daemon ← split daemon "def hookClient" "def awaitStopped" >>= fun (before,_,tail) =>
    pure (before++"def hookClient (fast : Bool := false) : IO UInt32 := do\n"++
      "  Command.hookClient (← IO.appPath) fast\n\n"++tail)
  IO.FS.writeFile (source/"Daemon.lean") daemon
  let (_,waiting,_) ← split worker "partial def awaitUntil" "structure Search where"
  let group ← IO.FS.readFile (source/"ProcessGroup.lean")
  let group ← replace group "public import Lean" "public import Std"
  let group ← replace group "end Eggshell.ProcessGroup" (waiting++"end Eggshell.ProcessGroup")
  IO.FS.writeFile (source/"ProcessGroup.lean") group
  let worker ← split worker "partial def awaitUntil" "structure Search where" >>= fun (before,_,tail) =>
    pure (before++"def awaitUntil (task : Task (Except IO.Error α)) (deadline : Nat) : IO (Option α) :=\n"++
      "  ProcessGroup.awaitUntil task deadline\n\n"++tail)
  IO.FS.writeFile (source/"Worker.lean") worker
  let contract ← IO.FS.readFile (source/"ContractAudit.lean")
  let boundary := "      (``Eggshell.Plugin.Daemon.hookClient,\n"++
    "        #[``Eggshell.Plugin.Worker.awaitUntil, ``Eggshell.Plugin.Worker.killGroup,\n"++
    "          ``Eggshell.Plugin.Daemon.decodeHookReply], #[``IO.getStdin, ``Eggshell.Plugin.captureTerminal]),"
  let checkedBoundary := "      (``Eggshell.Plugin.Daemon.hookClient,\n"++
    "        #[``Eggshell.ProcessGroup.awaitUntil, ``Eggshell.ProcessGroup.kill,\n"++
    "          ``Eggshell.Plugin.Daemon.Command.hookClient,\n"++
    "          ``Eggshell.Plugin.Daemon.decodeHookReply], #[``IO.getStdin, ``Eggshell.Plugin.captureTerminal]),\n"++
    "      (``Eggshell.Plugin.Daemon.Command.hookClient,\n"++
    "        #[``Eggshell.ProcessGroup.awaitUntil, ``Eggshell.ProcessGroup.kill,\n"++
    "          ``Eggshell.Plugin.Daemon.decodeHookReply], #[``IO.getStdin, ``Eggshell.Plugin.captureTerminal]),"
  IO.FS.writeFile (source/"ContractAudit.lean") (← replace contract boundary checkedBoundary)
  let wire ← IO.FS.readFile (source/"PublicationWire.lean")
  IO.FS.writeFile (source/"PublicationWire.lean") (← replace wire
    "(include_str \"DaemonWire.lean\").toUTF8" "(include_str \"DaemonWire.lean\").toUTF8,\n  (include_str \"HookWire.lean\").toUTF8,(include_str \"HookCommand.lean\").toUTF8")
  IO.FS.writeFile (root/"source/tools/research/HookCommandMain.lean")
    (← IO.FS.readFile (project/"tools/research/HookCommandMain.lean"))
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
  let mut patch := ""
  for name in changes++additions do
    let path := "Eggshell/"++name++".lean"
    let before := if additions.contains name then "/dev/null" else (parent/"source"/path).toString
    let label := if additions.contains name then "/dev/null" else "a/"++path
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L",label,"-L","b/"++path,before,(root/"source"/path).toString]}
    check (result.exitCode ≤ 1) "cannot preserve command extraction"
    patch := patch++result.stdout
  IO.FS.writeFile (records/"candidate.patch") patch
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("smallSupervisorSeparateFromBackend",toJson true),("startupOnlyEntryRetry",toJson false),
    ("rankingOrCapacityChanged",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "hook-command-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def audit : IO Unit := do
  idle
  discard <| finished productBuildTag
  let claims ← (changes++additions).mapM fun name => do
    let path := root/"source/Eggshell"/(name++".lean")
    return "@"++(← hash path)++":"++path.toString
  for args in [#["inspect",(root/"build").toString,(records/"native.json").toString],
      #["compare-sources",(parent/"build").toString,(root/"build").toString,(records/"sources.json").toString]++
        changes.map ("Eggshell."++·)++additions.map ("+Eggshell."++·)++claims] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
def prepareCommand : IO Unit := do
  idle
  discard <| finished productBuildTag
  IO.FS.writeFile (root/"source/tools/research/HookCommandMain.lean")
    (← IO.FS.readFile (project/"tools/research/HookCommandMain.lean"))
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"command-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.HookCommandMain")
  write (root/"command-settings.json") settings
  guard "hook-command-client-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"command-settings.json").toString]
def checkedBuild : IO Unit := do
  idle
  let previous ← read (base/"hook-command-build.guard.json")
  check (previous.getObjValD "state" == toJson "finished" && previous.getObjValD "exitCode" == toJson (1 : Nat) &&
    previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "retain the original compiler rejection first"
  unless ← (records/"build-rejection.json").pathExists do
    let log ← IO.FS.readFile (root/"build/Eggshell_ContractAudit-lean.stdout")
    let errors := log.splitOn "\n" |>.filter (fun line => line.contains "Source boundary" || line.contains "error:")
    write (records/"build-rejection.json") (Json.mkObj [("guard",previous),("errors",toJson errors),
      ("patch",toJson (← IO.FS.readFile (records/"candidate.patch")))])
  let mut patch := ""
  for name in changes++additions do
    let path := "Eggshell/"++name++".lean"
    let before := if additions.contains name then "/dev/null" else (parent/"source"/path).toString
    let label := if additions.contains name then "/dev/null" else "a/"++path
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L",label,"-L","b/"++path,before,(root/"source"/path).toString]}
    check (result.exitCode ≤ 1) "cannot retain checked hook-command sources"
    patch := patch++result.stdout
  IO.FS.writeFile (records/"candidate.patch") patch
  guard productBuildTag #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def auditCommand : IO Unit := do
  idle
  discard <| finished "hook-command-client-build"
  let mapping ← read (root/"command-build/object-mapping.json")
  let mut names : Array String := #[]
  for line in (← IO.FS.readFile (root/"command-build/runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    if let some name := (mapping.getObjValAs? String path).toOption then names := names.push name
  let required := names.filter (·.startsWith "Eggshell.")
  check (!required.isEmpty && !required.any (fun name =>
    name.startsWith "Eggshell.DB." || ["Eggshell.Worker","Eggshell.Handoff","Eggshell.Daemon","Eggshell.PluginHooks",
      "Eggshell.SearchProvider","Eggshell.Numerical","Eggshell.PublicationService"].contains name))
    "small command still imports a backend"
  for args in [#["inspect",(root/"command-build").toString,(records/"command-native.json").toString],
      #["component-sources",(root/"build").toString,(root/"command-build").toString,
        (records/"command-sources.json").toString]++required] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
  write (records/"command-modules.json") (Json.mkObj [("allModules",toJson names),
    ("allCommandProductModulesCompared",toJson required),("backendImports",toJson false),
    ("commandSha256",toJson (← hash (root/"command-build/StudyMain"))),
    ("backendSha256",toJson (← hash (root/"build/StudyMain")))])
def completeInventory : IO Unit := do
  idle
  let checked ← read (records/"command-modules.json")
  check (checked.getObjValD "commandSha256" == toJson (← hash (root/"command-build/StudyMain")))
    "small command changed before inventory correction"
  let names ← IO.ofExcept (checked.getObjValAs? (Array String) "allModules")
  let compiled ← IO.ofExcept ((← read (root/"command-build/build.json")).getObjValAs? (Array Json) "modules")
  let extra ← compiled.mapM fun row => IO.ofExcept (row.getObjValAs? String "module")
  check (extra.all (fun name => #["tools.research.RegisterMix","tools.research.RegisterRounds","tools.research.HookCommandMain"].contains name))
    "unexpected compiled module in the small command"
  let all := (names++extra).toList.eraseDups.toArray
  check ((← read (records/"command-native.json")).getObjValD "checkedNativeObjects" == toJson all.size)
    "command inventory does not cover all selected native objects"
  write (records/"command-modules.json") (checked.setObjVal! "allModules" (toJson all))
def proofs : IO Unit := do
  idle
  if (← (records/"proofs.json").pathExists) && !(← (records/"proofs-rejection.json").pathExists) then
    let previous ← read (records/"proofs.json")
    if previous.getObjValD "exitCode" != toJson (0 : Nat) then write (records/"proofs-rejection.json") previous
  let source := project/"tools/research/HookCommandAudit.lean"
  let result ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768","-DwarningAsError=true",source.toString],
    env := #[("LEAN_PATH",some (root/"build/lib").toString)]}
  write (records/"proofs.json") (Json.mkObj [("exitCode",toJson result.exitCode.toNat),
    ("sourceSha256",toJson (← hash source)),("stdout",toJson result.stdout),("stderr",toJson result.stderr)])
  check (result.exitCode == 0 && result.stderr.isEmpty && !result.stdout.contains "sorryAx" &&
    !result.stdout.contains "Lean.trustCompiler" && !result.stdout.contains "Lean.ofReduceBool") "small-command proof audit failed"
def prepareFixture : IO Unit := do
  idle
  discard <| finished productBuildTag
  IO.FS.writeFile (root/"source/tools/research/HookCommandBackend.lean")
    (← IO.FS.readFile (project/"tools/research/HookCommandBackend.lean"))
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"fixture-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.HookCommandBackend")
  write (root/"fixture-settings.json") settings
  guard "hook-command-fixture-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"fixture-settings.json").toString]
def auditFixture : IO Unit := do
  idle
  discard <| finished "hook-command-fixture-build"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",
    (root/"fixture-build").toString,(records/"fixture-native.json").toString]
def checks : IO Unit := do
  idle
  for name in ["native","command-native","fixture-native"] do
    check ((← read (records/(name++".json"))).getObjValD "consistent" == toJson true) "native input audit is missing"
  check ((← read (records/"proofs.json")).getObjValD "exitCode" == toJson (0 : Nat)) "proof audit has not passed"
  check (!(← (records/"check-plan.json").pathExists)) "preserve the first check plan"
  write (records/"check-plan.json") (Json.mkObj [("sourceSha256",toJson (← hash (project/"tools/research/HookCommandChecks.lean"))),
    ("sameBackendSha256",toJson (← hash (root/"build/StudyMain"))),
    ("smallClientSha256",toJson (← hash (root/"command-build/StudyMain"))),
    ("fixtureSha256",toJson (← hash (root/"fixture-build/StudyMain"))),
    ("protocolCases",toJson #["valid","empty","invalid","missing","malformed","silent","hang","blocked-input"]),
    ("footprintOrder",toJson #["full","small","small","full"]),
    ("sampleIntervalMs",toJson #[(400 : Nat),1200]),("minimumPairSavingKiBForGrowthTrial",toJson (8192 : Nat)),
    ("queryBenchmark",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  guard "hook-command-checks" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/HookCommandChecks.lean").toString,root.toString]
def checkedChecks : IO Unit := do
  idle
  let before ← read (base/"hook-command-checks.guard.json")
  check (before.getObjValD "state" == toJson "finished" && before.getObjValD "exitCode" == toJson (1 : Nat) &&
    before.getObjValD "ownedPids" == toJson (#[] : Array Nat) && !(← (root/"checks").pathExists))
    "only the metadata import refusal may be retried"
  write (records/"checks-import-refusal.json") (Json.mkObj [("guard",before),
    ("error",toJson "StudyLocal import path missing; no fixture or hook started")])
  guard "hook-command-checked-checks" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/HookCommandChecks.lean").toString,root.toString]
def prepareNativeChecks : IO Unit := do
  idle
  let before ← read (base/"hook-command-checked-checks.guard.json")
  check (before.getObjValD "state" == toJson "finished" && before.getObjValD "exitCode" == toJson (1 : Nat) &&
    before.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "retain the interpreted check rejection"
  write (records/"interpreted-check-rejection.json") (Json.mkObj [("guard",before),
    ("lastReceipt",← read (root/"checks/valid/receipt.json")),
    ("error",toJson "First valid case wrote its receipt, but the interpreted observer exceeded its three-second process-exit gate"),
    ("protocolCasesCompleted",toJson (0 : Nat)),("queryBenchmark",toJson false)])
  for name in ["HookCommandChecks","StudyLocal"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"checks-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.HookCommandChecks")
  write (root/"checks-settings.json") settings
  guard "hook-command-checks-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"checks-settings.json").toString]
def nativeChecks : IO Unit := do
  idle
  discard <| finished "hook-command-checks-build"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",
    (root/"checks-build").toString,(records/"checks-native.json").toString]
  let previous ← read (records/"check-plan.json")
  let current := previous.setObjVal! "sourceSha256" (toJson (← hash (project/"tools/research/HookCommandChecks.lean")))
    |>.setObjVal! "nativeControllerSha256" (toJson (← hash (root/"checks-build/StudyMain")))
    |>.setObjVal! "nativeController" (toJson true)
  write (records/"native-check-plan.json") current
  guard "hook-command-native-checks" #[(root/"checks-build/StudyMain").toString,root.toString,"checks-native"]
def repairNativeChecks : IO Unit := do
  idle
  let previous ← read (base/"hook-command-native-checks.guard.json")
  check (previous.getObjValD "state" == toJson "finished" && previous.getObjValD "exitCode" == toJson (1 : Nat) &&
    previous.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "preserve the native observer rejection"
  write (records/"native-observer-rejection.json") (Json.mkObj [("guard",previous),
    ("error",toJson "No child processes: observer called wait after tryWait had already reaped the valid client's exit"),
    ("lastReceipt",← read (root/"checks-native/valid/receipt.json")),("plan",← read (records/"native-check-plan.json"))])
  IO.FS.writeFile (root/"source/tools/research/HookCommandChecks.lean")
    (← IO.FS.readFile (project/"tools/research/HookCommandChecks.lean"))
  guard "hook-command-checked-checks-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"checks-settings.json").toString]
def checkedNativeChecks : IO Unit := do
  idle
  discard <| finished "hook-command-checked-checks-build"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",
    (root/"checks-build").toString,(records/"checked-native-controller.json").toString]
  write (records/"checked-native-plan.json") ((← read (records/"native-check-plan.json"))
    |>.setObjVal! "sourceSha256" (toJson (← hash (project/"tools/research/HookCommandChecks.lean")))
    |>.setObjVal! "nativeControllerSha256" (toJson (← hash (root/"checks-build/StudyMain"))))
  guard "hook-command-checked-native-checks" #[(root/"checks-build/StudyMain").toString,root.toString,"checked-native"]
def diagnose : IO Unit := do
  idle
  let before ← read (base/"hook-command-checked-native-checks.guard.json")
  check (before.getObjValD "state" == toJson "finished" && before.getObjValD "exitCode" == toJson (1 : Nat) &&
    before.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "retain the stopped footprint probe"
  let receiptFolder := root/"checked-native/footprint-0/data/receipts"
  let mut stages := #[]
  for receipt in ← receiptFolder.readDir do
    for file in ← receipt.path.readDir do
      if file.fileName.endsWith ".json" then stages := stages.push (file.fileName,← read file.path)
  write (records/"footprint-rejection.json") (Json.mkObj [("guard",before),
    ("stages",toJson stages),("error",toJson "full-backend supervisor did not stop within the 3.5-second observation gate"),
    ("completedProtocolCases",toJson (8 : Nat)),("completedFootprintProbes",toJson (0 : Nat))])
  guard "hook-command-tty-diagnostic" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(root/"tty-data").toString,
    (root/"build/StudyMain").toString,"codex-hook","fast"]
def productionEnvironmentBuild : IO Unit := do
  idle
  discard <| finished "hook-command-tty-diagnostic"
  check (!(← (records/"footprint.json").pathExists)) "do not repeat a completed footprint experiment"
  let installation ← read (parent/"installation.json")
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  check (environment.contains ("LEAN_NUM_THREADS",none)) "production environment no longer unsets the guard's thread override"
  write (records/"thread-environment-diagnosis.json") (Json.mkObj [
    ("guardSetsLeanThreads",toJson "1"),("productionUnsetsLeanThreads",toJson true),
    ("ttyGuard",← finished "hook-command-tty-diagnostic"),
    ("previousProbeComplete",toJson false),("eightProtocolCasesRetained",toJson true),
    ("causalPerformanceClaim",toJson false)])
  IO.FS.writeFile (root/"source/tools/research/HookCommandChecks.lean")
    (← IO.FS.readFile (project/"tools/research/HookCommandChecks.lean"))
  guard "hook-command-production-environment-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"checks-settings.json").toString]
def productionEnvironmentProbe : IO Unit := do
  idle
  discard <| finished "hook-command-production-environment-build"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",
    (root/"checks-build").toString,(records/"production-environment-native.json").toString]
  write (records/"production-environment-plan.json") ((← read (records/"checked-native-plan.json"))
    |>.setObjVal! "sourceSha256" (toJson (← hash (project/"tools/research/HookCommandChecks.lean")))
    |>.setObjVal! "nativeControllerSha256" (toJson (← hash (root/"checks-build/StudyMain")))
    |>.setObjVal! "leanThreadEnvironment" Json.null)
  guard "hook-command-production-environment-probe" #[(root/"checks-build/StudyMain").toString,root.toString,"production-environment","footprint"]
def connectBuild : IO Unit := do
  idle
  discard <| finished "hook-command-production-environment-probe"
  let rows ← IO.ofExcept ((← read (records/"footprint.json")).getObjValAs? (Array Json) "probes")
  let mut full : Array Nat := #[]
  let mut small : Array Nat := #[]
  for row in rows do
    let peak ← IO.ofExcept (row.getObjValAs? Nat "pairPeakRssKiB")
    if row.getObjValD "smallSupervisor" == toJson true then small := small.push peak else full := full.push peak
  check (full.size == 2 && small.size == 2 && full.foldl min 1000000 ≥ small.foldl max 0+8192)
    "the paired footprint gate did not justify another mixed workload"
  let mut artifacts := #[]
  for name in ["native","sources","proofs"] do artifacts := artifacts.push (name,← read (records/(name++".json")))
  write (records/"component-build.json") (Json.mkObj [("artifacts",toJson artifacts),
    ("runtimeSha256",toJson (← hash (root/"build/StudyMain")))])
  let mut patch := ""
  for name in connectedChanges++additions do
    let path := "Eggshell/"++name++".lean"
    let before := if additions.contains name then "/dev/null" else (parent/"source"/path).toString
    let label := if additions.contains name then "/dev/null" else "a/"++path
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L",label,"-L","b/"++path,before,(root/"source"/path).toString]}
    check (result.exitCode ≤ 1) "cannot retain connected command sources"
    patch := patch++result.stdout
  IO.FS.writeFile (records/"candidate.patch") patch
  guard "hook-command-connected-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def auditConnected : IO Unit := do
  idle
  discard <| finished "hook-command-connected-build"
  let claims ← (connectedChanges++additions).mapM fun name => do
    let path := root/"source/Eggshell"/(name++".lean")
    return "@"++(← hash path)++":"++path.toString
  for args in [#["inspect",(root/"build").toString,(records/"connected-native.json").toString],
      #["compare-sources",(parent/"build").toString,(root/"build").toString,(records/"connected-sources.json").toString]++
        connectedChanges.map ("Eggshell."++·)++additions.map ("+Eggshell."++·)++claims] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
def configure : IO Unit := do
  idle
  check ((← read (records/"connected-native.json")).getObjValD "consistent" == toJson true &&
    !(← (root/"prefix").pathExists)) "fresh audited command prefix required"
  let client ← read (records/"command-modules.json")
  check (client.getObjValD "commandSha256" == toJson (← hash (root/"command-build/StudyMain"))) "small command changed"
  discard <| command "/bin/cp" #["-cR",(parent/"prefix").toString,(root/"prefix").toString]
  IO.FS.removeFile (root/"prefix/libexec/eggshell")
  discard <| command "/bin/ln" #["-s",(root/"build/StudyMain").toString,(root/"prefix/libexec/eggshell").toString]
  discard <| command "/bin/ln" #["-s",(root/"command-build/StudyMain").toString,(root/"prefix/libexec/eggshell-hook").toString]
  discard <| command "/bin/ln" #["-s",(root/"command-build/StudyMain").toString,(root/"build/eggshell-hook").toString]
  discard <| command "/bin/cp" #["-cR",(root/"build/lib").toString,(root/"helper-lib").toString]
  let library := (root/"helper-lib").toString++":"++(compiler/"lib/lean").toString
  let compiled ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768","-DwarningAsError=true","-o",(root/"helper-lib/tools/research/StudyLaunchers.olean").toString,
      (project/"tools/research/StudyLaunchers.lean").toString]
    env := #[("LEAN_PATH",some library)]}
  check (compiled.exitCode == 0) (compiled.stdout++compiled.stderr)
  let binding ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768","--run",(project/"tools/research/HookCommandInstall.lean").toString,
      (root/"prefix").toString,(parent/"prefix").toString,(records/"launcher-binding.json").toString]
    env := #[("LEAN_PATH",some library)]}
  check (binding.exitCode == 0) (binding.stdout++binding.stderr)
  let before ← read (parent/"installation.json")
  let mut files := #[]
  for artifact in ← IO.ofExcept (before.getObjValAs? (Array Json) "pluginFiles") do
    let old ← IO.ofExcept (artifact.getObjValAs? String "path")
    let oldRoot := (parent/"prefix").toString++"/"
    check (old.startsWith oldRoot) "plugin artifact escaped its parent prefix"
    let path := root/"prefix"/(old.drop oldRoot.length |>.toString)
    let digest ← hash path
    unless ["plugins/eggshell/bin/egg","plugins/eggshell/bin/eggshelld"].any (fun ending => path.toString.endsWith ending) do
      check (artifact.getObjValD "sha256" == toJson digest) "unrelated plugin asset changed"
    files := files.push (artifact.setObjVal! "path" (toJson path.toString) |>.setObjVal! "sha256" (toJson digest))
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (before.getObjValD "environment"))
  let updates := #[("EGGSHELL_PREFIX",some (root/"prefix").toString),("PLUGIN_ROOT",some (root/"prefix/plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (root/"growing/data").toString),("TMPDIR",some (root/"tmp").toString)]
  IO.FS.createDirAll (root/"tmp")
  let installed := before
    |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (root/"prefix/libexec/eggshell").toString),
      ("sha256",toJson (← hash (root/"build/StudyMain")))])
    |>.setObjVal! "hookClient" (Json.mkObj [("path",toJson (root/"prefix/libexec/eggshell-hook").toString),
      ("sha256",toJson (← hash (root/"command-build/StudyMain")))])
    |>.setObjVal! "pluginRoot" (toJson (root/"prefix/plugins/eggshell").toString)
    |>.setObjVal! "pluginFiles" (toJson files)
    |>.setObjVal! "environment" (toJson (environment.filter (fun row => !updates.any (·.1 == row.1))++updates))
  write (root/"installation.json") installed
  write (records/"installation.json") installed
def prepareMixed : IO Unit := do
  idle
  discard <| finished "hook-command-connected-build"
  IO.FS.writeFile (root/"source/tools/research/MixedChatChecks.lean")
    (← IO.FS.readFile (project/"tools/research/MixedChatChecks.lean"))
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"mixed-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.MixedChatChecks")
  write (root/"mixed-settings.json") settings
  guard "hook-command-mixed-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"mixed-settings.json").toString]
def prepareNativeInstall : IO Unit := do
  idle
  check (!(← (records/"launcher-binding.json").pathExists) && (← (root/"prefix").pathExists))
    "only an unfinished isolated binding may be resumed"
  for name in ["egg","eggshelld"] do
    check ((← IO.FS.readFile (root/"prefix/plugins/eggshell/bin"/name)) ==
      (← IO.FS.readFile (parent/"prefix/plugins/eggshell/bin"/name))) "partial prefix has unrelated script changes"
  write (records/"configure-refusal.json") (Json.mkObj [
    ("error",toJson "Full-product interpreter exceeded -M768 during metadata binding"),
    ("sourceScriptUnchanged",toJson true),("databaseOrHookStarted",toJson false),
    ("guardLimitChanged",toJson false)])
  for name in ["HookCommandInstall","StudyLaunchers"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  let settings := (← read (root/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"install-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.HookCommandInstall")
  write (root/"install-settings.json") settings
  guard "hook-command-install-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"install-settings.json").toString]
def bindNative : IO Unit := do
  idle
  discard <| finished "hook-command-install-build"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",
    (root/"install-build").toString,(records/"install-native.json").toString]
  guard "hook-command-bind" #[(root/"install-build/StudyMain").toString,(root/"prefix").toString,
    (parent/"prefix").toString,(records/"launcher-binding.json").toString]
def finishConfigure : IO Unit := do
  idle
  discard <| finished "hook-command-bind"
  let binding ← read (records/"launcher-binding.json")
  check (binding.getObjValD "actualProductGeneratorUsed" == toJson true && binding.getObjValD "smallHookRequired" == toJson true)
    "native hook binding was not verified"
  let before ← read (parent/"installation.json")
  let mut files := #[]
  for artifact in ← IO.ofExcept (before.getObjValAs? (Array Json) "pluginFiles") do
    let old ← IO.ofExcept (artifact.getObjValAs? String "path")
    let oldRoot := (parent/"prefix").toString++"/"
    check (old.startsWith oldRoot) "plugin artifact escaped parent prefix"
    let path := root/"prefix"/(old.drop oldRoot.length |>.toString)
    let digest ← hash path
    unless ["plugins/eggshell/bin/egg","plugins/eggshell/bin/eggshelld"].any (fun suffix => path.toString.endsWith suffix) do
      check (artifact.getObjValD "sha256" == toJson digest) "unrelated plugin asset changed"
    files := files.push (artifact.setObjVal! "path" (toJson path.toString) |>.setObjVal! "sha256" (toJson digest))
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (before.getObjValD "environment"))
  let updates := #[("EGGSHELL_PREFIX",some (root/"prefix").toString),("PLUGIN_ROOT",some (root/"prefix/plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (root/"growing/data").toString),("TMPDIR",some (root/"tmp").toString)]
  IO.FS.createDirAll (root/"tmp")
  let installed := before
    |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (root/"prefix/libexec/eggshell").toString),
      ("sha256",toJson (← hash (root/"build/StudyMain")))])
    |>.setObjVal! "hookClient" (Json.mkObj [("path",toJson (root/"prefix/libexec/eggshell-hook").toString),
      ("sha256",toJson (← hash (root/"command-build/StudyMain")))])
    |>.setObjVal! "pluginRoot" (toJson (root/"prefix/plugins/eggshell").toString)
    |>.setObjVal! "pluginFiles" (toJson files)
    |>.setObjVal! "environment" (toJson (environment.filter (fun row => !updates.any (·.1 == row.1))++updates))
  write (root/"installation.json") installed
  write (records/"installation.json") installed
def auditMixed : IO Unit := do
  idle
  discard <| finished "hook-command-mixed-build"
  for args in [#["inspect",(root/"mixed-build").toString,(records/"mixed-native.json").toString],
      #["common-sources",(root/"build").toString,(root/"mixed-build").toString,(records/"mixed-sources.json").toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
def primeMixed : IO Unit := do
  idle
  check (!(← (base/"hook-command-mixed-build.guard.json").pathExists)) "mixed build already started"
  copyLocalArtifacts (root/"build") (root/"mixed-build")
def growth : IO Unit := do
  idle
  let checked ← read (records/"mixed-sources.json")
  let installed ← read (root/"installation.json")
  check (checked.getObjValD "commonSourcesUnchanged" == toJson true &&
    checked.getObjValD "allProductCorePresent" == toJson true &&
    checked.getObjValD "productSha256" == toJson (← hash (root/"build/StudyMain")) &&
    checked.getObjValD "productSha256" == (installed.getObjValD "runtime").getObjValD "sha256" &&
    checked.getObjValD "auditorSha256" == toJson (← hash (root/"mixed-build/StudyMain")) &&
    (installed.getObjValD "hookClient").getObjValD "sha256" == toJson (← hash (root/"command-build/StudyMain")))
    "mixed product/client/observer binding changed"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installed.getObjValD "environment"))
  let unsets := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let values := environment.filterMap fun (key,value) => value.map (fun item => key++"="++item)
  write (records/"growth-plan.json") (Json.mkObj [("mode",toJson "service-growth"),
    ("installation",installed),("observer",checked),("maxClients",toJson (14 : Nat)),
    ("samePhysicalOwner",toJson true),("writerTurns",toJson (25 : Nat)),("originalObservations",toJson (75 : Nat)),
    ("distinctFields",toJson (50 : Nat)),("manualKeepOrWarm",toJson false),("adopted",toJson false)])
  guard "hook-command-growth" (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "hook-command",(records/"growth.stdout").toString,(records/"growth.stderr").toString,"/usr/bin/env"]++
    unsets.flatMap (fun key => #["-u",key])++values++#[(root/"mixed-build/StudyMain").toString,"service-growth",
      (root/"installation.json").toString,(root/"growing").toString])
def retainGrowth : IO Unit := do
  idle
  let guard ← read (base/"hook-command-growth.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "mixed growth has not drained"
  let run := root/"growing"
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
  write (records/"growth-records.json") (Json.mkObj [("guard",guard),("calls",toJson calls),
    ("metadata",toJson metadata),("observer",← read (records/"mixed-sources.json")),
    ("fixtureSource",← read (root/"mixed-build/tools_research_MixedChatChecks.source"))])
def inspectGrowth : IO Unit := do
  idle
  let previous ← read (base/"hook-command-growth.guard.json")
  check (previous.getObjValD "state" == toJson "finished" && previous.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "growth workload has not drained"
  let installed ← read (root/"installation.json")
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installed.getObjValD "environment"))
  let unsets := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let values := environment.filterMap fun (key,value) => value.map (fun item => key++"="++item)
  guard "hook-command-growth-inspect" (#["/usr/bin/env"]++unsets.flatMap (fun key => #["-u",key])++values++
    #[(root/"mixed-build/StudyMain").toString,"inspect",(root/"growing").toString,(records/"growth-storage-inspect.json").toString])
def retainAndPlanCleanup : IO Unit := do
  idle
  discard <| finished "hook-command-growth-inspect"
  let partialSummary ← read (records/"completed-stages.json")
  check (partialSummary.getObjValD "wholeWorkloadSucceeded" == toJson false &&
    partialSummary.getObjValD "completedAdditionalWaves" == toJson (3 : Nat) &&
    partialSummary.getObjValD "queries" == toJson (52 : Nat) &&
    partialSummary.getObjValD "deliveredAppearances" == toJson (788 : Nat)) "retain the failed whole workload separately from completed stages"
  let inspection ← read (records/"growth-storage-inspect.json")
  check (inspection.getObjValD "readOnly" == toJson true && inspection.getObjValD "originalsUnchanged" == toJson true)
    "source storage inspection is not complete"
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "hook-command-" && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "unfinished hook-command guard cannot be retired"
      guards := guards.push (entry.fileName,value)
  write (records/"guard-records.json") (toJson guards)
  let commandBefore ← hash (root/"command-build/StudyMain")
  let parentBefore ← hash (parent/"build/StudyMain")
  write (records/"protected-products.json") (Json.mkObj [("smallCommandSha256",toJson commandBefore),
    ("parentSha256",toJson parentBefore),("backendSha256",toJson (← hash (root/"build/StudyMain")))])
  let targets := #["growing","checks","checks-native","checked-native","production-environment","tty-data", "fixture-build",
    "checks-build","install-build","mixed-build","helper-lib","tmp"]
  write (records/"cleanup-plan.json") (toJson (targets.map (fun (name : String) => (root/name).toString)))
def verifyCleanup : IO Unit := do
  idle
  let before ← read (records/"protected-products.json")
  check (before.getObjValD "smallCommandSha256" == toJson (← hash (root/"command-build/StudyMain"))) "small command changed during cleanup"
  check (before.getObjValD "parentSha256" == toJson (← hash (parent/"build/StudyMain"))) "fixed parent changed during cleanup"
  check (before.getObjValD "backendSha256" == toJson (← hash (root/"build/StudyMain"))) "backend changed during cleanup"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",
    (root/"command-build").toString,(records/"command-after-cleanup.json").toString]
end HookCommandStudy
def main : List String → IO Unit
  | ["prepare"] => HookCommandStudy.prepare
  | ["reset-incomplete-preparation"] => HookCommandStudy.resetIncompletePreparation
  | ["audit"] => HookCommandStudy.audit
  | ["prepare-command"] => HookCommandStudy.prepareCommand
  | ["checked-build"] => HookCommandStudy.checkedBuild
  | ["audit-command"] => HookCommandStudy.auditCommand
  | ["complete-inventory"] => HookCommandStudy.completeInventory
  | ["proofs"] => HookCommandStudy.proofs
  | ["prepare-fixture"] => HookCommandStudy.prepareFixture
  | ["audit-fixture"] => HookCommandStudy.auditFixture
  | ["checks"] => HookCommandStudy.checks
  | ["checked-checks"] => HookCommandStudy.checkedChecks
  | ["prepare-native-checks"] => HookCommandStudy.prepareNativeChecks
  | ["native-checks"] => HookCommandStudy.nativeChecks
  | ["repair-native-checks"] => HookCommandStudy.repairNativeChecks
  | ["checked-native-checks"] => HookCommandStudy.checkedNativeChecks
  | ["diagnose"] => HookCommandStudy.diagnose
  | ["production-environment-build"] => HookCommandStudy.productionEnvironmentBuild
  | ["production-environment-probe"] => HookCommandStudy.productionEnvironmentProbe
  | ["connect-build"] => HookCommandStudy.connectBuild
  | ["audit-connected"] => HookCommandStudy.auditConnected
  | ["configure"] => HookCommandStudy.configure
  | ["prepare-native-install"] => HookCommandStudy.prepareNativeInstall
  | ["bind-native"] => HookCommandStudy.bindNative
  | ["finish-configure"] => HookCommandStudy.finishConfigure
  | ["prepare-mixed"] => HookCommandStudy.prepareMixed
  | ["audit-mixed"] => HookCommandStudy.auditMixed
  | ["prime-mixed"] => HookCommandStudy.primeMixed
  | ["growth"] => HookCommandStudy.growth
  | ["retain-growth"] => HookCommandStudy.retainGrowth
  | ["inspect-growth"] => HookCommandStudy.inspectGrowth
  | ["retain-cleanup-plan"] => HookCommandStudy.retainAndPlanCleanup
  | ["verify-cleanup"] => HookCommandStudy.verifyCleanup
  | _ => throw (IO.userError "HookCommandStudy prepare")
