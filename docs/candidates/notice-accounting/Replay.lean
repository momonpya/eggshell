import tools.research.OriginalPayloadBasis
import tools.research.OriginalEvidence
import tools.SharedCoverageInput
import tools.VerifiedWinnerCoverage
import Eggshell.ContentMetadata
import Eggshell.Handoff
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (value : Bool) (reason : String) : IO Unit :=
  unless value do throw (IO.userError reason)

private def savedRows (study root : System.FilePath) : IO (DB.PageMap.Snapshot × Array StoredRow × Array String) := do
  let source ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  let baseline ← read (study / "seed-originals.json")
  check (baseline.getObjValD "sourceHead" == toJson source.head) "original source changed"
  let initial : Array StoredRow ← IO.ofExcept (baseline.getObjValAs? _ "canonicalRows")
  let extras : Array (Nat × String × ContentCapture.Supplement) ← IO.ofExcept
    ((← read (root / "anchored-capture/seed-refinement.json")).getObjValAs? _ "supplements")
  let byId := Std.HashMap.ofArray (extras.map fun (id,owner,extra) => (id,(owner,extra)))
  let reader ← Persistence.Store.NodeReader.new source
  let mut additions := #[]
  let mut owners := #[]
  for entry in ← Build.entries source do
    let doc ← Build.document reader entry.id
    owners := owners.push doc.owner
    if let some parent ← ContentMetadata.load? source entry.id doc then
      if let some (owner,extra) := byId[entry.id]? then
        check (owner == doc.owner) "supplement owner changed"
        if extra.sealed then
          let catalog ← IO.ofExcept (ContentMetadata.catalogSupplement source.head.identity doc parent extra)
          for located in catalog.located do
            let some file := located.read.source.file? | throw (IO.userError "source coordinates lost")
            let origins := doc.occurrences.map fun occurrence => (⟨occurrence,located.read.binding⟩ : Origin)
            additions := additions.push ⟨⟨file,located.read.source.first⟩,located.text,origins⟩
  let rows ← IO.ofExcept (Delivery.merge (initial ++ additions))
  check (rows.size == 8276 && owners.size == 38) "saved candidate domain changed"
  return (source,rows,owners)

/-- Infer only ownership constraints implied by original one-family payloads.
Ambiguous families remain sets; they never choose a guessed representative. -/
private def familyCandidates (p : SharedCoverage.Problem) (families : Nat)
    (rows : Array (StoredRow × Fin p.costs.size)) (owners : Array String) : Array (Array String) := Id.run do
  let source := Std.HashMap.ofArray (rows.map fun (row,node) => (node,row))
  let mut found := Array.replicate families owners
  for offer in p.offers do
    if !offer.covers.all (fun cue => cue.val%2 == 0) then continue
    let family := (hashDistinct offer.closure).filter (·.val < families)
    let [family] := family | continue
    for node in offer.closure do
      if let some row := source[node]? then
        let witnesses := row.origins.map (·.binding.owner)
        found := found.modify family.val (·.filter witnesses.contains)
  for _ in [:families] do
    let fixed := found.filterMap fun candidates => if candidates.size == 1 then candidates[0]? else none
    found := found.map fun candidates => if candidates.size == 1 then candidates else
      candidates.filter (!fixed.contains ·)
  return found

private def rowReserve (owner : String) : Nat × Nat :=
  let yes := Plugin.ownerStatusDescription owner true
  let no := Plugin.ownerStatusDescription owner false true
  (max yes.length no.length,max yes.utf8ByteSize no.utf8ByteSize)

