import tools.research.PreparedRoutingObserver

open Lean Eggshell.Research.PreparedRoutingObserver

def main (args : List String) : IO Unit := do
  match args with
  | [input] => runAt input 700 "1"
  | ["transport",input] => do
    let value ← read (.mk input)
    let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (value.getObjValD "environment"))
    let some (_,some path) := environment.find? (·.1 == "EGGSHELL_HANDOFF_TRACE") |
      throw (IO.userError "transport sampling requires the existing handoff trace")
    let wait : IO Unit := do
      let deadline := (← IO.monoMsNow)+180000
      repeat
        check ((← IO.monoMsNow) < deadline) "transport stage was not reached"
        if ← (System.FilePath.mk path).pathExists then
          let text ← IO.FS.readFile (.mk path)
          if (text.splitOn "ms synaptic owners\n").length ≥ 5 then break
        IO.sleep 5
    runAt input 0 "1" (some wait)
  | _ => throw (IO.userError "early-source-sample [transport] INPUT")
