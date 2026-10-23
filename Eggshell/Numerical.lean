module

public import Eggshell.DaemonWire
public import Eggshell.MiniLM
public import Eggshell.Sha256
public import Std.Sync.Mutex

@[expose] public section

namespace Eggshell.Numerical
open Lean Std Async TCP Plugin.Daemon

structure Config where
  model : String
  models : System.FilePath
  python : System.FilePath

def Config.key (config : Config) : String :=
  Sha256.hex ((toJson (config.model,config.models.normalize.toString,config.python.normalize.toString,
    MiniLM.embeddingSource,include_str "Numerical.lean",include_str "DaemonWire.lean")).compress.toUTF8)

def directory (config : Config) : IO System.FilePath := do
  let path := (← Paths.dataRoot) / "numerical" / config.key
  FileSystem.rejectSymlinkAncestors path
  FileSystem.privateDirectory path
  return path

def lockFile (path : System.FilePath) : IO FileSystem.ReadHandle := do
  FileSystem.immutableExistingBytes path ByteArray.empty
  FileSystem.openRead path.toString

def claim (handle : FileSystem.ReadHandle) (exclusive : Bool) (deadline : Nat) : IO Unit := do
  repeat
    unless (← IO.monoMsNow) < deadline do throw (IO.userError "numerical ownership deadline expired")
    if ← FileSystem.tryReadLock handle exclusive then return
    IO.sleep 5

structure Keeper where
  config : Config
  handle : FileSystem.ReadHandle

def keep (config : Config) : IO Keeper := do
  let handle ← lockFile ((← directory config) / "owners.guard")
  claim handle false ((← IO.monoMsNow)+10000)
  return ⟨config,handle⟩

abbrev Service := IO.Process.Child {stdin := .null,stdout := .null,stderr := .inherit}
abbrev Kernel := IO.Process.Child {stdin := .piped,stdout := .piped,stderr := .inherit}

initialize ownedServices : IO.Ref (Array Service) ← IO.mkRef #[]

