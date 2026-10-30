import tools.research.PrincipalNetwork
import tools.research.ResidualInterval
import tools.research.FrozenCanonicalBasis
import tools.research.OriginalPayloadBasis
import tools.research.AvailableDelivery
import tools.SharedCoverageInput
import tools.VerifiedWinnerCoverage
open Lean Eggshell Eggshell.Research SharedCoverage

private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

private def fixtures : IO Nat := do
  let mut networks := #[]
  for vertices in [2:8] do
    for seed in [0:5] do
      let mut arcs := #[]
      for first in [:vertices] do
        for last in [:vertices] do
          let capacity := (first*17+last*31+seed*13)%11
          if first != last && capacity%3 != 0 then arcs := arcs.push ⟨first,last,capacity⟩
      networks := networks.push (⟨vertices,0,vertices-1,arcs⟩ : ClosureFlow.Network)
  -- Empty arcs, disconnected nodes and equal-capacity paths deliberately
  -- exercise a non-singleton family of optimal source sides.
  networks := networks ++ #[⟨4,0,3,#[]⟩,
    ⟨4,0,3,#[⟨0,1,7⟩,⟨1,3,7⟩]⟩,
    ⟨5,0,4,#[⟨0,1,3⟩,⟨1,4,3⟩,⟨0,2,5⟩,⟨2,4,5⟩,⟨2,3,2⟩]⟩]
  for network in networks do
    let result ← ClosureFlow.solve network ((← IO.monoMsNow)+2000)
    let maximum ← ClosureFlow.maximumSource network result
    let mut cuts := #[]
    let mut best := network.arcs.foldl (fun sum arc => sum+arc.capacity) 0
    for mask in [:2^(network.vertices-2)] do
      let selected := (Array.range network.vertices).map fun vertex =>
        vertex == 0 || (vertex+1 < network.vertices && (mask/2^(vertex-1))%2 == 1)
      let value := ClosureFlow.cutCapacity network selected
      if value < best then cuts := #[]; best := value
      if value == best then cuts := cuts.push selected
    let intersection := (Array.range network.vertices).map fun vertex => cuts.all (·[vertex]!)
    let union := (Array.range network.vertices).map fun vertex => cuts.any (·[vertex]!)
    check (result.value == best && result.selected == intersection && maximum == union)
      "residual extremes differ from independently enumerated minimum cuts"
    for vertex in [:network.vertices] do
      if maximum[vertex]! then
        let extended ← ClosureFlow.extendSource network result #[vertex]
        check (extended[vertex]! && cuts.contains extended) "residual extension is not an enumerated minimum cut"
  return networks.size

private def feasible (p : Problem) (selected : List (Fin p.offers.size)) : Bool :=
  (cost p selected).1 ≤ p.limit.1 && (cost p selected).2 ≤ p.limit.2

private def reward (p : Problem) (witnesses : Array (Sigma (PrincipalOffers.Witness p)))
    (selected : Array Bool) : Nat :=
  (List.finRange witnesses.size).foldl (fun total index =>
    if selected[2+p.costs.size+index.val]! then total+p.weights[witnesses[index].1] else total) 0

private structure Bound (p : Problem) where
  lower : List (Fin p.offers.size)
  upper : List (Fin p.offers.size)

