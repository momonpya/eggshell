import tools.research.StudyLocal
open Lean StudyLocal
namespace NativeCpuStudy
def root := base/"native-cpu-attribution"
def records := project/"docs/candidates/native-cpu-attribution"
def parent := base/"canonical-decoder-runtime"
def driver := project/"tools/research/NativeCpuStudy.lean"

structure Process where
  pid : Nat
  parent : Nat
  rssKiB : Nat
  cpuCs : Nat
  program : String
  deriving ToJson,FromJson,BEq

def cpuTime (text : String) : Option Nat := do
  let parts := text.splitOn ":"
  let parsed : Option (Nat × String) := match parts with
    | [minutes,seconds] => minutes.toNat?.map (·,seconds)
    | [hours,minutes,seconds] => do
      let h ← hours.toNat?
      let m ← minutes.toNat?
      return (h*60+m,seconds)
    | _ => none
  let (minutes,seconds) ← parsed
  let [seconds,fraction] := seconds.splitOn "." | none
  unless fraction.length == 2 do none
  return (minutes*60+(← seconds.toNat?))*100+(← fraction.toNat?)

def parseProcess (line : String) : Option Process := do
  let fields := (line.replace "\t" " ").splitOn " " |>.filter (!·.isEmpty)
  let pid ← (← fields[0]?).toNat?
  let parent ← (← fields[1]?).toNat?
  let rssKiB ← (← fields[2]?).toNat?
  let cpuCs ← cpuTime (← fields[3]?)
  let program ← fields[4]?
  return {pid,parent,rssKiB,cpuCs,program}

def owned (rows : Array Process) (pid : Nat) : Array Process := Id.run do
  let mut selected := #[pid]
  for _ in [:rows.size] do
    let previous := selected.size
    for row in rows do
      if selected.contains row.parent && !selected.contains row.pid then selected := selected.push row.pid
    if selected.size == previous then break
  return rows.filter (fun row => selected.contains row.pid)