def alive (pid : Nat) : IO Bool := do
  for child in ← ownedServices.get do
    if child.pid.toNat == pid then
      if (← child.tryWait).isSome then
        ownedServices.modify (·.filter (·.pid.toNat != pid))
        return false
  let status ← IO.Process.output {cmd := "/bin/kill",args := #["-0",toString pid],stdin := .null}
  return status.exitCode == 0

def endpoint? (config : Config) : IO (Option Endpoint) := do
  Plugin.readJson? ((← directory config) / "endpoint.json") endpointJsonDefaults

def resolve (config : Config) : IO Endpoint := do
  let root ← directory config
  let starting ← lockFile (root / "starting.guard")
  claim starting true ((← IO.monoMsNow)+10000)
  try
    let generation := config.key
    if let some endpoint ← endpoint? config then
      if ← alive endpoint.pid then
        unless endpoint.session == config.key && endpoint.compatible generation do
          throw (IO.userError "numerical endpoint belongs to another executable or model")
        let _ ← exchange endpoint "ping" (budget := 500)
        return endpoint
      IO.FS.removeFile (root / "endpoint.json")
    let child ← IO.Process.spawn {
      cmd := (← IO.appPath).toString
      args := #["codex-numerical-daemon",config.model,config.models.toString,config.python.toString]
      stdin := .null,stdout := .null,stderr := .inherit,setsid := true}
    ownedServices.modify (·.push child)
    let deadline := (← IO.monoMsNow)+10000
    repeat
      unless (← child.tryWait).isNone do throw (IO.userError "numerical daemon exited during startup")
      if let some endpoint ← endpoint? config then
        unless endpoint.pid == child.pid.toNat && endpoint.session == config.key && endpoint.compatible generation do
          throw (IO.userError "numerical startup returned another owner")
        let _ ← exchange endpoint "ping" (budget := 500)
        return endpoint
      unless (← IO.monoMsNow) < deadline do throw (IO.userError "numerical daemon startup expired")
      IO.sleep 5
  finally FileSystem.unlockRead starting

/-- The last live caller prevents new owners from entering until the model
and service really exit. Another chat's live claim is never cancelled. -/
def release (keeper : Keeper) (drainMs : Nat := 0) : IO Unit := do
  let retained ← endpoint? keeper.config
  FileSystem.unlockRead keeper.handle
  let deadline := (← IO.monoMsNow)+drainMs
  repeat
    if ← FileSystem.tryReadLock keeper.handle true then break
    if (← IO.monoMsNow) ≥ deadline then return
    IO.sleep 5
  try
    if let some endpoint := retained then
      if ← alive endpoint.pid then
        let generation := keeper.config.key
        unless endpoint.session == keeper.config.key && endpoint.compatible generation do
          throw (IO.userError "cannot stop a foreign numerical owner")
        if (← endpoint? keeper.config).isSome then
          let _ ← exchange endpoint "shutdown" (budget := 500)
          pure ()
        let deadline := (← IO.monoMsNow)+10000
        while ← alive endpoint.pid do
          unless (← IO.monoMsNow) < deadline do throw (IO.userError "numerical model did not exit after shutdown")
          IO.sleep 5
  finally FileSystem.unlockRead keeper.handle

def withKeeper (config : Config) (action : IO α) : IO α := do
  let keeper ← keep config
  try action finally release keeper

def defaultConfig? : IO (Option Config) := do
  let layout := MiniLM.layout (← Paths.installRoot)
  return (← MiniLM.runtimePython? layout).map fun python => ⟨MiniLM.model,layout.models,python⟩

def withDefaultKeeper (action : IO α) (drainMs : Nat := 0) : IO α := do
  let some config ← defaultConfig? | action
  let keeper ← keep config
  try action finally release keeper drainMs

def spawnKernel (config : Config) (lease : System.FilePath) : IO Kernel := do
  let _ ← lockFile lease
  IO.Process.spawn {
    cmd := config.python.toString
    args := #["-c",MiniLM.embeddingSource,config.model,config.models.toString,"4",lease.toString,"shared"]
    stdin := .piped,stdout := .piped,stderr := .inherit}

def stopKernel (child : Kernel) : IO Unit := do
  child.kill
  let _ ← child.wait
  pure ()

def awaitLine (child : Kernel) (deadline : Nat) : IO String := do
  let reading ← IO.asTask child.stdout.getLine .dedicated
  repeat
    if ← IO.hasFinished reading then
      let result ← IO.ofExcept ((← IO.wait reading).mapError IO.Error.toString)
      unless !result.isEmpty do throw (IO.userError "numerical kernel closed its response")
      return result
    unless (← IO.monoMsNow) < deadline do
      child.kill
      throw (IO.userError "numerical kernel response expired")
    IO.sleep 5

/-- A disconnected request waiting for the numerical gate cannot start work.
No mutex action is queued for later execution after this check returns. -/
def peerWaiting (client : Socket.Client) : IO Bool :=
  (do
    let timer ← Selector.sleep (.ofNat 5)
    Selectable.one #[.case (client.recvSelector 1) (fun _ => pure false),
      .case timer (fun _ => pure true)]).block

structure Backend where
  gate : Std.Mutex Unit
  child : IO.Ref (Option Kernel)
  starts : IO.Ref Nat
  stopping : IO.Ref Bool

def Backend.encode (backend : Backend) (config : Config) (client : Socket.Client)
    (body : String) (deadline : Nat) : IO String := do
  unless body.toUTF8.size ≤ maxFrameBytes/2 do throw (IO.userError "numerical text request exceeds its bound")
  let request ← IO.ofExcept (Json.parse body)
  let _ ← IO.ofExcept (request.getObjValAs? (Array String) "texts")
  repeat
    unless !(← backend.stopping.get) && (← IO.monoMsNow) < deadline do
      throw (IO.userError "numerical request is no longer live")
    let result ← backend.gate.tryAtomically do
      unless !(← backend.stopping.get) && (← IO.monoMsNow) < deadline do
        throw (IO.userError "numerical gate admission expired")
      let child ← match ← backend.child.get with
        | some child => pure child
        | none => do
            let child ← spawnKernel config ((← directory config) / "model.guard")
            backend.child.set (some child)
            backend.starts.modify (·+1)
            pure child
      try
        child.stdin.putStr body
        child.stdin.flush
        awaitLine child deadline
      catch error =>
        backend.stopping.set true
        throw error
    if let some result := result then return result
    unless ← peerWaiting client do throw (IO.userError "numerical requester disconnected before admission")

