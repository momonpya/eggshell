module
public import Eggshell.HashDistinct
public import tools.research.DeliveryKeys
public import Eggshell.Sha256
public import Lean
@[expose] public section
namespace Eggshell.Research.DeliveryKeySetsChecks
open Lean

#print axioms DeliveryKeys.distinct_compiled

def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

/-- Keep the old list implementation independently of the new csimp rule. -/
@[noinline, nospecialize] def parent (keys : List String) : List String := keys.eraseDups
@[noinline, nospecialize] def candidate (keys : List String) : List String := DeliveryKeys.distinct keys

@[noinline, nospecialize] def measure (fn : List String → List String)
    (input : IO.Ref (List String)) (sink : IO.Ref (List String)) : IO (Nat × List String) := do
  let start ← IO.monoMsNow
  let keys ← input.get
  sink.set (fn keys)
  let result ← sink.get
  return ((← IO.monoMsNow)-start,result)

def run (fixture : System.FilePath) (expectedHash : String) (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve previous key-set comparison"
  let bytes ← IO.FS.readBinFile fixture
  check (Sha256.hex bytes == expectedHash) "actual acknowledged-key input changed"
  let value ← IO.ofExcept (Json.parse (String.fromUTF8! bytes))
  let keys ← IO.ofExcept (value.getObjValAs? (List String) "incoming")
  check (keys.length == 6554) "actual acknowledged-key inventory changed"
  let alphabet := ["", "a", "b", "c:source:7", "s:scope:old", "s:scope:new", "日本語"]
  let small := [[]]++alphabet.map (·::[])++alphabet.flatMap (fun a =>
    alphabet.flatMap fun b => alphabet.map fun c => [a,b,c])
  for input in small do
    check (parent input == candidate input) "first occurrence or exact key identity changed"
  let doubled := keys++keys.map ("independent:"++·)
  let cases := [("actual",keys),("repeated",keys++keys),
    ("double-distinct",doubled),("double-repeated",doubled++doubled)]
  let input ← IO.mkRef []
  let sink ← IO.mkRef []
  let mut trials : Array Json := #[]
  for (name,items) in cases do
    input.set items
    for repetition in [:3] do
      let (old,new) ← if repetition == 1 then do
        let new ← measure candidate input sink
        let old ← measure parent input sink
        pure (old,new)
      else do
        let old ← measure parent input sink
        let new ← measure candidate input sink
        pure (old,new)
      check (old.2 == new.2) "ordered delivery keys changed"
      trials := trials.push (Json.mkObj [("case",toJson name),("repetition",toJson repetition),
        ("inputKeys",toJson items.length),("outputKeys",toJson new.2.length),
        ("parentMs",toJson old.1),("candidateMs",toJson new.1),
        ("allOrderedKeysExact",toJson true)])
  IO.FS.writeFile output (Json.mkObj [("fixtureSha256",toJson expectedHash),
    ("smallCases",toJson small.length),("trials",toJson trials),
    ("pairedOrder",toJson "AB,BA,AB"),("componentOnly",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress

end Eggshell.Research.DeliveryKeySetsChecks
