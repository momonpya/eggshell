import tools.research.ReplayReadinessChecks
import tools.research.MemoryCapacity
import tools.research.NativeTrialAudit
import tools.research.BaseCueBuckets
open Lean Eggshell Eggshell.Plugin.SharedRangeAdapter
namespace Eggshell.Research.BaseCueBench

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

structure Case where
  name : String
  query : ServiceQuery
  source : Synapses.PreparedSourceView.Domain
  units : Array ServiceUnit
  cues : List CuePiece

def make (name : String) (families unitCount cueCount : Nat) (mode : String) : Case := Id.run do
  let positions := fun i => if mode == "dense" then i%64 else (i/families)*64
  let cues := (List.range cueCount).map fun i => ({
    family := i%families
    first := positions i
    last := if mode == "degenerate" && i%3 == 0 then positions i else positions i+8
    weight := if i%11 == 0 then 2^384 else i%19+1
    baseWeight := if i%13 == 0 then 0 else i%19+1} : CuePiece)
  let cues := if mode == "degenerate" then cues ++ cues.take 16 ++
    [{family := 0,first := 200,last := 3,weight := 7}] else cues
  let ranges := fun i => if mode == "wide" then [(0,(cueCount/families+1)*64)]
    else if mode == "dense" then [(0,32)]
    else if mode == "degenerate" then [(0,0),(0,128),(64,256),(0,128)]
    else let first := (i/families)*64; [(first,first+16)]
  let units := (Array.range unitCount).map fun i => ({
    shape := {family := i%families,ranges := ranges i}
    generic := some (if mode == "invalid" then unitCount else i)} : ServiceUnit)
  let query : ServiceQuery := {
    owners := (Array.range families).map (fun i => "owner-"++toString i)
    works := (Array.range families).map (fun i => ("work-"++toString i,0))
    frameCosts := Array.replicate families (0,0)
    scale := 1
    genericCosts := Array.replicate unitCount (1,1)
    generic := units.mapIdx fun i unit => {
      family := unit.shape.family,ranges := unit.shape.ranges,payloads := [i],contextual := false}
    pieces := cues
    files := #[]
    bundles := #[]
    fixed := (0,0)
    ceiling := (1000000,1000000) }
  let source : Synapses.PreparedSourceView.Domain := {
    rows := #[],costs := query.frameCosts,fileIds := {},rowIds := {},payloads := #[],files := {} }
  return ⟨name,query,source,units,cues⟩

@[noinline,nospecialize] def original (input : Case) : Option SharedCoverage.Problem :=
  problemFromView input.query input.source input.units input.cues
@[noinline,nospecialize] def candidate (input : Case) : Option SharedCoverage.Problem :=
  BaseCueBuckets.problem input.query input.source input.units input.cues

def measured (select : Case → Option SharedCoverage.Problem) (input : IO.Ref Case) :
    IO (Option SharedCoverage.Input.RawProblem × Nat × Nat) := do
  let input ← input.get
  let allocations ← IO.getNumHeartbeats
  let began ← IO.monoNanosNow
  let result ← (← IO.mkRef (select input)).get
  let elapsed := ((← IO.monoNanosNow)-began)/1000
  let allocated := (← IO.getNumHeartbeats)-allocations
  return (result.map SharedCoverage.Input.ofProblem,elapsed,allocated)

def run (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve previous native comparison"
  IO.FS.createDirAll output
  let mut rows := #[]
  for (name,families,units,cues,mode) in [
      ("empty",1,0,0,"narrow"),("small",4,32,64,"narrow"),
      ("balanced",40,8192,16384,"narrow"),("single-family",1,2048,8192,"narrow"),
      ("dense",1,128,4096,"dense"),("wide",1,128,4096,"wide"),
      ("degenerate-duplicate",4,128,1024,"degenerate"),("invalid",4,32,128,"invalid")] do
    let input ← IO.mkRef (make name families units cues mode)
    let mut trials := #[]
    for repetition in [:3] do
      let (old,next) ← if repetition == 1 then do
        let next ← measured candidate input
        let old ← measured original input
        pure (old,next)
      else do
        let old ← measured original input
        let next ← measured candidate input
        pure (old,next)
      check (old.1 == next.1) "complete ordered problem differs"
      check (old.1.isSome == (mode != "invalid")) "unexpected failure result"
      trials := trials.push (Json.mkObj [("repetition",toJson repetition),
        ("originalUs",toJson old.2.1),("candidateUs",toJson next.2.1),
        ("originalAllocationEvents",toJson old.2.2),("candidateAllocationEvents",toJson next.2.2),
        ("wholeProblemExact",toJson true)])
    rows := rows.push (Json.mkObj [("case",toJson name),("families",toJson families),
      ("units",toJson units),("inputCues",toJson ((← input.get).cues.length)),("trials",toJson trials)])
    IO.FS.writeFile (output/"progress.json") (toJson rows).compress
  IO.FS.writeFile (output/"result.json") (Json.mkObj [("rows",toJson rows),
    ("order",toJson "AB,BA,AB"),("syntheticComponentOnly",toJson true),
    ("wholeProblemsExact",toJson true),("actualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.BaseCueBench

def main (args : List String) : IO UInt32 := do
  match args with
  | ["base-cue-bench",output] => Eggshell.Research.BaseCueBench.run (.mk output); return 0
  | other => Eggshell.Research.ReplayReadinessChecks.main other
