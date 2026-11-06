import Eggshell.OperationPool
open Lean Eggshell Eggshell.Plugin
namespace PhaseRetention
@[extern "eggshell_research_thread_id"] opaque threadId : IO Nat
@[extern "eggshell_research_thread_inventory"] opaque inventoryRaw : IO String
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
structure Inventory where
  rssBytes : Nat
  threads : Array Nat
  deriving ToJson
def inventory : IO Inventory := do
  let raw ← inventoryRaw
  let [rss,threads] := raw.splitOn "\n" | throw (IO.userError "invalid OS inventory")
  let some bytes := (rss.drop 9 |>.toString).toNat? | throw (IO.userError "invalid OS RSS")
  let ids ← ((threads.drop 8 |>.toString).splitOn ",").filterMapM fun value => do
    if value.isEmpty then return none
    let some id := value.toNat? | throw (IO.userError "invalid OS thread id")
    return some id
  return ⟨bytes,ids.toArray⟩
def observe : IO Inventory := do
  let deadline := (← IO.monoMsNow)+5000
  repeat
    let value ← try pure (some (← inventory)) catch _ => pure none
    if let some value := value then return value
    check ((← IO.monoMsNow) < deadline) "OS inventory unavailable"
    IO.sleep 2
  throw (IO.userError "unreachable OS inventory wait")
def waitExited (ids : Array Nat) : IO Unit := do
  let deadline := (← IO.monoMsNow)+5000
  repeat
    let current ← observe
    if ids.all (fun id => !current.threads.contains id) then return
    check ((← IO.monoMsNow) < deadline) "producer OS thread remained live"
    IO.sleep 2
  throw (IO.userError "unreachable OS exit wait")
def input : String := (Json.arr ((Array.range 4096).map fun i => Json.mkObj [
  ("path",toJson s!"source/component-{i}/implementation.c"),("line",toJson i),
  ("code",toJson s!"if flag_{i} then record_result({i});")])).compress
@[noinline] def allocate (raw : String) : IO (Array Json) := do
  let mut values := #[]
  for _ in [:2] do values := values.push (← IO.ofExcept (Json.parse raw))
  return values
@[noinline] def produce (raw mode : String) (graph : IO.Ref (Option (Array Json)))
    (producer notices : IO.Ref Nat) : IO Unit := do
  let values ← if mode == "plain" then do
      producer.set (← threadId)
      allocate raw
    else do
      let now ← IO.monoMsNow
      OperationPool.ownedPhase (now+3000) (now+2000) (fun ready => do
        producer.set (← threadId)
        if mode == "ready" then ready
        let values ← allocate raw
        if mode == "ready" then IO.sleep 5
        return values) (fun _ => do notices.modify (·+1))
  graph.set (some values)
@[noinline] def consume (graph : IO.Ref (Option (Array Json))) : IO Unit := do
  let some values ← graph.get | throw (IO.userError "phase result disappeared")
  graph.set none
  let mut count := 0
  for value in values do
    let rows ← IO.ofExcept value.getArr?
    check (rows.size == 4096) "phase row domain changed"
    let some head := rows[0]? | throw (IO.userError "phase head missing")
    let some tail := rows[4095]? | throw (IO.userError "phase tail missing")
    check ((head.getObjValAs? Nat "line").toOption == some 0 &&
      (tail.getObjValAs? Nat "line").toOption == some 4095) "phase endpoints changed"
    count := count+rows.size
  check (count == 8192) "phase result count changed"
structure Actor where
  graph : IO.Ref (Option (Array Json))
  outer : IO.Ref Nat
  producer : IO.Ref Nat
  notices : IO.Ref Nat
  task : Task (Except IO.Error Unit)
@[noinline] def wave (raw mode : String) : IO (Array Nat × Nat) := do
  let registry : IO.Ref (Array Actor) ← IO.mkRef #[]
  let mut ids := #[]
  let mut notices := 0
  try
    for _ in [:8] do
      let graph ← IO.mkRef (none : Option (Array Json))
      let outer ← IO.mkRef 0
      let producer ← IO.mkRef 0
      let count ← IO.mkRef 0
      let task ← IO.asTask (do
        outer.set (← threadId)
        produce raw mode graph producer count) .dedicated
      registry.modify (·.push ⟨graph,outer,producer,count,task⟩)
    for actor in ← registry.get do
      IO.ofExcept (← IO.wait actor.task)
      let outer ← actor.outer.get
      let producer ← actor.producer.get
      check (outer > 0 && producer > 0) "phase producer identity missing"
      ids := ids.push outer |>.push producer
      notices := notices+(← actor.notices.get)
    waitExited ids
    for actor in ← registry.get do consume actor.graph
  finally
    for actor in ← registry.get do discard <| IO.wait actor.task
  return (ids,notices)
def run (root : System.FilePath) (mode : String) : IO Unit := do
  check (!(← root.pathExists) && ["plain","quiet","ready"].contains mode) "fresh phase fixture required"
  IO.FS.createDirAll root
  let warmId ← IO.mkRef 0
  let now ← IO.monoMsNow
  OperationPool.ownedPhase (now+2000) (now+1000) (fun ready => do
    warmId.set (← threadId)
    ready) (fun _ => pure ())
  waitExited #[← warmId.get]
  let raw := input
  check (raw.utf8ByteSize == 446121) "fixed phase input changed"
  let initial ← observe
  let mut timeline := #[]
  let mut notices := 0
  for round in [:4] do
    let (ids,count) ← wave raw mode
    notices := notices+count
    let current ← observe
    check (ids.all (fun id => !current.threads.contains id)) "post-wave phase producer present"
    timeline := timeline.push (Json.mkObj [("round",toJson round),("inventory",toJson current),
      ("producerAndOuterIds",toJson ids),("readyNotifications",toJson count)])
  check (notices == (if mode == "ready" then 32 else 0)) "actual helper readiness path changed"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("mode",toJson mode),("initial",toJson initial),
    ("timeline",toJson timeline),("readyNotifications",toJson notices),
    ("actualSealedCoreHelper",toJson true),("prewarmedIdentically",toJson true),
    ("producerExitVerifiedByOsIdentities",toJson true),("noDbOrModel",toJson true),("adopted",toJson false)]).compress
end PhaseRetention
def main (args : List String) : IO Unit := do
  let [root,mode] := args | throw (IO.userError "OwnedPhaseRetention FRESH_ROOT MODE")
  PhaseRetention.run (.mk root) mode
