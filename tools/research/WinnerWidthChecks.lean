import tools.research.WinnerWidth
import tools.SelectionRating
import tools.research.PreparedRoutingObserver
open Lean StableWinnerIndex

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def save (root : System.FilePath) (name : String) (value : Json) : IO Unit :=
  IO.FS.writeFile (root/name) value.compress

def keys (count : Nat) (scale : Nat) : Array (Option (SharedCoverage.Rating.Key count)) :=
  (Array.finRange count).map fun index => some {
    index,gain := (scale/(61+index.val%160))*(1+index.val%31),charge := (1+index.val%511)*512000}

def original {α : Type} {order : Preference α} {depth : Nat}
    (cache : Cache order depth) (updates : List (Nat × Option α)) : Cache order depth :=
  updates.foldl (fun current row => current.tree.updated row.1 row.2) cache

def controls : IO Nat := do
  let mut checked := 0
  for depth in [:7] do
    let count := 2^depth
    let values := keys count 1000000
    let cache := build (SharedCoverage.Rating.preference count) depth values
    for index in [:count+3] do
      for value in [none,values[0]?.getD none] do
        let left := cache.tree.updated index value
        let right := Width.updated cache.tree count index value
        check (left.best == right.best && left.tree.values == right.tree.values)
          "width-carrying point update changed the original tree"
        checked := checked+1
  return checked

def run (inputPath : String) : IO Unit := do
  let input ← read (.mk inputPath)
  let root : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "output"))
  let scale ← IO.ofExcept (input.getObjValAs? Nat "scale")
  check (!(← root.pathExists) && scale > 0) "fresh fixed-magnitude probe required"
  IO.FS.createDirAll root
  let checked ← controls
  let depth := 14
  let count := 2^depth
  let values := keys count scale
  let cache := build (SharedCoverage.Rating.preference count) depth values
  let patterns : Array (String × List Nat × Bool) := #[
    ("sparse16",(List.range 16).map (·*1024),false),
    ("contiguous1024",(List.range 1024).map (4096+·),false),
    ("all16384",List.range count,false),
    ("duplicate1024",(List.range 1024).map (fun i => 32+i%16),false),
    ("erase1024",(List.range 1024).map (·*8),true)]
  let mut cases := #[]
  for (name,positions,erase) in patterns do
    let updates := positions.map fun position =>
      let value := values[(position+1)%count]?.getD none
      (position,if erase then none else value)
    let expected := original cache updates
    let inputs ← IO.mkRef (cache,updates)
    let mut pairs := #[]
    for candidateFirst in #[false,true,false] do
      let mut pair := #[]
      for candidate in #[candidateFirst,!candidateFirst] do
        let started ← IO.monoNanosNow
        let (timedCache,timedUpdates) ← inputs.get
        let result ← (← IO.mkRef (if candidate then Width.updateMany timedCache timedUpdates
          else original timedCache timedUpdates)).get
        let elapsed := (← IO.monoNanosNow)-started
        check (result.best == expected.best && result.tree.values == expected.tree.values)
          "native batch update changed a leaf or the stable winner"
        pair := pair.push (Json.mkObj [("candidate",toJson candidate),("nanos",toJson elapsed)])
      pairs := pairs.push pair
    cases := cases.push (Json.mkObj [("name",toJson name),("updates",toJson updates.length),("pairs",toJson pairs)])
    save root "progress.json" (toJson cases)
  save root "report.json" (Json.mkObj [("controls",toJson checked),("depth",toJson depth),
    ("leaves",toJson count),("weightScaleBits",toJson (scale.log2+1)),("cases",toJson cases),
    ("exactAllLeavesAndStableWinner",toJson true),("syntheticUpdates",toJson true),
    ("timedInputsReadAfterClock",toJson true),
    ("retainedBaseForBothImplementations",toJson true),("newCacheOrQueue",toJson false),
    ("wholeHookBenefitEstablished",toJson false),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def main (args : List String) : IO Unit := do
  match args with
  | ["observe",input] => Eggshell.Research.PreparedRoutingObserver.run input
  | ["observer-controls",output] => Eggshell.Research.PreparedRoutingObserver.controls output
  | [input] => run input
  | _ => throw (IO.userError "input | observe input | observer-controls output")
