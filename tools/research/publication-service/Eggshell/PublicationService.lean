module

public import Eggshell.PublicationWire
public import Std.Sync.Mutex
public import Init.System.Promise

@[expose] public section

namespace Eggshell.Plugin.Publication.Service
open Lean DB Synapses Std Async TCP

structure Job where
  request : NativePublication.Prepared
  bytes : Nat
  admitted : Nat
  deadline : Nat
  cancelled : IO.Ref Bool
  reply : IO.Promise (Except String Json)

structure ProjectState where
  directory : System.FilePath
  identity : String
  capability : String
  lease : FileSystem.ReadHandle
  queue : Array Job := #[]
  active : Bool := false

structure State where
  projects : Array ProjectState := #[]
  closed : Bool := false
  publishedGroups : Nat := 0
  publishedReplies : Nat := 0
  admittedBytes : Nat := 0

structure Server where
  state : Std.Mutex State
  resident : Std.Mutex Nat
  stopping : IO.Ref Bool

def lease (path : System.FilePath) : IO FileSystem.ReadHandle := do
  FileSystem.immutableExistingBytes path ByteArray.empty
  let handle ← FileSystem.openRead path.toString
  unless ← FileSystem.tryReadLock handle true do throw (IO.userError "another publisher owns this database")
  return handle

/-- Registration is local administrator authority. Project capabilities grant
only scoped publication; they cannot register paths or control the service. -/
def register (server : Server) (payload : Json) : IO Project := do
  let raw ← IO.ofExcept (payload.getObjValAs? String "directory")
  let identity ← IO.ofExcept (payload.getObjValAs? String "database")
  let path ← PageMap.absolute (.mk raw)
  let source ← PageMap.pin path
  unless source.head.identity == identity do throw (IO.userError "registered database identity changed")
  server.state.atomically do
    let state ← get
    unless !state.closed do throw (IO.userError "publisher is closed")
    if let some project := state.projects.find? (·.identity == identity) then
      unless project.directory == path do throw (IO.userError "database already has another registered location")
      return ⟨identity,project.capability⟩
    let owned ← lease (path / "publisher.guard")
    let capability := Blake3.hex (← IO.getRandomBytes 32)
    set {state with projects := state.projects.push {directory := path,identity,capability,lease := owned}}
    return ⟨identity,capability⟩

def submit (server : Server) (secret : String) (payload : Json) (deadline : Nat)
    (cancelled : IO.Ref Bool) : IO (IO.Promise (Except String Json)) := do
  let database ← IO.ofExcept (payload.getObjValAs? String "database")
  let capsule ← IO.ofExcept (payload.getObjVal? "capsule" >>= fromJson? (α := Capsule))
  let promise ← IO.Promise.new
  server.state.atomically do
    let state ← get
    unless !state.closed do throw (IO.userError "publisher is closed")
    let some index := state.projects.findIdx? (·.identity == database) |
      throw (IO.userError "unknown project capability")
    let some project := state.projects[index]? | throw (IO.userError "missing project")
    unless secret == project.capability do throw (IO.userError "unauthorized project publication")
    let prepared ← IO.ofExcept (capsule.prepare project.directory project.identity)
    let bytes := (toJson prepared.pending).compress.utf8ByteSize
    unless bytes ≤ NativePublication.maxBatchBytes && (← IO.monoMsNow) < deadline do
      throw (IO.userError "publication request exceeds its live bounds")
    let queued := state.projects.foldl (fun count project => count+project.queue.size) 0
    unless queued < maxClients && state.admittedBytes+bytes ≤ maxResidentBytes do
      throw (IO.userError "publisher admission is full")
    let job : Job := ⟨prepared,bytes,← IO.monoMsNow,deadline,cancelled,promise⟩
    set {state with
      admittedBytes := state.admittedBytes+bytes
      projects := state.projects.modify index fun project => {project with queue := project.queue.push job}}
    return promise

def takeGroup (server : Server) : IO (Option (System.FilePath × String × Array Job)) :=
  server.state.atomically do
    let state ← get
    if state.closed then return none
    let now ← IO.monoMsNow
    for index in [:state.projects.size] do
      let some project := state.projects[index]? | continue
      if project.active || project.queue.isEmpty then continue
      let some oldest := project.queue[0]? | continue
      if now < oldest.admitted+2 then continue
      let mut jobs := #[]
      let mut remaining := #[]
      let mut bytes := 0
      let mut dropped := 0
      for job in project.queue do
        if (← job.cancelled.get) || now ≥ job.deadline then
          job.reply.resolve (.error "publication expired before commit admission")
          dropped := dropped+job.bytes
        else if jobs.size < NativePublication.maxBatchRequests && bytes+job.bytes ≤ NativePublication.maxBatchBytes then
          jobs := jobs.push job
          bytes := bytes+job.bytes
        else remaining := remaining.push job
      let updated := {project with queue := remaining,active := !jobs.isEmpty}
      -- Rotate the chosen DB so a continuous producer cannot starve siblings.
      set {state with
        admittedBytes := state.admittedBytes-dropped
        projects := (state.projects.extract 0 index ++
        state.projects.extract (index+1) state.projects.size).push updated}
      if jobs.isEmpty then return none
      return some (project.directory,project.identity,jobs)
    return none

