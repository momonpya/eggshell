import Main
open Lean Eggshell
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal memory profile inputs"
  return (result.stdout.splitOn " ").headD ""
structure Process where
  pid : Nat
  parent : Nat
  rssKiB : Nat
  role : String
  deriving ToJson
def processes (owner : Nat) : IO (Array Process) := do
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-axww","-o","pid=,ppid=,rss=,command="]}
  check (result.exitCode == 0) "cannot inspect working-set descendants"
  let all := (result.stdout.splitOn "\n").toArray.filterMap fun line => do
    let pid::parent::rss::command := line.trimAscii.toString.splitOn " " |>.filter (!·.isEmpty) | none
    let pid ← pid.toNat?
    let parent ← parent.toNat?
    let rssKiB ← rss.toNat?
    let command := String.intercalate " " command
    let role := if command.contains " codex-publication-daemon" then "publication-service"
      else if command.contains " codex-daemon " then "frontend"
      else if command.contains " codex-numerical-daemon" then "numerical-service"
      else if command.contains " codex-worker " then "worker" else "client-or-backend"
    return ({pid,parent,rssKiB,role} : Process)
  let mut wanted := #[owner]
  for _ in [:16] do
    let before := wanted.size
    for row in all do
      if wanted.contains row.parent && !wanted.contains row.pid then wanted := wanted.push row.pid
    if wanted.size == before then break
  return all.filter (fun row => wanted.contains row.pid)
def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "fresh memory-profile root required")
  let root : System.FilePath := .mk path
  check (root.isAbsolute && !(← root.pathExists)) "preserve preceding memory profile"
  let client := base/"numerical-stages-client-build/StudyMain"
  let engine := base/"readonly-pages-build/StudyMain"
  check ((← hash client) == "a80cad2a80fb084842d22e3ead44358762fbdea3e175601b1d407d82c67b308e" &&
    (← hash engine) == "33c408217bb99d6278ad1519d0f65bfa39ddda23f58a1275e6cbac428184247d") "sealed memory-profile runtime changed"
  check ((← IO.FS.realPath (base/"worker-cpu-target/bin/eggshelld")) == engine) "memory profile changed target runtime"
  let child ← IO.Process.spawn {cmd := client.toString,args := #[root.toString,engine.toString,← hash engine]}
  let began ← IO.monoMsNow
  -- The finalizer must observe the actual reaping state,not the initial value
  -- captured when entering try/finally.
  let exitCode : IO.Ref (Option UInt32) ← IO.mkRef none
  let mut timeline := #[]
  let mut captured : Array (Nat × Nat) := #[]
  let mut maps := #[]
  try
    repeat
      let rows ← processes child.pid.toNat
      timeline := timeline.push ((← IO.monoMsNow)-began,rows)
      for row in rows do
        let thresholds := if row.role == "publication-service" then #[409600,716800]
          else if row.role == "frontend" then #[131072] else #[]
        for threshold in thresholds do
          if row.rssKiB < threshold || captured.contains (row.pid,threshold) then continue
          captured := captured.push (row.pid,threshold)
          let started ← IO.monoMsNow
          let result ← IO.Process.output {cmd := "/usr/bin/vmmap",args := #["-summary","-wide",toString row.pid]}
          maps := maps.push (Json.mkObj [("pid",toJson row.pid),("role",toJson row.role),
            ("thresholdKiB",toJson threshold),("observedRssKiB",toJson row.rssKiB),
            ("atMs",toJson (started-began)),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
            ("exitCode",toJson result.exitCode.toNat),("stdout",toJson result.stdout),("stderr",toJson result.stderr)])
      if let some code ← child.tryWait then
        exitCode.set (some code)
        break
      unless (← IO.monoMsNow) < began+90000 do throw (IO.userError "memory profile controller exceeded its lifecycle bound")
      IO.sleep 300
    check ((← exitCode.get) == some 0) "native memory profile client failed"
    check ((← IO.FS.readFile (root/"report.json")).contains "originalHeadsUnchanged") "native profile report missing"
    IO.FS.writeFile (root/"memory-profile.json") (Json.mkObj [("timeline",toJson timeline),("maps",toJson maps),
      ("sameHookRuntimeAndClient",toJson true),("clientExitCode",toJson ((← exitCode.get).map UInt32.toNat)),
      ("snapshotCollectionAddsObserverCost",toJson true),("notRetainedHeapAttribution",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
  finally
    if (← exitCode.get).isNone then
      try child.kill catch _ => pure ()
      discard <| child.wait
