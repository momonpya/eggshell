import tools.research.StudyLocal
open Lean StudyLocal
namespace DelegatedConnectionStudy
def parent := base/"practical-runtime/hook-command"
def root := base/"practical-runtime/request-socket"
def records := project/"docs/candidates/delegated-connection"
def changed := #["Config","ProjectGateway","ProjectGatewayPeer","ProjectHookRead","Worker","PublicationService","PublicationWire"]
def prepare : IO Unit := do
  idle
  check (!(← records.pathExists) && !(← (root/"gateway-build").pathExists)) "fresh delegated integration required"
  check ((← hash (parent/"build/StudyMain")) == "ea5b3861dfba62fe0e600552a13facb59595304c67b28fa9f2d3f395d66e0e35") "fixed mixed-workload parent changed"
  let ffi ← read (project/"docs/candidates/request-socket/ffi.json")
  check (ffi.getObjValD "sourceSha256" == toJson (← hash (root/"source/Eggshell/Storage/socket.c")) &&
    ffi.getObjValD "objectSha256" == toJson (← hash (root/"socket.o"))) "verified OS leaf changed"
  IO.FS.createDirAll records
  copyLocalArtifacts (parent/"build") (root/"gateway-build")
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"gateway-build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString,(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"baseline.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"inherited-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.StudyMain")
  write (root/"gateway-settings.json") settings
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("ffi",ffi),("changedModules",toJson changed),("transport",toJson "request-owned direct loopback; immutable delegated host scopes"),
    ("readAuthority",toJson "complete captured manifest/cut with private service registration capabilities"),
    ("writeAuthority",toJson "one selected project; other projects read-only; source ACK unchanged"),
    ("firstWorkload",toJson "native authority/cancellation checks before the unchanged mixed lifecycle semantics"),
    ("maximumMacClients",toJson (16 : Nat)),("aggregateStopRssKiB",toJson (4358524 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenComparisons",toJson (0 : Nat)),("adopted",toJson false)])
  guard "delegated-connection-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"gateway-settings.json").toString]
def prepareChecks : IO Unit := do
  idle
  write (records/"build.guard.json") (← finished "delegated-connection-build")
  if (← (records/"sources.json").pathExists) && !(← (records/"sources-rejection.json").pathExists) then
    let previous ← read (records/"sources.json")
    if previous.getObjValD "exactExpectedChangeSet" != toJson true then
      write (records/"sources-rejection.json") (previous.setObjVal! "reason"
        (toJson "declared Lean inputs omitted the already audited C source embedded by implementation identities"))
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  if !(← (records/"native.json").pathExists) then
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditing.toString,
      "inspect",(root/"gateway-build").toString,(records/"native.json").toString]
  else
    check ((← read (records/"native.json")).getObjValD "consistent" == toJson true)
      "previous native closure did not validate"
  let leanClaims ← (changed.push "OwnedSocket").mapM fun name => do
    let path := root/"source/Eggshell"/(name++".lean")
    return "@"++(← hash path)++":"++path.toString
  let os := root/"source/Eggshell/Storage/socket.c"
  let claims := leanClaims.push ("@"++(← hash os)++":"++os.toString)
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString,
    "compare-sources",(parent/"build").toString,(root/"gateway-build").toString,(records/"sources-checked.json").toString]++
    changed.map ("Eggshell."++·)++#["+Eggshell.OwnedSocket"]++claims)
  let mut patch := ""
  for name in changed.push "OwnedSocket" do
    let path := "Eggshell/"++name++".lean"
    let added := name == "OwnedSocket"
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L",if added then "/dev/null" else "a/"++path,
      "-L","b/"++path,if added then "/dev/null" else (parent/"source"/path).toString,(root/"source"/path).toString]}
    check (result.exitCode ≤ 1) "cannot retain delegated product source patch"
    patch := patch++result.stdout
  IO.FS.writeFile (records/"candidate.patch") patch
  IO.FS.writeFile (root/"source/tools/research/DelegatedConnectionChecks.lean")
    (← IO.FS.readFile (project/"tools/research/DelegatedConnectionChecks.lean"))
  let settings := (← read (root/"gateway-build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"gateway-checks-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"gateway-build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"gateway-build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"gateway-build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"gateway-build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.DelegatedConnectionChecks")
  write (root/"gateway-checks-settings.json") settings
  guard "delegated-connection-checks-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"gateway-checks-settings.json").toString]
def repairChecks : IO Unit := do
  idle
  let stopped ← read (base/"delegated-connection-checks-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" == toJson (1 : Nat)) "only correct the stopped fixture elaboration"
  write (records/"checks-build-rejection.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"gateway-checks-build/tools_research_DelegatedConnectionChecks-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"gateway-checks-build/tools_research_DelegatedConnectionChecks-lean.stderr"))),
    ("fixtureSourceSha256",toJson (← hash (root/"source/tools/research/DelegatedConnectionChecks.lean"))),
    ("productChanged",toJson false),("modelCalls",toJson (0 : Nat))])
  IO.FS.writeFile (root/"source/tools/research/DelegatedConnectionChecks.lean")
    (← IO.FS.readFile (project/"tools/research/DelegatedConnectionChecks.lean"))
  guard "delegated-connection-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"gateway-checks-settings.json").toString]
