module
public import Eggshell.KeyedProtocol
public import Eggshell.SemanticMatcher

@[expose] public section
namespace Eggshell.KeyedSearchClient
open Lean DB Persistence.Store

def command (configured : List String) : Except String (List String) := do
  match configured with
  | executable :: "search-provider" :: arguments =>
    return executable :: "keyed-search-provider" :: arguments
  | executable :: "keyed-search-provider" :: arguments =>
    return executable :: "keyed-search-provider" :: arguments
  | _ => throw "keyed search requires the built-in source-scoped provider"

def nominate (configured : List String) (sources : Array Snapshot) (query : String)
    (receipt : Option String := none) : IO (Option (KeyedProtocol.Checked sources)) := do
  try
    let counts ← sources.mapM (fun source => getNat source.get "candidates")
    if counts.all (· == 0) then
      let coverage : List KeyedProtocol.Coverage := (List.range sources.size).map fun index => {
        source := index, population := 0, routePoints := 0, routeCells := 0, totalCells := 0,
        routeKeys := 0, physicalRows := 0, partialKeys := [], lexicalOwners := 0, nominatedOwners := 0 }
      let empty ← IO.ofExcept (KeyedProtocol.check sources ⟨[],[],coverage⟩)
      Receipt.observe receipt "keyed-nominations" (Json.mkObj [
        ("status",toJson "empty-source-domain"),("sources",toJson sources.size)])
      return some empty
    let command ← IO.ofExcept (command configured)
    SemanticMatcher.withProvider command fun running => SemanticMatcher.withResponseDeadline do
      let request : KeyedProtocol.Request := ⟨query,sources.map KeyedProtocol.Scope.ofSnapshot,4096,8192,receipt⟩
      let bytes := (toJson request).compress
      Receipt.observe receipt "keyed-request" (Json.mkObj [
        ("sources",toJson sources.size),("requestBytes",toJson bytes.utf8ByteSize),
        ("allDocumentMetadataTransferred",toJson false)])
      running.child.stdin.putStrLn bytes
      running.child.stdin.flush
      let json ← IO.ofExcept (Json.parse (← running.child.stdout.getLine))
      if let .ok error := json.getObjValAs? String "error" then throw (IO.userError error)
      let response ← IO.ofExcept (fromJson? json : Except String KeyedProtocol.Response)
      let checked ← IO.ofExcept (KeyedProtocol.check sources response)
      KeyedProtocol.validateRelated sources checked
      Receipt.observe receipt "keyed-nominations" (Json.mkObj [
        ("related",toJson checked.related.length),("ranked",toJson checked.ranked.length),
        ("coverage",toJson checked.coverage),("authority",toJson "advisory-only")])
      return some checked
  catch error =>
    Receipt.observe receipt "keyed-nominations" (Json.mkObj [
      ("status",toJson "unavailable"),("error",toJson error.toString)])
    IO.eprintln s!"eggshell: keyed semantic matcher unavailable: {error}"
    return none

end Eggshell.KeyedSearchClient
