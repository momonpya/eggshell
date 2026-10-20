import Eggshell.Install

open Lean Eggshell Persistence

/-- Explicit experimental data import through the existing inspection codec.
No compatibility reader is added to hooks or ordinary storage. -/
def main (arguments : List String) : IO UInt32 := do
  let [sourcePath, targetPath] := arguments |
    throw (IO.userError "import_scale_graph LEGACY_GRAPH NEW_DATABASE")
  let source : System.FilePath := .mk sourcePath
  let target : System.FilePath := .mk targetPath
  unless source.isAbsolute && target.isAbsolute do throw (IO.userError "use absolute fixture paths")
  if ← target.pathExists then throw (IO.userError "the imported fixture must be new")
  let bytes ← FileSystem.boundedBytes source (16 * 1024 * 1024)
  let some text := String.fromUTF8? bytes | throw (IO.userError "legacy fixture is not UTF-8")
  let graph ← IO.ofExcept (Persistence.decode text)
  if let some parent := target.parent then IO.FS.createDirAll parent
  saveAtomic target graph
  let sourceHash := Sha256.hex bytes
  unless Sha256.hex (← FileSystem.boundedBytes source (16 * 1024 * 1024)) == sourceHash do
    throw (IO.userError "the original fixture changed during import")
  let snapshot ← DB.PageMap.pin target
  let restored ← Store.materialize snapshot
  unless restored.authority == graph.authority && restored.values == graph.values &&
      restored.unions.map (fun edge => (edge.edge.left, edge.edge.right)) ==
        graph.unions.map (fun edge => (edge.edge.left, edge.edge.right)) do
    throw (IO.userError "import changed an authoritative value, root order, union or Exact reference")
  let documents ← Store.searchDocuments snapshot
  let references := (documents.map (·.windows.length)).sum
  let unique := (Std.HashSet.ofList (documents.flatMap (·.windows))).size
  let maxWindows := (documents.map (·.windows.length)).foldl max 0
  IO.println (Json.mkObj [
    ("sourceSha256", toJson sourceHash), ("database", toJson target.toString),
    ("head", toJson snapshot.head), ("roots", toJson graph.values.length),
    ("rootBindings", toJson (← Store.rootDirectory snapshot)),
    ("unions", toJson graph.unions.length), ("documents", toJson documents.length),
    ("windowReferences", toJson references), ("uniqueWindows", toJson unique),
    ("maxOwnerWindows", toJson maxWindows), ("allValuesAndReferencesPreserved", toJson true)]).compress
  pure 0
