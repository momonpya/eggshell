import tools.research.ReplayReadinessChecks
import tools.research.MemoryCapacity
import tools.research.NativeTrialAudit
import tools.research.ObjectCensus
open Lean Eggshell

def censusCheck (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

def censusControls (root : System.FilePath) : IO Unit := do
  censusCheck (!(← root.pathExists)) "preserve prior object controls"
  IO.FS.createDirAll root
  let a ← IO.getRandomBytes (1024*1024)
  let b ← IO.getRandomBytes (1024*1024)
  let single ← Research.ObjectCensus.inspect a
  let shared ← Research.ObjectCensus.inspect (a,a)
  let separate ← Research.ObjectCensus.inspect (a,b)
  let reference ← IO.mkRef a
  let opaqueRef ← Research.ObjectCensus.inspect reference
  let capped ← Research.ObjectCensus.inspect (Array.replicate 300000 a)
  let get := fun (value : Json) key => value.getObjValAs? Nat key |>.toOption.getD 0
  censusCheck (single.getObjValD "saturated" == toJson false && get single "scalarArrays" == 1 &&
    get single "scalarBytes" ≥ 1024*1024) "native byte payload was not counted"
  censusCheck (shared.getObjValD "saturated" == toJson false && get shared "scalarArrays" == 1 &&
    get shared "duplicates" ≥ 1 && get shared "scalarBytes" == get single "scalarBytes") "shared original counted twice"
  censusCheck (separate.getObjValD "saturated" == toJson false && get separate "scalarArrays" == 2 &&
    get separate "scalarBytes" == 2*get single "scalarBytes") "independent byte payload was omitted"
  censusCheck (get opaqueRef "skippedRefs" == 1 && get opaqueRef "scalarBytes" == 0)
    "census traversed a mutable ref"
  censusCheck (capped.getObjValD "saturated" == toJson true) "bounded traversal did not signal truncation"
  IO.FS.writeFile (root/"result.json") (Json.mkObj [("single",single),("shared",shared),
    ("separate",separate),("mutableRef",opaqueRef),("capacity",capped),("allPassed",toJson true),
    ("wholeProcessReachability",toJson false),("changesAllocatorPolicy",toJson false)]).compress

def main (args : List String) : IO UInt32 := do
  match args with
  | ["object-census-controls",output] => censusControls (.mk output); return 0
  | ["object-census-hooks",input] => Research.MemoryCapacity.run (.mk input); return 0
  | other => Research.ReplayReadinessChecks.main other