def controls : IO Unit := do
  check (cpuTime "0:00.01" == some 1 && cpuTime "12:34.56" == some 75456 &&
    cpuTime "1:02:03.04" == some 372304 && cpuTime "unknown" == none &&
    cpuTime "0:00.123" == none) "Darwin CPU counter parser changed"
  let p := fun id parent => ({pid := id,parent,rssKiB := 0,cpuCs := 0,program := "fixture"} : Process)
  let rows := #[p 10 1,p 11 10,p 12 11,p 99 1,p 98 99,p 97 98]
  check ((owned rows 10).map (·.pid) == #[10,11,12]) "CPU attribution admitted a foreign process"

def closeChild (child : IO.Process.Child {stdin := .null,stdout := .inherit,stderr := .inherit})
    (terminal : IO.Ref (Option UInt32)) : IO Unit := do
  if (← terminal.get).isSome then return
  if let some code ← child.tryWait then terminal.set (some code); return
  try child.kill
  catch error =>
    if let some code ← child.tryWait then terminal.set (some code)
    else throw error
  if (← terminal.get).isNone then terminal.set (some (← child.wait))

def lifetimeControls : IO Unit := do
  -- Mutable try-block state is scoped; it is not a shared termination receipt.
  let observed ← IO.mkRef true
  let mut finishedFlag := false
  try finishedFlag := true
  finally observed.set finishedFlag
  check (!(← observed.get)) "old mutable/finally reproducer changed"
  for command in ["/usr/bin/true","/usr/bin/false"] do
    let child ← IO.Process.spawn {cmd := command,stdin := .null,stdout := .inherit,stderr := .inherit}
    let code ← child.wait
    let terminal ← IO.mkRef (some code)
    closeChild child terminal
    closeChild child terminal
    check ((← terminal.get) == some code) "retirement lost its already-consumed exit code"
  let child ← IO.Process.spawn {cmd := "/bin/sleep",args := #["5"],stdin := .null,stdout := .inherit,stderr := .inherit}
  let terminal ← IO.mkRef (none : Option UInt32)
  let failed ← try
    try throw (IO.userError "original observer failure")
    finally closeChild child terminal
    pure false
  catch error => pure (error.toString.contains "original observer failure")
  check (failed && (← terminal.get).isSome) "failure path did not preserve error and child exit"
  closeChild child terminal
  write (records/"lifetime-controls.json") (Json.mkObj [("mutableFinallyBugReproduced",toJson true),
    ("successfulAndFailedExitRetained",toJson true),("repeatedCloseSafe",toJson true),
    ("exceptionPreservedAndOwnedChildDrained",toJson true),("productOperations",toJson (0 : Nat))])

def phase (trial : System.FilePath) : IO String := do
  for count in #[16,4] do
    if ← (trial/s!"phase-{count}/initializations.json").pathExists then
      if ← (trial/s!"phase-{count}/clients.json").pathExists then return s!"after-{count}"
      return s!"wave-{count}"
  return "warm-or-prime"

def setup : IO Unit := do
  idle
  controls
  check (!(← root.pathExists) && !(← records.pathExists)) "preserve CPU diagnosis"
  let runtime := parent/"prefix/libexec/eggshell"
  let digest ← hash runtime
  check (digest == "7cc1432d2d3931a26d60e3e614807545e3f6b522737838bdabc1b1c626e657ab") "fixed product changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  let original ← read (base/"snapshot-scheduling/capacity-16-input.json")
  let trial := root/"trial"
  let config := trial/"config.toml"
  let plugin := parent/"prefix/share/eggshell/codex-plugin"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
  let controlled := #["EGGSHELL_PREFIX","PLUGIN_ROOT","EGGSHELL_CONFIG","EGGSHELL_DATA_ROOT",
    "EGGSHELL_TRACE_QUERY_STAGES","EGGSHELL_TRACE_SERVICE_PROFILE","EGGSHELL_TRACE_ACTOR_HEAP",
    "EGGSHELL_TRACE_ALLOCATOR","EGGSHELL_TRACE_SELECTION_RANGES","EGGSHELL_TRACE_SELECTOR_INPUT","EGGSHELL_HANDOFF_TRACE"]
  let environment := environment.filter (fun row => !controlled.contains row.1) ++ #[
    ("EGGSHELL_PREFIX",some (parent/"prefix").toString),("PLUGIN_ROOT",some plugin.toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_DATA_ROOT",some (parent/"data").toString),
    ("EGGSHELL_TRACE_SERVICE_PROFILE",some "1"),("EGGSHELL_TRACE_QUERY_STAGES",none),
    ("EGGSHELL_TRACE_ACTOR_HEAP",none),("EGGSHELL_TRACE_ALLOCATOR",none),
    ("EGGSHELL_TRACE_SELECTION_RANGES",none),("EGGSHELL_TRACE_SELECTOR_INPUT",none),("EGGSHELL_HANDOFF_TRACE",none)]
  let input := original.setObjVal! "runtime" (toJson runtime.toString) |>.setObjVal! "runtimeSha256" (toJson digest)
    |>.setObjVal! "output" (toJson trial.toString) |>.setObjVal! "config" (toJson config.toString)
    |>.setObjVal! "data" (toJson (parent/"data").toString) |>.setObjVal! "plugin" (toJson plugin.toString)
    |>.setObjVal! "environment" (toJson environment)
  write (root/"input.json") input
  write (records/"plan.json") (Json.mkObj [("classificationPreviousTurn",toJson "progress:whole-hook decoder hypothesis rejected;original ACK timeout retained;ended scratch removed"),
    ("input",input),("productChanges",toJson (0 : Nat)),("newNativeBuild",toJson false),
    ("question",toJson "CPU demand and concurrency of existing project-image consumers,not another decoder/cache/pool candidate"),
    ("counts",toJson (#[(4 : Nat),16])),("diagnosticNotPerformanceComparison",toJson true),
    ("measurement",toJson "100ms owned-process cumulative CPU counters;existing scalar profiles;one-second native samples near 3s and 8s in wave16"),
    ("cpuTicksAreLowerBound",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "native-cpu-attribution" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",driver.toString,"observe"]

/-- A single owner polls this child. No second wait consumes its terminal status.
Only this already-spawned native process performs product DB operations. -/
def observe : IO Unit := do
  controls
  let input ← read (root/"input.json")
  let runtime ← IO.ofExcept (input.getObjValAs? String "runtime")
  check ((← hash (.mk runtime)) == (← IO.ofExcept (input.getObjValAs? String "runtimeSha256"))) "native runtime changed"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
  let child ← IO.Process.spawn {
    cmd := runtime
    args := #["owned-selection-capacity",(root/"input.json").toString]
    env := environment
    stdin := .null
    stdout := .inherit
    stderr := .inherit }
  let terminal ← IO.mkRef (none : Option UInt32)
  let mut exitCode : Nat := 1
  let mut samples := #[]
  let began ← IO.monoMsNow
  let mut wave16 : Option Nat := none
  let mut sampled := #[]
  try
    repeat
      if let some code ← child.tryWait then
        terminal.set (some code)
        exitCode := code.toNat
        break
      check ((← IO.monoMsNow) < began+240000) "native CPU diagnosis exceeded its observation budget"
      let time ← IO.monoMsNow
      let status ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,ppid=,rss=,time=,comm="]}
      check (status.exitCode == 0) "cannot read process CPU counters"
      let parsed := (status.stdout.splitOn "\n").filterMap parseProcess |>.toArray
      let rows := owned parsed child.pid.toNat
      let stage ← phase (root/"trial")
      if stage == "wave-16" && wave16.isNone then wave16 := some time
      let mut publisher := Json.null
      let endpoint := parent/"data/publisher/endpoint.json"
      if ← endpoint.pathExists then
        let owner ← read endpoint
        let pid ← IO.ofExcept (owner.getObjValAs? Nat "pid")
        if rows.any (·.pid == pid) then publisher := toJson pid
      samples := samples.push (Json.mkObj [("observedMs",toJson time),("finishedMs",toJson (← IO.monoMsNow)),
        ("phase",toJson stage),("publisherPid",publisher),("processes",toJson rows)])
      if stage == "wave-16" then
        for offset in #[3000,8000] do
          if !sampled.contains offset && time ≥ wave16.getD time+offset && publisher != Json.null then
            let pid ← IO.ofExcept (fromJson? publisher : Except String Nat)
            let path := root/s!"publisher-{offset}.sample.txt"
            let start ← IO.monoMsNow
            let result ← IO.Process.output {cmd := "/usr/bin/sample",args := #[toString pid,"1","5","-file",path.toString]}
            write (root/s!"sample-{offset}.json") (Json.mkObj [("pid",toJson pid),("startedMs",toJson start),
              ("finishedMs",toJson (← IO.monoMsNow)),("exitCode",toJson result.exitCode.toNat),("file",toJson path.toString)])
            sampled := sampled.push offset
      IO.sleep 100
    write (root/"cpu-samples.json") (toJson samples)
    write (root/"child.json") (Json.mkObj [("pid",toJson child.pid.toNat),("exitCode",toJson exitCode),
      ("elapsedMs",toJson ((← IO.monoMsNow)-began)),("singleStatusOwner",toJson true)])
    check (exitCode == 0) "native diagnostic failed;preserve partial data,do not rerun unchanged"
  finally
    closeChild child terminal

def analyze : IO Unit := do
  let monitor ← read (base/"native-cpu-attribution.guard.json")
  check (monitor.getObjValD "state" == toJson "finished" &&
    monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    monitor.getObjValD "guardTriggered" == toJson false) "CPU observation has not drained"
  let child ← read (root/"child.json")
  check (child.getObjValD "exitCode" == toJson (0 : Nat)) "native product did not complete"
  let input ← read (root/"input.json")
  let source : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (name,digest) in files do check ((← hash (source/name)) == digest) "source changed during CPU observation"
  let report ← read (root/"trial/report.json")
  check (report.getObjValD "allPhasesPassed" == toJson true) "native CPU waves failed"
  let phases ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
  let mut clients : Array Json ← IO.ofExcept (fromJson? (← read (root/"trial/prime.json")))
  let data := parent/"data"
  let samples : Array Json ← IO.ofExcept (fromJson? (← read (root/"cpu-samples.json")))
  let mut windows := #[]
  let mut cpu := #[]
  for phase in phases do
    let rows ← IO.ofExcept (phase.getObjValAs? (Array Json) "rows")
    clients := clients++rows
    let mut starts := #[]
    let mut ends := #[]
    for row in rows do
      let id ← IO.ofExcept (row.getObjValAs? String "receipt")
      let published := (← read (data/"receipts"/id/"published.json")).getObjValD "data"
      let started ← IO.ofExcept (published.getObjValAs? Nat "startedMs")
      let elapsed ← IO.ofExcept (row.getObjValAs? Nat "elapsedMs")
      starts := starts.push started
      ends := ends.push (started+elapsed)
      windows := windows.push (Json.mkObj [("receipt",toJson id),("firstMs",toJson started),("lastMs",toJson (started+elapsed))])
    let first := starts.foldl min starts[0]!
    let last := ends.foldl max 0
    let inside := samples.filter fun sample =>
      (sample.getObjValAs? Nat "observedMs").toOption.any (first ≤ ·) &&
      (sample.getObjValAs? Nat "finishedMs").toOption.any (· ≤ last) && sample.getObjValD "publisherPid" != Json.null
    check (inside.size ≥ 2) "fewer than two CPU snapshots wholly inside the native wave"
    let a := inside[0]!
    let b := inside.back!
    let pid ← IO.ofExcept (a.getObjValAs? Nat "publisherPid")
    check (b.getObjValD "publisherPid" == toJson pid) "publisher changed during the CPU interval"
    let ticks := fun (sample : Json) => do
      let processes : Array Process ← IO.ofExcept (fromJson? (sample.getObjValD "processes"))
      let some process := processes.find? (·.pid == pid) | throw (IO.userError "CPU snapshot omitted its publisher")
      check (process.program == (parent/"prefix/libexec/eggshell").toString) "CPU interval names another executable"
      return process.cpuCs
    let before ← ticks a
    let after ← ticks b
    check (before ≤ after) "publisher CPU counter went backwards"
    let counterDelta := (after-before)*10
    -- ps displays centiseconds. Reserve two displayed ticks rather than
    -- treating the difference of rounded displays as an exact lower bound.
    let work := counterDelta-20
    let interval := (← IO.ofExcept (b.getObjValAs? Nat "finishedMs"))-(← IO.ofExcept (a.getObjValAs? Nat "observedMs"))
    cpu := cpu.push (Json.mkObj [("clients",phase.getObjValD "clients"),("publisherPid",toJson pid),
      ("nativeWaveFirstMs",toJson first),("nativeWaveLastMs",toJson last),
      ("firstSample",a),("lastSample",b),("publisherCpuMsLowerBound",toJson work),
      ("displayedCpuCounterDeltaMs",toJson counterDelta),("counterDisplayAllowanceMs",toJson (20 : Nat)),
      ("intervalWallMsUpperBound",toJson interval),("physicalCores",toJson (10 : Nat)),
      ("sameCpuDemandAtTenCoresMsLowerBound",toJson ((work+9)/10)),
      ("doesNotRuleOutReducingCpuDemand",toJson true)])
  check (clients.size == 23 && clients.all (fun row => row.getObjValD "success" == toJson true &&
    row.getObjValD "bodyByteEqual" == toJson true && row.getObjValD "acknowledged" == toJson true)) "native bodies or ACKs failed"
  let mut profiles := #[]
  for directory in ← (data/"receipts").readDir do
    for file in ← directory.path.readDir do
      if file.fileName.endsWith "-profile.json" then profiles := profiles.push (← read file.path)
  for offset in #[3000,8000] do
    let capture ← read (root/s!"sample-{offset}.json")
    check (capture.getObjValD "exitCode" == toJson (0 : Nat)) "native sample did not finish"
    write (records/s!"sample-{offset}.json") capture
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
      (project/"tools/research/StackWeights.lean").toString,(root/s!"publisher-{offset}.sample.txt").toString,
      (records/s!"stacks-{offset}.json").toString]
  write (records/"cpu-intervals.json") (toJson cpu)
  write (records/"cpu-samples.json") (toJson samples)
  write (records/"profiles.json") (toJson profiles)
  write (records/"result.json") (Json.mkObj [("input",input),("guard",monitor),("nativeChild",child),
    ("report",report),("clients",toJson clients),("nativeWindows",toJson windows),
    ("originalSourceFilesUnchanged",toJson true),("runtimeSha256Unchanged",toJson ((← hash (parent/"build/StudyMain")) ==
      (← IO.ofExcept (input.getObjValAs? String "runtimeSha256")))),
    ("all23BodiesAndAcksPassed",toJson true),("productChanges",toJson (0 : Nat)),
    ("observerFailedAfterNativeChildExited",toJson true),("guardIsNotAnUnqualifiedSuccess",toJson true),
    ("observerAffectsLatency",toJson true),("notPerformanceComparison",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def refineIntervals : IO Unit := do
  let path := records/"cpu-intervals.json"
  let rows : Array Json ← IO.ofExcept (fromJson? (← read path))
  check (rows.all (fun row => row.getObjValD "counterDisplayAllowanceMs" == Json.null)) "interval allowance already applied"
  let refined ← rows.mapM fun row => do
    let raw ← IO.ofExcept (row.getObjValAs? Nat "publisherCpuMsLowerBound")
    let work := raw-20
    return row.setObjVal! "displayedCpuCounterDeltaMs" (toJson raw)
      |>.setObjVal! "counterDisplayAllowanceMs" (toJson (20 : Nat))
      |>.setObjVal! "publisherCpuMsLowerBound" (toJson work)
      |>.setObjVal! "sameCpuDemandAtTenCoresMsLowerBound" (toJson ((work+9)/10))
  write path (toJson refined)

partial def removeOwned (path : System.FilePath) : IO (Nat × Nat) := do
  let stat ← path.symlinkMetadata
  if stat.type == .dir then
    let mut count := (0,0)
    for entry in ← path.readDir do
      let next ← removeOwned entry.path
      count := (count.1+next.1,count.2+next.2)
    IO.FS.removeDir path
    return count
  IO.FS.removeFile path
  return (1,if stat.type == .file then stat.byteSize.toNat else 0)

def retire : IO Unit := do
  idle
  let observation ← read (base/"native-cpu-attribution.guard.json")
  check (observation.getObjValD "state" == toJson "finished" && observation.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "observer still owns a process"
  let analysis ← finished "native-cpu-analysis"
  check ((← read (records/"result.json")).getObjValD "all23BodiesAndAcksPassed" == toJson true) "collect completed native trial first"
  check (← (records/"lifetime-controls.json").pathExists) "check termination fix before cleanup"
  for offset in #[3000,8000] do
    let result ← read (records/s!"stacks-{offset}.json")
    check (result.getObjValD "inputSha256" == toJson (← hash (root/s!"publisher-{offset}.sample.txt")) &&
      result.getObjValD "inconsistentParents" == toJson (0 : Nat)) "stack summary differs from its raw input"
  for name in #["publisher/endpoint.json","publisher/operations.json","daemon.json"] do
    check (!(← (parent/"data"/name).pathExists)) "service endpoint remains"
  let protectedPaths := #[parent/"build/StudyMain",base/"register-rounds-runtime/build/StudyMain",
    base/"current-six/stable-source-rows/build/StudyMain",base/"current-six/fixed-sequence/controller-build/StudyMain",
    base/"current-six/fixed-sequence/preparation-closure-build/StudyMain",base/"byte-pages-prefix/libexec/eggshell",
    base/"snapshot-scheduling/work/work.egg/head"]++
    (#[1,2,3].map fun n => base/"snapshot-scheduling/diagnostic"/("topic-"++toString n)/"body.txt")
  let hashes ← protectedPaths.mapM hash
  let input ← read (root/"input.json")
  let original : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (file,digest) in files do check ((← hash (original/file)) == digest) "original source changed before retirement"
  write (records/"resources.json") (Json.mkObj [("observation",observation),("analysis",analysis)])
  let mut deleted := #[]
  for path in #[root,parent/"data/sessions",parent/"data/confirmed-delivery",parent/"data/receipts",
      base/"native-cpu-attribution.guard.json",base/"native-cpu-attribution.guard-settings.json",
      base/"native-cpu-analysis.guard.json",base/"native-cpu-analysis.guard-settings.json"] do
    if ← path.pathExists then
      let count ← removeOwned path
      deleted := deleted.push (path.toString,count.1,count.2)
  check ((← protectedPaths.mapM hash) == hashes) "retirement changed protected native inputs"
  for (file,digest) in files do check ((← hash (original/file)) == digest) "original source changed during retirement"
  write (records/"retired.json") (Json.mkObj [("deleted",toJson deleted),
    ("protected",toJson (protectedPaths.zip hashes)),("sourceFilesUnchanged",toJson true),("archive",toJson false),
    ("rawStacksCannotBeReconstructedFromSummaries",toJson true),("currentCacheAndModelsRetained",toJson true)])

def main (args : List String) : IO Unit := do
  match args with
  | ["setup"] => setup
  | ["observe"] => observe
  | ["lifetime-controls"] => lifetimeControls
  | ["analyze"] => guard "native-cpu-analysis" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M768","--run",driver.toString,"analyze-worker"]
  | ["analyze-worker"] => analyze
  | ["refine-intervals"] => refineIntervals
  | ["retire"] => retire
  | _ => throw (IO.userError "native CPU study setup|observe")
end NativeCpuStudy
def main := NativeCpuStudy.main
