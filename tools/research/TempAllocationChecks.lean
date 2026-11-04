import Eggshell.FileSystem

open Lean Eggshell
namespace Eggshell.Research.TempAllocationChecks

/-- The same existing native allocator used by FileSystem publication. No
new native implementation or replacement backend is introduced. -/
opaque Handle : Type
@[extern "eggshell_publication_open"] opaque openHandle
  (path temporary : @& String) : IO Handle
@[extern "eggshell_publication_close"] opaque closeHandle (handle : @& Handle) : IO Unit

def client (root : System.FilePath) (clockBased : Bool) (count : Nat) : IO (Nat × Array String) := do
  let mut accepted := 0
  let mut errors := #[]
  for _ in [:count] do
    let suffix ← if clockBased then pure s!"{← IO.Process.getPID}-{← IO.monoNanosNow}"
      else FileSystem.freshSuffix
    let temporary := FileSystem.publicationTemporary .replace suffix
    try
      let handle ← openHandle (root/"unused-target").toString temporary
      closeHandle handle
      accepted := accepted+1
    catch error => errors := errors.push error.toString
  return (accepted,errors)

def wave (root : System.FilePath) (clockBased : Bool) : IO Json := do
  let tasks ← (List.range 80).toArray.mapM fun _ => IO.asTask (client root clockBased 64) .dedicated
  let mut accepted := 0
  let mut errors : Array String := #[]
  for task in tasks do
    let result ← IO.ofExcept (← IO.wait task)
    accepted := accepted+result.1
    errors := errors++result.2
  unless accepted+errors.size == 5120 && errors.all (· == "File exists") do
    throw (IO.userError s!"unexpected allocator result: {errors}")
  unless clockBased || errors.isEmpty do throw (IO.userError "fresh allocation collided")
  unless !(← (root/"unused-target").pathExists) && (← root.readDir).isEmpty do
    throw (IO.userError "allocation-only probe published an object or left temporary files")
  return Json.mkObj [("clockBased",toJson clockBased),("calls",toJson (5120 : Nat)),
    ("accepted",toJson accepted),("exclusiveCreateCollisions",toJson errors.size)]

end Eggshell.Research.TempAllocationChecks

def main (args : List String) : IO UInt32 := do
  let [directory] := args | throw (IO.userError "fresh probe root required")
  let root : System.FilePath := .mk directory
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "fresh probe root required")
  FileSystem.privateDirectory root
  let mut rows := #[]
  for _ in [:3] do
    rows := rows.push (← Eggshell.Research.TempAllocationChecks.wave root true)
    rows := rows.push (← Eggshell.Research.TempAllocationChecks.wave root false)
  IO.FS.writeFile (root/"allocation-ablation.json") ((toJson rows).pretty++"\n")
  IO.println (toJson rows).compress
  return 0
