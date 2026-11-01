import tools.SharedCoverageInput
import tools.research.FrozenCanonicalBasis
import tools.research.AvailableDelivery
import tools.research.ArtifactHash
import tools.research.SelectionReceipt
import tools.research.SelectionReceiptTests
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource
private def projectPath : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def field [FromJson α] (value : Json) (key : String) : IO α := IO.ofExcept (value.getObjValAs? α key)
private def cell [FromJson α] (row : Json) (index : Nat) : IO α := do
  let values ← IO.ofExcept row.getArr?
  let some value := values[index]? | throw (IO.userError "witness row is incomplete")
  IO.ofExcept (fromJson? value)

private structure Piece where
  family : Nat
  first : Nat
  last : Nat
  base : Nat
  total : Nat
  node : Option Nat
  deriving Inhabited

private def piece (value : Json) : IO Piece :=
  return ⟨← cell value 0,← cell value 1,← cell value 2,← cell value 3,← cell value 4,← cell value 5⟩

private structure Cue where
  priority : Nat
  first : Nat
  last : Nat
  deriving FromJson

private def coefficients (scale family : Nat) (cues : Array Cue) : Array (Cue × Nat) :=
  cues.map fun cue => (cue,scale/(61+family)+scale/(61+cue.priority))
private def value (first last : Nat) (cues : Array (Cue × Nat)) : Nat :=
  cues.foldl (fun best (cue,weight) => max best ((min last cue.last-max first cue.first)*weight)) 0
private def minimumPriority (first last : Nat) (cues : Array (Cue × Nat)) : Option Nat :=
  cues.foldl (fun found (cue,_) =>
    if min last cue.last ≤ max first cue.first then found else
    some (found.map (min cue.priority) |>.getD cue.priority)) none

private structure Captured where
  selection : Json
  witness : Json
  receipt : String

private def captured (trial actual : System.FilePath) : IO Captured := do
  let session : String ← field (← read (actual / "UserPromptSubmit/stdin")) "session_id"
  let mut matching : Array Captured := #[]
  for entry in ← (trial / "data/receipts").readDir do
    let request := entry.path / "request.json"
    let selection := entry.path / "selection-plan.json"
    if !(← request.pathExists) || !(← selection.pathExists) then continue
    let requested := (← read request).getObjValD "data"
    if requested.getObjValD "session" != toJson session || requested.getObjValD "event" != toJson "UserPromptSubmit" then continue
    let saved ← Receipt.readSelection entry.path
    check (saved.getObjValD "selectionWitness" != Json.null) "actual selector omitted its witness"
    matching := matching.push ⟨saved,saved.getObjValD "selectionWitness",entry.fileName⟩
  let #[found] := matching | throw (IO.userError "need exactly one completed prompt witness")
  return found

