module

public import Eggshell.NativePublication
public import Eggshell.DaemonWire

@[expose] public section

namespace Eggshell.Plugin.Publication
open Lean DB Synapses

inductive Timing where
  | interval (value : NativePublication.Interval)
  | awaiting
  | unavailable
  deriving ToJson, FromJson

/-- Only original graph inputs and their query-free intervals cross the wire.
`work` is the historical Work being stored, not a retrieval query/cache entry.
No private Journal.Entry, Knowledge, delivery claims or encoder state is sent. -/
structure Capsule where
  session : String
  turn : String
  cwd : String
  work : String
  tools : Array ToolEvent
  finalMessage : Option String
  checkpoint : Bool
  timing : Array Timing
  deriving ToJson, FromJson

def Capsule.ofPrepared (request : NativePublication.Prepared) : Capsule := {
  session := request.pending.sessionId,turn := request.pending.turnId,cwd := request.pending.cwd
  work := request.pending.prompt,tools := request.pending.tools.toArray
  finalMessage := request.pending.finalMessage,checkpoint := request.checkpoint
  timing := request.items.map fun item => match item.evidence with
    | .timed first last _ => .interval ⟨first.clock.domain,first.clock.nanos,last.clock.nanos,last.receivedUnixMs⟩
    | .stored origin _ => .interval ⟨origin.domain,origin.started,origin.finished,origin.receivedUnixMs⟩
    | .observed interval _ => .interval interval
    | .awaiting => .awaiting
    | .unavailable => .unavailable }

def Capsule.pending (capsule : Capsule) (target : System.FilePath) : PendingTurn := {
  sessionId := capsule.session,turnId := capsule.turn,cwd := capsule.cwd,prompt := capsule.work
  profile := "publisher",semanticMatcher := none,read := [],write := some target.toString
  handoffChars := 0,projection := .none,tools := capsule.tools.toList,finalMessage := capsule.finalMessage }

theorem pending_preserves_originals (request : NativePublication.Prepared) (target : System.FilePath) :
    observedRoots ((Capsule.ofPrepared request).pending target) = observedRoots request.pending := by
  simp [Capsule.ofPrepared, Capsule.pending, observedRoots]

def Capsule.prepare (capsule : Capsule) (target : System.FilePath) (identity : String) : Except String NativePublication.Prepared := do
  unless !capsule.session.isEmpty && !capsule.turn.isEmpty && capsule.tools.size == capsule.timing.size do
    throw "invalid native publication capsule"
  unless (capsule.tools.map (·.useId)).toList.Pairwise (· != ·) do
    throw "duplicate native occurrence in publication capsule"
  let pending := capsule.pending target
  let items ← (capsule.tools.zip capsule.timing).mapM fun (tool,timing) => do
    let occurrence : Occurrence := ⟨capsule.session,capsule.turn,tool.useId⟩
    unless occurrence.valid && !tool.name.isEmpty do throw "invalid native tool identity"
    let evidence ← match timing with
      | .interval value =>
          if valid : value.valid = true then pure (.observed value valid)
          else throw "invalid observed native interval"
      | .awaiting => pure .awaiting
      | .unavailable => pure .unavailable
    return ({tool,occurrence,evidence} : NativePublication.Item)
  if matching : NativePublication.matchesPending pending items = true then
    return ⟨pending,target.normalize,some identity,capsule.checkpoint,items,matching⟩
  else throw "native capsule changed its original observations"

structure Project where
  database : String
  capability : String
  deriving ToJson, FromJson

def directory : IO System.FilePath := do
  let root := (← Paths.dataRoot) / "publisher"
  FileSystem.rejectSymlinkAncestors root
  FileSystem.privateDirectory root
  return root

def generation : IO String := do Daemon.executableGeneration (← IO.appPath)

def maxClients : Nat := 128
def maxResidentBytes : Nat := 64*1024*1024
def maxBudgetMs : Nat := 28000

end Eggshell.Plugin.Publication
