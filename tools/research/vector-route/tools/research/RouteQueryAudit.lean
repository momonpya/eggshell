import Eggshell.VectorRoute
import Eggshell.Warm

open Lean Eggshell

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def exchange (running : SemanticMatcher.Running) (request : Json) : IO (Json × Nat) := do
  let began ← IO.monoMsNow
  running.child.stdin.putStrLn request.compress
  running.child.stdin.flush
  let response ← IO.ofExcept (Json.parse (← running.child.stdout.getLine))
  check (!(response.getObjVal? "error").isOk && !(response.getObjVal? "need_windows").isOk)
    "prepared provider failed or requested original source text"
  return (response,(← IO.monoMsNow)-began)

private def roots (documents : Array Json) (result : Json) : IO (List Nat) := do
  let selected ← IO.ofExcept (result.getObjValAs? (List Nat) "related")
  selected.mapM fun index => do
    let some document := documents[index]? | throw (IO.userError "provider invented document")
    IO.ofExcept (document.getObjValAs? Nat "id")

def main (args : List String) : IO Unit := do
  let [database,matrixRoot,routerRoot,binary,output] := args |
    throw (IO.userError "RouteQueryAudit DB MATRIX-ROOT ROUTER-ROOT REFERENCE-RUNTIME NEW-OUTPUT")
  let output := System.FilePath.mk output
  check (!(← output.pathExists)) "keep earlier query comparison"
  IO.FS.createDirAll output
  let source ← DB.PageMap.pin (.mk database)
  let some domain ← CandidateDomain.openShared? source | throw (IO.userError "prepared source unavailable")
  let some matrix ← VectorMatrix.open? (.mk matrixRoot) MiniLM.model SearchProvider.encoderContract |
    throw (IO.userError "same matrix unavailable")
  let some router ← VectorRoute.open? (.mk routerRoot) MiniLM.model SearchProvider.encoderContract matrix |
    throw (IO.userError "same routing publication unavailable")
  let question := "Find kernel realtime clock observations for monotonic scheduling and elapsed timers, question 1."
  let documents := domain.documents.toArray.map fun document => Json.mkObj [
    ("id",toJson document.owner),("windows",toJson document.windows),("cache",toJson document.cache)]
  let base := Json.mkObj [("query",toJson (SemanticMatcher.item (.text question) question)),
    ("documents",toJson documents),("lexical",toJson ([] : List Nat)),("anchors",toJson ([] : List Nat))]
  IO.FS.writeFile (output / "reference-request.json") base.compress
  SemanticMatcher.withProvider [binary,"search-provider"] fun running => do
    let (reference,referenceMs) ← exchange running base
    IO.FS.writeFile (output / "reference.json") reference.pretty
    let queryOptions : SearchProvider.Options := { cache := (← Paths.dataRoot) / "queries",models := .mk "unused" }
    let packed ← SearchProvider.vectors queryOptions question
    let vectors ← IO.ofExcept packed.getArr?
    check (vectors.size == 1) "fixed routing probe requires one query window"
    let packed ← IO.ofExcept vectors[0]!.getStr?
    let bytes ← IO.ofExcept (VectorMatrix.decodeHex packed)
    let point ← IO.ofExcept (VectorRoute.sketch (Persistence.Store.windowKey question) bytes)
    let began ← IO.monoMsNow
    let selected ← VectorRoute.nominate router point 128
    let routeMs := (← IO.monoMsNow)-began
    let wanted := Std.HashSet.ofList selected.val.keys
    let mut narrowed := #[]
    let mut windows := 0
    for document in domain.documents do
      let picked := document.windows.filter wanted.contains
      if picked.isEmpty then continue
      windows := windows+picked.length
      narrowed := narrowed.push (Json.mkObj [("id",toJson document.owner),
        ("windows",toJson picked),("cache",toJson document.cache)])
    check (!narrowed.isEmpty) "routing returned no source-discovery window"
    let request := base.setObjVal! "documents" (toJson narrowed)
    IO.FS.writeFile (output / "routed-request.json") request.compress
    let (routed,routedMs) ← exchange running request
    IO.FS.writeFile (output / "routed.json") routed.pretty
    let original ← roots documents reference
    let candidate ← roots narrowed routed
    let retained := original.filter candidate.contains
    let missed := original.filter (fun root => !candidate.contains root)
    check (candidate.all (fun root => domain.owners.contains root)) "routed result lacks original owner"
    let result := Json.mkObj [("scope",toJson "one fixed synthetic natural-language query, no lexical/anchor additions; component recall only, no native hook or model-token/quality result"),
      ("source",toJson source.head),("matrix",toJson matrix.snapshot.head),("question",toJson question),
      ("referenceProviderMs",toJson referenceMs),("routingMs",toJson routeMs),("routedProviderMs",toJson routedMs),
      ("referenceDocuments",toJson documents.size),("routedDocuments",toJson narrowed.size),
      ("routedDiscoveryWindows",toJson windows),("nominatedProjectionKeys",toJson selected.val.keys.length),
      ("referenceRelatedRoots",toJson original),("routedRelatedRoots",toJson candidate),
      ("retainedReferenceRoots",toJson retained),("missedReferenceRoots",toJson missed),
      ("queryEmbeddingFromCurrentMiniLM",toJson true),("sourceEmbeddings",toJson (0 : Nat)),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
    IO.FS.writeFile (output / "result.json") result.pretty
    IO.println result.compress
  check ((← DB.PageMap.pin source.directory).head == source.head) "original source changed"
  check ((← DB.PageMap.pin matrix.snapshot.directory).head == matrix.snapshot.head) "original matrix changed"
