import Lean.Data.Json
import Std.Sync.Mutex
import Init.Data.Queue
import tools.research.ResourceGuard

open Lean

namespace Eggshell.Research.StudyTransport

inductive Access where
  | inspect | generate
  deriving DecidableEq

inductive ReadMethod where
  | initialize | models | hooks

inductive RunMethod where
  | threadStart | turnStart | unsubscribe | interrupt

inductive Request : Access → Type where
  | read (method : ReadMethod) : Request access
  | run (method : RunMethod) : Request .generate

def Request.method : Request access → String
  | .read .initialize => "initialize"
  | .read .models => "model/list"
  | .read .hooks => "hooks/list"
  | .run .threadStart => "thread/start"
  | .run .turnStart => "turn/start"
  | .run .unsubscribe => "thread/unsubscribe"
  | .run .interrupt => "turn/interrupt"

theorem inspection_cannot_start_turn (request : Request .inspect) :
    request.method ≠ "turn/start" := by
  cases request with
  | read method => cases method <;> decide

structure Settings where
  command : Array String
  cwd : String
  environment : Array (String × Option String)
  output : String
  timeoutMs : Nat
  responseBytes : Nat
  transcriptBytes : Nat
  deriving FromJson

private structure Inbox where
  pending : Std.Queue (Json × Nat) := .empty
  count : Nat := 0
  bytes : Nat := 0
  error : Option String := none
  closed : Bool := false
  stopping : Bool := false

private structure Transcript where
  handle : IO.FS.Handle
  bytes : Nat := 0
  largest : Nat := 0

private abbrev Reader := Task (Except IO.Error Unit)
private abbrev Child := IO.Process.Child {stdin := .null, stdout := .piped, stderr := .piped}

structure Client (access : Access) where
  private settings : Settings
  private child : Child
  private input : IO.Ref (Option IO.FS.Handle)
  private stdoutReader : Reader
  private stderrReader : Reader
  private writer : IO.Ref (Option Reader)
  private inbox : Std.Mutex Inbox
  private transcript : Std.Mutex Transcript
  private nextId : IO.Ref Nat
  private notices : IO.Ref (Array Json)
  private exit : IO.Ref (Option UInt32)
  private family : IO.Ref (Std.HashMap Nat String)
  private monitor : Nat

private def record (settings : Settings) (transcript : Std.Mutex Transcript)
    (direction : String) (message : Json) (size : Nat := 0) : IO Unit := do
  let row := Json.mkObj [("direction",toJson direction),("message",message),
    ("monotonic_ns",toJson (← IO.monoNanosNow))]
  let line := row.compress ++ "\n"
  transcript.atomically do
    let current ← get
    unless current.bytes + line.utf8ByteSize ≤ settings.transcriptBytes do
      throw (IO.userError "App Server transcript exceeded its frozen capture bound")
    current.handle.putStr line
    current.handle.flush
    set {current with bytes := current.bytes + line.utf8ByteSize, largest := max current.largest size}

private partial def enqueue (inbox : Std.Mutex Inbox) (message : Json) (size : Nat) : IO Unit := do
  let inserted ← inbox.atomically do
    let state ← get
    if state.stopping then return true
    if state.count ≥ 128 || state.bytes + size > 32 * 1024 * 1024 then return false
    set {state with pending := state.pending.enqueue (message,size), count := state.count + 1, bytes := state.bytes + size}
    return true
  unless inserted do
    IO.sleep 5
    enqueue inbox message size

private def readStdout (access : Access) (settings : Settings) (handle : IO.FS.Handle)
    (inbox : Std.Mutex Inbox) (transcript : Std.Mutex Transcript) : IO Unit := do
  try
    let mut pending := ByteArray.empty
    repeat
      if ← inbox.atomically (return (← get).stopping) then break
      -- FS.Handle is buffered stdio: a large fread can wait for that many
      -- bytes on a live pipe. One buffered byte completes without waiting
      -- for the next frame and bounds even an unterminated response.
      let chunk ← handle.read 1
      if chunk.isEmpty then
        unless pending.isEmpty do throw (IO.userError "App Server closed an unfinished JSON frame")
        break
      let mut start := 0
      for i in [0:chunk.size] do
        if chunk[i]! != 10 then continue
        let raw := pending ++ chunk.extract start i
        unless raw.size ≤ settings.responseBytes do throw (IO.userError "App Server response exceeded its frozen capture bound")
        let some text := String.fromUTF8? raw | throw (IO.userError "App Server response is not UTF-8")
        let message ← IO.ofExcept (Json.parse text)
        let _ ← IO.ofExcept message.getObj?
        record settings transcript "server" message raw.size
        if access == .inspect && #["turn/started","thread/tokenUsage/updated"].contains
            ((message.getObjValAs? String "method").toOption.getD "") then
          throw (IO.userError "unexpected generation event during metadata inspection")
        enqueue inbox message raw.size
        pending := .empty
        start := i + 1
      pending := pending ++ chunk.extract start chunk.size
      unless pending.size ≤ settings.responseBytes do throw (IO.userError "App Server partial response exceeded its frozen capture bound")
  catch error =>
    inbox.atomically (modify fun state => {state with error := some error.toString})
  finally
    inbox.atomically (modify fun state => {state with closed := true})

