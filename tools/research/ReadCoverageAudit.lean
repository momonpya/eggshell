import Eggshell.SynapseBuild
import tools.research.StudyRuntime

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction Eggshell.Research

private structure Requirement where
  name : String
  path : String
  first : Nat
  last : Nat
  deriving FromJson, ToJson

private structure Topic where
  topic : Nat
  referenceRanges : Array Requirement
  deriving FromJson

private def sourceLines (workspace : System.FilePath) (file : File) : IO (Array String) := do
  unless file.valid do throw (IO.userError "invalid source identity")
  let bytes ← FileSystem.boundedBytes (workspace / file.relative) (16*1024*1024)
  let mut root := Blake3.digest "eggshell.source.file".toUTF8 [Blake3.u64le bytes.size]
  for page in [:((bytes.size+4095)/4096)] do
    root := SourceEvidence.pageRoot root (bytes.extract (page*4096) (min bytes.size ((page+1)*4096)))
  unless bytes.size == file.bytes && Blake3.hex root == file.fingerprint do
    throw (IO.userError s!"source fingerprint differs: {file.relative}")
  let some text := String.fromUTF8? bytes | throw (IO.userError "source is not UTF-8")
  return (text.splitOn "\n").toArray

/-- Inspect every stored native read form before any topic handoff. Unsupported
coordinates remain explicit; a saved response is not labelled absent. -/
def main (args : List String) : IO Unit := do
  let [database,workspace,definitions,report] := args |
    throw (IO.userError "ReadCoverageAudit DATABASE WORKSPACE TASK-DEFINITIONS NEW-REPORT")
  let output := System.FilePath.mk report
  unless !(← output.pathExists) do throw (IO.userError "keep the existing read audit")
  let source ← DB.PageMap.pin (.mk database)
  let before ← StudyRuntime.files source.directory
  let reader ← Persistence.Store.NodeReader.new source
  let mut documents := #[]
  let mut total := 0
  let mut unsupported := 0
  let mut rows := 0
  let mut allRows : Array Read := #[]
  let mut sourceFiles : Std.HashMap File (Array String) := {}
  let mut mismatches : Array Json := #[]
  let mut payloads : Std.HashMap Range (Std.HashSet String) := {}
  let mut nativeText : Array (String × String) := #[]
  for entry in ← Build.entries source do
    let doc ← Build.document reader entry.id
    if !doc.native then continue
    total := total+1
    let command : Except String String := match doc.workText with
      | none => .error "missing work"
      | some work => workCommand work
    let plans := command >>= fun command => readPlans command doc.files
    let located := recordedRows source.head.identity doc
    if plans.toOption.isNone then unsupported := unsupported+1
    let found := located.toOption.getD #[]
    if let .ok decoded := layout (doc.source.getD "") then
      nativeText := nativeText.push (doc.owner,"\n".intercalate (decoded.text.splitOn "\n" |>.map fun line =>
        (numbered line).map (·.2) |>.getD line))
    rows := rows+found.size
    allRows := allRows ++ found
    let mut identities : Array String := #[]
    if !found.isEmpty then
      let decoded ← IO.ofExcept (layout (doc.source.getD ""))
      let coordinates := found.foldl (fun known row =>
        known.insert (row.binding.first,row.binding.limit) row)
        ({} : Std.HashMap (Nat × Nat) Read)
      for line in textLines decoded.text do
        let some row := coordinates[(decoded.offsets[line.first]!,decoded.offsets[line.limit]!)]? | continue
        let some (number,code) := numbered line.text | throw (IO.userError "located row has no number")
        unless number == row.source.first && number == row.source.last && row.valid do
          throw (IO.userError "invalid original row coordinates")
        let expected ← match sourceFiles[row.source.file]? with
          | some lines => pure lines
          | none => do
            let lines ← sourceLines (.mk workspace) row.source.file
            sourceFiles := sourceFiles.insert row.source.file lines
            pure lines
        if expected[number-1]? != some code then
          mismatches := mismatches.push (Json.mkObj [("row",toJson row),("observed",toJson code),
            ("expected",toJson expected[number-1]?)])
        payloads := payloads.insert row.source (payloads[row.source]?.getD {} |>.insert code)
        identities := identities.push (Sha256.hex ((Json.mkObj [
          ("row",toJson row),("code",toJson code)]).compress.toUTF8))
      unless identities.size == found.size do throw (IO.userError "not every original row was checked")
    documents := documents.push (Json.mkObj [
      ("owner",toJson doc.owner),("occurrences",toJson doc.occurrences),("command",toJson command.toOption),
      ("planError",toJson (match plans with | .ok _ => none | .error message => some message)),
      ("recordedRows",toJson found.size),("rowIdentities",toJson identities)])
  let topics ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk definitions)) >>= fromJson? (α := Array Topic))
  let availability := topics.map fun topic => Json.mkObj [
    ("topic",toJson topic.topic),("requirements",toJson (topic.referenceRanges.map fun requirement => Id.run do
      let candidates := allRows.filter fun row => row.source.file.relative == requirement.path &&
        row.source.first ≤ requirement.last && requirement.first ≤ row.source.last
      let files := candidates.foldl (fun found row => found.insert row.source.file) ({} : Std.HashSet File)
      let located := files.toArray.any fun file => covered ⟨file,requirement.first,requirement.last⟩ (candidates.map (·.source))
      let literalOwners := sourceFiles.toArray.filterMap fun (file,lines) => do
        if file.relative != requirement.path || requirement.first == 0 ||
            requirement.last < requirement.first || lines.size < requirement.last then none else
          let snippet := "\n".intercalate (lines.extract (requirement.first-1) requirement.last).toList
          some (nativeText.filterMap fun (owner,text) => if !snippet.isEmpty &&
            (text.splitOn snippet).length > 1 then some owner else none)
      return Json.mkObj [("reference",toJson requirement),("locatedOriginal",toJson located),
        ("literalSnippetSearchAvailable",toJson (!literalOwners.isEmpty)),
        ("literalSnippetNativeOwners",toJson literalOwners.flatten)]))]
  let conflicts := payloads.fold (fun count _ variants => if variants.size > 1 then count+1 else count) 0
  unless (← StudyRuntime.files source.directory) == before do throw (IO.userError "read audit changed the source")
  IO.FS.writeFile output ((Json.mkObj [("database",toJson database),("nativeDocuments",toJson total),
    ("unsupportedReadForms",toJson unsupported),("recordedRows",toJson rows),("documents",toJson documents),
    ("verifiedSourceFiles",toJson sourceFiles.keysArray),("payloadMismatches",toJson mismatches),
    ("conflictingCanonicalRows",toJson conflicts),("availability",toJson availability),
    ("taskDefinitionsSha256",toJson (← ArtifactHash.hex (.mk definitions))),
    ("publicationUnchanged",toJson true),("handoffBodiesRead",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat))]).compress ++ "\n")
  unless mismatches.isEmpty && conflicts == 0 do throw (IO.userError "source coordinate or payload disagreement")
