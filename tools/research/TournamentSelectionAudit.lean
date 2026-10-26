import tools.TournamentCoverage
import Lean.Data.Json.FromToJson
open Lean Eggshell SharedCoverage Deferred

#print axioms StableTournament.Tree.best_exact
#print axioms StableTournament.Tree.updated_values
#print axioms StableTournament.Tree.refreshed_values
#print axioms Rating.better_trans
#print axioms Rating.better_neg_trans
#print axioms Tournament.fill_exact
#print axioms Tournament.choose_exact
#print axioms Sparse.Incidence.lookup_exact
#print axioms Sparse.patch_exact
#print axioms Sparse.Values.advance
#print axioms Sparse.score_exact
#print axioms Sparse.fill_exact
#print axioms Sparse.choose_exact
#print axioms Sparse.Incidence.changed_streaming_exact
#print axioms KeyPostings.compactDirectory_exact

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

/-- Direct parent scan remains separate from the compiled choose entry. -/
private def reference (p : Problem) : Option (Selection p) := do
  let initial ← empty? p
  pure (prefer (fillDeferred p.offers.size initial) (bestSingleton initial))

private def densePostings (population keys : Nat) : IO Json := do
  let _ : Hashable Nat := ⟨fun _ => 0⟩
  let rows := (Array.range population).map fun index => (index%keys,index%97)
  let queries := (List.range keys) ++ [keys]
  let started ← IO.monoMsNow
  let parent := KeyPostings.directory Prod.fst rows
  let original := queries.map fun key => parent[key]?.getD #[]
  check ((original.map Array.size).sum == population) "old postings were not fully prepared"
  let parentMs := (← IO.monoMsNow)-started
  let started ← IO.monoMsNow
  let current := KeyPostings.prepare Prod.fst rows
  let rebuilt := queries.map current.lookup
  check (rebuilt == original) "postings changed order, duplicates or collided full keys"
  return Json.mkObj [("rows",toJson population),("keys",toJson keys),
    ("forcedHashCollisions",toJson true),("parentMs",toJson parentMs),
    ("candidateMs",toJson ((← IO.monoMsNow)-started)),("exactOriginalSequences",toJson true)]

private def scenario (count population groups budget : Nat) : IO Json := do
  let costs := (Array.range (count+2)).map fun i => if i == 0 then (40,80) else (i%7+1,i%9+2)
  let weights := (Array.range population).map fun i => if i%13 == 0 then 0 else 2^300+i%19
  let offers : Array (Offer costs.size weights.size) := (Array.range count).map fun i => {
    closure := (List.finRange costs.size).filter fun node => node.val == 0 || node.val == i+1
    covers := let selected := (List.finRange weights.size).filter fun cue => cue.val%groups == i%groups
      selected ++ selected.take 4}
  let p : Problem := {costs,weights,offers,limit := (budget,2*budget)}
  let initial := empty? p
  let mut states := #[]
  if let some initial := initial then
    let prepared := Sparse.layout p
    let mut state : (current : Selection p) × Sparse.Values current := ⟨initial,Sparse.values initial⟩
    for _ in [0:min groups 6] do
      let current := state.1
      let stored := state.2
      for index in List.finRange p.offers.size do
        check (stored.costs[index] == Sparse.rawCost (evaluation current) index &&
          stored.gains[index] == Sparse.rawGain (evaluation current) index) "cached marginal differs from full scan"
      let some best := Sparse.best current stored | break
      let before := evaluation current
      check (prepared.nodes.changed before.nodeIndex p.offers[best.index].closure ==
        hashDistinct (prepared.nodes.touched (p.offers[best.index].closure.filter
          fun value => !before.nodeIndex.contains value))) "streamed changed nodes reordered offers"
      check (prepared.cues.changed before.cueIndex p.offers[best.index].covers ==
        hashDistinct (prepared.cues.touched (p.offers[best.index].covers.filter
          fun value => !before.cueIndex.contains value))) "streamed changed cues reordered offers"
      states := states.push (Json.mkObj [("selected",toJson current.selected.length),
        ("costUpdates",toJson (prepared.nodes.changed before.nodeIndex p.offers[best.index].closure).length),
        ("gainUpdates",toJson (prepared.cues.changed before.cueIndex p.offers[best.index].covers).length)])
      let next := best.proposal.result
      state := ⟨next,stored.advance prepared next best.index rfl⟩
  let started ← IO.monoMsNow
  let parent := reference p
  let referenceSelection := parent.map (·.selected.map (·.val))
  check (referenceSelection.isSome && (referenceSelection.getD []).length ≤ p.offers.size)
    "reference was not evaluated"
  let parentMs := (← IO.monoMsNow)-started
  let started ← IO.monoMsNow
  let directParent := Sparse.choose? p
  let directParentSelection := directParent.map (·.selected.map (·.val))
  check (directParentSelection == referenceSelection) "direct parent differs from full ordered selection"
  let directParentMs := (← IO.monoMsNow)-started
  let started ← IO.monoMsNow
  let candidate := SharedCoverage.choose? p
  let candidateSelection := candidate.map (·.selected.map (·.val))
  check (candidateSelection == referenceSelection) "incremental selector changed full ordered selection"
  let candidateMs := (← IO.monoMsNow)-started
  return Json.mkObj [("offers",toJson count),("cues",toJson population),("groups",toJson groups),
    ("budget",toJson budget),("selected",toJson candidateSelection),("parentMs",toJson parentMs),
    ("candidateMs",toJson candidateMs),("exactOrderedSelection",toJson true),
    ("directParentMs",toJson directParentMs),("directParentEntry",toJson "Sparse.choose?"),
    ("entry",toJson "SharedCoverage.choose?"),
    ("hugeWeightsAndDuplicateCues",toJson true),("states",toJson states)]

def main (args : List String) : IO UInt32 := do
  try
    let [destination] := args | throw (IO.userError "TournamentSelectionAudit NEW-DIRECTORY")
    let root := System.FilePath.mk destination
    check (root.isAbsolute && !(← root.pathExists)) "new selector audit directory required"
    IO.FS.createDir root
    let mut results := #[]
    for (count,population,groups,budget) in [(0,0,1,100),(32,0,1,100),(64,256,8,100),
        (256,4096,32,140),(512,16384,64,220),(64,512,8,10)] do
      let result ← scenario count population groups budget
      IO.println result.compress
      results := results.push result
    let mut postings := #[]
    for (population,keys) in [(128,1),(8192,1),(16384,8)] do
      let result ← densePostings population keys
      IO.println result.compress
      postings := postings.push result
    IO.FS.writeFile (root / "results.json") (Json.mkObj [("synthetic",toJson true),
      ("scenarios",toJson results),("postings",toJson postings),
      ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).pretty
    return 0
  catch error => IO.eprintln error.toString; return 1