private def readStderr (handle output : IO.FS.Handle) (inbox : Std.Mutex Inbox) : IO Unit := do
  try
    let mut bytes := 0
    let mut pending := ByteArray.empty
    repeat
      let chunk ← handle.read 1
      if chunk.isEmpty then
        output.write pending
        output.flush
        break
      bytes := bytes + chunk.size
      unless bytes ≤ 16 * 1024 * 1024 do throw (IO.userError "App Server stderr exceeded 16 MiB")
      pending := pending ++ chunk
      if chunk[0]! == 10 || pending.size ≥ 4096 then
        output.write pending
        output.flush
        pending := .empty
  catch error =>
    inbox.atomically (modify fun state => {state with error := some error.toString})

def start (access : Access) (settings : Settings) : IO (Client access) := do
  unless !settings.command.isEmpty && settings.timeoutMs > 0 && settings.timeoutMs ≤ 900000 &&
      settings.responseBytes > 0 && settings.responseBytes ≤ 32 * 1024 * 1024 &&
      settings.transcriptBytes > 0 && settings.transcriptBytes ≤ 256 * 1024 * 1024 do
    throw (IO.userError "invalid App Server command, deadline, or capture bounds")
  let output := System.FilePath.mk settings.output
  unless output.isAbsolute && !(← output.pathExists) do throw (IO.userError "keep the existing transport evidence")
  -- Reserve this run atomically; concurrent clients must not truncate each
  -- other's transcript after both pass the existence check above.
  IO.FS.createDir output
  let log ← IO.FS.Handle.mk (output / "exchange.jsonl") .write
  let errors ← IO.FS.Handle.mk (output / "stderr.log") .write
  let spawned ← IO.Process.spawn {
    cmd := settings.command[0]!, args := settings.command.extract 1 settings.command.size
    cwd := some (.mk settings.cwd), env := settings.environment
    stdin := .piped, stdout := .piped, stderr := .piped, setsid := true}
  let (input,child) ← spawned.takeStdin
  let inbox ← Std.Mutex.new ({} : Inbox)
  let transcript ← Std.Mutex.new ({handle := log} : Transcript)
  let stdoutReader ← IO.asTask (readStdout access settings child.stdout inbox transcript) .dedicated
  let stderrReader ← IO.asTask (readStderr child.stderr errors inbox) .dedicated
  return {
    settings,child,input := ← IO.mkRef (some input),stdoutReader,stderrReader
    writer := ← IO.mkRef none,inbox,transcript,nextId := ← IO.mkRef 0,
    notices := ← IO.mkRef #[],exit := ← IO.mkRef none
    family := ← IO.mkRef {},monitor := (← IO.Process.getPID).toNat}

private partial def awaitTask (task : Reader) (deadline : Nat) : IO Unit := do
  if ← IO.hasFinished task then
    match task.get with
    | .ok () => return
    | .error error => throw error
  unless (← IO.monoMsNow) < deadline do throw (IO.userError "App Server pipe operation timed out")
  IO.sleep 5
  awaitTask task deadline

private def send (client : Client access) (message : Json) : IO Unit := do
  let line := message.compress ++ "\n"
  unless line.utf8ByteSize ≤ 1024 * 1024 do throw (IO.userError "App Server request exceeds 1 MiB")
  let some input ← client.input.get | throw (IO.userError "App Server input is closed")
  record client.settings client.transcript "client" message
  let writing ← IO.asTask (do input.putStr line; input.flush) .dedicated
  client.writer.set (some writing)
  awaitTask writing ((← IO.monoMsNow) + client.settings.timeoutMs)
  client.writer.set none

private partial def receive (client : Client access) (deadline : Nat) : IO Json := do
  let row ← client.inbox.atomically do
    let state ← get
    if let some ((message,size),rest) := state.pending.dequeue? then
      set {state with pending := rest,count := state.count - 1,bytes := state.bytes - size}
      return some message
    if let some error := state.error then throw (IO.userError error)
    if state.closed then throw (IO.userError "App Server stdout closed")
    return none
  if let some row := row then return row
  unless (← IO.monoMsNow) < deadline do throw (IO.userError "App Server response timed out")
  IO.sleep 5
  receive client deadline

