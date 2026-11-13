import Eggshell.SynapseBuild
import Eggshell.ContentMetadata
import Lean.Data.Json.Parser

open Lean Eggshell Eggshell.Synapses
namespace ContentLocationAudit
def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)
def run (database output : String) : IO Unit := do
  check (!(← System.FilePath.pathExists output)) "preserve the earlier source-location audit"
  let source ← DB.PageMap.pin (.mk database)
  let reader ← Persistence.Store.NodeReader.new source
  let mut reports := #[]
  for entry in ← Build.entries source do
    let doc ← Build.document reader entry.id
    if !doc.native then continue
    let recorded ← ContentMetadata.load? source entry.id doc
    let fallback := Extraction.recordedReads source.head.identity doc
    let report : Json ← match recorded with
      | none => pure Json.null
      | some captured => do
        let catalog ← IO.ofExcept (ContentMetadata.catalog source.head.identity doc captured)
        pure <| Json.mkObj [("producer",toJson captured.implementation),("complete",toJson captured.complete),
          ("failure",toJson captured.failure),("inputs",toJson captured.inputs),
          ("aliases",toJson captured.aliases.size),("located",toJson catalog.located.size)]
    reports := reports.push (Json.mkObj [("id",toJson entry.id),("owner",toJson doc.owner),
      ("work",toJson doc.work),("invocation",toJson doc.workText),
      ("sourceCharacters",toJson (doc.source.map String.length)),("documentFiles",toJson doc.files),
      ("metadata",report),("fallbackReads",toJson (fallback.toOption.map Array.size)),
      ("fallbackFailure",toJson (match fallback with | .ok _ => none | .error reason => some reason))])
  check ((← DB.PageMap.pin source.directory).head == source.head) "read-only source audit changed the publication"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("documents",toJson reports),
    ("sourceUnchanged",toJson true),("queryOrModelCalled",toJson false),("adopted",toJson false)]).compress
end ContentLocationAudit
def main : List String → IO Unit
  | [database,output] => ContentLocationAudit.run database output
  | _ => throw (IO.userError "ContentLocationAudit DATABASE NEW-OUTPUT")
