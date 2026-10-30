import tools.research.RecordClosedOffers
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

private def fixtureRows (file : File) : Array StoredRow :=
  #["","if (ready) {","  use();","}","","next();", ""].mapIdx fun position text =>
    ⟨⟨file,position+1⟩,text,#[⟨⟨"session","turn","call"⟩,
      ⟨String.ofList (List.replicate 64 'b'),"owner","work",position*8,position*8+8⟩⟩]⟩

private def fixtures : IO Unit := do
  let file : File := ⟨"source.txt",String.ofList (List.replicate 64 'a'),128⟩
  let rows := fixtureRows file
  let records := Records.prepare rows
  let (labels,domain) ← IO.ofExcept (CanonicalRecordDomain.compile rows records)
  let requested ← IO.ofExcept (SharedCoverage.Input.checkedIndices rows.size [2])
  let closed := domain.close requested
  check (closed.map Fin.val == [1,2,3]) "a body alias split a bounded original record"
  check ((domain.close closed).map Fin.val == closed.map Fin.val) "record closure is not idempotent"
  check (!(CanonicalRecordDomain.check rows records (List.range rows.size).toArray).isOk)
    "forged display labels split a checked record"
  check (!(CanonicalRecordDomain.check rows records (labels.push 99)).isOk)
    "display labels crossed their frozen original basis"
  let gap := rows.extract 2 4
  let (_,isolated) ← IO.ofExcept (CanonicalRecordDomain.compile gap (Records.prepare gap))
  let gapRequest ← IO.ofExcept (SharedCoverage.Input.checkedIndices gap.size [0])
  check ((isolated.close gapRequest).length == 1) "unobserved boundaries invented a full record"
  let other := fixtureRows {file with fingerprint := String.ofList (List.replicate 64 'c')}
  let both := rows ++ other
  let (_,separate) ← IO.ofExcept (CanonicalRecordDomain.compile both (Records.prepare both))
  let wanted ← IO.ofExcept (SharedCoverage.Input.checkedIndices both.size [2])
  check ((separate.close wanted).all (fun row => both[row].key.file == file))
    "identical text crossed an original fingerprint"
  let raw : SharedCoverage.Input.RawProblem := {
    costs := Array.replicate rows.size (4,4),weights := #[7,11],fixed := (0,0),limit := (8,20),
    offers := #[{closure := [2],covers := [0]},{closure := [1,2,3],covers := [1]}]}
  let prepared ← IO.ofExcept (RecordClosedOffers.prepare domain (List.range rows.size).toArray raw)
  let some a := prepared.problem.offers[0]? | throw (IO.userError "fixture lost proposal")
  let some b := prepared.problem.offers[1]? | throw (IO.userError "fixture lost alias")
  check (a.covers == b.covers && a.covers.contains 0 && a.covers.contains 1)
    "physical aliases lost an existing cue"
  let p ← IO.ofExcept prepared.problem.decode
  let some chosen := SharedCoverage.choose? p | throw (IO.userError "bounded record made empty selection infeasible")
  check ((SharedCoverage.nodes p chosen.selected).isEmpty) "a complete record bypassed its byte budget"

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh display-domain replay destination required")
  let out : System.FilePath := .mk destination
  check (!(← out.pathExists)) "preserve previous display replay"
  fixtures
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let previous := project / "docs/candidates/prepared-bindings/resumed"
  let receipt := previous / "cue-capture/receipts/43ba2a13af5aae5fc34557e5b8747cafce13fa0063d0da7356b09f43de8cd9ca"
  let data := (← read (receipt / "selection-plan.json")).getObjValD "data"
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (data.getObjValAs? _ "selectorInput")
  let p ← IO.ofExcept raw.decode
  let families ← IO.ofExcept (data.getObjValAs? Nat "families")
  let (source,rows) ← FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let some basis := OriginalPayloadBasis.prepare families rows p |
    throw (IO.userError "captured atoms differ from the original byte basis")
  let records := Records.prepare rows
  let (_,domain) ← IO.ofExcept (CanonicalRecordDomain.compile rows records)
  let started ← IO.monoMsNow
  let prepared ← IO.ofExcept (RecordClosedOffers.prepare domain (basis.sourceRows.map (·.2.val)) raw)
  let next ← IO.ofExcept prepared.problem.decode
  check (next.costs == p.costs && next.weights == p.weights && next.fixed == p.fixed &&
    next.limit == p.limit && next.offers.size == p.offers.size) "display closure changed values, costs, limits or proposal IDs"
  let some chosen := SharedCoverage.choose? next | throw (IO.userError "display closure rejected feasible empty selection")
  let solveAndBindMs := (← IO.monoMsNow)-started
  let prior : List Nat ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/selector-decisions.json")).getObjValAs? _ "selected")
  let priorIndices ← IO.ofExcept (SharedCoverage.Input.checkedIndices p.offers.size prior)
  let beforeNodes := Std.HashSet.ofList ((SharedCoverage.nodes p priorIndices).map Fin.val)
  let afterNodes := Std.HashSet.ofList ((SharedCoverage.nodes next chosen.selected).map Fin.val)
  -- Frozen human labels are read only after both selections are fixed.
  let frozenEntries ← IO.ofExcept ((← read (previous / "trial/frozen-before-delivery.json")).getArr?)
  let some entry := frozenEntries[0]? | throw (IO.userError "missing frozen topic")
  check (entry.getObjValD "topic" == toJson (1 : Nat)) "frozen topic order changed"
  let frozen : AvailableDelivery.Frozen ← IO.ofExcept (fromJson? (entry.getObjValD "available"))
  let shown := fun (nodes : Std.HashSet Nat) => basis.sourceRows.filterMap fun (row,atom) =>
    if nodes.contains atom.val then some (⟨row.key.file,row.key.line,row.key.line⟩ : Range) else none
  let baseline := AvailableDelivery.assess frozen (shown beforeNodes)
  let candidate := AvailableDelivery.assess frozen (shown afterNodes)
  check (baseline.eligible == 3 && baseline.delivered == 2) "baseline source-node audit disagrees with real delivery"
  let selectedRows := (List.finRange rows.size).filter fun index =>
    (basis.sourceRows[index.val]?).any (fun (_,atom) => afterNodes.contains atom.val)
  check (records.all (fun record => !record.indices.any selectedRows.contains || record.indices.all selectedRows.contains))
    "the final selected physical domain split a checked record"
  let after ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  check (source.head == after.head) "read-only replay changed original source"
  IO.FS.createDirAll out
  IO.FS.writeFile (out / "result.json") (Json.mkObj [("baseline",toJson baseline),("candidate",toJson candidate),
    ("plannedOriginalNodesOnly",toJson true),("actualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false),("sourceUnchanged",toJson true),
    ("sourceRows",toJson rows.size),("checkedRecords",toJson records.length),
    ("splitSelectedRecords",toJson (0 : Nat)),("physicalOfferClasses",toJson prepared.physicalClasses),
    ("extendedOffers",toJson prepared.extendedOffers),("solveAndBindMs",toJson solveAndBindMs),
    ("candidateCost",toJson (SharedCoverage.cost next chosen.selected)),
    ("valuesCostsLimitsAndProposalIdsUnchanged",toJson true),("independentFixturesPassed",toJson true)]).pretty
  IO.println s!"Closed display domain: {baseline.delivered}/{baseline.eligible} -> {candidate.delivered}/{candidate.eligible}; zero split records"