/-- Failed atomic groups have published nothing. Split only those groups, so
a conflicting immutable observation cannot discard unrelated originals.
Fuel and the original request/byte bounds limit fault-isolation work. -/
def commitJobs (server : Server) (path : System.FilePath) : Nat → Array Job → IO (Nat × Nat)
  | 0, jobs => do
      for job in jobs do job.reply.resolve (.error "publisher fault-isolation bound reached")
      return (0,0)
  | fuel+1, jobs => do
      let now ← IO.monoMsNow
      let live ← jobs.filterM fun job => do
        if (← server.stopping.get) || (← job.cancelled.get) || now ≥ job.deadline then
          job.reply.resolve (.error "publication left before commit admission")
          return false
        return true
      if live.isEmpty then return (0,0)
      let result ← try
        let publications ← NativePublication.runPrepared path (live.map (·.request))
        unless publications.size == live.size do throw (IO.userError "publisher changed its admitted group")
        pure (.ok publications : Except String (Array NativePublication.Published))
      catch error => pure (.error error.toString)
      match result with
      | .ok publications =>
          for (job,published) in live.zip publications do job.reply.resolve (.ok (toJson published.source))
          return (1,live.size)
      | .error error =>
          if live.size == 1 then
            for job in live do job.reply.resolve (.error error)
            return (0,0)
          let middle := live.size/2
          let left ← commitJobs server path fuel (live.extract 0 middle)
          let right ← commitJobs server path fuel (live.extract middle live.size)
          return (left.1+right.1,left.2+right.2)

def publish (server : Server) (path : System.FilePath) (identity : String) (jobs : Array Job) : IO Unit := do
  let committed ← IO.mkRef (0,0)
  try
    committed.set (← commitJobs server path (jobs.size+1) jobs)
  catch error =>
    for job in jobs do job.reply.resolve (.error error.toString)
  finally
    let committed ← committed.get
    server.state.atomically do
      modify fun state => {state with
        projects := state.projects.map (fun project =>
          if project.identity == identity then {project with active := false} else project)
        publishedGroups := state.publishedGroups+committed.1
        publishedReplies := state.publishedReplies+committed.2
        admittedBytes := state.admittedBytes-(jobs.foldl (fun total job => total+job.bytes) 0)}

def stats (server : Server) : IO Json := server.state.atomically do
  let state ← get
  return Json.mkObj [("projects",toJson state.projects.size),
    ("queued",toJson (state.projects.foldl (fun count project => count+project.queue.size) 0)),
    ("active",toJson (state.projects.filter (·.active)).size),("closed",toJson state.closed),
    ("admittedBytes",toJson state.admittedBytes),
    ("publishedGroups",toJson state.publishedGroups),("publishedReplies",toJson state.publishedReplies)]

partial def receiveLive (server : Server) (client : Socket.Client) (remaining deadline : Nat)
    (received : ByteArray := ByteArray.empty) : IO ByteArray := do
  if remaining == 0 then return received
  let now ← IO.monoMsNow
  unless !(← server.stopping.get) && now < deadline do throw (IO.userError "publisher frame expired")
  let chunk : Option (Option ByteArray) ← (do
    let timer ← Selector.sleep (.ofNat (min 5 (deadline-now)))
    Selectable.one #[.case (client.recvSelector remaining.toUInt64) (fun value => pure (some value)),
      .case timer (fun _ => pure none)]).block
  match chunk with
  | none => receiveLive server client remaining deadline received
  | some none => throw (IO.userError "publisher peer closed an incomplete frame")
  | some (some bytes) =>
      unless !bytes.isEmpty do throw (IO.userError "publisher received an empty frame")
      receiveLive server client (remaining-bytes.size) deadline (received.append bytes)

def peerWaiting (client : Socket.Client) : IO Bool := (do
  let timer ← Selector.sleep (.ofNat 5)
  Selectable.one #[.case (client.recvSelector 1) (fun _ => pure false),
    .case timer (fun _ => pure true)]).block

def awaitReply (server : Server) (client : Socket.Client) (cancelled : IO.Ref Bool)
    (promise : IO.Promise (Except String Json)) (deadline : Nat) : IO Json := do
  repeat
    if ← promise.isResolved then
      let some result := promise.result?.get | throw (IO.userError "publisher dropped its reply")
      return ← IO.ofExcept result
    unless !(← server.stopping.get) && (← IO.monoMsNow) < deadline && (← peerWaiting client) do
      cancelled.set true
      throw (IO.userError "publisher requester left before its reply")
  throw (IO.userError "unreachable publication wait")

