import Eggshell.HookWire
import Eggshell.Sha256
open Lean Eggshell Eggshell.Plugin

/-- A protocol peer for supervisor failure tests, with no DB/model/service. -/
def main : List String → IO UInt32
  | ["codex-hook-child",_,receipt] => do
      let input ← IO.ofExcept (Json.parse (← (← IO.getStdin).readToEnd))
      let mode := (optionalString input "case").getD "valid"
      if mode == "hang" then IO.sleep 10000
      if mode == "silent" then return 0
      if mode == "malformed" then IO.println "{"; return 0
      if mode == "missing" then IO.println "{}"; return 0
      let output := if mode == "empty" then "{}" else if mode == "invalid" then "[]" else
        (Json.mkObj [("context",toJson "fixture original evidence")]).compress
      let ack := if mode == "valid" then Json.mkObj [("session_id",toJson "fixture"),("receipt",toJson receipt)] else Json.null
      IO.println (Json.mkObj [("output",toJson output),("ack",ack)]).compress
      return 0
  | ["codex-rpc","receipt"] => do
      let input ← IO.ofExcept (Json.parse (← (← IO.getStdin).getLine))
      let publication := input.getObjValD "publication"
      let output ← IO.ofExcept (publication.getObjValAs? String "output")
      unless publication.getObjValD "bytes" == toJson output.utf8ByteSize &&
          publication.getObjValD "sha256" == toJson (Sha256.hex output.toUTF8) do
        throw (IO.userError "supervisor changed the published bytes or digest")
      let some path ← IO.getEnv "EGGSHELL_FIXTURE_RECEIPT" | throw (IO.userError "missing fixture receipt path")
      IO.FS.writeFile (.mk path) input.compress
      IO.println (Json.mkObj [("output",toJson "")]).compress
      return 0
  | _ => throw (IO.userError "unexpected fixture backend operation")
