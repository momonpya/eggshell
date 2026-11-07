module
public import Eggshell.GraphStore
public import Lean.Data.Json.FromToJson
@[expose] public section
namespace Eggshell.Research.DecodedDagProbe
open Lean DB Persistence.Store

structure Row where
  frame : NodeFrame
  atomBytes : Nat

structure Walk where
  nodes : Std.HashSet Nat := {}
  atomBytes : Nat := 0
  atoms : Nat := 0
  edges : Nat := 0

/-- This probe follows the original checked references without resolving
Value trees or loading Atom bodies. Sizes are original metadata, not heap. -/
def walk (source : Snapshot) (cache : IO.Ref (Std.HashMap Nat Row))
    (roots : List Nat) : IO Walk := do
  let mut pending := roots
  let mut result : Walk := {}
  while let index :: tail := pending do
    pending := tail
    if result.nodes.contains index then continue
    result := {result with nodes := result.nodes.insert index}
    let row ← match (← cache.get)[index]? with
      | some row => pure row
      | none => do
          let checked ← readFrame source source.get index
          let bytes ← match checked.frame with
            | .atom => IO.ofExcept (payloadSize (← source.get (key "body" index)))
            | .apply .. => pure 0
          let row : Row := ⟨checked.frame,bytes⟩
          cache.modify (·.insert index row)
          pure row
    let children := row.frame.arguments
    let addedAtoms := match row.frame with | .atom => 1 | _ => 0
    result := {result with
      atomBytes := result.atomBytes + row.atomBytes
      atoms := result.atoms + addedAtoms
      edges := result.edges + children.length}
    pending := children.map Prod.snd ++ pending
  return result

def summary (walk : Walk) : Json := Json.mkObj [
  ("nodes",toJson walk.nodes.size),("atoms",toJson walk.atoms),
  ("atomBytes",toJson walk.atomBytes),("edges",toJson walk.edges)]

def run (project output : System.FilePath) : IO Unit := do
  unless !(← output.pathExists) do throw (IO.userError "preserve the previous DAG observation")
  let source ← PageMap.pin project
  let population ← getNat source.get "outcomes"
  let allocated ← getNat source.get "nodes"
  let cache ← IO.mkRef ({} : Std.HashMap Nat Row)
  let began ← IO.monoMsNow
  let mut owners := #[]
  let mut roots := []
  for ordinal in [:population] do
    let index ← getNat source.get (key "outcome" ordinal)
    let located ← locateOutcome source index
    let whole ← walk source cache [index]
    let work ← walk source cache [located.header.work]
    let outcome ← walk source cache [located.header.outcome]
    let observations ← walk source cache located.header.observations
    roots := index::roots
    owners := owners.push (Json.mkObj [("ordinal",toJson ordinal),("node",toJson index),
      ("workNode",toJson located.header.work),("outcomeNode",toJson located.header.outcome),
      ("whole",summary whole),("work",summary work),("outcome",summary outcome),
      ("observations",summary observations)])
  let union ← walk source cache roots
  let after ← PageMap.pin project
  unless after.head == source.head do throw (IO.userError "the original publication changed during the probe")
  let sum := fun field => owners.foldl (fun total row => total+
    ((row.getObjValD field).getObjValAs? Nat "atomBytes").toOption.getD 0) 0
  IO.FS.writeFile output (Json.mkObj [("project",toJson project.toString),("head",toJson source.head),
    ("owners",toJson owners),("liveOutcomes",toJson population),("allocatedNodes",toJson allocated),
    ("uniqueOriginalClosure",summary union),("sumOwnerAtomBytes",toJson (sum "whole")),
    ("sumWorkAtomBytes",toJson (sum "work")),("elapsedMs",toJson ((← IO.monoMsNow)-began)),
    ("framesRead",toJson (← cache.get).size),("valueTreesMaterialized",toJson false),
    ("atomBodiesLoaded",toJson false),("byteCountsAreMetadataNotHeap",toJson true),
    ("allLiveOwnersIncluded",toJson true),("originalHeadUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress

end Eggshell.Research.DecodedDagProbe
def main (args : List String) : IO Unit := do
  let [project,output] := args | throw (IO.userError "DAG probe PROJECT OUTPUT")
  Eggshell.Research.DecodedDagProbe.run (.mk project) (.mk output)
