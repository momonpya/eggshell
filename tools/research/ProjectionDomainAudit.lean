import tools.research.FrozenCanonicalBasis
import tools.research.ArtifactHash
import tools.research.NativeTrialAudit
import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "fresh domain audit directory required")
  let output : System.FilePath := .mk directory
  check (!(← output.pathExists)) "preserve projection domain audit"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let sourcePath := study / "r0/stage1/history/source.egg"
  let before ← Eggshell.Research.ArtifactHash.hex (sourcePath / "head")
  let (source,rows) ← Eggshell.Research.FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let pagesBefore ← Eggshell.Research.ArtifactHash.hex (DB.PageMap.dataPath source.directory source.head)
  let reader ← Persistence.Store.NodeReader.new source
  let entries ← Build.entries source
  let some canonical := CanonicalSource.Delivery.Part.check? rows | throw (IO.userError "missing canonical domain")
  let canonicalBody := canonical.render
  let mut originalBodies := #[]
  let mut populations := #[]
  let mut docs := #[]
  for entry in entries do
    let doc ← Build.document reader entry.id
    docs := docs.push doc
    if !doc.native then continue
    let edge ← reader.outcome (← reader.locateOutcome entry.id)
    let some raw := Matcher.atomText? edge.outcome | throw (IO.userError "native original is not text")
    if raw.isEmpty then continue
    let template : TransportSlice := {owner := some edge.relation,keys := [],text := "",members := [],visibleKeys := []}
    let family : SharedRangeAdapter.Family := {owner := edge,template,windows := []}
    let prepared := family.contextualOutputs
    let some envelope := prepared.template.context | throw (IO.userError "original context was not available")
    check (OriginalStructure.complete raw.length (OriginalStructure.prepare raw)) "original record domain is incomplete"
    let context := {envelope with fragments := [{first := 0,original := raw,decoded := false}]}
    originalBodies := originalBodies.push context.render
    let ownerRows := rows.filter fun row => row.origins.any (·.binding.owner == doc.owner)
    let mapped := ownerRows.flatMap fun row => row.origins.filterMap fun origin =>
      if origin.binding.owner == doc.owner then some (Range.original (ObservationContext.originalSubject doc.work raw)
        origin.binding.first origin.binding.limit) else none
    let observed := (Extraction.recordedRows source.head.identity doc).toOption.getD #[]
    let unmapped := observed.filter fun saved => saved.source.subject.file?.isNone && !covered saved.source mapped
    populations := populations.push (Json.mkObj [("owner",toJson doc.owner),("fileRows",toJson ownerRows.size),
      ("originalChars",toJson raw.length),("originalRecords",toJson observed.size),
      ("recordsNotFullyCoveredByFileAliases",toJson unmapped.size)])
  let originalBody := "\n".intercalate originalBodies.toList
  let aliases : Array Read := rows.flatMap fun row => row.origins.map fun origin =>
    ⟨origin.occurrence,⟨row.key.file,row.key.line,row.key.line⟩,origin.binding,#[]⟩
  let reads := aliases ++ docs.flatMap (fun doc => (Extraction.recordedRows source.head.identity doc).toOption.getD #[])
  let canonicalShown := Extraction.presented canonicalBody docs reads
  check (rows.all (fun row => covered ⟨row.key.file,row.key.line,row.key.line⟩ canonicalShown.ranges))
    "complete canonical renderer omitted a source row"
  let originalShown := Extraction.presented originalBody docs reads
  let originalInputs := docs.filter (·.native) |>.flatMap fun doc =>
    (Extraction.recordedRows source.head.identity doc).toOption.getD #[] |>.filter (·.source.subject.file?.isNone)
  check (originalInputs.all (fun row => covered row.source originalShown.ranges)) "complete original renderer omitted source records"
  IO.FS.createDirAll output
  let bodies := #[ ("canonical",canonicalBody),("original",originalBody) ]
  let mut sealedBodies := #[]
  for (name,body) in bodies do
    IO.FS.writeFile (output / (name ++ "-domain.txt")) body
    sealedBodies := sealedBodies.push (Json.mkObj [("population",toJson name),("chars",toJson body.length),
      ("sha256",toJson (Sha256.hex body.toUTF8)),("withinOriginalCharacterCap",toJson (decide (body.length ≤ 120000)))])
  IO.FS.writeFile (output / "before-gold.json") (Json.mkObj [
    ("source",toJson source.head),("canonicalRows",toJson rows.size),("owners",toJson populations),
    ("bodies",toJson sealedBodies),("populationRenderersChecked",toJson true)]).pretty
  let frozen ← IO.ofExcept ((← read (project / "docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json")).getArr?)
  let mut results := #[]
  for (name,body) in bodies do
    for topic in [1,2,3] do
      let some item := frozen[topic-1]? | throw (IO.userError "missing frozen references")
      let audit ← Eggshell.Research.NativeTrialAudit.replayAvailable (item.getObjValD "specification")
        (output / (name ++ "-domain.txt")).toString (Sha256.hex body.toUTF8)
      check (audit.getObjValD "availableEvidence" == item.getObjValD "available") "domain audit changed the frozen population"
      results := results.push (Json.mkObj [("population",toJson name),("topic",toJson topic),
        ("domainRepresentability",audit.getObjValD "availableDelivery")])
  check ((← Eggshell.Research.ArtifactHash.hex (sourcePath / "head")) == before &&
    (← Eggshell.Research.ArtifactHash.hex (DB.PageMap.dataPath source.directory source.head)) == pagesBefore)
    "projection audit changed source"
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("results",toJson results),("sourceUnchanged",toJson true),("actualHooks",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("unboundedPopulationTest",toJson true),("adopted",toJson false)]).pretty
  IO.println (toJson results).compress
