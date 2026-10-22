import Eggshell.SynapseArchive

open Lean Eggshell.Synapses Eggshell.Synapses.Extraction

def main (args : List String) : IO Unit := do
  let inputPath :: rpcs := args | throw (IO.userError "SynapseExtract NATIVE-EXPORT RPC...")
  unless !rpcs.isEmpty do throw (IO.userError "actual RPC traces are required")
  let archive ← Archive.load (.mk inputPath)
  let database := archive.database
  let docs := archive.documents
  let mut trace : Trace := {}
  for rpc in rpcs do trace ← IO.ofExcept (combineTraces trace (← readTrace (.mk rpc)))
  let mut reads := #[]
  let mut issues := #[]
  let mut bound := 0
  let mut rows : Std.HashMap Occurrence (Array OutputRow) := {}
  for doc in docs do
    if !doc.native then continue
    match recordedReads database doc with
    | .ok recorded => reads := reads ++ recorded
    | .error reason => issues := issues.push (Json.mkObj [("owner", toJson doc.owner), ("reason", toJson reason)])
    match locateReads database doc trace with
    | .ok located =>
      bound := bound + 1
      for value in located do
        let occurrence := value.read.occurrence
        rows := rows.insert occurrence (rows[occurrence]?.getD #[] ++ value.rows)
    | .error reason => issues := issues.push (Json.mkObj [("owner", toJson doc.owner), ("reason", toJson reason)])
  trace ← IO.ofExcept (trace.locate rows)
  let mut graph := trace.graph
  for located in reads do graph ← IO.ofExcept (graph.insert (.read located.read))
  for doc in docs do
    if doc.native then continue
    let route := reachable archive.all doc.work
    match addAnswer database doc (reads.filter (route.contains ·.read.binding.work)) graph with
    | .ok next => graph := next
    | .error reason => issues := issues.push (Json.mkObj [("owner", toJson doc.owner), ("reason", toJson reason)])
  IO.println (Json.mkObj [
    ("database", toJson database), ("facts", toJson graph.snapshot),
    ("summary", Json.mkObj [
      ("documents", toJson docs.size), ("completedCalls", toJson trace.finished.size),
      ("boundObservations", toJson bound), ("readChunks", toJson reads.size),
      ("rangeNodes", toJson graph.rangeCount), ("evidence", toJson graph.evidenceCount),
      ("issues", toJson issues)])]).compress
