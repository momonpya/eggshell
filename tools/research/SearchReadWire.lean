import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean

/-- A small native Lean peer emits the exact frame bytes supplied by the
product-side test. It contains no Eggshell runtime, DB, model or protocol. -/
def main : IO Unit := do
  let input ← IO.getStdin
  let output ← IO.getStdout
  repeat
    let raw ← input.getLine
    if raw.isEmpty then return
    let payload ← IO.ofExcept (Json.parse raw)
    let frames ← IO.ofExcept (payload.getObjValAs? (Array Json) "frames")
    let pause ← IO.ofExcept (payload.getObjValAs? Nat "pauseMs")
    if frames.isEmpty then IO.sleep pause.toUInt32
    for (frame,index) in frames.zipIdx do
      if index > 0 then IO.sleep pause.toUInt32
      output.putStrLn frame.compress
      output.flush
