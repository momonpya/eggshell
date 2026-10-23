import tools.research.ArtifactHash
import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap
import Std.Data.HashSet

open Lean

namespace Eggshell.Research.ResourceGuard

structure Process where
  pid : Nat
  parent : Nat
  rssKiB : Nat
  state : String
  identity : String
  command : Array String
  deriving Inhabited, ToJson

def words (line : String) : Array String :=
  ((line.splitOn " ").filter (! ·.isEmpty)).toArray

def parseProcess (line : String) : Option Process := do
  let parts := words line
  guard (10 ≤ parts.size)
  return {
    pid := ← parts[0]!.toNat?, parent := ← parts[1]!.toNat?, rssKiB := ← parts[2]!.toNat?
    state := parts[3]!, identity := String.intercalate " " (parts.extract 4 9).toList
    command := parts.extract 9 parts.size }

def processes : IO (Std.HashMap Nat Process) := do
  let output ← IO.Process.output {
    cmd := "/bin/ps", args := #["-axo","pid=,ppid=,rss=,stat=,lstart=,args="]
    env := #[("LC_ALL",some "C")]}
  unless output.exitCode == 0 do throw (IO.userError "cannot inspect owned process resources")
  return (output.stdout.splitOn "\n").foldl (fun rows line =>
    match parseProcess line with
    | some row => rows.insert row.pid row
    | none => rows) {}

def ancestors (rows : Std.HashMap Nat Process) (monitor : Nat) : Std.HashSet Nat := Id.run do
  let mut result := ({} : Std.HashSet Nat).insert monitor
  let mut current := rows[monitor]?.map (·.parent)
  while let some pid := current do
    if result.contains pid then break
    result := result.insert pid
    current := rows[pid]?.map (·.parent)
  return result

/-- Signals can only target rows outside the monitor's current ancestor set. -/
structure CheckedProcess (excluded : Std.HashSet Nat) where
  process : Process
  permitted : excluded.contains process.pid = false

theorem CheckedProcess.ne_protected (row : CheckedProcess excluded)
    (present : excluded.contains pid = true) : row.process.pid ≠ pid := by
  intro same
  have forbidden := row.permitted
  rw [same, present] at forbidden
  contradiction

def owned (rows : Std.HashMap Nat Process) (excluded : Std.HashSet Nat)
    (child : Nat) (known : Std.HashMap Nat String) (prefixes : Array String) : Array (CheckedProcess excluded) := Id.run do
  let eligible := rows.toArray.filter fun (_,row) =>
    !excluded.contains row.pid && !row.state.startsWith "Z"
  let mut children : Std.HashMap Nat (Array Nat) := {}
  let mut selected : Std.HashSet Nat := {}
  let mut queue := #[]
  for (_,row) in eligible do
    children := children.insert row.parent ((children[row.parent]?.getD #[]).push row.pid)
    let identified := row.command.any fun arg => prefixes.any fun root =>
      arg == root || arg.startsWith (root ++ "/")
    if row.pid == child || known[row.pid]? == some row.identity || identified then
      selected := selected.insert row.pid
      queue := queue.push row.pid
  let mut position := 0
  while position < queue.size do
    let parent := queue[position]!
    position := position + 1
    for pid in children[parent]?.getD #[] do
      if selected.contains pid then continue
      selected := selected.insert pid
      queue := queue.push pid
  let mut result := #[]
  for (_,row) in eligible do
    if !selected.contains row.pid then continue
    if permitted : excluded.contains row.pid = false then
      result := result.push ⟨row,permitted⟩
  return result

structure Settings where
  record : String
  cwd : String
  command : Array String
  ownedPrefixes : Array String := #[]
  limitRssKiB : Nat := 3145728
  minFreeKiB : Nat := 524288
  deriving FromJson, ToJson

/-- Keep half a GiB below the user's four-GiB ceiling for sampling and
shutdown. Three GiB remains the default, rather than the maximum allowed. -/
def maximumStopRssKiB : Nat := 3670016

def validStopRss (limit : Nat) : Bool := decide (0 < limit ∧ limit ≤ maximumStopRssKiB)

theorem valid_stop_reserves_headroom {limit : Nat} (valid : validStopRss limit = true) :
    limit + 524288 ≤ 4194304 := by
  have bound := (of_decide_eq_true valid).2
  exact Nat.add_le_add_right bound 524288

def diskFreeKiB (directory : System.FilePath) : IO Nat := do
  let output ← IO.Process.output {cmd := "/bin/df", args := #["-Pk",directory.toString]}
  let rows := (output.stdout.splitOn "\n").filter (! ·.isEmpty)
  let some row := rows.getLast? | throw (IO.userError "disk inspection returned no rows")
  let fields := words row
  let some free := fields[3]?.bind String.toNat? | throw (IO.userError "disk inspection did not report available KiB")
  unless output.exitCode == 0 do throw (IO.userError "cannot inspect free disk space")
  return free

/-- Generation has temporary disk costs beyond its persisted trial directory.
The continuous stop floor stays separate from this startup headroom. -/
def generationSpaceReady (availableKiB : Nat) : Bool := decide (2097152 ≤ availableKiB)

theorem generation_space_bound {availableKiB : Nat}
    (ready : generationSpaceReady availableKiB = true) : 2097152 ≤ availableKiB :=
  of_decide_eq_true ready

def requireGenerationSpace (directory : System.FilePath) : IO Unit := do
  unless generationSpaceReady (← diskFreeKiB directory) do
    throw (IO.userError "generation requires at least 2 GiB free before starting; keep the 512 MiB continuous stop floor")

private abbrev Child := IO.Process.Child {stdin := .inherit, stdout := .inherit, stderr := .inherit}

private def poll (child : Child) (exit : IO.Ref (Option UInt32)) : IO (Option UInt32) := do
  if let some code ← exit.get then return some code
  let code ← child.tryWait
  exit.set code
  return code

private def snapshot (path : System.FilePath) (json : Json) : IO Unit := do
  let pending := System.FilePath.mk (path.toString ++ ".pending")
  IO.FS.writeFile pending (json.compress ++ "\n")
  IO.FS.rename pending path

def run (settings : Settings) : IO UInt32 := do
  unless !settings.command.isEmpty && validStopRss settings.limitRssKiB do
    throw (IO.userError "guard needs a command and an RSS stop threshold at most 3.5 GiB")
  let path := System.FilePath.mk settings.record
  unless path.isAbsolute && !(← path.pathExists) do
    throw (IO.userError "keep the existing guard record; use a new absolute path")
  let directory := path.parent.getD (.mk settings.cwd)
  IO.FS.createDirAll directory
  unless settings.minFreeKiB ≤ (← diskFreeKiB directory) do
    throw (IO.userError "not enough disk space to start this guarded execution")
  let monitor := (← IO.Process.getPID).toNat
  let started ← IO.monoMsNow
  let binarySha ← Eggshell.Research.ArtifactHash.hex (← IO.appPath)
  let child ← IO.Process.spawn {
    cmd := settings.command[0]!, args := settings.command.extract 1 settings.command.size
    cwd := some (.mk settings.cwd), setsid := true
    env := #[("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),
      ("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
      ("TOKENIZERS_PARALLELISM",some "false"),("HF_HUB_OFFLINE",some "1")]
    stdin := .inherit, stdout := .inherit, stderr := .inherit}
  let exit ← IO.mkRef none
  let mut known : Std.HashMap Nat String := {}
  let mut peak := 0
  let mut samples := 0
  let mut reason : Option String := none
  let mut failure : Option String := none
  let mut activeIds := #[]
  let mut peakProcesses : Array Json := #[]
  let mut lastDisk := 0
  let report := fun (state : String) (code : Option Nat) (peak samples : Nat)
      (reason failure : Option String) (activeIds : Array Nat) (elapsed : Nat)
      (peakProcesses : Array Json) => Json.mkObj [
    ("state",toJson state),("guardPid",toJson monitor),("childPid",toJson child.pid.toNat),
    ("guardSha256",toJson binarySha),("limitRssKiB",toJson settings.limitRssKiB),
    ("userCeilingRssKiB",toJson (4194304 : Nat)),("sampledPeakRssKiB",toJson peak),
    ("samples",toJson samples),("reason",toJson reason),("error",toJson failure),
    ("guardTriggered",toJson reason.isSome),("exitCode",toJson code),
    ("ownedPids",toJson activeIds),("peakProcesses",toJson peakProcesses),
    ("elapsedMs",toJson elapsed),("settings",toJson settings)]
  try
    repeat
      let rows ← processes
      let excluded := ancestors rows monitor
      let active := owned rows excluded child.pid.toNat known settings.ownedPrefixes
      activeIds := active.map (·.process.pid)
      for row in active do known := known.insert row.process.pid row.process.identity
      let rss := active.foldl (fun total row => total + row.process.rssKiB)
        (rows[monitor]?.map (·.rssKiB) |>.getD 0)
      if peak < rss then
        peak := rss
        let peakRows := (active.map (·.process)) ++ (rows[monitor]?).toArray
        peakProcesses := peakRows.map fun row =>
          let role := row.command[1]?.filter (#["codex-worker","codex-daemon","codex-hook",
            "search-provider","app-server","guard"].contains ·)
          let lane := if role == some "codex-worker" then
            row.command[2]?.filter (#["save","search","index"].contains ·) else none
          Json.mkObj [("pid",toJson row.pid),("parent",toJson row.parent),("rssKiB",toJson row.rssKiB),
            ("program",toJson (row.command[0]?.getD "")),("role",toJson role),("lane",toJson lane)]
      samples := samples + 1
      let now ← IO.monoMsNow
      if rss ≥ settings.limitRssKiB then reason := some "aggregate-rss"
      if now ≥ lastDisk + 1000 then
        lastDisk := now
        if (← diskFreeKiB directory) < settings.minFreeKiB then reason := some "disk-space"
      if reason.isSome then break
      if let some _ ← poll child exit then
        -- tryWait reaps this child. Reinspect so a prior ps row cannot make
        -- a completed child appear to be a leftover process.
        let finalRows ← processes
        let remaining := owned finalRows (ancestors finalRows monitor) child.pid.toNat known settings.ownedPrefixes
        activeIds := remaining.map (·.process.pid)
        if !remaining.isEmpty then reason := some "leftover-processes"
        break
      if samples % 10 == 1 then
        snapshot path (report "running" (none : Option Nat) peak samples reason failure activeIds (now-started) peakProcesses)
      IO.sleep 100
  catch error =>
    reason := some "monitor-error"
    failure := some error.toString
  if reason.isSome then
    -- Revalidate identity immediately before signaling. The proof-bearing
    -- rows exclude the monitor and all its ancestors even during teardown.
    try
      let rows ← processes
      let targets := owned rows (ancestors rows monitor) child.pid.toNat known settings.ownedPrefixes
      for target in targets do
        let _ ← IO.Process.output {cmd := "/bin/kill",args := #["-KILL",toString target.process.pid]}
    catch error => failure := some s!"cleanup inspection: {error}"
    if (← poll child exit).isNone then
      -- This child owns a fresh process group (setsid above). Even if ps is
      -- unavailable, terminate that owned group before waiting or reporting.
      let _ ← IO.Process.output {cmd := "/bin/kill",args := #["-KILL","--","-" ++ toString child.pid]}
      try child.kill catch _ => pure ()
  let code ← match ← poll child exit with
    | some code => pure code
    | none => child.wait
  -- The recorded set describes actual survivors after cleanup, rather than
  -- the last sample taken before the owned processes were signalled.
  let cleanupDeadline := (← IO.monoMsNow)+2000
  let mut emptySince : Option Nat := none
  repeat
    let rows ← processes
    let active := owned rows (ancestors rows monitor) child.pid.toNat known settings.ownedPrefixes
    activeIds := active.map (·.process.pid)
    for target in active do
      known := known.insert target.process.pid target.process.identity
    let now ← IO.monoMsNow
    if activeIds.isEmpty then
      if let some since := emptySince then
        if now ≥ since+100 then break
      else emptySince := some now
    else
      emptySince := none
      -- A hook can finish spawning its daemon after the first kill sweep.
      -- Reacquire proof-bearing ownership rows on every sweep, including
      -- newly discovered children, and retain their identities if reparented.
      if reason.isSome then
        for target in active do
          let _ ← IO.Process.output {cmd := "/bin/kill",args := #["-KILL",toString target.process.pid]}
          pure ()
    if now ≥ cleanupDeadline then break
    IO.sleep 5
  let finalRows ← processes
  activeIds := (owned finalRows (ancestors finalRows monitor) child.pid.toNat known settings.ownedPrefixes).map (·.process.pid)
  if !activeIds.isEmpty then
    failure := some "owned processes survived resource cleanup"
    if reason.isNone then reason := some "leftover-processes"
  snapshot path (report "finished" (some code.toNat) peak samples reason failure activeIds ((← IO.monoMsNow)-started) peakProcesses)
  return if reason.isSome then 2 else code

def cliMain (args : List String) : IO UInt32 := do
  try
    let [input] := args | throw (IO.userError "ResourceGuard SETTINGS.json")
    let json ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk input)))
    let settings ← IO.ofExcept (fromJson? (α := Eggshell.Research.ResourceGuard.Settings) json)
    Eggshell.Research.ResourceGuard.run settings
  catch error =>
    IO.eprintln error.toString
    return 1

end Eggshell.Research.ResourceGuard