private def analyze (study records trial : System.FilePath) (topic : Nat) : IO Unit := do
  let actual := records / s!"hooks/candidate/audit/topic-{topic}"
  let saved ← captured trial actual
  let destination := records / s!"topic-{topic}"
  check (!(← destination.pathExists)) "preserve prior explanation"
  let raw : SharedCoverage.Input.RawProblem ← field saved.selection "selectorInput"
  let p ← IO.ofExcept raw.decode
  let selected : List Nat ← field saved.witness "compiledSelected"
  check (selected.eraseDups.length == selected.length) "duplicate chosen offer"
  let chosen ← IO.ofExcept (SharedCoverage.Input.checkedIndices p.offers.size selected)
  let replayStarted ← IO.monoMsNow
  let some replay := SharedCoverage.choose? p | throw (IO.userError "captured problem did not replay")
  let replay ← (← IO.mkRef replay).get
  let replayMs := (← IO.monoMsNow)-replayStarted
  check (replay.selected.map Fin.val == selected) "captured selection differs from exact offline replay"
  let paid := Std.HashSet.ofList ((SharedCoverage.nodes p chosen).map Fin.val)
  let coveredCues := Std.HashSet.ofList ((SharedCoverage.cues p chosen).map Fin.val)
  let cost := SharedCoverage.cost p chosen
  check (cost.1 ≤ p.limit.1 && cost.2 ≤ p.limit.2) "captured selection exceeds its two budgets"
  let sourceRows : Array (Option Nat × Key) ← field saved.witness "sourceNodes"
  let mut keys : Std.HashSet Key := {}
  let mut nodes : Std.HashMap Nat Key := {}
  for (id,key) in sourceRows do
    let some id := id | throw (IO.userError "source lacks its actual cost node")
    check (id < p.costs.size && !nodes.contains id && !keys.contains key) "source/cost-node binding is not injective"
    nodes := nodes.insert id key
    keys := keys.insert key
  let reified : Array (Option Nat) ← field saved.witness "selectedSourceNodes"
  let mut returned : Std.HashSet Nat := {}
  for item in reified do
    let some id := item | throw (IO.userError "returned original lost its cost-node binding")
    check (nodes.contains id && !returned.contains id) "returned original is foreign or duplicated"
    returned := returned.insert id
  check (nodes.toArray.all (fun (id,_) => paid.contains id == returned.contains id))
    "costed source rows differ from the actual selector response"
  let owners : Array String ← field saved.witness "owners"
  let rawPieces : Array Json ← field saved.witness "pieces"
  let pieces ← rawPieces.mapM piece
  let files : Array Json ← field saved.witness "files"
  let scale : Nat ← field saved.selection "scale"
  let mut weighted : Std.HashMap Nat (Array (Cue × Nat) × Array (Cue × Nat)) := {}
  for input in files do
    let family : Nat ← field input "family"
    let base : Array Cue ← field input "baseCues"
    let all : Array Cue ← field input "allCues"
    check (!weighted.contains family) "duplicate source family"
    weighted := weighted.insert family (coefficients scale family base,coefficients scale family all)
  let mut sourceCues : Std.HashMap Nat Nat := {}
  let mut producers : Std.HashMap Nat (List Json) := {}
  let mut byFamily : Std.HashMap Nat (List Nat) := {}
  let mut cueIds := #[]
  let mut weights : Array (Nat × Nat) := #[]
  for position in [:pieces.size] do
    let item := pieces[position]!
    byFamily := byFamily.insert item.family (position :: byFamily[item.family]?.getD [])
    check (item.family < owners.size && item.first < item.last && item.base ≤ item.total) "invalid captured relevance cell"
    let id := item.node.bind (sourceCues[·]?) |>.getD weights.size
    if id == weights.size then
      weights := weights.push (item.base,item.total)
      if let some node := item.node then
        check (nodes.contains node) "relevance cell names a foreign original"
        sourceCues := sourceCues.insert node id
    else weights := weights.modify id fun prior => (max prior.1 item.base,max prior.2 item.total)
    cueIds := cueIds.push id
    if let some _ := item.node then
      let some (base,all) := weighted[item.family]? |
        throw (IO.userError "source cell has no original family")
      let expected := value item.first item.last base
      check (expected == item.base && max expected (value item.first item.last all) == item.total)
        "captured weight differs from the actual ranked original cues"
      if let some node := item.node then
        producers := producers.insert node ((Json.mkObj [("family",toJson item.family),
          ("owner",toJson owners[item.family]?),("first",toJson item.first),("last",toJson item.last),
          ("bestBasePriority",toJson (minimumPriority item.first item.last base)),
          ("bestAnyPriority",toJson (minimumPriority item.first item.last all))]) :: producers[node]?.getD [])
  check (weights.size*2 ≤ p.weights.size) "compiled problem lost relevance cells"
  for index in [:weights.size] do
    let pair := weights[index]!
    check (p.weights[index*2]? == some pair.1 && p.weights[index*2+1]? == some (pair.2-pair.1))
      "global cue aggregation differs from compiled weights"
  let units : Array Json ← field saved.witness "units"
  let mut genericUnits : Array (Nat × List (Nat × Nat) × Nat) := #[]
  check (units.size ≤ p.offers.size) "compiled selector lost base candidates"
  for index in [:units.size] do
    let unit := units[index]!
    let family : Nat ← cell unit 0
    let ranges : List (Nat × Nat) ← cell unit 1
    let payloads : Array (Option Nat) ← cell unit 2
    let original : Option Nat ← cell unit 3
    check (family < owners.size) "candidate has a foreign owner"
    if original.isSome then genericUnits := genericUnits.push (family,ranges,index)
    let some offer := p.offers[index]? | throw (IO.userError "missing compiled base offer")
    for payload in payloads do
      let some payload := payload | throw (IO.userError "unit lost an original source key")
      check (offer.closure.any (·.val == payload)) "candidate claims a source row it does not pay for"
    for index in byFamily[family]?.getD [] do
      let item := pieces[index]!
      if item.family != family || item.base == 0 || !ranges.any (fun (a,b) => a ≤ item.first && item.last ≤ b) then continue
      check (offer.covers.any (·.val == cueIds[index]!*2)) "candidate omitted a positive original cue"
  let (source,basis) ← Eggshell.Research.FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let known := Std.HashSet.ofArray (basis.map (·.key))
  let admitted := Std.HashSet.ofArray owners
  let eligibleBasis := basis.filter fun row => row.origins.any (fun origin => admitted.contains origin.binding.owner)
  let outsideCanonical := eligibleBasis.filter fun row => !keys.contains row.key
  let presentation ← read (actual / "original-presentation.json")
  let shown : Array Range ← field presentation "ranges"
  let bodySeal ← read (actual / "before-gold.json")
  check (bodySeal.getObjValD "goldRead" == toJson false && bodySeal.getObjValD "bodySha256" ==
    toJson (← Eggshell.Research.ArtifactHash.hex (actual / "body.txt"))) "actual body differs from its pre-gold seal"
  let mut offering : Std.HashMap Nat (List Nat) := {}
  let mut remaining : Array (Nat × Bool) := #[]
  for index in [:raw.offers.size] do
    let some offer := raw.offers[index]? | throw (IO.userError "missing captured offer")
    let closure := (hashDistinct offer.closure)
    for node in closure do
      if nodes.contains node then offering := offering.insert node (index :: offering[node]?.getD [])
    let extra := closure.foldl (fun total node => if paid.contains node then total else
      (total.1+raw.costs[node]!.1,total.2+raw.costs[node]!.2)) (0,0)
    let gain := (hashDistinct offer.covers).foldl (fun total cue =>
      if coveredCues.contains cue then total else total+raw.weights[cue]!) 0
    remaining := remaining.push (gain,decide (cost.1+extra.1 ≤ p.limit.1 && cost.2+extra.2 ≤ p.limit.2))
  let mut explanations := #[]
  let mut withNoUnit := 0
  let mut withNoPositiveBase := 0
  let mut unbackedCredit := 0
  for (node,key) in nodes.toArray.qsort (fun a b => a.1 < b.1) do
    let offers := (offering[node]?.getD []).reverse.toArray
    let baseCue := (sourceCues[node]?).map (·*2)
    let positive := baseCue.any (fun cue => (p.weights[cue]?).any (0 < ·))
    let credited := baseCue.any coveredCues.contains
    let observed := covered ⟨key.file,key.line,key.line⟩ shown
    if offers.isEmpty then withNoUnit := withNoUnit+1
    if !positive then withNoPositiveBase := withNoPositiveBase+1
    if positive && credited && known.contains key && !observed then unbackedCredit := unbackedCredit+1
    explanations := explanations.push (Json.mkObj [("node",toJson node),("source",toJson key),
      ("candidateOffers",toJson offers),("hasPositiveBaseCue",toJson positive),("baseCue",toJson baseCue),
      ("scaledBaseWeight",toJson (baseCue.bind (p.weights[·]?))),("producers",toJson (producers[node]?.getD [])),
      ("baseCueCredited",toJson credited),("sourcePayloadPaid",toJson (paid.contains node)),
      ("independentBasisKnown",toJson (known.contains key)),("actualFileRangeShown",toJson observed),
      ("offersWithUncoveredGain",toJson (offers.countP fun offer => 0 < remaining[offer]!.1)),
      ("positiveOffersFittingFinalBudget",toJson (offers.countP fun offer => 0 < remaining[offer]!.1 && remaining[offer]!.2))])
  -- Generic explanation is sealed before the evaluator opens the gold list.
  let decisions := (toJson explanations).compress
  IO.FS.createDirAll destination
  IO.FS.writeFile (destination / "source-decisions.json") decisions
  IO.FS.writeFile (destination / "before-gold.json") (Json.mkObj [
    ("source",toJson source.head),("bodySha256",bodySeal.getObjValD "bodySha256"),
    ("relevanceCellsChecked",toJson pieces.size),("costNodesChecked",toJson nodes.size),
    ("offersChecked",toJson raw.offers.size),("cost",toJson cost),
    ("exactChoiceReplayed",toJson true),("offlineChooseMs",toJson replayMs),
    ("sourceResponseMatchesPaidNodes",toJson true),("cueWeightsAndPositiveMembershipChecked",toJson true),
    ("sourcesWithNoCandidate",toJson withNoUnit),("sourcesWithNoPositiveBase",toJson withNoPositiveBase),
    ("knownRowsFromAdmittedOwners",toJson eligibleBasis.size),
    ("knownRowsOutsideCanonicalCandidateDomain",toJson outsideCanonical.size),
    ("creditedKnownSourcesWithoutActualFileWitness",toJson unbackedCredit),
    ("goldRead",toJson false),("decisionsSha256",toJson (Sha256.hex decisions.toUTF8)),
    ("receipt",toJson saved.receipt)]).pretty
  let frozen ← IO.ofExcept ((← read (projectPath / "docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json")).getArr?)
  let some frozen := frozen[topic-1]? | throw (IO.userError "missing frozen topic")
  let available : Eggshell.Research.AvailableDelivery.Frozen ← field frozen "available"
  let mut requirements := #[]
  for requirement in available.units do
    let fileRanges := requirement.alternatives.filterMap fun parts =>
      if parts.all (fun part => part.subject.file?.isSome) then some parts else none
    let targetNodes := nodes.toArray.filter fun (_,key) => fileRanges.any fun parts => parts.any fun part =>
      part.subject.file? == some key.file && part.first ≤ key.line && key.line ≤ part.last
    let domainGaps := outsideCanonical.filter fun row => fileRanges.any fun parts => parts.any fun part =>
      part.subject.file? == some row.key.file && part.first ≤ row.key.line && row.key.line ≤ part.last
    let gaps := domainGaps.map fun row => Json.mkObj [("source",toJson row.key),
      ("originalBindings",toJson row.origins),
      ("coveringSingleGenericUnits",toJson (genericUnits.filterMap fun (family,ranges,index) =>
        if row.origins.any (fun origin => owners[family]? == some origin.binding.owner &&
            ranges.any (fun (first,last) => first ≤ origin.binding.first && origin.binding.limit ≤ last)) then some index else none)),
      ("multipleGenericUnitsNotRuledOut",toJson true)]
    let rows := explanations.filter fun entry => targetNodes.any fun (node,_) =>
      (entry.getObjValAs? Nat "node").toOption == some node
    requirements := requirements.push (Json.mkObj [("names",toJson requirement.names),
      ("fileOriginalNodes",toJson rows),("outsideCanonicalDomain",toJson gaps),
      ("fileAlternativeAbsentIsUnknown",toJson fileRanges.isEmpty)])
  IO.FS.writeFile (destination / "requirements.json") (toJson requirements).pretty
  IO.println s!"Topic {topic}: {nodes.size} original nodes; unsupported paid credit {unbackedCredit}"

def main (args : List String) : IO Unit := do
  if args == ["selftest"] then return ← Eggshell.Research.SelectionReceiptTests.run
  let [destination,trial,topicText] := args | throw (IO.userError "records directory, trial and completed topic required")
  let some topic := topicText.toNat? | throw (IO.userError "invalid completed topic")
  check ([1,2,3].contains topic) "outside frozen topics"
  analyze "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028" (.mk destination)
    (.mk trial) topic
