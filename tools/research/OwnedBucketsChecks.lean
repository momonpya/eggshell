import tools.research.OwnedBuckets
import Lean.Data.Json.FromToJson
open Lean Eggshell.Research
namespace OwnedBucketsChecks

structure Span where
  first : Nat
  limit : Nat
  unit : Nat
  deriving BEq

abbrev Rows := List (String × Span)
abbrev Table := Std.HashMap String (Array Span)
def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def rows (count owners : Nat) : Rows :=
  let keys := (Array.range owners).map fun i => "owner-"++toString i
  (Array.range count).map (fun i => (keys[i%owners]!,({first := i*16,limit := i*16+32,unit := i} : Span))) |>.toList

@[noinline,nospecialize] def before (input : Rows) : Table := OwnedBuckets.reference input
@[noinline,nospecialize] def after (input : Rows) : Table := OwnedBuckets.exclusive input

@[noinline,nospecialize] def measure (operation : Rows → Table)
    (input : IO.Ref Rows) : IO (Json × Table) := do
  let heartbeat ← IO.getNumHeartbeats
  let started ← IO.monoNanosNow
  let source ← input.get
  let result := operation source
  let sink ← IO.mkRef result
  let finished ← IO.monoNanosNow
  return (Json.mkObj [("nanos",toJson (finished-started)),
    ("heartbeatDeltaNotBytes",toJson ((← IO.getNumHeartbeats)-heartbeat))],← sink.get)

def validate : IO Nat := do
  let mut count := 0
  let source := rows 32 4
  for size in [:33] do
    let chosenRows := source.take size
    let previous : Table := (before (rows 7 2)).insert "empty" #[]
    let frozen ← IO.mkRef previous
    let oldLayout := previous.toArray
    let current := OwnedBuckets.exclusive chosenRows previous
    let reference := OwnedBuckets.reference chosenRows previous
    check (current.toArray == reference.toArray) "native bucket order/content changed"
    check ((← frozen.get).toArray == oldLayout) "retained initial table was mutated"
    for key in ["owner-0","owner-1","owner-2","owner-3","empty","missing"] do
      check (current[key]? == reference[key]?) "bucket,empty or absent-key behavior changed"
      count := count+1
  return count

def run (output : String) : IO Unit := do
  let root : System.FilePath := .mk output
  check (!(← root.pathExists)) "fresh native component output required"
  IO.FS.createDirAll root
  let controls ← validate
  let mut results := #[]
  for size in [1024,4096,8192] do
    for owners in [1,46] do
      let input ← IO.mkRef (rows size owners)
      let mut pairs := #[]
      for repetition in [:3] do
        -- The input is retained and shared with an owned dedicated actor.
        -- This is not a private, uniquely-owned-input timing claim.
        let task ← IO.asTask (do
          let (a,b) ← if repetition%2 == 0 then do
            let a ← measure before input
            let b ← measure after input
            pure (a,b)
          else do
            let b ← measure after input
            let a ← measure before input
            pure (a,b)
          check (a.2.toArray == b.2.toArray) "timed bucket table differs"
          check (a.2.size == owners) "timed output did not materialize every bucket"
          pure (Json.mkObj [("referenceFirst",toJson (repetition%2 == 0)),("reference",a.1),("exclusive",b.1)])) .dedicated
        pairs := pairs.push (← IO.ofExcept (← IO.wait task))
      results := results.push (Json.mkObj [("rows",toJson size),("owners",toJson owners),("pairs",toJson pairs)])
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("controls",toJson controls),
    ("measurements",toJson results),("inputReadAfterClock",toJson true),
    ("retainedInputSharedWithDedicatedActor",toJson true),("wholeHookReplay",toJson false),
    ("internalTableLayoutEqualityProved",toJson false),("nativeLayoutChecksPassed",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end OwnedBucketsChecks
def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "owned-buckets OUTPUT")
  OwnedBucketsChecks.run output
