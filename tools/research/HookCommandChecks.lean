import tools.research.StudyLocal
open Lean StudyLocal
namespace HookCommandChecks
abbrev Child := IO.Process.Child {stdin := .null,stdout := .piped,stderr := .piped}
def launch (binary : System.FilePath) (args : Array String) (environment : Array (String × Option String))
    (input : Option String) : IO (Child × Option IO.FS.Handle) := do
  let spawned ← IO.Process.spawn {
    cmd := binary.toString,args,env := #[("LEAN_NUM_THREADS",none)]++environment,
    stdin := .piped,stdout := .piped,stderr := .piped,setsid := true}
  let (stdin,child) ← spawned.takeStdin
  if let some text := input then
    stdin.putStr text
    stdin.flush
    return (child,none)
  else return (child,some stdin)
def census (pid : Nat) : IO (Array (Nat × Nat × Nat)) := do
  let rows := (← command "/bin/ps" #["-axo","pid=,ppid=,rss="]).splitOn "\n"
  let mut all := #[]
  for row in rows do
    let fields := row.splitOn " " |>.filter (!·.isEmpty)
    if let [p,parent,rss] := fields then
      if let (some p,some parent,some rss) := (p.toNat?,parent.toNat?,rss.toNat?) then all := all.push (p,parent,rss)
  let mut owned := #[pid]
  repeat
    let next := all.filterMap fun (p,parent,_) => if owned.contains parent && !owned.contains p then some p else none
    if next.isEmpty then break
    owned := owned++next
  return all.filter fun (p,_,_) => owned.contains p
def remaining (known : Array Nat) : IO (Array Nat) := do
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-o","pid=","-p",",".intercalate (known.toList.map toString)]}
  check (result.exitCode ≤ 1) "cannot inspect owned PIDs"
  return result.stdout.splitOn "\n" |>.toArray.filterMap (fun row => row.trimAscii.toString.toNat?)
def run (root : System.FilePath) (label : String := "checks") (footprintOnly : Bool := false) : IO Unit := do
  let records := project/"docs/candidates/hook-command"
  let checkRoot := root/label
  check (!(← checkRoot.pathExists)) "fresh hook-command checks required"
  IO.FS.createDirAll checkRoot
  let client := root/"command-build/StudyMain"
  let fixture := root/"fixture-build/StudyMain"
  let backend := root/"build/StudyMain"
  let mut cases := #[]
  for mode in (if footprintOnly then [] else ["valid","empty","invalid","missing","malformed","silent","hang","blocked-input"]) do
    let path := checkRoot/mode
    IO.FS.createDirAll path
    let began ← IO.monoMsNow
    let (child,held) ← launch client #[fixture.toString,"fast"]
      #[("EGGSHELL_FIXTURE_RECEIPT",some (path/"receipt.json").toString)]
      (if mode == "blocked-input" then none else some (Json.mkObj [("case",toJson mode)]).compress)
    let hold ← IO.mkRef held
    let stdout ← IO.asTask child.stdout.readToEnd .dedicated
    let stderr ← IO.asTask child.stderr.readToEnd .dedicated
    let mut known := #[child.pid.toNat]
    let mut exitCode : Option UInt32 := none
    repeat
      for (pid,_,_) in ← census child.pid.toNat do
        unless known.contains pid do known := known.push pid
      if let some code ← child.tryWait then
        exitCode := some code
        break
      check ((← IO.monoMsNow)-began < 3000) "small supervisor did not enforce its fast deadline"
      IO.sleep 10
    hold.set none
    let some exit := exitCode | throw (IO.userError "missing observed child exit")
    let output ← IO.ofExcept ((← IO.wait stdout).mapError IO.Error.toString)
    let errors ← IO.ofExcept ((← IO.wait stderr).mapError IO.Error.toString)
    let parsed ← IO.ofExcept (Json.parse output)
    let published ← read (path/"receipt.json")
    let complete := ["valid","empty"].contains mode
    check (exit == 0 && errors.isEmpty && parsed.getObj?.isOk &&
      (published.getObjValD "publication").getObjValD "replyComplete" == toJson complete &&
      (published.getObjValD "publication").getObjValD "output" == toJson output)
      "small supervisor changed completion, visible bytes or the receipt"
    if mode == "valid" then
      check (parsed.getObjValD "context" == toJson "fixture original evidence" &&
        (published.getObjValD "ack").getObjValD "receipt" == published.getObjValD "receipt") "valid body or ACK was lost"
    else if mode == "empty" then check (parsed == Json.mkObj []) "valid empty reply became an incomplete notice"
    else
      check ((parsed.getObjValAs? String "systemMessage").isOk && published.getObjValD "ack" == Json.null)
        "invalid or absent output granted completion or an ACK"
    check ((← remaining known).isEmpty) "supervisor or an observed child survived the test"
    cases := cases.push (Json.mkObj [("case",toJson mode),("elapsedMs",toJson ((← IO.monoMsNow)-began)),
      ("output",toJson output),("publication",published),("noSurvivingChildren",toJson true)])
  unless footprintOnly do
    write (records/"protocol-checks.json") (Json.mkObj [("cases",toJson cases),
      ("clientSha256",toJson (← hash client)),("fixtureSha256",toJson (← hash fixture)),
      ("answeringModelCalls",toJson (0 : Nat)),("actualProjectQueries",toJson (0 : Nat))])
  let mut probes := #[]
  for (index,small) in #[(0,false),(1,true),(2,true),(3,false)] do
    let path := checkRoot/s!"footprint-{index}"
    IO.FS.createDirAll path
    let began ← IO.monoMsNow
    let (child,held) ← launch (if small then client else backend)
      (if small then #[backend.toString,"fast"] else #["codex-hook","fast"])
      #[("EGGSHELL_DATA_ROOT",some (path/"data").toString)] none
    let hold ← IO.mkRef held
    let stdout ← IO.asTask child.stdout.readToEnd .dedicated
    let stderr ← IO.asTask child.stderr.readToEnd .dedicated
    let mut samples := #[]
    let mut known := #[child.pid.toNat]
    let mut exitCode : Option UInt32 := none
    repeat
      let elapsed := (← IO.monoMsNow)-began
      let owned ← census child.pid.toNat
      for (pid,_,_) in owned do
        unless known.contains pid do known := known.push pid
      if let some code ← child.tryWait then
        exitCode := some code
        break
      check (elapsed < 3500) "footprint supervisor did not stop"
      if elapsed ≥ 400 && elapsed ≤ 1200 then
        samples := samples.push (elapsed,owned)
      IO.sleep 20
    hold.set none
    let some exit := exitCode | throw (IO.userError "missing footprint child exit")
    let output ← IO.ofExcept ((← IO.wait stdout).mapError IO.Error.toString)
    let errors ← IO.ofExcept ((← IO.wait stderr).mapError IO.Error.toString)
    check (exit == 0 && !samples.isEmpty && (Json.parse output).isOk && (← remaining known).isEmpty)
      "footprint observation failed its ownership or output checks"
    let peaks := samples.map fun (_,rows) => rows.foldl (fun total row => total+row.2.2) 0
    probes := probes.push (Json.mkObj [("index",toJson index),("smallSupervisor",toJson small),
      ("samples",toJson samples),("pairPeakRssKiB",toJson (peaks.foldl max 0)),
      ("elapsedMs",toJson ((← IO.monoMsNow)-began)),("stdout",toJson output),("stderr",toJson errors)])
  write (records/"footprint.json") (Json.mkObj [("order",toJson #["full","small","small","full"]),
    ("probes",toJson probes),("sameBackendSha256",toJson (← hash backend)),
    ("leanThreadEnvironment",Json.null),
    ("workload",toJson "blocked stdin; identical backend; 400-1200 ms owned-process RSS"),
    ("queryOrDeliveryBenchmark",toJson false),("adopted",toJson false)])
end HookCommandChecks
def main : List String → IO Unit
  | [root] => HookCommandChecks.run (.mk root)
  | [root,label] => HookCommandChecks.run (.mk root) label
  | [root,label,"footprint"] => HookCommandChecks.run (.mk root) label true
  | _ => throw (IO.userError "HookCommandChecks ROOT")