def checks : IO Unit := do
  idle
  write (records/"checks-build.guard.json") (← finished "delegated-connection-checked-build")
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditing.toString,
    "inspect",(root/"gateway-checks-build").toString,(records/"checks-native.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditing.toString,
    "component-sources",(root/"gateway-build").toString,(root/"gateway-checks-build").toString,
    (records/"checks-sources.json").toString,"Eggshell.PublicationService","Eggshell.Config",
    "Eggshell.ProjectGateway","Eggshell.ProjectGatewayPeer","Eggshell.ProjectHookRead","Eggshell.NativePublication",
    "Eggshell.ProjectRead","Eggshell.ProjectInputs","Eggshell.ProjectPublication","Eggshell.DB.PageMap"]
  let (text,_included) : String × Array (String × String) ← IO.ofExcept
    (fromJson? (← read (root/"gateway-checks-build/tools_research_DelegatedConnectionChecks.source")))
  check (text == (← IO.FS.readFile (project/"tools/research/DelegatedConnectionChecks.lean")))
    "executed fixture differs from reviewable source"
  let ffi ← read (project/"docs/candidates/request-socket/ffi.json")
  check (ffi.getObjValD "sourceSha256" == toJson (← hash (root/"source/Eggshell/Storage/socket.c")) &&
    ffi.getObjValD "objectSha256" == toJson (← hash (root/"socket.o"))) "native transport changed"
  write (records/"run-plan.json") (Json.mkObj [("runtimeSha256",toJson (← hash (root/"gateway-build/StudyMain"))),
    ("fixtureSha256",toJson (← hash (root/"gateway-checks-build/StudyMain"))),
    ("ffi",ffi),("maximumConcurrentWriters",toJson (10 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
  guard "delegated-connection-checks" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_PREFIX="++(parent/"prefix").toString,
    "EGGSHELL_DATA_ROOT="++(root/"authority/host").toString,
    (root/"gateway-checks-build/StudyMain").toString,"checks",(root/"gateway-build/StudyMain").toString,
    (root/"authority").toString,(records/"checks.json").toString]
def proofs : IO Unit := do
  idle
  guard "delegated-connection-proofs" #["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "delegated-proof",(records/"proofs.stdout").toString,(records/"proofs.stderr").toString,
    "/usr/bin/env","LEAN_PATH="++(root/"gateway-build/lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M1536","-DwarningAsError=true",
    (project/"tools/research/DelegatedConnectionAudit.lean").toString]
def retryProofs (previous stage before after : String) : IO Unit := do
  idle
  let stopped ← read (base/("delegated-connection-"++previous++".guard.json"))
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" == toJson (1 : Nat)) "only correct the stopped meta auditor"
  write (records/(previous++"-rejection.json")) (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (records/(before++".stdout")))),
    ("stderr",toJson (← IO.FS.readFile (records/(before++".stderr")))),
    ("reason",toJson "all six theorems elaborated; correct the static effect auditor without changing product code"),
    ("productChanged",toJson false)])
  guard ("delegated-connection-"++stage) #["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "delegated-proof",(records/(after++".stdout")).toString,(records/(after++".stderr")).toString,
    "/usr/bin/env","LEAN_PATH="++(root/"gateway-build/lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M1536","-DwarningAsError=true",
    (project/"tools/research/DelegatedConnectionAudit.lean").toString]
