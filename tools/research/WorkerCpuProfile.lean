import Eggshell.Daemon
open Lean
namespace Eggshell.Research.WorkerCpuProfile
open Eggshell Eggshell.Plugin
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def source := base/"frontend-quiescence-fixture-small1"
def bundledEngine := base/"worker-cpu-target/bin/eggshelld"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty
def hash (path : System.FilePath) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (reply.exitCode == 0) "cannot seal profile input"
  return (reply.stdout.splitOn " ").headD ""
def command (engine : System.FilePath) (args : Array String) (input : Option String := none) : IO IO.Process.Output :=
  IO.Process.output {cmd := engine.toString,args} input

/-- Darwin ps emits hundredths; preserve the printed precision as integer ms.
Only related processes are parsed. Unsupported formats are an error. -/
def cpuMs (value : String) : Except String Nat := do
  let parts := value.splitOn ":"
  unless parts.length == 2 || parts.length == 3 do throw "unexpected ps CPU clock shape"
  let mut total := 0
  for part in parts.dropLast do
    let some n := part.toNat? | throw "invalid ps CPU clock component"
    total := total*60+n
  let some final := parts.getLast? | throw "missing ps seconds"
  let seconds := final.splitOn "."
  let [whole,fraction] := seconds | throw "missing ps CPU clock precision"
  let some whole := whole.toNat? | throw "invalid ps seconds"
  unless !fraction.isEmpty && fraction.length ≤ 3 do throw "unsupported ps fraction"
  let some fraction := (fraction++String.ofList (List.replicate (3-fraction.length) '0')).toNat? |
    throw "invalid ps fraction"
  return (total*60+whole)*1000+fraction

structure Process where
  pid : Nat
  parent : Nat
  cpu : Nat
  user : Nat
  system : Nat
  rssKiB : Nat
  role : String
  deriving ToJson,FromJson

def selectedProgram (engine : System.FilePath) (command : String) : Option String :=
  [engine.toString,bundledEngine.toString].find? (fun path => command.startsWith (path++" "))

def role (engine : System.FilePath) (command : String) : String :=
  match selectedProgram engine command with
  | none => "backend-child"
  | some program =>
    let arguments := (command.drop (program.length+1)).toString
    if arguments.startsWith "codex-worker search" then "search-worker"
    else if arguments.startsWith "codex-worker save" then "save-worker"
    else if arguments.startsWith "codex-daemon " then "frontend"
    else if arguments.startsWith "codex-publication-daemon" then "publication-service"
    else (arguments.splitOn " ").headD "native-client"