def request (client : Client access) (method : Request access) (params : Json) : IO Json := do
  let id ← client.nextId.get
  client.nextId.set (id + 1)
  send client (Json.mkObj [("id",toJson id),("method",toJson method.method),("params",params)])
  let deadline := (← IO.monoMsNow) + client.settings.timeoutMs
  repeat
    let message ← receive client deadline
    if (message.getObjVal? "id").toOption.isSome then
      if (message.getObjVal? "method").toOption.isSome then throw (IO.userError "unexpected server-initiated request")
      unless (message.getObjValAs? Nat "id").toOption == some id do throw (IO.userError "App Server response ID mismatch")
      if (message.getObjVal? "error").toOption.isSome then throw (IO.userError s!"App Server {method.method} failed; retain the recorded error")
      return ← IO.ofExcept (message.getObjVal? "result")
    client.notices.modify (·.push message)
  throw (IO.userError "unreachable request completion")

def handshake (client : Client access) (version : String) : IO Json := do
  let hello ← request client (.read .initialize) (Json.mkObj [
    ("clientInfo",Json.mkObj [("name",toJson "eggshell_study"),("title",toJson "Eggshell study"),("version",toJson version)]),
    ("capabilities",Json.mkObj [("experimentalApi",toJson true)])])
  send client (Json.mkObj [("method",toJson "initialized"),("params",Json.mkObj [])])
  return hello

def waitNotification (client : Client .generate) (method : String)
    (accepts : Json → Bool) : IO Json := do
  let buffered ← client.notices.get
  client.notices.set #[]
  for message in buffered do
    if (message.getObjValAs? String "method").toOption != some method then continue
    if let .ok params := message.getObjVal? "params" then
      if accepts params then return params
  let deadline := (← IO.monoMsNow) + client.settings.timeoutMs
  repeat
    let message ← receive client deadline
    if (message.getObjVal? "id").toOption.isSome then throw (IO.userError "unexpected RPC request/response while waiting for a turn")
    if (message.getObjValAs? String "method").toOption != some method then continue
    let params ← IO.ofExcept (message.getObjVal? "params")
    if accepts params then return params
  throw (IO.userError "unreachable notification completion")

private def poll (client : Client access) : IO (Option UInt32) := do
  if let some code ← client.exit.get then return some code
  let code ← client.child.tryWait
  client.exit.set code
  return code

private partial def waitExit (client : Client access) (deadline : Nat) : IO (Option UInt32) := do
  if let some code ← poll client then return some code
  if (← IO.monoMsNow) ≥ deadline then return none
  IO.sleep 5
  waitExit client deadline

private def familyMembers (client : Client access) : IO (Array ResourceGuard.Process) := do
  let rows ← ResourceGuard.processes
  let excluded := ResourceGuard.ancestors rows client.monitor
  let members := ResourceGuard.owned rows excluded client.child.pid.toNat (← client.family.get) #[]
  for member in members do
    client.family.modify (·.insert member.process.pid member.process.identity)
  return members.map fun member => member.process

private def familySummary (process : ResourceGuard.Process) : Json :=
  Json.mkObj [("pid",toJson process.pid),("parent",toJson process.parent),
    ("birth",toJson process.identity),("executable",toJson (process.command[0]?.getD ""))]

def executables (client : Client access) : IO (Array String) := do
  return (← familyMembers client).map (fun process => process.command[0]?.getD "")