def serveClient (server : Server) (admin : String) (client : Socket.Client) : IO Unit := do
  let reserved ← IO.mkRef (0 : Nat)
  let cancelled ← IO.mkRef false
  let reply ← try
    let deadline := (← IO.monoMsNow)+maxBudgetMs
    let header ← receiveLive server client 4 deadline
    let size := Daemon.decodeLength header
    unless size ≤ Daemon.maxFrameBytes do throw (IO.userError "publisher frame exceeds its bound")
    let admitted ← server.resident.atomically do
      let bytes ← get
      if bytes+size > maxResidentBytes then return false
      set (bytes+size)
      return true
    unless admitted do throw (IO.userError "publisher resident byte budget is full")
    reserved.set size
    let bytes ← receiveLive server client size deadline
    let some text := String.fromUTF8? bytes | throw (IO.userError "publisher frame is not UTF-8")
    let json ← IO.ofExcept (Json.parse text)
    let secret ← IO.ofExcept (json.getObjValAs? String "secret")
    let kind ← IO.ofExcept (json.getObjValAs? String "kind")
    let payload := json.getObjValD "payload"
    let value ← if kind == "publish" then do
        let promise ← submit server secret payload deadline cancelled
        awaitReply server client cancelled promise deadline
      else do
        unless secret == admin do throw (IO.userError "unauthorized publisher administration")
        match kind with
        | "register" => toJson <$> register server payload
        | "ping" => pure (toJson true)
        | "stats" => stats server
        | "shutdown" => server.stopping.set true; pure (toJson true)
        | _ => throw (IO.userError "unknown publication operation")
    pure (Daemon.response (.ok value.compress))
    catch error => pure (Daemon.response (.error error.toString))
  try Daemon.sendFrame client reply.compress.toUTF8
  finally
    cancelled.set true
    let bytes ← reserved.get
    server.resident.atomically (modify (·-bytes))

def retain (tasks : List (Task (Except IO.Error Unit))) : IO (List (Task (Except IO.Error Unit))) := do
  let mut live := []
  for task in tasks do
    if ← IO.hasFinished task then
      if let .error error ← IO.wait task then IO.eprintln s!"publisher operation stopped: {error}"
    else live := task::live
  return live

def close (server : Server) : IO (Array ProjectState) := server.state.atomically do
  let state : State ← get
  set {state with closed := true,projects := state.projects.map (fun (project : ProjectState) => {project with queue := #[]})}
  for project in state.projects do
    for job in project.queue do job.reply.resolve (.error "publisher closed before commit admission")
  return state.projects

/-- A local data-side service. Loopback administration is private to its OS
owner; project capabilities are distinct. Network deployment/auth is separate. -/
def run : IO UInt32 := do
  let root ← directory
  let owner ← lease (root / "service.guard")
  let socket ← Socket.Server.mk
  socket.bind (Daemon.loopback 0)
  socket.listen maxClients.toUInt32
  socket.noDelay
  let address ← socket.getSockName
  let endpoint : Daemon.Endpoint := {
    session := "publisher",pid := (← IO.Process.getPID).toNat,port := address.port.toNat
    secret := Blake3.hex (← IO.getRandomBytes 32),generation := ← generation }
  writeJson (root / "endpoint.json") endpoint
  let server : Server := ⟨← Std.Mutex.new ({} : State),← Std.Mutex.new 0,← IO.mkRef false⟩
  -- `finally` must read the live owners, rather than a mutable local captured
  -- when its cleanup closure was constructed.
  let clients ← IO.mkRef ([] : List (Task (Except IO.Error Unit)))
  let publications ← IO.mkRef ([] : List (Task (Except IO.Error Unit)))
  let mut activity ← IO.monoMsNow
  try
    while !(← server.stopping.get) do
      match ← socket.tryAccept with
      | none => pure ()
      | some client =>
          activity ← IO.monoMsNow
          if (← clients.get).length < maxClients then
            let task ← IO.asTask (serveClient server endpoint.secret client) .dedicated
            clients.modify (task :: ·)
      clients.set (← retain (← clients.get))
      publications.set (← retain (← publications.get))
      while (← publications.get).length < 2 do
        let some (path,identity,jobs) ← takeGroup server | break
        let task ← IO.asTask (publish server path identity jobs) .dedicated
        publications.modify (task :: ·)
      if (← clients.get).isEmpty && (← publications.get).isEmpty && (← IO.monoMsNow) > activity+300000 then
        server.stopping.set true
      IO.sleep 1
    return 0
  finally
    server.stopping.set true
    let projects ← close server
    let publications ← publications.get
    let clients ← clients.get
    -- No derived preparation is part of this wait. Active source commits
    -- finish their bounded group; queued requests receive no source ACK.
    for task in publications do let _ ← IO.wait task; pure ()
    -- receiveLive/awaitReply poll `stopping` every five milliseconds. Do not
    -- cancel tasks parked in async socket selectors: cancelling a selector's
    -- waiter does not guarantee that its blocking task completes.
    for task in clients do let _ ← IO.wait task; pure ()
    for project in projects do FileSystem.unlockRead project.lease
    if let some current ← (readJson? (root / "endpoint.json") [] : IO (Option Daemon.Endpoint)) then
      if current.secret == endpoint.secret then removeIfExists (root / "endpoint.json")
    FileSystem.unlockRead owner

end Eggshell.Plugin.Publication.Service
