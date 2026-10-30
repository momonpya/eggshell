import tools.research.GroupCueCoverage
import tools.research.FrozenCanonicalBasis
import tools.research.OriginalPayloadBasis
import tools.research.AvailableDelivery
import tools.VerifiedWinnerCoverage
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource
open Eggshell.Research

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def fixtures : IO Unit := do
  let a : SharedCoverage.Input.RawOffer := {closure := [0,1,2],covers := [0]}
  let b : SharedCoverage.Input.RawOffer := {closure := [0,1,3],covers := [2]}
  let whole : SharedCoverage.Input.RawOffer := {closure := [0,1,2,3],covers := [0,2]}
  let alias : SharedCoverage.Input.RawOffer := {closure := [3,2,1,0],covers := [2,0]}
  let raw : SharedCoverage.Input.RawProblem := {
    costs := #[(0,0),(9,9),(10,10),(10,10)]
    weights := #[10,0,10,0]
    offers := #[a,b,whole,alias]
    fixed := (0,0)
    limit := (20,80)}
  let frames := Std.HashSet.ofList [0,1]
  let prepared ← IO.ofExcept (GroupCueCoverage.prepare raw 2 4 512 frames)
  let some group := prepared.groups[0]? | throw (IO.userError "fixture produced no evidence group")
  check (prepared.groups.size == 1 && group.originals == [2,3]) "physical aliases gained extra group votes"
  check (group.mass == 512) "group mass uses unexpected units"
  for (index,expected) in #[(0,false),(1,false),(2,true),(3,true)] do
    let some offer := prepared.problem.offers[index]? | throw (IO.userError "fixture lost an original offer")
    check (offer.covers.contains 4 == expected) "partial group gained a complete-group cue"
  check (prepared.problem.costs == raw.costs && prepared.problem.limit == raw.limit &&
    prepared.problem.fixed == raw.fixed) "group value changed original cost or budget"
  let p ← IO.ofExcept prepared.problem.decode
  let some chosen := SharedCoverage.choose? p | throw (IO.userError "fixture rejected empty feasible selection")
  check (!(SharedCoverage.cues p chosen.selected).any (·.val == 4)) "infeasible group bypassed budget"
  let larger := {raw with costs := #[(0,0),(9,9),(20,20),(20,20)],weights := #[20,0,20,0]}
  let normalized ← IO.ofExcept (GroupCueCoverage.prepare larger 2 4 512 frames)
  check ((normalized.groups[0]?).any (·.mass == group.mass)) "longer group acquired more relevance solely from length"
  let header := {raw with costs := #[(0,0),(100009,100009),(10,10),(10,10)]}
  let unchanged ← IO.ofExcept (GroupCueCoverage.prepare header 2 4 512 frames)
  check ((unchanged.groups[0]?).any (·.mass == group.mass)) "structural shell changed relevance density"

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh replay destination required")
  let out : System.FilePath := .mk destination
  check (!(← out.pathExists)) "keep previous group-cue replay"
  fixtures
  let started ← IO.monoMsNow
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let resumed := project / "docs/candidates/prepared-bindings/resumed"
  let receipt := resumed / "cue-capture/receipts/43ba2a13af5aae5fc34557e5b8747cafce13fa0063d0da7356b09f43de8cd9ca"
  let data := (← read (receipt / "selection-plan.json")).getObjValD "data"
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (data.getObjValAs? _ "selectorInput")
  let p ← IO.ofExcept raw.decode
  let families ← IO.ofExcept (data.getObjValAs? Nat "families")
  let first ← IO.ofExcept (data.getObjValAs? Nat "candidateUnits")
  let count ← IO.ofExcept ((data.getObjValD "jointBindings").getObjValAs? Nat "preparedBundles")
  let (source,rows) ← FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let some basis := OriginalPayloadBasis.prepare families rows p |
    throw (IO.userError "captured source atoms differ from frozen original rows")
  let mut frames := Std.HashSet.ofList (List.range families)
  let mut files : Std.HashSet File := {}
  for (row,atom) in basis.sourceRows do
    unless files.contains row.key.file do
      check (0 < atom.val) "source payload lacks its frame"
      frames := frames.insert (atom.val-1)
      files := files.insert row.key.file
  let inputMs := (← IO.monoMsNow)-started
  let compileStarted ← IO.monoMsNow
  let prepared ← IO.ofExcept (GroupCueCoverage.prepare raw first (first+count) 512 frames)
  let compileMs := (← IO.monoMsNow)-compileStarted
  let next ← IO.ofExcept prepared.problem.decode
  check (next.costs == p.costs && next.fixed == p.fixed && next.limit == p.limit &&
    prepared.problem.offers.size == raw.offers.size) "relevance compilation changed physical domain"
  for index in [:raw.offers.size] do
    let some old := raw.offers[index]? | throw (IO.userError "original proposal is missing")
    let some compiled := prepared.problem.offers[index]? | throw (IO.userError "compiled proposal is missing")
    check (old.closure == compiled.closure) "group changed a physical proposal"
  for index in [:raw.weights.size] do
    if index%2 == 0 then check (raw.weights[index]! == prepared.problem.weights[index]!) "base semantic weight changed"
  let solveStarted ← IO.monoMsNow
  let some chosen := SharedCoverage.choose? next | throw (IO.userError "candidate rejected feasible original input")
  let solveMs := (← IO.monoMsNow)-solveStarted
  let prior : List Nat ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/selector-decisions.json")).getObjValAs? _ "selected")
  let priorIndices ← IO.ofExcept (SharedCoverage.Input.checkedIndices p.offers.size prior)
  check (SharedCoverage.cost p priorIndices == (120000,120002)) "original sequence changed"
  let priorNodes := Std.HashSet.ofList ((SharedCoverage.nodes p priorIndices).map (·.val))
  let nextNodes := Std.HashSet.ofList ((SharedCoverage.nodes next chosen.selected).map (·.val))
  -- Human requirements enter only after both selections are fixed.
  let frozenList ← IO.ofExcept ((← read (resumed / "trial/frozen-before-delivery.json")).getArr?)
  let some topic := frozenList[0]? | throw (IO.userError "missing frozen topic")
  check (topic.getObjValD "topic" == toJson (1 : Nat)) "frozen topic order changed"
  let frozen : AvailableDelivery.Frozen ← IO.ofExcept (fromJson? (topic.getObjValD "available"))
  let shown := fun (nodes : Std.HashSet Nat) => basis.sourceRows.filterMap fun (row,atom) =>
    if nodes.contains atom.val then some (⟨row.key.file,row.key.line,row.key.line⟩ : Range) else none
  let baseline := AvailableDelivery.assess frozen (shown priorNodes)
  let candidate := AvailableDelivery.assess frozen (shown nextNodes)
  check (baseline.eligible == 3 && baseline.delivered == 2) "source-node baseline disagrees with actual delivery audit"
  let nextRows := basis.sourceRows.filterMap fun (row,atom) => if nextNodes.contains atom.val then some row.key else none
  let ended ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  check (source.head == ended.head) "read-only replay changed original source"
  IO.FS.createDirAll out
  IO.FS.writeFile (out / "result.json") (Json.mkObj [
    ("plannedOriginalNodesOnly",toJson true),("actualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false),("sourceUnchanged",toJson true),
    ("topic",toJson (1 : Nat)),("baseline",toJson baseline),("candidate",toJson candidate),
    ("inputGraphOffers",toJson count),("uniquePhysicalGroups",toJson prepared.groups.size),
    ("zeroMassOffers",toJson prepared.zeroMassOffers),("containmentChecks",toJson prepared.candidateChecks),
    ("baseWeightsUnchanged",toJson true),("physicalDomainAndLimitsUnchanged",toJson true),
    ("inputMs",toJson inputMs),("compileMs",toJson compileMs),("solveMs",toJson solveMs),
    ("candidateCost",toJson (SharedCoverage.cost next chosen.selected)),
    ("candidateOffers",toJson (chosen.selected.map (·.val))),
    ("sourceKeys",toJson nextRows),("independentFixturesPassed",toJson true)]).pretty
  IO.println s!"Complete evidence groups: {prepared.groups.size}; frozen source-node preview {baseline.delivered}/{baseline.eligible} -> {candidate.delivered}/{candidate.eligible}"