def replace (text before after : String) : IO String := do
  let [left,right] := text.splitOn before | throw (IO.userError ("nonunique fixture source anchor: "++before))
  return left++after++right
def prepareMixed : IO Unit := do
  idle
  write (records/"checks.guard.json") (← finished "delegated-connection-checks")
  write (records/"proofs.guard.json") (← finished "delegated-connection-effect-proofs")
  let checks ← read (records/"checks.json")
  check (checks.getObjValD "concurrentWriters" == toJson (10 : Nat) &&
    checks.getObjValD "actualPublisherRestart" == toJson true &&
    checks.getObjValD "rawAuthorityRejections" == toJson (8 : Nat)) "native delegation checks did not complete"
  check (!(← (root/"connection-mixed-build").pathExists)) "fresh mixed observer required"
  let original ← IO.FS.readFile (parent/"source/tools/research/MixedChatChecks.lean")
  check (original == (← IO.FS.readFile (project/"tools/research/MixedChatChecks.lean")))
    "mixed lifecycle oracle differs from the previous fourteen-client run"
  let text ← replace original "(command : Array String) (groups : Array String)" "(transport : Json) (groups : Array String)"
  let text ← replace text "(toJson command).compress" "transport.compress"
  let text ← replace text "(sharedOwner : Bool := false) (remote : Bool := false) : IO Unit := do"
    "(sharedOwner : Bool := false) (remote : Bool := false) (direct : Bool := false) : IO Unit := do"
  let text ← replace text "remoteConfig plan.runtime.path command #[\"ALPHA\",\"BETA\"] (some name)"
    "remoteConfig plan.runtime.path (if direct then toJson (root/\"connections\"/(\"write-\"++name++\".json\")).toString else toJson command) #[\"ALPHA\",\"BETA\"] (some name)"
  let text ← replace text "remoteConfig plan.runtime.path command #[name] none"
    "remoteConfig plan.runtime.path (if direct then toJson (root/\"connections\"/(\"read-\"++name++\".json\")).toString else toJson command) #[name] none"
  let text ← replace text "remoteConfig plan.runtime.path command #[\"ALPHA\",\"BETA\"] none"
    "remoteConfig plan.runtime.path (if direct then toJson (root/\"connections/read-both.json\").toString else toJson command) #[\"ALPHA\",\"BETA\"] none"
  let extra := "    if direct then\n"++
    "      let catalog : Publication.Gateway.Catalog ← IO.ofExcept (fromJson? (← StudyAdmission.readJson catalog.toString))\n"++
    "      let mut grants : Array Publication.Gateway.Delegation := #[]\n"++
    "      for name in [\"ALPHA\",\"BETA\"] do\n"++
    "        for (label,selection) in [(\"write-\"++name,(⟨#[\"ALPHA\",\"BETA\"],some name⟩ : Publication.Gateway.Selection)),\n"++
    "            (\"read-\"++name,(⟨#[name],none⟩ : Publication.Gateway.Selection))] do\n"++
    "          grants := grants.push ⟨selection,Blake3.hex (← IO.getRandomBytes 32),(root/\"connections\"/(label++\".json\")).toString⟩\n"++
    "      grants := grants.push ⟨⟨#[\"ALPHA\",\"BETA\"],none⟩,Blake3.hex (← IO.getRandomBytes 32),(root/\"connections/read-both.json\").toString⟩\n"++
    "      Plugin.writeJson (host/\"publisher/project-access.json\") (⟨catalog,grants⟩ : Publication.Gateway.Host)\n"
  let sessions := "  let mut sessions := #[]\n  for (group,slot) in [(\"ALPHA\",0),(\"ALPHA\",1),(\"BETA\",2),(\"BETA\",3)] do"
  let text ← replace text sessions (extra++sessions)
  let text ← replace text "def main (args : List String) : IO UInt32 := do"
    "def mixedMain (args : List String) : IO UInt32 := do"
  IO.FS.writeFile (root/"source/tools/research/MixedChatChecks.lean") text
  IO.FS.writeFile (root/"source/tools/research/DelegatedConnectionMixed.lean")
    (← IO.FS.readFile (project/"tools/research/DelegatedConnectionMixed.lean"))
  IO.FS.writeFile (root/"source/tools/research/StudyLaunchers.lean")
    (← IO.FS.readFile (project/"tools/research/StudyLaunchers.lean"))
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/tools/research/MixedChatChecks.lean",
    "-L","b/tools/research/MixedChatChecks.lean",(parent/"source/tools/research/MixedChatChecks.lean").toString,
    (root/"source/tools/research/MixedChatChecks.lean").toString]}
  check (diff.exitCode == 1) "mixed transport-only change is missing"
  IO.FS.writeFile (records/"mixed-transport.patch") diff.stdout
  copyLocalArtifacts (root/"gateway-build") (root/"connection-mixed-build")
  let settings := (← read (root/"gateway-build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"connection-mixed-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"gateway-build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"gateway-build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"gateway-build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"gateway-build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.DelegatedConnectionMixed")
  write (root/"connection-mixed-settings.json") settings
  guard "delegated-connection-mixed-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"connection-mixed-settings.json").toString]
def repairMixed : IO Unit := do
  idle
  let stopped ← read (base/"delegated-connection-mixed-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" == toJson (1 : Nat)) "only repair the stopped observer entry conflict"
  write (records/"mixed-build-rejection.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"connection-mixed-build/tools_research_DelegatedConnectionMixed-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"connection-mixed-build/tools_research_DelegatedConnectionMixed-lean.stderr"))),
    ("productChanged",toJson false),("hookCalls",toJson (0 : Nat))])
  let path := root/"source/tools/research/MixedChatChecks.lean"
  IO.FS.writeFile path (← replace (← IO.FS.readFile path) "def main (args : List String) : IO UInt32 := do"
    "def mixedMain (args : List String) : IO UInt32 := do")
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/tools/research/MixedChatChecks.lean",
    "-L","b/tools/research/MixedChatChecks.lean",(parent/"source/tools/research/MixedChatChecks.lean").toString,path.toString]}
  check (diff.exitCode == 1) "missing fixed mixed observer patch"
  IO.FS.writeFile (records/"mixed-transport.patch") diff.stdout
  guard "delegated-connection-mixed-entry-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"connection-mixed-settings.json").toString]
