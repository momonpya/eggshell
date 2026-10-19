module

public import Eggshell.FileSystem
public import Eggshell.Paths
public import Eggshell.Blake3
public import Eggshell.Sha256

@[expose] public section

namespace Eggshell.Receipt
open Lean

def validId (id : String) : Bool :=
  id.length == 64 && id.toList.all (fun c =>
    ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))

def fresh : IO String := do pure (Blake3.hex (← IO.getRandomBytes 32))

/-- Every writer publishes its own stage atomically. No shared append lock,
    graph write, session lifetime or provider command identifies a receipt. -/
def write (id stage : String) (data : Json) : IO Unit := do
  unless validId id && !stage.isEmpty && stage.length ≤ 96 &&
      stage.toList.all (fun c => c.isAlphanum || c == '-' || c == '_') do
    throw (IO.userError "invalid hook receipt identity or stage")
  let directory := (← Paths.dataRoot) / "receipts" / id
  FileSystem.rejectSymlinkAncestors directory
  FileSystem.privateDirectory directory
  let record := Json.mkObj [("receipt", toJson id), ("stage", toJson stage),
    ("pid", toJson (← IO.Process.getPID).toNat), ("observedMs", toJson (← IO.monoMsNow)), ("data", data)]
  let bytes := record.compress.toUTF8
  unless bytes.size ≤ 8 * 1024 * 1024 do
    throw (IO.userError "hook receipt exceeds the native frame bound")
  FileSystem.atomicExistingBytes (directory / (stage ++ ".json")) bytes

/-- Diagnostics cannot grant authority or turn a storage error into a miss. -/
def observe (id : Option String) (stage : String) (data : Json) : IO Unit := do
  let some id := id | return
  try write id stage data
  catch error => IO.eprintln s!"Eggshell could not record {stage}: {error}"

end Eggshell.Receipt
