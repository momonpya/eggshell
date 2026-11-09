import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
import Std.Data.HashSet
open Lean
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout

structure Proc where
  pid : Nat
  parent : Nat
  rssKiB : Nat
  identity : String
  program : String
  deriving ToJson

def words (value : String) : Array String := ((value.splitOn " ").filter (! ·.isEmpty)).toArray
def processes : IO (Std.HashMap Nat Proc) := do
  let raw ← command "/bin/ps" #["-axww","-o","pid=,ppid=,rss=,lstart=,comm="]
  return (raw.splitOn "\n").foldl (fun found line =>
    let parts := words line
    if parts.size < 9 then found else
    match parts[0]!.toNat?,parts[1]!.toNat?,parts[2]!.toNat? with
    | some pid,some parent,some rss => found.insert pid
        ⟨pid,parent,rss," ".intercalate (parts.extract 3 8).toList," ".intercalate (parts.extract 8 parts.size).toList⟩
    | _,_,_ => found) {}

def descendant (table : Std.HashMap Nat Proc) (root pid : Nat) : Bool := Id.run do
  let mut current := pid
  let mut seen : Std.HashSet Nat := {}
  while !seen.contains current do
    if current == root then return true
    seen := seen.insert current
    let some row := table[current]? | return false
    current := row.parent
  return false

def main (args : List String) : IO UInt32 := do
  let [harness,inputPath,samplePath] := args | throw (IO.userError "INPUT SAMPLES required")
  let samples : System.FilePath := .mk samplePath
  check (!(← samples.pathExists)) "fresh observation file required"
  let child ← IO.Process.spawn {
    cmd := harness
    args := #["capacity",inputPath]
    stdin := .null
    stdout := .inherit
    stderr := .inherit }
  let done ← IO.mkRef false
  let waiter ← IO.asTask (try child.wait finally done.set true) .dedicated
  let output ← IO.FS.Handle.mk samples .write
  let scratch := samples.withExtension "current.json"
  let observer := (← IO.Process.getPID).toNat
  let endBy := (← IO.monoMsNow)+300000
  try
    while !(← done.get) do
      let started ← IO.monoMsNow
      check (started < endBy) "observation lifetime exceeded"
      let row ← try
        let before ← processes
        let selected := before.toArray.map Prod.snd |>.filter (fun row => descendant before child.pid.toNat row.pid)
        if selected.isEmpty then
          pure (Json.mkObj [("fromMs",toJson started),("noLiveNativeProcesses",toJson true)])
        else
        let result ← IO.Process.output {cmd := "/usr/bin/footprint",args :=
          #["--noCategories","--swapped","-f","bytes","-j",scratch.toString] ++ selected.map (toString ∘ Proc.pid)}
        let footprint ← if ← scratch.pathExists then read scratch else pure Json.null
        if ← scratch.pathExists then IO.FS.removeFile scratch
        let after ← processes
        let rows := selected.map fun row => Json.mkObj [("before",toJson row),
          ("sameIdentityAfter",toJson ((after[row.pid]?).any (·.identity == row.identity))),
          ("afterRssKiB",toJson ((after[row.pid]?).map (·.rssKiB)))]
        pure (Json.mkObj [("fromMs",toJson started),("toMs",toJson (← IO.monoMsNow)),
          ("rootPid",toJson child.pid.toNat),("rows",toJson rows),("osFootprint",footprint),
          ("footprintExit",toJson result.exitCode.toNat),("footprintStderr",toJson result.stderr),
          ("observerRssKiB",toJson ((before[observer]?).map (·.rssKiB)))])
      catch error => pure (Json.mkObj [("fromMs",toJson started),("error",toJson error.toString)])
      output.putStrLn row.compress
      output.flush
      if !(← done.get) then IO.sleep 1000
    return ← IO.ofExcept (← IO.wait waiter)
  finally
    if !(← done.get) then
      child.kill
      discard <| IO.wait waiter