def bind : IO Unit := do
  idle
  write (records/"mixed-build.guard.json") (← finished "delegated-connection-mixed-entry-build")
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for arguments in [#["inspect",(root/"connection-mixed-build").toString,(records/"mixed-native.json").toString],
      #["common-sources",(root/"gateway-build").toString,(root/"connection-mixed-build").toString,
        (records/"mixed-sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString]++arguments)
  let client ← read (project/"docs/candidates/hook-command/command-modules.json")
  let required : Array String ← IO.ofExcept (client.getObjValAs? _ "allCommandProductModulesCompared")
  check (client.getObjValD "commandSha256" == toJson (← hash (parent/"command-build/StudyMain"))) "small client changed"
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditing.toString,
    "component-sources",(root/"gateway-build").toString,(parent/"command-build").toString,
    (records/"small-client-sources.json").toString]++required)
  check (!(← (root/"prefix").pathExists)) "fresh isolated prefix required"
  discard <| command "/bin/cp" #["-cR",(parent/"prefix").toString,(root/"prefix").toString]
  let backend := root/"prefix/libexec/eggshell"
  check ((← backend.symlinkMetadata).type == .symlink) "copied backend was not the declared link"
  IO.FS.removeFile backend
  discard <| command "/bin/ln" #["-s",(root/"gateway-build/StudyMain").toString,backend.toString]
  check ((← hash (root/"prefix/libexec/eggshell-hook")) ==
    (← hash (parent/"command-build/StudyMain"))) "isolated prefix changed its small supervisor"
  guard "delegated-connection-bind" #[(root/"connection-mixed-build/StudyMain").toString,
    "bind",(root/"prefix").toString,(parent/"prefix").toString,(records/"launcher-binding.json").toString]
