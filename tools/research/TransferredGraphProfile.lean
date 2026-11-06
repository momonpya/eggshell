import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.TransferredGraph
@[extern "eggshell_research_thread_id"] opaque threadId : IO Nat
@[extern "eggshell_research_thread_inventory"] opaque inventoryRaw : IO String
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
structure Inventory where
  rssBytes : Nat
  threads : Array Nat
  deriving ToJson
def inventory : IO Inventory := do
  let raw ← inventoryRaw
  let [rss,threads] := raw.splitOn "\n" | throw (IO.userError "invalid thread inventory shape")
  let some bytes := (rss.drop 9 |>.toString).toNat? | throw (IO.userError "invalid resident byte count")
  let ids ← ((threads.drop 8 |>.toString).splitOn ",").filterMapM fun value => do
    if value.isEmpty then return none
    let some id := value.toNat? | throw (IO.userError "invalid thread identity")
    return some id
  return ⟨bytes,ids.toArray⟩
def observe : IO Inventory := do
  let deadline := (← IO.monoMsNow)+5000
  repeat
    let result ← try pure (some (← inventory)) catch _ => pure none
    if let some value := result then return value
    check ((← IO.monoMsNow) < deadline) "thread inventory remained unavailable"
    IO.sleep 2
  throw (IO.userError "unreachable inventory retry")
def waitExited (ids : Array Nat) : IO Unit := do
  let deadline := (← IO.monoMsNow)+5000
  repeat
    let current ← observe
    if ids.all (fun id => !current.threads.contains id) then return
    check ((← IO.monoMsNow) < deadline) "completed producer thread still present"
    IO.sleep 2
  throw (IO.userError "unreachable producer exit wait")
def input : String := (Json.arr ((Array.range 4096).map fun i => Json.mkObj [
  ("path",toJson s!"source/component-{i}/implementation.c"),("line",toJson i),
  ("code",toJson s!"if flag_{i} then record_result({i});")])).compress
def expected (raw : String) : String := "["++raw++","++raw++"]"
@[noinline] def allocate (raw : String) : IO (Array Json) := do
  let mut values := #[]
  for _ in [:2] do values := values.push (← IO.ofExcept (Json.parse raw))
  return values
def checksum (values : Array Json) : Except String Nat := do
  let mut total := 0
  for value in values do
    let rows ← value.getArr?
    unless rows.size == 4096 do throw "transferred row domain changed"
    let some first := rows[0]? | throw "transferred first row absent"
    let some last := rows[4095]? | throw "transferred final row absent"
    unless (← first.getObjValAs? Nat "line") == 0 && (← last.getObjValAs? Nat "line") == 4095 do
      throw "transferred endpoints changed"
    total := total+rows.size
  return total
@[noinline] def localWork (raw : String) : IO Unit := do
  check ((← IO.ofExcept (checksum (← allocate raw))) == 8192) "owner workload changed"
@[noinline] def publishGraph (raw : String) (cell : IO.Ref (Option (Array Json))) : IO Unit := do
  cell.set (some (← allocate raw))
@[noinline] def publishWire (raw : String) (cell : IO.Ref (Option String)) : IO Unit := do
  let values ← allocate raw
  cell.set (some (Json.arr values).compress)
@[noinline] def consumeGraph (cell : IO.Ref (Option (Array Json))) : IO Unit := do
  let some values ← cell.get | throw (IO.userError "transferred graph absent")
  cell.set none
  check ((← IO.ofExcept (checksum values)) == 8192) "consumer workload changed"
@[noinline] def consumeWire (expectedWire : String) (cell : IO.Ref (Option String)) : IO Unit := do
  let some bytes ← cell.get | throw (IO.userError "transferred wire absent")
  cell.set none
  check (bytes == expectedWire) "producer encoding changed actual bytes"
  let parsed ← IO.ofExcept (Json.parse bytes >>= Json.getArr?)
  check ((← IO.ofExcept (checksum parsed)) == 8192) "encoded consumer workload changed"
structure Actor where
  graph : IO.Ref (Option (Array Json))
  wire : IO.Ref (Option String)
  ready : IO.Promise Nat
  task : Task (Except IO.Error Unit)
@[noinline] def wave (raw expectedWire mode : String) : IO (Array Nat) := do
  let release : IO.Promise Unit ← IO.Promise.new
  let actors : IO.Ref (Array Actor) ← IO.mkRef #[]
  let mut ids := #[]
  try
    for _ in [:8] do
      let graph ← IO.mkRef (none : Option (Array Json))
      let wire ← IO.mkRef (none : Option String)
      let ready : IO.Promise Nat ← IO.Promise.new
      let task ← IO.asTask (do
        let id ← threadId
        if mode == "owner" then localWork raw
        else if mode == "encoded" then publishWire raw wire
        else publishGraph raw graph
        ready.resolve id
        if mode == "alive" then discard <| IO.wait release.result!) .dedicated
      actors.modify (·.push ⟨graph,wire,ready,task⟩)
    let deadline := (← IO.monoMsNow)+60000
    for actor in ← actors.get do
      repeat
        if ← actor.ready.isResolved then break
        if ← IO.hasFinished actor.task then
          IO.ofExcept (← IO.wait actor.task)
          throw (IO.userError "producer stopped before readiness")
        check ((← IO.monoMsNow) < deadline) "producer readiness expired"
        IO.sleep 1
      let some id := actor.ready.result?.get | throw (IO.userError "producer lost identity")
      ids := ids.push id
    if mode == "alive" then
      let current ← observe
      check (ids.all current.threads.contains) "producer exited before consumer release"
      for actor in ← actors.get do check (!(← IO.hasFinished actor.task)) "alive producer already completed"
    else
      for actor in ← actors.get do IO.ofExcept (← IO.wait actor.task)
      waitExited ids
    for actor in ← actors.get do
      if mode == "encoded" then consumeWire expectedWire actor.wire
      else if mode != "owner" then consumeGraph actor.graph
  finally
    release.resolve ()
    for actor in ← actors.get do IO.ofExcept (← IO.wait actor.task)
  waitExited ids
  return ids
def run (root : System.FilePath) (mode : String) : IO Unit := do
  check (!(← root.pathExists) && ["owner","alive","exited","encoded"].contains mode) "fresh transfer fixture and known mode required"
  IO.FS.createDirAll root
  let raw := input
  let expectedWire := expected raw
  let self ← threadId
  let initial ← observe
  check (initial.threads.contains self && raw.utf8ByteSize == 446121) "native thread identity or fixed input changed"
  let mut timeline := #[]
  for round in [:4] do
    let ids ← wave raw expectedWire mode
    let current ← observe
    check (ids.all (fun id => !current.threads.contains id)) "post-wave producer still live"
    timeline := timeline.push (Json.mkObj [("round",toJson round),("inventory",toJson current),("producerIds",toJson ids)])
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("mode",toJson mode),("initial",toJson initial),
    ("timeline",toJson timeline),("sameInputUtf8Bytes",toJson raw.utf8ByteSize),
    ("actorsPerWave",toJson (8 : Nat)),("waves",toJson (4 : Nat)),
    ("producerExitVerifiedByOsIdentities",toJson true),("actorAndResultHandlesDoNotEscapeWave",toJson true),
    ("noAllocatorCollectionOrGlobalCounters",toJson true),("noDbOrModel",toJson true),("adopted",toJson false)]).compress
end Eggshell.Research.TransferredGraph
def main (args : List String) : IO Unit := do
  let [root,mode] := args | throw (IO.userError "TransferredGraphProfile FRESH_ROOT MODE")
  Eggshell.Research.TransferredGraph.run (.mk root) mode
