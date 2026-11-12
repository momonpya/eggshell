module
import all Eggshell.OwnedSocket
import all Eggshell.DaemonWire
meta import Lean
open Lean Eggshell
theorem framing_preserved (bytes : ByteArray) :
    OwnedSocket.frameLength bytes = Plugin.Daemon.frameLength bytes := rfl
theorem decoding_preserved (bytes : ByteArray) :
    OwnedSocket.decodeLength bytes = Plugin.Daemon.decodeLength bytes := rfl
theorem frame_bound_preserved : OwnedSocket.maxFrameBytes = Plugin.Daemon.maxFrameBytes := rfl
#print axioms framing_preserved
#print axioms decoding_preserved
#print axioms frame_bound_preserved
#print axioms OwnedSocket.valid_port_bounded
#print axioms OwnedSocket.send_step_bounded
run_meta do
  let env ← getEnv
  let mut pending := [``OwnedSocket.withConnection,``OwnedSocket.Connection.writeFrame,``OwnedSocket.Connection.readFrame]
  let mut seen : NameSet := {}
  while let name :: rest := pending do
    pending := rest
    if seen.contains name then continue
    seen := seen.insert name
    let text := name.toString
    if ["IO.Process.spawn","Std.Mutex.","Std.SharedMutex.","IO.mkRef","Eggshell.Plugin.","Eggshell.DB."].any
        (fun excluded => text.startsWith excluded) then throwError "socket reaches an excluded effect: {name}"
    if let some info := env.find? name then
      if let some value := info.value? then pending := value.getUsedConstants.toList++pending
  Lean.logInfo m!"Owned socket closure: {seen.size} declarations; no process, application mutex, shared reference, graph or DB."
