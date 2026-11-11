import tools.research.StudyLocal
open Lean StudyLocal
namespace IndependentMaintenanceStudy
def practical := base/"practical-runtime"
def parent := practical/"coordinated-warm"
def root := practical/"independent-maintenance"
def records := project/"docs/candidates/independent-maintenance"

def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← (records/"plan.json").pathExists)) "fresh isolated maintenance candidate required"
  check ((← hash (parent/"build/StudyMain")) == "0411e4921419b4948f97aebdb6436a3c2de92087c150f15515d2eb67f7545fec") "fixed product changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  for name in ["source","build","prefix"] do
    discard <| command "/bin/cp" #["-cR",(parent/name).toString,(root/name).toString]
  for name in ["SharedProjectLifecycle.lean","SharedTrafficChecks.lean","RegisteredHook.lean","IndependentMaintenanceChecks.lean"] do
    IO.FS.writeFile (root/"source/tools/research"/name) (← IO.FS.readFile (project/"tools/research"/name))
  let entry := root/"source/tools/research/StudyMain.lean"
  let original ← IO.FS.readFile entry
  let marker := "  | other => sourceRouteEngine other"
  check ((original.splitOn marker).length == 2) "controller dispatcher changed"
  IO.FS.writeFile entry ("import tools.research.SharedTrafficChecks\nimport tools.research.IndependentMaintenanceChecks\n" ++
    original.replace marker ("  | [\"maintenance-controls\"] => Eggshell.Research.IndependentMaintenanceChecks.run; return 0\n" ++
      "  | [\"shared-traffic\",input,directory] => Eggshell.Research.SharedTrafficChecks.run input directory; return 0\n"++marker))
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "force" (toJson (#[] : Array String))
  write (root/"build-settings.json") settings
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("sourcePreparationIndependent",toJson true),("newNativeWorkers",toJson (0 : Nat)),
    ("changedCore",toJson #["Eggshell.HookFrontend"]),("mixedClients",toJson (10 : Nat)),
    ("mixedWaves",toJson (3 : Nat)),("registeredCommands",toJson true),("manualKeepUsed",toJson false),
    ("modelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def sealCandidate : IO Unit := do
  idle
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/Eggshell/HookFrontend.lean",
    "-L","b/Eggshell/HookFrontend.lean",(parent/"source/Eggshell/HookFrontend.lean").toString,
    (root/"source/Eggshell/HookFrontend.lean").toString]}
  check (patch.exitCode == 1 && !patch.stdout.isEmpty) "candidate must change the actual frontend"
  check (!(← (records/"candidate.patch").pathExists)) "preserve sealed candidate source"
  IO.FS.writeFile (records/"candidate.patch") patch.stdout
  guard "independent-maintenance-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]

def revise : IO Unit := do
  idle
  let previous ← finished "independent-maintenance-build"
  let digest ← hash (records/"candidate.patch")
  write (records/"rejected-draft.json") (Json.mkObj [("patchSha256",toJson digest),("build",previous),
    ("reason",toJson "source completion must invalidate an in-flight preparation result"),
    ("hookCalls",toJson (0 : Nat)),("modelCalls",toJson (0 : Nat))])
  IO.FS.writeFile (root/"source/tools/research/IndependentMaintenanceChecks.lean")
    (← IO.FS.readFile (project/"tools/research/IndependentMaintenanceChecks.lean"))
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/Eggshell/HookFrontend.lean",
    "-L","b/Eggshell/HookFrontend.lean",(parent/"source/Eggshell/HookFrontend.lean").toString,
    (root/"source/Eggshell/HookFrontend.lean").toString]}
  check (patch.exitCode == 1) "corrected source candidate required"
  IO.FS.writeFile (records/"candidate.patch") patch.stdout
  guard "independent-maintenance-epoch-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]

def rebuild (previous next : String) : IO Unit := do
  idle
  let stopped ← read (base/(previous++".guard.json"))
  check (stopped.getObjValD "state" == toJson "finished" &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous native build is live"
  write (records/"build-attempt.json") (Json.mkObj [("guard",stopped),
    ("error",toJson (← IO.FS.readFile (root/"build/Eggshell_HookFrontend-lean.stdout")))])
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/Eggshell/HookFrontend.lean",
    "-L","b/Eggshell/HookFrontend.lean",(parent/"source/Eggshell/HookFrontend.lean").toString,
    (root/"source/Eggshell/HookFrontend.lean").toString]}
  check (patch.exitCode == 1) "source candidate required"
  IO.FS.writeFile (records/"candidate.patch") patch.stdout
  guard next #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]

