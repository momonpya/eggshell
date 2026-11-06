import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.AllocatorProfile
@[extern "eggshell_research_allocator_snapshot"] opaque snapshotRaw (detailed : Bool) : IO String
@[extern "eggshell_research_allocator_collect"] opaque collect (force : Bool) : IO Unit
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def snapshot (detailed : Bool := true) : IO Json := do
  let text ← snapshotRaw detailed
  let sections := text.splitOn "--\n"
  let fields ← ((sections.headD "").splitOn "\n").filterMapM fun line => do
    if line.isEmpty then return none
    let [key,value] := line.splitOn "=" | throw (IO.userError "invalid allocator diagnostic field")
    let some number := value.toNat? | throw (IO.userError "invalid allocator diagnostic number")
    return some (key,toJson number)
  let result := Json.mkObj fields
  check (result.getObjValD "version" == toJson (223 : Nat) &&
    result.getObjValD "visited" == toJson (1 : Nat)) "unexpected allocator or owner traversal"
  return result.setObjVal! "rawStats" (toJson (String.intercalate "--\n" (sections.drop 1)))

def input : String := (Json.arr ((Array.range 4096).map fun i => Json.mkObj [
  ("path",toJson s!"source/component-{i}/implementation.c"),("line",toJson i),
  ("code",toJson s!"if flag_{i} then record_result({i});")])).compress

/-- Return only a small parsed string plus an immediate checksum. All other
parse results are released when this non-inlined scope returns. -/
@[noinline] def allocate (raw : String) : IO (Nat × String) := do
  let mut values := #[]
  for _ in [:2] do values := values.push (← IO.ofExcept (Json.parse raw))
  let mut checksum := 0
  for value in values do
    checksum := checksum+(← IO.ofExcept value.getArr?).size
  let some value := values[0]? | throw (IO.userError "allocation input absent")
  let rows ← IO.ofExcept value.getArr?
  let some row := rows[0]? | throw (IO.userError "allocation row absent")
  return (checksum,← IO.ofExcept (row.getObjValAs? String "code"))

@[noinline] def churn (raw : String) (retained : IO.Ref String) (keep : Bool) : IO Nat := do
  let (checksum,tiny) ← allocate raw
  if keep then retained.set tiny
  return checksum

/-- Reports are written and dropped on their producer; returning their strings
to the coordinator would itself retain a block in each producer's segment. -/
@[noinline] def reportActor (path : System.FilePath) : IO Unit := do
  IO.FS.writeFile path (← snapshot false).compress

structure Actor where
  ready : IO.Promise Nat
  task : Task (Except IO.Error Unit)

def osRss : IO Nat := do
  let pid ← IO.Process.getPID
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","rss="]}
  check (result.exitCode == 0) "RSS observation failed"
  let some rss := result.stdout.trimAscii.toString.toNat? | throw (IO.userError "invalid RSS observation")
  return rss

def stamp (root : System.FilePath) (name : String) : IO Unit := do
  let data ← snapshot
  IO.FS.writeFile (root/(name++".json")) (data.setObjVal! "osRssKiB" (toJson (← osRss))).compress

/-- No worker result or task handle escapes this wave. Retention cells have
one writer each; the coordinator only observes them after task termination. -/
@[noinline] def wave (root : System.FilePath) (round : Nat) (raw : String)
    (cells : Array (IO.Ref String)) (keep ownerCollect : Bool) : IO Unit := do
  let release : IO.Promise Unit ← IO.Promise.new
  let mut actors : Array Actor := #[]
  try
    for index in [:cells.size] do
      let some cell := cells[index]? | throw (IO.userError "allocator actor has no retention cell")
      let ready : IO.Promise Nat ← IO.Promise.new
      let path := root/s!"wave-{round}-actor-{index}.json"
      let task ← IO.asTask (do
        let checksum ← churn raw cell keep
        if ownerCollect then collect true
        reportActor path
        ready.resolve checksum
        discard <| IO.wait release.result!) .dedicated
      actors := actors.push ⟨ready,task⟩
    let deadline := (← IO.monoMsNow)+60000
    for actor in actors do
      repeat
        if ← actor.ready.isResolved then break
        if ← IO.hasFinished actor.task then
          IO.ofExcept (← IO.wait actor.task)
          throw (IO.userError "actor ended before readiness")
        check ((← IO.monoMsNow) < deadline) "allocator wave exceeded its observation bound"
        IO.sleep 1
      let some checksum := actor.ready.result?.get | throw (IO.userError "allocator actor dropped readiness")
      check (checksum == 8192) "allocator workload checksum changed"
    stamp root s!"wave-{round}-held"
  finally
    release.resolve ()
    for actor in actors do IO.ofExcept (← IO.wait actor.task)

def run (root : System.FilePath) (mode : String) : IO Unit := do
  check (!(← root.pathExists)) "fresh allocator fixture required"
  check (["drop","drop-collect","keep","keep-collect"].contains mode) "unknown allocator fixture mode"
  IO.FS.createDirAll root
  let raw := input
  let keep := mode.startsWith "keep"
  let ownerCollect := mode.endsWith "collect"
  stamp root "initial"
  let mut retained : Array (IO.Ref String) := #[]
  for round in [:4] do
    let cells ← (Array.range 8).mapM fun _ => IO.mkRef ""
    wave root round raw cells keep ownerCollect
    if keep then retained := retained++cells
    stamp root s!"wave-{round}-joined"
    collect true
    stamp root s!"wave-{round}-main-collected"
  let retainedCount ← retained.foldlM (fun n cell => do return n+(if (← cell.get).isEmpty then 0 else 1)) 0
  check (retainedCount == (if keep then 32 else 0)) "retention condition changed"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("mode",toJson mode),
    ("actorsPerWave",toJson (8 : Nat)),("waves",toJson (4 : Nat)),
    ("inputUtf8Bytes",toJson raw.utf8ByteSize),("retainedTinyStrings",toJson retainedCount),
    ("actorReportsWrittenAndDroppedOnOwner",toJson true),("tasksDoNotEscapeWave",toJson true),
    ("sameInstalledAllocator",toJson true),("noDbOrModel",toJson true),("adopted",toJson false)]).compress
end Eggshell.Research.AllocatorProfile
def main (args : List String) : IO Unit := do
  let [path,mode] := args | throw (IO.userError "AllocatorProfile FRESH_ROOT MODE")
  Eggshell.Research.AllocatorProfile.run (.mk path) mode
