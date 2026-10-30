import tools.research.StablePacketCompletion
import tools.research.OriginalPayloadBasis
import Eggshell.ContentMetadata
import Eggshell.SynapseBuild
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource
open Eggshell.Research.StablePacketCompletion

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

/- Restore the same immutable original basis as SelectionCauseAudit. This is
not warm, a new seed, a provider call or an inferred dependency. -/
private def originals (study root : System.FilePath) : IO (DB.PageMap.Snapshot × Array StoredRow) := do
  let source ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  let initial ← read (study / "seed-originals.json")
  check (initial.getObjValD "sourceHead" == toJson source.head) "original source changed"
  let rows : Array StoredRow ← IO.ofExcept (initial.getObjValAs? _ "canonicalRows")
  let refinement ← read (root / "anchored-capture/seed-refinement.json")
  check (refinement.getObjValD "source" == toJson source.head) "supplement source changed"
  let extras : Array (Nat × String × ContentCapture.Supplement) ←
    IO.ofExcept (refinement.getObjValAs? _ "supplements")
  let byId := Std.HashMap.ofArray (extras.map fun (id,owner,extra) => (id,(owner,extra)))
  let reader ← Persistence.Store.NodeReader.new source
  let mut additions := #[]
  for entry in ← Build.entries source do
    let some (owner,extra) := byId[entry.id]? | continue
    let doc ← Build.document reader entry.id
    check (owner == doc.owner) "supplement owner changed"
    let some parent ← ContentMetadata.load? source entry.id doc | continue
    unless extra.sealed do continue
    let catalog ← IO.ofExcept (ContentMetadata.catalogSupplement source.head.identity doc parent extra)
    for located in catalog.located do
      let some file := located.read.source.file? | throw (IO.userError "supplement lost original coordinates")
      let origins := doc.occurrences.map fun occurrence => (⟨occurrence,located.read.binding⟩ : Origin)
      additions := additions.push ⟨⟨file,located.read.source.first⟩,located.text,origins⟩
  let result ← IO.ofExcept (Delivery.merge (rows ++ additions))
  check (result.size == 8276) "original payload basis changed"
  return (source,result)

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh isolated replay destination required")
  let out : System.FilePath := .mk destination
  check (!(← out.pathExists)) "preserve previous replay"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let capture := project / "docs/candidates/prepared-bindings/resumed/cue-capture"
  let receipt := capture / "receipts/43ba2a13af5aae5fc34557e5b8747cafce13fa0063d0da7356b09f43de8cd9ca"
  let started ← IO.monoMsNow
  let (source,rows) ← originals study (study / "shared-snapshot")
  let captured := (← read (receipt / "selection-plan.json")).getObjValD "data"
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (captured.getObjValAs? _ "selectorInput")
  let p ← IO.ofExcept raw.decode
  let families ← IO.ofExcept (captured.getObjValAs? Nat "families")
  let some basis := Eggshell.Research.OriginalPayloadBasis.prepare families rows p |
    throw (IO.userError "original rows disagree with actual selector cost atoms")
  let baseline ← read (project / "docs/candidates/read-signal-trace/selector-decisions.json")
  check (baseline.getObjValD "sameProductionSequence" == toJson true) "unverified selection sequence"
  let prior : List Nat ← IO.ofExcept (baseline.getObjValAs? _ "selected")
  let indices ← IO.ofExcept (SharedCoverage.Input.checkedIndices p.offers.size prior)
  check (SharedCoverage.cost p indices == (120000,120002)) "captured original selection cost changed"
  let paid := Std.HashSet.ofList (SharedCoverage.nodes p indices)
  let beforeRows := basis.sourceRows.filterMap fun (row,atom) => if paid.contains atom then some row else none
  let some beforePart := Delivery.Part.check? beforeRows | throw (IO.userError "empty original shared packet")
  let oldPart := beforePart.render
  let body ← IO.FS.readFile (capture.parent.get! / "trial/baseline/rep-0/topic-1/body.txt")
  check ((body.splitOn oldPart).length == 2) "restored original packet differs from actual hook body"
  let inputMs := (← IO.monoMsNow)-started
  let solveStarted ← IO.monoMsNow
  let sourceRows := basis.sourceRows.map fun (row,atom) => (row,atom.val)
  let tailRaw := residual raw prior sourceRows beforeRows (body.length,body.utf8ByteSize)
  let tailProblem ← IO.ofExcept tailRaw.decode
  let some tail := SharedCoverage.choose? tailProblem | throw (IO.userError "actual original body exceeds limit")
  let tailNodes := Std.HashSet.ofList ((SharedCoverage.nodes tailProblem tail.selected).map (·.val))
  let existing := Std.HashSet.ofArray (beforeRows.map (·.key))
  let added := sourceRows.filterMap fun (row,atom) =>
    if tailNodes.contains atom && !existing.contains row.key then some row else none
  let solveMs := (← IO.monoMsNow)-solveStarted
  let finalStarted ← IO.monoMsNow
  let afterRows ← IO.ofExcept (Delivery.merge (extendRows beforeRows added))
  let afterByKey := Std.HashMap.ofArray (afterRows.map fun row => (row.key,row))
  check (beforeRows.all fun row => afterByKey[row.key]? == some row) "accepted original data/provenance changed"
  let known := references beforeRows
  check (added.all (eligible known)) "added row requires another provenance shell"
  let some sample := beforeRows[0]? | throw (IO.userError "missing eligibility test input")
  let some origin := sample.origins[0]? | throw (IO.userError "missing original provenance")
  check (eligible known sample) "accepted original provenance became ineligible"
  let foreignDb := {origin with binding := {origin.binding with database := "foreign-database"}}
  let foreignOwner := {origin with binding := {origin.binding with owner := origin.binding.owner ++ ":foreign"}}
  let foreignOccurrence := {origin with occurrence := {origin.occurrence with useId := origin.occurrence.useId ++ ":foreign"}}
  for changed in [foreignDb,foreignOwner,foreignOccurrence] do
    check (!eligible known {sample with origins := #[changed]}) "foreign provenance was accepted"
  let changedFile := {sample.key.file with fingerprint := "different-content"}
  check (!eligible known {sample with key := {sample.key with file := changedFile}}) "different file bytes were accepted"
  let files := (Std.HashSet.ofArray (beforeRows.map (·.key.file))).toArray
  for file in files do
    let old := Packet.fileFrame file (beforeRows.filter (·.key.file == file))
    let next := Packet.fileFrame file (afterRows.filter (·.key.file == file))
    check (old.leading == next.leading && old.trailing == next.trailing) "file/provenance shell changed"
  let some afterPart := Delivery.Part.check? afterRows | throw (IO.userError "completion lost shared packet")
  check (beforePart.owners.all afterPart.owners.contains && afterPart.owners.all beforePart.owners.contains)
    "completion changed graph owners"
  let finalBody := body.replace oldPart afterPart.render
  check (finalBody.length ≤ raw.limit.1 && finalBody.utf8ByteSize ≤ raw.limit.2) "counterfactual body exceeds wire limit"
  let payloadCost := added.foldl (fun total row =>
    let text := Packet.rowText row
    (total.1+text.length,total.2+text.utf8ByteSize)) (0,0)
  check (finalBody.length == body.length+payloadCost.1 &&
    finalBody.utf8ByteSize == body.utf8ByteSize+payloadCost.2) "new cost contains unexpected shell changes"
  let ended ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  check (source.head == ended.head) "original DB changed during read-only replay"
  IO.FS.createDirAll out
  IO.FS.writeFile (out / "counterfactual-body.txt") finalBody
  IO.FS.writeFile (out / "result.json") (Json.mkObj [
    ("actualHookDelivery",toJson false),("actualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false),
    ("sourceUnchanged",toJson true),("sourceRows",toJson rows.size),
    ("beforeRows",toJson beforeRows.size),("addedRows",toJson added.size),
    ("beforeWireCost",toJson (body.length,body.utf8ByteSize)),
    ("afterWireCost",toJson (finalBody.length,finalBody.utf8ByteSize)),
    ("allAcceptedRowsAndOriginsRetained",toJson true),("allProvenanceFramesUnchanged",toJson true),
    ("graphOwnersUnchanged",toJson true),("newPhysicalPayload",toJson payloadCost),
    ("foreignDatabaseOwnerOccurrenceAndFingerprintRejected",toJson true),
    ("inputMs",toJson inputMs),("solveMs",toJson solveMs),
    ("materializeAndVerifyMs",toJson ((← IO.monoMsNow)-finalStarted)),
    ("added",toJson (added.map fun row => (row.key,Packet.rowText row))) ]).pretty
  IO.println s!"Preserved {beforeRows.size} original rows; added {added.size} provenance-stable rows within the same wire limit"
