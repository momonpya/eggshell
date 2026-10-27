import tools.research.StudyTrial
open Lean Eggshell
namespace Eggshell.Research.StudyBudgetChecks

def run (fixture directory : String) : IO Unit := do
  let root := System.FilePath.mk directory
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "preserve prior budget checks")
  IO.FS.createDirAll root
  let cases := #[("normal","ok",200,5000,false),("limit","ok",100,5000,true),
    ("unrelated","wrong-usage",200,5000,false),("time","turn-hang",1000,200,true)]
  let mut results := #[]
  for (label,mode,tokens,milliseconds,shouldStop) in cases do
    let output := root / label
    IO.FS.createDir output
    let settings : StudyTransport.Settings := {
      command := #[fixture,mode],cwd := root.toString,environment := #[],output := (output / "rpc").toString,
      timeoutMs := 10000,responseBytes := 1024*1024,transcriptBytes := 4*1024*1024}
    let stopped ← IO.mkRef false
    StudyTransport.withClient .generate settings fun client => do
      let _ ← StudyTransport.handshake client "fixture"
      let _ ← StudyTransport.request client (.run .threadStart) (Json.mkObj [])
      let deadline := (← IO.monoMsNow)+milliseconds
      let _ ← StudyTransport.request client (.run .turnStart) (Json.mkObj []) (deadline? := some deadline)
      try
        let _ ← StudyTrial.waitTurn client output "fixture-thread" "fixture-turn"
          (some {inclusiveTokens := tokens,answerMs := milliseconds}) deadline
        pure ()
      catch _ => stopped.set true
    let stopped ← stopped.get
    unless stopped == shouldStop do throw (IO.userError s!"wrong budget decision: {label}")
    let input ← IO.FS.Handle.mk (output / "rpc/exchange.jsonl") .read
    let mut interrupts := 0
    repeat
      let line ← input.getLine
      if line.isEmpty then break
      let row ← IO.ofExcept (Json.parse line)
      if row.getObjValD "direction" == toJson "client" &&
          (row.getObjValD "message").getObjValD "method" == toJson "turn/interrupt" then
        interrupts := interrupts+1
    unless interrupts == (if shouldStop then 1 else 0) do
      throw (IO.userError s!"budget did not send exactly the expected interruption: {label}")
    let state ← StudyAccounting.replay ⟨"fixture-thread","fixture-turn",Sha256.hex "fixture body".toUTF8⟩
      (output / "rpc/exchange.jsonl")
    let usage := state.lastUsage.map (fun value => value.inclusive)
    unless mode == "turn-hang" || usage == some 110 do
      throw (IO.userError "inclusive usage was lost or counted cached/reasoning twice")
    results := results.push (Json.mkObj [("case",toJson label),("stopped",toJson stopped),
      ("interrupts",toJson interrupts),("syntheticInclusiveTokens",toJson usage)])
  IO.FS.writeFile (root / "result.json") (Json.mkObj [("cases",toJson results),
    ("answeringModelCalls",toJson (0 : Nat)),("fixtureHasNoProvider",toJson true)]).compress
  IO.println (toJson results).compress

end Eggshell.Research.StudyBudgetChecks
