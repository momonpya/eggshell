module

public import Eggshell.PluginModel
public import Std.Async.TCP
public import Std.Async.Timer

@[expose] public section

namespace Eggshell.Plugin.Daemon

open Lean Std Async TCP

def maxFrameBytes : Nat := 8 * 1024 * 1024
def startupAttempts : Nat := 80

structure Endpoint where
  session : String := ""
  pid : Nat := 0
  port : Nat
  secret : String
  /-- Identity of the daemon executable selected by the current Plugin bundle. -/
  generation : String
  deriving ToJson, FromJson

def endpointJsonDefaults : List (String × Json) :=
  [("session", toJson ""), ("pid", toJson (0 : Nat))]

namespace Endpoint

def compatible (endpoint : Endpoint) (generation : String) : Bool :=
  endpoint.generation == generation

theorem incompatible_generation_rejected {endpoint : Endpoint} {generation : String}
    (different : endpoint.generation ≠ generation) :
    endpoint.compatible generation = false := by
  simp [compatible, different]

end Endpoint

def endpointPath (session : String) : IO System.FilePath := do
  pure ((← sessionFiles session).directory / "daemon.json")

def startupLock (session : String) : IO System.FilePath := do
  pure ((← sessionFiles session).directory / "daemon-start")

def daemonExecutable : IO System.FilePath := do
  match ← IO.getEnv "PLUGIN_ROOT" with
  | some root =>
      let bundled := System.FilePath.mk root / "bin" / "eggshelld"
      if ← bundled.pathExists then pure bundled else IO.appPath
  | none => IO.appPath

/--
The endpoint is valid only for the executable selected by this Plugin bundle.
File metadata is a private lifecycle generation, not semantic authority; it
keeps a reinstalled Plugin from silently talking to an older resident daemon.
-/
def executableGeneration (path : System.FilePath) : IO String := do
  let metadata ← path.metadata
  pure s!"{metadata.byteSize}:{repr metadata.modified}"

def desiredGeneration : IO String := do
  executableGeneration (← daemonExecutable)

def loopback (port : UInt16) : Net.SocketAddress :=
  .v4 ⟨.ofParts 127 0 0 1, port⟩

def frameLength (bytes : ByteArray) : ByteArray :=
  let value := bytes.size.toUInt32
  .mk #[
    (value >>> 24).toUInt8,
    (value >>> 16).toUInt8,
    (value >>> 8).toUInt8,
    value.toUInt8]

def decodeLength (bytes : ByteArray) : Nat :=
  ((bytes.get! 0).toNat <<< 24) |||
    ((bytes.get! 1).toNat <<< 16) |||
    ((bytes.get! 2).toNat <<< 8) ||| (bytes.get! 3).toNat

partial def receiveExactly (client : Socket.Client) (remaining : Nat)
    (deadline : Nat) (received : ByteArray := ByteArray.empty) : IO ByteArray := do
  if remaining = 0 then return received
  let now ← IO.monoMsNow
  if now ≥ deadline then throw (IO.userError "daemon receive deadline expired")
  let chunk ← (do
    let timer ← Selector.sleep (.ofNat (deadline - now))
    Selectable.one #[
      .case (client.recvSelector remaining.toUInt64) pure,
      .case timer (fun _ => throw (IO.userError "daemon receive deadline expired"))]).block
  let some chunk := chunk |
    throw (IO.userError "eggshelld closed an incomplete frame")
  if chunk.isEmpty then
    throw (IO.userError "eggshelld returned an empty frame")
  receiveExactly client (remaining - chunk.size) deadline (received.append chunk)

def receiveFrameBefore (client : Socket.Client) (deadline : Nat) : IO ByteArray := do
  let header ← receiveExactly client 4 deadline
  let length := decodeLength header
  if length > maxFrameBytes then
    throw (IO.userError "eggshelld frame exceeds the transport bound")
  receiveExactly client length deadline

def receiveFrame (client : Socket.Client) (budget : Nat := 24000) : IO ByteArray := do
  receiveFrameBefore client ((← IO.monoMsNow) + budget)

def sendFrame (client : Socket.Client) (payload : ByteArray) : IO Unit := do
  if payload.size > maxFrameBytes then
    throw (IO.userError "eggshelld frame exceeds the transport bound")
  (client.sendAll #[frameLength payload, payload]).block

def response (output : Except String String) : Json :=
  match output with
  | .ok value => Json.mkObj [("ok", true), ("output", value)]
  | .error message => Json.mkObj [("ok", false), ("error", message)]

def request (secret kind : String) (payload : Json := Json.null) : Json :=
  Json.mkObj [("secret", secret), ("kind", kind), ("payload", payload)]

def connect (endpoint : Endpoint) : IO Socket.Client := do
  if endpoint.port > 65535 then
    throw (IO.userError "invalid eggshelld port")
  let client ← Socket.Client.mk
  (client.connect (loopback endpoint.port.toUInt16)).block
  pure client

def exchangeBefore (endpoint : Endpoint) (kind : String)
    (payload : Json) (deadline : Nat) : IO String := do
  let client ← connect endpoint
  sendFrame client (request endpoint.secret kind payload |>.compress |>.toUTF8)
  let bytes ← receiveFrameBefore client deadline
  let text ← match String.fromUTF8? bytes with
    | some text => pure text
    | none => throw (IO.userError "daemon response is not UTF-8")
  let json ← match Json.parse text with
    | .ok json => pure json
    | .error message => throw (IO.userError message)
  if json.getObjValD "ok" == true then
    pure ((json.getObjValAs? String "output").toOption.getD "")
  else throw (IO.userError ((json.getObjValAs? String "error").toOption.getD "daemon failure"))

def exchange (endpoint : Endpoint) (kind : String)
    (payload : Json := Json.null) (budget : Nat := 24000) : IO String := do
  exchangeBefore endpoint kind payload ((← IO.monoMsNow) + budget)

end Eggshell.Plugin.Daemon