private def attributed (p : SharedCoverage.Problem) (families : Nat)
    (rows : Array (StoredRow × Fin p.costs.size)) (candidates : Array (Array String)) :
    Option SharedCoverage.Problem := do
  let owners := hashDistinct (rows.toList.flatMap fun (row,_) => row.origins.toList.map (·.binding.owner)) |>.toArray
  let extra := owners.map rowReserve
  let reserve := extra.foldl (fun sum cost => (sum.1+cost.1,sum.2+cost.2)) (0,0)
  unless reserve.1 ≤ p.fixed.1 && reserve.2 ≤ p.fixed.2 do none
  let mut incidence : Std.HashMap (Fin p.costs.size) (Array String) := {}
  for (row,node) in rows do incidence := incidence.insert node (row.origins.map (·.binding.owner))
  let sourceAtoms := Std.HashSet.ofArray (rows.map Prod.snd)
  let sourceValues := Std.HashSet.ofArray (rows.map (fun (_,node) => node.val))
  let frames := Std.HashSet.ofList (rows.toList.filterMap fun (_,node) =>
    if sourceValues.contains (node.val-1) then none
    else some (node.val-1))
  for offer in p.offers do
    if !offer.covers.all (fun cue => cue.val%2 == 0) then continue
    let [family] := (hashDistinct offer.closure).filter (·.val < families) | continue
    let associated := candidates[family.val]?.getD owners
    for node in offer.closure do
      if node.val < families || sourceAtoms.contains node || frames.contains node.val then continue
      let previous := incidence[node]?.getD #[]
      incidence := incidence.insert node (hashDistinct (previous.toList ++ associated.toList)).toArray
  let costs := p.costs ++ extra
  let offers ← p.offers.mapM fun offer => do
    let original ← offer.closure.mapM fun node => if h : node.val < costs.size then some (⟨node.val,h⟩ : Fin costs.size) else none
    let needed := offer.closure.flatMap fun node =>
      let associated := incidence[node]?.getD (if node.val < families || frames.contains node.val then #[] else owners)
      associated.toList.filterMap fun owner => owners.findIdx? (· == owner)
    let notices ← (hashDistinct needed).mapM fun index =>
      if h : p.costs.size+index < costs.size then some (⟨p.costs.size+index,h⟩ : Fin costs.size) else none
    return ({closure := original ++ notices,covers := offer.covers} : SharedCoverage.Offer costs.size p.weights.size)
  return {
    costs := costs
    weights := p.weights
    offers := offers
    fixed := (p.fixed.1-reserve.1,p.fixed.2-reserve.2)
    limit := p.limit}

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "NoticeCostReplay NEW-OUTPUT")
  check (!(← System.FilePath.pathExists destination)) "preserve previous replay"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let (snapshot,rows,owners) ← savedRows study root
  let data := (← read (project / "docs/candidates/anchored-capture/selector.json")).getObjValD "data"
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (data.getObjValAs? _ "selectorInput")
  let p ← IO.ofExcept raw.decode
  let families ← IO.ofExcept (data.getObjValAs? Nat "families")
  let some basis := Research.OriginalPayloadBasis.prepare families rows p | throw (IO.userError "cost basis changed")
  let candidates := familyCandidates p families basis.sourceRows owners
  check (candidates.all (!·.isEmpty)) "ownership constraints are inconsistent; do not guess"
  let some original := SharedCoverage.choose? p | throw (IO.userError "baseline did not fit")
  check (original.selected.length == 741 && SharedCoverage.cost p original.selected == (120000,120002)) "baseline replay changed"
  let oldPaid := Std.HashSet.ofList ((SharedCoverage.nodes p original.selected).map (·.val))
  let some changed := attributed p families basis.sourceRows candidates | throw (IO.userError "notice accounting failed")
  let some selected := SharedCoverage.choose? changed | throw (IO.userError "attributed selection did not fit")
  let paid := Std.HashSet.ofList ((SharedCoverage.nodes changed selected.selected).map (·.val))
  -- Independent control: navigation cannot reserve bytes ahead of evidence.
  -- This is the previously unmeasurable late-catalog hypothesis, not a new
  -- scoring rule. No fitted metadata model is used in this control.
  let catalog := Delivery.locators rows
  let actual ← IO.FS.readFile (project / "docs/candidates/anchored-capture/hook/body.txt")
  check (!catalog.isEmpty && (actual.splitOn catalog).length == 2 &&
    catalog.length ≤ p.fixed.1 && catalog.utf8ByteSize ≤ p.fixed.2) "catalog is not the exact fixed displayed inventory"
  let withoutCatalog := {p with fixed := (p.fixed.1-catalog.length,p.fixed.2-catalog.utf8ByteSize)}
  let some optional := SharedCoverage.choose? withoutCatalog | throw (IO.userError "late catalog control did not fit")
  let optionalPaid := Std.HashSet.ofList ((SharedCoverage.nodes withoutCatalog optional.selected).map (·.val))
  let familyPricing := (List.range families).toArray.map fun family => Id.run do
    let offers := p.offers.filter fun offer =>
      let declaredFamilies := (hashDistinct offer.closure).filter (·.val < families)
      declaredFamilies.length == 1 && declaredFamilies.any (·.val == family) && offer.covers.all (fun cue => cue.val%2 == 0)
    let positive := offers.filter fun offer => offer.covers.any (fun cue => 0 < p.weights[cue])
    let weight := positive.foldl (fun result offer => max result
      ((hashDistinct offer.covers).foldl (fun sum cue => sum+p.weights[cue]) 0)) 0
    return Json.mkObj [("family",toJson family),("possibleOwners",toJson candidates[family]?),
      ("frameCost",toJson p.costs[family]?),("offers",toJson offers.size),
      ("positiveOffers",toJson positive.size),("maximumOfferValue",toJson weight),
      ("setupSelected",toJson (oldPaid.contains family))]
  -- Human labels are opened only after all decisions, never supplied to fitting.
  let required : Array Research.OriginalEvidence.Reference ← IO.ofExcept
    (((← read (study / "all-citations-audit-input.json")).getObjValD "source").getObjValAs? _ "required")
  let checks := required.map fun target =>
    let wanted := basis.sourceRows.filter fun (row,_) => row.key.file.relative == target.path &&
      target.first ≤ row.key.line && row.key.line ≤ target.last
    Json.mkObj [("reference",toJson target),("indexed",toJson wanted.size),
      ("priorSelected",toJson (wanted.countP fun (_,atom) => oldPaid.contains atom.val)),
      ("selected",toJson (wanted.countP fun (_,atom) => paid.contains atom.val)),
      ("lateCatalogSelected",toJson (wanted.countP fun (_,atom) => optionalPaid.contains atom.val))]
  let fragment := basis.sourceRows.filter fun (row,_) => row.key.file.relative == "clang/lib/Driver/Driver.cpp" && row.key.line == 3097
  check ((← DB.PageMap.pin snapshot.directory).head == snapshot.head) "read-only replay changed the source"
  let result := Json.mkObj [("ownershipCandidates",toJson candidates),("familyPricing",toJson familyPricing),("priorFixed",toJson p.fixed),
    ("attributedFixed",toJson changed.fixed),("notices",toJson (changed.costs.size-p.costs.size)),
    ("newCosts",toJson (SharedCoverage.cost changed selected.selected)),("selectedOffers",toJson selected.selected.length),
    ("partialSelected",toJson (fragment.all fun (_,atom) => paid.contains atom.val)),("indexedRangeDiagnostics",toJson checks),
    ("catalogChars",toJson catalog.length),("catalogBytes",toJson catalog.utf8ByteSize),
    ("lateCatalogFixed",toJson withoutCatalog.fixed),("lateCatalogCosts",toJson (SharedCoverage.cost withoutCatalog optional.selected)),
    ("lateCatalogOffers",toJson optional.selected.length),
    ("lateCatalogPartialSelected",toJson (fragment.all fun (_,atom) => optionalPaid.contains atom.val)),
    ("actualHookMeasured",toJson false),("accountingUpperBoundVerified",toJson false),
    ("sourceUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]
  IO.FS.writeFile destination result.pretty
  IO.println (Json.mkObj [("priorFixed",toJson p.fixed),("attributedFixed",toJson changed.fixed),
    ("partialSelected",result.getObjValD "partialSelected"),("selectedOffers",toJson selected.selected.length),
    ("lateCatalogPartialSelected",result.getObjValD "lateCatalogPartialSelected"),
    ("lateCatalogOffers",toJson optional.selected.length)]).compress