private structure Band where
  index : Nat
  network : ClosureFlow.Network
  result : ClosureFlow.Result
  maximum : Array Bool

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh residual-band result required")
  let output : System.FilePath := .mk destination
  check (!(← output.pathExists)) "preserve previous residual-band result"
  let fixtureCount ← fixtures
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let input := project / "docs/candidates/prepared-bindings/resumed/cue-capture/receipts/43ba2a13af5aae5fc34557e5b8747cafce13fa0063d0da7356b09f43de8cd9ca/selection-plan.json"
  let data := (← read input).getObjValD "data"
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (data.getObjValAs? _ "selectorInput")
  let p ← IO.ofExcept raw.decode
  let some baseline := SharedCoverage.choose? p | throw (IO.userError "baseline empty selection infeasible")
  let previous : List Nat ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/selector-decisions.json")).getObjValAs? _ "selected")
  check (baseline.selected.map Fin.val == previous) "baseline actual sequence changed"
  let domain := PrincipalOffers.prepare p
  let mut witnesses : Array (Sigma (PrincipalOffers.Witness p)) := #[]
  for cue in List.finRange p.weights.size do
    if p.weights[cue] > 0 then
      if let some witness := PrincipalOffers.find? domain cue then witnesses := witnesses.push ⟨cue,witness⟩
  let saved ← IO.ofExcept ((← read (project / "docs/candidates/principal-offers/frontier-replay.json")).getObjValAs? (Array Json) "cuts")
  check (saved.size == 25 && witnesses.size == 9453) "fixed diagnostic input cardinalities changed"
  let started ← IO.monoMsNow
  let deadline := started+15000
  let mut bounds : Array (Bound p) := #[]
  let mut bands : Array Band := #[]
  let mut records := #[]
  for index in [:saved.size] do
    let old := saved[index]!
    let byteAxis := old.getObjValD "axis" == toJson "bytes"
    let numerator : Nat ← IO.ofExcept (old.getObjValAs? _ "numerator")
    let denominator : Nat ← IO.ofExcept (old.getObjValAs? _ "denominator")
    check (denominator > 0) "invalid saved price"
    let network := PrincipalNetwork.make p witnesses domain byteAxis numerator denominator
    let result ← ClosureFlow.solve network deadline
    let maximum ← ClosureFlow.maximumSource network result
    -- Restore the same original offers; compare every saved deterministic statistic.
    let lower := (PrincipalNetwork.offers p witnesses result.selected).reverse
    let upper := PrincipalNetwork.offers p witnesses maximum
    let axis := PrincipalNetwork.axis p byteAxis
    let charge := (nodes p lower).foldl (fun total node => total+axis node) 0
    let minimalReward := reward p witnesses result.selected
    let oldMatches := old.getObjValD "reward" == toJson minimalReward &&
      old.getObjValD "charge" == toJson charge && old.getObjValD "nodes" == toJson network.vertices &&
      old.getObjValD "arcs" == toJson network.arcs.size && old.getObjValD "phases" == toJson result.phases &&
      old.getObjValD "augmentations" == toJson result.augmentations
    check oldMatches "fixed-price minimum differs from the saved frontier"
    let boundary := feasible p lower && !feasible p upper
    if boundary then bands := bands.push ⟨index,network,result,maximum⟩
    bounds := bounds.push ⟨lower,upper⟩
    records := records.push (Json.mkObj [("index",toJson index),("axis",old.getObjValD "axis"),
      ("numerator",toJson numerator),("denominator",toJson denominator),("savedMinimumMatches",toJson oldMatches),
      ("lowerOffers",toJson (lower.map Fin.val)),("upperOffers",toJson (upper.map Fin.val)),
      ("lowerCost",toJson (cost p lower)),("upperCost",toJson (cost p upper)),
      ("lowerReward",toJson minimalReward),("upperReward",toJson (reward p witnesses maximum)),
      ("boundaryChosenWithoutLabels",toJson boundary),("bothFlowCutCertificates",toJson true),
      ("distinctVertices",toJson ((result.selected.zip maximum).filter fun (a,b) => a != b).size)])
  let allCutsMs := (← IO.monoMsNow)-started
  -- Original-coordinate restoration and human labels occur only after all
  -- price solves and the budget-only selection of boundary networks.
  let (source,rows) ← FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let families : Nat ← IO.ofExcept (data.getObjValAs? _ "families")
  let some basis := OriginalPayloadBasis.prepare families rows p | throw (IO.userError "original cost basis differs")
  let frozenTopics ← IO.ofExcept ((← read (project / "docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json")).getArr?)
  let frozen : AvailableDelivery.Frozen ← IO.ofExcept (fromJson? (frozenTopics[0]!.getObjValD "available"))
  let shown := fun selected =>
    let paid := Std.HashSet.ofList ((nodes p selected).map Fin.val)
    basis.sourceRows.filterMap fun (row,atom) =>
      if paid.contains atom.val then some (⟨row.key.file,row.key.line,row.key.line⟩ : Synapses.Range) else none
  let mut assessments := #[]
  for index in List.finRange bounds.size do
    let point := bounds[index]
    assessments := assessments.push (Json.mkObj [("index",toJson index.val),
      ("lower",toJson (AvailableDelivery.assess frozen (shown point.lower))),
      ("upper",toJson (AvailableDelivery.assess frozen (shown point.upper)))])
  let mut oracle := #[]
  for band in bands do
    for unit in frozen.units do
      for parts in unit.alternatives do
        let seeds := basis.sourceRows.filterMap fun (row,atom) =>
          if parts.any (fun range => range.file? == some row.key.file && range.first ≤ row.key.line && row.key.line ≤ range.last)
          then some (2+atom.val) else none
        let inside := !seeds.isEmpty && seeds.all (band.maximum[·]!)
        let mut detail := [("cutIndex",toJson band.index),("names",toJson unit.names),
          ("seedCount",toJson seeds.size),("allSeedNodesInsideUpper",toJson inside)]
        if inside then
          let extended ← ClosureFlow.extendSource band.network band.result seeds
          let selected := PrincipalNetwork.offers p witnesses extended
          let assessment := AvailableDelivery.assess ⟨#[unit],#[]⟩ (shown selected)
          detail := detail ++ [("sameOptimalCutValue",toJson true),("cost",toJson (cost p selected)),
            ("bothBudgetsFit",toJson (feasible p selected)),("originalOffersDeliverUnit",toJson (assessment.delivered == 1)),
            ("oracleOfferIds",toJson (selected.map Fin.val))]
        oracle := oracle.push (Json.mkObj detail)
  check ((← DB.PageMap.pin source.directory).head == source.head) "read-only diagnostic changed source"
  IO.FS.writeFile output (Json.mkObj [("priceCount",toJson saved.size),("cuts",toJson records),
    ("assessmentsAfterAllSolves",toJson assessments),("oracleUsesFrozenLabelsOnlyAfterSolves",toJson oracle),
    ("baseline",toJson (AvailableDelivery.assess frozen (shown baseline.selected))),
    ("allCutsMs",toJson allCutsMs),("includingRestoreAndOracleMs",toJson ((← IO.monoMsNow)-started)),
    ("exhaustiveExtremeAndExtensionFixtures",toJson fixtureCount),("sourceUnchanged",toJson true),
    ("allPricesWeightsCostsOffersLimitsUnchanged",toJson true),("boundaryCount",toJson bands.size),
    ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println s!"Fixed residual bounds: {saved.size} prices, {bands.size} budget-straddling bands"
