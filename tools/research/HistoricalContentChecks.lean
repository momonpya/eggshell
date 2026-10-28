import Eggshell.ContentMetadata
import Eggshell.SynapseBuild
import Eggshell.Persistence
open Lean Eggshell Eggshell.Synapses

private def check (yes : Bool) (message : String) : IO Unit :=
  unless yes do throw (IO.userError message)

private def putHeader (source : DB.PageMap.Snapshot) (id : Nat) (header : ContentMetadata.Header) : IO DB.PageMap.Snapshot := do
  let _ ← DB.PageMap.withWriter source fun writer => do
    let payload ← IO.ofExcept (MetadataBytes.checked (toJson header).compress.toUTF8)
    let _ ← MetadataBytes.put writer (ContentMetadata.ownerKey id) payload
    pure ()
  DB.PageMap.pin source.directory

private def reject (action : IO α) : IO Unit := do
  let failed ← try let _ ← action; pure false catch _ => pure true
  check failed "invalid historical correspondence was accepted"

#print axioms ContentMetadata.Header.bound_original
#print axioms ContentMetadata.Header.producer_is_provenance

def main (args : List String) : IO Unit := do
  let [directory,history] := args | throw (IO.userError "HistoricalContentChecks NEW-DIRECTORY SOURCE")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "new metadata trial required"
  IO.FS.createDir root
  let raw := "alpha_token();\n"
  IO.FS.writeFile (root / "source.cpp") raw
  let acquired ← ContentCapture.captureInputs root (Json.mkObj [("path",toJson "source.cpp")]) none
    ((← IO.monoMsNow)+10000)
  let captured ← ContentCapture.finish root acquired raw ((← IO.monoMsNow)+10000)
  check (captured.complete && !captured.aliases.isEmpty) "fixture has no literal correspondence"
  let doc : Extraction.Document := {
    owner := "v1",work := "v2",workText := some "source.cpp",source := some raw,native := true
    occurrences := #[⟨"session","turn","call"⟩],files := #[]}
  let source ← Persistence.ensureSnapshot (root / "source.egg")
  let _ ← DB.PageMap.withWriter source fun writer => do
    let _ ← ContentMetadata.stage writer 7 doc captured
    pure ()
  let current ← DB.PageMap.pin source.directory
  let some payload ← MetadataBytes.get? current (ContentMetadata.ownerKey 7) |
    throw (IO.userError "fixture omitted captured metadata")
  let header ← ObservedRecords.decode (α := ContentMetadata.Header) payload.bytes
  let old := Sha256.hex "historical extractor producer".toUTF8
  check (old != ContentCapture.implementation) "historical producer equals current extractor"
  let historical := {header with implementation := old}
  let snapshot ← putHeader current 7 historical
  let some loaded ← ContentMetadata.load? snapshot 7 doc | throw (IO.userError "producer change erased original coordinates")
  check (loaded.implementation == old && loaded.aliases == captured.aliases)
    "historical producer or literal projections changed"
  let catalog ← IO.ofExcept (ContentMetadata.catalog snapshot.head.identity doc loaded)
  check (catalog.located.size == captured.aliases.size && catalog.located.all (·.text == "alpha_token();"))
    "historical code differs from actual original bytes"
  for changed in #[
      {historical with database := Sha256.hex "foreign DB".toUTF8},
      {historical with owner := "v999"}, {historical with work := "v999"},
      {historical with original := Sha256.hex "different original".toUTF8},
      {historical with implementation := "not-a-producer-digest"},
      {historical with aliases := historical.aliases+1}] do
    let altered ← putHeader (← DB.PageMap.pin source.directory) 7 changed
    reject (ContentMetadata.load? altered 7 doc)
  let restored ← putHeader (← DB.PageMap.pin source.directory) 7 historical
  reject (ContentMetadata.load? restored 7 {doc with native := false})
  reject (ContentMetadata.load? restored 7 {doc with source := some "changed output"})
  let before ← DB.PageMap.pin (.mk history)
  let reader ← Persistence.Store.NodeReader.new before
  let mut oldHeaders := 0
  let mut originalAliases := 0
  for entry in ← Build.entries before do
    let document ← Build.document reader entry.id
    if let some original ← ContentMetadata.load? before entry.id document then
      oldHeaders := oldHeaders+1
      originalAliases := originalAliases+original.aliases.size
  check (oldHeaders > 0 && originalAliases > 0) "fixed seed lost every historical correspondence"
  check ((← DB.PageMap.pin (.mk history)).head == before.head) "read-only seed check wrote to source"
  let report := Json.mkObj [("historicalProducerPreserved",toJson true),("literalAliasesEqual",toJson true),
    ("mutationsRejected",toJson (8 : Nat)),("seedHeaders",toJson oldHeaders),("seedAliases",toJson originalAliases),
    ("sourceUnchanged",toJson true),("authorityAdded",toJson false),("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress
