import Eggshell.PublicationWire
import tools.research.ArtifactHash
open Lean Eggshell

/-- Build against each arm's audited module closure. This value comes from
its original source bytes, not a running service's self-reported endpoint. -/
def main (args : List String) : IO Unit := do
  let [binary,output] := args | throw (IO.userError "one audited runtime executable and a fresh descriptor path required")
  let path := System.FilePath.mk binary
  unless path.isAbsolute && !(← (System.FilePath.mk output).pathExists) do
    throw (IO.userError "absolute runtime and fresh descriptor required")
  let value := Json.mkObj [("binary",toJson binary),
    ("sha256",toJson (← Eggshell.Research.ArtifactHash.hex path)),
    ("generation",toJson (← Plugin.Publication.generation))]
  IO.FS.writeFile output value.pretty
  IO.println value.compress
