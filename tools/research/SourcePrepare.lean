import Eggshell.PublicationWire
open Lean Eggshell Eggshell.Synapses

/-- Compile separately against each arm's audited runtime modules. The
comparison controller must not prepare another arm with its own producer. -/
def main (args : List String) : IO Unit := do
  let [database,refinement,output] := args |
    throw (IO.userError "isolated source DB, frozen supplements and fresh output required")
  let path := System.FilePath.mk database
  unless path.isAbsolute && database.startsWith
      "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot/prepared-bindings-trial/" &&
      !(← (System.FilePath.mk output).pathExists) do
    throw (IO.userError "only a fresh comparison-arm source may be prepared")
  let specification ← IO.ofExcept (Json.parse (← IO.FS.readFile refinement))
  let source ← DB.PageMap.pin path
  unless specification.getObjValD "source" == toJson source.head do
    throw (IO.userError "supplements differ from the exact common source")
  let values : Array (Nat × String × ContentCapture.Supplement) ←
    IO.ofExcept (specification.getObjValAs? _ "supplements")
  let reader ← Persistence.Store.NodeReader.new source
  let mut supplements := #[]
  for (id,owner,value) in values do
    unless (← Build.document reader id).owner == owner do
      throw (IO.userError "supplement crossed original owner identity")
    if value.sealed then supplements := supplements.push (id,value)
  let prepared ← Build.refresh source .database supplements
  let result := (toJson prepared).setObjVal! "preparerGeneration" (toJson (← Plugin.Publication.generation))
  IO.FS.writeFile output result.pretty
  IO.println result.compress
