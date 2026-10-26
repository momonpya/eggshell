import Eggshell.SynapseUsage
open Lean Eggshell.Synapses

private def read (path : String) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))

/-- Assess only the already frozen alternatives against the independently
recorded walk. This tool has no product or answering-model entry point. -/
def main (args : List String) : IO Unit := do
  let [frozenPath,walkPath,outputPath] := args |
    throw (IO.userError "SynapticWalkCoverage FROZEN WALK NEW-REPORT")
  unless !(← (System.FilePath.mk outputPath).pathExists) do
    throw (IO.userError "keep earlier coverage evidence")
  let frozen ← read frozenPath
  let units ← IO.ofExcept (frozen.getObjValAs? (Array Json) "units")
  let trials ← IO.ofExcept ((← read walkPath).getObjValAs? (Array Json) "trials")
  let mut assessed := #[]
  for trial in trials do
    let result := trial.getObjValD "result"
    let offers ← IO.ofExcept (result.getObjValAs? (Array Json) "offers")
    let mut ranges : Array Range := #[]
    for offer in offers do
      if let some source ← IO.ofExcept (offer.getObjValAs? (Option Range) "source") then
        ranges := ranges.push source
    let mut missing : Array Json := #[]
    for unit in units do
      let alternatives ← IO.ofExcept (unit.getObjValAs? (Array Range) "alternatives")
      unless alternatives.any (fun target => covered target ranges) do
        missing := missing.push (unit.getObjValD "names")
    assessed := assessed.push (Json.mkObj [
      ("label",trial.getObjValD "label"),("complete",result.getObjValD "complete"),
      ("elapsedMs",trial.getObjValD "elapsedMs"),("requests",result.getObjValD "requests"),
      ("facts",result.getObjValD "facts"),("offers",toJson offers.size),
      ("eligible",toJson units.size),("covered",toJson (units.size-missing.size)),
      ("missing",toJson missing),("actualDelivery",toJson false)])
  IO.FS.writeFile (.mk outputPath) (toJson assessed).pretty
  IO.println (toJson assessed).compress
