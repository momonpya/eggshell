import tools.research.RemainingSource
import Eggshell.CanonicalSourceCache
open Lean Eggshell DB Synapses CanonicalSource CanonicalSource.Delivery
namespace RemainingSourceChecks
def check (b : Bool) (s : String) : IO Unit := unless b do throw (IO.userError s)
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def source := base/"real-source-search-read-trial-result/work.egg"
def fixture := base/"selection-profile-inputs/selector-fixture.json"
def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= (IO.ofExcept ∘ Json.parse)
def hash (p : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",p.toString]}
  check (result.exitCode == 0) "cannot hash original source"
  return (result.stdout.splitOn " ").headD ""
def originalFiles : IO (Array (String × String)) := do
  (← source.readDir).mapM fun entry => do
    check ((← entry.path.metadata).type == .file) "unexpected original directory"
    return (entry.fileName,← hash entry.path)

-- Independent frozen source spelling, not a call rewritten by csimp.
@[noinline,nospecialize] def reference (part : Part) (acknowledged : List String) : Option Part :=
  if !part.plan.isEmpty && acknowledged.contains part.plan then none else
  let rows := part.rows.filter fun row => !acknowledged.contains (rowKey row.key)
  if nonempty : rows.isEmpty = false then some {part with rows,nonempty} else none
theorem reference_exact (part : Part) (acknowledged : List String) :
    reference part acknowledged = part.remaining acknowledged := rfl

@[noinline,nospecialize] def measure (fast : Bool) (parts : IO.Ref (Array (Part × List String))) : IO Json := do
  let before ← IO.getNumHeartbeats
  let started ← IO.monoNanosNow
  let mut checksum := 0
  for (part,acknowledged) in ← parts.get do
    let result := if fast then remainingSource part acknowledged else reference part acknowledged
    checksum := checksum+(result.map (fun part => part.rows.size+part.plan.utf8ByteSize)).getD 0
  let elapsed := ((← IO.monoNanosNow)-started)/1000
  return Json.mkObj [("us",toJson elapsed),("checksum",toJson checksum),
    ("smallAllocationsNotBytes",toJson ((← IO.getNumHeartbeats)-before))]

def run (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve component result"
  let before ← originalFiles
  let snapshot ← PageMap.pin source
  let examples ← IO.ofExcept (← read fixture).getArr?
  check (examples.size == 3 && examples.all (fun row =>
    (row.getObjValD "heads").getArr?.toOption.getD #[] == #[toJson snapshot.head]))
    "three frozen query/source snapshots required"
  let directory ← Cache.directory snapshot .user
  let current ← PageMap.pin (directory/"recipes")
  let recipes := (← PreparedRoot.select? snapshot current).getD current
  let some header ← Cache.header? recipes | throw (IO.userError "prepared source header absent")
  check (← Index.sameSources snapshot header.source) "prepared source has a different original publication"
  let mut raw := #[]
  let mut seen : Std.HashSet String := {}
  for sample in examples do
    let nested ← IO.ofExcept (sample.getObjValAs? (Array (Array String)) "owners")
    for owner in nested.flatten do
      if seen.contains owner then continue
      seen := seen.insert owner
      if let some stored ← Recipe.read? recipes owner then raw := raw++stored.rows
  let merged ← IO.ofExcept (Delivery.merge raw)
  check (!merged.isEmpty && merged.size < 65536) "bounded actual source rows required"
  let directory := Std.HashMap.ofArray (merged.map fun row => (row.key,row))
  let mut parts : Array Part := #[]
  for sample in examples do
    let keys ← IO.ofExcept ((sample.getObjValD "choice").getObjValAs? (Array Key) "sourceKeys")
    let rows ← keys.mapM fun key => do
      let some row := directory[key]? | throw (IO.userError "frozen selected row is absent from the actual original")
      return row
    let some part := Part.check? rows "component-plan" | throw (IO.userError "selected original part is empty")
    parts := parts.push part
  let mut checked := 0
  for original in parts do
    let some first := original.rows[0]? | throw (IO.userError "empty actual part")
    let smallRows := original.rows.extract 0 (min 64 original.rows.size)
    let some small := Part.check? smallRows "small-plan" | throw (IO.userError "empty small original")
    for part in #[original,{original with plan := ""},small] do
      let keys := part.keys
      let histories := [[],[part.plan],[rowKey first.key],["foreign-source"],keys.take 32,
        keys.take 32++keys.take 32,(keys.take 64).reverse]
      for history in histories do
        check (reference part history == remainingSource part history) "source difference changed original rows, order or plan"
        checked := checked+1
    let allSmall := small.rows.toList.map (fun row => rowKey row.key)
    check ((reference small allSmall).isNone && (remainingSource small allSmall).isNone) "exhausted original rows refilled"
  let mut trials := #[]
  for mode in ["empty","partial","long-foreign"] do
    let inputs := parts.map fun part => (part,if mode == "empty" then [] else if mode == "partial" then
      (part.rows.toList.take 32).map (fun row => rowKey row.key) else (List.range 1024).map fun n => s!"foreign-source-{n}")
    let prepared ← IO.mkRef inputs
    for repetition in [:3] do
      let (old,fresh) ← if repetition % 2 == 0 then do
        let old ← measure false prepared
        let fresh ← measure true prepared
        pure (old,fresh)
        else do
          let fresh ← measure true prepared
          let old ← measure false prepared
          pure (old,fresh)
      check (old.getObjValD "checksum" == fresh.getObjValD "checksum") "measured source result changed"
      trials := trials.push (Json.mkObj [("mode",toJson mode),("repetition",toJson repetition),("reference",old),("candidate",fresh)])
  check ((← originalFiles) == before) "original source changed during pure source subtraction"
  IO.FS.writeFile output (Json.mkObj [("fixtureSha256",toJson (← hash fixture)),("sourceFiles",toJson before),
    ("sourceRows",toJson merged.size),("selectedRows",toJson (parts.map (·.rows.size))),
    ("controls",toJson checked),("trials",toJson trials),("allExact",toJson true),
    ("originalSourceUnchanged",toJson true),("componentOnly",toJson true),("adopted",toJson false),
    ("answeringModelCalls",toJson (0 : Nat))]).compress
end RemainingSourceChecks
def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "component output required")
  RemainingSourceChecks.run (.mk output)
