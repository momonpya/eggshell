import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "routing service anchor changed"
  return source.replace before after

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let core := root / "routing-scope-core"
  let mut client ← IO.FS.readFile (core / "Eggshell/PublicationClient.lean")
  client ← once client "def SourceReference.reader (reference : SourceReference)"
    ("def sourceRouting (reference : SourceReference) (request : Synapses.Routing.PrivateView.Request)\n" ++
     "    (deadline : Nat) : IO Synapses.Routing.PrivateView.Reply := do\n" ++
     "  let access := reference.access\n" ++
     "  let budget ← liveBudget deadline\n" ++
     "  let response ← Stream.exchange reference.endpoint \"source-route\" (Json.mkObj [\n" ++
     "    (\"database\",toJson access.database),(\"scope\",toJson access.scope),(\"source\",toJson access.source),\n" ++
     "    (\"metadata\",toJson access.metadata),(\"request\",toJson request),(\"budgetMs\",toJson budget)]) budget\n" ++
     "  let result ← IO.ofExcept (Json.parse response >>= fromJson? (α := Synapses.Routing.PrivateView.Reply))\n" ++
     "  unless result.basis == request.basis do throw (IO.userError \"routing reply changed its pinned index\")\n" ++
     "  return result\n\n" ++
     "def SourceReference.reader (reference : SourceReference)")
  client ← once client "records := sourceRecords reference}"
    "records := sourceRecords reference,routing := some (sourceRouting reference)}"
  let mut service ← IO.FS.readFile (core / "Eggshell/PublicationService.lean")
  service ← once service "/-- Registration is local administrator authority."
    ("def sourceRouting (server : Server) (secret : String) (payload : Json) (deadline : Nat) : IO Json := do\n" ++
     "  let request ← IO.ofExcept (payload.getObjVal? \"request\" >>= fromJson? (α := Routing.PrivateView.Request))\n" ++
     "  withSourceReader server secret payload deadline fun reader => do\n" ++
     "    let some routing := reader.routing | throw (IO.userError \"prepared service has no routing reader\")\n" ++
     "    return toJson (← routing request deadline)\n\n" ++
     "/-- Registration is local administrator authority.")
  service ← once service "[\"source-rows\",\"source-records\",\"source-bindings\"].contains kind"
    "[\"source-rows\",\"source-records\",\"source-bindings\",\"source-route\"].contains kind"
  service ← once service "[\"prepare-source\",\"refresh-source\",\"source-rows\",\"source-records\",\"source-bindings\"].contains kind"
    "[\"prepare-source\",\"refresh-source\",\"source-rows\",\"source-records\",\"source-bindings\",\"source-route\"].contains kind"
  service ← once service "      else if kind == \"source-bindings\" then sourceBindings server secret payload deadline"
    "      else if kind == \"source-bindings\" then sourceBindings server secret payload deadline\n      else if kind == \"source-route\" then sourceRouting server secret payload deadline"
  let mut transport ← IO.FS.readFile (core / "Eggshell/SynapticTransport.lean")
  let first := "    let some routing ← Routing.Store.open? shared |"
  let last := "    let usage ← prepared.usage.mapM fun original => do"
  let split := transport.splitOn first
  check (split.length == 2) "routing opening anchor changed"
  let rest := split[1]!.splitOn last
  check (rest.length == 2) "private usage opening anchor changed"
  transport := split[0]! ++
    "    let remote := prepared.canonical.bind (·.routing)\n" ++
    "    let localView ← if remote.isNone then Routing.Store.open? shared else pure none\n" ++
    "    if remote.isNone && localView.isNone then\n" ++
    "      return {initial with complete := false,available := false,failure := some \"routing-unprepared\"}\n" ++
    last ++ rest[1]!
  transport ← once transport "    let walked ← Routing.Store.walk routing usage roots deadline\n    return {initial with"
    ("    let (walked,routingHead) ← match remote with\n" ++
     "      | some remote => do\n" ++
     "        let queries := roots.filterMap fun (key,_) => match key with | .query query => some query | _ => none\n" ++
     "        let capsule ← usage.mapM fun original => Routing.PrivateView.capture original queries deadline\n" ++
     "        let result ← remote {basis := shared.index.head,roots,usage := capsule} deadline\n" ++
     "        pure (result.walk,result.basis)\n" ++
     "      | none => do\n" ++
     "        let some routing := localView | throw (IO.userError \"routing reader disappeared\")\n" ++
     "        pure (← Routing.Store.walk routing usage roots deadline,routing.snapshot.head)\n" ++
     "    return {initial with")
  transport ← once transport "routing := some routing.snapshot.head,usageRouting := usage.map (·.snapshot.head)"
    "routing := some routingHead,usageRouting := usage.map (·.snapshot.head)"
  let mut wire ← IO.FS.readFile (core / "Eggshell/PublicationWire.lean")
  wire ← once wire "  (include_str \"../tools/research/PreparedSourceReader.lean\").toUTF8,"
    "  (include_str \"../tools/research/PreparedSourceReader.lean\").toUTF8,\n  (include_str \"../tools/research/PrivateRoutingView.lean\").toUTF8,"
  for (name,source) in [("PublicationClient",client),("PublicationService",service),
      ("SynapticTransport",transport),("PublicationWire",wire)] do
    IO.FS.writeFile (core / ("Eggshell/" ++ name ++ ".lean")) source
  for name in ["PreparedSourceReader","PrivateRoutingView"] do
    let path := "tools/research/" ++ name ++ ".lean"
    IO.FS.writeFile (core / path) (← IO.FS.readFile (project / path))
  check ((← IO.FS.readFile (core / "Eggshell/Handoff.lean")) ==
    (← IO.FS.readFile (root / "query-cache-baseline-core/Eggshell/Handoff.lean"))) "routing service changed final selection"
  IO.println "Normal prepared routing now uses the scoped source service and a request-local caller overlay"
