import Eggshell.SynapseTransport
import Eggshell.SynapseBuild

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction

private structure Requirement where
  name : String
  path : String
  first : Nat
  last : Nat
  originalOwners : Array String
  deriving FromJson

private structure CaseRow where
  stage : Nat
  source : String
  files : Array (String × String)
  required : Array Requirement
  deriving FromJson

private structure OfferRow where
  source : Range
  priority : Nat
  kind : String
  evidence : String
  deriving FromJson

private def audit (row : CaseRow) (directory : System.FilePath) : IO Json := do
  let path := System.FilePath.mk row.source
  for (name, expected) in row.files do
    unless Sha256.hex (← IO.FS.readBinFile (path / name)) == expected do
      throw (IO.userError "frozen source changed")
  let source ← DB.PageMap.pin path
  let reader ← Persistence.Store.NodeReader.new source
  let mut documents := #[]
  let mut answers : Array Document := #[]
  let mut rows : Array Read := #[]
  for entry in ← Build.entries source do
    let document ← Build.document reader entry.id
    if !document.native then answers := answers.push document
    let .ok found := recordedRows source.head.identity document | continue
    documents := documents.push document
    rows := rows ++ found
  let files := rows.foldl (fun found read => found.insert read.source.file) ({} : Std.HashSet File)
  let citations := answers.flatMap fun answer =>
    let parsed := (answer.source.bind fun text => (layout text).toOption).map fun decoded =>
      paragraphCitations decoded.text files.toArray
    (parsed.getD #[]).map fun cited => (answer.owner,cited)
  let stage := directory / s!"stage{row.stage}"
  let mut receipts := #[]
  for file in ← (stage / "data" / "receipts").readDir do
    let path := file.path / "synaptic-delivery.json"
    if ← path.pathExists then
      receipts := receipts.push (← IO.ofExcept (Json.parse (← IO.FS.readFile path)))
  let mut sessions := #[]
  for index in [:2] do
    let body ← IO.FS.readFile (stage / s!"native-{index}" / "body.txt")
    let shown := presented body documents rows
    -- Both independent requests use the same frozen graph. Require receipts
    -- to agree, rather than picking whichever contains the desired offer.
    let payloads ← receipts.mapM fun receipt => IO.ofExcept (receipt.getObjVal? "data")
    unless payloads.size == 2 && payloads[0]? == payloads[1]? do
      throw (IO.userError "independent synaptic plans differ")
    let payload := payloads[0]!
    let raw ← IO.ofExcept (payload.getObjValAs? (Array Json) "offers")
    let offers ← raw.mapM fun item => IO.ofExcept (item.getObjVal? "offer" >>= fromJson? (α := OfferRow))
    let located := offers.map fun offer =>
      let matching := rows.filter (offer.source.contains ·.source)
      Json.mkObj [("offer", toJson offer.evidence), ("kind", toJson offer.kind),
        ("source", toJson offer.source), ("priority", toJson offer.priority),
        ("originalRows", toJson matching.size),
        ("originalOwners", toJson ((matching.map (·.binding.owner)).toList.eraseDups)),
        ("completeOriginalRange", toJson (covered offer.source (matching.map (·.source))))]
    let requirements := row.required.map fun requirement => Id.run do
      let original := rows.filter fun read =>
        requirement.originalOwners.contains read.binding.owner && read.source.file.relative == requirement.path
      let files := original.foldl (fun found read => found.insert read.source.file) ({} : Std.HashSet File)
      let stored := files.toArray.any fun file => covered ⟨file, requirement.first, requirement.last⟩ (original.map (·.source))
      let actual := files.toArray.any fun file => covered ⟨file, requirement.first, requirement.last⟩ shown.ranges
      let graph := files.toArray.any fun file => covered ⟨file, requirement.first, requirement.last⟩ (offers.map (·.source))
      let cited := citations.filterMap fun (answer,citation) =>
        if files.contains citation.file && citation.first ≤ requirement.first && requirement.last ≤ citation.last then
          some (Json.mkObj [("answer", toJson answer), ("citation", toJson citation),
            ("wholeCitationStored", toJson (covered citation (rows.map (·.source))))])
        else none
      let details := (List.range (requirement.last+1-requirement.first)).toArray.map fun offset => Id.run do
        let number := requirement.first+offset
        let matching := offers.filter fun offer => offer.source.file.relative == requirement.path &&
          files.contains offer.source.file && offer.source.first ≤ number && number ≤ offer.source.last
        return Json.mkObj [("line", toJson number),
          ("bodyDelivered", toJson (files.toArray.any fun file => covered ⟨file,number,number⟩ shown.ranges)),
          ("hints", toJson (matching.map fun offer => Json.mkObj [
            ("kind", toJson offer.kind), ("priority", toJson offer.priority),
            ("first", toJson offer.source.first), ("last", toJson offer.source.last)]))]
      return Json.mkObj [("name", toJson requirement.name), ("stored", toJson stored),
        ("graphReached", toJson graph), ("bodyDelivered", toJson actual),
        ("storedAnswerCitations", toJson cited), ("rows", toJson details)]
    sessions := sessions.push (Json.mkObj [("bodySha256", toJson (Sha256.hex body.toUTF8)),
      ("requirements", toJson requirements), ("locatedOffers", toJson located)])
  return Json.mkObj [("stage", toJson row.stage), ("sessions", toJson sessions)]

/-- Read-only diagnosis of an already frozen delivery. Human requirements
are applied only to the recorded output; no selector or extractor receives them. -/
def main (arguments : List String) : IO Unit := do
  let [specification, directory, destination] := arguments |
    throw (IO.userError "SynapsePathAudit FROZEN-SPEC NATIVE-ROOT OUTPUT")
  let cases ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk specification)) >>= fromJson? (α := Array CaseRow))
  let results ← cases.mapM fun row => audit row (.mk directory)
  IO.FS.writeFile (.mk destination) (toJson results).compress
  for result in results do
    let sessions ← IO.ofExcept (result.getObjValAs? (Array Json) "sessions")
    IO.println (Json.mkObj [("stage", (result.getObjVal? "stage").toOption.getD .null),
      ("requirements", (sessions[0]!.getObjVal? "requirements").toOption.getD .null)]).compress