private def stopFamily (client : Client access) : IO Unit := do
  let rows ← ResourceGuard.processes
  let excluded := ResourceGuard.ancestors rows client.monitor
  for member in ResourceGuard.owned rows excluded client.child.pid.toNat (← client.family.get) #[] do
    let _ ← IO.Process.output {cmd := "/bin/kill",args := #["-KILL",toString member.process.pid]}

private def groupMembers (pid : Nat) : IO (Array Json) := do
  let output ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,ppid=,pgid=,stat=,comm="]}
  unless output.exitCode == 0 do throw (IO.userError "cannot inspect the owned App Server process group")
  let mut members := #[]
  for line in output.stdout.splitOn "\n" do
    let fields := ((line.splitOn " ").filter (! ·.isEmpty)).toArray
    if fields.size < 5 || fields[2]!.toNat? != some pid || fields[3]!.startsWith "Z" then continue
    members := members.push (Json.mkObj [("pid",toJson fields[0]!),("parent",toJson fields[1]!),
      ("group",toJson fields[2]!),("state",toJson fields[3]!),
      ("executable",toJson (String.intercalate " " (fields.extract 4 fields.size).toList))])
  return members

def close (client : Client access) (actionError : Option String := none) : IO Json := do
  -- Capture the still-attached family before EOF can reparent helpers that
  -- created their own process group. Reuse the guard's birth-checked ownership
  -- and ancestor exclusion rather than inferring ownership from names.
  let mut cleanupErrors := #[]
  let mut beforeFamily := #[]
  let mut afterFamily := #[]
  try beforeFamily := (← familyMembers client).map familySummary
  catch error => cleanupErrors := cleanupErrors.push error.toString
  client.input.set none
  let mut forced := false
  let mut code ← waitExit client ((← IO.monoMsNow) + 15000)
  if code.isNone then
    forced := true
    let _ ← IO.Process.output {cmd := "/bin/kill",args := #["-KILL","--","-" ++ toString client.child.pid]}
    code := some (← client.child.wait)
    client.exit.set code
  let mut beforeGroup := #[]
  let mut afterGroup := #[]
  try beforeGroup ← groupMembers client.child.pid.toNat
  catch error => cleanupErrors := cleanupErrors.push error.toString
  -- Reaping the server does not reap helpers that still own its setsid group.
  -- Retain their identities and terminate only that group, including on a
  -- normal server exit. No global process-name shutdown is involved.
  try
    let _ ← IO.Process.output {cmd := "/bin/kill",args := #["-KILL","--","-" ++ toString client.child.pid]}
    stopFamily client
    IO.sleep 10
    afterGroup ← groupMembers client.child.pid.toNat
    afterFamily := (← familyMembers client).map familySummary
  catch error => cleanupErrors := cleanupErrors.push error.toString
  client.inbox.atomically (modify fun state => {state with stopping := true})
  let mut taskErrors := #[]
  let tasks := #[client.stdoutReader,client.stderrReader] ++ (← client.writer.get).toArray
  for task in tasks do
    try awaitTask task ((← IO.monoMsNow) + 5000)
    catch error => taskErrors := taskErrors.push error.toString
  let finalInbox ← client.inbox.atomically get
  let trace ← client.transcript.atomically get
  let stopped ← tasks.allM (fun task => return ← IO.hasFinished task)
  let result := Json.mkObj [("pid",toJson client.child.pid.toNat),("exitCode",toJson (code.map UInt32.toNat)),
    ("forced",toJson forced),("readersStopped",toJson stopped),("taskErrors",toJson taskErrors),
    ("actionError",toJson actionError),
    ("groupBeforeCleanup",toJson beforeGroup),("groupAfterCleanup",toJson afterGroup),
    ("familyBeforeCleanup",toJson beforeFamily),("familyAfterCleanup",toJson afterFamily),
    ("cleanupErrors",toJson cleanupErrors),
    ("transportError",toJson finalInbox.error),("transcriptBytes",toJson trace.bytes),
    ("largestResponseBytes",toJson trace.largest)]
  IO.FS.writeFile (.mk client.settings.output / "process.json") (result.compress ++ "\n")
  return result

def withClient (access : Access) (settings : Settings) (action : Client access → IO α) : IO α := do
  let client ← start access settings
  let outcome : Except IO.Error α ← try pure (.ok (← action client)) catch error => pure (.error error)
  let actionError := match outcome with
    | .error error => some error.toString
    | .ok _ => none
  let cleanup ← close client actionError
  match outcome with
  | .error error => throw error
  | .ok value =>
      unless (cleanup.getObjValAs? Nat "exitCode").toOption == some 0 &&
          (cleanup.getObjValAs? Bool "forced").toOption == some false &&
          (cleanup.getObjValAs? Bool "readersStopped").toOption == some true &&
          (cleanup.getObjValAs? (Array String) "taskErrors").toOption == some #[] &&
          (cleanup.getObjValAs? (Array String) "cleanupErrors").toOption == some #[] &&
          (cleanup.getObjValAs? (Array Json) "groupAfterCleanup").toOption == some #[] &&
          (cleanup.getObjValAs? (Array Json) "familyAfterCleanup").toOption == some #[] &&
          (cleanup.getObjVal? "transportError").toOption == some .null do
        throw (IO.userError "App Server did not close cleanly; retain process.json")
      return value

def probe (settings : Settings) : IO Unit :=
  withClient .inspect settings fun client => do
    let hello ← handshake client "0.145.0"
    let models ← request client (.read .models) (Json.mkObj [("includeHidden",toJson true)])
    let hooks ← request client (.read .hooks) (Json.mkObj [("cwds",toJson #[settings.cwd])])
    for (name,value) in #[("initialize",hello),("models",models),("hooks",hooks)] do
      IO.FS.writeFile (.mk settings.output / (name ++ ".json")) (value.compress ++ "\n")

end Eggshell.Research.StudyTransport
