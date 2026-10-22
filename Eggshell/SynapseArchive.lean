module

public import Eggshell.SynapseUsage

@[expose] public section

namespace Eggshell.Synapses.Extraction
open Lean

/-- Read-only adapter for pinned native exports, not a DB publication verifier. -/
structure Archive where
  database : String
  documents : Array Document
  all : Std.HashMap String (Array String)

def Archive.load (path : System.FilePath) : IO Archive := do
  let handle ← IO.FS.Handle.mk path .read
  let header ← IO.ofExcept (Json.parse (← handle.getLine))
  unless (← IO.ofExcept (header.getObjValAs? String "kind")) == "publication" do
    throw (IO.userError "expected native publication header")
  let database ← IO.ofExcept ((header.getObjVal? "head") >>= (·.getObjValAs? String "identity"))
  unless digest database do throw (IO.userError "invalid DB identity")
  let topology ← IO.ofExcept (header.getObjValAs? (Array Json) "all")
  let mut all := {}
  for edge in topology do
    let parent ← IO.ofExcept (edge.getObjValAs? String "parent")
    let children ← IO.ofExcept (edge.getObjValAs? (Array String) "children")
    all := all.insert parent (all[parent]?.getD #[] ++ children)
  let mut documents := #[]
  while true do
    let line ← handle.getLine
    if line.isEmpty then break
    if !line.trimAscii.isEmpty then
      let json ← IO.ofExcept (Json.parse line)
      unless (← IO.ofExcept (json.getObjValAs? String "kind")) == "outcome" do
        throw (IO.userError "unexpected native export row")
      documents := documents.push (← IO.ofExcept (document json))
  return ⟨database, documents, all⟩

def readTrace (path : System.FilePath) : IO Trace := do
  let handle ← IO.FS.Handle.mk path .read
  let mut ordinal := 0
  let mut trace : Trace := {}
  while true do
    let line ← handle.getLine
    if line.isEmpty then break
    if !line.trimAscii.isEmpty then
      trace ← IO.ofExcept (Json.parse line >>= trace.notification ordinal)
    ordinal := ordinal + 1
  return trace

def combineTraces (left right : Trace) : Except String Trace := do
  let mut starts := left.starts
  let mut finished := left.finished
  for (occurrence, start) in right.starts do
    if let some previous := starts[occurrence]? then
      unless previous.command == start.command && previous.ordinal == start.ordinal do
        throw "conflicting trace for one exact occurrence"
    starts := starts.insert occurrence start
  for (occurrence, output) in right.finished do
    if let some previous := finished[occurrence]? then
      unless previous == output do throw "conflicting output for one exact occurrence"
    finished := finished.insert occurrence output
  return {left with graph := ← left.graph.merge right.graph, starts, finished}

def reachable (all : Std.HashMap String (Array String)) (root : String) : Std.HashSet String := Id.run do
  let mut seen : Std.HashSet String := {}
  let mut queue := #[root]
  let mut position := 0
  while position < queue.size do
    let current := queue[position]!
    position := position+1
    if seen.contains current then continue
    seen := seen.insert current
    queue := queue ++ all[current]?.getD #[]
  return seen

end Eggshell.Synapses.Extraction
