import Eggshell.SynapseBuild

open Lean Eggshell Eggshell.Synapses

/-- Research entrypoint for the native builder in the isolated warm candidate.
Read-only use always selects the private overlay; no answering model is run. -/
def main (args : List String) : IO Unit := do
  let database :: output :: remaining := args | throw (IO.userError "SynapseWarm DB FACTS-OUTPUT [FROZEN-LEAN-EXTRACTION]")
  unless remaining.length ≤ 1 do throw (IO.userError "at most one frozen extraction is supported")
  let snapshot ← DB.PageMap.pin (.mk database)
  let result ← Build.refresh snapshot .user
  let some reader ← Index.open? snapshot .user .shared | throw (IO.userError "native warm did not produce a readable index")
  let facts ← Index.allFacts reader.index
  if let some reference := remaining.head? then
    let json ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk reference)))
    let previous ← IO.ofExcept (json.getObjValAs? (Array Fact) "facts")
    let dbOnly := previous.filter fun fact => match fact with
      | .consumed _ | .used _ => false
      | _ => true
    let expected ← IO.ofExcept (Graph.ofFacts dbOnly)
    let actual ← IO.ofExcept (Graph.ofFacts facts)
    unless expected.snapshot == actual.snapshot do
      throw (IO.userError "native DB extraction differs from frozen Lean source bindings")
    IO.eprintln s!"exact frozen Lean source-binding comparison passed: {facts.size} facts"
  IO.FS.writeFile (.mk output) (toJson facts).compress
  IO.println (toJson result).compress
