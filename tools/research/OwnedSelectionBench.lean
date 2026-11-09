import tools.research.ReplayReadinessChecks
import tools.research.MemoryCapacity
import tools.research.NativeTrialAudit
import tools.research.OwnedCoverageAdvance
open Lean SharedCoverage
namespace Eggshell.Research.OwnedSelectionBench
open Deferred Deferred.VerifiedWinner

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

def problem (count width : Nat) (ring : Bool) : Problem := Id.run do
  let costs := Array.replicate (count+1) (1,1)
  let weights := (Array.range (count+1)).map fun i => 2^width/(61+i%64)+1
  let offers := (Array.finRange count).map fun i =>
    let own : Fin costs.size := ⟨i.val+1,by simp [costs]⟩
    let zero : Fin costs.size := ⟨0,by simp [costs]⟩
    let cue : Fin weights.size := ⟨own.val,by simpa [weights,costs] using own.isLt⟩
    let common : Fin weights.size := ⟨0,by simp [weights]⟩
    let other : Fin weights.size := ⟨(i.val+2)%(count+1),by
      simpa only [weights,Array.size_map,Array.size_range] using Nat.mod_lt (i.val+2) (Nat.zero_lt_succ count)⟩
    ({closure := [zero,own],covers := if ring then [common,cue,other] else [common,cue]} : Offer costs.size weights.size)
  return {costs,weights,offers,limit := (count/2+1,count/2+1)}

def answer (p : Problem) (selected : SharedCoverage.Selection p) : Json := Json.mkObj [
  ("selected",toJson (selected.selected.map (·.val))),
  ("cost",toJson (cost p selected.selected)),("benefit",toJson (benefit p selected.selected))]

@[noinline,nospecialize] def original (p : Problem) : Option (SharedCoverage.Selection p) :=
  Deferred.VerifiedWinner.choose? p
@[noinline,nospecialize] def candidate (p : Problem) : Option (SharedCoverage.Selection p) :=
  OwnedAdvance.chooseOwned p

structure Snapshot (p : Problem) where
  prior : SharedCoverage.Selection p
  values : Sparse.Values prior
  signature : UInt64

def signature {p : Problem} {prior : SharedCoverage.Selection p} (stored : Sparse.Values prior) : UInt64 :=
  hash (stored.costs.toArray,stored.gains.toArray,stored.base.nodeIndex.toArray,
    stored.base.cueIndex.toArray,stored.base.beforeCost,stored.base.beforeBenefit)

/-- Deliberately retain every prior value and verify it after later updates.
The extra lifetime is a control; its time is not a production benchmark. -/
def retained (owned : Bool) (layout : Sparse.Layout p) (fuel : Nat) (prior : SharedCoverage.Selection p)
    (stored : Sparse.Values prior) (state : State prior stored (depth p)) (seen : Known prior)
    (snapshots : Array (Snapshot p)) : SharedCoverage.Selection p × Array (Snapshot p) :=
  match fuel with
  | 0 => (prior,snapshots)
  | fuel+1 =>
      let resolved := state.resolveWith seen
      match resolved.score with
      | none => (prior,snapshots)
      | some score =>
          let snapshots := snapshots.push ⟨prior,stored,signature stored⟩
          let next := score.proposal.result
          let nextSeen := advanceKnown seen next score.index rfl
          if owned then
            let changed := affected layout stored score.index
            let updated := OwnedAdvance.values stored layout next score.index rfl
            retained owned layout fuel next updated
              (OwnedAdvance.winnerAdvance resolved.state layout next score.index rfl updated
                (OwnedAdvance.values_exact ..) nextSeen changed rfl) nextSeen snapshots
          else
            let updated := stored.advance layout next score.index rfl
            retained owned layout fuel next updated
              (resolved.state.advanceUsing layout next score.index rfl updated rfl nextSeen) nextSeen snapshots

def retainedRun (owned : Bool) (p : Problem) : IO Json := do
  let some initial := empty? p | throw (IO.userError "retained control is infeasible")
  let layout := Sparse.layout p
  let stored := Sparse.values initial
  let state := State.initial initial stored (depth p) (Nat.le_of_lt Nat.lt_log2_self)
  let result ← (← IO.mkRef (retained owned layout p.offers.size initial stored state (known initial) #[])).get
  check (result.2.all fun snapshot => signature snapshot.values == snapshot.signature)
    "later selection updates mutated a retained immutable snapshot"
  let chosen := prefer result.1 (bestSingleton initial)
  return Json.mkObj [("answer",answer p chosen),("snapshots",toJson result.2.size),
    ("retainedSnapshotsUnchanged",toJson true)]

def measured (select : (p : Problem) → Option (SharedCoverage.Selection p)) (input : IO.Ref Problem) : IO (Json × Nat × Nat) := do
  let p ← input.get
  let allocations ← IO.getNumHeartbeats
  let began ← IO.monoNanosNow
  let selected ← (← IO.mkRef (select p)).get
  let elapsed := ((← IO.monoNanosNow)-began)/1000
  let allocated := (← IO.getNumHeartbeats)-allocations
  let some selected := selected | throw (IO.userError "native selector returned infeasible")
  return (answer p selected,elapsed,allocated)

def run (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve one fixed native ownership comparison"
  IO.FS.createDirAll output
  let mut rows : Array Json := #[]
  for (count,width,ring) in [(0,0,false),(1,0,false),(32,0,false),(128,0,true),
    (512,384,true),(2048,384,false),(4096,384,true)] do
    let p := problem count width ring
    let input ← IO.mkRef p
    let mut trials := #[]
    for repetition in [:3] do
      let (before,after) ← if repetition == 1 then do
        let after ← measured candidate input
        let before ← measured original input
        pure (before,after)
      else do
        let before ← measured original input
        let after ← measured candidate input
        pure (before,after)
      check (before.1 == after.1) "ordered selection, cost or benefit changed"
      trials := trials.push (Json.mkObj [("repetition",toJson repetition),
        ("originalUs",toJson before.2.1),("candidateUs",toJson after.2.1),
        ("originalSmallAllocations",toJson before.2.2),("candidateSmallAllocations",toJson after.2.2),
        ("answerSha256",toJson (Eggshell.Sha256.hex before.1.compress.toUTF8)),
        ("selected",toJson ((before.1.getObjValD "selected").getArr?.toOption.map (·.size))),
        ("allOrderedResultsExact",toJson true)])
    let retainedControl ← if count ≤ 128 then do
        let before ← retainedRun false p
        let after ← retainedRun true p
        check (before == after) "retained control selection or snapshot domain changed"
        pure after
      else pure Json.null
    rows := rows.push (Json.mkObj [("offers",toJson count),("weightBits",toJson width),("ring",toJson ring),
      ("trials",toJson trials),("retainedControl",retainedControl)])
    IO.FS.writeFile (output/"progress.json") (toJson rows).compress
  IO.FS.writeFile (output/"result.json") (Json.mkObj [("rows",toJson rows),
    ("comparisonOrder",toJson "AB,BA,AB"),("syntheticComponentOnly",toJson true),
    ("queryOrModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.OwnedSelectionBench

def main (args : List String) : IO UInt32 := do
  match args with
  | ["owned-selection-bench",output] =>
    Eggshell.Research.OwnedSelectionBench.run (.mk output)
    return 0
  | other => Eggshell.Research.ReplayReadinessChecks.main other
