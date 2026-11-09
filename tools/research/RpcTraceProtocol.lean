import tools.research.NumericalProtocolProbe
import tools.research.RpcTrace
open Lean Eggshell Eggshell.Plugin.Daemon Std Async TCP

#print axioms Eggshell.Research.RpcTrace.disabled_mark
#print axioms Eggshell.Research.RpcTrace.disabled_connection
#print axioms Eggshell.Research.RpcTrace.disabled_close

namespace RpcTraceProtocol
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)

def frameCase (mode : String) : IO Json := do
  let socket ← Socket.Server.mk
  socket.bind (loopback 0)
  socket.listen 8
  socket.noDelay
  let address ← socket.getSockName
  let endpoint : Endpoint := {port := address.port.toNat,secret := "fixture",generation := "rpc-frame"}
  let body := "日本語・한글・é・😀\n\"\\"++String.ofList (List.replicate 70000 'x')
  let server ← IO.asTask (do
    let client ← TaskDeadline.run socket.accept ((← IO.monoMsNow)+2000)
    let events ← IO.mkRef (#[] : Array (String × Nat))
    let trace ← Research.RpcTrace.start? "server" "other" (some events)
    Research.RpcTrace.connected trace client
    try
      Research.RpcTrace.mark trace "request-read:start"
      let bytes ← receiveFrameBefore client ((← IO.monoMsNow)+2000)
      Research.RpcTrace.mark trace "request-read:end"
      let some text := String.fromUTF8? bytes | throw (IO.userError "fixture request was not UTF8")
      let request ← IO.ofExcept (Json.parse text)
      check (request.getObjValD "payload" == toJson body) "fixture request bytes changed"
      if mode == "timeout" || mode == "cancel" then IO.sleep 200
      let output := if mode == "error" then response (.error "fixture refusal") else response (.ok body)
      Research.RpcTrace.mark trace "send:start"
      sendFrameBefore client output.compress.toUTF8 ((← IO.monoMsNow)+2000)
      Research.RpcTrace.mark trace "send:end"
    finally Research.RpcTrace.close trace) .dedicated
  let started ← IO.monoMsNow
  let task ← IO.asTask (Research.RpcTrace.exchange endpoint "encode" (toJson body)
    (started+(if mode == "timeout" then 50 else 2000))) .dedicated
  if mode == "cancel" then
    IO.sleep 30
    IO.cancel task
  let result ← IO.wait task
  let elapsed := (← IO.monoMsNow)-started
  let serverResult ← IO.wait server
  let correct := match result with
    | .ok output => mode == "ok" && output == body
    | .error _ => mode != "ok"
  check correct "framed success/error/deadline/cancellation changed"
  if mode == "ok" || mode == "error" then check serverResult.isOk "ordinary server failed"
  return Json.mkObj [("mode",toJson mode),("correct",toJson correct),("clientSucceeded",toJson result.isOk),
    ("elapsedMs",toJson elapsed),("serverSucceeded",toJson serverResult.isOk)]

def controls (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh trace controls output required"
  IO.FS.createDirAll root
  let mut rows := #[]
  for mode in ["ok","error","timeout","cancel"] do rows := rows.push (← frameCase mode)
  IO.FS.writeFile (root/"result.json") (Json.mkObj [("cases",toJson rows),
    ("requestAndReplyBytesPreserved",toJson true),("droppedRepliesAndCancellationObserved",toJson true),
    ("observerEnabled",toJson Research.RpcTrace.configured.isSome),("answeringModelCalls",toJson (0 : Nat))]).compress
end RpcTraceProtocol

def main (args : List String) : IO UInt32 := do
  match args with
  | ["rpc-frame-controls",root] => RpcTraceProtocol.controls (.mk root); return 0
  | ["codex-numerical-daemon",model,models,python] => Numerical.serve ⟨model,.mk models,.mk python⟩
  | ["rpc-protocol",root,count] =>
    let some count := count.toNat? | throw (IO.userError "count required")
    NumericalProtocolProbe.run (.mk root) count
    return 0
  | other => sourceRouteEngine other
