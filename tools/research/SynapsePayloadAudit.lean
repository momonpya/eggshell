import Eggshell.SynapseBuild
import Eggshell.SynapseUsage

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction

private def audit (source : DB.PageMap.Snapshot) (bodies : Array String) : IO Json := do
  let reader ← Persistence.Store.NodeReader.new source
  let mut documents := #[]
  let mut rows : Array Read := #[]
  let mut payloads : Std.HashMap Range (Std.HashSet String) := {}
  for entry in ← Build.entries source do
    let doc ← Provenance.document reader entry.id
    if !doc.native then continue
    let .ok reads := recordedRows source.head.identity doc | continue
    let some raw := doc.source | continue
    let .ok decoded := layout raw | continue
    documents := documents.push doc
    rows := rows ++ reads
    let coordinates := reads.foldl (fun known row =>
      known.insert (row.binding.first, row.binding.limit) row.source)
      ({} : Std.HashMap (Nat × Nat) Range)
    for line in textLines decoded.text do
      let some (_, text) := numbered line.text | continue
      let some first := decoded.offsets[line.first]? | continue
      let some limit := decoded.offsets[line.limit]? | continue
      let some range := coordinates[(first,limit)]? | continue
      payloads := payloads.insert range (payloads[range]?.getD {} |>.insert text)
  let stored := rows.foldl (fun known row => known.insert row.source) ({} : Std.HashSet Range)
  let conflicts := payloads.fold (fun count _ texts => if texts.size > 1 then count+1 else count) 0
  let derived ← Provenance.derive source
  let consumed := derived.graph.snapshot.filterMap fun fact => match fact with
    | .consumed edge => some edge | _ => none
  let frequencies := consumed.foldl (fun counts edge =>
    counts.insert (edge.kind,edge.term) ((counts[(edge.kind,edge.term)]?.getD 0)+1))
    ({} : Std.HashMap (WitnessKind × String) Nat)
  let top := frequencies.toArray.qsort (fun a b =>
    a.2 > b.2 || (a.2 == b.2 && (toJson a.1).compress < (toJson b.1).compress))
  let numeric := consumed.filter (fun edge => !edge.term.isEmpty && edge.term.toList.all Char.isDigit)
  let sessions := bodies.map fun body => Id.run do
    let shown := presented body documents rows
    let unique := shown.ranges.foldl (fun known range => known.insert range) ({} : Std.HashSet Range)
    let mut owners : Std.HashMap Range (Std.HashSet String) := {}
    -- A validated row can be shared in the canonical domain. Keep all
    -- original bindings; this audit does not merge or certify the owners.
    for row in rows do
      owners := owners.insert row.source (owners[row.source]?.getD {} |>.insert row.binding.owner)
    let crossOwner := unique.fold (fun count range =>
      if (owners[range]?.getD {}).size > 1 then count+1 else count) 0
    return Json.mkObj [("bodySha256", toJson (Sha256.hex body.toUTF8)),
      ("verifiedRowOccurrences", toJson shown.ranges.size), ("distinctOriginalRows", toJson unique.size),
      ("repeatedRowOccurrences", toJson (shown.ranges.size-unique.size)),
      ("rowsStoredUnderMultipleOwners", toJson crossOwner), ("uncertainFiles", toJson shown.uncertain.size)]
  return Json.mkObj [("nativeOwners", toJson documents.size), ("storedRows", toJson rows.size),
    ("distinctStoredRows", toJson stored.size), ("conflictingCanonicalRows", toJson conflicts),
    ("consumptionFacts", toJson consumed.size), ("numericWitnessFacts", toJson numeric.size),
    ("mostFrequentWitnesses", toJson (top.extract 0 12)),
    ("sessions", toJson sessions)]

/-- Measurement only: no question, oracle, model, source writer or selector. -/
def main (args : List String) : IO Unit := do
  let [specification, directory, destination] := args |
    throw (IO.userError "SynapsePayloadAudit FROZEN-SPEC SIX-BODY-ROOT OUTPUT")
  let cases ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk specification)) >>= Json.getArr?)
  let mut results := #[]
  for row in cases do
    let stage ← IO.ofExcept (row.getObjValAs? Nat "stage")
    let source := System.FilePath.mk (← IO.ofExcept (row.getObjValAs? String "source"))
    let files ← IO.ofExcept (row.getObjValAs? (Array (String × String)) "files")
    for (name, expected) in files do
      unless Sha256.hex (← IO.FS.readBinFile (source / name)) == expected do
        throw (IO.userError "frozen source changed before payload audit")
    let mut bodies := #[]
    for index in [:2] do
      bodies := bodies.push (← IO.FS.readFile (System.FilePath.mk directory /
        s!"stage{stage}" / s!"native-{index}" / "body.txt"))
    results := results.push ((← audit (← DB.PageMap.pin source) bodies).setObjVal! "stage" (toJson stage))
  IO.FS.writeFile (.mk destination) (toJson results).compress
  IO.println (toJson results).compress
