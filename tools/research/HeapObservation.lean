module
public import Lean.Data.Json.FromToJson
public import Std.Internal.UV.Timer
public import Eggshell.TaskDeadline
public import Std.Sync.Channel
@[expose] public section
namespace Eggshell.Research.HeapObservation
open Lean
@[extern "eggshell_research_heap_observe_init"] opaque initializeObserver : IO Unit
@[extern "eggshell_research_heap_owner"] opaque ownerRaw : IO String
@[extern "eggshell_research_heap_arenas"] opaque arenasRaw : IO String
@[extern "eggshell_research_heap_thread_id"] opaque threadId : IO Nat
@[extern "eggshell_research_heap_thread_alive"] opaque threadAlive (identity : @& Nat) : IO Bool

def owner : IO Json := do
  let raw ← ownerRaw
  let fields ← (raw.splitOn "\n").filterMapM fun line => do
    if line.isEmpty then return none
    let [key,value] := line.splitOn "=" | throw (IO.userError "invalid owner heap observation")
    let some value := value.toNat? | throw (IO.userError "invalid owner heap counter")
    return some (key,toJson value)
  let value := Json.mkObj fields
  unless value.getObjValD "version" == toJson (223 : Nat) do throw (IO.userError "owner heap ABI changed")
  return value.setObjVal! "mayIncludePendingRemoteFree" (toJson true)

/-- The synchronous continuation observes the thread resolving an unresolved
native timer. Reject completion before registration rather than observing a
fresh worker or the registering caller by accident. -/
def onNativeTimer (action : IO α) : IO (Nat × α) := do
  let caller ← threadId
  let timer ← Std.Internal.UV.Timer.mk 20 false
  let pending ← timer.next
  try
    unless !(← pending.isResolved) do throw (IO.userError "diagnostic timer completed before registration")
    let task ← IO.mapTask (t := pending.result!) (sync := true) fun _ => do
      let resolving ← threadId
      unless resolving != caller do throw (IO.userError "diagnostic continuation ran on its registering thread")
      return (resolving,← action)
    TaskDeadline.wait task ((← IO.monoMsNow)+2000)
  finally timer.stop

def ioSnapshot : IO Json := do
  let (thread,heap) ← onNativeTimer owner
  return Json.mkObj [("thread",toJson thread),("heap",heap)]

def workerSnapshot : IO Json := do
  let caller ← threadId
  let task ← IO.asTask (do
    let identity ← threadId
    return Json.mkObj [("thread",toJson identity),("caller",toJson caller),("heap",← owner)])
  TaskDeadline.wait task ((← IO.monoMsNow)+2000)

/-- Explicitly owned diagnostic mailbox. Only the main service loop answers it,
so a stats handler never traverses another live thread's allocator heap. -/
abbrev Probe := Std.CloseableChannel (IO.Promise (Except IO.Error Json))
def Probe.new : IO Probe := Std.CloseableChannel.new (some 1)
def Probe.request (probe : Probe) : IO Json := do
  let reply ← IO.Promise.new
  unless ← probe.trySend reply do throw (IO.userError "owner diagnostic mailbox is full or closed")
  TaskDeadline.wait reply.result! ((← IO.monoMsNow)+2000)
def Probe.respond (probe : Probe) : IO Unit := do
  if let some reply ← probe.tryRecv then
    let result ← try
      let identity ← threadId
      pure (.ok (Json.mkObj [("thread",toJson identity),("heap",← owner)]))
      catch error => pure (.error error)
    reply.resolve result
def Probe.stop (probe : Probe) : IO Unit := do
  try probe.close catch _ => pure ()
  repeat
    let some reply ← probe.tryRecv | break
    reply.resolve (.error (IO.userError "owner diagnostic stopped"))
end Eggshell.Research.HeapObservation
