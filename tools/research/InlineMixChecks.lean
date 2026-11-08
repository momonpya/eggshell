module
public import Eggshell.Blake3
public import tools.research.ReferenceBlake3
public import Lean.Data.Json.FromToJson
@[expose] public section
namespace Eggshell.Research.InlineMixChecks
open Lean
def check (yes : Bool) (message : String) : IO Unit := unless yes do throw (IO.userError message)
#print axioms Eggshell.Research.RegisterMix.optimized_exact
@[noinline,nospecialize] def before (bytes : ByteArray) : ByteArray := ReferenceBlake3.hash bytes
@[noinline,nospecialize] def after (bytes : ByteArray) : ByteArray := Blake3.hash bytes
@[noinline,nospecialize] def measure (operation : ByteArray → ByteArray) (input : IO.Ref ByteArray) : IO Json := do
  let sink ← IO.mkRef ByteArray.empty
  let allocations ← IO.getNumHeartbeats
  let started ← IO.monoNanosNow
  for _ in [:8] do
    let bytes ← input.get
    sink.set (operation bytes)
  let elapsed := ((← IO.monoNanosNow)-started)/1000
  let delta := (← IO.getNumHeartbeats)-allocations
  return Json.mkObj [("us",toJson elapsed),("heartbeatDeltaNotBytes",toJson delta),
    ("digest",toJson (Blake3.hex (← sink.get)))]
def run (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve mix comparison"
  check (Blake3.hex (Blake3.hash ByteArray.empty) == "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262") "empty BLAKE3 vector failed"
  check (Blake3.hex (Blake3.hash "abc".toUTF8) == "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85") "abc BLAKE3 vector failed"
  let data := ByteArray.mk ((Array.range 262144).map fun n => (n%251).toUInt8)
  let lengths := #[0,1,31,32,63,64,65,127,128,1023,1024,1025,4096,8192,65536,262144]
  for count in lengths do
    let bytes := data.extract 0 count
    check (before bytes == after bytes) "parent/candidate digest changed"
    let parts := [bytes.extract 0 (count/3),ByteArray.empty,bytes.extract (count/3) count]
    check (ReferenceBlake3.hashSegments parts == Blake3.hashSegments parts &&
      Blake3.hashSegments parts == after bytes) "segment boundary changed BLAKE3"
  for size in [:34] do
    let words := (Array.range size).map fun n => (n*9187).toUInt32
    for indices in [#[0,4,8,12,16,17],#[0,0,0,0,0,0],#[33,32,31,30,29,28],#[3,4,9,14,30,31]] do
      let a := indices[0]!
      let b := indices[1]!
      let c := indices[2]!
      let d := indices[3]!
      let mx := indices[4]!
      let my := indices[5]!
      -- Out-of-range Array.get! intentionally panics; test arbitrary aliases
      -- only when every lane exists, keeping the parent's total fallback.
      if indices.all (· < size) then
        check (RegisterMix.optimized words a b c d mx my == ReferenceMix.optimized words a b c d mx my)
          "guard inlining changed an aliased mix"
  let source ← IO.mkRef data
  let mut trials := #[]
  for repetition in [:3] do
    let oldFirst := repetition%2 == 0
    let (old,fresh) ← if oldFirst then do
        let old ← measure before source
        let fresh ← measure after source
        pure (old,fresh)
      else do
        let fresh ← measure after source
        let old ← measure before source
        pure (old,fresh)
    check (old.getObjValD "digest" == fresh.getObjValD "digest") "timed digest changed"
    trials := trials.push (Json.mkObj [("parentFirst",toJson oldFirst),("parent",old),("candidate",fresh)])
  IO.FS.writeFile output (Json.mkObj [("knownVectorsPassed",toJson true),("lengths",toJson lengths),
    ("allDigestsAndSegmentsEqual",toJson true),("aliasedMixesEqual",toJson true),
    ("bytesPerHash",toJson data.size),("hashesPerArm",toJson (8 : Nat)),("trials",toJson trials),
    ("newDeliveryOrCapacityEvidence",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.InlineMixChecks
def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "inline mix OUTPUT")
  Eggshell.Research.InlineMixChecks.run (.mk output)
