import Eggshell.Blake3
import Lean.Data.Json.FromToJson
open Lean Eggshell

namespace Eggshell.Research.BlockSeekChecks

/-- Independent block oracle keeps the original scalar word reader and is not
the declaration rewritten by the candidate's compiler simplification. -/
def originalBlock (source : Blake3.Source) (offset : Nat) : Array UInt32 :=
  (Array.range 16).map fun index => Blake3.wordAt source (offset+index*4)

def fields (count width salt : Nat) : List ByteArray :=
  (List.range count).map fun index => ByteArray.mk
    ((Array.range (if index%7 == 0 then 0 else width+index%13)).map fun byte =>
      (byte*31+index*17+salt).toUInt8)

def run (salt : Nat) : IO Unit := do
  let mut checks := 0
  for (count,width) in [(0,0),(1,0),(2,1),(8,3),(17,31),(33,63),(65,127)] do
    let pieces := fields count width salt
    let size := (Blake3.Source.ofSegments pieces).size
    for declared in [0,size/2,size,size+17] do
      let source : Blake3.Source := {segments := pieces,size := declared}
      for offset in [0,1,3,15,31,63,64,65,size/2,size,size+1] do
        unless Blake3.blockWords source offset == originalBlock source offset do
          throw (IO.userError "prepared native block disagrees with the independent scalar block")
        checks := checks+1
  let mut measurements := #[]
  for (count,width) in [(1,262144),(16,16384),(64,4096),(256,1024)] do
    let pieces := fields count width salt
    let size := (Blake3.Source.ofSegments pieces).size
    let mut hashes := #[]
    let started ← IO.monoMsNow
    for repetition in [:4] do
      let framing := Blake3.u64le (salt+repetition)
      hashes := hashes.push (Blake3.hex (Blake3.hashSegments (framing::pieces)))
    let elapsed := (← IO.monoMsNow)-started
    measurements := measurements.push (Json.mkObj [("fields",toJson count),("bytes",toJson size),
      ("repetitions",toJson (4 : Nat)),("elapsedMs",toJson elapsed),("hashes",toJson hashes)])
  IO.println (Json.mkObj [("salt",toJson salt),("scalarBlockChecks",toJson checks),
    ("measurements",toJson measurements)]).compress
end Eggshell.Research.BlockSeekChecks

def main : List String → IO Unit
  | [salt] => do
    let some value := salt.toNat? | throw (IO.userError "numeric diagnostic salt required")
    Eggshell.Research.BlockSeekChecks.run value
  | _ => throw (IO.userError "BlockSeekChecks SALT")