def configure : IO Unit := do
  idle
  write (records/"bind.guard.json") (← finished "delegated-connection-bind")
  check ((← read (records/"launcher-binding.json")).getObjValD "actualProductGeneratorUsed" == toJson true)
    "ordinary launchers were not generated by the product"
  let before ← read (parent/"installation.json")
  let mut files := #[]
  for artifact in ← IO.ofExcept (before.getObjValAs? (Array Json) "pluginFiles") do
    let old ← IO.ofExcept (artifact.getObjValAs? String "path")
    let oldRoot := (parent/"prefix").toString++"/"
    check (old.startsWith oldRoot) "parent plugin path escaped its prefix"
    let path := root/"prefix"/(old.drop oldRoot.length |>.toString)
    let digest ← hash path
    unless ["plugins/eggshell/bin/egg","plugins/eggshell/bin/eggshelld"].any (path.toString.endsWith ·) do
      check (artifact.getObjValD "sha256" == toJson digest) "unrelated plugin asset changed"
    files := files.push (artifact.setObjVal! "path" (toJson path.toString) |>.setObjVal! "sha256" (toJson digest))
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (before.getObjValD "environment"))
  let updates := #[("EGGSHELL_PREFIX",some (root/"prefix").toString),
    ("PLUGIN_ROOT",some (root/"prefix/plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (root/"growing/data").toString),("TMPDIR",some (root/"tmp").toString)]
  IO.FS.createDirAll (root/"tmp")
  let installed := before
    |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (root/"prefix/libexec/eggshell").toString),
      ("sha256",toJson (← hash (root/"gateway-build/StudyMain")))])
    |>.setObjVal! "hookClient" (Json.mkObj [("path",toJson (root/"prefix/libexec/eggshell-hook").toString),
      ("sha256",toJson (← hash (parent/"command-build/StudyMain")))])
    |>.setObjVal! "pluginRoot" (toJson (root/"prefix/plugins/eggshell").toString)
    |>.setObjVal! "pluginFiles" (toJson files)
    |>.setObjVal! "environment" (toJson (environment.filter (fun row => !updates.any (·.1 == row.1))++updates))
  write (root/"connection-installation.json") installed
  write (records/"installation.json") installed