def serveClient (backend : Backend) (config : Config) (secret : String) (client : Socket.Client) : IO Unit := do
  let deadline := (← IO.monoMsNow)+24000
  let reply ← try
    let bytes ← receiveFrameBefore client deadline
    let some text := String.fromUTF8? bytes | throw (IO.userError "invalid numerical frame encoding")
    let request ← IO.ofExcept (Json.parse text)
    unless (request.getObjValAs? String "secret").toOption == some secret do
      throw (IO.userError "unauthorized numerical request")
    let kind ← IO.ofExcept (request.getObjValAs? String "kind")
    let output ← match kind with
      | "ping" => pure ""
      | "stats" => pure ((Json.mkObj [("modelStarts",toJson (← backend.starts.get)),
          ("modelPid",toJson ((← backend.child.get).map (·.pid.toNat)))]).compress)
      | "shutdown" => backend.stopping.set true; pure ""
      | "encode" =>
          backend.encode config client (← IO.ofExcept (request.getObjValAs? String "payload")) deadline
      | _ => throw (IO.userError "unsupported numerical operation")
    pure (response (.ok output))
  catch error => pure (response (.error error.toString))
  sendFrame client reply.compress.toUTF8

def serve (config : Config) : IO UInt32 := do
  let root ← directory config
  let owners ← lockFile (root / "owners.guard")
  let server ← Socket.Server.mk
  server.bind (loopback 0)
  server.listen 32
  server.noDelay
  let address ← server.getSockName
  let endpoint : Endpoint := {
    session := config.key,pid := (← IO.Process.getPID).toNat,port := address.port.toNat
    secret := Blake3.hex (← IO.getRandomBytes 32),generation := config.key}
  let backend : Backend := ⟨← Std.Mutex.new (),← IO.mkRef none,← IO.mkRef 0,← IO.mkRef false⟩
  FileSystem.atomicExistingBytes (root / "endpoint.json") (toJson endpoint).compress.toUTF8
  FileSystem.privateFile (root / "endpoint.json")
  let mut clients : List (Task (Except IO.Error Unit)) := []
  let mut exclusive := false
  try
    while !(← backend.stopping.get) do
      if ← FileSystem.tryReadLock owners true then
        exclusive := true
        backend.stopping.set true
        break
      if clients.length < 32 then
        if let some client ← server.tryAccept then
          clients := (← IO.asTask (serveClient backend config endpoint.secret client) .dedicated) :: clients
      let mut running := []
      for task in clients do
        if ← IO.hasFinished task then let _ ← IO.wait task; pure ()
        else running := task :: running
      clients := running
      IO.sleep 1
    return 0
  finally
    backend.stopping.set true
    if let some child ← backend.child.get then stopKernel child
    for task in clients do let _ ← IO.wait task; pure ()
    if let some current ← endpoint? config then
      if current.pid == endpoint.pid && current.secret == endpoint.secret then IO.FS.removeFile (root / "endpoint.json")
    if exclusive then FileSystem.unlockRead owners

/-- Embedding batches use the shared model. Large cache-only scoring frames
stay on a local NumPy process and never enter the bounded RPC transport. -/
def proxy (config : Config) : IO UInt32 := withKeeper config do
  let scores ← IO.mkRef (none : Option Kernel)
  let shared ← IO.mkRef (none : Option Endpoint)
  try
    let input ← IO.getStdin
    let output ← IO.getStdout
    repeat
      let marker ← input.read 1
      if marker.isEmpty then break
      let body ← input.getLine
      if marker[0]! == 67 then break
      let reply ← try
        if marker[0]! == 69 then
          let endpoint ← match ← shared.get with
            | some endpoint => pure endpoint
            | none => do
                let endpoint ← resolve config
                shared.set (some endpoint)
                pure endpoint
          exchange endpoint "encode" (toJson body)
        else if marker[0]! == 83 then
          let child ← match ← scores.get with
            | some child => pure child
            | none => do
                let child ← spawnKernel config ((← directory config) / "score-unused.guard")
                scores.set (some child)
                pure child
          child.stdin.putStr body
          child.stdin.flush
          awaitLine child ((← IO.monoMsNow)+24000)
        else throw (IO.userError "invalid numerical pipe operation")
      catch error => pure ((Json.mkObj [("error",toJson error.toString)]).compress ++ "\n")
      output.putStr reply
      output.flush
    return 0
  finally
    if let some child ← scores.get then stopKernel child

end Eggshell.Numerical
