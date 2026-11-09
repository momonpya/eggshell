import tools.VerifiedWinnerCoverage
import tools.SharedCoverageInput
import Lean.Data.Json.Parser
open Lean SharedCoverage

namespace WinnerReplay
@[noinline,nospecialize] def select (problem : Problem) := SharedCoverage.choose? problem
def main (input output : System.FilePath) : IO Unit := do
  unless !(← output.pathExists) do throw (IO.userError "preserve prior actual selector replay")
  let encoded ← IO.ofExcept (Json.parse (← IO.FS.readFile input))
  let raw ← IO.ofExcept (fromJson? encoded : Except String Input.RawProblem)
  let problem ← IO.ofExcept raw.decode
  unless Input.encode problem == encoded do throw (IO.userError "selector input is not a canonical complete problem")
  let stored ← IO.mkRef problem
  let mut rows := #[]
  let mut previous : Option Json := none
  for repetition in [:3] do
    let problem ← stored.get
    let began ← IO.monoNanosNow
    let selection ← (← IO.mkRef (select problem)).get
    let elapsed := (← IO.monoNanosNow)-began
    let some selection := selection | throw (IO.userError "frozen selector problem is infeasible")
    let answer := Json.mkObj [("selected",toJson (selection.selected.map (·.val))),
      ("cost",toJson (cost problem selection.selected)),("benefit",toJson (benefit problem selection.selected))]
    if let some prior := previous then
      unless prior == answer do throw (IO.userError "deterministic selector replay changed within a binary")
    previous := some answer
    rows := rows.push (Json.mkObj [("repetition",toJson repetition),("elapsedNs",toJson elapsed)])
  IO.FS.writeFile output (Json.mkObj [("offers",toJson problem.offers.size),("nodes",toJson problem.costs.size),
    ("cues",toJson problem.weights.size),("answer",previous.getD Json.null),("rows",toJson rows),
    ("scope",toJson "complete captured conditioned selector; no IO, search, rendering or model cost"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end WinnerReplay

def main (args : List String) : IO Unit := do
  let [input,output] := args | throw (IO.userError "winner replay INPUT OUTPUT")
  WinnerReplay.main (.mk input) (.mk output)