def growth : IO Unit := do
  idle
  let installation ← read (root/"connection-installation.json")
  let checked ← read (records/"mixed-sources.json")
  check (checked.getObjValD "allProductCorePresent" == toJson true &&
    checked.getObjValD "commonSourcesUnchanged" == toJson true &&
    checked.getObjValD "productSha256" == toJson (← hash (root/"gateway-build/StudyMain")) &&
    checked.getObjValD "auditorSha256" == toJson (← hash (root/"connection-mixed-build/StudyMain")) &&
    (installation.getObjValD "runtime").getObjValD "sha256" == checked.getObjValD "productSha256")
    "mixed product/observer binding changed"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let unsets := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let values := environment.filterMap fun (key,value) => value.map (fun item => key++"="++item)
  write (records/"growth-plan.json") (Json.mkObj [("installation",installation),("observer",checked),
    ("projects",toJson (2 : Nat)),("ownersPerProject",toJson (4 : Nat)),("writers",toJson (4 : Nat)),
    ("maxClients",toJson (14 : Nat)),("growthWaves",toJson (4 : Nat)),("writerTurns",toJson (25 : Nat)),
    ("originalObservations",toJson (75 : Nat)),("distinctFields",toJson (50 : Nat)),
    ("scope",toJson "same lifecycle/storage/delivery oracle; only transport configuration and observer entry changed"),
    ("manualKeepOrWarm",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "delegated-connection-growth" (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "delegated-growth",(records/"growth.stdout").toString,(records/"growth.stderr").toString,"/usr/bin/env"]++
    unsets.flatMap (fun key => #["-u",key])++values++#[(root/"connection-mixed-build/StudyMain").toString,"growth",
      (root/"connection-installation.json").toString,(root/"growing").toString])
def retain : IO Unit := do
  idle
  let completed ← finished "delegated-connection-growth"
  write (records/"growth.guard.json") completed
  let run := root/"growing"
  let mut calls := #[]
  for session in ← (run/"calls").readDir do
    for call in ← session.path.readDir do
      if !(← (call.path/"record.json").pathExists) then continue
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("record",← read (call.path/"record.json")),("input",toJson (← IO.FS.readFile (call.path/"stdin"))),
        ("stdout",toJson (← IO.FS.readFile (call.path/"stdout"))),("stderr",toJson (← IO.FS.readFile (call.path/"stderr")))])
  let mut metadata := #[]
  for entry in ← run.readDir do
    if entry.fileName.endsWith ".json" then metadata := metadata.push (entry.fileName,← read entry.path)
  write (records/"growth-records.json") (Json.mkObj [("guard",completed),("calls",toJson calls),
    ("metadata",toJson metadata),("observer",← read (records/"mixed-sources.json")),
    ("fixtureSource",← read (root/"connection-mixed-build/tools_research_MixedChatChecks.source"))])
  let result ← read (run/"result.json")
  check (result.getObjValD "finalOriginalObservations" == toJson (75 : Nat) &&
    result.getObjValD "finalWriterTurns" == toJson (25 : Nat)) "mixed source capture did not reach the final wave"
  let summary ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768","--run",(project/"tools/research/NativeMixedSummary.lean").toString,
      (records/"growth-records.json").toString,(records/"summary.json").toString],
    env := #[("LEAN_PATH",some ((base/"study-local-lib").toString++":"++(root/"connection-mixed-build/lib").toString))]}
  check (summary.exitCode == 0) (summary.stdout++summary.stderr)
  let installed ← read (root/"connection-installation.json")
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installed.getObjValD "environment"))
  let unsets := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let values := environment.filterMap fun (key,value) => value.map (fun item => key++"="++item)
  guard "delegated-connection-storage" (#["/usr/bin/env"]++unsets.flatMap (fun key => #["-u",key])++values++
    #[(root/"connection-mixed-build/StudyMain").toString,"inspect",run.toString,(records/"storage.json").toString])
def block (text first after : String) : IO String := do
  let [_before,tail] := text.splitOn first | throw (IO.userError "nonunique original operation body")
  let [body,_after] := tail.splitOn after | throw (IO.userError "nonunique original operation boundary")
  return (first++body).trimAscii.toString
def finalizeEvidence : IO Unit := do
  idle
  write (records/"storage.guard.json") (← finished "delegated-connection-storage")
  let summary ← read (records/"summary.json")
  check (summary.getObjValD "wholeWorkloadSucceeded" == toJson true &&
    summary.getObjValD "queries" == toJson (72 : Nat) && summary.getObjValD "semanticCompleted" == toJson (72 : Nat) &&
    summary.getObjValD "requiredAppearances" == summary.getObjValD "deliveredAppearances" &&
    summary.getObjValD "completedAdditionalWaves" == toJson (4 : Nat)) "full mixed workload has not passed"
  let storage ← read (records/"storage.json")
  let fields : Array Json ← IO.ofExcept (storage.getObjValAs? _ "rawFields")
  let inventory := storage.getObjValD "inventory"
  let originals : Array Json ← IO.ofExcept (inventory.getObjValAs? _ "native")
  let answers : Array String ← IO.ofExcept (inventory.getObjValAs? _ "answers")
  let unknown : Array Json ← IO.ofExcept (inventory.getObjValAs? _ "withoutVerifiedInterval")
  let frozen : Array (String × Json) ← IO.ofExcept (fromJson? (← read (root/"growing/growth-required-3.json")))
  let finalRows : Array Json ← IO.ofExcept ((← read (root/"growing/growth-final-readers.json")).getObjValAs? _ "rows")
  let mut required := (#[] : Array Json)
  for row in finalRows do
    let groups : Array String ← IO.ofExcept (row.getObjValAs? _ "groups")
    let actual : Array Json ← IO.ofExcept (row.getObjValAs? _ "required")
    let expected := (frozen.filter (fun item => groups.contains item.1)).map (·.2)
    check (actual.size == expected.size && expected.all actual.contains) "final query changed its frozen project-specific requirement set"
    for item in actual do
      if !required.contains item then required := required.push item
  check (storage.getObjValD "readOnly" == toJson true && storage.getObjValD "originalsUnchanged" == toJson true &&
    originals.size == 75 && answers.size == 25 && fields.size == 50 &&
    fields.all (fun field => field.getObjValD "present" == toJson true) && frozen.size == 50 &&
    required.size == 50 && frozen.all (fun item => required.contains item.2)) "native storage or final frozen requirement inventory is incomplete"
  write (records/"storage-summary.json") (Json.mkObj [("nativeOriginals",toJson originals.size),
    ("answers",toJson answers.size),("storedFields",toJson fields.size),("finalFrozenDistinctRequirements",toJson frozen.size),
    ("allFinalFrozenRequirementsInIndependentlyCheckedQueries",toJson true),
    ("verifiedIntervals",inventory.getObjValD "timedObservations"),("unknownIntervals",toJson unknown.size),
    ("readOnly",toJson true),("originalsUnchanged",toJson true),
    ("wholeRunStatusSource",toJson "growth.guard.json and independent summary.json"),
    ("rawInspectorLegacyConstantNotAStatusMeasurement",storage.getObjValD "originalRunPassed")])
  let original ← IO.FS.readFile (parent/"source/Eggshell/ProjectGateway.lean")
  let audit ← IO.FS.readFile (project/"tools/research/DelegatedConnectionAudit.lean")
  let pin ← block original "def pin (" "\ninductive Operation"
  let previous ← block audit "def originalPin (" "\n/-- The preceding"
  check (pin == previous.replace "def originalPin (" "def pin (") "original pin proof body differs from fixed parent"
  let execute ← block original "def execute (" "\n/-- A connection"
  let previous ← block audit "def originalExecute (" "\ntheorem executor_preserves"
  check (execute == (previous.replace "def originalExecute (" "def execute (").replace "originalPin endpoint" "pin endpoint")
    "original execute proof body differs from fixed parent"
  let output ← IO.FS.readFile (records/"proofs-effects.stdout")
  let errors ← IO.FS.readFile (records/"proofs-effects.stderr")
  check (errors.isEmpty && !output.contains "sorryAx" && !output.contains "Lean.trustCompiler" &&
    !output.contains "Lean.ofReduceBool" && output.contains "1308 declarations") "proof/effect audit did not finish"
  write (records/"proofs.json") (Json.mkObj [("stdout",toJson output),("stderr",toJson errors),
    ("sourceSha256",toJson (← hash (project/"tools/research/DelegatedConnectionAudit.lean"))),
    ("originalBodiesBoundToFixedParent",toJson true),("standardAxiomsOnly",toJson true)])
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "delegated-connection-" && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "a delegated stage remains live"
      guards := guards.push (entry.fileName,value)
  write (records/"guard-records.json") (toJson guards)
  let mut inputs : Array (String × String) := #[]
  for line in (← IO.FS.readFile (root/"gateway-build/runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    if path.endsWith ".o" then inputs := inputs.push (path,← hash (.mk path))
  check ((inputs.filter (·.1 == (root/"socket.o").toString)).size == 1) "OS object must be linked exactly once"
  for path in [root/"gateway-build/StudyMain",parent/"build/StudyMain",parent/"command-build/StudyMain"] do
    inputs := inputs.push (path.toString,← hash path)
  write (records/"protected-native-inputs.json") (toJson inputs)
  let mut targets := #[root/"authority",root/"growing",root/"gateway-checks-build",root/"connection-mixed-build",root/"tmp"]
  for entry in ← (root/"gateway-build").readDir do
    if entry.fileName.endsWith ".c" then targets := targets.push entry.path
    else if entry.fileName.endsWith ".o" && !(inputs.any (·.1 == entry.path.toString)) then
      for extension in ["o","source","dependencies"] do
        let path := entry.path.withExtension extension
        if ← path.pathExists then targets := targets.push path
    else if (entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr") &&
        (← entry.path.metadata).byteSize == 0 then targets := targets.push entry.path
  check (targets.all fun target => !(inputs.any fun (path,_) =>
    path == target.toString || path.startsWith (target.toString++"/"))) "cleanup includes a live native input"
  write (records/"cleanup-plan.json") (toJson targets)
def afterCleanup : IO Unit := do
  idle
  let inputs : Array (String × String) ← IO.ofExcept (fromJson? (← read (records/"protected-native-inputs.json")))
  for (path,digest) in inputs do check ((← hash (.mk path)) == digest) "protected native input changed during cleanup"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  for (build,name) in [(root/"gateway-build","candidate-after-cleanup.json"),(parent/"build","parent-after-cleanup.json"),
      (parent/"command-build","client-after-cleanup.json")] do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditing.toString,
      "inspect",build.toString,(records/name).toString]
def pruneReviewDuplicates : IO Unit := do
  idle
  let mut removed : Array (String × Nat) := #[]
  for (name,retained) in [("proofs.stdout","proofs-rejection.json"),
      ("proofs-checked.stdout","checked-proofs-rejection.json"),("proofs-final.stdout","meta-proofs-rejection.json"),
      ("proofs-effects.stdout","proofs.json")] do
    let bytes ← IO.FS.readFile (records/name)
    check ((← read (records/retained)).getObjValD "stdout" == toJson bytes) "compact proof record lost its raw output"
    removed := removed.push (name,bytes.utf8ByteSize)
    IO.FS.removeFile (records/name)
  let original ← read (records/"sources.json")
  let retained ← read (records/"sources-rejection.json")
  for (key,value) in (← IO.ofExcept original.getObj?).toArray do
    check (retained.getObjValD key == value) "compact source refusal lost its original fields"
  removed := removed.push ("sources.json",(← IO.FS.readFile (records/"sources.json")).utf8ByteSize)
  IO.FS.removeFile (records/"sources.json")
  write (records/"duplicate-logs-removed.json") (Json.mkObj [("removed",toJson removed),
    ("compactEvidencePreservedExactly",toJson true),("archiveCreated",toJson false)])
def reviewArtifacts : IO Unit := do
  idle
  let storage ← read (records/"storage.json")
  write (records/"storage.json") storage
  check ((← read (records/"storage.json")) == storage) "JSON whitespace compaction changed storage evidence"
  let mut patch := ""
  for name in changed.push "OwnedSocket" do
    let path := "Eggshell/"++name++".lean"
    let added := name == "OwnedSocket"
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L",if added then "/dev/null" else "a/"++path,
      "-L","b/"++path,if added then "/dev/null" else (parent/"source"/path).toString,(root/"source"/path).toString]}
    check (result.exitCode == 1) "candidate review patch no longer describes a changed module"
    patch := patch++result.stdout
  IO.FS.writeFile (records/"candidate.patch") patch
  let (fixture,_inputs) : String × Array (String × String) ← IO.ofExcept
    (fromJson? ((← read (records/"growth-records.json")).getObjValD "fixtureSource"))
  let path := "tools/research/MixedChatChecks.lean"
  check (fixture == (← IO.FS.readFile (root/"source"/path))) "retained mixed fixture source changed"
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/"++path,"-L","b/"++path,
    (parent/"source"/path).toString,(root/"source"/path).toString]}
  check (diff.exitCode == 1) "missing mixed review diff"
  IO.FS.writeFile (records/"mixed-transport.patch") diff.stdout