def configure : IO Unit := do
  idle
  discard <| finished "independent-maintenance-checked-build"
  let executable := root/"prefix/libexec/eggshell"
  check ((← executable.symlinkMetadata).type == .symlink &&
    (← IO.FS.realPath executable) == (← IO.FS.realPath (parent/"build/StudyMain"))) "candidate alias is not the inherited product"
  IO.FS.removeFile executable
  discard <| command "/bin/ln" #["-s",(root/"build/StudyMain").toString,executable.toString]
  let previous ← read (parent/"owner-lifecycle-input.json")
  let plugin := root/"prefix/plugins/eggshell"
  let mut files := #[]
  for file in ← IO.ofExcept (previous.getObjValAs? (Array Json) "pluginFiles") do
    let old ← IO.ofExcept (file.getObjValAs? String "path")
    let oldRoot := (parent/"prefix").toString++"/"
    check (old.startsWith oldRoot) "sealed plugin artifact is outside its prefix"
    let path := root/"prefix"/(old.drop oldRoot.length |>.toString)
    check (toJson (← hash path) == file.getObjValD "sha256") "copied plugin changed"
    files := files.push (file.setObjVal! "path" (toJson path.toString))
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (previous.getObjValD "environment"))
  let updates := #[("EGGSHELL_PREFIX",some (root/"prefix").toString),("PLUGIN_ROOT",some plugin.toString),
    ("EGGSHELL_DATA_ROOT",some (root/"run/data").toString),("TMPDIR",some (root/"tmp").toString)]
  let environment := environment.filter (fun row => !updates.any (·.1 == row.1)) ++ updates
  IO.FS.createDirAll (root/"tmp")
  let installation := previous
    |>.setObjVal! "runtime" (Json.mkObj [("path",toJson executable.toString),("sha256",toJson (← hash executable))])
    |>.setObjVal! "pluginRoot" (toJson plugin.toString)
    |>.setObjVal! "pluginFiles" (toJson files)
    |>.setObjVal! "environment" (toJson environment)
  check (!(← (root/"installation.json").pathExists)) "preserve sealed candidate installation"
  write (root/"installation.json") installation
  write (records/"identity.json") (Json.mkObj [("runtime",installation.getObjValD "runtime"),
    ("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("patchSha256",toJson (← hash (records/"candidate.patch"))),("globalInstallChanged",toJson false)])
  guard "independent-maintenance-controls" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    "EGGSHELL_DATA_ROOT="++(root/"control-data").toString,"EGGSHELL_PREFIX="++(root/"prefix").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/IndependentMaintenanceStudy.lean").toString,"__controls"]

def runControls : IO Unit := do
  let installation ← read (root/"installation.json")
  check (toJson (← hash (root/"build/StudyMain")) == (installation.getObjValD "runtime").getObjValD "sha256")
    "native control differs from its sealed candidate"
  let laws := root/"laws.lean"
  IO.FS.writeFile laws ("import Eggshell.HookFrontend\nimport tools.research.IndependentMaintenanceChecks\n" ++
    "#print axioms Eggshell.Plugin.HookFrontend.OwnedTasks.preparation_cannot_block_source\n" ++
    "#print axioms Eggshell.Plugin.HookFrontend.OwnedTasks.duplicate_source_refused\n" ++
    "#print axioms Eggshell.Plugin.HookFrontend.Session.stale_save_ignored\n" ++
    "#print axioms Eggshell.Plugin.HookFrontend.Session.stale_preparation_ignored\n" ++
    "#print axioms Eggshell.Plugin.HookFrontend.Session.old_preparation_cannot_close_after_save\n" ++
    "#print axioms Eggshell.Research.IndependentMaintenanceChecks.unchanged_epoch_can_accept_old_preparation\n")
  let checkedProof ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M2048",laws.toString]
    env := #[("LEAN_PATH",some ((root/"build/lib").toString++":"++(compiler/"lib/lean").toString))] }
  IO.FS.writeFile (records/"laws.txt") (checkedProof.stdout++checkedProof.stderr)
  check (checkedProof.exitCode == 0 && !checkedProof.stdout.contains "sorryAx") "actual candidate laws failed their kernel audit"
  let started ← IO.monoMsNow
  let tested ← IO.Process.output {cmd := (root/"build/StudyMain").toString,args := #["maintenance-controls"]}
  let elapsed := (← IO.monoMsNow)-started
  write (records/"controls.json") (Json.mkObj [("exitCode",toJson tested.exitCode.toNat),("elapsedMs",toJson elapsed),
    ("stdout",toJson tested.stdout),("stderr",toJson tested.stderr),
    ("runtime",installation.getObjValD "runtime")])
  check (tested.exitCode == 0) (tested.stderr++tested.stdout)

def retryControls : IO Unit := do
  idle
  let failed ← read (base/"independent-maintenance-controls.guard.json")
  check (failed.getObjValD "state" == toJson "finished" &&
    failed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "control audit still owns processes"
  write (records/"control-audit-attempt.json") (Json.mkObj [("guard",failed),
    ("output",toJson (← IO.FS.readFile (records/"laws.txt"))),
    ("nativeControlStarted",toJson false),("globalMemoryLimitChanged",toJson false)])
  guard "independent-maintenance-controls-checked" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    "EGGSHELL_DATA_ROOT="++(root/"control-data").toString,"EGGSHELL_PREFIX="++(root/"prefix").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/IndependentMaintenanceStudy.lean").toString,"__controls"]

def run (controlsTag : String) : IO Unit := do
  idle
  discard <| finished controlsTag
  let installation ← read (root/"installation.json")
  let controls ← read (records/"controls.json")
  check (controls.getObjValD "exitCode" == toJson (0 : Nat) &&
    controls.getObjValD "runtime" == installation.getObjValD "runtime") "candidate source control did not pass"
  let report ← IO.ofExcept ((← IO.ofExcept (controls.getObjValAs? String "stdout")) |> Json.parse)
  check (report.getObjValD "completedSourceRefresh" == toJson true && report.getObjValD "blockedPreparation" == toJson (2 : Nat))
    "deterministic independent admission control is absent"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let source ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let seed ← read (practical/"cohort/study/seed-1/plan.json")
  let input := Json.mkObj [("installation",installation),("original",source.getObjValD "source"),
    ("originalFiles",source.getObjValD "sourceFiles"),("workspace",seed.getObjValD "workspace"),
    ("definitions",← read (practical/"interrupted-recovery/definitions.json")),("preparedReference",Json.null),
    ("activeReaders",toJson (3 : Nat)),("llvmReaders",toJson (3 : Nat)),("registered",toJson true),
    ("observeMaintenance",toJson false)]
  check (!(← (root/"input.json").pathExists)) "preserve admitted candidate traffic"
  write (root/"input.json") input
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := environment.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  guard "independent-maintenance-traffic" (#["/usr/bin/env"] ++
    unset.flatMap (fun key => #["-u",key]) ++ assigned ++ #[(root/"build/StudyMain").toString,
      "shared-traffic",(root/"input.json").toString,(root/"run").toString])

def summarize : IO Unit := do
  idle
  discard <| finished "independent-maintenance-traffic"
  let result ← read (records/"result.json")
  let waves ← IO.ofExcept (result.getObjValAs? (Array Json) "summary")
  let mut compact := #[]
  for wave in waves do
    compact := compact.push (Json.mkObj [("wave",wave.getObjValD "wave"),("elapsedMs",wave.getObjValD "elapsedMs"),
      ("maxReaderMs",wave.getObjValD "maxHookMs"),("semanticCompleted",wave.getObjValD "semanticCompleted"),
      ("observations",(wave.getObjValD "census").getObjValD "count"),("answers",wave.getObjValD "automaticAnswers")])
  let mut events := #[]
  for session in ← (root/"run/calls").readDir do
    for call in ← session.path.readDir do
      if !["stop","compact-start","post-compact","interrupt","end"].contains call.fileName then continue
      let timing ← read (call.path/"record.json")
      let registration ← read (call.path/"registration.json")
      let response ← IO.FS.readFile (call.path/"stdout")
      check ((← IO.ofExcept (Json.parse response)) == Json.mkObj []) "terminal hook returned a notice"
      check (timing.getObjValD "stdoutSha256" == toJson (← hash (call.path/"stdout"))) "actual terminal reply changed"
      events := events.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("timing",timing),("registration",registration)])
  check (events.size == 88) "all sixteen Stops and seventy-two compact/terminal events required"
  write (records/"terminal-events.json") (toJson events)
  write (records/"baseline.json") (Json.mkObj [("answers",← read (root/"run/baseline-auto-answers.json")),
    ("synapses",← read (root/"run/baseline-facts.json"))])
  let output := Json.mkObj [("waves",toJson compact),("terminalEvents",toJson events.size),
    ("peakRssKiB",(result.getObjValD "guard").getObjValD "sampledPeakRssKiB"),
    ("adopted",toJson false),("paidMatchedComparisons",toJson (0 : Nat))]
  write (records/"summary.json") output
  IO.println output.compress

partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut count := (0,0)
    for entry in ← path.readDir do
      let part ← remove entry.path
      count := (count.1+part.1,count.2+part.2)
    IO.FS.removeDir path
    return count
  IO.FS.removeFile path
  return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)

def retireTrial : IO Unit := do
  idle
  discard <| finished "independent-maintenance-traffic"
  check (!(← (records/"retired-trial.json").pathExists)) "preserve trial retirement"
  let result ← read (records/"result.json")
  let queries ← IO.ofExcept (result.getObjValAs? (Array Json) "queries")
  check (queries.size == 18 && (← (records/"terminal-events.json").pathExists) &&
    (← (records/"hook-profiles.json").pathExists)) "retain actual queries and lifecycle first"
  for query in queries do
    let body ← IO.ofExcept (query.getObjValAs? String "retainedBody")
    let stdout ← IO.ofExcept (query.getObjValAs? String "retainedStdout")
    check ((query.getObjValD "delivery").getObjValD "bodySha256" == toJson (← hash (.mk body))) "retained body changed"
    check ((query.getObjValD "timing").getObjValD "stdoutSha256" == toJson (← hash (.mk stdout))) "retained stdout changed"
  let original ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let source ← IO.ofExcept (original.getObjValAs? String "source")
  let files : Array (String × String) ← IO.ofExcept (original.getObjValAs? _ "sourceFiles")
  let artifacts := #[root/"build/StudyMain",parent/"build/StudyMain",practical/"build/StudyMain",
    base/"canonical-decoder-runtime/build/StudyMain",practical/"package/prefix/libexec/eggshell"]
  let before ← artifacts.mapM fun path => do pure (path,← hash path)
  for (name,digest) in files do check ((← hash (System.FilePath.mk source/name)) == digest) "protected source changed"
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any fun line => line.trimAscii.toString.startsWith (base.toString++"/"))
    "trial still owns native processes"
  let targets := #[root/"run",root/"control-data",root/"tmp"]
  for build in [root/"build",parent/"build",practical/"build",base/"canonical-decoder-runtime/build"] do
    for line in (← IO.FS.readFile (build/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      if path.isAbsolute then
        let actual := (← IO.FS.realPath path).toString
        check (!(targets.any (fun target => actual.startsWith (target.toString++"/")))) "native input belongs to ended traffic"
  let model := (← IO.FS.realPath (root/"prefix/share/eggshell/minilm")).toString
  check (!(targets.any (fun target => model.startsWith (target.toString++"/")))) "model belongs to ended traffic"
  let mut removed := (0,0)
  for path in targets do
    if !(← path.pathExists) then continue
    let part ← remove path
    removed := (removed.1+part.1,removed.2+part.2)
  for (path,digest) in before do check ((← hash path) == digest) "protected runtime changed"
  for (name,digest) in files do check ((← hash (System.FilePath.mk source/name)) == digest) "source changed during retirement"
  write (records/"retired-trial.json") (Json.mkObj [("files",toJson removed.1),("logicalBytes",toJson removed.2),
    ("archiveCreated",toJson false),("sourceAndRuntimeHashesUnchanged",toJson true),
    ("candidateRuntimeRetained",toJson true)])

def main : List String → IO Unit
  | ["prepare"] => prepare
  | ["seal"] => sealCandidate
  | ["revise"] => revise
  | ["rebuild",previous,next] => rebuild previous next
  | ["configure"] => configure
  | ["__controls"] => runControls
  | ["retry-controls"] => retryControls
  | ["run",tag] => run tag
  | ["summary"] => summarize
  | ["retire-trial"] => retireTrial
  | _ => IO.println "IndependentMaintenanceStudy prepare|seal"
end IndependentMaintenanceStudy
def main := IndependentMaintenanceStudy.main
