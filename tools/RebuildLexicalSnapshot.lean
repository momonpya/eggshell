import Eggshell.Install

open Lean Eggshell

/-- Offline benchmark preparation: compile this helper against the frozen public
implementation and republish the same authoritative values into a new private
DB. Its ordinary producer rebuilds complete public-readable lexical postings.
The source remains untouched; both compared implementations must receive copies
of the one resulting snapshot. This is not a compatibility path in the product. -/
def main (arguments : List String) : IO Unit := do
  let [sourceName, targetName] := arguments |
    throw (IO.userError "RebuildLexicalSnapshot SOURCE_DATABASE NEW_PRIVATE_DATABASE")
  let source : System.FilePath := .mk sourceName
  let target : System.FilePath := .mk targetName
  unless source.isAbsolute && target.isAbsolute && source.normalize != target.normalize do
    throw (IO.userError "source and new destination must be different absolute paths")
  if ← target.pathExists then throw (IO.userError "refusing to replace an existing snapshot")
  let original ← DB.PageMap.pin source
  let graph ← Persistence.Store.materialize original
  let beforeRoots ← Persistence.Store.rootIds original
  let beforeDocuments ← Persistence.Store.searchDocuments original
  if let some parent := target.parent then IO.FS.createDirAll parent
  Persistence.saveAtomic target graph
  let rebuilt ← DB.PageMap.pin target
  let restored ← Persistence.Store.materialize rebuilt
  let afterRoots ← Persistence.Store.rootIds rebuilt
  let afterDocuments ← Persistence.Store.searchDocuments rebuilt
  unless graph.authority == restored.authority && graph.values == restored.values &&
      graph.unions.map (fun edge => (edge.edge.left, edge.edge.right)) ==
        restored.unions.map (fun edge => (edge.edge.left, edge.edge.right)) do
    throw (IO.userError "rebuild changed authoritative values, root order, unions or Exact references")
  unless beforeRoots == afterRoots &&
      beforeDocuments.map (fun row => (row.owner, row.work, row.windows)) ==
        afterDocuments.map (fun row => (row.owner, row.work, row.windows)) do
    throw (IO.userError "rebuild changed stable root, owner, Work or window identities")
  unless (← DB.PageMap.pin source).head == original.head do
    throw (IO.userError "source publication changed during preparation")
  let postings ← ["driver", "Pdriver", "target", "Ptarget"].mapM fun term => do
    let (owners, count) ← Persistence.Store.searchPosting rebuilt term
    pure (Json.mkObj [("term", toJson term), ("owners", toJson owners), ("count", toJson count)])
  IO.println (Json.mkObj [
    ("source", toJson sourceName), ("destination", toJson targetName),
    ("sourceHead", toJson original.head), ("destinationHead", toJson rebuilt.head),
    ("authoritativeGraphEqual", toJson true), ("stableRootAndOwnerIds", toJson true),
    ("roots", toJson graph.values.length), ("documents", toJson afterDocuments.length),
    ("unions", toJson graph.unions.length), ("postings", toJson postings),
    ("generationModelCalls", toJson (0 : Nat)), ("productionAdoption", toJson false)]).compress