end DelegatedConnectionStudy
def main : List String → IO Unit
  | ["prepare"] => DelegatedConnectionStudy.prepare
  | ["prepare-checks"] => DelegatedConnectionStudy.prepareChecks
  | ["repair-checks"] => DelegatedConnectionStudy.repairChecks
  | ["checks"] => DelegatedConnectionStudy.checks
  | ["proofs"] => DelegatedConnectionStudy.proofs
  | ["checked-proofs"] => DelegatedConnectionStudy.retryProofs "proofs" "checked-proofs" "proofs" "proofs-checked"
  | ["meta-proofs"] => DelegatedConnectionStudy.retryProofs "checked-proofs" "meta-proofs" "proofs-checked" "proofs-final"
  | ["effect-proofs"] => DelegatedConnectionStudy.retryProofs "meta-proofs" "effect-proofs" "proofs-final" "proofs-effects"
  | ["prepare-mixed"] => DelegatedConnectionStudy.prepareMixed
  | ["repair-mixed"] => DelegatedConnectionStudy.repairMixed
  | ["bind"] => DelegatedConnectionStudy.bind
  | ["configure"] => DelegatedConnectionStudy.configure
  | ["growth"] => DelegatedConnectionStudy.growth
  | ["retain"] => DelegatedConnectionStudy.retain
  | ["seal"] => DelegatedConnectionStudy.finalizeEvidence
  | ["after-cleanup"] => DelegatedConnectionStudy.afterCleanup
  | ["prune-review-duplicates"] => DelegatedConnectionStudy.pruneReviewDuplicates
  | ["review-artifacts"] => DelegatedConnectionStudy.reviewArtifacts
  | _ => throw (IO.userError "DelegatedConnectionStudy prepare|prepare-checks|repair-checks|checks|proofs|checked-proofs|meta-proofs|effect-proofs|prepare-mixed|repair-mixed|bind|configure|growth|retain|seal|after-cleanup|prune-review-duplicates|review-artifacts")