def processes (engine : System.FilePath) : IO (Array Process) := do
  let reply ← IO.Process.output {cmd := "/bin/ps",args := #["-axww","-o","pid=,ppid=,time=,utime=,stime=,rss=,command="]}
  check (reply.exitCode == 0) "cannot read actual process CPU clocks"
  let rows := reply.stdout.splitOn "\n" |>.filterMap fun line => do
    let words := line.trimAscii.toString.splitOn " " |>.filter (!·.isEmpty)
    let pid::parent::cpu::user::system::rss::command := words | none
    let pid ← pid.toNat?
    let parent ← parent.toNat?
    pure (pid,parent,cpu,user,system,rss," ".intercalate command)
  let mut wanted := (rows.filterMap fun row =>
    if (selectedProgram engine row.2.2.2.2.2.2).isSome then some row.1 else none).toArray
  for _ in [:16] do
    let before := wanted.size
    for (pid,parent,_,_,_,_,_) in rows do
      if wanted.contains parent && !wanted.contains pid then wanted := wanted.push pid
    if wanted.size == before then break
  let mut selected := #[]
  for (pid,parent,cpu,user,system,rss,command) in rows do
    unless wanted.contains pid do continue
    let some rss := rss.toNat? | throw (IO.userError "invalid related RSS")
    selected := selected.push ⟨pid,parent,← IO.ofExcept (cpuMs cpu),← IO.ofExcept (cpuMs user),
      ← IO.ofExcept (cpuMs system),rss,role engine command⟩
  return selected

def cpuChanges (before after : Array Process) : Array Json := after.filterMap fun current => do
  let previous ← before.find? (·.pid == current.pid)
  if previous.role != current.role || previous.cpu > current.cpu then none else
    some (Json.mkObj [("pid",toJson current.pid),("role",toJson current.role),
      ("cpuMs",toJson (current.cpu-previous.cpu)),("userMs",toJson (current.user-previous.user)),
      ("systemMs",toJson (current.system-previous.system))])

def hook (root : System.FilePath) (wave : String) (caseIndex : Nat) : IO Json := do
  let session := s!"cpu-{wave}-{caseIndex}"
  let question := s!"Return the recorded head and tail facts for support case-{caseIndex}."
  let input := Json.mkObj [("session_id",toJson session),("turn_id",toJson "turn"),
    ("cwd",toJson root.toString),("hook_event_name",toJson "UserPromptSubmit"),
    ("_eggshell_config",toJson (root/"eggshell.toml").toString),("prompt",toJson question)]
  let began ← IO.monoMsNow
  let receipt ← Receipt.fresh
  let reply ← Daemon.hookRequest input (began+30000) receipt
  let output ← IO.ofExcept (reply.getObjValAs? String "output")
  let ack := reply.getObjValD "ack"
  let mut acknowledged := false
  let mut acknowledgmentError : Option String := none
  if ack != Json.null then
    try
      let endpoint ← Daemon.readyEndpoint session
      acknowledged := (← Daemon.exchange endpoint "ack" ack) == "true"
    catch error => acknowledgmentError := some error.toString
  let elapsed := (← IO.monoMsNow)-began
  let path := root/(session++".stdout")
  IO.FS.writeFile path output
  let parsed := (Json.parse output).toOption
  let body := parsed.bind (fun output => (output.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext" |>.toOption) |>.getD ""
  let both := body.contains s!"\"observed-head-case-{caseIndex}-7b319c\"" &&
    body.contains s!"\"observed-tail-case-{caseIndex}-d82a04\""
  return Json.mkObj [("session",toJson session),("case",toJson caseIndex),("elapsedMs",toJson elapsed),
    ("receipt",toJson receipt),("ackRequested",toJson (ack != Json.null)),
    ("acknowledged",toJson acknowledged),("ackError",toJson acknowledgmentError),
    ("validJson",toJson parsed.isSome),("complete",toJson (body != pendingSearch.text)),
    ("bothFields",toJson both),("bodyBytes",toJson body.utf8ByteSize),("stdoutSha256",toJson (← hash path))]

def receipts (root : System.FilePath) (hooks : Array Json) : IO (Array Json) := do
  let folder := root/"private/receipts"
  let mut rows := #[]
  for hook in hooks do
    let session ← IO.ofExcept (hook.getObjValAs? String "session")
    let receipt ← IO.ofExcept (hook.getObjValAs? String "receipt")
    let directory := folder/receipt
    let mut fields := [("session",toJson session),("receipt",toJson receipt)]
    for stage in ["operation-service","search-phase-semantic","search-phase-lexical","ack","transport","keyed-nominations","delivery-domain"] do
      if ← (directory/(stage++".json")).pathExists then
        fields := fields++[(stage,(← read (directory/(stage++".json"))).getObjValD "data")]
    if ← (directory/"published.json").pathExists then
      let published := (← read (directory/"published.json")).getObjValD "data"
      fields := fields++[("published",published.setObjVal! "output" Json.null)]
    rows := rows.push (Json.mkObj fields)
  return rows

def wave (root engine : System.FilePath) (name : String) (first count : Nat)
    (samplePid : Option Nat := none) : IO Json := do
  let before ← processes engine
  let began ← IO.monoMsNow
  let sampler ← samplePid.mapM fun pid => IO.asTask (do
    IO.sleep 750
    let current ← processes engine
    if current.any (·.pid == pid) then
      let sampled ← IO.Process.output {cmd := "/usr/bin/sample",args := #[toString pid,"2","1","-file",(root/"worker.sample.txt").toString]}
      save (root/"sample-result.json") (Json.mkObj [("pid",toJson pid),("exitCode",toJson sampled.exitCode.toNat),
        ("stdout",toJson sampled.stdout),("stderr",toJson sampled.stderr)])
    else save (root/"sample-result.json") (Json.mkObj [("pid",toJson pid),("targetMissing",toJson true)])) .dedicated
  let tasks ← (List.range count).toArray.mapM fun offset => IO.asTask (hook root name (first+offset)) .dedicated
  let mut timeline := #[]
  repeat
    let observed ← processes engine
    timeline := timeline.push ((← IO.monoMsNow)-began,observed)
    let finished ← tasks.allM fun task => do return ← IO.hasFinished task
    if finished then break
    IO.sleep 500
  let rows ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
  if let some sampler := sampler then IO.ofExcept (← IO.wait sampler)
  let after ← processes engine
  let cpuInterval := (← IO.monoMsNow)-began
  let stats ← command engine #["publication-control","stats"]
  let report := Json.mkObj [("name",toJson name),("wallMs",toJson ((← IO.monoMsNow)-began)),
    ("cpuIntervalMs",toJson cpuInterval),
    ("samplePid",toJson samplePid),("latencyIsDiagnostic",toJson true),
    ("before",toJson before),("after",toJson after),("persistentCpu",toJson (cpuChanges before after)),
    ("lostPids",toJson (before.filter (fun previous => !after.any (fun current => current.pid == previous.pid)) |>.map (·.pid))),
    ("timeline",toJson timeline),("rows",toJson rows),("receipts",toJson (← receipts root rows)),
    ("serviceStats",(Json.parse stats.stdout).toOption.getD Json.null)]
  save (root/(name++".json")) report
  return report

def run (root engine : System.FilePath) (expected : String) (caseCount : Nat := 32) (burst : Bool := false) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute worker profile required"
  check (caseCount == 32 || caseCount == 80) "fixed profile case count required"
  for (input,expected) in [("0:00.00",0),("1:02.34",62340),("1:02:03.45",3723450)] do
    check ((cpuMs input).toOption == some expected) "CPU clock parser mismatch"
  IO.FS.createDirAll root
  let heads ← (List.range 16).toArray.mapM fun index => do
    let path := source/s!"work.project/owners/{index}/source.egg/head"
    return (path.toString,← IO.FS.readFile path,← hash path)
  save (root/"heads.json") (toJson heads)
  let runtimeHash ← hash engine
  check (expected.length == 64 && runtimeHash == expected) "profile runtime changed"
  check ((← IO.FS.realPath bundledEngine) == (← IO.FS.realPath engine) &&
    (← Daemon.daemonExecutable) == bundledEngine) "native client did not select the frozen target runtime"
  IO.FS.writeFile (root/"eggshell.toml") ("default = \"work\"\n[eggs]\nwork = \""++(source/"work.project").toString++
    "\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let auditPath := source/"retained-original-audit.json"
  let previous ← if ← auditPath.pathExists then some <$> IO.FS.readFile auditPath else pure none
  try
    let audited ← command engine #["front-traffic-audit",source.toString]
    check (audited.exitCode == 0) "independent original audit failed"
    let audit ← read auditPath
    save (root/"original-audit.json") audit
    let saved ← IO.ofExcept (audit.getObjValAs? (Array String) "saved")
    check (saved.size == 82 && (List.range caseCount).all (fun i => saved.contains s!"case-{i}")) "needed originals not present"
  finally
    match previous with
    | some text => IO.FS.writeFile auditPath text
    | none => if ← auditPath.pathExists then IO.FS.removeFile auditPath
  save (root/"frozen-required.json") (Json.mkObj [("sourceHeads",toJson heads),
    ("cases",toJson (List.range caseCount)),("fields",toJson #["head","tail"]),("frozenBeforeDelivery",toJson true)])
  try
    let warm ← command engine #["egg","warm",(source/"work.project").toString]
    save (root/"warm.json") (Json.mkObj [("exitCode",toJson warm.exitCode.toNat),("stdout",toJson warm.stdout),("stderr",toJson warm.stderr)])
    check (warm.exitCode == 0) "explicit profile warm failed"
    -- Prepared readers are owned by the selected target, not this lightweight
    -- caller's compiled producer. Inspect its report without reopening it.
    let ready ← IO.ofExcept (Json.parse warm.stdout)
    let databases ← IO.ofExcept (ready.getObjValAs? (Array Json) "databases")
    check (databases.size == 1) "warm changed the project domain"
    let some database := databases[0]? | throw (IO.userError "warm project report missing")
    let sources ← IO.ofExcept (database.getObjValAs? (Array Json) "sources")
    check (sources.size == 16 && sources.all (fun row =>
      let prepared := row.getObjValD "prepared"
      prepared != Json.null && ((prepared.getObjValAs? Nat "population").toOption == some 0 ||
        prepared.getObjValD "numeric" != Json.null))) "target warm did not prepare every source"
    let ownerSources ← IO.ofExcept ((ready.getObjValD "ownerView").getObjValAs? (Array Json) "sources")
    check (ownerSources.size == 16) "target warm omitted original owner sources"
    let prime ← wave root engine "prime" 0 3
    let primed ← IO.ofExcept (prime.getObjValAs? (Array Process) "after")
    check ((primed.filter (·.role == "search-worker")).size == 3) "three ordinary worker processes were not observed"
    let first ← wave root engine "wave-a" 0 (if burst then caseCount else 16)
    let second ← if burst then pure Json.null else do
      let cpu ← IO.ofExcept (first.getObjValAs? (Array Json) "persistentCpu")
      let ranked := cpu.qsort fun a b =>
        (a.getObjValAs? Nat "cpuMs").toOption.getD 0 > (b.getObjValAs? Nat "cpuMs").toOption.getD 0
      let some target := ranked.find? (fun row =>
        let role := (row.getObjValAs? String "role").toOption.getD ""
        role == "search-worker") |
        throw (IO.userError "no persistent search-worker CPU sampling target")
      let pid ← IO.ofExcept (target.getObjValAs? Nat "pid")
      save (root/"sample-target.json") target
      wave root engine "wave-b" 16 16 (some pid)
    let mut remaining := #[]
    if caseCount == 80 && !burst then
      for firstCase in [32,48,64] do
        remaining := remaining.push (← wave root engine s!"wave-{firstCase/16}" firstCase 16)
    for (path,text,digest) in heads do
      check ((← IO.FS.readFile (.mk path)) == text && (← hash (.mk path)) == digest) "profiling changed an original head"
    save (root/"report.json") (Json.mkObj [("runtimeSha256",toJson runtimeHash),
      ("prime",prime),("first",first),("second",second),("remaining",toJson remaining),
      ("caseCount",toJson caseCount),("concurrentClients",toJson (if burst then caseCount else 16)),
      ("originalHeadsUnchanged",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("productChanged",toJson false),("adopted",toJson false)])
  finally
    let frontend ← command engine #["codex-daemon","shutdown"]
    let publisher ← command engine #["publication-control","shutdown"]
    save (root/"shutdown.json") (Json.mkObj [("frontendExit",toJson frontend.exitCode.toNat),("publisherExit",toJson publisher.exitCode.toNat)])
end Eggshell.Research.WorkerCpuProfile
def main (args : List String) : IO Unit := do
  match args with
  | [root,engine,expected] => Eggshell.Research.WorkerCpuProfile.run (.mk root) (.mk engine) expected
  | [root,engine,expected,"80"] => Eggshell.Research.WorkerCpuProfile.run (.mk root) (.mk engine) expected 80
  | [root,engine,expected,"burst80"] => Eggshell.Research.WorkerCpuProfile.run (.mk root) (.mk engine) expected 80 true
  | _ => throw (IO.userError "fresh profile root, target runtime, SHA and optional 80/burst80 required")
