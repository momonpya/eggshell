import Eggshell.Blake3
import tools.research.RegisterRoundsDigest
import Lean.Data.Json.FromToJson
open Lean Eggshell
namespace RegisterRoundsChecks
def check (yes : Bool) (message : String) : IO Unit := unless yes do throw (IO.userError message)

theorem reference_is_actual : @Research.RegisterRounds.referenceSeven = @Blake3.sevenRounds := by
  have lane : @Research.RegisterMix.reference = @Blake3.g := by
    rw [Blake3.register_mix_compiled]
    funext state a b c d mx my
    exact (Research.RegisterMix.optimized_exact state a b c d mx my).symm
  have one : @Research.RegisterRounds.referenceRound = @Blake3.round := by
    funext state message
    simp only [Research.RegisterRounds.referenceRound,Research.RegisterRounds.referenceRoundState,Blake3.round,lane]
  have shuffle : @Research.RegisterRounds.referencePermute = @Blake3.permute := by rfl
  funext state message
  simp only [Research.RegisterRounds.referenceSeven,Blake3.sevenRounds,one,shuffle]

theorem optimized_is_actual (state message : Array UInt32) :
    Research.RegisterRounds.optimized state message = Blake3.sevenRounds state message := by
  rw [Research.RegisterRounds.optimized_exact,reference_is_actual]

@[noinline,nospecialize] def before (bytes : ByteArray) : ByteArray := Blake3.hash bytes
@[noinline,nospecialize] def after (bytes : ByteArray) : ByteArray := Research.RegisterRoundsDigest.hash bytes

@[noinline,nospecialize] def measure (operation : ByteArray → ByteArray)
    (input : IO.Ref ByteArray) (count : Nat) : IO Json := do
  let sink ← IO.mkRef ByteArray.empty
  let allocated ← IO.getNumHeartbeats
  let started ← IO.monoNanosNow
  for _ in [:count] do
    let bytes ← input.get
    sink.set (operation bytes)
  let elapsed := (← IO.monoNanosNow)-started
  return Json.mkObj [("nanos",toJson elapsed),("digest",toJson (Blake3.hex (← sink.get))),
    ("heartbeatDeltaNotBytes",toJson ((← IO.getNumHeartbeats)-allocated))]

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh register-rounds output required"
  IO.FS.createDirAll root
  let data := ByteArray.mk ((Array.range 262144).map fun n => (n%251).toUInt8)
  check (Blake3.hex (after ByteArray.empty) == "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262") "empty vector changed"
  check (Blake3.hex (after "abc".toUTF8) == "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85") "abc vector changed"
  let lengths := #[0,1,31,32,63,64,65,127,128,1023,1024,1025,4095,4096,4097,8192,65536,262144]
  for count in lengths do
    let bytes := data.extract 0 count
    check (before bytes == after bytes) "digest differs from actual product"
    for boundary in [0,count/3,count/2,count] do
      let parts := [bytes.extract 0 boundary,ByteArray.empty,bytes.extract boundary count]
      check (Blake3.hashSegments parts == Research.RegisterRoundsDigest.hashSegments parts &&
        Research.RegisterRoundsDigest.hashSegments parts == after bytes) "segmentation changed digest"
    let fields := [bytes.extract 0 (count/3),bytes.extract (count/3) count]
    check (Blake3.digest "native.page-map".toUTF8 fields ==
      Research.RegisterRoundsDigest.digest "native.page-map".toUTF8 fields) "framed fields changed digest"
  let mut laneCases := 0
  for size in [0,1,8,15,16,17,31,32,33] do
    for messageSize in [16,17,31,32,33] do
      if size+messageSize < 32 then continue
      for pattern in [:4] do
        let word := fun i => (if pattern == 0 then 0 else if pattern == 1 then 4294967295
          else if pattern == 2 then i*9187 else i*316487+(i%3)*217179).toUInt32
        let state := (Array.range size).map word
        let message := (Array.range messageSize).map (fun i => word (i+size))
        check (Research.RegisterRounds.optimized state message == Blake3.sevenRounds state message)
          "seven-round state or safe malformed-length behavior changed"
        laneCases := laneCases+1
  let mut results := #[]
  for (bytes,count) in [(4096,128),(262144,8)] do
    let input ← IO.mkRef (data.extract 0 bytes)
    let mut pairs := #[]
    for round in [:3] do
      let oldFirst := round%2 == 0
      let (old,fresh) ← if oldFirst then do
        let old ← measure before input count
        let fresh ← measure after input count
        pure (old,fresh)
      else do
        let fresh ← measure after input count
        let old ← measure before input count
        pure (old,fresh)
      check (old.getObjValD "digest" == fresh.getObjValD "digest") "timed digest changed"
      pairs := pairs.push (Json.mkObj [("parentFirst",toJson oldFirst),("parent",old),("candidate",fresh)])
    results := results.push (Json.mkObj [("bytes",toJson bytes),("hashesPerArm",toJson count),("pairs",toJson pairs)])
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("knownVectors",toJson true),("lengths",toJson lengths),
    ("allDigestSegmentsAndFramedFieldsEqual",toJson true),("safeLaneCases",toJson laneCases),
    ("timedInputReadAfterClock",toJson true),("measurements",toJson results),
    ("componentOnly",toJson true),("wholeHookBenefitEstablished",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress

#print axioms reference_is_actual
#print axioms optimized_is_actual
end RegisterRoundsChecks
def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "register-rounds OUTPUT")
  RegisterRoundsChecks.run (.mk output)
