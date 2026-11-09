import tools.research.ReplayReadinessChecks
import tools.research.MemoryCapacity
import tools.research.NativeTrialAudit
import tools.research.ObjectCensus
open Lean Eggshell Eggshell.Synapses DB

def checkField (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

def main (args : List String) : IO Unit := do
  let [project,output] := args | throw (IO.userError "original-project output required")
  let root : System.FilePath := .mk output
  checkField (!(← root.pathExists)) "preserve actual metadata field measurements"
  IO.FS.createDirAll root
  let source ← PageMap.pin (.mk project)
  let mut found : Option PageMap.Snapshot := none
  for storage in [Sidecar.Storage.database,.user] do
    let path ← CanonicalSource.Cache.directory source storage
    let some ready ← CanonicalSource.Cache.open? source storage | continue
    let some snapshot ← CanonicalSource.Cache.preparedAt? source path ready.metadata | continue
    found := some snapshot
    break
  let some snapshot := found | throw (IO.userError "existing canonical preparation required")
  let documents ← Persistence.Store.searchDocuments source
  checkField (documents.length == 40) "fixed forty-owner metadata domain changed"
  let mut rows : Array Json := #[]
  for document in documents do
    let original ← Persistence.Store.readLocatedOutcome source
      (← Persistence.Store.locateOutcome source document.owner)
    let owner := Persistence.selectionKey original.relation
    let ready ← PreparedSourceView.readOwner snapshot source.head.identity owner
    let data : List (String × Json) ← pure [
      ("ready",← Research.ObjectCensus.inspect ready),
      ("descriptor",← Research.ObjectCensus.inspect ready.stored.descriptor),
      ("rowRefs",← Research.ObjectCensus.inspect ready.rows),
      ("units",← Research.ObjectCensus.inspect ready.units),
      ("wireJson",← Research.ObjectCensus.inspect ready.json),
      ("wordDictionary",← Research.ObjectCensus.inspect (ready.focus.map (·.stored.dictionary))),
      ("decodedTermRows",← Research.ObjectCensus.inspect (ready.focus.map (·.rows))),
      ("identifierRows",← Research.ObjectCensus.inspect (ready.focus.map (·.stored.identifierRows)))]
    rows := rows.push (Json.mkObj [("owner",toJson owner),("fields",Json.mkObj data)])
  IO.FS.writeFile (root/"result.json") (Json.mkObj [("source",toJson source.head),
    ("recipes",toJson snapshot.head),("owners",toJson rows.size),("rows",toJson rows),
    ("queryOrModelCalls",toJson (0 : Nat)),("separateReadOnlyComponent",toJson true),
    ("rootUnionOrActualCrossRequestSharing",toJson false)]).compress
