module
public import Eggshell.CanonicalSourceCache
public import tools.research.MemoGroupFold
@[expose] public section
namespace Eggshell.Research.GroupReuseChecks
open Lean Eggshell DB Synapses CanonicalSource PreparedSourceView

#print axioms MemoGroupFold.run_exact
#print axioms PreparedSourceView.grouped_units_memo_exact

-- ORIGINAL PRODUCERS

def check (yes : Bool) (message : String) : IO Unit := unless yes do throw (IO.userError message)

def signature (units : Array UnitRef) := units.map fun unit =>
  (unit.keys,unit.ranges,unit.coverage.intervals.map fun part => (part.start,part.stop))

def sameResult (first second : Except String (Array UnitRef)) : Bool :=
  match first,second with
  | .error a,.error b => a == b
  | .ok a,.ok b => signature a == signature b
  | _,_ => false

structure Input where
  owner : String
  ready : OwnerReady
  groups : List (List (Nat × Nat))

@[noinline,nospecialize] def replay (fast : Bool) (input : Input) : Except String (Array UnitRef) :=
  if fast then groupedUnits input.owner input.ready input.groups
  else referenceGroupedUnits input.owner input.ready input.groups

@[noinline,nospecialize] def measure (fast : Bool) (inputs : IO.Ref (Array Input)) : IO Json := do
  let allocations ← IO.getNumHeartbeats
  let started ← IO.monoNanosNow
  let mut checksum := 0
  for input in ← inputs.get do
    let units ← IO.ofExcept (replay fast input)
    checksum := checksum+units.size+units.foldl (fun total unit => total+unit.keys.size+unit.ranges.length) 0
  let elapsed := ((← IO.monoNanosNow)-started)/1000
  return Json.mkObj [("us",toJson elapsed),("checksum",toJson checksum),
    ("heartbeatDeltaNotBytes",toJson ((← IO.getNumHeartbeats)-allocations))]

def sourceFiles (path : System.FilePath) : IO (Array (String × String)) := do
  let entries := (← path.readDir).qsort (fun a b => a.fileName < b.fileName)
  entries.mapM fun entry => do
    check ((← entry.path.metadata).type == .file) "source-only project unexpectedly contains a directory"
    let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",entry.path.toString]}
    check (result.exitCode == 0) "source digest failed"
    return (entry.fileName,(result.stdout.splitOn " ").headD "")

def run (project fixture output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve the group comparison"
  let originals ← sourceFiles project
  let source ← PageMap.pin project
  let path ← Cache.directory source .user
  let current ← PageMap.pin (path/"recipes")
  let recipes := (← PreparedRoot.select? source current).getD current
  let some header ← Cache.header? recipes | throw (IO.userError "published source metadata is absent")
  check (← Index.sameSources source header.source) "published group input belongs to another source"
  -- This compares deterministic producers on already-published metadata.
  -- It does not certify the candidate's warm/admission contract.
  let examples ← IO.ofExcept (Json.parse (← IO.FS.readFile fixture) >>= Json.getArr?)
  check (examples.size == 3) "the complete three-query fixture is required"
  let mut readyByOwner : Std.HashMap String OwnerReady := {}
  let mut queries : Array (Array Input) := #[]
  let mut exact := 0
  let mut federated := 0
  let mut rows := #[]
  for (sampleRow,ordinal) in examples.zipIdx do
    let files ← IO.ofExcept ((← IO.ofExcept (sampleRow.getObjVal? "query")).getObjValAs? (Array Json) "files")
    let mut inputs := #[]
    let mut raw := 0
    let mut distinct := 0
    let mut outputs := 0
    for file in files do
      let owner ← IO.ofExcept (file.getObjValAs? String "owner")
      let groups ← IO.ofExcept (file.getObjValAs? (List (List (Nat × Nat))) "groups")
      let ready ← match readyByOwner[owner]? with
        | some ready => pure ready
        | none => readOwner recipes source.head.identity owner
      readyByOwner := readyByOwner.insert owner ready
      let input : Input := ⟨owner,ready,groups⟩
      let old := replay false input
      let fresh := replay true input
      check (sameResult old fresh) "memoized groups changed complete ordered keys, ranges, coverage or errors"
      let units ← IO.ofExcept fresh
      exact := exact+1
      outputs := outputs+units.size
      raw := raw+groups.length
      distinct := distinct+(hashDistinct groups).length
      -- Two independently remapped owner parts exercise the federation branch.
      let oldFederation := referenceFederatedUnits owner #[ready,ready] ready.rows groups
      let newFederation := federatedUnits owner #[ready,ready] ready.rows groups
      check (sameResult oldFederation newFederation && newFederation.isOk)
        "federated group memoization changed the original catalogue or group order"
      federated := federated+1
      inputs := inputs.push input
    queries := queries.push inputs
    rows := rows.push (Json.mkObj [("query",toJson (ordinal+1)),("owners",toJson files.size),
      ("groups",toJson raw),("distinctGroups",toJson distinct),("orderedOutputUnits",toJson outputs)])
  check (exact > 0 && federated == exact) "group comparison had no successful actual inputs"
  let mut trials := #[]
  for repetition in [:3] do
    for (inputs,ordinal) in queries.zipIdx do
      let input ← IO.mkRef inputs
      let oldFirst := repetition%2 == 0
      let (old,fresh) ← if oldFirst then do
          let old ← measure false input
          let fresh ← measure true input
          pure (old,fresh)
        else do
          let fresh ← measure true input
          let old ← measure false input
          pure (old,fresh)
      check (old.getObjValD "checksum" == fresh.getObjValD "checksum") "timed group checksum changed"
      trials := trials.push (Json.mkObj [("repetition",toJson repetition),("query",toJson (ordinal+1)),
        ("parentFirst",toJson oldFirst),("parent",old),("candidate",fresh)])
  check ((← sourceFiles project) == originals) "group comparison changed original project files"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("recipeHead",toJson recipes.head),
    ("sourceFiles",toJson originals),("originalSourceUnchanged",toJson true),
    ("queries",toJson rows),("completeOrderedOwnerComparisons",toJson exact),
    ("federatedComparisons",toJson federated),("allCompleteOutputsEqual",toJson true),
    ("trials",toJson trials),("preparationIncludedInCandidateTiming",toJson true),
    ("warmAdmissionVerified",toJson false),("fullHooksVerified",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.GroupReuseChecks

def main (args : List String) : IO Unit := do
  let [project,fixture,output] := args | throw (IO.userError "group reuse PROJECT FIXTURE OUTPUT")
  Eggshell.Research.GroupReuseChecks.run (.mk project) (.mk fixture) (.mk output)
