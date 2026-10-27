import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def copy (source target : System.FilePath) : IO Unit := do
  unless ← source.pathExists do throw (IO.userError s!"missing evidence: {source}")
  IO.FS.createDirAll target.parent.get!
  let bytes ← IO.FS.readBinFile source
  if ← target.pathExists then
    unless (← IO.FS.readBinFile target) == bytes do throw (IO.userError "preserve prior evidence")
  else IO.FS.writeBinFile target bytes

def main (_args : List String) : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "quotation-context-20261027"
  let parent := base / "prepared-record-delivery-20261027"
  let output := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/quotation-context"
  IO.FS.createDirAll (output / "records")
  let mut guards := #[]
  for entry in ← root.readDir do
    if !entry.fileName.endsWith ".guard.json" then continue
    let value ← read entry.path
    unless (value.getObjValAs? String "state").toOption == some "finished" &&
        (value.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
      throw (IO.userError "candidate process still running")
    guards := guards.push (entry.fileName,value)
  IO.FS.writeFile (output / "records/guards.json") (toJson guards).pretty
  let files := #["Eggshell/QuotationContext.lean","Eggshell/ObservationContext.lean",
    "Eggshell/ObservedRecords.lean","Eggshell/ContentMetadata.lean","Eggshell/SynapseIndex.lean",
    "Eggshell/SynapticBindings.lean","Eggshell/SynapseTransport.lean"]
  let response ← IO.FS.readFile (root / "bindings-build/runtime.rsp")
  let mut patch := ""
  for file in files do
    let path := root / "checkout" / file
    let stem := file.replace "/" "_" |>.replace ".lean" ""
    let object := root / "bindings-build" / (stem ++ ".o")
    let stamp ← read (object.withExtension "source")
    let fields ← IO.ofExcept stamp.getArr?
    unless (fields[0]!.getStr?).toOption == some (← IO.FS.readFile path) &&
        (response.splitOn ((toJson object.toString).compress)).length == 2 &&
        (← (object.withExtension "dependencies").pathExists) do
      throw (IO.userError s!"source/object mismatch: {file}")
    for included in ← IO.ofExcept fields[1]!.getArr? do
      let (name,bytes) ← IO.ofExcept (fromJson? (α := String × String) included)
      unless bytes == (← IO.FS.readFile (path.parent.get! / name)) do
        throw (IO.userError s!"embedded source mismatch: {file}")
    let old := parent / "checkout" / file
    let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/" ++ file,"-L","b/" ++ file,
      (if ← old.pathExists then old.toString else "/dev/null"),path.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "exact changed candidate required")
    patch := patch ++ diff.stdout
  let renderer := root / "checkout/Eggshell/Handoff.lean"
  let prior := base / "bound-span-preparation-20261027/checkout/Eggshell/Handoff.lean"
  unless (← IO.FS.readFile renderer) == (← IO.FS.readFile prior) do
    throw (IO.userError "withdrawn frontier selector reintroduced")
  IO.FS.writeFile (output / "core.patch") patch
  IO.FS.writeFile (output / "records/link-boundary.json") (Json.mkObj [
    ("files",toJson files),("sourcesAndEmbeddedBytesExact",toJson true),("objectsSelectedInNativeAudit",toJson true),
    ("rendererRestoredFrom",toJson prior.toString),("fullProductBuilt",toJson false),
    ("parent",toJson parent.toString),("candidate",toJson root.toString),("adopted",toJson false)]).pretty
  for (name,destination) in #[
      ("mapped-records/result.json","synthetic-quotes.json"),
      ("c7-source-comparison/result.json","initial-source-comparison.json"),
      ("scoped-origin-contracts/result.json","direct-bindings.json"),
      ("c7-source-metadata/result.json","source-comparison.json")] do
    copy (root / name) (output / "records" / destination)
  for (name,stem) in #[ ("audit-build","tools_research_QuotationContextAudit"),
      ("bindings-build","tools_research_SynapticBindingAudit"),
      ("source-current-build","tools_research_QuotationSourceAudit")] do
    for ext in [".source","-lean.stdout"] do
      copy (root / name / (stem ++ ext)) (output / "records/contracts" / (stem ++ ext))
  copy (base / "synaptic-signal-audit-20261027/legacy-walk-summary.json") (output / "records/legacy-walk-summary.json")
  IO.FS.writeFile (output / "records/collection.json") (Json.mkObj [
    ("modelCalls",toJson (0 : Nat)),("fullWarmCalls",toJson (0 : Nat)),("actualHook",toJson false),
    ("deliveryRecallMeasured",toJson false),("adopted",toJson false)]).pretty
