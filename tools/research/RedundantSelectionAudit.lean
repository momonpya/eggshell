import tools.SharedCoverageInput
import tools.VerifiedWinnerCoverage
import Lean.Data.Json.Parser
open Lean SharedCoverage

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

/-- Inspect only declared coverage. Reverse deletion may discard an offer
only when every one of its distinct cues still has another selected witness.
No answer labels, original positions, names or new weights enter this pass. -/
private def prune (p : Problem) (selected : List (Fin p.offers.size)) : List (Fin p.offers.size) := Id.run do
  let mut counts := Array.replicate p.weights.size 0
  for index in selected do
    for cue in Eggshell.hashDistinct p.offers[index].covers do
      counts := counts.modify cue.val (· + 1)
  let mut removed : Std.HashSet (Fin p.offers.size) := {}
  for index in selected.reverse do
    let cues := Eggshell.hashDistinct p.offers[index].covers
    if cues.all (fun cue => 1 < counts[cue.val]!) then
      removed := removed.insert index
      for cue in cues do counts := counts.modify cue.val (· - 1)
  return selected.filter (!removed.contains ·)

private def problem (costs : Array (Nat × Nat)) (weights : Array Nat)
    (offers : Array Input.RawOffer) : IO Problem :=
  IO.ofExcept ({costs, weights, offers, fixed := (0, 0), limit := (100, 100)} : Input.RawProblem).decode

private def fixtures : IO Unit := do
  let duplicate ← problem #[(10, 10), (20, 20)] #[1]
    #[⟨[0, 1], [0, 0]⟩, ⟨[0], [0]⟩]
  let all := List.finRange duplicate.offers.size
  let result := prune duplicate all
  check (result.map (·.val) == [0] && benefit duplicate result == benefit duplicate all)
    "duplicate cue occurrences corrupted reverse deletion"
  let essential ← problem #[(10, 10), (20, 20)] #[0, 1]
    #[⟨[0], [0]⟩, ⟨[1], [1]⟩]
  check (prune essential (List.finRange essential.offers.size) == List.finRange essential.offers.size)
    "zero-weight but distinct coverage was removed"
  let shared ← problem #[(10, 10)] #[1] #[⟨[0, 0], [0]⟩, ⟨[0], [0]⟩]
  check (cost shared (prune shared (List.finRange shared.offers.size)) == (10, 10))
    "shared cost atoms were counted more than once"

private def refill (prior : Selection p) : Selection p := Id.run do
  let layout := SharedCoverage.Deferred.Sparse.layout p
  let stored := SharedCoverage.Deferred.Sparse.values prior
  let state := SharedCoverage.Deferred.VerifiedWinner.State.initial prior stored
    (SharedCoverage.Deferred.VerifiedWinner.depth p) (Nat.le_of_lt Nat.lt_log2_self)
  return SharedCoverage.prefer
    (SharedCoverage.Deferred.VerifiedWinner.fill layout p.offers.size prior stored state)
    (SharedCoverage.bestSingleton prior)

def main (args : List String) : IO Unit := do
  let [input, destination] := args | throw (IO.userError "recorded selector input and new output required")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "preserve prior redundancy audit"
  fixtures
  let data ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk input)))
  let raw : Input.RawProblem ← IO.ofExcept ((data.getObjValD "data").getObjValAs? _ "selectorInput")
  let p ← IO.ofExcept raw.decode
  let began ← IO.monoMsNow
  let some baseline := SharedCoverage.choose? p | throw (IO.userError "recorded selection did not replay")
  check (baseline.selected.length == 741 && cost p baseline.selected == (120000, 120002))
    "fixed actual selection changed before inspection"
  let selectedMs := (← IO.monoMsNow) - began
  let started ← IO.monoMsNow
  let pruned := prune p baseline.selected
  let oldCues := Std.HashSet.ofList (cues p baseline.selected)
  let newCues := Std.HashSet.ofList (cues p pruned)
  check (oldCues.size == newCues.size && oldCues.toList.all newCues.contains &&
      benefit p baseline.selected == benefit p pruned) "declared coverage or value was lost"
  let before := cost p baseline.selected
  let after := cost p pruned
  check (after.1 ≤ before.1 && after.2 ≤ before.2) "pruning increased shared cost"
  let oldNodes := Std.HashSet.ofList (nodes p baseline.selected)
  let newNodes := Std.HashSet.ofList (nodes p pruned)
  let freed := oldNodes.toArray.filter (!newNodes.contains ·)
  let removed := baseline.selected.filter (!pruned.contains ·)
  let families ← IO.ofExcept ((data.getObjValD "data").getObjValAs? Nat "families")
  let pruningMs := (← IO.monoMsNow) - started
  let checked := if unique : pruned.Nodup then
      if fits : (cost p pruned).1 ≤ p.limit.1 ∧ (cost p pruned).2 ≤ p.limit.2 then
        some ({selected := pruned, unique, charsFit := fits.1, bytesFit := fits.2} : Selection p)
      else none
    else none
  let some compact := checked | throw (IO.userError "compacted selection is not certified feasible")
  -- No extra traversal when no physical capacity was recovered. The frozen
  -- selector and all original weights remain the only choice rule.
  let refilled := if after == before then compact else refill compact
  check (benefit p baseline.selected ≤ benefit p refilled.selected) "refill reduced the existing objective"
  let digest ← IO.Process.output {cmd := "/usr/bin/shasum", args := #["-a", "256", input]}
  check (digest.exitCode == 0) "input digest failed"
  let report := Json.mkObj [("input", toJson input),
    ("inputSha256", toJson (digest.stdout.splitOn " ").head!),
    ("baselineSelectionMs", toJson selectedMs), ("pruningMs", toJson pruningMs),
    ("baselineOffers", toJson baseline.selected.length), ("remainingOffers", toJson pruned.length),
    ("removedOffers", toJson (removed.map (·.val))), ("freedAtoms", toJson (freed.map (·.val))),
    ("onlyFamilyFramesFreed", toJson (freed.all (fun atom => atom.val < families))),
    ("beforeCost", toJson before), ("afterCost", toJson after),
    ("allDeclaredCuesPreserved", toJson true), ("benefitPreserved", toJson true),
    ("refilledCost", toJson (cost p refilled.selected)),
    ("newOffersAfterRefill", toJson (refilled.selected.filter (!baseline.selected.contains ·) |>.map (·.val))),
    ("refilledObjectiveNondecreasing", toJson true), ("fixturesPassed", toJson true),
    ("weightsCostsOffersAndBudgetChanged", toJson false), ("answerLabelsRead", toJson false),
    ("answeringModelCalls", toJson (0 : Nat)), ("warmCalls", toJson (0 : Nat)),
    ("actualHookCalls", toJson (0 : Nat)), ("adopted", toJson false)]
  IO.FS.createDirAll output.parent.get!
  IO.FS.writeFile output report.pretty
  IO.println report.compress
