module
import all Eggshell.Handoff
import Eggshell.SearchProvider
public meta import Lean

open Lean Eggshell

run_meta do
  let environment ← getEnv
  let some declaration := environment.find? ``Plugin.computeAutomaticHandoff |
    throwError "missing automatic handoff entry"
  let some body := declaration.value? | throwError "missing automatic handoff implementation"
  unless body.getUsedConstants.contains ``SemanticMatcher.projectCommand do
    throwError "automatic handoff does not bind the selected project"

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def options (scratch : System.FilePath) : SearchProvider.Options :=
  {cache := scratch / "sources",queryTemporary := some (scratch / "queries"),models := scratch / "models"}

private def projectOptions (scratch database : System.FilePath) : IO SearchProvider.Options := do
  let command := SemanticMatcher.projectCommand ["egg","search-provider"] (some database)
  let configured ← IO.ofExcept (SearchProvider.parse (options scratch) (command.drop 2))
  SearchProvider.queryOptions configured

public def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "new output directory required")
  let root := System.FilePath.mk destination
  check root.isAbsolute "output must be absolute"
  check (!(← root.pathExists)) "output already exists"
  let privateRoot ← Paths.dataRoot
  check (privateRoot == root / "private") "audit requires an isolated private data root"
  IO.FS.createDirAll root
  let a ← DB.PageMap.create (root / "project-a.egg") "project-a"
  let b ← DB.PageMap.create (root / "project-b.egg") "project-b"
  let imported ← DB.PageMap.create (root / "read-only.egg") "read-only"
  let config : Config.Config := {
    source := root / "config.toml",semanticMatcher := some ["egg","search-provider"],
    eggs := [{name := "a",path := a.directory},{name := "b",path := b.directory},
      {name := "imported",path := imported.directory}],
    profiles := [
      {name := "a",read := ["imported","b"],write := some "a"},
      {name := "b",read := ["imported","a"],write := some "b"},
      {name := "reader",read := ["imported","a","b"]}]}
  let selected ← IO.ofExcept (Config.resolve config "a")
  check (selected.write.map (·.path) == some a.directory) "selection lost the active writer"
  let some writer := selected.write | throw (IO.userError "fixture has no selected writer")
  check (selected.read.head?.map (·.path) == some imported.directory) "fixture did not put a reader first"
  let base := options (root / "temporary")
  let sourceRequest := Json.mkObj [("cache",toJson (DB.Sidecar.Owner.ofSnapshot imported))]
  let readerOptions ← SearchProvider.cacheOptions base sourceRequest
  check (readerOptions.owner == some (DB.Sidecar.Owner.ofSnapshot imported)) "reader cache changed DB"
  let first ← projectOptions (root / "temporary") writer.path
  let second ← projectOptions (root / "temporary") b.directory
  let again ← projectOptions (root / "another-chat") a.directory
  let expected := privateRoot / "read-cache" / a.head.identity / "queries"
  check (first.cache == expected && again.cache == first.cache) "project cache did not survive a new chat"
  check (first.cache != second.cache) "different project query caches were combined"
  check (first.owner.isNone && first.privateWrite.isNone && first.fallback.isNone)
    "query inherited a shared DB write or cross-project fallback"
  let query := "same query in different projects"
  let vector := Json.arr #[toJson (Array.replicate 384 (1 : Nat))]
  let coverage : SearchProvider.EncodingCoverage := {
    characters := query.length,visibleCharacters := query.length,
    tokenizerMappedCharacters := query.length,embeddedCharacters := query.length,
    sourceTokens := 8,segments := 1,contextTokens := 128,overlapTokens := 16,
    completeTokenOffsets := true}
  SearchProvider.saveVector first query vector coverage
  check (← SearchProvider.readVector again query).isSome "new chat missed its own project query vector"
  check (← SearchProvider.readVector second query).isNone "query cache leaked across projects"
  let reader ← IO.ofExcept (Config.resolve config "reader")
  let transientCommand := SemanticMatcher.projectCommand
    ["egg","search-provider","--query-db",a.directory.toString] (reader.write.map (·.path))
  let transient ← SearchProvider.queryOptions (← IO.ofExcept
    (SearchProvider.parse base (transientCommand.drop 2)))
  check (transient.cache == root / "temporary" / "queries") "reader selected a shared or first-readable DB"
  check (SemanticMatcher.projectCommand ["custom","--flag"] (some a.directory) == ["custom","--flag"])
    "custom provider arguments were changed"
  let relative := SearchProvider.parse base ["--query-db","relative.egg"]
  check (!relative.isOk) "relative DB namespace was accepted"
  let missingRejected ← try
      let _ ← projectOptions (root / "temporary") (root / "missing.egg")
      pure false
    catch _ => pure true
  check missingRejected "missing project DB fell back to another project's cache"
  for source in [a,b,imported] do
    let after ← DB.PageMap.pin source.directory
    check (after.head == source.head) "query caching published to a project DB"
    check (!(← (source.directory / "derived").pathExists)) "query caching created a shared DB sidecar"
  check (!(← (privateRoot / "queries").pathExists)) "unscoped user query cache was recreated"
  let report := Json.mkObj [
    ("selectedWriterOnly",toJson true),("firstReadableDbNotUsed",toJson true),
    ("privateProjectNamespaces",toJson true),("crossChatHit",toJson true),
    ("crossProjectMiss",toJson true),("readerUsesTemporary",toJson true),
    ("sourceHeadsUnchanged",toJson true),("sharedSidecarsAbsent",toJson true),
    ("customProviderUnchanged",toJson true),("invalidProjectRejected",toJson true),
    ("modelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress
